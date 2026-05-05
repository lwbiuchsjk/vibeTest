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
@export_range(2, 64) var font_size: int = 8
# 字符间距系数:网格步长 = font_size × cell_spacing。
# 1.0 = 字符紧密相邻;>1.0 留呼吸空隙;<1.0 强烈重叠(融合感更强)。
@export_range(0.3, 3.0) var cell_spacing: float = 1.0
# 网格起点相对 cell 的偏移比例(x/y 各推荐 [0, 1)):多层叠加时各层用不同 grid_phase
# 让网格错开,避免大/中/小字号共用 (0,0) 起点产生明显的横竖间隔线。0 = 严格从左上角开始。
@export var grid_phase: Vector2 = Vector2.ZERO
# 单层内部 cell-level alpha 抖动幅度(0 ~ 1):破除单层等密度网格感。
# 大字号层叠加时即使 grid_phase 错开,单层内部 cells 仍是规整网格 → 视觉固化。
# 用 cell 坐标做确定性伪随机抖动,让每个 cell alpha 在 [1.0 - density_jitter, 1.0] 内变化,
# 形成"有些浓有些淡"的不规整密度,模仿油画笔触自然疏密。0 = 不抖动(默认,不影响 test 场景)。
@export_range(0.0, 1.0) var density_jitter: float = 0.0
# 单层内部 cell-level 位置抖动幅度(0 ~ 1):破除字符严格落在 cell 网格点上的对齐感。
# density_jitter 只让 alpha 不均(密度变化),但 cells 位置仍是规整网格;
# position_jitter 让每个 cell 内字符 x/y 在 cell 内 ±cell*0.5*jitter 内偏移,
# 字符不再严格在网格点上 → 彻底破除"方块矩阵"视觉。0 = 不偏移(默认)。
@export_range(0.0, 1.0) var position_jitter: float = 0.0
# 透明度阈值:源图采样色 alpha 低于此值的格子跳过不渲染(过滤透明背景)
@export_range(0.0, 1.0) var density_threshold: float = 0.1
# V 通道下限阈值:cell 反向映射到源图后,源色 V < 此值的格子跳过不画。
# 用于"高光层"(素描式提亮)——只在亮区贡献字符,暗区跳过。
# 默认 0.0 = 无下限过滤,与原行为兼容。
@export_range(0.0, 1.0) var v_min_threshold: float = 0.0
# V 通道上限阈值:cell 反向映射到源图后,源色 V > 此值的格子跳过不画。
# 用于"暗部强化层"(素描式叠加)——只在暗区贡献字符,亮区跳过让下层透出。
# 多个 v_max 不同的层叠加 → 暗区被多层都画(密度累加)、亮区只有 1 层 → 自然形成密度梯度。
# 与 v_min_threshold 配合可定义 V 区间(高光/中调/暗部各取一段)。
# 默认 1.0 = 无上限过滤,与原行为兼容。
@export_range(0.0, 1.0) var v_max_threshold: float = 1.0
# 饱和度下限阈值:cell 反向映射到源图后,源色 S < 此值的格子跳过不画。
# 用于"点缀色层"——只在源图高饱和度区域(配饰/眼神/灯笼等)贡献字符,
# 让美术原本设计的"焦点色"在素描灰阶画面中保留为点睛之笔。
# 默认 0.0 = 无饱和度过滤,与原行为兼容。
@export_range(0.0, 1.0) var saturation_threshold: float = 0.0
# 边缘柔和过渡区宽度(canvas 像素):仅对 cell 中心已**超出** canvas 的字符做 alpha 衰减,
# canvas 内字符不衰减(避免 grid_phase 偏移产生的贴边 cell 被淡化复发白边)。
# 公式:fade = clamp(1 + min(min_dist, 0) / fade_pixels, 0, 1)。
#   - min_dist ≥ 0(cell 中心在 canvas 内) → fade = 1.0(完整 alpha,无白边)
#   - min_dist ∈ [-fade, 0)(cell 中心溢出 0~fade 像素) → 按比例渐隐
#   - min_dist ≤ -fade → fade = 0(完全溢出,clip_contents 兜底)
# 配合父容器 clip_contents 把"硬切"变"渐隐",边界过渡柔和。默认 8 px = 1 默认 cell 宽,
# 核心区视觉自然;衬底层(ScreenMosaic*)期望溢出 ±200 不需要 fade,显式设为 0 关闭。
@export_range(0, 64) var edge_fade_pixels: int = 8

# === 点缀色层专属(use_source_color + 呼吸动画)===

