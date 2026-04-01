extends RefCounted
class_name ConfigLoader

# ConfigLoader
# 职责：
# - 从磁盘读取配置文件，并解析为类型化模型对象。
# - 不负责缓存、不提供单例、不承担业务流程编排。
# - 作为底层数据源，供 ConfigRuntime 统一调度调用。
const RoleState := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")

# 通用 CSV 解析函数，供下方所有 load_* 接口复用。
# 返回：
# - {"ok": true, "headers": Array[String], "rows": Array[Dictionary]}
# - {"ok": false, "error": String}
static func load_csv_table(path: String) -> Dictionary:
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

	return {"ok": true, "headers": headers, "rows": rows}

# 从 roles.csv 加载角色定义，并转换为 RoleState 对象列表。
# 返回：
# - {"ok": true, "roles": Array[RoleState]}
# - {"ok": false, "error": String}
static func load_roles(path: String) -> Dictionary:
	var table_result := load_csv_table(path)
	if not table_result.get("ok", false):
		return table_result

	var roles: Array = []
	var rows: Array = table_result["rows"]
	for row_variant in rows:
		var row: Dictionary = row_variant
		var role := RoleState.new(
			str(row.get("role_id", "")),
			str(row.get("role_type", "")),
			str(row.get("display_name", "")),
			str(row.get("location_id", "")),
			str(row.get("portrait_file", "")),
			{
				"aptitude": _to_int(row.get("aptitude", "1"), 1),
				"physique": _to_int(row.get("physique", "1"), 1),
				"craft": _to_int(row.get("craft", "1"), 1),
				"insight": _to_int(row.get("insight", "1"), 1),
				"xinxing": clampi(_to_int(row.get("xinxing", "0"), 0), -2, 2)
			},
			{
				"hp": _to_int(row.get("hp", "0"), 0),
				"energy": _to_int(row.get("energy", "0"), 0),
				"gold": _to_int(row.get("gold", "0"), 0)
			}
		)
		roles.append(role)

	return {"ok": true, "roles": roles}

# 从地点邻接配置加载 LocationGraph。
# 返回：
# - {"ok": true, "graph": LocationGraph}
# - {"ok": false, "error": String}
static func load_location_graph(path: String) -> Dictionary:
	var table_result := load_csv_table(path)
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
		graph.set_art_file(location_id, str(row.get("art_file", "")))
		graph.set_display_name(location_id, str(row.get("display_name", "")))

	return {"ok": true, "graph": graph}

# 从好感度配置加载 AffinityMap。
# 返回：
# - {"ok": true, "affinity": AffinityMap}
# - {"ok": false, "error": String}
static func load_affinity_map(path: String) -> Dictionary:
	var table_result := load_csv_table(path)
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

# 从 creation_questions.csv 加载开局选择配置，解析为结构化问题-选项树。
# 返回：
# - {"ok": true, "data": Array} — data 为按行序排列的问题数组
# - {"ok": false, "error": String}
static func load_creation_config(path: String) -> Dictionary:
	var table_result := load_csv_table(path)
	if not table_result.get("ok", false):
		return table_result

	var rows: Array = table_result["rows"]
	# 按行序收集问题和选项，同 question_id 的行合并为一个问题。
	var questions: Array = []
	# 当前正在构建的问题 ID → questions 数组中的索引。
	var question_index_map: Dictionary = {}
	# 当前问题内的选项 ID → options 数组中的索引。
	var option_index_maps: Dictionary = {}

	for row_variant in rows:
		var row: Dictionary = row_variant
		var qid := str(row.get("question_id", "")).strip_edges()
		if qid.is_empty():
			continue

		# 若该问题尚未出现，创建新问题条目。
		if not question_index_map.has(qid):
			var question: Dictionary = {
				"question_id": qid,
				"question_text": str(row.get("question_text", "")),
				"condition": str(row.get("condition", "")),
				"options": []
			}
			question_index_map[qid] = questions.size()
			option_index_maps[qid] = {}
			questions.append(question)

		var q_idx: int = int(question_index_map[qid])
		var question: Dictionary = questions[q_idx]
		var options: Array = question["options"]
		var oid := str(row.get("option_id", "")).strip_edges()
		if oid.is_empty():
			continue

		# 构建 effect 条目。
		var effect: Dictionary = {
			"target": str(row.get("effect_target", "")),
			"key": str(row.get("effect_key", "")),
			"value": str(row.get("effect_value", ""))
		}

		# 若该选项已存在，追加 effect；否则创建新选项。
		var opt_map: Dictionary = option_index_maps[qid]
		if opt_map.has(oid):
			var o_idx: int = int(opt_map[oid])
			var existing_option: Dictionary = options[o_idx]
			var effects: Array = existing_option["effects"]
			effects.append(effect)
		else:
			var new_option: Dictionary = {
				"option_id": oid,
				"option_text": str(row.get("option_text", "")),
				"effects": [effect]
			}
			opt_map[oid] = options.size()
			options.append(new_option)

	return {"ok": true, "data": questions}


static func _to_int(value: Variant, default_value: int) -> int:
	var text := str(value).strip_edges()
	if text.is_empty():
		return default_value
	if text.is_valid_int():
		return int(text)
	return default_value
