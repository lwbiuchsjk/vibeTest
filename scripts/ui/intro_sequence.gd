## 功能：intro 场景序列控制脚本 + 屏幕级 girl_enter 渲染承担者。
## 说明：全屏覆盖池塘涟漪动画 → 玩家点击 → cross-fade 切到 girl_enter → 永久保持显示，
##       由 IntroSequence 13 层 mosaic 长期承担屏幕级 girl_enter 渲染（替代 ScreenMosaic 3 层粗渲染）。
##       LeftStack 内部背景全部隐藏（main_game._ready 中处理），核心区透出 IntroSequence 渲染，
##       LeftOverlay (UI) 在 Root 内渲染层级高于 IntroSequence 不会被遮挡。
##       3 个 reveal 信号 (screen_mosaic / core_girl / ui) 在新设计下无视觉效果，
##       保留作为未来叙事接入扩展点（信号契约稳定）。
##       双层 A/B 架构：任意时刻 A+B 两套 modulate.a 之和 ≈ 1.0，
##       彻底消除单层 cross-fade 的"米色闪烁"问题。
##       A/B 两套各含 13 层 mosaic（对标 LeftStack 实际渲染层数，
##       AccentMarked / Particles 因需特殊数据而不纳入）。
class_name IntroSequence
extends Control

# 开始按钮字体（2026-05-10）：思源宋体 Bold——宋骨厚重 + 仪式感对路；
# 与 main_game 叙事标题同字体，形成"重要时刻"语言一致性。
const FONT_START_BUTTON: Font = preload("res://font/SourceHanSerifCN-Bold.otf")

# ============================================================
# 资产路径常量
# ============================================================

## 静止水面（进入时默认画面 + 涟漪平息后过渡帧）
const STILL_PATH   := "res://assets/art/environments/backgrounds/pond_still.png"
## 涟漪帧 1：小圈涟漪
const RIPPLE_1_PATH := "res://assets/art/environments/backgrounds/pond_ripple_1.png"
## 涟漪帧 2：中圈涟漪
const RIPPLE_2_PATH := "res://assets/art/environments/backgrounds/pond_ripple_2.png"
## 涟漪帧 3：大圈涟漪（最终平息前）
const RIPPLE_3_PATH := "res://assets/art/environments/backgrounds/pond_ripple_3.png"
## 少女形象（点击后由 main_game 加载到核心区）
const GIRL_ENTER_PATH := "res://assets/art/environments/backgrounds/pond_girl_enter.png"
## girl_enter 脸部 mask（LangSAM 生成的二值 mask）：
## 通过 background.gd 的 set_exclude_mask 注入到 IntroCoarse（24px 最大字号层）；
## 该层在 mask 区跳 cell 不画字符，效果是脸部缺大字号"骨架"，其他细字层照常渲染，
## 与"在 mask 内被抑制的层不画任何字符"语义对齐。
const GIRL_ENTER_FACE_MASK_PATH := "res://assets/art/environments/backgrounds/pond_girl_enter_face_mask.png"

# ============================================================
# intro 涟漪场景专用词汇（水墨池塘氛围，内联，不依赖 LOCATION_TEXT_TOKENS）
# ============================================================
const INTRO_TEXT_TOKENS: Array = [
	"涟漪", "水波", "荷叶", "芦苇", "浮光", "碧水",
	"倒影", "鱼跃", "竹影", "天光", "静水", "扁舟",
	"柳影", "残荷", "云影", "风声"
]

# ============================================================
# 信号（后续叙事接入点，供 main_game 连接）
# ============================================================

## 玩家点击瞬间发出（t=0.0s），main_game 调 _render_event_background(girl_enter) 后台喂图给 14 层
signal intro_click_received()
## 点击后 0.4s 发出（IntroSequence 同时启动 cross-fade 切 girl_enter）；main_game handler 当前为空，保留作扩展点
signal intro_reveal_screen_mosaic()
## 点击后 0.8s 发出；main_game handler 仍 Tween LeftStack.modulate.a 0→1（无视觉效果，让未来 LeftOverlay 显示时 alpha 已就绪）
signal intro_reveal_core_girl()
## 点击后 1.2s 发出；main_game handler 当前为空，保留作扩展点（UI 实际由游戏后续逻辑控制）
signal intro_reveal_ui()
## 点击后 2.0s 发出，叙事系统接入点（当前留空）
signal intro_completed()

# ============================================================
# 状态枚举
# ============================================================
enum State {
	RIPPLE_ANIM,  ## 正在播放涟漪循环
	CLICKED,      ## 玩家已点击，正在播放退场时序
	DONE          ## 退场完毕
}

# ============================================================
# 内部状态变量
# ============================================================

## 当前状态机状态
var _state: State = State.RIPPLE_ANIM

## 涟漪循环 Timer（每帧停留 1.2s，still 停留 5~20s 随机）
var _ripple_timer: Timer = null

## 当前涟漪帧索引：-1=still, 0=帧1, 1=帧2, 2=帧3
var _ripple_frame_index: int = -1

## 呼吸式微动 Tween（A 套 IntroCoarse 层）
var _breathe_tween: Tween = null
## 呼吸式微动 Tween（A 套 IntroMedium 层，独立引用，CLICKED 时一并停止）
var _breathe_medium_tween: Tween = null
## 呼吸式微动 Tween（B 套 IntroCoarse 层，与 A 套同步）
var _breathe_tween_b: Tween = null
## 呼吸式微动 Tween（B 套 IntroMedium 层，与 A 套同步）
var _breathe_medium_tween_b: Tween = null
## 帧切换 cross-fade Tween（双层 A/B 并行过渡，CLICKED 时一并停止）
var _crossfade_tween: Tween = null
## 是否首次 still 停留：首次固定 2.0s 让玩家进入场景有稳定初始观察时间；后续 still 才用 5~20s 随机区间
var _is_first_still: bool = true

## 当前活跃层标识：true = A 套显示（modulate.a=1），false = B 套显示
var _active_is_a: bool = true

## 第一次 3 帧涟漪循环（ripple_1→2→3→still）是否已完成，用于触发开始按钮渐显
var _first_ripple_cycle_done: bool = false
## 开始按钮渐显 Tween（一次性，0→1 over 0.8s）
var _button_appear_tween: Tween = null
## 开始按钮 alpha 呼吸 Tween（循环 sin 脉动，黑色字与背景的"深→淡→深"循环）
var _button_breathe_alpha_tween: Tween = null
## 开始按钮淡出 Tween（点击后 0.5s 淡出，淡出完成才启动 girl_enter cross-fade）
var _button_fade_out_tween: Tween = null

