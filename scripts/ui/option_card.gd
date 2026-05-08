# 功能：选项卡片（OptionCard）—— 议题 B 纯文本选项的承载形态。
# 哲学锚点：
#   - 卡片的"浮起感"（z 轴上方）用 mosaic 字符阴影实现，与背景层 / SealPanel 同源。
#   - 不引入"高斯模糊暗块"等异质材质，所有视觉只用字 / 墨 / 纸 / 朱四样。
# 渲染层叠（_draw 一次绘制完毕，Godot 缓存）：
#   1. 阴影实色薄底 —— 卡片右下方 L 形带（左上光源），贴边深、向外渐变到 0
#   2. 阴影 mosaic 字符 —— 在阴影底上叠散落小字符,营造斑驳质感
#   3. 实色米白底 —— 卡片实体内部（inner rect，贴 OptionCard 左上角）
#   4. 淡墨边框 —— 卡片实体细线
#   5. 朱字主文本 —— 由内嵌 Label 子节点渲染（autowrap 处理换行）
#
# 几何说明（不对称布局）：
#   inner = Rect2(0, 0, size.x - shadow_extent, size.y - shadow_extent)  # 贴左上
#   阴影 L 形带 = inner 的右方 + 下方（不在左方、上方）
#   PanelContainer stylebox content_margin 对应不对称：左/上 = label_padding，右/下 = label_padding + shadow_extent
#
# 性能纪律（重要，参见 [[UI风格快速翻调_demo期进度]] § Phase 1.5 性能讨论）：
#   1. hover/pressed 只用 modulate 微调（GPU 端合成），绝不触发 mosaic 重绘
#   2. cell_size 用 6-8（不要更小，避免 draw call 翻倍）
#   3. 一次性绘制后 Godot 缓存，稳态零持续开销，仅事件切换时重绘一次
#   4. _bg_style / _border_style 在 _ready 中一次构建,_draw 复用,避免 GC 压力(P1 优化)
#
# 类名决策（重要）：
#   刻意不声明 class_name,避免与 main_game.gd 中 const OptionCard := preload(...) 同名冲突;
#   依据 user-level memory feedback_godot_classname_conflict —— Godot 中 class_name 与
#   const preload 同名会触发 LSP 错误。改造此文件时请保持 preload 模式而非 class_name 注册。

extends PanelContainer

signal pressed

# === 内容 ===
var option_id: String = ""
var selectable: bool = true

# === 颜色（与 main_game.gd UI_* 同源；颜色精调阶段可微调）===
# 设计决策:OptionCard 正文用通用深褐墨(与叙事正文同色),不用朱色 ——
# "伸手"语义由卡片形态(阴影+边框+米白底)承担,朱色严格只留给"继续"页脚。
var bg_color: Color = Color(0.957, 0.925, 0.847, 0.92)        # 米白纸面（比叙事面板 0.85 略实，焦点感）
var text_color: Color = Color(0.180, 0.161, 0.141, 1.0)        # 深褐墨（与 UI_TEXT_PRIMARY 同源,通用墨色）
var border_color: Color = Color(0.353, 0.310, 0.271, 0.45)     # 淡墨边框（细线提示）
var shadow_ink_color: Color = Color(0.180, 0.161, 0.141, 1.0)  # 深褐墨阴影字符 / 阴影底
var disabled_text_color: Color = Color(0.353, 0.310, 0.271, 0.5)

# === 几何（不对称布局,阴影只在右下）===
var shadow_extent: int = 9     # 阴影向右下扩张像素（仅右、下两个方向）
var label_padding_h: int = 16  # 卡片实体内左右 padding
var label_padding_v: int = 12  # 卡片实体内上下 padding
var border_width: int = 1
var corner_radius: int = 2

# === 阴影实色底参数 ===
var shadow_base_alpha: float = 0.22  # 贴卡片边缘处的阴影底色 alpha（向外渐变到 0）
var shadow_band_offset: int = 6      # 阴影 L 形带从 inner 角落的偏移（让阴影不贴角）

