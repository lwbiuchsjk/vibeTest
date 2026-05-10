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

# === 副字印章群（议题 E 子项 1/2/6.1：cost + check 视觉承担位）===
# 设计决策（2026-05-10 议题 E 组 1 收口 + 二轮调整）：
#   - 复用 SealPanel "中央大字 + 角落小字" 范式但内嵌在 _draw 中绘制（方案 B：不改节点结构）
#   - cost 多印分立：每种资源一个独立印章 [精 1][力 2]，墨印底
#   - check 单印按属性区分主字（武/艺/识/资）—— 暴露鉴定属性，但仍不暴露 DC
#   - check 改朱印（朱色"破例"作鉴定醒目提示）；朱色比 UI_ACCENT_ZHU 调暗 + alpha 略低，避免大面积朱底刺眼
#   - 排序：cost 在前 check 在后，由调用方在 seals 列表中按顺序构造
#   - 副字字号 13（数字醒目，2026-05-10 调整）
var seals: Array = []                   # 印章定义列表，每项 {main, value, tone="ink"|"zhu"}
var seal_main_font: Font = null         # 印章主字字体（推荐青鸟美黑，由调用方注入）
var seal_sub_font: Font = null          # 印章副字字体（推荐宋体 Medium，由调用方注入）
var seal_main_font_size: int = 18       # 印章主字字号（约状态栏 22 的 64%）
var seal_sub_font_size: int = 15        # 印章副字字号（数字醒目，2026-05-10 调整）
var seal_padding: Vector2 = Vector2(6.0, 4.0)
var seal_separation: int = 4            # 印章间间距
var seal_text_gap: int = 8              # 主文本与印章群之间的最小间距
var seal_corner_radius: int = 2
var seal_border_width: int = 1
# 印章底色按 tone 区分：ink (cost 墨印) vs zhu (check 朱印)
var seal_bg_color: Color = Color(0.220, 0.200, 0.170, 0.92)   # ink 墨印底，与 SealPanel 同源
var seal_zhu_bg_color: Color = Color(0.55, 0.17, 0.15, 0.88)  # zhu 朱印底（比 #B22E26 调暗 + alpha 0.88）
var seal_ink_color: Color = Color(0.050, 0.045, 0.035, 1.0)
var seal_text_white: Color = Color(0.957, 0.925, 0.847, 1.0)
var seal_noise_cell: int = 4
var seal_ink_pool: PackedStringArray = PackedStringArray([
	"命", "力", "金", "心", "回", "岁", "年", "气",
	"神", "魂", "天", "人", "土", "水", "火", "木"
])

# === 印章主字 / 副字锚点（提取到顶部便于调参，2026-05-10）===
# anchor x/y 是相对印章 rect 的 (0-1) 比例。SealPanel 范式：
#   - 有副字时主字偏左居中（给右下角副字让位），无副字时整体居中
#   - 副字默认右下角（模拟传统印章"中央大字 + 角落小字"）
var seal_main_anchor: Vector2 = Vector2(0.32, 0.50)         # 有副字时主字锚点
var seal_main_anchor_no_sub: Vector2 = Vector2(0.50, 0.50)  # 无副字时主字锚点（如朱印【鉴】）
var seal_sub_anchor: Vector2 = Vector2(0.78, 0.47)          # 副字锚点（右下角）

