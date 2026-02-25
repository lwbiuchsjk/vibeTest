extends Control

const RoleState := preload("res://scripts/models/role_state.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")
const RoleCard := preload("res://scripts/ui/role_card.gd")
const RoleCardScene := preload("res://scripts/ui/role_card.tscn")

@onready var status_label: Label = $Root/StatusLabel
@onready var role_list: HBoxContainer = $Root/RoleScroll/RoleList

func _ready() -> void:
	var runtime := ConfigRuntime.shared()
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
		var card: RoleCard = RoleCardScene.instantiate()
		role_list.add_child(card)
		card.bind_data(role, graph)