# 是否用源图原色作字符颜色(跳过 ink_palette 水墨化)。
# 用于"点缀色层":高饱和度区域保留源图原色,与素描灰阶形成"点醒"对比。
# 默认 false = 走 ink_palette,与原行为兼容。
@export var use_source_color: bool = false
# 是否启用呼吸动画(整层 modulate.a 正弦变化让画面活起来)。默认 false 兼容。
@export var breathe_enabled: bool = false
# 呼吸周期(秒);3~4 秒为推荐值,与素描静谧感配合,不显得机械
@export_range(0.5, 10.0) var breathe_period: float = 3.5
# 呼吸 alpha 下限(整层 modulate.a 的最低值)
@export_range(0.0, 1.0) var breathe_min_alpha: float = 0.4
# 呼吸 alpha 上限(整层 modulate.a 的最高值)
@export_range(0.0, 1.0) var breathe_max_alpha: float = 0.8
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
# 呼吸动画累积时间(仅 breathe_enabled=true 时使用)
var _breathe_time: float = 0.0


# 功能:初始化节点。
# 说明:取主题默认字体(中文渲染依赖项目主题已配置 CJK 字体);
#       mouse_filter=IGNORE 避免拦截 LeftOverlay 的鼠标事件;
#       监听 resized 信号:节点尺寸变化时自动 queue_redraw,响应式布局下保持密度;
#       breathe_enabled=false 时关闭 _process(避免空跑浪费帧时间)。
func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(breathe_enabled)


