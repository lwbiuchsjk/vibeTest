# 功能:文字马赛克的"动态层"——在指定 flow_regions 内 spawn 粒子,向下流动。
# 说明:与 TextMosaicBackground(静态层)配合,实现"动静分层":
#         - 静态层:5 万字符整张铺,只在地点切换时画一次
#         - 动态层(本节点):N 个粒子在主体区域内向下流,每帧更新位置 + redraw
#       粒子位置使用"源图坐标系"(0..image_size),与 flow_regions JSON 对齐,
#       渲染时再缩放到 canvas;响应式 resize 不需要重新 spawn 粒子。
# 设计依据:用户提议的 LLM-native 主体识别方案——flow_regions 由设计时 LLM 标注,
#       runtime 只消费 JSON,不做颜色/边缘启发式判断。
extends Control

# === 调试参数(开发期通过 Inspector 调节) ===

# 粒子总数(按 region.weight 比例分配到各区域)
# 注:region 是出生区,粒子流过整张画面后从 region 内重新出生。
#     总数过高(>500)会让出生区瞬间字符堆叠成色块,视觉糊感重——保持稀疏才看得清单字。
@export_range(0, 5000) var particle_count: int = 300
# 粒子下落速度区间(源图坐标系 px/s);区间大→个体差异强、视觉错落
# 源图 128 高 + 速度 8 ≈ 16s 从顶部走到底部,缓慢飘落
@export_range(0.0, 100.0) var speed_min: float = 4.0
@export_range(0.0, 100.0) var speed_max: float = 14.0
# 横向漂移最大速度(源图坐标系 px/s);每个粒子 vx 在 ±sway_max 内随机
# 0 = 严格垂直下落;>0 = 微微斜向飘动,破除"队列感"
@export_range(0.0, 20.0) var sway_max: float = 3.0
# 字号基准(单字符像素高度,canvas 像素)
@export_range(2, 24) var font_size: int = 8
# 字号扰动幅度:每个粒子在 font_size ± size_jitter 内随机字号
# 0 = 统一字号(僵硬);>0 = 大小错落,产生远近层次
@export_range(0, 8) var size_jitter: int = 3
# 整体透明度系数:让粒子比静态层稍突出但不抢眼;源图色 alpha 已是 1.0 时由本参数控制
@export_range(0.0, 1.0) var layer_alpha: float = 0.85
# 颜色模式:0=源图色 / 1=单色(用 mono_color)
@export var color_mode: int = 0
@export var mono_color: Color = Color.WHITE
# 调试:在每个 region 边界画红框
@export var debug_show_regions: bool = false

# === 水墨化色板(M1':色相敏感墨色映射;color_mode==0 时生效) ===
# 不是单色化,是滤镜:V 决定墨阶(灰度),H 决定暖冷偏向,S 决定偏色幅度。
# 原图色相信息保留,只是被重塑为水墨气质。

# 墨阶档数(2=黑白二值,5=焦/浓/淡/染/白 5 档;>5 渐变更细腻但水墨阶感弱)
@export_range(2, 16) var ink_levels: int = 5
# 暖冷偏色强度;饱和度 × 此值 = 实际混入墨色基色的比例。0=纯灰阶,1=完全偏到墨色基色
@export_range(0.0, 1.0) var ink_tint_strength: float = 0.4
# 暖墨基色(赭石,源图暖色调像素混入此色)
@export var ink_warm_color: Color = Color(0.659, 0.463, 0.353)
# 冷墨基色(松烟,源图冷色调像素混入此色)
@export var ink_cool_color: Color = Color(0.227, 0.282, 0.345)
# 暖色 H 锚点(0.08 ≈ 橙黄);源图色 H 越接近此值越"暖"
@export_range(0.0, 1.0) var ink_warm_anchor: float = 0.08

# === 粒子生命周期 alpha 衰减(M4:墨迹拖痕感) ===

# 0=平直 alpha,1=完全按曲线(出生 α=0,中段 α=1,底部 α=0);抛物线 1-(2t-1)²
@export_range(0.0, 1.0) var alpha_lifecycle_strength: float = 0.7

# === 低精度模拟感 / 失真套件(默认全关;保留 export 作为可选调试维度) ===

