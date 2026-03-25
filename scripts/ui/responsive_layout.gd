extends RefCounted
## 响应式布局工具库。
## 提供三阶段布局计算（比例锁定 → 高度触顶 → 超宽居中）和窗口初始化，
## 各场景按需调用，自行决定业务层响应逻辑。

# 默认布局常量，可在 setup / calc 时覆盖。
const DEFAULT_ASPECT_RATIO := 9.0 / 16.0   # 宽高比 9:16（竖屏基准）
const DEFAULT_MIN_WIDTH := 540              # 最小窗口宽度
const DEFAULT_MAX_CONTENT_WIDTH := 1200     # 内容区最大宽度
const DEFAULT_BASE_MARGIN := 24             # 内容区基础边距


# 功能：初始化窗口约束并连接 viewport 尺寸变化信号。
# 说明：在场景 _ready 中调用一次。callback 为场景自身的布局刷新函数（无参数）。
#       调用后会立刻触发一次 deferred 回调，确保初始布局正确。
static func setup(viewport: Viewport, callback: Callable, config: Dictionary = {}) -> void:
	var min_width := int(config.get("min_width", DEFAULT_MIN_WIDTH))
	var aspect_ratio := float(config.get("aspect_ratio", DEFAULT_ASPECT_RATIO))
	var min_height := int(float(min_width) / aspect_ratio)
	DisplayServer.window_set_min_size(Vector2i(min_width, min_height))
	if not viewport.size_changed.is_connected(callback):
		viewport.size_changed.connect(callback)
	# 延迟一帧触发初始布局，等节点尺寸就绪。
	callback.call_deferred()


# 功能：根据当前窗口状态计算三阶段布局结果。
# 说明：纯计算函数，不产生副作用。调用方根据返回的字典自行应用布局。
# 返回字典结构：
#   win_size: Vector2i        — 当前窗口尺寸
#   vp_size: Vector2          — 当前 viewport 可见区域尺寸
#   target_height: int        — 按比例计算的目标高度
#   height_capped: bool       — 高度是否已触顶（进入阶段2）
#   is_ultrawide: bool        — 是否超宽（进入阶段3）
#   side_margin: int          — 超宽时的左右 margin（未超宽时为 base_margin）
#   base_margin: int          — 基础边距
static func calc_layout(viewport: Viewport, config: Dictionary = {}) -> Dictionary:
	var aspect_ratio := float(config.get("aspect_ratio", DEFAULT_ASPECT_RATIO))
	var max_content_width := int(config.get("max_content_width", DEFAULT_MAX_CONTENT_WIDTH))
	var base_margin := int(config.get("base_margin", DEFAULT_BASE_MARGIN))

	var win_size := DisplayServer.window_get_size()
	var vp_size: Vector2 = viewport.get_visible_rect().size

	# 获取当前屏幕可用高度（排除任务栏等系统 UI）
	var screen_rect := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()
	)
	var max_height := screen_rect.size.y

	# 阶段1：按比例计算目标高度
	var target_height := int(float(win_size.x) / aspect_ratio)

	# 阶段2：高度是否触顶
	var height_capped := target_height >= max_height

	# 阶段3：超宽居中
	var is_ultrawide := vp_size.x > max_content_width
	var side_margin := base_margin
	if is_ultrawide:
		side_margin = int((vp_size.x - float(max_content_width)) / 2.0)

	return {
		"win_size": win_size,
		"vp_size": vp_size,
		"target_height": target_height,
		"max_height": max_height,
		"height_capped": height_capped,
		"is_ultrawide": is_ultrawide,
		"side_margin": side_margin,
		"base_margin": base_margin,
	}


# 功能：阶段1 — 在自由窗口模式下锁定宽高比。
# 说明：仅在 WINDOW_MODE_WINDOWED 且高度未触顶时调整窗口尺寸。
static func apply_aspect_lock(layout: Dictionary) -> void:
	var win_mode := DisplayServer.window_get_mode()
	if win_mode != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	if bool(layout.get("height_capped", false)):
		return
	var win_size: Vector2i = layout.get("win_size", Vector2i.ZERO)
	var target_height := int(layout.get("target_height", win_size.y))
	var new_size := Vector2i(win_size.x, target_height)
	if win_size != new_size:
		DisplayServer.window_set_size(new_size)


# 功能：将 calc_layout 的 margin 结果应用到 MarginContainer。
# 说明：设置左右 margin 为 side_margin，上下为 base_margin。
static func apply_margins(margin_container: Control, layout: Dictionary) -> void:
	var side := int(layout.get("side_margin", DEFAULT_BASE_MARGIN))
	var base := int(layout.get("base_margin", DEFAULT_BASE_MARGIN))
	margin_container.offset_left = side
	margin_container.offset_right = -side
	margin_container.offset_top = base
	margin_container.offset_bottom = -base
