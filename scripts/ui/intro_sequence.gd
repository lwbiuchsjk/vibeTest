## 功能：intro 场景序列控制脚本。
## 说明：全屏覆盖池塘涟漪动画，等待玩家点击后按时序发射信号，
##       驱动 main_game 分阶段揭示大字层 → 核心区少女 → 正式 UI。
##       自身在 intro_completed 后隐藏，不参与正式游戏流程。
##       双层 A/B 架构：任意时刻 A+B 两套 modulate.a 之和 ≈ 1.0，
##       彻底消除单层 cross-fade 的"米色闪烁"问题。
class_name IntroSequence
extends Control

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

## 玩家点击瞬间发出（t=0.0s），main_game 立即后台加载少女图
signal intro_click_received()
## 点击后 0.4s 发出，main_game 淡入大字层（screen_mosaic_*）
signal intro_reveal_screen_mosaic()
## 点击后 0.8s 发出，main_game 切换核心区少女图并淡入
signal intro_reveal_core_girl()
## 点击后 1.2s 发出，main_game 淡入 Root（正式 UI）
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

## 已加载的涟漪图 Texture2D 缓存（避免每次切帧重复加载）
var _still_tex: Texture2D = null
var _ripple1_tex: Texture2D = null
var _ripple2_tex: Texture2D = null
var _ripple3_tex: Texture2D = null

# ============================================================
# 子节点引用（@onready，路径与 tscn 中节点名一致）
# ============================================================

## A 套容器（初始活跃，modulate.a=1）
@onready var mosaic_layers_a: Control     = $MosaicLayersA
## B 套容器（初始隐藏，modulate.a=0）
@onready var mosaic_layers_b: Control     = $MosaicLayersB

## A 套 8 层 TextMosaicBackground
@onready var intro_bg_a: Control          = $MosaicLayersA/IntroBg
@onready var intro_coarse_a: Control      = $MosaicLayersA/IntroCoarse
@onready var intro_medium_a: Control      = $MosaicLayersA/IntroMedium
@onready var intro_dark_light_a: Control  = $MosaicLayersA/IntroDarkLight
@onready var intro_dark_accent_a: Control = $MosaicLayersA/IntroDarkAccent
@onready var intro_dark_deep_a: Control   = $MosaicLayersA/IntroDarkDeep
@onready var intro_dark_ink_a: Control    = $MosaicLayersA/IntroDarkInk
@onready var intro_highlight_a: Control   = $MosaicLayersA/IntroHighlight

## B 套 8 层 TextMosaicBackground
@onready var intro_bg_b: Control          = $MosaicLayersB/IntroBg
@onready var intro_coarse_b: Control      = $MosaicLayersB/IntroCoarse
@onready var intro_medium_b: Control      = $MosaicLayersB/IntroMedium
@onready var intro_dark_light_b: Control  = $MosaicLayersB/IntroDarkLight
@onready var intro_dark_accent_b: Control = $MosaicLayersB/IntroDarkAccent
@onready var intro_dark_deep_b: Control   = $MosaicLayersB/IntroDarkDeep
@onready var intro_dark_ink_b: Control    = $MosaicLayersB/IntroDarkInk
@onready var intro_highlight_b: Control   = $MosaicLayersB/IntroHighlight


# ============================================================
# 初始化
# ============================================================

## 功能：节点就绪。
## 说明：此处仅做 null 检查；实际动画启动由 main_game 在 _ready 末尾调用 start_pond_animation()。
func _ready() -> void:
	# 确保自身鼠标捕捉开启（默认会继承，但显式设置更安全）
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 预加载所有涟漪纹理到内存（_ready 阶段加载，避免首帧切换卡顿）
	_preload_textures()


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


# ============================================================
# 纹理预加载
# ============================================================

## 功能：预加载 4 张涟漪纹理，避免首次切帧时 ResourceLoader 阻塞导致掉帧。
func _preload_textures() -> void:
	_still_tex   = ResourceLoader.load(STILL_PATH)    as Texture2D
	_ripple1_tex = ResourceLoader.load(RIPPLE_1_PATH) as Texture2D
	_ripple2_tex = ResourceLoader.load(RIPPLE_2_PATH) as Texture2D
	_ripple3_tex = ResourceLoader.load(RIPPLE_3_PATH) as Texture2D


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


## 功能：双层 cross-fade 切换到新帧，彻底消除米色闪烁。
## 说明：把新图设到非活跃层 → 并行 Tween：活跃层 1→0 + 非活跃层 0→1（各 0.5s）；
##       任意时刻两层 alpha 之和 ≈ 1.0，米色底层的视觉比例始终守恒，无闪烁。
##       完成后由 _on_crossfade_done 翻转 _active_is_a 标识。
func _crossfade_to_image(tex: Texture2D) -> void:
	# 杀死已有 cross-fade Tween（防御性，正常流程不会重叠）
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	# 把新图设到非活跃层（非活跃层当前 alpha=0，用户看不见，可安全覆盖）
	_set_layers_image(_get_inactive_layers(), tex)
	# 获取容器引用
	var active: Control = _get_active_container()
	var inactive: Control = _get_inactive_container()
	# 并行 cross-fade：两层同时动，alpha 守恒（Tween.TRANS_SINE + EASE_IN_OUT 使过渡柔和）
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	_crossfade_tween.tween_property(active,   "modulate:a", 0.0, 0.5)
	_crossfade_tween.tween_property(inactive, "modulate:a", 1.0, 0.5)
	# 并行段完成后，chain() 切回串行以衔接回调；翻转活跃标识并调度下一帧
	_crossfade_tween.chain().tween_callback(_on_crossfade_done)