# 颜色量化档数(每个 RGB 分量保留几档);256=不量化(默认)
@export_range(2, 256) var color_levels: int = 256
# 位置 snap 网格(canvas 像素);0=不 snap(默认)
@export_range(0, 16) var pos_snap: int = 0
# 单粒子 alpha 随机扰动幅度;0=不抖动(默认)
@export_range(0.0, 1.0) var alpha_jitter: float = 0.0
# 每帧每粒子换 token 的概率;0=不替换(默认)
@export_range(0.0, 0.2) var glitch_chance: float = 0.0

# === 内部状态 ===

var _source_texture: Texture2D = null
# 缓存源图 Image,粒子取色用(避免 _draw 时频繁 GPU→CPU 拉取)
var _source_image: Image = null
var _text_tokens: PackedStringArray = PackedStringArray()
var _font: Font = null
# flow_regions JSON 解析后的数组,每项 {type, rect: [x,y,w,h], weight, note}
var _flow_regions: Array = []
# JSON 里声明的源图像素尺寸,用于把 region/粒子源图坐标映射到 canvas
var _image_size: Vector2 = Vector2.ZERO
# 粒子列表;每个粒子 {pos: Vector2(源图坐标), vel: float, region: Dictionary, token_idx: int}
var _particles: Array[Dictionary] = []


# 功能:节点初始化。
# 说明:取主题默认字体(中文渲染依赖项目主题已配 CJK);
#       mouse_filter=IGNORE 避免拦截 LeftOverlay 的鼠标事件;
#       resized 信号 connect:节点尺寸变化时 redraw(粒子源图坐标不变,只是渲染缩放变)。
func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


# 功能:设置源图,缓存其 Image 供粒子取色。
# 参数 texture:与静态层共享同一张 Texture2D。
func set_source_image(texture: Texture2D) -> void:
	_source_texture = texture
	_source_image = null
	if texture != null:
		_source_image = texture.get_image()
	queue_redraw()


# 功能:设置文字材料数组。
# 参数 tokens:循环填充用的文字 token 数组(粒子 token_idx 从中取模)。
func set_text_tokens(tokens: PackedStringArray) -> void:
	_text_tokens = tokens
	queue_redraw()


# 功能:设置流动区域 + 源图尺寸,触发粒子 spawn。
# 参数 regions:JSON.flow_regions 数组(每项含 type/rect/weight/note)。
# 参数 image_size:JSON.image_size,用于映射粒子源图坐标 → canvas 坐标。
# 说明:每次调用都重新 spawn 全部粒子(粒子数随 particle_count + region weight 重算)。
func set_flow_data(regions: Array, image_size: Vector2) -> void:
	_flow_regions = regions
	_image_size = image_size
	_spawn_particles()
	queue_redraw()


# 功能:清空粒子(地点无 flow_regions JSON 时调用,避免残留旧粒子)。
func clear_flow_data() -> void:
	_flow_regions.clear()
	_image_size = Vector2.ZERO
	_particles.clear()
	queue_redraw()


# 功能:按 region.weight 比例分配粒子数,在每个 region 内随机生成粒子初始位置。
# 说明:weight 总和归一化;粒子均匀分布在 region.rect 内,初始速度在 [speed_min, speed_max] 随机。
func _spawn_particles() -> void:
	_particles.clear()
	if _flow_regions.is_empty():
		return
	if _image_size.x <= 0.0 or _image_size.y <= 0.0:
		push_warning("TextMosaicParticles: image_size 无效,无法 spawn 粒子")
		return

	var total_weight: float = 0.0
	for region: Dictionary in _flow_regions:
		total_weight += float(region.get("weight", 1.0))
	if total_weight <= 0.0:
		return

	for region: Dictionary in _flow_regions:
		var w: float = float(region.get("weight", 1.0))
		var n: int = int(round(float(particle_count) * w / total_weight))
		for i in n:
			_particles.append(_make_particle(region))