## 已加载的涟漪图 Texture2D 缓存（避免每次切帧重复加载）
var _still_tex: Texture2D = null
var _ripple1_tex: Texture2D = null
var _ripple2_tex: Texture2D = null
var _ripple3_tex: Texture2D = null
## 少女入画图 Texture2D 缓存（CLICKED 阶段 cross-fade 切到此图永久显示，接管屏幕级渲染）
var _girl_enter_tex: Texture2D = null

## 当前显示的事件背景图路径（set_event_background 幂等检查用）。
## - 涟漪期：空字符串（涟漪帧切换不跟踪）
## - CLICKED 阶段 cross-fade 到 girl_enter：_on_start_fade_out 设为 GIRL_ENTER_PATH
## - intro_completed 后由 set_event_background 维护
## 设计依据：避免 t=2.0s intro_completed 后 main_game 注入 sys_opening_reflection（background=girl_enter）
##         触发重复 cross-fade（13 层 set_source_image + 双套并行渲染 0.5s）导致明显卡顿。
var _current_displayed_art_path: String = ""

## A/B 套各自持有的 art_path 缓存（议题 §🔵 实施期 2026-05-11）。
## 当 set_event_background 目标已被某套持有时，直接切到该套（避免重复 _draw 破坏 Godot canvas item batch）。
var _last_art_in_a: String = ""
var _last_art_in_b: String = ""

## N 套 LRU 缓存池（议题 §🔵 实施期 2026-05-11，REQ-004）：
## 涟漪期 A/B 套保留原 cross-fade Tween 机制；intro_completed 后 set_event_background 走 LRU 模式。
## SLOT_COUNT=4：A + B + 2 个额外套（_ready 时 duplicate A 套生成）。覆盖 girl_enter + 包内 2-3 图。
## 根因调查 + 静态化方案见 [[代码重构_预启动]] REQ-004。
const SLOT_COUNT: int = 4
## 额外的 mosaic 套容器（C、D），_ready 时由 A 套 duplicate 生成。
var _extra_slots: Array[Control] = []
## 缓存命中表：art_path → slot 容器（intro_completed 后维护）
var _slot_holdings: Dictionary = {}
## LRU 顺序：最旧在头部，最新在末尾
var _slot_lru: Array[Control] = []

## 调试：DONE 状态下每秒 print 一次 A/B 套实时状态（visible + modulate.a + active 标识）。
## 议题 §🔵 卡顿诊断用——直接回答"A/B 是否同时渲染"的疑问。卡顿解决后可整体移除。
var _dbg_state_print_accum: float = 0.0

# ============================================================
# 子节点引用（@onready，路径与 tscn 中节点名一致）
# ============================================================

## A 套容器（初始活跃，modulate.a=1）
@onready var mosaic_layers_a: Control     = $MosaicLayersA
## B 套容器（初始隐藏，modulate.a=0）
@onready var mosaic_layers_b: Control     = $MosaicLayersB

## A 套 13 层 TextMosaicBackground
@onready var intro_bg_a: Control            = $MosaicLayersA/IntroBg
@onready var intro_coarse_a: Control        = $MosaicLayersA/IntroCoarse
@onready var intro_medium_a: Control        = $MosaicLayersA/IntroMedium
@onready var intro_dark_light_a: Control    = $MosaicLayersA/IntroDarkLight
@onready var intro_dark_accent_a: Control   = $MosaicLayersA/IntroDarkAccent
@onready var intro_dark_deep_a: Control     = $MosaicLayersA/IntroDarkDeep
@onready var intro_dark_ink_a: Control      = $MosaicLayersA/IntroDarkInk
## 新增：对标 LeftStack TextMosaicDarkBetween（极暗区下边界，v_max=0.13）
@onready var intro_dark_between_a: Control  = $MosaicLayersA/IntroDarkBetween
## 新增：对标 LeftStack TextMosaicDarkAbyss（最暗区，v_max=0.08）
@onready var intro_dark_abyss_a: Control    = $MosaicLayersA/IntroDarkAbyss
## 新增：对标 LeftStack TextMosaicMidDark（中暗区，v_min=0.4 v_max=0.55，font_size=6）
@onready var intro_mid_dark_a: Control      = $MosaicLayersA/IntroMidDark
## 新增：对标 LeftStack TextMosaicMidLight（中亮区，v_min=0.55 v_max=0.75，font_size=6）
@onready var intro_mid_light_a: Control     = $MosaicLayersA/IntroMidLight
@onready var intro_highlight_a: Control     = $MosaicLayersA/IntroHighlight
## 新增：对标 LeftStack TextMosaicAccent（彩色强调层，use_source_color=true）
@onready var intro_accent_a: Control        = $MosaicLayersA/IntroAccent

## B 套 13 层 TextMosaicBackground（参数与 A 套完全一致；容器整体 modulate.a=0 已隐藏）
@onready var intro_bg_b: Control            = $MosaicLayersB/IntroBg
@onready var intro_coarse_b: Control        = $MosaicLayersB/IntroCoarse
@onready var intro_medium_b: Control        = $MosaicLayersB/IntroMedium
@onready var intro_dark_light_b: Control    = $MosaicLayersB/IntroDarkLight
@onready var intro_dark_accent_b: Control   = $MosaicLayersB/IntroDarkAccent
@onready var intro_dark_deep_b: Control     = $MosaicLayersB/IntroDarkDeep
@onready var intro_dark_ink_b: Control      = $MosaicLayersB/IntroDarkInk
## 新增：对标 LeftStack TextMosaicDarkBetween
@onready var intro_dark_between_b: Control  = $MosaicLayersB/IntroDarkBetween
## 新增：对标 LeftStack TextMosaicDarkAbyss
@onready var intro_dark_abyss_b: Control    = $MosaicLayersB/IntroDarkAbyss
## 新增：对标 LeftStack TextMosaicMidDark
@onready var intro_mid_dark_b: Control      = $MosaicLayersB/IntroMidDark
## 新增：对标 LeftStack TextMosaicMidLight
@onready var intro_mid_light_b: Control     = $MosaicLayersB/IntroMidLight
@onready var intro_highlight_b: Control     = $MosaicLayersB/IntroHighlight
## 新增：对标 LeftStack TextMosaicAccent
@onready var intro_accent_b: Control        = $MosaicLayersB/IntroAccent

## 开始按钮（Label，IntroSequence 直接子节点，渲染在所有 mosaic 层之上）
## mouse_filter=IGNORE 不拦截鼠标事件，玩家点击按钮位置由 IntroSequence._input 全局监听处理
@onready var start_button: Label = $StartButton


# ============================================================
# 初始化
# ============================================================

