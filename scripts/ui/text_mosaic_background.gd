# 功能:把源图渲染为"远看像图、近看是字"的文字马赛克美术背景节点。
# 说明:基于 Godot 4.5 原生 _draw() + draw_string(),不依赖 HTML overlay 或外部 JS 库。
#       渲染策略(MVP 验证密度后调整):
#         - 按 canvas 像素步长扫描(步长 = font_size × cell_spacing)
#         - 每格反向映射到源图坐标取 Image 像素颜色
#         - 颜色 alpha 过 density_threshold 的格子画一个文字 token
#       这样字符间距 ≈ font_size,字符自然挨在一起像像素点;font_size 同时控制字号 + 密度。
# 设计依据:Design/文字马赛克美术背景_MVP设计.md(架构 B 路径:Godot 原生 draw_string)
extends Control

# === 调试参数(开发期通过 Inspector 调节,不进玩家 UI)===

# 字号(单字符像素高度;也作为 canvas 上字符网格的基础步长)
# 越小越像图、越大越可读但形状识别度下降。中文双字 token 实际宽 ≈ 2×font_size。
@export_range(2, 24) var font_size: int = 8
# 字符间距系数:网格步长 = font_size × cell_spacing。
# 1.0 = 字符紧密相邻;>1.0 留呼吸空隙;<1.0 强烈重叠(融合感更强)。
@export_range(0.3, 3.0) var cell_spacing: float = 1.0
# 透明度阈值:源图采样色 alpha 低于此值的格子跳过不渲染(过滤透明背景)
@export_range(0.0, 1.0) var density_threshold: float = 0.1
# 对比度强化系数:用于让远看图像更清晰(>1.0 让深色更深、浅色更浅);1.0 = 不调整
@export_range(0.1, 3.0) var contrast_factor: float = 1.0
# 颜色模式:0=源图色 / 1=单色(用 mono_color)
@export var color_mode: int = 0
# 单色模式下的字符颜色(color_mode=1 时生效)
@export var mono_color: Color = Color.WHITE

# === 水墨化色板(M1':色相敏感墨色映射;color_mode==0 时生效)===
# 不是单色化,是滤镜:V 决定墨阶,H 决定暖冷偏向,S 决定偏色幅度。
# 与 TextMosaicParticles 共享同一映射逻辑,推荐两层参数同步以保持视觉一致。

# 墨阶档数(2=黑白二值,5=焦/浓/淡/染/白 5 档)
@export_range(2, 16) var ink_levels: int = 5
# 暖冷偏色强度;饱和度 × 此值 = 实际混入墨色基色的比例
@export_range(0.0, 1.0) var ink_tint_strength: float = 0.4
# 暖墨基色(赭石,源图暖色调像素混入此色)
@export var ink_warm_color: Color = Color(0.659, 0.463, 0.353)
# 冷墨基色(松烟,源图冷色调像素混入此色)
@export var ink_cool_color: Color = Color(0.227, 0.282, 0.345)
# 暖色 H 锚点(0.08 ≈ 橙黄);源图色 H 越接近此值越"暖"
@export_range(0.0, 1.0) var ink_warm_anchor: float = 0.08

# 调试:在每个采样格画小圆点(验证密度,不影响最终视觉)
@export var debug_show_grid: bool = false

# === 内部状态 ===

var _source_texture: Texture2D = null
# 缓存源图 Image,避免每次 _draw 都重新 get_image()(后者会触发 GPU→CPU 拉取)
var _source_image: Image = null
var _text_tokens: PackedStringArray = PackedStringArray()
var _font: Font = null


# 功能:初始化节点。
# 说明:取主题默认字体(中文渲染依赖项目主题已配置 CJK 字体);
#       mouse_filter=IGNORE 避免拦截 LeftOverlay 的鼠标事件;
#       监听 resized 信号:节点尺寸变化时自动 queue_redraw,响应式布局下保持密度。
func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


# 功能:设置源图,缓存其 Image 供 _draw 反向映射采样。
# 参数 texture:地点 SVG 加载后的 Texture2D(来自 location_graph.csv 的 art_file)。
# 说明:传入 null 表示清空背景;Image 不可读时 push_warning,_draw 将不渲染。
func set_source_image(texture: Texture2D) -> void:
	_source_texture = texture
	_source_image = null
	if texture != null:
		_source_image = texture.get_image()
		if _source_image == null:
			push_warning(
				"TextMosaicBackground: source_texture.get_image() 返回 null"
				+ "(SVG 可能未光栅化为可读 Image)"
			)
	queue_redraw()


# 功能:设置文字材料数组,触发重绘。
# 参数 tokens:循环填充用的文字 token 数组(如 ["药铺", "苦汤", "草药", ...])。
# 说明:传入空数组会触发警告,避免静默渲染失败。
func set_text_tokens(tokens: PackedStringArray) -> void:
	_text_tokens = tokens
	if tokens.is_empty():
		push_warning("TextMosaicBackground: text_tokens 为空,_draw 将不渲染")
	queue_redraw()