# 功能:在 region 内生成一个粒子,初始位置在 region 内均匀分布(避免开局粒子从顶部同步下落)。
# 说明:每个粒子有独立的 size / vel(2D),让群体有个体差异、视觉错落。
func _make_particle(region: Dictionary) -> Dictionary:
	var rect_data: Array = region.get("rect", [0, 0, 0, 0])
	var rx: float = float(rect_data[0])
	var ry: float = float(rect_data[1])
	var rw: float = float(rect_data[2])
	var rh: float = float(rect_data[3])
	return {
		"pos": Vector2(rx + randf() * rw, ry + randf() * rh),
		"vel": Vector2(
			randf_range(-sway_max, sway_max),
			randf_range(speed_min, speed_max)
		),
		"rect": [rx, ry, rw, rh],
		"size": _random_size(),
		"token_idx": randi()
	}


# 功能:在 font_size ± size_jitter 内随机生成单粒子字号。
func _random_size() -> int:
	if size_jitter <= 0:
		return font_size
	return clampi(font_size + randi_range(-size_jitter, size_jitter), 2, 24)


# 功能:每帧更新粒子位置 + 触发 redraw。
# 说明:流动模型是"长程下落"——粒子从 region 内出生,持续向下流过整张画面,
#       直到 pos.y 超出 image_size.y 才回收(回 region 内重新出生)。
#       这样视觉上是"主体在持续散落字符到画面底部",而不是窄带内抖动。
# 实现注意:Vector2 是值类型,Dictionary[] 取出的是副本,直接 p["pos"].y += x 不写回。
#       必须 read-modify-write:取出 → 修改 → 整个 pos 赋回 dict。
func _process(delta: float) -> void:
	if _particles.is_empty():
		return
	if _image_size.y <= 0.0:
		return
	var bottom_limit: float = _image_size.y
	for p: Dictionary in _particles:
		var pos: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		pos += vel * delta
		if pos.y > bottom_limit:
			# 出底 → 回 region 内重新出生;同时刷新 size/vel/token,让重生粒子也有新差异
			var rect: Array = p["rect"]
			var rx: float = float(rect[0])
			var ry: float = float(rect[1])
			var rw: float = float(rect[2])
			var rh: float = float(rect[3])
			pos = Vector2(rx + randf() * rw, ry + randf() * rh)
			p["vel"] = Vector2(
				randf_range(-sway_max, sway_max),
				randf_range(speed_min, speed_max)
			)
			p["size"] = _random_size()
			p["token_idx"] = randi()
		elif glitch_chance > 0.0 and randf() < glitch_chance:
			# 失真:小概率字符替换,像 CRT 坏点闪烁
			p["token_idx"] = randi()
		p["pos"] = pos
	queue_redraw()


# 功能:渲染所有粒子。
# 说明:粒子源图坐标 → canvas 坐标缩放;颜色取自源图对应位置;layer_alpha 控制整层透明度。
func _draw() -> void:
	if _particles.is_empty() or _text_tokens.is_empty() or _source_image == null:
		return
	if _image_size.x <= 0.0 or _image_size.y <= 0.0:
		return
	var canvas_size: Vector2 = size
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		return
	var scale_x: float = canvas_size.x / _image_size.x
	var scale_y: float = canvas_size.y / _image_size.y
	var src_w: int = _source_image.get_width()
	var src_h: int = _source_image.get_height()
	var token_count: int = _text_tokens.size()

	for p: Dictionary in _particles:
		var pos: Vector2 = p["pos"]
		var p_size: int = int(p["size"])
		# 源图取色:把粒子源图坐标(0..image_size)映射到 Image 像素(0..src_w/h)
		var src_x: int = clampi(
			int(pos.x * src_w / _image_size.x), 0, src_w - 1
		)
		var src_y: int = clampi(
			int(pos.y * src_h / _image_size.y), 0, src_h - 1
		)
		var color: Color = _source_image.get_pixel(src_x, src_y)
		# 水墨化色板映射(M1':color_mode==0 时按色相敏感映射,1=单色 mono_color 不动)
		var draw_color: Color = (
			_apply_ink_palette(color) if color_mode == 0 else mono_color
		)
		# 失真:颜色量化(默认关闭;保留作为可选调试)
		if color_levels < 256:
			draw_color = _quantize_color(draw_color)
		# 失真:alpha 抖动(默认关闭)
		var a_jitter: float = (
			randf_range(-alpha_jitter, 0.0) if alpha_jitter > 0.0 else 0.0
		)
		# 粒子生命周期 alpha 衰减(M4):从 region 顶到 image 底归一化进度,
		# 抛物线 1 - (2t-1)² → 中段最浓、两端淡
		var rect_data: Array = p["rect"]
		var ry: float = float(rect_data[1])
		var life_span: float = max(_image_size.y - ry, 1.0)
		var life_t: float = clampf((pos.y - ry) / life_span, 0.0, 1.0)
		var lifecycle_alpha: float = 1.0 - pow(2.0 * life_t - 1.0, 2.0)
		var alpha_factor: float = lerpf(
			1.0, lifecycle_alpha, alpha_lifecycle_strength
		)
		draw_color.a *= clampf(layer_alpha + a_jitter, 0.0, 1.0) * alpha_factor
		# baseline 偏移使用粒子自身字号,大字粒子位置略低、小字略高
		var canvas_pos: Vector2 = Vector2(
			pos.x * scale_x, pos.y * scale_y + p_size
		)
		# 失真:位置 snap → 粒子渲染落到 N 像素网格,下落呈格子步进感
		if pos_snap > 0:
			canvas_pos = Vector2(
				round(canvas_pos.x / pos_snap) * pos_snap,
				round(canvas_pos.y / pos_snap) * pos_snap
			)
		var token: String = _text_tokens[int(p["token_idx"]) % token_count]
		draw_string(
			_font,
			canvas_pos,
			token,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			p_size,
			draw_color
		)

	if debug_show_regions:
		_draw_debug_regions(scale_x, scale_y)