## 功能：DONE 状态下每秒打印 A/B 套实时状态，议题 §🔵 卡顿诊断用。
## 输出：A vis + α + B vis + α + active_is_a + 当前 art_path —— 直接回答"A/B 是否同时渲染"。
## 卡顿解决后整个 _process + _dbg_state_print_accum 可移除。
func _process(delta: float) -> void:
	if _state != State.DONE:
		return
	_dbg_state_print_accum += delta
	if _dbg_state_print_accum < 1.0:
		return
	_dbg_state_print_accum = 0.0
	print("[IntroSeq state] A vis=%s α=%.2f | B vis=%s α=%.2f | active_is_a=%s | art=%s" % [
		str(mosaic_layers_a.visible), mosaic_layers_a.modulate.a,
		str(mosaic_layers_b.visible), mosaic_layers_b.modulate.a,
		str(_active_is_a), _current_displayed_art_path
	])


## 功能：节点就绪。
## 说明：此处仅做 null 检查；实际动画启动由 main_game 在 _ready 末尾调用 start_pond_animation()。
func _ready() -> void:
	# 确保自身鼠标捕捉开启（默认会继承，但显式设置更安全）
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 预加载所有涟漪纹理到内存（_ready 阶段加载，避免首帧切换卡顿）
	_preload_textures()
	# 脸部 mask 注入推迟到 _on_start_fade_out（即将装载 girl_enter 时），
	# 涟漪期 A/B 套 IntroFaceMask 都不挂 mask——涟漪 cross-fade 切帧时
	# B 套 alpha 0→1 不会带出米色块污染涟漪画面。

	# 开始按钮字体注入（2026-05-10）：思源宋体 Bold 替换全局默认霞鹜文楷，强化"开始游戏"仪式感
	if start_button != null:
		start_button.add_theme_font_override("font", FONT_START_BUTTON)

	# 议题 §🔵 实施期 2026-05-11：duplicate A 套生成 C/D 额外缓存套（SLOT_COUNT=4 - 2 = 2 个新套）。
	# 子节点 script 和 inspector 参数自动继承，与 A 套完全镜像。
	# 新套初始 modulate.a=0（隐藏），visible=true（避免 visible 切换破坏 batch）。
	var letters: Array[String] = ["C", "D"]
	for letter: String in letters:
		var new_slot: Control = mosaic_layers_a.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Control
		new_slot.name = "MosaicLayers" + letter
		new_slot.modulate = Color(1, 1, 1, 0)
		new_slot.visible = true
		add_child(new_slot)
		_extra_slots.append(new_slot)


# ============================================================
# 对外接口
# ============================================================

## 功能：开始池塘涟漪帧循环动画。
## 说明：由 main_game._ready() 在挂载信号后调用。
##       先渲染 still 静止帧让玩家看到初始画面，再启动 Timer 驱动帧切换循环。
##       A 套初始 alpha=1（活跃），B 套初始 alpha=0（非活跃）；
##       两套都设置 still 图，避免首次 cross-fade 时 B 套渲染空白。
func start_pond_animation() -> void:
	if _state != State.RIPPLE_ANIM:
		return
	# 确认初始 alpha 状态（tscn 中 B 套已设 modulate = Color(1,1,1,0)，此处显式确认）
	mosaic_layers_a.modulate.a = 1.0
	mosaic_layers_b.modulate.a = 0.0
	# 两套都设 still 图：B 套虽不可见，首次切帧时会立即成为非活跃层接图，必须预先设好
	_set_layers_image(_get_all_mosaic_layers(), _still_tex)
	# 启动 A/B 两套中间层呼吸微动
	_start_breathe_tween()
	# 启动 Timer：先做 still 停留（首次固定 2.0s），之后进入帧循环
	_schedule_next_ripple_cycle(true)


## 功能：切换事件背景（事件背景路由的外部入口）。
## 参数 art_path：图路径（res://...）；空字符串 = 显示静态米色底（非活跃套 source_image=null）
## 参数 tokens：字符 token 池，13 层共用；空数组 fallback 到 INTRO_TEXT_TOKENS
## 参数 face_mask_path：抑制大字号层（IntroCoarse 24px / IntroMedium 14px）落脸的 mask；空字符串 = 清 mask
## 说明：intro_completed 后由 main_game._render_event_background 调用，统一驱动事件背景切换。
##       内部复用 _crossfade_to_image 的 A/B 双套 cross-fade（0.5s）实现平滑切换。
##       状态机要求 DONE（intro 已完成）；其他状态调用时跳过（intro 期间不接受外部切帧）。
## 设计依据：[[intro_全盘重新设计_预启动]] §🔵 议题决议方案（候选 B）
func set_event_background(art_path: String, tokens: PackedStringArray, face_mask_path: String = "") -> void:
	if _state != State.DONE:
		# intro 期间不接受外部切帧
		return
	# 幂等检查：相同 art_path 直接 return
	if art_path == _current_displayed_art_path:
		return
	_current_displayed_art_path = art_path

	if art_path.is_empty():
		# 空路径：所有 slot α=0
		mosaic_layers_a.modulate.a = 0.0
		mosaic_layers_b.modulate.a = 0.0
		for extra: Control in _extra_slots:
			extra.modulate.a = 0.0
		return

	# N=4 LRU 缓存命中（REQ-004 议题 §🔵 实施期 2026-05-11）：
	# 缓存目标已在某 slot 持有 → 切到该 slot 活跃，永远不重 _draw（避免 Godot canvas item batch 破坏）。
	if _slot_holdings.has(art_path):
		var slot: Control = _slot_holdings[art_path]
		_activate_slot(slot)
		_apply_face_mask_to_slot(slot, face_mask_path)
		# 更新 LRU 顺序（最新使用挪到末尾）
		_slot_lru.erase(slot)
		_slot_lru.append(slot)
		return

	# 缓存未命中 → LRU 选 slot 装载新图（slot 首次 _draw，之后该 slot 永远不重 _draw）
	var tex: Texture2D = ResourceLoader.load(art_path) as Texture2D
	if tex == null:
		push_warning("set_event_background: 资源加载失败或非 Texture2D %s" % art_path)
		return

	var target_slot: Control = _get_lru_slot()
	# 清除该 slot 之前持有的 art_path（被覆盖）
	for old_path: String in _slot_holdings.keys():
		if _slot_holdings[old_path] == target_slot:
			_slot_holdings.erase(old_path)
			break

	# 装载新图到 target_slot
	var target_layers: Array[Control] = _get_slot_layers(target_slot)
	_set_layers_image(target_layers, tex, tokens)
	_apply_face_mask_to_slot(target_slot, face_mask_path)

	# 更新缓存 + 激活
	_slot_holdings[art_path] = target_slot
	_slot_lru.erase(target_slot)
	_slot_lru.append(target_slot)
	_activate_slot(target_slot)


