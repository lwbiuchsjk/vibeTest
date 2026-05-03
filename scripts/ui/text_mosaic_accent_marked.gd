# 功能:基于 flow_regions.json 中 accent_areas 标注,在指定多边形区域内画
#       "点睛色"字符——保留高饱和度颜色,与素描灰阶 12 层形成"画龙点睛"对比。
#       每个 area 独立呼吸节奏(基于 _global_time + area.breathe_period 各自计算)。
# 设计依据:[[文字马赛克美术背景_视觉精调过程]] §决策点 7(待落档)。
#       不再走 cell 网格扫描全图(那是 text_mosaic_background.gd 的语义),
#       改为按 schema 中显式标注的多边形 area 渲染——区域形状由设计驱动而非源图驱动,
#       让"该有点睛但被 ink_palette 压扁"的位置由人(我/美术)显式标注恢复。
extends Control

# 字号(与点睛区域颗粒度匹配,通常用最小字号 8 让点睛细密)
@export_range(2, 64) var font_size: int = 8
# 字符间距系数:网格步长 = font_size × cell_spacing
@export_range(0.3, 3.0) var cell_spacing: float = 1.0


var _accent_areas: Array = []  # [{polygon, color, breathe_period, breathe_min_alpha, breathe_max_alpha, ...}]
var _src_image_size: Vector2 = Vector2.ZERO
var _text_tokens: PackedStringArray = PackedStringArray()
var _font: Font = null
var _global_time: float = 0.0


# 功能:初始化节点。开 _process 用于呼吸动画(全局时间累积驱动每 area 独立 sin 相位)。
func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(true)


# 功能:每帧累积 _global_time 并触发重绘(字符颜色 alpha 随时间变化必须每帧重画)。
# 说明:仅 accent_areas 非空时累积。性能开销限于各 area bbox 内 cell 扫描,小区域可接受。
func _process(delta: float) -> void:
	if _accent_areas.is_empty():
		return
	_global_time += delta
	queue_redraw()


# 功能:设置 accent_areas 列表 + 源图尺寸(后者用于 cover 反向映射)。
# 参数 areas:从 flow_regions.json 的 accent_areas 字段读取的数组。
# 参数 src_size:源图原始像素尺寸(同 flow_regions.json 的 image_size)。
func set_accent_data(areas: Array, src_size: Vector2) -> void:
	_accent_areas = areas
	_src_image_size = src_size
	queue_redraw()


# 功能:清空 accent 数据(切换地点时由 _render_event_background 调用)。
func clear_accent_data() -> void:
	_accent_areas = []
	_src_image_size = Vector2.ZERO
	queue_redraw()


# 功能:设置文字 token 池(与其他 mosaic 层共享,按 cell 顺序循环填充)。
func set_text_tokens(tokens: PackedStringArray) -> void:
	_text_tokens = tokens
	queue_redraw()