# === 鉴定结果中央大印（议题 E 子项 6.2，2026-05-10）===
# 玩家点击 check 选项后：
#   1. 引擎结算出 check.pass (success/fail)
#   2. 当前 OptionCard 中央叠一枚大印章（成功 = 墨色 / 失败 = 朱色）
#   3. 其他 OptionCard 由 main_game 调用方 modulate 灰化
#   4. 0.8s 强制等待后推进 outcome（main_game 流程层负责）
# 失败朱色 #6B1E1A 比朱印 #8C2B26 偏暗 + 偏紫红，靠 V 差异让朱印 check 在失败大印的"周边"仍可读。
var check_result_state: String = ""                          # "" / "success" / "fail"
# 大印"成功 / 失败"字体可独立指定（默认 null = fallback 到 seal_main_font 即青鸟美黑）。
# 若引入隶书 / 草书等专用字体，由调用方注入。
var center_seal_text_font: Font = null
var center_seal_main_font_size: int = 56                     # 大印字号（覆盖整张卡，字号需更大）
var center_seal_padding: Vector2 = Vector2(12.0, 6.0)
var center_seal_noise_cell: int = 8                          # 大印斑驳 cell 步长（覆盖更大区域，cell 略大）
var center_seal_fail_bg_color: Color = Color(0.42, 0.12, 0.10, 0.96)  # 失败朱色（偏紫红 #6B1E1A）
var center_seal_corner_radius: int = 2
var center_seal_border_width: int = 2
# Reveal 动画：从右到左快速展开（"被盖印"的物理动作）
var center_seal_reveal_duration: float = 0.10               # 动画时长（s）
var _center_seal_reveal_progress: float = 0.0                # 0 → 1，由 Tween 推进
var _reveal_tween: Tween = null

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


# 功能：一次性配置选项卡片（文本 + 选项 ID + 字体 + selectable + 阴影 seed + 词汇池 + 副字印章群）。
# 参数 text:选项主文本（如"接下这趟药材送货"）
# 参数 id:option_id，pressed 信号触发后用于 main_game._on_option_pressed 路由
# 参数 font:文本字体（推荐项目主字体霞鹜文楷 Light）
# 参数 font_size:文本字号（推荐 17，与叙事正文同级）
# 参数 is_selectable:false 时显示淡墨字 + 不响应点击
# 参数 seed_val:阴影 noise seed（各卡片传不同值产生各异斑驳模式）
# 参数 tokens:阴影 mosaic 词汇库（与背景同源；空则不画阴影）
# 参数 seal_list:副字印章群（每项 {main, value}，cost 在前 check 在后）
# 参数 s_main_font / s_sub_font:印章主字 / 副字字体（调用方注入，避免 OptionCard 直接 preload）
func set_option(
	text: String,
	id: String,
	font: Font,
	font_size: int,
	is_selectable: bool = true,
	seed_val: int = 0,
	tokens: PackedStringArray = PackedStringArray(),
	seal_list: Array = [],
	s_main_font: Font = null,
	s_sub_font: Font = null
) -> void:
	option_id = id
	selectable = is_selectable
	noise_seed = seed_val
	if tokens.size() > 0:
		ink_pool = tokens
	seals = seal_list
	if s_main_font != null:
		seal_main_font = s_main_font
	if s_sub_font != null:
		seal_sub_font = s_sub_font
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
	# 印章群存在时调整 PanelContainer 右侧 content_margin，给印章群让出空间
	_refresh_seal_layout()
	queue_redraw()


# 功能：设置/清除鉴定结果大印（议题 E 子项 6.2 + 二轮调整：覆盖整张 OptionCard + reveal 动画，2026-05-10）。
# 参数 state: "" 清除（恢复正常）/ "success" / "fail"
# 说明：state != "" 时启动 Tween 从右到左 reveal 大印；state == "" 时停止动画 + 清状态。
#       调用方（main_game._show_check_result_feedback）负责整体反馈窗口时长 + 清理 OptionCard。
func set_check_result(state: String) -> void:
	check_result_state = state
	# 停止旧的 reveal tween（避免叠加）
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	if state == "":
		_center_seal_reveal_progress = 0.0
		queue_redraw()
		return
	# 启动 reveal 动画：0 → 1，时长 center_seal_reveal_duration
	_center_seal_reveal_progress = 0.0
	_reveal_tween = create_tween()
	_reveal_tween.tween_method(_set_reveal_progress, 0.0, 1.0, center_seal_reveal_duration)


# 功能：Tween 回调，更新 reveal 进度并触发重绘。
func _set_reveal_progress(p: float) -> void:
	_center_seal_reveal_progress = p
	queue_redraw()