# === 阴影 mosaic 字符参数 ===
var noise_cell_size: int = 6   # 阴影字符 cell 像素步长（不要小于 6，避免 draw call 翻倍）
var noise_seed: int = 0        # 各卡片传不同 seed 产生各异斑驳模式
var ink_pool: PackedStringArray = PackedStringArray()  # 由外部注入，与背景同源词汇库

# === 内部状态 ===
var _label: Label = null
var _bg_font: Font = null
var _is_pressing: bool = false
# StyleBoxFlat 一次构建复用(在 _ready 中初始化,_draw 直接 draw_style_box),
# 避免每次 _draw 都 new 临时对象造成 GC 压力(Web 平台尤其敏感)
var _bg_style: StyleBoxFlat = null
var _border_style: StyleBoxFlat = null


func _ready() -> void:
	_bg_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_STOP

	# PanelContainer 的 panel stylebox 改为透明 + content_margin 不对称：
	#   左/上 = label_padding（inner 贴卡片左上角，无阴影）
	#   右/下 = label_padding + shadow_extent（给右下阴影 L 形带留空间）
	# 让自动布局把内嵌 Label 安排到 inner 实体内部（避开阴影区）。
	# PanelContainer 默认会画自己的 panel stylebox，我们用 StyleBoxEmpty 替代后由 _draw 接管。
	var transparent: StyleBoxEmpty = StyleBoxEmpty.new()
	transparent.content_margin_left = float(label_padding_h)
	transparent.content_margin_top = float(label_padding_v)
	transparent.content_margin_right = float(label_padding_h + shadow_extent)
	transparent.content_margin_bottom = float(label_padding_v + shadow_extent)
	add_theme_stylebox_override("panel", transparent)

	# 内嵌 Label 子节点处理文字渲染（autowrap 自动处理多行）
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", text_color)
	add_child(_label)

	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))

	# 一次性构建实色底 + 边框 stylebox(后续 _draw 直接复用,避免每次 new 造成 GC 压力)
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = bg_color
	_bg_style.corner_radius_top_left = corner_radius
	_bg_style.corner_radius_top_right = corner_radius
	_bg_style.corner_radius_bottom_left = corner_radius
	_bg_style.corner_radius_bottom_right = corner_radius

	if border_width > 0:
		_border_style = StyleBoxFlat.new()
		_border_style.draw_center = false
		_border_style.border_color = border_color
		_border_style.border_width_left = border_width
		_border_style.border_width_top = border_width
		_border_style.border_width_right = border_width
		_border_style.border_width_bottom = border_width
		_border_style.corner_radius_top_left = corner_radius
		_border_style.corner_radius_top_right = corner_radius
		_border_style.corner_radius_bottom_left = corner_radius
		_border_style.corner_radius_bottom_right = corner_radius

	queue_redraw()


# 功能：一次性配置选项卡片（文本 + 选项 ID + 字体 + selectable + 阴影 seed + 词汇池）。
# 参数 text:选项主文本（如"接下这趟药材送货"）
# 参数 id:option_id，pressed 信号触发后用于 main_game._on_option_pressed 路由
# 参数 font:文本字体（推荐项目主字体霞鹜文楷 Light）
# 参数 font_size:文本字号（推荐 17，与叙事正文同级）
# 参数 is_selectable:false 时显示淡墨字 + 不响应点击
# 参数 seed_val:阴影 noise seed（各卡片传不同值产生各异斑驳模式）
# 参数 tokens:阴影 mosaic 词汇库（与背景同源；空则不画阴影）
func set_option(
	text: String,
	id: String,
	font: Font,
	font_size: int,
	is_selectable: bool = true,
	seed_val: int = 0,
	tokens: PackedStringArray = PackedStringArray()
) -> void:
	option_id = id
	selectable = is_selectable
	noise_seed = seed_val
	if tokens.size() > 0:
		ink_pool = tokens
	# 节点可能在 add_child 前就调用 set_option（_label 还是 null）；await ready 等待
	if _label == null:
		await ready
	_label.text = text
	if font != null:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", font_size)
	if is_selectable:
		_label.add_theme_color_override("font_color", text_color)
	else:
		_label.add_theme_color_override("font_color", disabled_text_color)
	queue_redraw()


