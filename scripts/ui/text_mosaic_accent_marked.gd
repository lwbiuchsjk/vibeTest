# 功能:基于 flow_regions.json 中 accent_areas 标注,在指定区域内画
#       "点睛色"字符——保留高饱和度颜色,与素描灰阶 12 层形成"画龙点睛"对比。
#       每个 area 独立呼吸节奏(基于 _global_time + area.breathe_period 各自计算)。
# 设计依据:[[文字马赛克美术背景_视觉精调过程]] §决策点 7 阶段 4。
#       schema v2:area 优先用 mask_path 字段(LangSAM 像素级 mask,与源图同坐标系),
#       polygon 字段保留作 fallback(早期 LLM 矩形近似路径,精度不足已弃用)。
#       不再走 cell 网格扫描全图(那是 text_mosaic_background.gd 的语义),
#       改为按 schema 中显式标注的 area 渲染——区域形状由设计驱动而非源图驱动,
#       让"该有点睛但被 ink_palette 压扁"的位置由人(LangSAM 或 LLM)显式标注恢复。
extends Control

# mask alpha 判定阈值:mask_path 路径下,反向映射到 src 后查 mask alpha,> 此值才画字符。
# LangSAM 输出 mask 编码:RGB=白(255),alpha=0(非 mask 区) / 255(mask 区),二值 → 0.5 阈值稳健。
const MASK_ALPHA_THRESHOLD: float = 0.5

# 字号(与点睛区域颗粒度匹配,通常用最小字号 8 让点睛细密)
@export_range(2, 64) var font_size: int = 8
# 字符间距系数:网格步长 = font_size × cell_spacing
@export_range(0.3, 3.0) var cell_spacing: float = 1.0


var _accent_areas: Array = []  # [{polygon|mask_path, color, breathe_*, accent_layers?, _mask_image?}]
var _src_image_size: Vector2 = Vector2.ZERO
var _text_tokens: PackedStringArray = PackedStringArray()
var _font: Font = null
var _global_time: float = 0.0
# 源图 Image 缓存:仅 mask 路径下被 accent_layers 的 mix_source 字段使用——
# 把 area_color 与"该 cell 位置源图原色"混合,让点睛色融合环境色(如绛朱混眼球深褐)。
# 由 main_game.gd 在 _render_event_background 中调 set_source_image(texture) 注入。
var _source_image: Image = null


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


# 功能:设置 accent_areas 列表 + 源图尺寸(后者用于 cover 反向映射)。对带 mask_path 的 area
#       立即加载 mask Image 缓存到 area dict 上的 `_mask_image` 字段(避免 _draw 每帧 IO)。
# 参数 areas:从 flow_regions.json 的 accent_areas 字段读取的数组。
# 参数 src_size:源图原始像素尺寸(同 flow_regions.json 的 image_size)。
func set_accent_data(areas: Array, src_size: Vector2) -> void:
	_accent_areas = areas
	_src_image_size = src_size
	for area_variant in _accent_areas:
		if not (area_variant is Dictionary):
			continue
		var area: Dictionary = area_variant
		var mask_path_variant: Variant = area.get("mask_path", "")
		if mask_path_variant is String and (mask_path_variant as String) != "":
			_ensure_mask_loaded(area, mask_path_variant)
	queue_redraw()


# 功能:按 area 缓存 mask Image。已缓存则跳过(切换地点会重建 area dict 触发重新加载)。
# 说明:mask_path 用 res:// 协议,通过 ProjectSettings.globalize_path 转绝对路径后用
#       Image.load_from_file 读 PNG。开发期 OK;若导出 PCK 后需改走 ResourceLoader 加载。
func _ensure_mask_loaded(area: Dictionary, mask_path: String) -> void:
	if area.has("_mask_image") and (area["_mask_image"] is Image):
		return
	var abs_path: String = ProjectSettings.globalize_path(mask_path)
	var img: Image = Image.load_from_file(abs_path)
	if img == null:
		push_warning(
			"accent_marked: mask 加载失败 %s -> %s" % [mask_path, abs_path]
		)
		return
	area["_mask_image"] = img


# 功能:清空 accent 数据(切换地点时由 _render_event_background 调用)。
func clear_accent_data() -> void:
	_accent_areas = []
	_src_image_size = Vector2.ZERO
	queue_redraw()


