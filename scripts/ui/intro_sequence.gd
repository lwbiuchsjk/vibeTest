## 功能：intro 场景序列控制脚本 + 屏幕级渲染调度（hybrid 模式）。
##
## 说明：
##   - **Mosaic 模式**：pond_* / pond_girl_enter 用 13 层 runtime mosaic 渲染（A/B 套 cross-fade）。
##     涟漪期 + intro_completed 后承担 sys_reflection 系列自省事件背景。
##   - **Plain 模式**：其他事件背景图（药铺 / 家 / 练场等）用 TextureRect 直接显示源 PNG。
##     无 mosaic 渲染，每帧 1 draw_call，FPS 稳定 60。
##   - **mode 切换**：两轨道（mosaic A/B / event A/B）相互 cross-fade alpha 0↔1 完成视觉过渡。
##
## 设计依据：
##   - [[intro_全盘重新设计_预启动]] §🔵 议题决议方案（候选 B）
##   - [[intro_mosaic_性能排查_2026-05-11]] 实测推翻假设 14 + 用户决议：
##       涟漪 + girl_enter mosaic 稳态 FPS 60 ✓；事件背景 mosaic 化触发 50k draw_calls 卡帧 ✗
##       hybrid 方案：自省事件保留 mosaic 诗意，现实事件用清晰原图
##
## 历史架构（已淘汰，留作回看）：
##   - N=4 LRU 池 + duplicate(A) 生成 C/D 套：根因诊断错误（perf doc 假设 14）+ 实施有 bug；移除
##   - REQ-004 静态化方案 C.2（编辑器预渲染 mosaic PNG）：保留工具作技术储备，
##     运行时不再使用 mosaic_static/ 下产物
class_name IntroSequence
extends Control

# 开始按钮字体（2026-05-10）：思源宋体 Bold——宋骨厚重 + 仪式感对路
const FONT_START_BUTTON: Font = preload("res://font/SourceHanSerifCN-Bold.otf")

# ============================================================
# 资产路径常量
# ============================================================

const STILL_PATH      := "res://assets/art/environments/backgrounds/pond_still.png"
const RIPPLE_1_PATH   := "res://assets/art/environments/backgrounds/pond_ripple_1.png"
const RIPPLE_2_PATH   := "res://assets/art/environments/backgrounds/pond_ripple_2.png"
const RIPPLE_3_PATH   := "res://assets/art/environments/backgrounds/pond_ripple_3.png"
const GIRL_ENTER_PATH := "res://assets/art/environments/backgrounds/pond_girl_enter.png"
## girl_enter 脸部 mask（runtime 注入到 mosaic IntroCoarse/IntroMedium 抑制大字号字符落脸）
const GIRL_ENTER_FACE_MASK_PATH := "res://assets/art/environments/backgrounds/pond_girl_enter_face_mask.png"

# ============================================================
# Cross-fade 时长（事件切换呼吸感 MVP）
# ============================================================
## EventBg A/B 套与 mosaic↔plain mode 切换的 cross-fade 时长。
## 与 mosaic_crossfade（0.5s）统一节奏。
const EVENT_CROSSFADE_SEC: float = 0.5

## 同图跨事件背景脉动（同地点不同填充事件呼吸感）。
## 用 modulate 颜色变暗（不动 α）：图像短暂变暗复明，类似"翻页时光影掠过"。
## α 始终为 1 → 米色底完全被图遮住 → 不会漏出底色造成闪屏。
## PULSE_DIM_FACTOR 是变暗最深处的 RGB 系数（0.7 = 70% 亮度），越低越显著。
const PULSE_DIM_FACTOR: float = 0.2
const PULSE_DURATION: float = 0.8


# ============================================================
# intro 涟漪场景专用词汇（13 层 mosaic 用）
# ============================================================
const INTRO_TEXT_TOKENS: Array = [
	"涟漪", "水波", "荷叶", "芦苇", "浮光", "碧水",
	"倒影", "鱼跃", "竹影", "天光", "静水", "扁舟",
	"柳影", "残荷", "云影", "风声"
]

# ============================================================
# 信号（叙事接入点，供 main_game 连接）
# ============================================================
signal intro_click_received()
signal intro_reveal_screen_mosaic()
signal intro_reveal_core_girl()
signal intro_reveal_ui()
signal intro_completed()

