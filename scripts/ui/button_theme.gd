extends RefCounted
## 按钮主题工具库。
## 提供命名预设和自定义配置两种方式，统一生成 Button 的四态 StyleBoxFlat 样式，
## 消除各场景中重复的 StyleBox 样板代码。

# ── 预设名常量 ──
const PRESET_DEFAULT := "default"          # 常规选项：深灰蓝
const PRESET_BET := "bet"                  # 主动押注：紫色调 + 左侧紫边框
const PRESET_DESPERATE := "desperate"      # 孤注一掷：红色调 + 左侧红边框
const PRESET_TOGGLE := "toggle"            # 切换按钮：紧凑半透明
const PRESET_SECTION_HINT := "section_hint" # 分区提示标签风格（非按钮，但共享配色体系）
const PRESET_RELATION_TRUST := "relation_trust"       # 自省关系调整：+信任 小按钮
const PRESET_RELATION_DISTRUST := "relation_distrust"  # 自省关系调整：+警惕 小按钮

# ── 预设配置表 ──
# 每个预设是一个 Dictionary，包含以下可选字段：
#   bg_normal, bg_hover, bg_pressed, bg_disabled  — Color，四态背景色
#   border_color  — Color，左侧强调边框颜色（TRANSPARENT 表示无边框）
#   border_width  — int，左侧边框宽度（默认 3）
#   font_color    — Color，常态字体色
#   font_disabled_color — Color，禁用态字体色
#   font_size     — int，字号覆盖（0 表示不覆盖）
#   corner_radius — int，四角圆角半径
#   margin_left, margin_right, margin_top, margin_bottom — int，内边距
#   min_height    — int，最小高度（0 表示不设置）
#   autowrap      — bool，是否开启自动换行
#   alignment     — int，水平对齐（HorizontalAlignment 枚举值）
static var _presets: Dictionary = {
	PRESET_DEFAULT: {
		"bg_normal": Color(0.18, 0.20, 0.25, 1.0),
		"bg_hover": Color(0.26, 0.28, 0.34, 1.0),
		"bg_pressed": Color(0.14, 0.16, 0.20, 1.0),
		"bg_disabled": Color(0.12, 0.12, 0.14, 0.7),
		"border_color": Color.TRANSPARENT,
		"font_color": Color.WHITE,
		"font_disabled_color": Color(0.45, 0.45, 0.50, 1.0),
		"font_size": 0,
		"corner_radius": 6,
		"margin_left": 14, "margin_right": 14,
		"margin_top": 10, "margin_bottom": 10,
		"min_height": 54,
		"autowrap": true,
		"alignment": HORIZONTAL_ALIGNMENT_LEFT,
	},
	PRESET_BET: {
		"bg_normal": Color(0.24, 0.16, 0.36, 1.0),
		"bg_hover": Color(0.32, 0.22, 0.46, 1.0),
		"bg_pressed": Color(0.18, 0.12, 0.28, 1.0),
		"bg_disabled": Color(0.12, 0.12, 0.14, 0.7),
		"border_color": Color(0.55, 0.35, 0.85, 1.0),
		"border_disabled_color": Color(0.3, 0.3, 0.3, 0.5),
		"font_color": Color(0.90, 0.85, 1.0, 1.0),
		"font_disabled_color": Color(0.45, 0.45, 0.50, 1.0),
		"font_size": 0,
		"corner_radius": 6,
		"margin_left": 16, "margin_right": 14,
		"margin_top": 10, "margin_bottom": 10,
		"min_height": 54,
		"autowrap": true,
		"alignment": HORIZONTAL_ALIGNMENT_LEFT,
	},
	PRESET_DESPERATE: {
		"bg_normal": Color(0.34, 0.14, 0.14, 1.0),
		"bg_hover": Color(0.44, 0.20, 0.18, 1.0),
		"bg_pressed": Color(0.26, 0.10, 0.10, 1.0),
		"bg_disabled": Color(0.12, 0.12, 0.14, 0.7),
		"border_color": Color(0.85, 0.30, 0.25, 1.0),
		"border_disabled_color": Color(0.3, 0.3, 0.3, 0.5),
		"font_color": Color(1.0, 0.90, 0.88, 1.0),
		"font_disabled_color": Color(0.45, 0.45, 0.50, 1.0),
		"font_size": 0,
		"corner_radius": 6,
		"margin_left": 16, "margin_right": 14,
		"margin_top": 10, "margin_bottom": 10,
		"min_height": 54,
		"autowrap": true,
		"alignment": HORIZONTAL_ALIGNMENT_LEFT,
	},
	PRESET_TOGGLE: {
		"bg_normal": Color(0.35, 0.30, 0.45, 0.85),
		"bg_hover": Color(0.45, 0.38, 0.55, 0.95),
		"bg_pressed": Color(0.28, 0.24, 0.38, 0.9),
		"bg_disabled": Color(0.15, 0.15, 0.18, 0.7),
		"border_color": Color.TRANSPARENT,
		"font_color": Color(0.85, 0.82, 0.92, 1.0),
		"font_disabled_color": Color(0.45, 0.45, 0.50, 1.0),
		"font_size": 12,
		"corner_radius": 4,
		"margin_left": 4, "margin_right": 4,
		"margin_top": 4, "margin_bottom": 4,
		"min_height": 0,
		"autowrap": false,
		"alignment": HORIZONTAL_ALIGNMENT_CENTER,
		"expand_horizontal": false,
	},
	PRESET_RELATION_TRUST: {
		"bg_normal": Color(0.15, 0.30, 0.22, 0.90),
		"bg_hover": Color(0.20, 0.40, 0.30, 0.95),
		"bg_pressed": Color(0.12, 0.24, 0.18, 0.95),
		"bg_disabled": Color(0.15, 0.15, 0.18, 0.7),
		"border_color": Color.TRANSPARENT,
		"font_color": Color(0.75, 1.0, 0.85, 1.0),
		"font_disabled_color": Color(0.45, 0.45, 0.50, 1.0),
		"font_size": 12,
		"corner_radius": 4,
		"margin_left": 6, "margin_right": 6,
		"margin_top": 2, "margin_bottom": 2,
		"min_height": 0,
		"autowrap": false,
		"alignment": HORIZONTAL_ALIGNMENT_CENTER,
		"expand_horizontal": false,
	},
	PRESET_RELATION_DISTRUST: {
		"bg_normal": Color(0.32, 0.18, 0.15, 0.90),
		"bg_hover": Color(0.42, 0.24, 0.20, 0.95),
		"bg_pressed": Color(0.25, 0.14, 0.12, 0.95),
		"bg_disabled": Color(0.15, 0.15, 0.18, 0.7),
		"border_color": Color.TRANSPARENT,
		"font_color": Color(1.0, 0.82, 0.78, 1.0),
		"font_disabled_color": Color(0.45, 0.45, 0.50, 1.0),
		"font_size": 12,
		"corner_radius": 4,
		"margin_left": 6, "margin_right": 6,
		"margin_top": 2, "margin_bottom": 2,
		"min_height": 0,
		"autowrap": false,
		"alignment": HORIZONTAL_ALIGNMENT_CENTER,
		"expand_horizontal": false,
	},
}