# 功能:设置源图 Image 缓存。仅 accent_layers 的 mix_source > 0 时被引用——
#       cell 中心反向映射到 src 后,从 _source_image 取该位置源图色,与 area_color
#       按 mix_source 插值,让点睛色融合环境色。传 null = 清空(切换地点时调)。
func set_source_image(texture: Texture2D) -> void:
	_source_image = null
	if texture != null:
		_source_image = texture.get_image()
		if _source_image == null:
			push_warning(
				"accent_marked: source_texture.get_image() 返回 null"
				+ "(SVG 可能未光栅化);mix_source 将退回 area_color"
			)
	queue_redraw()


# 功能:设置文字 token 池(与其他 mosaic 层共享,按 cell 顺序循环填充)。
func set_text_tokens(tokens: PackedStringArray) -> void:
	_text_tokens = tokens
	queue_redraw()


# 功能:渲染回调。对每个 area 计算当前呼吸 alpha,然后按 mask_path 优先 / polygon fallback
#       两条路径之一画字符。
# 几何:mask 路径——cell 中心(canvas 像素)反向映射到 src 像素 → 查 mask alpha → 阈值过则画。
#       polygon 路径——polygon 顶点(src 坐标系)正向映射到 canvas 系算 bbox,
#                       cell 中心 canvas 坐标做内点判定。
# 坐标系约定:mask PNG 与源图同尺寸(1024×576),不需 resize(决策点 7 阶段 4 风险点已确认)。
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

	# Cover 模式映射(与 text_mosaic_background.gd / text_mosaic_particles.gd 完全一致):
	# 保持源图比例,超出 canvas 比例的源图边缘被裁切。
	# canvas (cx, cy) → src (src_offset + (cx, cy) * inv_scale)。
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

		# === 颜色 + 呼吸节奏(两条路径共用)===
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
		var period: float = float(area.get("breathe_period", 3.5))
		var min_a: float = float(area.get("breathe_min_alpha", 0.4))
		var max_a: float = float(area.get("breathe_max_alpha", 0.85))
		var phase: float = sin(_global_time * TAU / max(period, 0.01)) * 0.5 + 0.5
		var area_alpha: float = lerp(min_a, max_a, phase)
		var draw_color: Color = Color(
			area_base_color.r,
			area_base_color.g,
			area_base_color.b,
			area_base_color.a * area_alpha
		)

		# === 路径分支:mask_path 优先,polygon fallback ===
		var has_mask: bool = (
			area.has("_mask_image") and (area["_mask_image"] is Image)
		)

		if has_mask:
			# --- mask 路径:扫全 canvas,cell 中心反向映射到 src 查 mask alpha ---
			# 多层叠加:area 内 accent_layers 数组(可选)定义 N 个 sub-pass,每 pass 用
			# 不同 font_size / alpha_mul / grid_phase / mix_source 跑一次扫描,在 mask
			# 区内累积"密度+颜色层次",让小面积 mask 也能承接丰富视觉细节(类比决策点 6
			# 暗部强化的密度承担灰度原理)。无 accent_layers 字段时退回单层默认行为。
			var mask_image: Image = area["_mask_image"]
			var mask_w: int = mask_image.get_width()
			var mask_h: int = mask_image.get_height()

			# 构造 layers 数组:有配置走配置,没有则单层默认(向后兼容)
			var layers_variant: Variant = area.get("accent_layers", [])
			var layers: Array = layers_variant if layers_variant is Array else []
			if layers.is_empty():
				layers = [{
					"font_size": font_size,
					"alpha_mul": 1.0,
					"grid_phase": [0.0, 0.0],
					"mix_source": 0.0,
				}]

			for layer_variant in layers:
				if not (layer_variant is Dictionary):
					continue
				var layer: Dictionary = layer_variant
				var layer_font_size: int = clampi(
					int(layer.get("font_size", font_size)), 2, 64
				)
				var layer_alpha_mul: float = clampf(
					float(layer.get("alpha_mul", 1.0)), 0.0, 4.0
				)
				var phase_arr_variant: Variant = layer.get("grid_phase", [0.0, 0.0])
				var phase_x: float = 0.0
				var phase_y: float = 0.0
				if phase_arr_variant is Array:
					var phase_arr: Array = phase_arr_variant
					if phase_arr.size() >= 1:
						phase_x = float(phase_arr[0])
					if phase_arr.size() >= 2:
						phase_y = float(phase_arr[1])
				var mix_source: float = clampf(
					float(layer.get("mix_source", 0.0)), 0.0, 1.0
				)

				var layer_cell: int = clampi(
					int(round(float(layer_font_size) * cell_spacing)), 1, 256
				)
				var layer_baseline: int = layer_font_size

				# 起点偏移(grid_phase × layer_cell):多层错开 cell 网格起点
				var my: int = int(round(phase_y * float(layer_cell)))
				while my < int(canvas_size.y):
					var mx: int = int(round(phase_x * float(layer_cell)))
					while mx < int(canvas_size.x):
						var ccx: float = float(mx) + layer_cell * 0.5
						var ccy: float = float(my) + layer_cell * 0.5
						var msx: int = int(src_offset_x + ccx * inv_scale)
						var msy: int = int(src_offset_y + ccy * inv_scale)
						if (
							msx >= 0 and msx < mask_w
							and msy >= 0 and msy < mask_h
						):
							if (
								mask_image.get_pixel(msx, msy).a
								> MASK_ALPHA_THRESHOLD
							):
								# 颜色:area_color 与源图原色按 mix_source 插值
								# (mix=0 纯 area_color,mix=1 纯源图色,中间值融合)。
								# _source_image 缺失或越界时退回 area_color。
								var layer_color: Color = draw_color
								if (
									mix_source > 0.0
									and _source_image != null
									and msx < _source_image.get_width()
									and msy < _source_image.get_height()
								):
									var src_color: Color = (
										_source_image.get_pixel(msx, msy)
									)
									layer_color = Color(
										lerp(draw_color.r, src_color.r, mix_source),
										lerp(draw_color.g, src_color.g, mix_source),
										lerp(draw_color.b, src_color.b, mix_source),
										draw_color.a
									)
								layer_color.a *= layer_alpha_mul

								var token_m: String = (
									_text_tokens[token_idx % token_count]
								)
								draw_string(
									_font,
									Vector2(
										float(mx),
										float(my + layer_baseline)
									),
									token_m,
									HORIZONTAL_ALIGNMENT_LEFT,
									-1,
									layer_font_size,
									layer_color
								)
								token_idx += 1
						mx += layer_cell
					my += layer_cell
			continue  # mask 路径完成,跳过 polygon

		# --- polygon 路径(fallback):polygon 顶点 → canvas bbox 扫描 + 内点判定 ---
		var polygon_src: Array = area.get("polygon", [])
		if polygon_src.size() < 3:
			continue

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
			var vsx: float = float(v_arr[0])
			var vsy: float = float(v_arr[1])
			var pcx: float = (vsx - src_offset_x) / inv_scale
			var pcy: float = (vsy - src_offset_y) / inv_scale
			polygon_canvas.append(Vector2(pcx, pcy))
			if pcx < min_x_canvas:
				min_x_canvas = pcx
			if pcy < min_y_canvas:
				min_y_canvas = pcy
			if pcx > max_x_canvas:
				max_x_canvas = pcx
			if pcy > max_y_canvas:
				max_y_canvas = pcy
		if polygon_canvas.size() < 3:
			continue

		# bbox clamp 到 canvas 内(避免无效扫描)
		min_x_canvas = clampf(min_x_canvas, 0.0, canvas_size.x)
		min_y_canvas = clampf(min_y_canvas, 0.0, canvas_size.y)
		max_x_canvas = clampf(max_x_canvas, 0.0, canvas_size.x)
		max_y_canvas = clampf(max_y_canvas, 0.0, canvas_size.y)
		if max_x_canvas <= min_x_canvas or max_y_canvas <= min_y_canvas:
			continue

		# cell 扫描:对齐到 cell 网格起点(避免 area 间网格抖动)
		var py: int = int(floor(min_y_canvas / cell)) * cell
		while py < int(max_y_canvas):
			var px: int = int(floor(min_x_canvas / cell)) * cell
			while px < int(max_x_canvas):
				var center: Vector2 = Vector2(
					float(px) + cell * 0.5, float(py) + cell * 0.5
				)
				if Geometry2D.is_point_in_polygon(center, polygon_canvas):
					var token_p: String = _text_tokens[token_idx % token_count]
					draw_string(
						_font,
						Vector2(float(px), float(py + baseline_offset)),
						token_p,
						HORIZONTAL_ALIGNMENT_LEFT,
						-1,
						font_size,
						draw_color
					)
					token_idx += 1
				px += cell
			py += cell