# ============================================================
# 状态枚举
# ============================================================
enum State {
	RIPPLE_ANIM,
	CLICKED,
	DONE
}

# 渲染 mode：mosaic（13 层 runtime 渲染）vs plain（TextureRect 直接显示源 PNG）
enum Mode {
	MOSAIC,
	PLAIN,
}

# ============================================================
# 内部状态变量
# ============================================================

var _state: State = State.RIPPLE_ANIM
var _mode: Mode = Mode.MOSAIC  # intro 期默认 mosaic 模式

var _ripple_timer: Timer = null
var _ripple_frame_index: int = -1  # -1=still, 0/1/2=涟漪帧

## 呼吸 Tween（A/B 套 IntroCoarse / IntroMedium 各 1 个，共 4 个）
var _breathe_tween: Tween = null
var _breathe_medium_tween: Tween = null
var _breathe_tween_b: Tween = null
var _breathe_medium_tween_b: Tween = null
## Mosaic A/B cross-fade Tween
var _mosaic_crossfade_tween: Tween = null
## Event A/B cross-fade Tween
var _event_crossfade_tween: Tween = null
## Mode 切换（mosaic↔plain）cross-fade Tween
var _mode_crossfade_tween: Tween = null
## 是否首次 still 停留
var _is_first_still: bool = true

## Mosaic 活跃 slot 标识（true = A 套显示）
var _mosaic_active_is_a: bool = true
## Event 活跃 slot 标识（true = EventBgA 显示）
var _event_active_is_a: bool = true

var _first_ripple_cycle_done: bool = false
var _button_appear_tween: Tween = null
var _button_breathe_alpha_tween: Tween = null
var _button_fade_out_tween: Tween = null

## 已加载的 mosaic 源图 Texture2D 缓存
var _still_tex: Texture2D = null
var _ripple1_tex: Texture2D = null
var _ripple2_tex: Texture2D = null
var _ripple3_tex: Texture2D = null
var _girl_enter_tex: Texture2D = null

## 当前显示的事件背景图路径（set_event_background 幂等检查用）
var _current_displayed_art_path: String = ""

# ============================================================
# 子节点引用
# ============================================================

@onready var mosaic_layers_a: Control     = $MosaicLayersA
@onready var mosaic_layers_b: Control     = $MosaicLayersB

## A 套 13 层 mosaic
@onready var intro_bg_a: Control            = $MosaicLayersA/IntroBg
@onready var intro_coarse_a: Control        = $MosaicLayersA/IntroCoarse
@onready var intro_medium_a: Control        = $MosaicLayersA/IntroMedium
@onready var intro_dark_light_a: Control    = $MosaicLayersA/IntroDarkLight
@onready var intro_dark_accent_a: Control   = $MosaicLayersA/IntroDarkAccent
@onready var intro_dark_deep_a: Control     = $MosaicLayersA/IntroDarkDeep
@onready var intro_dark_ink_a: Control      = $MosaicLayersA/IntroDarkInk
@onready var intro_dark_between_a: Control  = $MosaicLayersA/IntroDarkBetween
@onready var intro_dark_abyss_a: Control    = $MosaicLayersA/IntroDarkAbyss
@onready var intro_mid_dark_a: Control      = $MosaicLayersA/IntroMidDark
@onready var intro_mid_light_a: Control     = $MosaicLayersA/IntroMidLight
@onready var intro_highlight_a: Control     = $MosaicLayersA/IntroHighlight
@onready var intro_accent_a: Control        = $MosaicLayersA/IntroAccent

## B 套 13 层 mosaic
@onready var intro_bg_b: Control            = $MosaicLayersB/IntroBg
@onready var intro_coarse_b: Control        = $MosaicLayersB/IntroCoarse
@onready var intro_medium_b: Control        = $MosaicLayersB/IntroMedium
@onready var intro_dark_light_b: Control    = $MosaicLayersB/IntroDarkLight
@onready var intro_dark_accent_b: Control   = $MosaicLayersB/IntroDarkAccent
@onready var intro_dark_deep_b: Control     = $MosaicLayersB/IntroDarkDeep
@onready var intro_dark_ink_b: Control      = $MosaicLayersB/IntroDarkInk
@onready var intro_dark_between_b: Control  = $MosaicLayersB/IntroDarkBetween
@onready var intro_dark_abyss_b: Control    = $MosaicLayersB/IntroDarkAbyss
@onready var intro_mid_dark_b: Control      = $MosaicLayersB/IntroMidDark
@onready var intro_mid_light_b: Control     = $MosaicLayersB/IntroMidLight
@onready var intro_highlight_b: Control     = $MosaicLayersB/IntroHighlight
@onready var intro_accent_b: Control        = $MosaicLayersB/IntroAccent

