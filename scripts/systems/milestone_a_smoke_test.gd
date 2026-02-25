extends RefCounted
class_name MilestoneASmokeTest

const RoleState := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")
const RuleEngine := preload("res://scripts/systems/rule_engine.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")

static func run() -> Dictionary:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded()
	if not load_result.get("ok", false):
		return load_result
	var context := runtime.build_context()
	if not context.get("ok", false):
		return context

	return run_with_context(context)

static func run_with_context(context: Dictionary) -> Dictionary:
	var player: RoleState = context["player"]
	var npc: RoleState = context["npc"]
	var graph: LocationGraph = context["graph"]
	var affinity: AffinityMap = context["affinity"]

	var role_apply := RuleEngine.apply_role_delta(
		player,
		{"will": 5, "luck": -2},
		{"money": -25, "manpower": 2},
		{"will": 7, "intelligence": 8, "charm": 8, "luck": 6}
	)
	if not role_apply.get("ok", false):
		return role_apply

	var affinity_next := RuleEngine.apply_affinity_delta(
		affinity.get_score(player.role_id, npc.role_id),
		15
	)
	affinity.set_score(player.role_id, npc.role_id, int(affinity_next["score"]))

	var can_move_to_market := RuleEngine.can_move(graph, player.location_id, "market")
	var can_move_to_forest := RuleEngine.can_move(graph, player.location_id, "forest")
	var player_portrait_loaded := player.load_portrait_texture() != null

	return {
		"ok": true,
		"player": player.to_dict(),
		"player_portrait_loaded": player_portrait_loaded,
		"affinity_score": affinity.get_score(player.role_id, npc.role_id),
		"affinity_tier": str(affinity_next["tier"]),
		"can_move_to_market": can_move_to_market,
		"can_move_to_forest": can_move_to_forest
	}
