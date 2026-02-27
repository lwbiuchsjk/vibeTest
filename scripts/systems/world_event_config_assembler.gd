extends RefCounted
class_name WorldEventConfigAssembler

# 功能：将 CSV 配置组装为世界事件引擎可直接消费的数据结构。
const ConfigLoader = preload("res://scripts/systems/config_loader.gd")


# 功能：从 CSV 目录编译配置并输出运行时数据结构。
static func compile_from_csv_dir(csv_dir_path: String) -> Dictionary:
	var base = csv_dir_path.strip_edges()
	if base.is_empty():
		return {"ok": false, "error": "csv dir path is empty"}

	var tables_result = _load_tables(base)
	if not tables_result.get("ok", false):
		return tables_result

	var tables: Dictionary = tables_result["tables"]

	var world_result = _assemble_world_state(tables)
	if not world_result.get("ok", false):
		return world_result

	var choice_result = _assemble_choice_points(tables)
	if not choice_result.get("ok", false):
		return choice_result

	var events_result = _assemble_events(tables, choice_result.get("choice_point_ids", {}))
	if not events_result.get("ok", false):
		return events_result

	return {
		"ok": true,
		"data": {
			"world_state": world_result["world_state"],
			"events": events_result["events"],
			"choice_points": choice_result["choice_points"]
		}
	}


# 功能：读取编译所需的全部 CSV 表。
static func _load_tables(base: String) -> Dictionary:
	var required_files: Array = [
		"world_seed_core.csv",
		"world_seed_flags.csv",
		"world_seed_params.csv",
		"world_seed_location_state.csv",
		"world_seed_npc_presence.csv",
		"world_seed_player.csv",
		"world_seed_history.csv",
		"events.csv",
		"event_tags.csv",
		"event_eligibility_locations.csv",
		"event_eligibility_location_flags.csv",
		"event_eligibility_npcs.csv",
		"event_weight_rules.csv",
		"event_chain_patch.csv",
		"event_chain_bias.csv",
		"event_effects.csv",
		"choice_points.csv",
		"options.csv",
		"option_visibility_rules.csv",
		"option_eligibility_rules.csv",
		"option_costs.csv",
		"option_checks.csv",
		"option_resolutions.csv"
	]

	var tables: Dictionary = {}
	for file_variant in required_files:
		var file_name = str(file_variant)
		var path = _join_path(base, file_name)
		var table_result = ConfigLoader.load_csv_table(path)
		if not table_result.get("ok", false):
			return {"ok": false, "error": str(table_result.get("error", "load csv failed"))}
		tables[file_name] = table_result.get("rows", [])

	return {"ok": true, "tables": tables}