## 事件背景 plain TextureRect（hybrid 模式新增）
@onready var event_bg_a: TextureRect = $EventBgA
@onready var event_bg_b: TextureRect = $EventBgB

## 开始按钮
@onready var start_button: Label = $StartButton


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_preload_textures()
	if start_button != null:
		start_button.add_theme_font_override("font", FONT_START_BUTTON)


# ============================================================
# 对外接口
# ============================================================

## 功能：开始池塘涟漪帧循环动画。
## 说明：A 套初始 α=1（活跃，still 帧），B 套 α=0（非活跃，预设 still 帧避免首次 cross-fade 空白）。
func start_pond_animation() -> void:
	if _state != State.RIPPLE_ANIM:
		return
	mosaic_layers_a.modulate.a = 1.0
	mosaic_layers_b.modulate.a = 0.0
	event_bg_a.modulate.a = 0.0
	event_bg_b.modulate.a = 0.0
	# A + B 两套都设 still 图（首次 cross-fade B 接图避免空白）
	_set_layers_image(_get_all_mosaic_layers(), _still_tex)
	# 启动呼吸 Tween
	_start_breathe_tween()
	# 启动 Timer：首次 still 停留 2.0s，之后帧循环
	_schedule_next_ripple_cycle(true)


## 功能：切换事件背景（事件背景路由的外部入口）。
## 参数 art_path：源图路径（res://...）；空字符串 = 隐藏所有（米色底）
## 参数 tokens：mosaic mode 用作字符 token 池；plain mode 不用
## 参数 face_mask_path：mosaic mode 用作 face mask；plain mode 不用
##
## 派发规则：
##   - art_path 以 "pond_" 开头（pond_still / pond_ripple_* / pond_girl_enter）→ Mosaic 模式
##   - 其他 → Plain 模式（TextureRect 直接显示源 PNG）
##
## 设计依据：[[intro_mosaic_性能排查_2026-05-11]] hybrid 决议 2026-05-12
func set_event_background(art_path: String, tokens: PackedStringArray = PackedStringArray(), face_mask_path: String = "") -> void:
	if _state != State.DONE:
		return
	if art_path == _current_displayed_art_path:
		return
	_current_displayed_art_path = art_path

	if art_path.is_empty():
		mosaic_layers_a.modulate.a = 0.0
		mosaic_layers_b.modulate.a = 0.0
		event_bg_a.modulate.a = 0.0
		event_bg_b.modulate.a = 0.0
		return

	var target_mode: Mode = Mode.MOSAIC if _is_mosaic_art(art_path) else Mode.PLAIN
	print("[IntroSequence] set_event_background -> art=%s | mode=%s | prev_mode=%s" % [
		art_path, "MOSAIC" if target_mode == Mode.MOSAIC else "PLAIN",
		"MOSAIC" if _mode == Mode.MOSAIC else "PLAIN"
	])

	if target_mode == Mode.MOSAIC:
		_render_mosaic_mode(art_path, tokens, face_mask_path)
	else:
		_render_plain_mode(art_path)

	_mode = target_mode


## 功能：判定 art_path 是否走 mosaic 模式。
## 规则：pond_still / pond_ripple_* / pond_girl_enter 走 mosaic；其他源图走 plain。
func _is_mosaic_art(art_path: String) -> bool:
	var stem: String = art_path.get_file().get_basename()
	return stem.begins_with("pond_")


# ============================================================
# Mosaic 模式：13 层 runtime 渲染 + A/B cross-fade
# ============================================================