# 功能:呼吸动画——整层 modulate.a 正弦变化,让"点缀色层"在素描静谧画面中"活起来"。
# 说明:仅 breathe_enabled=true 时启用;modulate 改变不触发 _draw 重绘(GPU 端合成),
#       性能开销可忽略。alpha 在 [breathe_min_alpha, breathe_max_alpha] 间正弦变化,
#       周期由 breathe_period 控制(推荐 3~4 秒,与素描静谧感配合不显机械)。
func _process(delta: float) -> void:
	if not breathe_enabled:
		return
	_breathe_time += delta
	var phase: float = sin(_breathe_time * TAU / breathe_period) * 0.5 + 0.5
	modulate.a = lerp(breathe_min_alpha, breathe_max_alpha, phase)


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

	# Cover 模式反向映射:与 EventBackground.stretch_mode=6 (KEEP_ASPECT_COVERED) 对齐,保持源图比例。
	# canvas (cx, cy) → src (src_offset + (cx, cy) * inv_scale)。
	# 超出 canvas 比例的源图边缘被裁切——这里表现为 mosaic 不采样那部分,与原图层视觉一致。
	var canvas_aspect: float = canvas_size.x / canvas_size.y
	var src_aspect: float = float(src_w) / float(src_h)
	var inv_scale: float
	var src_offset_x: float = 0.0
	var src_offset_y: float = 0.0
	if canvas_aspect > src_aspect:
		# canvas 比图更宽:横向填满,纵向裁切上下边(居中)
		inv_scale = float(src_w) / canvas_size.x
		var visible_h: float = canvas_size.y * inv_scale
		src_offset_y = (float(src_h) - visible_h) * 0.5
	else:
		# canvas 比图更高:纵向填满,横向裁切左右边(居中)
		inv_scale = float(src_h) / canvas_size.y
		var visible_w: float = canvas_size.x * inv_scale
		src_offset_x = (float(src_w) - visible_w) * 0.5

	# 网格步长(canvas 像素);clampi 防止 cell_spacing 极端值导致 0 / 负数
	var cell: int = clampi(int(round(float(font_size) * cell_spacing)), 1, 256)
	var token_count: int = _text_tokens.size()
	var token_idx: int = 0
	# baseline 偏移:draw_string 的 pos 是基线位置,加 font_size 让字符出现在格子下沿
	var baseline_offset: int = font_size

	# 网格起点应用 grid_phase 偏移(单位:cell 比例),让多层叠加时网格不对齐。
	# 起点从 phase*cell - cell 开始(向左/上扩展一格):配合父容器 LeftStack 的 clip_contents,
	# 让左/上边缘 cell 也能贡献字符,外溢部分被 GPU 裁——同时解决"grid_phase 正向偏移导致
	# 左/上白边"和"position_jitter 让边缘字符部分超出容器进入背景"两个问题。
	var y: int = int(round(grid_phase.y * float(cell))) - cell
	while y < int(canvas_size.y):
		var sy: int = clampi(
			int(src_offset_y + float(y) * inv_scale), 0, src_h - 1
		)
		var x: int = int(round(grid_phase.x * float(cell))) - cell
		while x < int(canvas_size.x):
			var sx: int = clampi(
				int(src_offset_x + float(x) * inv_scale), 0, src_w - 1
			)
			var color: Color = _source_image.get_pixel(sx, sy)
			# V 区间 + S 下限过滤:[v_min, v_max] ∧ s ≥ saturation_threshold 才画。
			# 暗部强化层用 v_max < 1.0、高光层用 v_min > 0.0、中调切片用两端都设、
			# 点缀色层用 s ≥ 0.4(只在源图高饱和度区域贡献字符做"点睛")。
			if (
				color.a >= density_threshold
				and color.v >= v_min_threshold
				and color.v <= v_max_threshold
				and color.s >= saturation_threshold
			):
				var token: String = _text_tokens[token_idx % token_count]
				# 颜色处理(color_mode==0):先 contrast 强化亮度对比,
				# 再走 ink palette 水墨化(默认)或保留源图原色(use_source_color,点缀色层用)
				var draw_color: Color = mono_color
				if color_mode == 0:
					if use_source_color:
						draw_color = _apply_contrast(color)
					else:
						draw_color = _apply_ink_palette(_apply_contrast(color))
				# Cell-level alpha 抖动:基于 cell 坐标做确定性伪随机,每个 cell alpha 在
				# [1.0 - density_jitter, 1.0] 内变化,破除单层规整网格感(模仿油画笔触自然疏密)
				if density_jitter > 0.0:
					var jitter: float = (
						sin(float(x) * 0.137 + float(y) * 0.213) * 0.5 + 0.5
					)
					draw_color.a *= 1.0 - density_jitter * jitter
				# Cell-level 位置抖动:字符 x/y 在 cell 内 ±cell*0.5*position_jitter 偏移
				# 用与 alpha 抖动不同频率(0.211/0.317)避免相关性,字符不再严格在网格点
				var draw_x: float = float(x)
				var draw_y: float = float(y + baseline_offset)
				if position_jitter > 0.0:
					var jx: float = sin(float(x) * 0.211 + float(y) * 0.317)
					var jy: float = cos(float(x) * 0.317 + float(y) * 0.211)
					var amp: float = float(cell) * 0.5 * position_jitter
					draw_x += jx * amp
					draw_y += jy * amp
				# 边缘柔和过渡:仅对 cell 中心已超出 canvas 的字符按距离渐隐(取代 clip 硬切)。
				# canvas 内字符 fade=1.0 不衰减(避免贴边 cell 被淡化复发白边——grid_phase
				# 偏移让某些层"贴边 cell"距边只有 1~7 px,旧公式会把它们误判为 fade 区)。
				if edge_fade_pixels > 0:
					var cx: float = float(x) + float(cell) * 0.5
					var cy: float = float(y) + float(cell) * 0.5
					var dist_l: float = cx
					var dist_r: float = canvas_size.x - cx
					var dist_t: float = cy
					var dist_b: float = canvas_size.y - cy
					var min_dist: float = min(
						min(dist_l, dist_r), min(dist_t, dist_b)
					)
					var fade_factor: float = clampf(
						1.0 + min(min_dist, 0.0) / float(edge_fade_pixels),
						0.0, 1.0
					)
					draw_color.a *= fade_factor
				draw_string(
					_font,
					Vector2(draw_x, draw_y),
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
	# Cover 反向映射(与 _draw 一致):保持源图比例,超出 canvas 比例的源图边缘被裁切
	var canvas_aspect: float = canvas_size.x / canvas_size.y
	var src_aspect: float = float(src_w) / float(src_h)
	var inv_scale: float
	var src_offset_x: float = 0.0
	var src_offset_y: float = 0.0
	if canvas_aspect > src_aspect:
		inv_scale = float(src_w) / canvas_size.x
		var visible_h: float = canvas_size.y * inv_scale
		src_offset_y = (float(src_h) - visible_h) * 0.5
	else:
		inv_scale = float(src_h) / canvas_size.y
		var visible_w: float = canvas_size.x * inv_scale
		src_offset_x = (float(src_w) - visible_w) * 0.5
	# 同 _draw:debug 网格也按 grid_phase 偏移起点 + 向左/上扩展一格
	var y: int = int(round(grid_phase.y * float(cell))) - cell
	while y < int(canvas_size.y):
		var sy: int = clampi(
			int(src_offset_y + float(y) * inv_scale), 0, src_h - 1
		)
		var x: int = int(round(grid_phase.x * float(cell))) - cell
		while x < int(canvas_size.x):
			var sx: int = clampi(
				int(src_offset_x + float(x) * inv_scale), 0, src_w - 1
			)
			var color: Color = _source_image.get_pixel(sx, sy)
			# 与 _draw 主循环判定一致(包含 v_min/v_max + saturation 过滤)
			if (
				color.a >= density_threshold
				and color.v >= v_min_threshold
				and color.v <= v_max_threshold
				and color.s >= saturation_threshold
			):
				draw_circle(
					Vector2(x + cell * 0.5, y + cell * 0.5),
					1.0,
					Color(1.0, 0.0, 0.0, 0.6)
				)
			x += cell
		y += cell