# 功能:渲染回调。对每个 area 计算当前呼吸 alpha,在 polygon bbox 内 cell 扫描,
#       cell 中心点在 polygon 内时画字符(颜色 = area.color * area_alpha)。
# 几何:polygon 顶点是源图坐标系(与 flow_regions 一致),先正向映射到 canvas 坐标系
#       计算 bbox,再 cell 扫描;cell 中心点用 canvas 系下的 polygon 做内点判定。
func _draw() -> void:
	if _accent_areas.is_empty() or _text_tokens.is_empty():
		return
	if _src_image_size.x <= 0 or _src_image_size.y <= 0:
		return
	var canvas_size: Vector2 = size
	if canvas_size.x <= 0 or canvas_size.y <= 0:
		return

	var src_w: float = _src_image_size.x
	var src_h: float = _src_image_size.y

	# Cover 模式映射(与 text_mosaic_background.gd / text_mosaic_particles.gd 一致):
	# 保持源图比例,超出 canvas 比例的源图边缘被裁切。
	var canvas_aspect: float = canvas_size.x / canvas_size.y
	var src_aspect: float = src_w / src_h
	var inv_scale: float
	var src_offset_x: float = 0.0
	var src_offset_y: float = 0.0
	if canvas_aspect > src_aspect:
		inv_scale = src_w / canvas_size.x
		var visible_h: float = canvas_size.y * inv_scale
		src_offset_y = (src_h - visible_h) * 0.5
	else:
		inv_scale = src_h / canvas_size.y
		var visible_w: float = canvas_size.x * inv_scale
		src_offset_x = (src_w - visible_w) * 0.5

	var cell: int = clampi(int(round(float(font_size) * cell_spacing)), 1, 256)
	var token_count: int = _text_tokens.size()
	var baseline_offset: int = font_size
	var token_idx: int = 0

	for area_variant in _accent_areas:
		if not (area_variant is Dictionary):
			continue
		var area: Dictionary = area_variant
		var polygon_src: Array = area.get("polygon", [])
		if polygon_src.size() < 3:
			continue

		# 颜色解析(JSON 中是 [r, g, b, a] 数组形式)
		var color_arr_variant: Variant = area.get("color", [1.0, 1.0, 1.0, 1.0])
		if not (color_arr_variant is Array):
			continue
		var color_arr: Array = color_arr_variant
		if color_arr.size() < 3:
			continue
		var color_a: float = float(color_arr[3]) if color_arr.size() >= 4 else 1.0
		var area_base_color: Color = Color(
			float(color_arr[0]), float(color_arr[1]), float(color_arr[2]), color_a
		)

		# 呼吸节奏参数
		var period: float = float(area.get("breathe_period", 3.5))
		var min_a: float = float(area.get("breathe_min_alpha", 0.4))
		var max_a: float = float(area.get("breathe_max_alpha", 0.85))
		var phase: float = sin(_global_time * TAU / max(period, 0.01)) * 0.5 + 0.5
		var area_alpha: float = lerp(min_a, max_a, phase)

		# 顶点正向映射到 canvas 坐标系 + 计算 bbox
		var polygon_canvas: PackedVector2Array = PackedVector2Array()
		var min_x_canvas: float = INF
		var min_y_canvas: float = INF
		var max_x_canvas: float = -INF
		var max_y_canvas: float = -INF
		for v_variant in polygon_src:
			if not (v_variant is Array):
				continue
			var v_arr: Array = v_variant
			if v_arr.size() < 2:
				continue
			var sx: float = float(v_arr[0])
			var sy: float = float(v_arr[1])
			var cx: float = (sx - src_offset_x) / inv_scale
			var cy: float = (sy - src_offset_y) / inv_scale
			polygon_canvas.append(Vector2(cx, cy))
			if cx < min_x_canvas:
				min_x_canvas = cx
			if cy < min_y_canvas:
				min_y_canvas = cy
			if cx > max_x_canvas:
				max_x_canvas = cx
			if cy > max_y_canvas:
				max_y_canvas = cy
		if polygon_canvas.size() < 3:
			continue

		# bbox clamp 到 canvas 内(避免无效扫描)
		min_x_canvas = clampf(min_x_canvas, 0.0, canvas_size.x)
		min_y_canvas = clampf(min_y_canvas, 0.0, canvas_size.y)
		max_x_canvas = clampf(max_x_canvas, 0.0, canvas_size.x)
		max_y_canvas = clampf(max_y_canvas, 0.0, canvas_size.y)
		if max_x_canvas <= min_x_canvas or max_y_canvas <= min_y_canvas:
			continue

		var draw_color: Color = Color(
			area_base_color.r,
			area_base_color.g,
			area_base_color.b,
			area_base_color.a * area_alpha
		)

		# cell 扫描:对齐到 cell 网格起点(避免 area 间网格抖动)
		var y: int = int(floor(min_y_canvas / cell)) * cell
		while y < int(max_y_canvas):
			var x: int = int(floor(min_x_canvas / cell)) * cell
			while x < int(max_x_canvas):
				var center: Vector2 = Vector2(
					float(x) + cell * 0.5, float(y) + cell * 0.5
				)
				if Geometry2D.is_point_in_polygon(center, polygon_canvas):
					var token: String = _text_tokens[token_idx % token_count]
					draw_string(
						_font,
						Vector2(float(x), float(y + baseline_offset)),
						token,
						HORIZONTAL_ALIGNMENT_LEFT,
						-1,
						font_size,
						draw_color
					)
					token_idx += 1
				x += cell
			y += cell