## 功能：mosaic 模式渲染目标 art_path。
## 说明：
##   - 如果之前是 PLAIN 模式 → 先 mode 切换：event α→0, mosaic α→1
##   - 然后 mosaic 内部 A/B cross-fade 切到新 art_path
##   - 若 mosaic 当前已是该 art_path，无需 mosaic cross-fade，仅 mode 切换
func _render_mosaic_mode(art_path: String, tokens: PackedStringArray, face_mask_path: String) -> void:
	# Plain → Mosaic mode 切换
	if _mode == Mode.PLAIN:
		# 先把 mosaic 设到目标图（非活跃套），切 mode 时活跃套是当前的
		var tex: Texture2D = _load_pond_texture(art_path)
		if tex == null:
			return
		var effective_tokens: PackedStringArray = tokens
		if effective_tokens.is_empty():
			effective_tokens = PackedStringArray(INTRO_TEXT_TOKENS)
		# 把目标图装到活跃 mosaic 套（用户看不到，因为 mosaic α=0；安全覆盖）
		var active_layers: Array[Control] = _get_active_mosaic_layers()
		_set_layers_image(active_layers, tex, effective_tokens)
		_apply_face_mask_to_active_mosaic(face_mask_path)
		# Mode 切换 Tween：active event → 0, active mosaic → 1
		_mode_crossfade(Mode.MOSAIC)
		return

	# Mosaic → Mosaic（同 mode 内部切图）：A/B cross-fade
	var tex2: Texture2D = _load_pond_texture(art_path)
	if tex2 == null:
		return
	var effective_tokens2: PackedStringArray = tokens
	if effective_tokens2.is_empty():
		effective_tokens2 = PackedStringArray(INTRO_TEXT_TOKENS)
	_crossfade_mosaic_to_image(tex2, effective_tokens2, face_mask_path)


## 功能：Mosaic A/B cross-fade 到新 texture。0.5s 守恒 alpha 过渡。
func _crossfade_mosaic_to_image(tex: Texture2D, tokens: PackedStringArray, face_mask_path: String) -> void:
	if _mosaic_crossfade_tween != null and _mosaic_crossfade_tween.is_valid():
		_mosaic_crossfade_tween.kill()
	# 装新图到非活跃 mosaic 套
	_set_layers_image(_get_inactive_mosaic_layers(), tex, tokens)
	_apply_face_mask_to_inactive_mosaic(face_mask_path)
	var active: Control = mosaic_layers_a if _mosaic_active_is_a else mosaic_layers_b
	var inactive: Control = mosaic_layers_b if _mosaic_active_is_a else mosaic_layers_a
	# DONE 状态瞬切（避免 mosaic 过渡阻塞事件流）；intro 期保留 Tween（米色闪烁解决）
	if _state == State.DONE:
		active.modulate.a = 0.0
		inactive.modulate.a = 1.0
		_on_mosaic_crossfade_done()
		return
	_mosaic_crossfade_tween = create_tween()
	_mosaic_crossfade_tween.set_parallel(true)
	_mosaic_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_mosaic_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	_mosaic_crossfade_tween.tween_property(active,   "modulate:a", 0.0, 0.5)
	_mosaic_crossfade_tween.tween_property(inactive, "modulate:a", 1.0, 0.5)
	_mosaic_crossfade_tween.chain().tween_callback(_on_mosaic_crossfade_done)


## 功能：mosaic cross-fade 完成回调，翻转 _mosaic_active_is_a + 涟漪期调度下一帧。
func _on_mosaic_crossfade_done() -> void:
	_mosaic_active_is_a = not _mosaic_active_is_a
	var new_active: Control = mosaic_layers_a if _mosaic_active_is_a else mosaic_layers_b
	var new_inactive: Control = mosaic_layers_b if _mosaic_active_is_a else mosaic_layers_a
	new_active.modulate.a = 1.0
	new_inactive.modulate.a = 0.0
	if _state != State.RIPPLE_ANIM:
		return
	var is_still: bool = (_ripple_frame_index == -1)
	if is_still and not _first_ripple_cycle_done:
		_first_ripple_cycle_done = true
		_trigger_button_appearance()
	_schedule_next_ripple_cycle(is_still)


# ============================================================
# Plain 模式：TextureRect 直接显示源 PNG + EventBg A/B cross-fade
# ============================================================

