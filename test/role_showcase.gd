extends Control

const RoleState := preload("res://scripts/models/role_state.gd")
const ROLES_CSV_PATH := "res://scripts/config/roles.csv"

@onready var status_label: Label = $Root/StatusLabel
@onready var role_list: HBoxContainer = $Root/RoleScroll/RoleList

func _ready() -> void:
	var roles_result := _load_roles_from_csv(ROLES_CSV_PATH)
	if not roles_result.get("ok", false):
		status_label.text = "Load failed: %s" % roles_result.get("error", "unknown")
		return

	var roles: Array = roles_result.get("roles", [])
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
		missing_label.text = "No portrait"
		missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(missing_label)

	var name_label := Label.new()
	name_label.text = role.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(name_label)

	return card

func _load_roles_from_csv(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "roles csv not found: %s" % path}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open roles csv: %s" % path}
	if file.eof_reached():
		return {"ok": false, "error": "roles csv is empty: %s" % path}

	var header_row := file.get_csv_line()
	var headers: Array[String] = []
	for header in header_row:
		headers.append(str(header).strip_edges())
	if headers.is_empty():
		return {"ok": false, "error": "roles csv header is empty: %s" % path}

	var roles: Array = []
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.is_empty():
			continue
		if values.size() == 1 and str(values[0]).strip_edges().is_empty():
			continue

		var row: Dictionary = {}
		for i in headers.size():
			var key := headers[i]
			var value := ""
			if i < values.size():
				value = str(values[i]).strip_edges()
			row[key] = value

		var role := RoleState.new(
			str(row.get("role_id", "")),
			str(row.get("role_type", "")),
			str(row.get("display_name", "")),
			str(row.get("location_id", "")),
			str(row.get("portrait_path", "")),
			{},
			{}
		)
		roles.append(role)

	return {"ok": true, "roles": roles}
