extends RefCounted
class_name MilestoneASmokeTest

const RoleState := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")
const RuleEngine := preload("res://scripts/systems/rule_engine.gd")

const ROLES_CSV_PATH := "res://scripts/config/roles.csv"
const LOCATION_GRAPH_CSV_PATH := "res://scripts/config/location_graph.csv"
const AFFINITY_CSV_PATH := "res://scripts/config/affinity.csv"

static func run() -> Dictionary:
	var roles_result := _load_roles_from_csv(ROLES_CSV_PATH)
	if not roles_result.get("ok", false):
		return roles_result
	var player: RoleState = roles_result["player"]
	var npc: RoleState = roles_result["npc"]

	var graph_result := _load_location_graph_from_csv(LOCATION_GRAPH_CSV_PATH)
	if not graph_result.get("ok", false):
		return graph_result
	var graph: LocationGraph = graph_result["graph"]

	var affinity_result := _load_affinity_from_csv(AFFINITY_CSV_PATH)
	if not affinity_result.get("ok", false):
		return affinity_result
	var affinity: AffinityMap = affinity_result["affinity"]

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

static func _load_roles_from_csv(path: String) -> Dictionary:
	var table_result := _load_csv_table(path)
	if not table_result.get("ok", false):
		return table_result

	var player: RoleState = null
	var npc: RoleState = null
	var rows: Array = table_result["rows"]
	for row_variant in rows:
		var row: Dictionary = row_variant
		var role := RoleState.new(
			str(row.get("role_id", "")),
			str(row.get("role_type", "")),
			str(row.get("display_name", "")),
			str(row.get("location_id", "")),
			str(row.get("portrait_path", "")),
			{
				"will": _to_int(row.get("will", "1"), 1),
				"intelligence": _to_int(row.get("intelligence", "1"), 1),
				"charm": _to_int(row.get("charm", "1"), 1),
				"luck": _to_int(row.get("luck", "1"), 1)
			},
			{
				"money": _to_int(row.get("money", "0"), 0),
				"manpower": _to_int(row.get("manpower", "0"), 0)
			}
		)

		var role_type := role.role_type.to_lower()
		if role_type == "player" and player == null:
			player = role
		elif role_type == "npc" and npc == null:
			npc = role

	if player == null or npc == null:
		return {"ok": false, "error": "roles csv must contain at least one player and one npc: %s" % path}

	return {"ok": true, "player": player, "npc": npc}

static func _load_location_graph_from_csv(path: String) -> Dictionary:
	var table_result := _load_csv_table(path)
	if not table_result.get("ok", false):
		return table_result

	var graph := LocationGraph.new()
	var rows: Array = table_result["rows"]
	for row_variant in rows:
		var row: Dictionary = row_variant
		var location_id := str(row.get("location_id", ""))
		if location_id.is_empty():
			continue

		var neighbors_text := str(row.get("neighbors", ""))
		var neighbors: Array[String] = []
		for neighbor in neighbors_text.split(";", false):
			var normalized := str(neighbor).strip_edges()
			if not normalized.is_empty():
				neighbors.append(normalized)
		graph.set_neighbors(location_id, neighbors)

	return {"ok": true, "graph": graph}

static func _load_affinity_from_csv(path: String) -> Dictionary:
	var table_result := _load_csv_table(path)
	if not table_result.get("ok", false):
		return table_result

	var affinity := AffinityMap.new()
	var rows: Array = table_result["rows"]
	for row_variant in rows:
		var row: Dictionary = row_variant
		var from_role_id := str(row.get("from_role_id", ""))
		var to_role_id := str(row.get("to_role_id", ""))
		if from_role_id.is_empty() or to_role_id.is_empty():
			continue

		var score := _to_int(row.get("score", "0"), 0)
		affinity.set_score(from_role_id, to_role_id, score)

	return {"ok": true, "affinity": affinity}

static func _load_csv_table(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "csv not found: %s" % path}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open csv: %s" % path}
	if file.eof_reached():
		return {"ok": false, "error": "csv is empty: %s" % path}

	var header_row := file.get_csv_line()
	var headers: Array[String] = []
	for header in header_row:
		headers.append(str(header).strip_edges())
	if headers.is_empty():
		return {"ok": false, "error": "csv header is empty: %s" % path}

	var rows: Array = []
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
		rows.append(row)

	return {"ok": true, "rows": rows}

static func _to_int(value: Variant, default_value: int) -> int:
	var text := str(value).strip_edges()
	if text.is_empty():
		return default_value
	if text.is_valid_int():
		return int(text)
	return default_value