# 功能：组装 world_state 初始状态。
static func _assemble_world_state(tables: Dictionary) -> Dictionary:
	var core_rows: Array = tables.get("world_seed_core.csv", [])
	if core_rows.size() != 1:
		return {"ok": false, "error": "world_seed_core.csv must contain exactly one row"}
	var core: Dictionary = core_rows[0]

	var world_state = {
		"turn": _to_int(core.get("turn", "1"), 1),
		"currentLocationId": str(core.get("current_location_id", "")),
		"flags": {},
		"params": {},
		"locationState": {},
		"npcPresence": {},
		"player": {},
		"history": [],
		"chainContext": null,
		"forcedNextEventId": str(core.get("forced_next_event_id", ""))
	}

	var flags: Dictionary = {}
	for row_variant in tables.get("world_seed_flags.csv", []):
		var row: Dictionary = row_variant
		var key = str(row.get("flag_key", ""))
		if key.is_empty():
			continue
		flags[key] = _parse_literal(str(row.get("flag_value", "")))
	world_state["flags"] = flags

	var params: Dictionary = {}
	for row_variant in tables.get("world_seed_params.csv", []):
		var row: Dictionary = row_variant
		var key = str(row.get("param_key", ""))
		if key.is_empty():
			continue
		params[key] = _to_int(row.get("param_value", "0"), 0)
	world_state["params"] = params

	var location_state: Dictionary = {}
	for row_variant in tables.get("world_seed_location_state.csv", []):
		var row: Dictionary = row_variant
		var location_id = str(row.get("location_id", ""))
		var key = str(row.get("key", ""))
		if location_id.is_empty() or key.is_empty():
			continue
		if not location_state.has(location_id):
			location_state[location_id] = {}
		var state_item: Dictionary = location_state[location_id]
		state_item[key] = _parse_literal(str(row.get("value", "")))
		location_state[location_id] = state_item
	world_state["locationState"] = location_state

	var npc_presence: Dictionary = {}
	for row_variant in tables.get("world_seed_npc_presence.csv", []):
		var row: Dictionary = row_variant
		var location_id = str(row.get("location_id", ""))
		var npc_id = str(row.get("npc_id", ""))
		if location_id.is_empty() or npc_id.is_empty():
			continue
		if not npc_presence.has(location_id):
			npc_presence[location_id] = []
		var present_list: Array = npc_presence[location_id]
		present_list.append(npc_id)
		npc_presence[location_id] = present_list
	world_state["npcPresence"] = npc_presence

	var player: Dictionary = {}
	for row_variant in tables.get("world_seed_player.csv", []):
		var row: Dictionary = row_variant
		var key = str(row.get("key", ""))
		if key.is_empty():
			continue
		player[key] = _parse_literal(str(row.get("value", "")))
	world_state["player"] = player

	var history_rows: Array = tables.get("world_seed_history.csv", [])
	var history_pairs: Array = []
	for row_variant in history_rows:
		var row: Dictionary = row_variant
		var seq = _to_int(row.get("seq", "0"), 0)
		var event_id = str(row.get("event_id", ""))
		if seq <= 0 or event_id.is_empty():
			continue
		history_pairs.append({"seq": seq, "event_id": event_id})
	_sort_history_pairs(history_pairs)

	var history: Array = []
	for pair_variant in history_pairs:
		var pair: Dictionary = pair_variant
		history.append(str(pair.get("event_id", "")))
	world_state["history"] = history

	world_state["chainContext"] = _build_chain_context_from_core(core)
	return {"ok": true, "world_state": world_state}


# 功能：组装 choice_points 与 options 数据。
static func _assemble_choice_points(tables: Dictionary) -> Dictionary:
	var cp_rows: Array = tables.get("choice_points.csv", [])
	var cp_map: Dictionary = {}
	var cp_order: Array = []

	for row_variant in cp_rows:
		var row: Dictionary = row_variant
		var cp_id = str(row.get("choice_point_id", ""))
		if cp_id.is_empty():
			continue
		if cp_map.has(cp_id):
			return {"ok": false, "error": "duplicate choice point id: %s" % cp_id}
		cp_map[cp_id] = {"id": cp_id, "options": []}
		cp_order.append(cp_id)

	for row_variant in tables.get("options.csv", []):
		var row: Dictionary = row_variant
		var option_id = str(row.get("option_id", ""))
		var cp_id = str(row.get("choice_point_id", ""))
		if option_id.is_empty() or cp_id.is_empty():
			continue
		if not cp_map.has(cp_id):
			return {"ok": false, "error": "options.csv references missing choice point: %s" % cp_id}

		var option = {
			"id": option_id,
			"text": str(row.get("text", "")),
			"eligibility": {},
			"cost": {},
			"check": null,
			"resolution": {
				"worldStatePatch": {},
				"forcedNextEventId": "",
				"chainContextPatch": {}
			}
		}
		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		options.append(option)
		cp_item["options"] = options
		cp_map[cp_id] = cp_item

	var option_ref: Dictionary = {}
	for cp_id_variant in cp_order:
		var cp_id = str(cp_id_variant)
		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		for idx in options.size():
			var option: Dictionary = options[idx]
			option_ref[str(option.get("id", ""))] = {"cp_id": cp_id, "index": idx}

	_apply_option_visibility_rules(tables.get("option_visibility_rules.csv", []), cp_map, option_ref)
	_apply_option_eligibility_rules(tables.get("option_eligibility_rules.csv", []), cp_map, option_ref)
	_apply_option_costs(tables.get("option_costs.csv", []), cp_map, option_ref)
	_apply_option_checks(tables.get("option_checks.csv", []), cp_map, option_ref)
	_apply_option_resolutions(tables.get("option_resolutions.csv", []), cp_map, option_ref)

	var out_choice_points: Array = []
	for cp_id_variant in cp_order:
		out_choice_points.append(cp_map[str(cp_id_variant)])

	var choice_point_ids: Dictionary = {}
	for cp_id_variant in cp_order:
		choice_point_ids[str(cp_id_variant)] = true

	return {
		"ok": true,
		"choice_points": out_choice_points,
		"choice_point_ids": choice_point_ids
	}


