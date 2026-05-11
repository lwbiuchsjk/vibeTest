## 离线 mosaic 预渲染工具（REQ-004 静态化方案 C.2）
##
## 用途：将 11 张事件背景源图通过 SubViewport + 13 层 text_mosaic_background 渲染管线
##       离线生成静态 mosaic PNG，运行时用 TextureRect 直接切静态图，绕开运行时 _draw
##       + draw_string 的每帧 50k draw_calls 性能瓶颈（见 [[intro_mosaic_性能排查_2026-05-11]]）。
##
## 使用方式：
##   1. Godot 编辑器打开 tools/gen_mosaic_static/gen_mosaic_static.tscn
##   2. 点 "Run Scene" (F6) 而不是 "Play Project" (F5)
##   3. 出现 UI 后点 "Generate All Mosaics" 按钮
##   4. 等所有 PNG 生成完毕（11 张约 30-60 秒）
##   5. 检查 assets/art/mosaic_static/ 下的 PNG，视觉对照 main_game 当前运行时效果
##
## 设计依据：
##   - 13 层参数表从 main_game.tscn MosaicLayersA 复制（必须保持同步——如参数表改动，
##     运行时跟离线渲染要同时更新）
##   - Token 池硬编码（main_game.gd::LOCATION_TEXT_TOKENS 的子集）
##   - 背景米色底 IntroBgColor 也包含在渲染（main_game.tscn 同款 Color(0.957, 0.925, 0.847)）
##   - 输出 1024×576 PNG，运行时 TextureRect KEEP_ASPECT_COVERED 拉伸全屏
##
## 注意事项：
##   - IntroAccent 层 breathe_enabled=true 在静态化时 freeze 为 modulate.a=0.6（呼吸中值）
##   - 如未来 mosaic 参数 / token 池调整，**必须**重新跑本工具生成新 PNG
##   - face mask 抑制将集成进本工具后续迭代（当前不应用 mask）

extends Control

# ============================================================
# 13 层 mosaic 参数表（与 scenes/main_game.tscn MosaicLayersA 同步）
# ============================================================

const MOSAIC_SCRIPT: Script = preload("res://scripts/ui/text_mosaic_background.gd")

# 输出 canvas 尺寸（与源图 aspect 1.778 一致）
const CANVAS_SIZE: Vector2i = Vector2i(1024, 576)

# 米色底色（与 main_game.tscn::IntroBgColor 同步）
const BG_COLOR: Color = Color(0.957, 0.925, 0.847, 1.0)

