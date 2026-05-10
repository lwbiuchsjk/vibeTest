# 功能:墨印阴刻面板 —— 用纯代码模拟印章质感(美术资源 80% 效果占位)。
# 说明:四层叠加渲染:
#         1. 实色墨底 —— StyleBoxFlat 矩形 + 极小圆角
#         2. 斑驳墨层 —— 在面板范围内按 cell 扫描,sin(x,y,seed) 产生 deterministic
#            noise 驱动字符密度 + alpha,与 text_mosaic_background.gd 同源算法的简化版
#         3. 边框 —— 默认与底色同色(用户决策:无视觉对比,只占空间)
#         4. 主字 + 副字 —— 主字大字号(粗壮书法感字体),副字小字号(规整数字),
#            分别独立锚定,模拟传统印章"中央大字 + 角落小字"布局
# 哲学锚点:状态条印章 = 修行者内观自己 → 墨色(与 mosaic 字符同源,含蓄内向);
#       朱色严格收回到"伸手"位(选项/继续按钮),关键时刻用在刀刃上。
# 参见 Design/进度/UI风格快速翻调_demo期进度.md § 印章设计决策记录。
extends Control

# === 主字(大,粗壮书法感) ===
var main_text: String = ""
var main_font: Font = null
var main_font_size: int = 22
# 主字锚点(0-1 印章内相对位置,字以此点为中心);默认偏左居中(给副字让出右下角)
var main_anchor: Vector2 = Vector2(0.32, 0.50)

# === 副字(小,规整数字) ===
var sub_text: String = ""
var sub_font: Font = null
var sub_font_size: int = 11
# 副字锚点(默认右下,模拟传统印章角落小字)
var sub_anchor: Vector2 = Vector2(0.78, 0.60)

# === 共享反白字色(底纸米白,与 BackgroundColor 同色) ===
var seal_text_color: Color = Color(0.957, 0.925, 0.847, 1.0)

# === 印章质感参数 ===
var bg_color: Color = Color(0.220, 0.200, 0.170, 0.92)
var ink_color: Color = Color(0.050, 0.045, 0.035, 1.0)  # 斑驳层墨色
var border_width: int = 2
var corner_radius: int = 2
var padding: Vector2 = Vector2(10.0, 6.0)
var noise_cell_size: int = 4
var noise_seed: int = 0
# 副字保留宽度（议题 A 抖动修复，2026-05-10）：
# > 0 时强制副字最小宽度，避免 sub_text 变化（如 "1"→"2"）宽度差异引起印章 size 抖动。
# 状态栏调用方按 "999" 等最大数值预算后传入。0 表示按实际 sub_text 宽度算（旧行为）。
var sub_reserve_width: float = 0.0
var ink_pool: PackedStringArray = PackedStringArray([
	"命", "力", "金", "心", "回", "岁", "年", "气",
	"神", "魂", "天", "人", "土", "水", "火", "木"
])

var _bg_font: Font = null


func _ready() -> void:
	_bg_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


# 功能:一次性配置印章主字 + 副字 + seed。
# 参数 main:大字内容(如 "命")
# 参数 value:小字内容(如 "99")
# 参数 m_font / m_size:大字字体 + 字号(推荐青鸟华光美黑等粗壮书法感字体)
# 参数 v_font / v_size:小字字体 + 字号(推荐宋体 Medium 等规整字体)
# 参数 seed_val:斑驳层 noise seed,各印章传不同值产生各异斑驳模式
func set_seal(
	main: String, value: String,
	m_font: Font, m_size: int,
	v_font: Font, v_size: int,
	seed_val: int = 0
) -> void:
	main_text = main
	sub_text = value
	main_font = m_font
	main_font_size = m_size
	sub_font = v_font
	sub_font_size = v_size
	noise_seed = seed_val
	update_minimum_size()
	queue_redraw()