## 功能：plain 模式渲染目标 art_path（事件背景源 PNG，无 mosaic）。
## 说明：
##   - 如果之前是 MOSAIC 模式 → mode 切换：mosaic α→0, EventBg α→1（装新图到活跃 event slot）
##   - 否则 plain 内部 EventBg A/B cross-fade 切到新源图
func _render_plain_mode(art_path: String) -> void:
	var tex: Texture2D = ResourceLoader.load(art_path) as Texture2D
	if tex == null:
		push_warning("set_event_background plain mode 加载失败: " + art_path)
		return

	if _mode == Mode.MOSAIC:
		# Mosaic → Plain mode 切换：装新图到活跃 EventBg，mode crossfade
		var active_event: TextureRect = event_bg_a if _event_active_is_a else event_bg_b
		active_event.texture = tex
		_mode_crossfade(Mode.PLAIN)
		return

	# Plain → Plain（事件 → 事件）：EventBg A/B cross-fade
	_crossfade_event_to_image(tex)


## 功能：EventBg A/B cross-fade 到新 texture。0.5s 双向 α tween（事件切换呼吸感 MVP）。
## 说明：
##   - 装新图到非活跃 EventBg slot
##   - 起点：active α=1（旧图显示中），inactive α=0（新图装好待淡入）
##   - tween：active 1→0 + inactive 0→1 并行 0.5s
##   - 完成后翻转 _event_active_is_a，确保 α 状态一致
func _crossfade_event_to_image(tex: Texture2D) -> void:
	if _event_crossfade_tween != null and _event_crossfade_tween.is_valid():
		_event_crossfade_tween.kill()
	var inactive: TextureRect = event_bg_b if _event_active_is_a else event_bg_a
	var active: TextureRect = event_bg_a if _event_active_is_a else event_bg_b
	inactive.texture = tex
	# 起点：active 旧图 α=1，inactive 新图 α=0
	active.modulate.a = 1.0
	inactive.modulate.a = 0.0
	_event_crossfade_tween = create_tween()
	_event_crossfade_tween.set_parallel(true)
	_event_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_event_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	_event_crossfade_tween.tween_property(active,   "modulate:a", 0.0, EVENT_CROSSFADE_SEC)
	_event_crossfade_tween.tween_property(inactive, "modulate:a", 1.0, EVENT_CROSSFADE_SEC)
	_event_crossfade_tween.chain().tween_callback(_on_event_crossfade_done)


## 功能：EventBg cross-fade 完成回调。翻转 active 标识 + 兜底 α 状态。
func _on_event_crossfade_done() -> void:
	_event_active_is_a = not _event_active_is_a
	var new_active: TextureRect = event_bg_a if _event_active_is_a else event_bg_b
	var new_inactive: TextureRect = event_bg_b if _event_active_is_a else event_bg_a
	new_active.modulate.a = 1.0
	new_inactive.modulate.a = 0.0


# ============================================================
# Mode 切换 cross-fade（mosaic↔plain）
# ============================================================

## 功能：mode 切换 cross-fade（mosaic ↔ plain）。0.5s 双向 α tween（事件切换呼吸感 MVP）。
## 参数 target_mode：目标 mode。
## 说明：
##   - 非活跃套（inactive_mosaic / inactive_event）始终保持 α=0（不参与 tween）
##   - target=MOSAIC：active_event 1→0，active_mosaic 0→1 并行 0.5s
##   - target=PLAIN：active_mosaic 1→0，active_event 0→1 并行 0.5s
##   - 不翻转 active 标识（mode 切换时活跃套类型变了，但同类型内的 active 选择不变）
func _mode_crossfade(target_mode: Mode) -> void:
	if _mode_crossfade_tween != null and _mode_crossfade_tween.is_valid():
		_mode_crossfade_tween.kill()
	var active_mosaic: Control = mosaic_layers_a if _mosaic_active_is_a else mosaic_layers_b
	var inactive_mosaic: Control = mosaic_layers_b if _mosaic_active_is_a else mosaic_layers_a
	var active_event: TextureRect = event_bg_a if _event_active_is_a else event_bg_b
	var inactive_event: TextureRect = event_bg_b if _event_active_is_a else event_bg_a
	# 非活跃套始终 α=0（不参与 tween）
	inactive_mosaic.modulate.a = 0.0
	inactive_event.modulate.a = 0.0
	# 起点：当前活跃套 α=1，目标活跃套 α=0（之前的隐藏状态）
	if target_mode == Mode.MOSAIC:
		# 从 plain 切到 mosaic：当前 event α=1, mosaic α=0
		active_event.modulate.a = 1.0
		active_mosaic.modulate.a = 0.0
	else:
		# 从 mosaic 切到 plain：当前 mosaic α=1, event α=0
		active_mosaic.modulate.a = 1.0
		active_event.modulate.a = 0.0
	_mode_crossfade_tween = create_tween()
	_mode_crossfade_tween.set_parallel(true)
	_mode_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_mode_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	if target_mode == Mode.MOSAIC:
		_mode_crossfade_tween.tween_property(active_event,  "modulate:a", 0.0, EVENT_CROSSFADE_SEC)
		_mode_crossfade_tween.tween_property(active_mosaic, "modulate:a", 1.0, EVENT_CROSSFADE_SEC)
	else:
		_mode_crossfade_tween.tween_property(active_mosaic, "modulate:a", 0.0, EVENT_CROSSFADE_SEC)
		_mode_crossfade_tween.tween_property(active_event,  "modulate:a", 1.0, EVENT_CROSSFADE_SEC)