# 功能：根据 seals 重计算印章群占宽，重设 PanelContainer 右侧 content_margin + 最小高度。
# 说明：印章绘制在 _draw 中完成（不是子节点），但 Label 的 autowrap 需通过 content_margin 让出右侧空间
#       才能避免主文本与印章群重叠。
func _refresh_seal_layout() -> void:
	var seal_total_w: float = _calc_seals_total_width()
	var seal_h: float = _calc_seal_height()

	# 重建 PanelContainer 透明 stylebox：
	#   左 = label_padding（不变）
	#   上 = label_padding（不变）
	#   右 = label_padding + shadow_extent + (seal_total_w + seal_text_gap, 仅当有印章)
	#   下 = label_padding + shadow_extent（不变）
	var transparent: StyleBoxEmpty = StyleBoxEmpty.new()
	transparent.content_margin_left = float(label_padding_h)
	transparent.content_margin_top = float(label_padding_v)
	var right_pad: float = float(label_padding_h + shadow_extent)
	if seals.size() > 0:
		right_pad += seal_total_w + float(seal_text_gap)
	transparent.content_margin_right = right_pad
	transparent.content_margin_bottom = float(label_padding_v + shadow_extent)
	add_theme_stylebox_override("panel", transparent)

	# 印章高度若大于单行 Label 高度，需保证卡片不会被印章溢出（custom_minimum_size.y 兜底）
	if seals.size() > 0:
		var min_h: float = seal_h + float(label_padding_v) * 2.0 + float(shadow_extent)
		custom_minimum_size = Vector2(custom_minimum_size.x, max(custom_minimum_size.y, min_h))
	update_minimum_size()


# 功能：估算印章群总宽（多个印章 + 间距）。
func _calc_seals_total_width() -> float:
	if seals.size() == 0 or seal_main_font == null:
		return 0.0
	var total: float = 0.0
	for i in range(seals.size()):
		var item: Dictionary = seals[i]
		total += _calc_seal_width(str(item.get("main", "")), str(item.get("value", "")))
		if i > 0:
			total += float(seal_separation)
	return total


# 功能：估算单个印章宽度（主字 + 副字 + padding + 主副字间隙）。
func _calc_seal_width(main_text: String, sub_text: String) -> float:
	if seal_main_font == null:
		return 0.0
	var m_w: float = seal_main_font.get_string_size(
		main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, seal_main_font_size
	).x
	var s_w: float = 0.0
	if seal_sub_font != null and sub_text != "":
		s_w = seal_sub_font.get_string_size(
			sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, seal_sub_font_size
		).x
	return m_w + s_w + seal_padding.x * 2.0 + 6.0  # 6 = 主副字之间最小间隙


# 功能：估算印章高度（主字字号 + 上下 padding）。
func _calc_seal_height() -> float:
	return float(seal_main_font_size) + seal_padding.y * 2.0 + 4.0  # 4 = 行高余量


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

	# === Layer 5:副字印章群（cost + check 视觉承担位）===
	# 在 inner rect 右侧从右往左排列；垂直居中于 inner 高度。
	# 不绘制为子节点，复制 SealPanel 4 层渲染逻辑（实色墨底 + 斑驳层 + 边框 + 主字+副字）。
	if seals.size() > 0 and seal_main_font != null:
		_draw_seals(inner)

	# === Layer 6:鉴定结果大印（议题 E 子项 6.2 + 二轮调整：覆盖整张 + reveal 动画）===
	# 玩家点击 check 选项后展示，由 main_game 控制总时长 + outcome 推进。
	# 大印覆盖整个 OptionCard inner，从右到左 reveal 动画——"被盖印"的物理动作。
	if check_result_state != "" and seal_main_font != null and _center_seal_reveal_progress > 0.0:
		_draw_check_result_center_seal(inner)

	# === Layer 7:朱印 check 重绘（保证大印之上始终可见）===
	# Layer 5 印章群已画一次，Layer 6 大印 reveal 时会覆盖印章群区域；
	# Layer 7 仅重绘 tone="zhu" 的印章（朱印【鉴】/【武】/【识】等），cost 印章被大印盖住即可。
	# 朱印 (#8C2B26) 在失败大印底 (#6B1E1A) 上靠 V 阶差异保持可读。
	if check_result_state != "" and seals.size() > 0 and seal_main_font != null:
		_draw_zhu_seals_overlay(inner)