## 让指定 slot 成为唯一活跃（modulate.a=1），其他 slot α=0
func _activate_slot(slot: Control) -> void:
	mosaic_layers_a.modulate.a = 1.0 if slot == mosaic_layers_a else 0.0
	mosaic_layers_b.modulate.a = 1.0 if slot == mosaic_layers_b else 0.0
	for extra: Control in _extra_slots:
		extra.modulate.a = 1.0 if slot == extra else 0.0
	# 维护 _active_is_a 以兼容涟漪期 / CLICKED 期逻辑（虽然 DONE 期不依赖）
	_active_is_a = (slot == mosaic_layers_a)


## 给指定 slot 的 IntroCoarse + IntroMedium 应用 face mask（缓存切换时调用）
func _apply_face_mask_to_slot(slot: Control, mask_path: String) -> void:
	var coarse: Control = slot.get_node_or_null("IntroCoarse")
	var medium: Control = slot.get_node_or_null("IntroMedium")
	if coarse == null or medium == null:
		return
	if mask_path.is_empty() or not FileAccess.file_exists(mask_path):
		coarse.call("clear_exclude_mask")
		medium.call("clear_exclude_mask")
		return
	coarse.call("set_exclude_mask", mask_path)
	medium.call("set_exclude_mask", mask_path)


## 获取 slot 容器内的 13 层 mosaic 节点（按顺序，与 _set_layers_image 期望的顺序对齐）
func _get_slot_layers(slot_container: Control) -> Array[Control]:
	return [
		slot_container.get_node("IntroBg"),
		slot_container.get_node("IntroCoarse"),
		slot_container.get_node("IntroMedium"),
		slot_container.get_node("IntroDarkLight"),
		slot_container.get_node("IntroDarkAccent"),
		slot_container.get_node("IntroDarkDeep"),
		slot_container.get_node("IntroDarkInk"),
		slot_container.get_node("IntroDarkBetween"),
		slot_container.get_node("IntroDarkAbyss"),
		slot_container.get_node("IntroMidDark"),
		slot_container.get_node("IntroMidLight"),
		slot_container.get_node("IntroHighlight"),
		slot_container.get_node("IntroAccent"),
	]


## 返回最久未使用的 slot；优先返回未在 _slot_lru 中的空 slot
func _get_lru_slot() -> Control:
	var all_slots: Array[Control] = [mosaic_layers_a, mosaic_layers_b]
	for extra: Control in _extra_slots:
		all_slots.append(extra)
	# 优先返回空 slot
	for slot: Control in all_slots:
		if slot not in _slot_lru:
			return slot
	# 都满了，返回 LRU 头部
	return _slot_lru[0]


## 议题 §🔵 实施期 2026-05-11：A/B 套缓存切换时，给指定套（is_a=true 即 A 套）的大字号 2 层应用 mask。
func _apply_face_mask_to_specific(is_a: bool, mask_path: String) -> void:
	var coarse_layer: Control
	var medium_layer: Control
	if is_a:
		coarse_layer = intro_coarse_a
		medium_layer = intro_medium_a
	else:
		coarse_layer = intro_coarse_b
		medium_layer = intro_medium_b
	if mask_path.is_empty():
		coarse_layer.call("clear_exclude_mask")
		medium_layer.call("clear_exclude_mask")
		return
	if not FileAccess.file_exists(mask_path):
		coarse_layer.call("clear_exclude_mask")
		medium_layer.call("clear_exclude_mask")
		return
	coarse_layer.call("set_exclude_mask", mask_path)
	medium_layer.call("set_exclude_mask", mask_path)


# ============================================================
# 纹理预加载
# ============================================================

## 功能：预加载 4 张涟漪纹理，避免首次切帧时 ResourceLoader 阻塞导致掉帧。
func _preload_textures() -> void:
	_still_tex      = ResourceLoader.load(STILL_PATH)      as Texture2D
	_ripple1_tex    = ResourceLoader.load(RIPPLE_1_PATH)   as Texture2D
	_ripple2_tex    = ResourceLoader.load(RIPPLE_2_PATH)   as Texture2D
	_ripple3_tex    = ResourceLoader.load(RIPPLE_3_PATH)   as Texture2D
	_girl_enter_tex = ResourceLoader.load(GIRL_ENTER_PATH) as Texture2D


## 功能：给非活跃套（即将随 cross-fade 显现）的 IntroCoarse / IntroMedium 两层应用或清除 face mask。
## 参数 mask_path：mask 资源路径；空字符串 = 调 clear_exclude_mask 恢复全 cell 渲染；非空 = 调 set_exclude_mask。
## 设计依据：[[intro_face_mask_抑制大字号_MVP]] + [[intro_全盘重新设计_预启动]] §🔵
##         背景层 background.gd 的 _draw 主循环每 cell 自查 _exclude_mask_image：alpha > 阈值则跳过该 cell。
##         **仅抑制 IntroCoarse 24px / IntroMedium 14px 两层**：这两层 v_max_threshold 暗部骨架字符落脸违和。
##         保留 IntroBg（ink_levels=32 承担色彩信息）不抑制，避免脸部丢色彩。
##         非空时若 mask 文件不存在则 push_warning 并清 mask（不阻断游戏运行）。
func _apply_face_mask_to_inactive(mask_path: String) -> void:
	var coarse_layer: Control
	var medium_layer: Control
	if _active_is_a:
		coarse_layer = intro_coarse_b
		medium_layer = intro_medium_b
	else:
		coarse_layer = intro_coarse_a
		medium_layer = intro_medium_a
	if mask_path.is_empty():
		coarse_layer.call("clear_exclude_mask")
		medium_layer.call("clear_exclude_mask")
		return
	if not FileAccess.file_exists(mask_path):
		push_warning(
			"intro_face_mask: mask 资源未入库 %s；脸部抑制跳过。"
			% mask_path
			+ "按 [[face_mask生成工作流]] 五步流程从 attachments 挑选并 cp 到 assets。"
		)
		coarse_layer.call("clear_exclude_mask")
		medium_layer.call("clear_exclude_mask")
		return
	coarse_layer.call("set_exclude_mask", mask_path)
	medium_layer.call("set_exclude_mask", mask_path)


# ============================================================
# 涟漪帧循环逻辑
# ============================================================