# ============================================================
# 同图跨事件背景脉动（事件切换呼吸感 MVP 增强）
# ============================================================

## 功能：当前活跃背景层做一次 modulate 颜色变暗脉动（RGB 系数 1 → PULSE_DIM_FACTOR → 1）。
## 说明：
##   - 同一地点不同填充事件 art_path 相同 → set_event_background 幂等返回 → 背景静止无呼吸感
##   - 调用此接口给当前活跃层（mosaic 套 / event 套）做一次"翻页光影"式变暗复明
##   - 用 modulate 颜色而非 α：α 始终为 1，米色底完全被图遮住，不会闪屏
##   - 复用 _event_crossfade_tween 字段做 kill 兜底（pulse 与 plain crossfade 排他不冲突）
## 参数 duration：脉动总时长（默认 PULSE_DURATION = 0.6s，比 cross-fade 略长更舒缓）。
func pulse_event_background(duration: float = PULSE_DURATION) -> void:
	if _state != State.DONE:
		return
	var target: CanvasItem = null
	if _mode == Mode.MOSAIC:
		target = mosaic_layers_a if _mosaic_active_is_a else mosaic_layers_b
	else:
		target = event_bg_a if _event_active_is_a else event_bg_b
	if target == null:
		return
	if _event_crossfade_tween != null and _event_crossfade_tween.is_valid():
		_event_crossfade_tween.kill()
	var bright: Color = Color(1.0, 1.0, 1.0, 1.0)
	var dim: Color = Color(PULSE_DIM_FACTOR, PULSE_DIM_FACTOR, PULSE_DIM_FACTOR, 1.0)
	target.modulate = bright
	_event_crossfade_tween = create_tween()
	_event_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_event_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	_event_crossfade_tween.tween_property(target, "modulate", dim, duration * 0.5)
	_event_crossfade_tween.tween_property(target, "modulate", bright, duration * 0.5)


# ============================================================
# 辅助：layer 数组 / face mask / token
# ============================================================

func _set_layers_image(layers: Array[Control], tex: Texture2D, tokens: PackedStringArray = PackedStringArray()) -> void:
	var effective_tokens: PackedStringArray = tokens
	if effective_tokens.is_empty():
		effective_tokens = PackedStringArray(INTRO_TEXT_TOKENS)
	for layer: Control in layers:
		layer.call("set_source_image", tex)
		layer.call("set_text_tokens", effective_tokens)


func _apply_face_mask_to_active_mosaic(mask_path: String) -> void:
	var coarse: Control = intro_coarse_a if _mosaic_active_is_a else intro_coarse_b
	var medium: Control = intro_medium_a if _mosaic_active_is_a else intro_medium_b
	_set_face_mask_to_layers(coarse, medium, mask_path)


func _apply_face_mask_to_inactive_mosaic(mask_path: String) -> void:
	var coarse: Control = intro_coarse_b if _mosaic_active_is_a else intro_coarse_a
	var medium: Control = intro_medium_b if _mosaic_active_is_a else intro_medium_a
	_set_face_mask_to_layers(coarse, medium, mask_path)