# 功能:调试参数变化时重绘(Inspector 调节后由开发者手动调用)。
func refresh() -> void:
	queue_redraw()


# 功能:渲染回调(由 queue_redraw / resized 触发)。
# 算法:按 canvas 像素步长 cell 扫描;每格反向映射到源图坐标取颜色;
#       alpha ≥ density_threshold 的格子画一个 token。
# 性能:稳态下 _draw 不会触发(Godot 缓存上次绘制),仅地点切换/尺寸变化重绘一次。
#       canvas 1700×2000 + cell=8 约 53000 次 draw_string,单次 < 1s 可接受。
func _draw() -> void:
	if _source_image == null or _text_tokens.is_empty():
		return
	var canvas_size: Vector2 = size
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		return
	var src_w: int = _source_image.get_width()
	var src_h: int = _source_image.get_height()
	if src_w <= 0 or src_h <= 0:
		return

	# 网格步长(canvas 像素);clampi 防止 cell_spacing 极端值导致 0 / 负数
	var cell: int = clampi(int(round(float(font_size) * cell_spacing)), 1, 256)
	var token_count: int = _text_tokens.size()
	var token_idx: int = 0
	# baseline 偏移:draw_string 的 pos 是基线位置,加 font_size 让字符出现在格子下沿
	var baseline_offset: int = font_size

	var y: int = 0
	while y < int(canvas_size.y):
		var sy: int = clampi(
			int(float(y) / canvas_size.y * src_h), 0, src_h - 1
		)
		var x: int = 0
		while x < int(canvas_size.x):
			var sx: int = clampi(
				int(float(x) / canvas_size.x * src_w), 0, src_w - 1
			)
			var color: Color = _source_image.get_pixel(sx, sy)
			if color.a >= density_threshold:
				var token: String = _text_tokens[token_idx % token_count]
				# 颜色处理(color_mode==0):先 contrast 强化亮度对比,再 ink palette 水墨化色调
				var draw_color: Color = mono_color
				if color_mode == 0:
					draw_color = _apply_ink_palette(_apply_contrast(color))
				draw_string(
					_font,
					Vector2(x, y + baseline_offset),
					token,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					font_size,
					draw_color
				)
				token_idx += 1
			x += cell
		y += cell

	# 调试网格(仅 debug_show_grid=true 时启用,在 alpha 通过的格子画红圆)
	if debug_show_grid:
		_draw_debug_grid(canvas_size, src_w, src_h, cell)


# 功能:把源图色按"色相敏感的水墨色板"重新映射(M1' 核心算法,与粒子层共用语义)。
# 说明:V 量化到 ink_levels 档墨阶 + H 决定暖冷偏向 + S 决定偏色幅度。alpha 不动。
func _apply_ink_palette(c: Color) -> Color:
	var levels: float = float(maxi(ink_levels, 2))
	var ink_v: float = round(c.v * (levels - 1.0)) / (levels - 1.0)
	var base_gray: Color = Color(ink_v, ink_v, ink_v, c.a)

	var hue: float = c.h
	var dist: float = abs(hue - ink_warm_anchor)
	if dist > 0.5:
		dist = 1.0 - dist
	var warmth: float = 1.0 - dist * 2.0

	var tint_color: Color = ink_warm_color if warmth > 0.5 else ink_cool_color
	var tint_strength: float = c.s * ink_tint_strength

	var result: Color = base_gray.lerp(tint_color, tint_strength)
	result.a = c.a
	return result


# 功能:对源图色按 contrast_factor 做对比度强化。
# 说明:围绕 0.5 灰度线性拉伸,>1.0 加深暗部 + 提亮亮部;1.0 = 原色。
func _apply_contrast(c: Color) -> Color:
	if is_equal_approx(contrast_factor, 1.0):
		return c
	var r: float = clampf((c.r - 0.5) * contrast_factor + 0.5, 0.0, 1.0)
	var g: float = clampf((c.g - 0.5) * contrast_factor + 0.5, 0.0, 1.0)
	var b: float = clampf((c.b - 0.5) * contrast_factor + 0.5, 0.0, 1.0)
	return Color(r, g, b, c.a)


# 功能:在每个 alpha 通过的格子上画一个小红圆,用于密度对比验证。
# 说明:不影响生产视觉,仅 debug_show_grid=true 时调用。
func _draw_debug_grid(
	canvas_size: Vector2, src_w: int, src_h: int, cell: int
) -> void:
	var y: int = 0
	while y < int(canvas_size.y):
		var sy: int = clampi(
			int(float(y) / canvas_size.y * src_h), 0, src_h - 1
		)
		var x: int = 0
		while x < int(canvas_size.x):
			var sx: int = clampi(
				int(float(x) / canvas_size.x * src_w), 0, src_w - 1
			)
			var color: Color = _source_image.get_pixel(sx, sy)
			if color.a >= density_threshold:
				draw_circle(
					Vector2(x + cell * 0.5, y + cell * 0.5),
					1.0,
					Color(1.0, 0.0, 0.0, 0.6)
				)
			x += cell
		y += cell
