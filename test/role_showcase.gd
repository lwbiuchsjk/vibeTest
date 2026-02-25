extends Control

const RoleState := preload("res://scripts/models/role_state.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")

@onready var status_label: Label = $Root/StatusLabel
@onready var role_list: HBoxContainer = $Root/RoleScroll/RoleList

func _ready() -> void:
	var runtime := ConfigRuntime.shared()
	# 测试场景中始终强制重载，避免配置缓存导致展示与文件不一致。
	var load_result := runtime.ensure_loaded({}, true)
	if not load_result.get("ok", false):
		status_label.text = "Load failed: %s" % load_result.get("error", "unknown")
		return

	var roles := runtime.get_roles()
	if roles.is_empty():
		status_label.text = "No role data found."
		return

	var context_result := runtime.build_context()
	if not context_result.get("ok", false):
		status_label.text = "Build context failed: %s" % context_result.get("error", "unknown")
		return

	var graph: LocationGraph = context_result.get("graph")
	_render_roles(roles, graph)
	status_label.text = "Loaded %d roles" % roles.size()

func _render_roles(roles: Array, graph: LocationGraph) -> void:
	for child in role_list.get_children():
		child.queue_free()

	for role_variant in roles:
		var role: RoleState = role_variant
		role_list.add_child(_build_role_card(role, graph))

func _build_role_card(role: RoleState, graph: LocationGraph) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(180, 360)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(content)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(150, 170)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.texture = role.load_portrait_texture()
	content.add_child(portrait)

	if portrait.texture == null:
		var missing_label := Label.new()
		missing_label.text = "No portrait: %s" % role.get_portrait_path()
		missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(missing_label)

	var name_label := Label.new()
	name_label.text = role.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(name_label)

	# 地点展示：名称 + 美术资源预览
	var location_name_label := Label.new()
	location_name_label.text = "地点：%s" % graph.get_display_name(role.location_id)
	location_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(location_name_label)

	var location_art := TextureRect.new()
	location_art.custom_minimum_size = Vector2(150, 72)
	location_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	location_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	location_art.texture = graph.load_art_texture(role.location_id)
	content.add_child(location_art)

	if location_art.texture == null:
		var missing_art_label := Label.new()
		missing_art_label.text = "地点美术缺失：%s" % graph.get_art_path(role.location_id)
		missing_art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing_art_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(missing_art_label)

	return card