# 功能：组装 events 数据并做 choice point 外键校验。
static func _assemble_events(tables: Dictionary, choice_point_ids: Dictionary) -> Dictionary:
	var rows: Array = tables.get("events.csv", [])
	var event_map: Dictionary = {}
	var event_order: Array = []

	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		if event_id.is_empty():
			continue
		if event_map.has(event_id):
			return {"ok": false, "error": "duplicate event id: %s" % event_id}

		var event_def = {
			"id": event_id,
			"title": str(row.get("title", "")),
			"baseWeight": _to_int(row.get("base_weight", "10"), 10),
			"tags": [],
			"eligibility": {},
			"weightRules": [],
			"continuationPolicy": str(row.get("continuation_policy", "ReturnToScheduler")),
			"effects": {}
		}

		var cp_id = str(row.get("choice_point_id", "")).strip_edges()
		if not cp_id.is_empty():
			if not choice_point_ids.has(cp_id):
				return {"ok": false, "error": "event references missing choice point: %s -> %s" % [event_id, cp_id]}
			event_def["choicePointId"] = cp_id

		event_map[event_id] = event_def
		event_order.append(event_id)

	_apply_event_tags(tables.get("event_tags.csv", []), event_map)
	_apply_event_eligibility_locations(tables.get("event_eligibility_locations.csv", []), event_map)
	_apply_event_eligibility_location_flags(tables.get("event_eligibility_location_flags.csv", []), event_map)
	_apply_event_eligibility_npcs(tables.get("event_eligibility_npcs.csv", []), event_map)
	_apply_event_weight_rules(tables.get("event_weight_rules.csv", []), event_map)
	_apply_event_chain_patch(tables.get("event_chain_patch.csv", []), event_map)
	_apply_event_chain_bias(tables.get("event_chain_bias.csv", []), event_map)
	_apply_event_effects(tables.get("event_effects.csv", []), event_map)

	var events: Array = []
	for event_id_variant in event_order:
		events.append(event_map[str(event_id_variant)])
	return {"ok": true, "events": events}