## 功能：调度下一次帧切换 Timer。
## 参数 is_still_phase：true=本次等待是 still 停留，false=涟漪帧停留（1.2s 固定）。
func _schedule_next_ripple_cycle(is_still_phase: bool) -> void:
	if _state != State.RIPPLE_ANIM:
		return
	var wait_time: float
	if is_still_phase:
		if _is_first_still:
			# 首次 still 停留：固定 2.0s（玩家进入场景的稳定初始观察期）
			wait_time = 2.0
			_is_first_still = false
		else:
			# 后续 still 停留：5~20s 随机大区间，制造长呼吸差异
			wait_time = randf_range(5.0, 20.0)
	else:
		# 涟漪帧停留：固定 1.2s（3 帧 × 1.2s = 3.6s 完整扩散周期）
		wait_time = 1.2

	# 复用或重建 Timer（避免累积悬挂节点）
	if _ripple_timer != null and is_instance_valid(_ripple_timer):
		_ripple_timer.stop()
		_ripple_timer.queue_free()
	_ripple_timer = Timer.new()
	_ripple_timer.one_shot = true
	_ripple_timer.wait_time = wait_time
	add_child(_ripple_timer)
	_ripple_timer.timeout.connect(_on_ripple_timer_timeout)
	_ripple_timer.start()


## 功能：Timer 超时回调，推进涟漪帧序列。
## 说明：帧序列：still(-1) → 帧1(0) → 帧2(1) → 帧3(2) → still(-1) → 循环。
##       切帧用双层 cross-fade 平滑过渡（活跃层淡出 + 非活跃层同时淡入），过渡完成后才调度下一次 Timer。
func _on_ripple_timer_timeout() -> void:
	if _state != State.RIPPLE_ANIM:
		return
	# 推进帧索引（-1: still, 0/1/2: 涟漪帧）
	_ripple_frame_index += 1
	if _ripple_frame_index > 2:
		# 3 帧播完，回到 still
		_ripple_frame_index = -1
	# cross-fade 切帧；完成后由 _on_crossfade_done 调度下一次 Timer
	var tex: Texture2D = _get_texture_for_frame(_ripple_frame_index)
	_crossfade_to_image(tex)


## 功能：双层 cross-fade 切换到新帧（可选同步切 token + face mask），彻底消除米色闪烁。
## 参数 tex：目标图纹理；null = 切到空白米色底（非活跃套各层 source_image=null）
## 参数 tokens：字符 token 池；空数组（默认）= 用 INTRO_TEXT_TOKENS 池塘词池
## 参数 face_mask_path：抑制大字号层的 mask 路径；空字符串（默认）= 清非活跃套大字号 2 层的 mask
## 说明：把新图设到非活跃层 + 同步切 token + 应用 face mask → 并行 Tween：活跃层 1→0 + 非活跃层 0→1（各 0.5s）；
##       任意时刻两层 alpha 之和 ≈ 1.0，米色底层的视觉比例始终守恒，无闪烁。
##       完成后由 _on_crossfade_done 翻转 _active_is_a 标识 + 把新非活跃容器 visible=false（跳 GPU pass）。
##       cross-fade 启动前显式恢复 inactive 容器 visible=true（_on_crossfade_done 上次可能设为 false）。
##       三参数版用于外部事件背景切帧（[[intro_全盘重新设计_预启动]] §🔵）；内部涟漪期调用沿用默认值。
func _crossfade_to_image(tex: Texture2D, tokens: PackedStringArray = PackedStringArray(), face_mask_path: String = "") -> void:
	# 调试 print：标识本次 cross-fade 的目标图 + face mask（议题 §🔵 卡顿诊断用，与 mosaic _draw print 配对）
	var art_label: String = "<empty>" if tex == null else tex.resource_path
	var mask_label: String = "<none>" if face_mask_path.is_empty() else face_mask_path
	print("[IntroSequence] cross-fade -> art=%s | mask=%s | active_was=%s" % [art_label, mask_label, "A" if _active_is_a else "B"])
	# 杀死已有 cross-fade Tween（防御性，正常流程不会重叠）
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	# 把新图 + token 设到非活跃层（非活跃层当前 alpha=0，用户看不见，可安全覆盖）
	_set_layers_image(_get_inactive_layers(), tex, tokens)
	# 同步设非活跃套大字号 2 层 face mask（空字符串 = 清 mask，避免上一图的 mask 残留）
	_apply_face_mask_to_inactive(face_mask_path)
	# 获取容器引用
	var active: Control = _get_active_container()
	var inactive: Control = _get_inactive_container()
	# 议题 §🔵 实施期 2026-05-11 移除 visible 优化后此处无需恢复 visible（始终保持 true）
	# 但保留显式赋值以防 tscn 某层 visible=false 未同步
	inactive.visible = true
	# 调试实验（议题 §🔵 2026-05-11）：DONE 状态下瞬切（无 Tween）验证 Tween 是否破坏 batch 状态
	# 涟漪期保留 Tween（米色闪烁解决依赖 cross-fade）
	if _state == State.DONE:
		active.modulate.a = 0.0
		inactive.modulate.a = 1.0
		_on_crossfade_done()
		return
	# 并行 cross-fade：两层同时动，alpha 守恒（Tween.TRANS_SINE + EASE_IN_OUT 使过渡柔和）
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	_crossfade_tween.tween_property(active,   "modulate:a", 0.0, 0.5)
	_crossfade_tween.tween_property(inactive, "modulate:a", 1.0, 0.5)
	# 并行段完成后，chain() 切回串行以衔接回调；翻转活跃标识并调度下一帧
	_crossfade_tween.chain().tween_callback(_on_crossfade_done)


## 功能：cross-fade 完成回调，翻转活跃层标识并（仅涟漪期）调度下一次帧切换 Timer。
## 副作用：第一次 3 帧涟漪循环完成（ripple_3 → still 的 cross-fade 结束）触发开始按钮渐显。
## 注意：_active_is_a 翻转必须在所有 cross-fade 完成时做（涟漪期 / 点击切 girl_enter / intro_completed
##       后外部 set_event_background）；否则 A/B 标识与实际状态错位，下次切帧时新图装到错误套，
##       cross-fade Tween 改错容器 modulate，两套都接近 alpha=1 同时渲染 → GPU 双倍开销 → 稳态卡顿。
##       涟漪调度 + 按钮渐显仅涟漪期需要，用状态守门挡掉。
## 性能优化：翻转后的新非活跃容器（原活跃容器，cross-fade 完成时 alpha=0）visible=false 跳过 GPU pipeline，
##         稳态下只有 1 套 13 层参与渲染。下次 _crossfade_to_image 启动前恢复 visible=true。
##         药铺等暗部多的图字符密度高 → vertex/fragment 负载重 → 关掉非活跃套显著减半 GPU 开销。
func _on_crossfade_done() -> void:
	# 翻转活跃层：原来的非活跃层已完全显示，成为新的活跃层。
	# 此翻转对所有 cross-fade 完成都必须执行，不受 _state 守门影响。
	_active_is_a = not _active_is_a
	# 取消 visible=false 优化（议题 §🔵 实施期 2026-05-11 发现）：
	# 多次 cross-fade 后 visible 切换让 Godot 内部 canvas item batch 状态被污染
	# （draw_calls 从 ~50 暴涨到 74000+ → FPS 60→5）。
	# 改为 modulate.a=0 隐藏（GPU vertex shader 跑但 fragment 早退）。
	var new_active: Control = _get_active_container()
	var new_inactive: Control = _get_inactive_container()
	new_active.modulate.a = 1.0
	new_inactive.modulate.a = 0.0
	# 不再设 visible=false（避免 batch 状态污染）
	# 后续动作（按钮渐显 + 涟漪调度）仅涟漪期需要；CLICKED / DONE 状态下直接 return
	if _state != State.RIPPLE_ANIM:
		return
	var is_still: bool = (_ripple_frame_index == -1)
	# 第一次回到 still 即"涟漪 1→2→3→still 一轮跑完"，触发按钮渐显（一次性）
	if is_still and not _first_ripple_cycle_done:
		_first_ripple_cycle_done = true
		_trigger_button_appearance()
	_schedule_next_ripple_cycle(is_still)