# 功能：用命名预设为按钮施加完整的四态样式。
# 说明：预设名见 PRESET_* 常量。未找到预设时回退到 PRESET_DEFAULT。
static func apply(button: Button, preset_name: String = PRESET_DEFAULT) -> void:
	var config: Dictionary = _presets.get(preset_name, _presets[PRESET_DEFAULT])
	apply_config(button, config)


# 功能：用自定义配置字典为按钮施加样式。
# 说明：字段格式与预设表一致，缺失字段从 PRESET_DEFAULT 补齐。
#       适用于需要微调但不值得新建预设的场景。
static func apply_config(button: Button, config: Dictionary) -> void:
	var base: Dictionary = _presets[PRESET_DEFAULT]
	# 合并：config 覆盖 base
	var c: Dictionary = base.duplicate()
	c.merge(config, true)

	# 基础属性
	var expand_h := bool(c.get("expand_horizontal", true))
	if expand_h:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var min_h := int(c.get("min_height", 54))
	if min_h > 0:
		button.custom_minimum_size.y = min_h
	if bool(c.get("autowrap", true)):
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = int(c.get("alignment", HORIZONTAL_ALIGNMENT_LEFT)) as HorizontalAlignment

	# 构建 normal 态 StyleBoxFlat
	var style_normal := _build_stylebox(c, "bg_normal", "border_color")
	button.add_theme_stylebox_override("normal", style_normal)

	# hover 态
	var style_hover: StyleBoxFlat = style_normal.duplicate()
	style_hover.bg_color = c.get("bg_hover", style_normal.bg_color) as Color
	button.add_theme_stylebox_override("hover", style_hover)

	# pressed 态
	var style_pressed: StyleBoxFlat = style_normal.duplicate()
	style_pressed.bg_color = c.get("bg_pressed", style_normal.bg_color) as Color
	button.add_theme_stylebox_override("pressed", style_pressed)

	# disabled 态
	var style_disabled: StyleBoxFlat = style_normal.duplicate()
	style_disabled.bg_color = c.get("bg_disabled", Color(0.12, 0.12, 0.14, 0.7)) as Color
	var border_disabled: Color = c.get("border_disabled_color", Color.TRANSPARENT) as Color
	if style_disabled.border_width_left > 0:
		style_disabled.border_color = border_disabled
	button.add_theme_stylebox_override("disabled", style_disabled)

	# 字体颜色
	var font_color: Color = c.get("font_color", Color.WHITE) as Color
	if font_color != Color.WHITE:
		button.add_theme_color_override("font_color", font_color)
	var font_disabled_color: Color = c.get("font_disabled_color", Color(0.45, 0.45, 0.50, 1.0)) as Color
	button.add_theme_color_override("font_disabled_color", font_disabled_color)

	# 字号
	var font_size := int(c.get("font_size", 0))
	if font_size > 0:
		button.add_theme_font_size_override("font_size", font_size)


