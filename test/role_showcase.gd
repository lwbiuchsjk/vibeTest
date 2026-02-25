extends Control

const RoleState := preload("res://scripts/models/role_state.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")

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

	_render_roles(roles)
	status_label.text = "Loaded %d roles" % roles.size()

func _render_roles(roles: Array) -> void:
	for child in role_list.get_children():
		child.queue_free()

	for role_variant in roles:
		var role: RoleState = role_variant
		role_list.add_child(_build_role_card(role))

func _build_role_card(role: RoleState) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(170, 240)

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

	return card