## 功能：开始按钮渐显（modulate.a 0→1 over 0.8s），结束后启动循环呼吸 A+B。
## 时机：第一次 3 帧涟漪循环完成（约 t≈5.6s = 2s 首 still + 3 × 1.2s 涟漪 + 4 次 cross-fade × 0.5s）。
## 设计依据：[[intro_开始按钮_MVP]]——按钮纯视觉引导，全局点击监听不依赖按钮。
func _trigger_button_appearance() -> void:
	if start_button == null:
		return
	# 杀已有 Tween 防御（理论上不会重叠，但 _first_ripple_cycle_done 守护已防多次触发）
	if _button_appear_tween != null and _button_appear_tween.is_valid():
		_button_appear_tween.kill()
	_button_appear_tween = create_tween()
	_button_appear_tween.set_trans(Tween.TRANS_SINE)
	_button_appear_tween.set_ease(Tween.EASE_OUT)
	_button_appear_tween.tween_property(start_button, "modulate:a", 1.0, 0.8)
	# 渐显结束后才启动循环呼吸，避免起始相位混乱
	_button_appear_tween.tween_callback(_start_button_breathe)


## 功能：启动按钮 alpha 呼吸循环（黑色字与背景的"深→淡→深"循环）。
## 说明：modulate.a 在 [0.4, 1.0] sin 脉动，单次 1.2s × 2 = 周期 2.4s。
##       下限 0.4 让"淡"更明显（实机迭代后从 0.7 降至 0.4）；上限 1.0 = 满黑色对比度。
##       位置呼吸暂未启用（用户反馈不要上下浮动），后续可叠加字符级抖动
##       （详见 [[intro_开始按钮_MVP]] §4.2）。
func _start_button_breathe() -> void:
	if start_button == null:
		return
	if _button_breathe_alpha_tween != null and _button_breathe_alpha_tween.is_valid():
		_button_breathe_alpha_tween.kill()
	_button_breathe_alpha_tween = create_tween()
	_button_breathe_alpha_tween.set_loops()
	_button_breathe_alpha_tween.set_trans(Tween.TRANS_SINE)
	_button_breathe_alpha_tween.set_ease(Tween.EASE_IN_OUT)
	_button_breathe_alpha_tween.tween_property(start_button, "modulate:a", 0.4, 1.2)
	_button_breathe_alpha_tween.tween_property(start_button, "modulate:a", 1.0, 1.2)


## 功能：根据帧索引返回对应 Texture2D。
## 参数 frame_index：-1=still, 0=帧1, 1=帧2, 2=帧3
func _get_texture_for_frame(frame_index: int) -> Texture2D:
	match frame_index:
		0:
			return _ripple1_tex
		1:
			return _ripple2_tex
		2:
			return _ripple3_tex
		_:
			return _still_tex


## 功能：将同一 Texture2D 设置到指定层数组并触发重绘。
## 参数 layers：目标层节点数组（A 套 13 层、B 套 13 层或全 26 层）。
## 参数 tex：要渲染的源图纹理。
## 参数 tokens：字符 token 池；空数组（默认）则用 INTRO_TEXT_TOKENS 池塘词池（intro 启动期默认）。
## 说明：set_source_image 内部已调用 queue_redraw，此处不重复调用。
##       外部事件背景切帧（[[intro_全盘重新设计_预启动]] §🔵）通过 set_event_background 公共 API
##       传入自定义 tokens（如药铺词池）；intro 启动期内部调用不传 tokens，沿用 INTRO_TEXT_TOKENS。
func _set_layers_image(layers: Array[Control], tex: Texture2D, tokens: PackedStringArray = PackedStringArray()) -> void:
	var effective_tokens: PackedStringArray = tokens
	if effective_tokens.is_empty():
		effective_tokens = PackedStringArray(INTRO_TEXT_TOKENS)
	# 逐层设置源图和 token，确保各层渲染同一帧画面
	for layer: Control in layers:
		layer.call("set_source_image", tex)
		layer.call("set_text_tokens", effective_tokens)


# ============================================================
# 层数组辅助方法（A/B 套导航）
# ============================================================

## 功能：返回当前活跃套（可见套）的 13 个 mosaic 子节点数组。
## 说明：新增 IntroDarkBetween / IntroDarkAbyss / IntroMidDark / IntroMidLight / IntroAccent，
##       与 LeftStack 实际渲染层数对齐，确保 intro 全屏和核心区 cover 字符密度一致。
func _get_active_layers() -> Array[Control]:
	if _active_is_a:
		return [
			intro_bg_a, intro_coarse_a, intro_medium_a,
			intro_dark_light_a, intro_dark_accent_a,
			intro_dark_deep_a, intro_dark_ink_a,
			intro_dark_between_a, intro_dark_abyss_a,
			intro_mid_dark_a, intro_mid_light_a,
			intro_highlight_a, intro_accent_a,
		]
	else:
		return [
			intro_bg_b, intro_coarse_b, intro_medium_b,
			intro_dark_light_b, intro_dark_accent_b,
			intro_dark_deep_b, intro_dark_ink_b,
			intro_dark_between_b, intro_dark_abyss_b,
			intro_mid_dark_b, intro_mid_light_b,
			intro_highlight_b, intro_accent_b,
		]