# 功能：在 inner rect 右侧绘制印章群（从右往左排，垂直居中）。
func _draw_seals(inner: Rect2) -> void:
	var seal_h: float = _calc_seal_height()
	var seal_y: float = inner.position.y + (inner.size.y - seal_h) * 0.5
	# 右侧贴边偏移（不要紧贴 inner 边框，留 4px 视觉缓冲）
	var cursor_x: float = inner.end.x - 4.0
	for i in range(seals.size() - 1, -1, -1):
		var item: Dictionary = seals[i]
		var m_text: String = str(item.get("main", ""))
		var v_text: String = str(item.get("value", ""))
		var tone: String = str(item.get("tone", "ink"))
		var seal_w: float = _calc_seal_width(m_text, v_text)
		cursor_x -= seal_w
		_draw_single_seal(
			Rect2(cursor_x, seal_y, seal_w, seal_h),
			m_text, v_text,
			noise_seed * 31 + i,  # 各印章独立 seed，确保斑驳模式各异
			tone
		)
		cursor_x -= float(seal_separation)


# 功能：绘制单个印章（实色底 + 斑驳层 + 边框 + 主字 + 副字）。
# 说明：复制 SealPanel _draw 主体逻辑；与 SealPanel 视觉同源（共享色板 / 斑驳算法 / 词汇池）。
# 参数 tone：印章色调，"ink"（墨印，默认）或 "zhu"（朱印，check 鉴定醒目提示）
func _draw_single_seal(rect: Rect2, m_text: String, v_text: String, seed_val: int, tone: String = "ink") -> void:
	var current_bg: Color = seal_zhu_bg_color if tone == "zhu" else seal_bg_color
	# Layer A：实色底
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = current_bg
	bg.corner_radius_top_left = seal_corner_radius
	bg.corner_radius_top_right = seal_corner_radius
	bg.corner_radius_bottom_left = seal_corner_radius
	bg.corner_radius_bottom_right = seal_corner_radius
	draw_style_box(bg, rect)

	# Layer B：斑驳墨层（在印章 inner 内 sin noise 驱动字符密度 + alpha）
	var pad_inner: int = 2
	var s_inner: Rect2 = Rect2(
		rect.position + Vector2(pad_inner, pad_inner),
		rect.size - Vector2(pad_inner * 2, pad_inner * 2)
	)
	var cell: int = seal_noise_cell
	var token_count: int = seal_ink_pool.size()
	if token_count > 0 and s_inner.size.x > 0.0 and s_inner.size.y > 0.0:
		var y: int = 0
		while y < int(s_inner.size.y):
			var x: int = 0
			while x < int(s_inner.size.x):
				var n: float = (
					sin(float(x) * 0.137 + float(y) * 0.213
						+ float(seed_val) * 1.7) * 0.5 + 0.5
				)
				if n > 0.25:
					var token_idx: int = (x * 3 + y * 7 + seed_val) % token_count
					var token: String = seal_ink_pool[token_idx]
					var c: Color = seal_ink_color
					c.a = 0.15 + n * 0.55
					draw_string(
						_bg_font,
						s_inner.position + Vector2(x, y + cell - 1),
						token,
						HORIZONTAL_ALIGNMENT_LEFT, -1, cell, c
					)
				x += cell
			y += cell

	# Layer C：边框（与底色同色，仅占空间，无视觉对比）
	var bd: StyleBoxFlat = StyleBoxFlat.new()
	bd.draw_center = false
	bd.border_color = current_bg
	bd.border_width_left = seal_border_width
	bd.border_width_top = seal_border_width
	bd.border_width_right = seal_border_width
	bd.border_width_bottom = seal_border_width
	bd.corner_radius_top_left = seal_corner_radius
	bd.corner_radius_top_right = seal_corner_radius
	bd.corner_radius_bottom_left = seal_corner_radius
	bd.corner_radius_bottom_right = seal_corner_radius
	draw_style_box(bd, rect)

	# Layer D：主字 + 副字（反白米白色）
	# 主字：副字存在时用 seal_main_anchor（偏左居中给副字让位），否则用 seal_main_anchor_no_sub（整体居中）
	var has_sub: bool = seal_sub_font != null and v_text != ""
	if m_text != "" and seal_main_font != null:
		var main_size: Vector2 = seal_main_font.get_string_size(
			m_text, HORIZONTAL_ALIGNMENT_LEFT, -1, seal_main_font_size
		)
		var anchor: Vector2 = seal_main_anchor if has_sub else seal_main_anchor_no_sub
		var main_pos: Vector2 = Vector2(
			rect.position.x + rect.size.x * anchor.x - main_size.x * 0.5,
			rect.position.y + rect.size.y * anchor.y + main_size.y * 0.30
		)
		draw_string(
			seal_main_font, main_pos, m_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, seal_main_font_size, seal_text_white
		)
	if has_sub:
		var sub_size: Vector2 = seal_sub_font.get_string_size(
			v_text, HORIZONTAL_ALIGNMENT_LEFT, -1, seal_sub_font_size
		)
		var sub_pos: Vector2 = Vector2(
			rect.position.x + rect.size.x * seal_sub_anchor.x - sub_size.x * 0.5,
			rect.position.y + rect.size.y * seal_sub_anchor.y + sub_size.y * 0.30
		)
		draw_string(
			seal_sub_font, sub_pos, v_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, seal_sub_font_size, seal_text_white
		)