# 功能：获取指定预设的配置副本，用于外部微调后传入 apply_config。
# 说明：返回的是独立副本，修改不会影响内部预设表。
static func get_preset_config(preset_name: String) -> Dictionary:
	var config: Dictionary = _presets.get(preset_name, _presets[PRESET_DEFAULT])
	return config.duplicate()


# 功能：覆盖按钮已施加样式的右侧内边距。
# 说明：用于在选项按钮右侧预留切换按钮空间等场景，避免外部重复遍历四态 StyleBox。
static func override_margin_right(button: Button, margin_right: int) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var sb: Variant = button.get_theme_stylebox(state_name)
		if sb is StyleBoxFlat:
			var patched: StyleBoxFlat = sb.duplicate()
			patched.content_margin_right = margin_right
			button.add_theme_stylebox_override(state_name, patched)


# ── 内部工具 ──

# 功能：根据配置构建一个 StyleBoxFlat。
# 说明：统一处理圆角、内边距、背景色和可选左侧边框。
static func _build_stylebox(config: Dictionary, bg_key: String, border_key: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = config.get(bg_key, Color(0.18, 0.20, 0.25, 1.0)) as Color

	var radius := int(config.get("corner_radius", 6))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius

	style.content_margin_left = int(config.get("margin_left", 14))
	style.content_margin_right = int(config.get("margin_right", 14))
	style.content_margin_top = int(config.get("margin_top", 10))
	style.content_margin_bottom = int(config.get("margin_bottom", 10))

	var border_color: Color = config.get(border_key, Color.TRANSPARENT) as Color
	if border_color != Color.TRANSPARENT:
		var border_width := int(config.get("border_width", 3))
		style.border_width_left = border_width
		style.border_color = border_color

	return style