## 功能：返回当前非活跃套（隐藏套）的 13 个 mosaic 子节点数组。
## 说明：非活跃套容器 modulate.a=0，子节点不可见；cross-fade 前在此套预设新帧内容。
func _get_inactive_layers() -> Array[Control]:
	if _active_is_a:
		return [
			intro_bg_b, intro_coarse_b, intro_medium_b,
			intro_dark_light_b, intro_dark_accent_b,
			intro_dark_deep_b, intro_dark_ink_b,
			intro_dark_between_b, intro_dark_abyss_b,
			intro_mid_dark_b, intro_mid_light_b,
			intro_highlight_b, intro_accent_b,
		]
	else:
		return [
			intro_bg_a, intro_coarse_a, intro_medium_a,
			intro_dark_light_a, intro_dark_accent_a,
			intro_dark_deep_a, intro_dark_ink_a,
			intro_dark_between_a, intro_dark_abyss_a,
			intro_mid_dark_a, intro_mid_light_a,
			intro_highlight_a, intro_accent_a,
		]


## 功能：返回当前活跃套容器（MosaicLayersA 或 MosaicLayersB）。
func _get_active_container() -> Control:
	if _active_is_a:
		return mosaic_layers_a
	else:
		return mosaic_layers_b


## 功能：返回当前非活跃套容器。
func _get_inactive_container() -> Control:
	if _active_is_a:
		return mosaic_layers_b
	else:
		return mosaic_layers_a


## 功能：返回 A 套和 B 套全部 26 层节点数组（用于同时初始化两套内容）。
## 说明：A + B 各 13 层，共 26 层；start_pond_animation 调用此方法一次性给全部层设置 still 图，
##       确保首次 cross-fade 时 B 套不渲染空白。
func _get_all_mosaic_layers() -> Array[Control]:
	return [
		intro_bg_a, intro_coarse_a, intro_medium_a,
		intro_dark_light_a, intro_dark_accent_a,
		intro_dark_deep_a, intro_dark_ink_a,
		intro_dark_between_a, intro_dark_abyss_a,
		intro_mid_dark_a, intro_mid_light_a,
		intro_highlight_a, intro_accent_a,
		intro_bg_b, intro_coarse_b, intro_medium_b,
		intro_dark_light_b, intro_dark_accent_b,
		intro_dark_deep_b, intro_dark_ink_b,
		intro_dark_between_b, intro_dark_abyss_b,
		intro_mid_dark_b, intro_mid_light_b,
		intro_highlight_b, intro_accent_b,
	]


# ============================================================
# 呼吸式微动（A/B 两套各自的 IntroCoarse / IntroMedium）
# ============================================================

## 功能：启动 A/B 两套的 IntroCoarse / IntroMedium 呼吸式微动 Tween（共 4 个）。
## 说明：modulate.a 在 ±5% 范围内循环，缓解纯定格切帧的视觉断裂感。
##       A/B 两套同步（相同目标值和时长），确保 cross-fade 过渡期间呼吸节奏一致。
##       进入 CLICKED 后会立即停止全部 4 个 Tween。
func _start_breathe_tween() -> void:
	# 清除已有 Tween（防止重复调用）
	if _breathe_tween != null and _breathe_tween.is_valid():
		_breathe_tween.kill()
	if _breathe_medium_tween != null and _breathe_medium_tween.is_valid():
		_breathe_medium_tween.kill()
	if _breathe_tween_b != null and _breathe_tween_b.is_valid():
		_breathe_tween_b.kill()
	if _breathe_medium_tween_b != null and _breathe_medium_tween_b.is_valid():
		_breathe_medium_tween_b.kill()

	# A 套 IntroCoarse：α 在 [0.50, 0.60] 之间（对标 tscn modulate.a 0.55 ±5%）
	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.set_trans(Tween.TRANS_SINE)
	_breathe_tween.set_ease(Tween.EASE_IN_OUT)
	_breathe_tween.tween_property(intro_coarse_a, "modulate:a", 0.60, 1.5)
	_breathe_tween.tween_property(intro_coarse_a, "modulate:a", 0.50, 1.5)

	# A 套 IntroMedium：α 在 [0.55, 0.65] 之间（对标 tscn modulate.a 0.60 ±5%），周期略不同增加自然感
	_breathe_medium_tween = create_tween()
	_breathe_medium_tween.set_loops()
	_breathe_medium_tween.set_trans(Tween.TRANS_SINE)
	_breathe_medium_tween.set_ease(Tween.EASE_IN_OUT)
	_breathe_medium_tween.tween_property(intro_medium_a, "modulate:a", 0.65, 1.8)
	_breathe_medium_tween.tween_property(intro_medium_a, "modulate:a", 0.55, 1.8)

	# B 套 IntroCoarse：与 A 套同步（相同目标值和时长）
	_breathe_tween_b = create_tween()
	_breathe_tween_b.set_loops()
	_breathe_tween_b.set_trans(Tween.TRANS_SINE)
	_breathe_tween_b.set_ease(Tween.EASE_IN_OUT)
	_breathe_tween_b.tween_property(intro_coarse_b, "modulate:a", 0.60, 1.5)
	_breathe_tween_b.tween_property(intro_coarse_b, "modulate:a", 0.50, 1.5)

	# B 套 IntroMedium：与 A 套同步
	_breathe_medium_tween_b = create_tween()
	_breathe_medium_tween_b.set_loops()
	_breathe_medium_tween_b.set_trans(Tween.TRANS_SINE)
	_breathe_medium_tween_b.set_ease(Tween.EASE_IN_OUT)
	_breathe_medium_tween_b.tween_property(intro_medium_b, "modulate:a", 0.65, 1.8)
	_breathe_medium_tween_b.tween_property(intro_medium_b, "modulate:a", 0.55, 1.8)


# ============================================================
# 点击输入处理
# ============================================================

## 功能：捕获鼠标点击触发 CLICKED 阶段。
## 说明：用 _input（节点级原始事件）而非 _gui_input，绕过 GUI 事件分发系统：
##       Root (MarginContainer) 默认 mouse_filter=STOP 在渲染层位于 IntroSequence 之上，
##       会先吞掉 GUI 鼠标事件，导致 _gui_input 收不到点击。_input 不依赖 mouse_filter。
##       CLICKED 和 DONE 状态忽略输入。
func _input(event: InputEvent) -> void:
	if _state != State.RIPPLE_ANIM:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_enter_clicked_phase()
			get_viewport().set_input_as_handled()


# ============================================================
# CLICKED 阶段时序
# ============================================================