func _set_face_mask_to_layers(coarse: Control, medium: Control, mask_path: String) -> void:
	if mask_path.is_empty() or not FileAccess.file_exists(mask_path):
		coarse.call("clear_exclude_mask")
		medium.call("clear_exclude_mask")
		return
	coarse.call("set_exclude_mask", mask_path)
	medium.call("set_exclude_mask", mask_path)


func _get_active_mosaic_layers() -> Array[Control]:
	if _mosaic_active_is_a:
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


func _get_inactive_mosaic_layers() -> Array[Control]:
	if _mosaic_active_is_a:
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
# 涟漪帧循环逻辑
# ============================================================

func _preload_textures() -> void:
	_still_tex      = ResourceLoader.load(STILL_PATH)      as Texture2D
	_ripple1_tex    = ResourceLoader.load(RIPPLE_1_PATH)   as Texture2D
	_ripple2_tex    = ResourceLoader.load(RIPPLE_2_PATH)   as Texture2D
	_ripple3_tex    = ResourceLoader.load(RIPPLE_3_PATH)   as Texture2D
	_girl_enter_tex = ResourceLoader.load(GIRL_ENTER_PATH) as Texture2D


## 功能：根据 pond_* art_path 返回对应预加载 texture。
func _load_pond_texture(art_path: String) -> Texture2D:
	if art_path == STILL_PATH: return _still_tex
	if art_path == RIPPLE_1_PATH: return _ripple1_tex
	if art_path == RIPPLE_2_PATH: return _ripple2_tex
	if art_path == RIPPLE_3_PATH: return _ripple3_tex
	if art_path == GIRL_ENTER_PATH: return _girl_enter_tex
	# fallback: ResourceLoader 兜底
	push_warning("_load_pond_texture: 未预加载 pond_* 资源 " + art_path)
	return ResourceLoader.load(art_path) as Texture2D


func _schedule_next_ripple_cycle(is_still_phase: bool) -> void:
	if _state != State.RIPPLE_ANIM:
		return
	var wait_time: float
	if is_still_phase:
		if _is_first_still:
			wait_time = 2.0
			_is_first_still = false
		else:
			wait_time = randf_range(5.0, 20.0)
	else:
		wait_time = 1.2
	if _ripple_timer != null and is_instance_valid(_ripple_timer):
		_ripple_timer.stop()
		_ripple_timer.queue_free()
	_ripple_timer = Timer.new()
	_ripple_timer.one_shot = true
	_ripple_timer.wait_time = wait_time
	add_child(_ripple_timer)
	_ripple_timer.timeout.connect(_on_ripple_timer_timeout)
	_ripple_timer.start()


func _on_ripple_timer_timeout() -> void:
	if _state != State.RIPPLE_ANIM:
		return
	_ripple_frame_index += 1
	if _ripple_frame_index > 2:
		_ripple_frame_index = -1
	var tex: Texture2D = _get_texture_for_frame(_ripple_frame_index)
	_crossfade_mosaic_to_image(tex, PackedStringArray(INTRO_TEXT_TOKENS), "")


func _get_texture_for_frame(frame_index: int) -> Texture2D:
	match frame_index:
		0: return _ripple1_tex
		1: return _ripple2_tex
		2: return _ripple3_tex
		_: return _still_tex


# ============================================================
# 呼吸 Tween（IntroCoarse / IntroMedium 微动）
# ============================================================