# 13 层参数：name + modulate.a + 全套 export property
const LAYER_CONFIGS: Array[Dictionary] = [
	{
		"name": "IntroBg",
		"modulate_a": 1.0,
		"font_size": 8,
		"grid_phase": Vector2(0.37, 0.71),
		"density_jitter": 0.0,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 1.0,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.4,
		"ink_levels": 32,
	},
	{
		"name": "IntroCoarse",
		"modulate_a": 0.55,
		"font_size": 24,
		"grid_phase": Vector2(0.13, 0.41),
		"density_jitter": 1.0,
		"position_jitter": 0.7,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.5,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroMedium",
		"modulate_a": 0.6,
		"font_size": 14,
		"grid_phase": Vector2(0.59, 0.17),
		"density_jitter": 0.95,
		"position_jitter": 0.6,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.55,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroDarkLight",
		"modulate_a": 0.3,
		"font_size": 8,
		"grid_phase": Vector2(0.07, 0.53),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.7,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroDarkAccent",
		"modulate_a": 0.35,
		"font_size": 8,
		"grid_phase": Vector2(0.83, 0.29),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.5,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroDarkDeep",
		"modulate_a": 0.45,
		"font_size": 8,
		"grid_phase": Vector2(0.61, 0.89),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.32,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroDarkInk",
		"modulate_a": 0.55,
		"font_size": 8,
		"grid_phase": Vector2(0.27, 0.23),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.18,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroDarkBetween",
		"modulate_a": 0.6,
		"font_size": 8,
		"grid_phase": Vector2(0.49, 0.71),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.13,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroDarkAbyss",
		"modulate_a": 0.65,
		"font_size": 8,
		"grid_phase": Vector2(0.91, 0.43),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 0.08,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroMidDark",
		"modulate_a": 0.35,
		"font_size": 6,
		"grid_phase": Vector2(0.31, 0.47),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.4,
		"v_max_threshold": 0.55,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroMidLight",
		"modulate_a": 0.35,
		"font_size": 6,
		"grid_phase": Vector2(0.79, 0.13),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.55,
		"v_max_threshold": 0.75,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroHighlight",
		"modulate_a": 0.4,
		"font_size": 8,
		"grid_phase": Vector2(0.43, 0.91),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.75,
		"v_max_threshold": 1.0,
		"saturation_threshold": 0.0,
		"use_source_color": false,
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
	{
		"name": "IntroAccent",
		"modulate_a": 0.6,  # 呼吸动画中值 freeze（breathe_min 0.4 / breathe_max 0.8）
		"font_size": 8,
		"grid_phase": Vector2(0.53, 0.67),
		"density_jitter": 0.3,
		"position_jitter": 0.45,
		"v_min_threshold": 0.0,
		"v_max_threshold": 1.0,
		"saturation_threshold": 0.4,
		"use_source_color": true,  # 点缀色用源图原色
		"contrast_factor": 1.0,
		"ink_levels": 5,
	},
]

# ============================================================
# Token 池（与 main_game.gd::LOCATION_TEXT_TOKENS + IntroSequence::INTRO_TEXT_TOKENS 同步）
# ============================================================

const INTRO_TOKENS: Array = [
	"涟漪", "水波", "荷叶", "芦苇", "浮光", "碧水",
	"倒影", "鱼跃", "竹影", "天光", "静水", "扁舟",
	"柳影", "残荷", "云影", "风声"
]
const PHARMACY_TOKENS: Array = ["药铺", "苦汤", "草药", "杵臼", "症候", "良方"]
# loc_qin_house 在 main_game.gd 没专属池 → fallback DEFAULT。这里用相对贴合家场景的自定义池
const QIN_HOUSE_TOKENS: Array = ["堂屋", "灶台", "炊烟", "门轴", "铜板", "晚归"]
const TRAINING_GROUND_TOKENS: Array = ["练场", "拳脚", "汗水", "号令", "招式", "刀光"]

# ============================================================
# 渲染任务清单
# ============================================================

const JOBS: Array[Dictionary] = [
	# 涟漪期 4 帧 + intro 终态 girl_enter（INTRO_TOKENS 池塘词池）
	# pond_girl_enter 应用 face mask 抑制大字号字符落少女脸
	{"src": "res://assets/art/environments/backgrounds/pond_still.png",
	 "tokens_id": "INTRO",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/pond_still_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/pond_ripple_1.png",
	 "tokens_id": "INTRO",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/pond_ripple_1_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/pond_ripple_2.png",
	 "tokens_id": "INTRO",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/pond_ripple_2_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/pond_ripple_3.png",
	 "tokens_id": "INTRO",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/pond_ripple_3_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/pond_girl_enter.png",
	 "tokens_id": "INTRO",
	 "face_mask": "res://assets/art/environments/backgrounds/pond_girl_enter_face_mask.png",
	 "out": "res://assets/art/mosaic_static/pond_girl_enter_mosaic.png"},

	# 药铺线 2 张（PHARMACY_TOKENS）
	# heshouren_foreground 应用 face mask（v5 时代 mask，v6 art 入库后位置可能轻微错位但可接受）
	{"src": "res://assets/art/environments/backgrounds/pharmacy_default.png",
	 "tokens_id": "PHARMACY",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/pharmacy_default_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/pharmacy_default_heshouren_foreground.png",
	 "tokens_id": "PHARMACY",
	 "face_mask": "res://assets/art/environments/backgrounds/pharmacy_default_heshouren_foreground_face_mask.png",
	 "out": "res://assets/art/mosaic_static/pharmacy_default_heshouren_foreground_mosaic.png"},

	# 家+市场线 2 张（QIN_HOUSE_TOKENS）
	# qinsuniang_foreground face mask 待 LangSAM 生成（face_mask生成工作流）→ 当前暂不应用
	{"src": "res://assets/art/environments/backgrounds/qin_house_default.png",
	 "tokens_id": "QIN_HOUSE",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/qin_house_default_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/qin_house_qinsuniang_foreground.png",
	 "tokens_id": "QIN_HOUSE",
	 "face_mask": "",  # TODO: face_mask生成工作流跑出 qinsuniang_face_mask.png 后填入并重跑本工具
	 "out": "res://assets/art/mosaic_static/qin_house_qinsuniang_foreground_mosaic.png"},

	# 练场线 2 张（TRAINING_GROUND_TOKENS）
	# zhoujiming_foreground face mask 待 LangSAM 生成 → 当前暂不应用
	{"src": "res://assets/art/environments/backgrounds/training_ground_default.png",
	 "tokens_id": "TRAINING_GROUND",
	 "face_mask": "",
	 "out": "res://assets/art/mosaic_static/training_ground_default_mosaic.png"},
	{"src": "res://assets/art/environments/backgrounds/training_ground_zhoujiming_foreground.png",
	 "tokens_id": "TRAINING_GROUND",
	 "face_mask": "",  # TODO: face_mask生成工作流跑出 zhoujiming_face_mask.png 后填入并重跑本工具
	 "out": "res://assets/art/mosaic_static/training_ground_zhoujiming_foreground_mosaic.png"},
]


# ============================================================
# UI 引用
# ============================================================

@onready var status_label: Label = $VBox/StatusLabel
@onready var generate_button: Button = $VBox/GenerateButton
@onready var preview_rect: TextureRect = $VBox/PreviewRect


# ============================================================
# 入口
# ============================================================

# 功能：场景启动时挂载按钮信号。
func _ready() -> void:
	generate_button.pressed.connect(_on_generate_pressed)
	status_label.text = "就绪。点 Generate All 开始（共 %d 张 PNG）" % JOBS.size()


# 功能：用户点击 Generate All 时启动批量预渲染流程。
func _on_generate_pressed() -> void:
	generate_button.disabled = true
	await _generate_all()
	generate_button.disabled = false


# 功能：批量遍历 JOBS，对每张源图调 _render_one 生成 mosaic PNG。
# 说明：每张渲染完成后让出一帧再开始下一张，避免 SubViewport 资源未释放堆积。
func _generate_all() -> void:
	var success_count: int = 0
	var fail_list: Array[String] = []
	for i in range(JOBS.size()):
		var job: Dictionary = JOBS[i]
		var src_name: String = (job["src"] as String).get_file()
		status_label.text = "[%d/%d] 渲染中: %s" % [i + 1, JOBS.size(), src_name]
		# 强制 UI 刷新（在长任务中保持响应）
		await get_tree().process_frame
		var ok: bool = await _render_one(job)
		if ok:
			success_count += 1
		else:
			fail_list.append(src_name)
		# 让渲染管线 free SubViewport
		await get_tree().process_frame
		await get_tree().process_frame
	var msg: String = "完成 %d/%d 张" % [success_count, JOBS.size()]
	if not fail_list.is_empty():
		msg += "\n失败: " + ", ".join(fail_list)
	status_label.text = msg
	print("[gen_mosaic_static] ", msg)


# 功能：单图渲染 + 截图保存。
# 说明：创建 SubViewport（1024×576）→ 装 ColorRect 米色底 + 13 个 mosaic Control 子节点
#       → set_source_image + set_text_tokens → 等 2 帧让 _draw 完成 → 截图保存 PNG。
# 返回：true 成功；false 失败（资源加载失败 / 图保存失败等）。
func _render_one(job: Dictionary) -> bool:
	var src_path: String = job["src"]
	var out_path: String = job["out"]
	var tokens_id: String = job["tokens_id"]

	# 加载源图
	var tex: Texture2D = load(src_path) as Texture2D
	if tex == null:
		push_error("[gen_mosaic_static] 源图加载失败: " + src_path)
		return false

	# 创建 SubViewport
	var vp: SubViewport = SubViewport.new()
	vp.size = CANVAS_SIZE
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	# 米色底 ColorRect
	var bg_color_rect: ColorRect = ColorRect.new()
	bg_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_color_rect.color = BG_COLOR
	bg_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(bg_color_rect)

	# 13 层 mosaic
	var tokens_arr: Array = _get_tokens(tokens_id)
	var tokens_psa: PackedStringArray = PackedStringArray(tokens_arr)
	var face_mask_path: String = str(job.get("face_mask", ""))
	for layer_cfg in LAYER_CONFIGS:
		var layer: Control = _create_mosaic_layer(layer_cfg)
		vp.add_child(layer)
		# add_child 后 _ready 触发，font 加载完成；再设 source + tokens + (optional) face mask
		layer.call("set_source_image", tex)
		layer.call("set_text_tokens", tokens_psa)
		# 仅 IntroCoarse / IntroMedium 大字号层应用 face mask（与 IntroSequence::_apply_face_mask 一致）
		if not face_mask_path.is_empty() and cfg_layer_uses_face_mask(layer_cfg["name"]):
			layer.call("set_exclude_mask", face_mask_path)

	# 等 2 帧让所有 layer _draw 完成
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	# 截取 SubViewport 当前帧到 Image
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("[gen_mosaic_static] viewport 截图失败: " + src_path)
		vp.queue_free()
		return false

	# 保存 PNG
	var save_err: int = img.save_png(out_path)
	if save_err != OK:
		push_error("[gen_mosaic_static] PNG 保存失败 err=%d: %s" % [save_err, out_path])
		vp.queue_free()
		return false

	# 预览：把刚渲染的图显示在 UI 上，便于实时检视
	preview_rect.texture = ImageTexture.create_from_image(img)

	# 清理
	vp.queue_free()
	print("[gen_mosaic_static] ✓ ", out_path)
	return true


# 功能：创建一个 mosaic Control 节点 + 挂 text_mosaic_background.gd + 设全套 export 参数。
# 参数 cfg：LAYER_CONFIGS 中的一条配置 Dictionary。
# 说明：先 set_script + add_child 后设属性，让 _ready 先跑（加载 font）。
#       breathe_enabled 总设 false（静态化时 freeze 在 modulate_a 配置值，不动画）。
func _create_mosaic_layer(cfg: Dictionary) -> Control:
	var layer: Control = Control.new()
	layer.set_script(MOSAIC_SCRIPT)
	layer.name = cfg["name"]
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.modulate = Color(1.0, 1.0, 1.0, cfg["modulate_a"])
	# Inspector 参数（text_mosaic_background.gd 中 @export 的）
	layer.set("font_size", cfg["font_size"])
	layer.set("grid_phase", cfg["grid_phase"])
	layer.set("density_jitter", cfg["density_jitter"])
	layer.set("position_jitter", cfg["position_jitter"])
	layer.set("v_min_threshold", cfg["v_min_threshold"])
	layer.set("v_max_threshold", cfg["v_max_threshold"])
	layer.set("saturation_threshold", cfg["saturation_threshold"])
	layer.set("use_source_color", cfg["use_source_color"])
	layer.set("breathe_enabled", false)  # 静态化 freeze，不启用呼吸动画
	layer.set("contrast_factor", cfg["contrast_factor"])
	layer.set("ink_levels", cfg["ink_levels"])
	return layer


# 功能：判定指定 mosaic 层名是否应用 face mask 抑制。
# 说明：与 IntroSequence::_apply_face_mask_to_slot 一致——只 IntroCoarse + IntroMedium 应用
#       （这两层 font_size=24 / 14 是大字号，落脸破坏识别；其他细字层照常渲染保留密度感）。
func cfg_layer_uses_face_mask(layer_name: String) -> bool:
	return layer_name == "IntroCoarse" or layer_name == "IntroMedium"


# 功能：按 tokens_id 返回对应 token 池数组。
func _get_tokens(tokens_id: String) -> Array:
	match tokens_id:
		"INTRO":
			return INTRO_TOKENS
		"PHARMACY":
			return PHARMACY_TOKENS
		"QIN_HOUSE":
			return QIN_HOUSE_TOKENS
		"TRAINING_GROUND":
			return TRAINING_GROUND_TOKENS
		_:
			push_warning("[gen_mosaic_static] 未知 tokens_id: " + tokens_id + "，fallback 到 INTRO")
			return INTRO_TOKENS