## 功能：cross-fade 完成回调，翻转活跃层标识并调度下一次帧切换 Timer。
func _on_crossfade_done() -> void:
	if _state != State.RIPPLE_ANIM:
		return
	# 翻转活跃层：原来的非活跃层已完全显示，成为新的活跃层
	_active_is_a = not _active_is_a
	var is_still: bool = (_ripple_frame_index == -1)
	_schedule_next_ripple_cycle(is_still)


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
## 参数 layers：目标层节点数组（A 套、B 套或全 16 层）。
## 参数 tex：要渲染的源图纹理。
## 说明：set_source_image 内部已调用 queue_redraw，此处不重复调用。
func _set_layers_image(layers: Array[Control], tex: Texture2D) -> void:
	var tokens: PackedStringArray = PackedStringArray(INTRO_TEXT_TOKENS)
	# 逐层设置源图和 token，确保各层渲染同一帧画面
	for layer: Control in layers:
		layer.call("set_source_image", tex)
		layer.call("set_text_tokens", tokens)


# ============================================================
# 层数组辅助方法（A/B 套导航）
# ============================================================

## 功能：返回当前活跃套（可见套）的 8 个 mosaic 子节点数组。
func _get_active_layers() -> Array[Control]:
	if _active_is_a:
		return [
			intro_bg_a, intro_coarse_a, intro_medium_a,
			intro_dark_light_a, intro_dark_accent_a,
			intro_dark_deep_a, intro_dark_ink_a, intro_highlight_a,
		]
	else:
		return [
			intro_bg_b, intro_coarse_b, intro_medium_b,
			intro_dark_light_b, intro_dark_accent_b,
			intro_dark_deep_b, intro_dark_ink_b, intro_highlight_b,
		]


## 功能：返回当前非活跃套（隐藏套）的 8 个 mosaic 子节点数组。
func _get_inactive_layers() -> Array[Control]:
	if _active_is_a:
		return [
			intro_bg_b, intro_coarse_b, intro_medium_b,
			intro_dark_light_b, intro_dark_accent_b,
			intro_dark_deep_b, intro_dark_ink_b, intro_highlight_b,
		]
	else:
		return [
			intro_bg_a, intro_coarse_a, intro_medium_a,
			intro_dark_light_a, intro_dark_accent_a,
			intro_dark_deep_a, intro_dark_ink_a, intro_highlight_a,
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


## 功能：返回 A 套和 B 套全部 16 层节点数组（用于同时初始化两套内容）。
func _get_all_mosaic_layers() -> Array[Control]:
	return [
		intro_bg_a, intro_coarse_a, intro_medium_a,
		intro_dark_light_a, intro_dark_accent_a,
		intro_dark_deep_a, intro_dark_ink_a, intro_highlight_a,
		intro_bg_b, intro_coarse_b, intro_medium_b,
		intro_dark_light_b, intro_dark_accent_b,
		intro_dark_deep_b, intro_dark_ink_b, intro_highlight_b,
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

## 功能：捕获未处理的输入事件，鼠标点击触发 CLICKED 阶段。
## 说明：mouse_filter = MOUSE_FILTER_STOP 让 IntroSequence 控件捕获所有点击，
##       不会漏传到下层节点。CLICKED 和 DONE 状态忽略输入。
func _gui_input(event: InputEvent) -> void:
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

	# t=0.4s：开始 IntroSequence 自身淡出（0.8s 完成，即 t=1.2s 时完全透明）
	seq.tween_callback(Callable(self, "_on_start_fade_out")).set_delay(0.4)

	# t=0.4s：发射 reveal_screen_mosaic
	seq.tween_callback(Callable(self, "_emit_reveal_screen_mosaic")).set_delay(0.0)

	# t=0.8s：发射 reveal_core_girl（距上一节点 0.4s）
	seq.tween_callback(Callable(self, "_emit_reveal_core_girl")).set_delay(0.4)

	# t=1.2s：发射 reveal_ui（距上一节点 0.4s）
	seq.tween_callback(Callable(self, "_emit_reveal_ui")).set_delay(0.4)

	# t=2.0s：发射 completed 并隐藏自身（距上一节点 0.8s）
	seq.tween_callback(Callable(self, "_emit_completed")).set_delay(0.8)


## 功能：t=0.4s 时触发，开始 IntroSequence 整体淡出。
func _on_start_fade_out() -> void:
	# 独立 Tween 驱动淡出，不占用时序 Tween 的插值轨道
	var fade: Tween = create_tween()
	fade.set_trans(Tween.TRANS_SINE)
	fade.set_ease(Tween.EASE_IN_OUT)
	# modulate.a 1→0，0.8s，EaseInOut（t=0.4s 开始，t=1.2s 结束）
	fade.tween_property(self, "modulate:a", 0.0, 0.8)


## 功能：t=0.4s 时发射 reveal_screen_mosaic 信号。
func _emit_reveal_screen_mosaic() -> void:
	intro_reveal_screen_mosaic.emit()


## 功能：t=0.8s 时发射 reveal_core_girl 信号。
func _emit_reveal_core_girl() -> void:
	intro_reveal_core_girl.emit()


## 功能：t=1.2s 时发射 reveal_ui 信号。
func _emit_reveal_ui() -> void:
	intro_reveal_ui.emit()


## 功能：t=2.0s 时发射 completed 信号并隐藏自身。
func _emit_completed() -> void:
	_state = State.DONE
	intro_completed.emit()
	# 隐藏自身，让正式 UI 完整呈现
	visible = false