# 功能：回填事件 tags。
static func _apply_event_tags(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		var tag = str(row.get("tag", ""))
		if event_id.is_empty() or tag.is_empty() or not event_map.has(event_id):
			continue
		var event_def: Dictionary = event_map[event_id]
		var tags: Array = event_def.get("tags", [])
		tags.append(tag)
		event_def["tags"] = tags
		event_map[event_id] = event_def


# 功能：回填事件地点硬约束。
static func _apply_event_eligibility_locations(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		var location_id = str(row.get("location_id", ""))
		if event_id.is_empty() or location_id.is_empty() or not event_map.has(event_id):
			continue
		var event_def: Dictionary = event_map[event_id]
		var eligibility: Dictionary = event_def.get("eligibility", {})
		var required_locations: Array = eligibility.get("requiredLocations", [])
		required_locations.append(location_id)
		eligibility["requiredLocations"] = required_locations
		event_def["eligibility"] = eligibility
		event_map[event_id] = event_def


# 功能：回填事件地点状态硬约束。
static func _apply_event_eligibility_location_flags(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		if not event_map.has(event_id):
			continue
		var key = str(row.get("key", ""))
		var op = str(row.get("op", "=="))
		if key.is_empty():
			continue
		var event_def: Dictionary = event_map[event_id]
		var eligibility: Dictionary = event_def.get("eligibility", {})
		var clauses: Array = eligibility.get("requiredLocationFlags", [])
		clauses.append({"key": key, "op": op, "value": _parse_literal(str(row.get("value", "")))})
		eligibility["requiredLocationFlags"] = clauses
		event_def["eligibility"] = eligibility
		event_map[event_id] = event_def


# 功能：回填事件 NPC 在场硬约束。
static func _apply_event_eligibility_npcs(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		var npc_id = str(row.get("npc_id", ""))
		if event_id.is_empty() or npc_id.is_empty() or not event_map.has(event_id):
			continue
		var event_def: Dictionary = event_map[event_id]
		var eligibility: Dictionary = event_def.get("eligibility", {})
		var npcs: Array = eligibility.get("requiredNPCsPresent", [])
		npcs.append(npc_id)
		eligibility["requiredNPCsPresent"] = npcs
		event_def["eligibility"] = eligibility
		event_map[event_id] = event_def


# 功能：回填事件权重规则。
static func _apply_event_weight_rules(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		if not event_map.has(event_id):
			continue
		var left = str(row.get("left", "")).strip_edges()
		var op = str(row.get("op", "")).strip_edges()
		var right = str(row.get("right", "")).strip_edges()
		if left.is_empty() or op.is_empty() or right.is_empty():
			continue
		var event_def: Dictionary = event_map[event_id]
		var rules: Array = event_def.get("weightRules", [])
		rules.append({"when": "%s %s %s" % [left, op, right], "delta": _to_int(row.get("delta", "0"), 0)})
		event_def["weightRules"] = rules
		event_map[event_id] = event_def


# 功能：回填事件链补丁基础字段。
static func _apply_event_chain_patch(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		if not event_map.has(event_id):
			continue
		var event_def: Dictionary = event_map[event_id]
		var patch: Dictionary = event_def.get("chainPatch", {})

		var chain_id = str(row.get("chain_id", "")).strip_edges()
		var stage_text = str(row.get("stage", "")).strip_edges()
		var stage_delta_text = str(row.get("stage_delta", "")).strip_edges()
		var exit_stage_text = str(row.get("exit_when_stage_gte", "")).strip_edges()

		if not chain_id.is_empty():
			patch["chainId"] = chain_id
		if not stage_text.is_empty():
			patch["stage"] = _to_int(stage_text, 1)
		if not stage_delta_text.is_empty():
			patch["stageDelta"] = _to_int(stage_delta_text, 1)
		if not exit_stage_text.is_empty():
			patch["exitWhenStageGte"] = _to_int(exit_stage_text, 0)

		if not patch.is_empty():
			event_def["chainPatch"] = patch
			event_map[event_id] = event_def


# 功能：回填事件链偏置与允许标签。
static func _apply_event_chain_bias(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		var tag = str(row.get("tag", "")).strip_edges()
		if not event_map.has(event_id) or tag.is_empty():
			continue

		var event_def: Dictionary = event_map[event_id]
		var patch: Dictionary = event_def.get("chainPatch", {})
		var source = str(row.get("source", "")).strip_edges()

		if source == "allowed_tag":
			var allowed_tags: Array = patch.get("allowedTags", [])
			allowed_tags.append(tag)
			patch["allowedTags"] = allowed_tags
		else:
			var bias_text = str(row.get("bias", "")).strip_edges()
			var weight_bias: Dictionary = patch.get("weightBias", {})
			weight_bias[tag] = _to_int(bias_text, 0)
			patch["weightBias"] = weight_bias

		event_def["chainPatch"] = patch
		event_map[event_id] = event_def


# 功能：回填事件 effects。
static func _apply_event_effects(rows: Array, event_map: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var event_id = str(row.get("event_id", ""))
		if not event_map.has(event_id):
			continue

		var target = str(row.get("target", ""))
		var op = str(row.get("op", ""))
		var key = str(row.get("key", ""))
		var value_text = str(row.get("value", ""))

		var event_def: Dictionary = event_map[event_id]
		var effects: Dictionary = event_def.get("effects", {})

		if target == "params" and op == "add":
			var add_params: Dictionary = effects.get("addParams", {})
			add_params[key] = _to_int(value_text, 0)
			effects["addParams"] = add_params
		elif target == "flags" and op == "set":
			var set_flags: Dictionary = effects.get("setFlags", {})
			set_flags[key] = _parse_literal(value_text)
			effects["setFlags"] = set_flags
		elif target == "world" and op == "set_location":
			effects["setLocation"] = value_text
		elif target == "world" and op == "set_forced_next":
			effects["forcedNextEventId"] = value_text
		elif target == "world" and op == "end_chain":
			effects["endChain"] = _to_bool(value_text)
		elif target == "world" and op == "clear_forced_next":
			effects["clearForcedNext"] = _to_bool(value_text)

		event_def["effects"] = effects
		event_map[event_id] = event_def


# 功能：回填选项可见性规则。
static func _apply_option_visibility_rules(rows: Array, cp_map: Dictionary, option_ref: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var option_id = str(row.get("option_id", ""))
		if not option_ref.has(option_id):
			continue
		var ref: Dictionary = option_ref[option_id]
		var cp_id = str(ref.get("cp_id", ""))
		var index = int(ref.get("index", -1))
		if index < 0:
			continue

		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		var option: Dictionary = options[index]
		var visibility_when: Array = option.get("visibilityWhen", [])
		visibility_when.append("%s %s %s" % [str(row.get("left", "")), str(row.get("op", "")), str(row.get("right", ""))])
		option["visibilityWhen"] = visibility_when
		options[index] = option
		cp_item["options"] = options
		cp_map[cp_id] = cp_item


# 功能：回填选项 eligibility 规则。
static func _apply_option_eligibility_rules(rows: Array, cp_map: Dictionary, option_ref: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var option_id = str(row.get("option_id", ""))
		if not option_ref.has(option_id):
			continue
		var ref: Dictionary = option_ref[option_id]
		var cp_id = str(ref.get("cp_id", ""))
		var index = int(ref.get("index", -1))
		if index < 0:
			continue

		var path = str(row.get("left", "")).strip_edges()
		var op = str(row.get("op", "")).strip_edges()
		var right = str(row.get("right", "")).strip_edges()
		if path.is_empty():
			continue

		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		var option: Dictionary = options[index]
		var eligibility: Dictionary = option.get("eligibility", {})
		eligibility[path] = op + right
		option["eligibility"] = eligibility
		options[index] = option
		cp_item["options"] = options
		cp_map[cp_id] = cp_item


# 功能：回填选项 cost。
static func _apply_option_costs(rows: Array, cp_map: Dictionary, option_ref: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var option_id = str(row.get("option_id", ""))
		if not option_ref.has(option_id):
			continue
		var ref: Dictionary = option_ref[option_id]
		var cp_id = str(ref.get("cp_id", ""))
		var index = int(ref.get("index", -1))
		if index < 0:
			continue

		var key = str(row.get("key", "")).strip_edges()
		if key.is_empty():
			continue

		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		var option: Dictionary = options[index]
		var cost: Dictionary = option.get("cost", {})
		cost[key] = _to_int(row.get("value", "0"), 0)
		option["cost"] = cost
		options[index] = option
		cp_item["options"] = options
		cp_map[cp_id] = cp_item


# 功能：回填选项 check。
static func _apply_option_checks(rows: Array, cp_map: Dictionary, option_ref: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var option_id = str(row.get("option_id", ""))
		if not option_ref.has(option_id):
			continue
		var ref: Dictionary = option_ref[option_id]
		var cp_id = str(ref.get("cp_id", ""))
		var index = int(ref.get("index", -1))
		if index < 0:
			continue

		var check_type = str(row.get("check_type", "")).strip_edges()
		if check_type.is_empty():
			continue

		var check = {"type": check_type}
		var success_rate = str(row.get("success_rate", "")).strip_edges()
		if not success_rate.is_empty():
			check["successRate"] = _to_float(success_rate, 1.0)

		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		var option: Dictionary = options[index]
		option["check"] = check
		options[index] = option
		cp_item["options"] = options
		cp_map[cp_id] = cp_item


# 功能：回填选项 resolution（success/fail）。
static func _apply_option_resolutions(rows: Array, cp_map: Dictionary, option_ref: Dictionary) -> void:
	for row_variant in rows:
		var row: Dictionary = row_variant
		var option_id = str(row.get("option_id", ""))
		if not option_ref.has(option_id):
			continue
		var ref: Dictionary = option_ref[option_id]
		var cp_id = str(ref.get("cp_id", ""))
		var index = int(ref.get("index", -1))
		if index < 0:
			continue

		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		var option: Dictionary = options[index]
		var branch = str(row.get("branch", "success")).strip_edges()

		if branch == "fail":
			var check: Variant = option.get("check", {})
			if check == null or typeof(check) != TYPE_DICTIONARY:
				check = {}
			var check_dict: Dictionary = check
			var fail_resolution: Dictionary = check_dict.get("onFailResolution", {})
			_apply_resolution_row(fail_resolution, row)
			check_dict["onFailResolution"] = fail_resolution
			option["check"] = check_dict
		else:
			var resolution: Dictionary = option.get("resolution", {})
			_apply_resolution_row(resolution, row)
			option["resolution"] = resolution

		options[index] = option
		cp_item["options"] = options
		cp_map[cp_id] = cp_item


# 功能：将单行 resolution 配置应用到目标结构。
static func _apply_resolution_row(resolution: Dictionary, row: Dictionary) -> void:
	var target = str(row.get("target", "")).strip_edges()
	var op = str(row.get("op", "")).strip_edges()
	var key = str(row.get("key", "")).strip_edges()
	var value_text = str(row.get("value", ""))

	if target == "params" and op == "add":
		var world_patch: Dictionary = resolution.get("worldStatePatch", {})
		var params_patch: Dictionary = world_patch.get("params", {})
		params_patch[key] = _to_int(value_text, 0)
		world_patch["params"] = params_patch
		resolution["worldStatePatch"] = world_patch
	elif target == "flags" and op == "set":
		var world_patch: Dictionary = resolution.get("worldStatePatch", {})
		var flags_patch: Dictionary = world_patch.get("flags", {})
		flags_patch[key] = _parse_literal(value_text)
		world_patch["flags"] = flags_patch
		resolution["worldStatePatch"] = world_patch
	elif target == "world" and op == "set_forced_next":
		resolution["forcedNextEventId"] = value_text
	elif target == "world" and op == "set_location":
		var world_patch: Dictionary = resolution.get("worldStatePatch", {})
		world_patch["currentLocationId"] = value_text
		resolution["worldStatePatch"] = world_patch
	elif target == "chain_context" and op == "patch":
		var chain_patch: Dictionary = resolution.get("chainContextPatch", {})
		chain_patch[key] = _parse_literal(value_text)
		resolution["chainContextPatch"] = chain_patch


# 功能：从 world_seed_core 提取 chainContext。
static func _build_chain_context_from_core(core: Dictionary) -> Variant:
	var chain_id = str(core.get("chain_id", "")).strip_edges()
	if chain_id.is_empty():
		return null

	var ctx = {
		"chainId": chain_id,
		"stage": _to_int(core.get("chain_stage", "1"), 1),
		"allowedTags": [],
		"weightBias": {},
		"exitWhenStageGte": _to_int(core.get("chain_exit_when_stage_gte", "0"), 0)
	}

	var allowed_tags_json = str(core.get("chain_allowed_tags_json", "")).strip_edges()
	if not allowed_tags_json.is_empty():
		var parsed_tags: Variant = JSON.parse_string(allowed_tags_json)
		if typeof(parsed_tags) == TYPE_ARRAY:
			ctx["allowedTags"] = parsed_tags

	var weight_bias_json = str(core.get("chain_weight_bias_json", "")).strip_edges()
	if not weight_bias_json.is_empty():
		var parsed_bias: Variant = JSON.parse_string(weight_bias_json)
		if typeof(parsed_bias) == TYPE_DICTIONARY:
			ctx["weightBias"] = parsed_bias

	return ctx


# 功能：按 seq 升序排序历史记录。
static func _sort_history_pairs(history_pairs: Array) -> void:
	for i in range(1, history_pairs.size()):
		var current: Dictionary = history_pairs[i]
		var current_seq = int(current.get("seq", 0))
		var j = i - 1
		while j >= 0:
			var left: Dictionary = history_pairs[j]
			if int(left.get("seq", 0)) <= current_seq:
				break
			history_pairs[j + 1] = history_pairs[j]
			j -= 1
		history_pairs[j + 1] = current

static func _join_path(base: String, file_name: String) -> String:
	if base.ends_with("/") or base.ends_with("\\"):
		return base + file_name
	return base + "/" + file_name

static func _to_int(value: Variant, default_value: int) -> int:
	var text = str(value).strip_edges()
	if text.is_empty():
		return default_value
	if text.is_valid_int():
		return int(text)
	return default_value

static func _to_float(value: Variant, default_value: float) -> float:
	var text = str(value).strip_edges()
	if text.is_empty():
		return default_value
	if text.is_valid_float():
		return float(text)
	return default_value

static func _to_bool(value: Variant) -> bool:
	return str(value).strip_edges().to_lower() == "true"

static func _parse_literal(value: String) -> Variant:
	var text = value.strip_edges()
	if text.is_empty():
		return ""
	var lowered = text.to_lower()
	if lowered == "true":
		return true
	if lowered == "false":
		return false
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	return text