# 功能:把源图色按"色相敏感的水墨色板"重新映射(M1' 核心算法)。
# 说明:不是单色化——保留原图色相信息,只是被重塑为水墨气质。
#       V → 量化到 ink_levels 档墨阶(基础灰阶)
#       H → 决定暖冷偏向(暖色混入 ink_warm_color,冷色混入 ink_cool_color)
#       S → 偏色幅度(高饱和偏色重,低饱和接近中性墨)
#       alpha 不动。
func _apply_ink_palette(c: Color) -> Color:
	# V 量化到 ink_levels 档(0=焦墨黑,1=飞白)
	var levels: float = float(maxi(ink_levels, 2))
	var ink_v: float = round(c.v * (levels - 1.0)) / (levels - 1.0)
	var base_gray: Color = Color(ink_v, ink_v, ink_v, c.a)

	# H 与暖锚点的圆形距离(色相是环形 [0,1) 的,用 min 处理跨 0 边界)
	var hue: float = c.h
	var dist: float = abs(hue - ink_warm_anchor)
	if dist > 0.5:
		dist = 1.0 - dist
	# warmth: 1=最暖(贴锚点), 0=最冷(对锚点 180°)
	var warmth: float = 1.0 - dist * 2.0

	# 选偏色基色:暖时混入暖墨,冷时混入冷墨
	var tint_color: Color = ink_warm_color if warmth > 0.5 else ink_cool_color
	# 偏色强度:饱和度 × 强度系数(饱和度低的近中性墨,饱和度高的偏色重)
	var tint_strength: float = c.s * ink_tint_strength

	var result: Color = base_gray.lerp(tint_color, tint_strength)
	result.a = c.a
	return result


# 功能:把颜色每个 RGB 分量量化到 color_levels 档,产生 LED 矩阵 / 老调色板的 banding 感。
# 说明:alpha 不量化(避免硬切),仅量化色相亮度。**保留作为可选失真维度,默认关闭**。
func _quantize_color(c: Color) -> Color:
	var lvl: float = float(color_levels - 1)
	if lvl <= 0.0:
		return c
	return Color(
		round(c.r * lvl) / lvl,
		round(c.g * lvl) / lvl,
		round(c.b * lvl) / lvl,
		c.a
	)


# 功能:在每个 region 边界画红框,验证区域定义对不对。
func _draw_debug_regions(scale_x: float, scale_y: float) -> void:
	for region: Dictionary in _flow_regions:
		var rect_data: Array = region.get("rect", [0, 0, 0, 0])
		var canvas_rect: Rect2 = Rect2(
			float(rect_data[0]) * scale_x,
			float(rect_data[1]) * scale_y,
			float(rect_data[2]) * scale_x,
			float(rect_data[3]) * scale_y
		)
		draw_rect(canvas_rect, Color(1.0, 0.0, 0.0, 0.4), false, 2.0)