# 功能:根据主字 + 副字 size 计算 minimum size。
# 说明:高度按主字 ascent+descent + 上下 padding;
#       宽度按主字宽 + 副字宽 + 6px 间隔 + 左右 padding。
#       sub_reserve_width > 0 时副字宽度兜底（避免数字变化引起印章宽度抖动）。
func _get_minimum_size() -> Vector2:
	if main_font == null or main_text == "":
		return Vector2(60.0, 32.0)
	var main_size: Vector2 = main_font.get_string_size(
		main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, main_font_size
	)
	var sub_w: float = 0.0
	if sub_font != null and sub_text != "":
		sub_w = sub_font.get_string_size(
			sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_font_size
		).x
	# 副字保留宽度兜底：sub_reserve_width 大于实际宽时用保留值，避免抖动
	if sub_reserve_width > 0.0:
		sub_w = max(sub_w, sub_reserve_width)
	var total_w: float = main_size.x + sub_w + 6.0
	return Vector2(total_w, main_size.y) + padding * 2.0


# 功能:四层叠加渲染。
func _draw() -> void:
	if _bg_font == null:
		_bg_font = get_theme_default_font()

	var rect := Rect2(Vector2.ZERO, size)

	# === Layer 1:实色墨底 ===
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.corner_radius_top_left = corner_radius
	bg_style.corner_radius_top_right = corner_radius
	bg_style.corner_radius_bottom_left = corner_radius
	bg_style.corner_radius_bottom_right = corner_radius
	draw_style_box(bg_style, rect)

	# === Layer 2:斑驳墨层(密集小字符,noise 驱动 alpha) ===
	var pad_inner: int = 3
	var inner := Rect2(
		Vector2(pad_inner, pad_inner),
		size - Vector2(pad_inner * 2, pad_inner * 2)
	)
	var cell: int = noise_cell_size
	var token_count: int = ink_pool.size()
	if token_count > 0 and inner.size.x > 0.0 and inner.size.y > 0.0:
		var y: int = 0
		while y < int(inner.size.y):
			var x: int = 0
			while x < int(inner.size.x):
				# Deterministic noise:不相关频率组合
				var n: float = (
					sin(float(x) * 0.137 + float(y) * 0.213
						+ float(noise_seed) * 1.7) * 0.5 + 0.5
				)
				if n > 0.25:
					var token_idx: int = (
						(x * 3 + y * 7 + noise_seed) % token_count
					)
					var token: String = ink_pool[token_idx]
					var c: Color = ink_color
					c.a = 0.15 + n * 0.55
					draw_string(
						_bg_font,
						inner.position + Vector2(x, y + cell - 1),
						token,
						HORIZONTAL_ALIGNMENT_LEFT, -1, cell, c
					)
				x += cell
			y += cell

	# === Layer 3:边框(与底色同色,无视觉对比,只维持空间一致) ===
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.draw_center = false
	border_style.border_color = bg_color
	border_style.border_width_left = border_width
	border_style.border_width_top = border_width
	border_style.border_width_right = border_width
	border_style.border_width_bottom = border_width
	border_style.corner_radius_top_left = corner_radius
	border_style.corner_radius_top_right = corner_radius
	border_style.corner_radius_bottom_left = corner_radius
	border_style.corner_radius_bottom_right = corner_radius
	draw_style_box(border_style, rect)

	# === Layer 4a:主字(大,粗壮书法感) ===
	if main_font != null and main_text != "":
		var main_size: Vector2 = main_font.get_string_size(
			main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, main_font_size
		)
		var main_pos := Vector2(
			size.x * main_anchor.x - main_size.x * 0.5,
			size.y * main_anchor.y + main_size.y * 0.30
		)
		draw_string(
			main_font, main_pos, main_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, main_font_size, seal_text_color
		)

	# === Layer 4b:副字(小,规整数字,角落小字) ===
	if sub_font != null and sub_text != "":
		var sub_size: Vector2 = sub_font.get_string_size(
			sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_font_size
		)
		var sub_pos := Vector2(
			size.x * sub_anchor.x - sub_size.x * 0.5,
			size.y * sub_anchor.y + sub_size.y * 0.30
		)
		draw_string(
			sub_font, sub_pos, sub_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sub_font_size, seal_text_color
		)