func _start_breathe_tween() -> void:
	for t: Tween in [_breathe_tween, _breathe_medium_tween, _breathe_tween_b, _breathe_medium_tween_b]:
		if t != null and t.is_valid():
			t.kill()
	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.set_trans(Tween.TRANS_SINE)
	_breathe_tween.set_ease(Tween.EASE_IN_OUT)
	_breathe_tween.tween_property(intro_coarse_a, "modulate:a", 0.60, 1.5)
	_breathe_tween.tween_property(intro_coarse_a, "modulate:a", 0.50, 1.5)

	_breathe_medium_tween = create_tween()
	_breathe_medium_tween.set_loops()
	_breathe_medium_tween.set_trans(Tween.TRANS_SINE)
	_breathe_medium_tween.set_ease(Tween.EASE_IN_OUT)
	_breathe_medium_tween.tween_property(intro_medium_a, "modulate:a", 0.65, 1.8)
	_breathe_medium_tween.tween_property(intro_medium_a, "modulate:a", 0.55, 1.8)

	_breathe_tween_b = create_tween()
	_breathe_tween_b.set_loops()
	_breathe_tween_b.set_trans(Tween.TRANS_SINE)
	_breathe_tween_b.set_ease(Tween.EASE_IN_OUT)
	_breathe_tween_b.tween_property(intro_coarse_b, "modulate:a", 0.60, 1.5)
	_breathe_tween_b.tween_property(intro_coarse_b, "modulate:a", 0.50, 1.5)

	_breathe_medium_tween_b = create_tween()
	_breathe_medium_tween_b.set_loops()
	_breathe_medium_tween_b.set_trans(Tween.TRANS_SINE)
	_breathe_medium_tween_b.set_ease(Tween.EASE_IN_OUT)
	_breathe_medium_tween_b.tween_property(intro_medium_b, "modulate:a", 0.65, 1.8)
	_breathe_medium_tween_b.tween_property(intro_medium_b, "modulate:a", 0.55, 1.8)


# ============================================================
# 开始按钮 渐显 / 呼吸 / 淡出
# ============================================================

func _trigger_button_appearance() -> void:
	if start_button == null:
		return
	if _button_appear_tween != null and _button_appear_tween.is_valid():
		_button_appear_tween.kill()
	_button_appear_tween = create_tween()
	_button_appear_tween.set_trans(Tween.TRANS_SINE)
	_button_appear_tween.set_ease(Tween.EASE_OUT)
	_button_appear_tween.tween_property(start_button, "modulate:a", 1.0, 0.8)
	_button_appear_tween.tween_callback(_start_button_breathe)


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


# ============================================================
# 点击输入处理
# ============================================================

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

func _enter_clicked_phase() -> void:
	_state = State.CLICKED

	if _ripple_timer != null and is_instance_valid(_ripple_timer):
		_ripple_timer.stop()
		_ripple_timer.queue_free()
		_ripple_timer = null

	for t: Tween in [_breathe_tween, _breathe_medium_tween, _breathe_tween_b, _breathe_medium_tween_b, _mosaic_crossfade_tween]:
		if t != null and t.is_valid():
			t.kill()

	# 按钮淡出 + cross-fade 切 girl_enter 衔接
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

	# 重置中间层 alpha 到静态值（防 Tween kill 后 alpha 锁定意外值）
	intro_coarse_a.modulate.a = 0.55
	intro_medium_a.modulate.a = 0.60
	intro_coarse_b.modulate.a = 0.55
	intro_medium_b.modulate.a = 0.60

	intro_click_received.emit()

	var seq: Tween = create_tween()
	seq.set_trans(Tween.TRANS_LINEAR)
	seq.tween_callback(Callable(self, "_on_start_fade_out")).set_delay(0.5)
	seq.tween_callback(Callable(self, "_emit_reveal_screen_mosaic")).set_delay(0.0)
	seq.tween_callback(Callable(self, "_emit_reveal_core_girl")).set_delay(0.4)
	seq.tween_callback(Callable(self, "_emit_reveal_ui")).set_delay(0.4)
	seq.tween_callback(Callable(self, "_emit_completed")).set_delay(0.8)


func _on_button_fade_out_done() -> void:
	if start_button != null:
		start_button.visible = false


## 功能：t=0.5s 时触发，cross-fade 涟漪当前帧 → girl_enter。
## 说明：IntroSequence 永久保持显示，mosaic 套承担屏幕级 girl_enter 渲染。
##       face mask 在此注入到非活跃套 IntroCoarse + IntroMedium（cross-fade 完成后接管）。
func _on_start_fade_out() -> void:
	_current_displayed_art_path = GIRL_ENTER_PATH
	_crossfade_mosaic_to_image(
		_girl_enter_tex,
		PackedStringArray(INTRO_TEXT_TOKENS),
		GIRL_ENTER_FACE_MASK_PATH
	)


func _emit_reveal_screen_mosaic() -> void:
	intro_reveal_screen_mosaic.emit()


func _emit_reveal_core_girl() -> void:
	intro_reveal_core_girl.emit()


func _emit_reveal_ui() -> void:
	intro_reveal_ui.emit()


func _emit_completed() -> void:
	_state = State.DONE
	intro_completed.emit()
