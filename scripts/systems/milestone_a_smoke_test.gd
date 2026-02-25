extends RefCounted
class_name MilestoneASmokeTest

const RoleState := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")
const RuleEngine := preload("res://scripts/systems/rule_engine.gd")

# 里程碑A冒烟测试：
# - 角色属性与资源变更
# - 好感度更新与档位映射
# - 合法/非法移动校验
static func run() -> Dictionary:
	# 构造一个玩家和一个NPC作为测试输入。
	var player = RoleState.new(
		"player_001",
		"player",
		"Player",
		"town",
		{"will": 3, "intelligence": 4, "charm": 2, "luck": 1},
		{"money": 10, "manpower": 1}
	)
	var npc = RoleState.new(
		"npc_001",
		"npc",
		"NPC-A",
		"market",
		{"will": 2, "intelligence": 2, "charm": 3, "luck": 2},
		{"money": 3, "manpower": 0}
	)

	# 构建地点邻接关系：town <-> market。
	var graph = LocationGraph.new()
	graph.set_neighbors("town", ["market"])
	graph.set_neighbors("market", ["town"])

	# 初始化玩家对NPC的好感度。
	var affinity = AffinityMap.new()
	affinity.set_score(player.role_id, npc.role_id, 20)

	# 应用角色属性与资源变化。
	var role_apply = RuleEngine.apply_role_delta(
		player,
		{"will": 5, "luck": -2},
		{"money": -25, "manpower": 2},
		{"will": 7, "intelligence": 8, "charm": 8, "luck": 6}
	)
	if not role_apply.get("ok", false):
		return role_apply

	# 应用好感度变化并回写结果。
	var affinity_next = RuleEngine.apply_affinity_delta(
		affinity.get_score(player.role_id, npc.role_id),
		15
	)
	affinity.set_score(player.role_id, npc.role_id, int(affinity_next["score"]))

	# 校验合法移动与非法移动两种场景。
	var can_move_to_market = RuleEngine.can_move(graph, player.location_id, "market")
	var can_move_to_forest = RuleEngine.can_move(graph, player.location_id, "forest")

	return {
		"ok": true,
		"player": player.to_dict(),
		"affinity_score": affinity.get_score(player.role_id, npc.role_id),
		"affinity_tier": str(affinity_next["tier"]),
		"can_move_to_market": can_move_to_market,
		"can_move_to_forest": can_move_to_forest
	}