# === 鼠标交互（hover/pressed 不触发 _draw，只用 modulate）===

func _gui_input(event: InputEvent) -> void:
	if not selectable:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		# 阴影区不响应点击：只在卡片实体 inner rect 内 fire（贴左上,不对称布局）
		var inner: Rect2 = Rect2(
			0.0, 0.0,
			size.x - float(shadow_extent),
			size.y - float(shadow_extent)
		)
		if not inner.has_point(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_pressing = true
				modulate = Color(1.0, 1.0, 1.0, 0.85)
				accept_event()  # press 也 accept,避免事件冒泡到 NarrativePanel
			else:
				if _is_pressing:
					_is_pressing = false
					modulate = Color.WHITE
					pressed.emit()
					accept_event()


# 功能:hover 进入/离开 → modulate 微调亮度（不触发重绘）
# 说明:hover 时整张卡片（含阴影）轻微提亮,与"浮起被光照"的物理感呼应。
func _on_hover_changed(is_entered: bool) -> void:
	if not selectable:
		return
	if is_entered:
		modulate = Color(1.06, 1.06, 1.06, 1.0)
	else:
		_is_pressing = false
		modulate = Color.WHITE


# === 渲染 ===

# 功能:多层叠加渲染卡片(阴影实色底 + 阴影 mosaic 字符 + 实底 + 边框)。
# 说明:Label 文字由 PanelContainer 自动布局,本函数不处理。
func _draw() -> void:
	if _bg_font == null:
		_bg_font = get_theme_default_font()

	# 卡片实体 rect(贴左上,只在右下方向留 shadow_extent)
	var inner: Rect2 = Rect2(
		0.0, 0.0,
		size.x - float(shadow_extent),
		size.y - float(shadow_extent)
	)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	# === Layer 1:阴影实色薄底(右下方 L 形带,逐 px 渐变模拟距离衰减)===
	_draw_shadow_base(inner)

	# === Layer 2:阴影 mosaic 字符斑驳 —— 已停用(用户反馈视觉效果不理想)===
	# 接口保留,未来美术资源补全后可恢复;当前只用纯实色阴影底。
	# if ink_pool.size() > 0:
	# 	_draw_shadow_mosaic(inner)

	# === Layer 3:实色米白底(_bg_style 在 _ready 中一次构建,此处直接复用)===
	if _bg_style != null:
		draw_style_box(_bg_style, inner)

	# === Layer 4:淡墨边框(_border_style 在 _ready 中一次构建,此处直接复用)===
	if _border_style != null:
		draw_style_box(_border_style, inner)


# 功能:画右下方 L 形阴影实色薄底,贴卡片边缘 alpha 最深、向外渐变到 0。
# 算法:用 3 个 polygon + 顶点颜色实现 L 形阴影,衰减方向在边界连续(无接缝):
#   - 下方矩形:贴 inner 底边 alpha 最深,向下衰减到 0(沿 y 方向)
#   - 右方矩形:贴 inner 右边 alpha 最深,向右衰减到 0(沿 x 方向)
#   - 右下角矩形:左上顶点 alpha 最深,其他三角顶点 alpha 0(对角线性衰减,近似径向)
# 边界一致性:
#   - 下方矩形的右边(x=inner.right)= 右下角矩形的左边 → alpha 沿 y 同样衰减,无突变
#   - 右方矩形的下边(y=inner.bottom)= 右下角矩形的上边 → alpha 沿 x 同样衰减,无突变
# offset 让阴影从左/上"切入一点点"开始,模拟左上光源投影的自然边界。
func _draw_shadow_base(inner: Rect2) -> void:
	var ext: float = float(shadow_extent)
	var offset: float = float(shadow_band_offset)

	var c_max: Color = shadow_ink_color
	c_max.a = shadow_base_alpha
	var c_zero: Color = shadow_ink_color
	c_zero.a = 0.0

	# 下方矩形:顶 alpha 最深,底 alpha 0
	var bottom_pts: PackedVector2Array = PackedVector2Array([
		Vector2(inner.position.x + offset, inner.end.y),
		Vector2(inner.end.x, inner.end.y),
		Vector2(inner.end.x, inner.end.y + ext),
		Vector2(inner.position.x + offset, inner.end.y + ext),
	])
	var bottom_cols: PackedColorArray = PackedColorArray([
		c_max, c_max, c_zero, c_zero
	])
	draw_polygon(bottom_pts, bottom_cols)

	# 右方矩形:左 alpha 最深,右 alpha 0
	var right_pts: PackedVector2Array = PackedVector2Array([
		Vector2(inner.end.x, inner.position.y + offset),
		Vector2(inner.end.x + ext, inner.position.y + offset),
		Vector2(inner.end.x + ext, inner.end.y),
		Vector2(inner.end.x, inner.end.y),
	])
	var right_cols: PackedColorArray = PackedColorArray([
		c_max, c_zero, c_zero, c_max
	])
	draw_polygon(right_pts, right_cols)

	# 右下角矩形:仅左上顶点 alpha 最深,其他三角顶点 alpha 0
	# triangle fan 拆分为 (0,1,2) + (0,2,3),沿对角线 (0->2) 线性衰减(近似径向)。
	# 边界 alpha 与下方矩形右边 / 右方矩形下边一致,无接缝。
	var corner_pts: PackedVector2Array = PackedVector2Array([
		Vector2(inner.end.x, inner.end.y),
		Vector2(inner.end.x + ext, inner.end.y),
		Vector2(inner.end.x + ext, inner.end.y + ext),
		Vector2(inner.end.x, inner.end.y + ext),
	])
	var corner_cols: PackedColorArray = PackedColorArray([
		c_max, c_zero, c_zero, c_zero
	])
	draw_polygon(corner_pts, corner_cols)


# 功能:在右下方 L 形阴影区叠 mosaic 字符斑驳,营造"印泥不均"的质感。
# 算法:同源 SealPanel sin noise——
#   - cell 中心在 inner 内 / 不在右下方 L 区 / 距 inner 边缘 ≥ shadow_extent → 跳过
#   - 距 inner 边缘 dist 越小、noise n 越大 → alpha 越高
func _draw_shadow_mosaic(inner: Rect2) -> void:
	var cell: int = noise_cell_size
	var token_count: int = ink_pool.size()
	if token_count == 0:
		return

	var canvas_w: int = int(size.x)
	var canvas_h: int = int(size.y)

	var y: int = 0
	while y < canvas_h:
		var x: int = 0
		while x < canvas_w:
			var cx: float = float(x) + float(cell) * 0.5
			var cy: float = float(y) + float(cell) * 0.5

			# 单方向:只在 inner 右方或下方画(不在左、上)
			var is_below: bool = cy > inner.end.y
			var is_right: bool = cx > inner.end.x
			if not (is_below or is_right):
				x += cell
				continue
			# 跳过左上方对角(cy < inner.top 或 cx < inner.left,实际不会发生因为不对称布局)
			if cx < inner.position.x or cy < inner.position.y:
				x += cell
				continue

			# 到 inner 边缘的外向距离(只取右、下两个方向)
			var dist_x: float = max(cx - inner.end.x, 0.0) if is_right else 0.0
			var dist_y: float = max(cy - inner.end.y, 0.0) if is_below else 0.0
			var dist: float = max(dist_x, dist_y)
			if dist >= float(shadow_extent):
				x += cell
				continue

			# 距离衰减(贴边 1.0、外缘 0)
			var dist_factor: float = 1.0 - dist / float(shadow_extent)

			# noise(不相关频率组合)
			var n: float = (
				sin(float(x) * 0.137 + float(y) * 0.213
					+ float(noise_seed) * 1.7) * 0.5 + 0.5
			)
			var combined: float = n * dist_factor
			if combined < 0.30:
				x += cell
				continue

			var token_idx: int = (x * 3 + y * 7 + noise_seed) % token_count
			var token: String = ink_pool[token_idx]

			var c: Color = shadow_ink_color
			c.a = clampf(0.30 + 0.40 * combined, 0.0, 0.75)

			draw_string(
				_bg_font,
				Vector2(float(x), float(y + cell)),
				token,
				HORIZONTAL_ALIGNMENT_LEFT, -1, cell, c
			)
			x += cell
		y += cell