# 功能：绘制鉴定结果大印（议题 E 子项 6.2 + 二轮调整：整张覆盖 + reveal 动画，2026-05-10）。
# 说明：大印覆盖整个 OptionCard inner，按 _center_seal_reveal_progress (0→1) 从右到左展开。
#       文字按 inner 中心居中（reveal 推进到中心覆盖时才完整显示）。
#       朱印 check 由 Layer 7 重绘叠在大印之上，保持始终可见。
func _draw_check_result_center_seal(inner: Rect2) -> void:
	var progress: float = clampf(_center_seal_reveal_progress, 0.0, 1.0)
	if progress <= 0.0:
		return
	# 大印 rect 从 inner 右侧开始按 progress 横向展开到 inner 左侧
	var rect_w: float = inner.size.x * progress
	var rect: Rect2 = Rect2(
		inner.end.x - rect_w, inner.position.y,
		rect_w, inner.size.y
	)

	var is_success: bool = check_result_state == "success"
	var current_bg: Color = seal_bg_color if is_success else center_seal_fail_bg_color
	var text: String = "成功" if is_success else "失败"

	# Layer A：实色底
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = current_bg
	bg.corner_radius_top_left = center_seal_corner_radius
	bg.corner_radius_top_right = center_seal_corner_radius
	bg.corner_radius_bottom_left = center_seal_corner_radius
	bg.corner_radius_bottom_right = center_seal_corner_radius
	draw_style_box(bg, rect)

	# Layer B：斑驳层（cell 步长 7，比印章群 4 大，适配大字号）
	var pad_inner: int = 3
	var s_inner: Rect2 = Rect2(
		rect.position + Vector2(pad_inner, pad_inner),
		rect.size - Vector2(pad_inner * 2, pad_inner * 2)
	)
	var cell: int = center_seal_noise_cell
	var token_count: int = seal_ink_pool.size()
	var seed_val: int = noise_seed * 17 + (1 if is_success else 2)
	if token_count > 0 and s_inner.size.x > 0.0 and s_inner.size.y > 0.0:
		var y: int = 0
		while y < int(s_inner.size.y):
			var x: int = 0
			while x < int(s_inner.size.x):
				var n: float = (
					sin(float(x) * 0.137 + float(y) * 0.213
						+ float(seed_val) * 1.7) * 0.5 + 0.5
				)
				if n > 0.30:
					var token_idx: int = (x * 3 + y * 7 + seed_val) % token_count
					var token: String = seal_ink_pool[token_idx]
					var c: Color = seal_ink_color
					c.a = 0.10 + n * 0.40
					draw_string(
						_bg_font,
						s_inner.position + Vector2(x, y + cell - 1),
						token,
						HORIZONTAL_ALIGNMENT_LEFT, -1, cell, c
					)
				x += cell
			y += cell

	# Layer C：边框（与底色同色，仅占空间）
	var bd: StyleBoxFlat = StyleBoxFlat.new()
	bd.draw_center = false
	bd.border_color = current_bg
	bd.border_width_left = center_seal_border_width
	bd.border_width_top = center_seal_border_width
	bd.border_width_right = center_seal_border_width
	bd.border_width_bottom = center_seal_border_width
	bd.corner_radius_top_left = center_seal_corner_radius
	bd.corner_radius_top_right = center_seal_corner_radius
	bd.corner_radius_bottom_left = center_seal_corner_radius
	bd.corner_radius_bottom_right = center_seal_corner_radius
	draw_style_box(bd, rect)

	# Layer D：反白大字（"成功" / "失败"），按 inner 中心居中（不随 rect 漂移）。
	# 仅当 reveal rect 横向覆盖到文字 x 范围时绘制——reveal 早期仅显示底色 + 斑驳，
	# reveal 推进越过文字位置后文字"出现"——视觉上像"印泥从右往左盖到字"。
	# 优先使用 center_seal_text_font（隶书/草书等专用字体），未注入则 fallback 到 seal_main_font（青鸟美黑）。
	var text_font: Font = center_seal_text_font if center_seal_text_font != null else seal_main_font
	if text_font != null:
		var text_size: Vector2 = text_font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, center_seal_main_font_size
		)
		var text_pos: Vector2 = Vector2(
			inner.position.x + (inner.size.x - text_size.x) * 0.5,
			inner.position.y + inner.size.y * 0.50 + text_size.y * 0.30
		)
		# reveal rect 左边界已覆盖到文字左边界时才绘制（避免文字"露出在大印之外"的破绽）
		if rect.position.x <= text_pos.x:
			draw_string(
				text_font, text_pos, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, center_seal_main_font_size, seal_text_white
			)


# 功能：仅重绘 tone="zhu" 的印章（朱印 check），叠在大印之上保证始终可见。
# 说明：议题 E 子项 6.2 二轮调整——大印覆盖整张 OptionCard，朱印 check 必须保留可见。
#       cost 印章（ink）被大印盖住即可，不重绘。位置算法与 _draw_seals 完全一致（保持像素对齐）。
func _draw_zhu_seals_overlay(inner: Rect2) -> void:
	var seal_h: float = _calc_seal_height()
	var seal_y: float = inner.position.y + (inner.size.y - seal_h) * 0.5
	var cursor_x: float = inner.end.x - 4.0
	for i in range(seals.size() - 1, -1, -1):
		var item: Dictionary = seals[i]
		var m_text: String = str(item.get("main", ""))
		var v_text: String = str(item.get("value", ""))
		var tone: String = str(item.get("tone", "ink"))
		var seal_w: float = _calc_seal_width(m_text, v_text)
		cursor_x -= seal_w
		if tone == "zhu":
			_draw_single_seal(
				Rect2(cursor_x, seal_y, seal_w, seal_h),
				m_text, v_text,
				noise_seed * 31 + i,
				tone
			)
		cursor_x -= float(seal_separation)


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