## 功能：进入 CLICKED 阶段，停止涟漪循环，按时序发射信号并驱动自身淡出。
func _enter_clicked_phase() -> void:
	_state = State.CLICKED

	# 停止涟漪 Timer
	if _ripple_timer != null and is_instance_valid(_ripple_timer):
		_ripple_timer.stop()
		_ripple_timer.queue_free()
		_ripple_timer = null

	# 停止 A/B 两套全部 4 个呼吸 Tween（避免 alpha 在淡出阶段被微动干扰）
	if _breathe_tween != null and _breathe_tween.is_valid():
		_breathe_tween.kill()
	if _breathe_medium_tween != null and _breathe_medium_tween.is_valid():
		_breathe_medium_tween.kill()
	if _breathe_tween_b != null and _breathe_tween_b.is_valid():
		_breathe_tween_b.kill()
	if _breathe_medium_tween_b != null and _breathe_medium_tween_b.is_valid():
		_breathe_medium_tween_b.kill()

	# 停止 cross-fade Tween（防止其改容器 modulate.a 与下面淡出冲突）
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	# 停止按钮渐显 / 呼吸 Tween，启动 0.5s 淡出（用户反馈：点击后按钮不要直接消失，要淡出过渡）
	# 淡出与 cross-fade 时序：按钮 0~0.5s 淡出，cross-fade 在 t=0.5s 启动（见下方 sequence Tween）
	if _button_appear_tween != null and _button_appear_tween.is_valid():
		_button_appear_tween.kill()
	if _button_breathe_alpha_tween != null and _button_breathe_alpha_tween.is_valid():
		_button_breathe_alpha_tween.kill()
	if start_button != null:
		if _button_fade_out_tween != null and _button_fade_out_tween.is_valid():
			_button_fade_out_tween.kill()
		_button_fade_out_tween = create_tween()
		_button_fade_out_tween.set_trans(Tween.TRANS_SINE)
		_button_fade_out_tween.set_ease(Tween.EASE_IN)
		_button_fade_out_tween.tween_property(start_button, "modulate:a", 0.0, 0.5)
		_button_fade_out_tween.tween_callback(_on_button_fade_out_done)

	# 重置中间层 alpha 到静态值，防止 Tween kill 后 alpha 锁定在意外值
	# 注意：A/B 两套均重置，无论当前哪套活跃
	intro_coarse_a.modulate.a = 0.55
	intro_medium_a.modulate.a = 0.60
	intro_coarse_b.modulate.a = 0.55
	intro_medium_b.modulate.a = 0.60

	# t=0.0s：发射 click_received，main_game 立即后台加载少女图（利用 0.4s 缓冲）
	intro_click_received.emit()

	# 启动时序 Tween（所有时间节点从同一个 Tween 调度，保证帧级精度）
	var seq: Tween = create_tween()
	seq.set_trans(Tween.TRANS_LINEAR)

	# t=0.5s：按钮淡出完成后启动 cross-fade 涟漪当前帧 → girl_enter
	# （原本 0.4s，因加按钮淡出 0.5s 而推迟 0.1s——girl_enter 入场等按钮先淡掉）
	seq.tween_callback(Callable(self, "_on_start_fade_out")).set_delay(0.5)

	# t=0.5s：发射 reveal_screen_mosaic（无视觉效果，扩展点）
	seq.tween_callback(Callable(self, "_emit_reveal_screen_mosaic")).set_delay(0.0)

	# t=0.8s：发射 reveal_core_girl（无视觉效果，扩展点；距上一节点 0.4s）
	seq.tween_callback(Callable(self, "_emit_reveal_core_girl")).set_delay(0.4)

	# t=1.2s：发射 reveal_ui（无视觉效果，扩展点；距上一节点 0.4s）
	seq.tween_callback(Callable(self, "_emit_reveal_ui")).set_delay(0.4)

	# t=2.0s：发射 completed（IntroSequence 保持显示作为屏幕渲染；距上一节点 0.8s）
	seq.tween_callback(Callable(self, "_emit_completed")).set_delay(0.8)


## 功能：按钮淡出 Tween 完成回调，释放节点 visible（alpha 已为 0，visible=false 节省渲染）。
func _on_button_fade_out_done() -> void:
	if start_button != null:
		start_button.visible = false


## 功能：t=0.5s 时触发，cross-fade 涟漪当前帧切到 girl_enter，IntroSequence 永久保持显示。
## 说明：原设计是 IntroSequence 整体淡出让 ScreenMosaic 浮现接管屏幕渲染。
##       现改为 IntroSequence 不淡出，用 13 层 mosaic 永久承担屏幕级渲染（参 [[intro_全盘重新设计_预启动]] §🔵）。
##       intro_completed 后由 main_game 通过 set_event_background 公共 API 喂入后续事件背景。
##       函数名 _on_start_fade_out 保留以避免改动 Callable；实际行为是切图 + 同步注入 face mask。
func _on_start_fade_out() -> void:
	# 记录当前显示图路径，供 intro_completed 后外部 set_event_background 幂等检查使用
	_current_displayed_art_path = GIRL_ENTER_PATH
	# cross-fade 切到 girl_enter：保留 INTRO_TEXT_TOKENS 池塘词池 + 注入 girl_enter face mask
	_crossfade_to_image(_girl_enter_tex, PackedStringArray(INTRO_TEXT_TOKENS), GIRL_ENTER_FACE_MASK_PATH)


## 功能：t=0.4s 时发射 reveal_screen_mosaic 信号。
func _emit_reveal_screen_mosaic() -> void:
	intro_reveal_screen_mosaic.emit()


## 功能：t=0.8s 时发射 reveal_core_girl 信号。
func _emit_reveal_core_girl() -> void:
	intro_reveal_core_girl.emit()


## 功能：t=1.2s 时发射 reveal_ui 信号。
func _emit_reveal_ui() -> void:
	intro_reveal_ui.emit()


## 功能：t=2.0s 时发射 completed 信号；IntroSequence 保持显示作为屏幕级 girl_enter 渲染。
func _emit_completed() -> void:
	_state = State.DONE
	# 议题 §🔵 实施期 2026-05-11（REQ-004）：DONE 期初始化 N=4 LRU 池。
	# CLICKED 期 _on_start_fade_out 已把 girl_enter 装到 cross-fade 翻转后的 active 套，
	# 登记到缓存池让后续 set_event_background(girl_enter) 命中缓存（不重 _draw）。
	# 涟漪期 inactive 套持有的图（最后一帧 ripple_*）在 DONE 期不再用，作为空 slot 由 LRU 策略覆盖。
	var girl_enter_slot: Control = mosaic_layers_a if _active_is_a else mosaic_layers_b
	_slot_holdings[GIRL_ENTER_PATH] = girl_enter_slot
	_slot_lru.append(girl_enter_slot)
	intro_completed.emit()
	# 不再隐藏自身：IntroSequence 13 层 mosaic 接管屏幕级 girl_enter 渲染，永久保持。
	# LeftOverlay (UI) 在 Root 内，渲染顺序在 IntroSequence 之上，不会被遮挡。
