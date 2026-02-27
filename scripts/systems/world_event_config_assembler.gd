extends RefCounted
class_name WorldEventConfigAssembler

# 功能：将收束后的 6 张 CSV 配置组装为世界事件引擎可直接消费的数据结构。
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


# 功能：读取编译所需的 6 张核心 CSV 表。
static func _load_tables(base: String) -> Dictionary:
	var required_files: Array = [
		"world_seed.csv",
		"events.csv",
		"event_conditions.csv",
		"event_outcomes.csv",
		"options.csv",
		"option_rules.csv"
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
# 说明：从 world_seed.csv 的 section/scope/key/value 通用结构解码。
static func _assemble_world_state(tables: Dictionary) -> Dictionary:
	var rows: Array = tables.get("world_seed.csv", [])

	var world_state = {
		"turn": 1,
		"currentLocationId": "",
		"flags": {},
		"params": {},
		"locationState": {},
		"npcPresence": {},
		"player": {},
		"history": [],
		"chainContext": null,
		"forcedNextEventId": ""
	}

	var history_pairs: Array = []
	var chain_seed: Dictionary = {}

	for row_variant in rows:
		var row: Dictionary = row_variant
		var section := str(row.get("section", "")).strip_edges()
		var scope_a := str(row.get("scope_a", "")).strip_edges()
		var key := str(row.get("key", "")).strip_edges()
		var value_text := str(row.get("value", "")).strip_edges()

		if section.is_empty() or key.is_empty():
			continue

		match section:
			"core":
				if key == "turn":
					world_state["turn"] = _to_int(value_text, 1)
				elif key == "current_location_id":
					world_state["currentLocationId"] = value_text
				elif key == "forced_next_event_id":
					world_state["forcedNextEventId"] = value_text
			"flag":
				var flags: Dictionary = world_state.get("flags", {})
				flags[key] = _parse_literal(value_text)
				world_state["flags"] = flags
			"param":
				var params: Dictionary = world_state.get("params", {})
				params[key] = _to_int(value_text, 0)
				world_state["params"] = params
			"player":
				var player: Dictionary = world_state.get("player", {})
				player[key] = _parse_literal(value_text)
				world_state["player"] = player
			"location_state":
				if scope_a.is_empty():
					continue
				var location_state: Dictionary = world_state.get("locationState", {})
				if not location_state.has(scope_a):
					location_state[scope_a] = {}
				var state_item: Dictionary = location_state[scope_a]
				state_item[key] = _parse_literal(value_text)
				location_state[scope_a] = state_item
				world_state["locationState"] = location_state
			"npc_presence":
				if scope_a.is_empty() or key != "npc_id" or value_text.is_empty():
					continue
				var npc_presence: Dictionary = world_state.get("npcPresence", {})
				if not npc_presence.has(scope_a):
					npc_presence[scope_a] = []
				var present_list: Array = npc_presence[scope_a]
				present_list.append(value_text)
				npc_presence[scope_a] = present_list
				world_state["npcPresence"] = npc_presence
			"history":
				if key != "event_id":
					continue
				var seq := _to_int(scope_a, 0)
				if seq <= 0 or value_text.is_empty():
					continue
				history_pairs.append({"seq": seq, "event_id": value_text})
			"chain":
				chain_seed[key] = value_text
			_:
				continue

	_sort_history_pairs(history_pairs)
	var history: Array = []
	for pair_variant in history_pairs:
		var pair: Dictionary = pair_variant
		history.append(str(pair.get("event_id", "")))
	world_state["history"] = history

	world_state["chainContext"] = _build_chain_context_from_seed(chain_seed)
	return {"ok": true, "world_state": world_state}


# 功能：组装 choice_points 与 options 数据。
# 说明：新结构中不再单独维护 choice_points.csv，按 options.csv 自动归组。
static func _assemble_choice_points(tables: Dictionary) -> Dictionary:
	var option_rows: Array = tables.get("options.csv", [])
	var rule_rows: Array = tables.get("option_rules.csv", [])

	var cp_map: Dictionary = {}
	var cp_order: Array = []
	var option_ref: Dictionary = {}

	for row_variant in option_rows:
		var row: Dictionary = row_variant
		var option_id := str(row.get("option_id", "")).strip_edges()
		var cp_id := str(row.get("choice_point_id", "")).strip_edges()
		if option_id.is_empty() or cp_id.is_empty():
			continue
		if option_ref.has(option_id):
			return {"ok": false, "error": "duplicate option id: %s" % option_id}

		if not cp_map.has(cp_id):
			cp_map[cp_id] = {"id": cp_id, "options": []}
			cp_order.append(cp_id)

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
			},
			"_display_order": _to_int(row.get("display_order", "0"), 0)
		}

		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		options.append(option)
		cp_item["options"] = options
		cp_map[cp_id] = cp_item
		option_ref[option_id] = {"cp_id": cp_id, "index": options.size() - 1}

	for row_variant in rule_rows:
		var row: Dictionary = row_variant
		var option_id := str(row.get("option_id", "")).strip_edges()
		if option_id.is_empty() or not option_ref.has(option_id):
			continue
		_apply_option_rule_row(row, cp_map, option_ref)

	var out_choice_points: Array = []
	for cp_id_variant in cp_order:
		var cp_id := str(cp_id_variant)
		var cp_item: Dictionary = cp_map[cp_id]
		var options: Array = cp_item.get("options", [])
		_sort_options_by_display_order(options)
		for idx in options.size():
			var option: Dictionary = options[idx]
			option.erase("_display_order")
			options[idx] = option
		cp_item["options"] = options
		out_choice_points.append(cp_item)

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
	var event_rows: Array = tables.get("events.csv", [])
	var condition_rows: Array = tables.get("event_conditions.csv", [])
	var outcome_rows: Array = tables.get("event_outcomes.csv", [])

	var event_map: Dictionary = {}
	var event_order: Array = []

	for row_variant in event_rows:
		var row: Dictionary = row_variant
		var event_id := str(row.get("event_id", "")).strip_edges()
		if event_id.is_empty():
			continue
		if event_map.has(event_id):
			return {"ok": false, "error": "duplicate event id: %s" % event_id}

		var event_def = {
			"id": event_id,
			"title": str(row.get("title", "")),
			"baseWeight": _to_int(row.get("base_weight", "10"), 10),
			"tags": _split_text_list(str(row.get("tags", "")), ";"),
			"eligibility": {},
			"weightRules": [],
			"continuationPolicy": str(row.get("continuation_policy", "ReturnToScheduler")),
			"effects": {}
		}

		var cp_id := str(row.get("choice_point_id", "")).strip_edges()
		if not cp_id.is_empty():
			if not choice_point_ids.has(cp_id):
				return {"ok": false, "error": "event references missing choice point: %s -> %s" % [event_id, cp_id]}
			event_def["choicePointId"] = cp_id

		event_map[event_id] = event_def
		event_order.append(event_id)

	for row_variant in condition_rows:
		var row: Dictionary = row_variant
		var event_id := str(row.get("event_id", "")).strip_edges()
		if event_id.is_empty() or not event_map.has(event_id):
			continue
		_apply_event_condition_row(event_map[event_id], row)

	for row_variant in outcome_rows:
		var row: Dictionary = row_variant
		var event_id := str(row.get("event_id", "")).strip_edges()
		if event_id.is_empty() or not event_map.has(event_id):
			continue
		_apply_event_outcome_row(event_map[event_id], row)

	var events: Array = []
	for event_id_variant in event_order:
		var event_def: Dictionary = event_map[str(event_id_variant)]
		# 说明：若 chainPatch 为空则移除，保持输出结构简洁。
		if event_def.has("chainPatch"):
			var patch: Dictionary = event_def.get("chainPatch", {})
			if patch.is_empty():
				event_def.erase("chainPatch")
		events.append(event_def)

	return {"ok": true, "events": events}


# 功能：应用单行事件条件。
static func _apply_event_condition_row(event_def: Dictionary, row: Dictionary) -> void:
	var condition_type := str(row.get("condition_type", "")).strip_edges()
	var left := str(row.get("left", "")).strip_edges()
	var op := str(row.get("op", "")).strip_edges()
	var right := str(row.get("right", "")).strip_edges()
	var delta_text := str(row.get("delta", "")).strip_edges()

	if condition_type.is_empty():
		return

	if condition_type == "required_location":
		if right.is_empty():
			return
		var eligibility_a: Dictionary = event_def.get("eligibility", {})
		var locations: Array = eligibility_a.get("requiredLocations", [])
		locations.append(right)
		eligibility_a["requiredLocations"] = locations
		event_def["eligibility"] = eligibility_a
		return

	if condition_type == "required_npc":
		if right.is_empty():
			return
		var eligibility_b: Dictionary = event_def.get("eligibility", {})
		var npcs: Array = eligibility_b.get("requiredNPCsPresent", [])
		npcs.append(right)
		eligibility_b["requiredNPCsPresent"] = npcs
		event_def["eligibility"] = eligibility_b
		return

	if condition_type == "required_location_flag":
		if left.is_empty():
			return
		var eligibility_c: Dictionary = event_def.get("eligibility", {})
		var clauses: Array = eligibility_c.get("requiredLocationFlags", [])
		clauses.append({"key": left, "op": op if not op.is_empty() else "==", "value": _parse_literal(right)})
		eligibility_c["requiredLocationFlags"] = clauses
		event_def["eligibility"] = eligibility_c
		return

	if condition_type == "weight_rule":
		if left.is_empty() or op.is_empty() or right.is_empty():
			return
		var rules: Array = event_def.get("weightRules", [])
		rules.append({"when": "%s %s %s" % [left, op, right], "delta": _to_int(delta_text, 0)})
		event_def["weightRules"] = rules


# 功能：应用单行事件后果。
# 说明：branch 当前仅处理 default，其他分支预留给未来扩展。
static func _apply_event_outcome_row(event_def: Dictionary, row: Dictionary) -> void:
	var branch := str(row.get("branch", "default")).strip_edges()
	if not branch.is_empty() and branch != "default":
		return

	var target := str(row.get("target", "")).strip_edges()
	var op := str(row.get("op", "")).strip_edges()
	var key := str(row.get("key", "")).strip_edges()
	var value_text := str(row.get("value", "")).strip_edges()

	if target == "chain_context" and op == "patch":
		var patch: Dictionary = event_def.get("chainPatch", {})
		_apply_chain_patch_item(patch, key, value_text)
		event_def["chainPatch"] = patch
		return

	var effects: Dictionary = event_def.get("effects", {})
	_apply_effect_or_resolution_action(effects, target, op, key, value_text)
	event_def["effects"] = effects


# 功能：应用单行选项规则。
static func _apply_option_rule_row(row: Dictionary, cp_map: Dictionary, option_ref: Dictionary) -> void:
	var option_id := str(row.get("option_id", "")).strip_edges()
	var ref: Dictionary = option_ref[option_id]
	var cp_id := str(ref.get("cp_id", ""))
	var index := int(ref.get("index", -1))
	if index < 0 or not cp_map.has(cp_id):
		return

	var cp_item: Dictionary = cp_map[cp_id]
	var options: Array = cp_item.get("options", [])
	if index >= options.size():
		return

	var option: Dictionary = options[index]
	var rule_type := str(row.get("rule_type", "")).strip_edges()
	var branch := str(row.get("branch", "default")).strip_edges()
	var left := str(row.get("left", "")).strip_edges()
	var op := str(row.get("op", "")).strip_edges()
	var right := str(row.get("right", "")).strip_edges()
	var target := str(row.get("target", "")).strip_edges()
	var key := str(row.get("key", "")).strip_edges()
	var value_text := str(row.get("value", "")).strip_edges()

	if rule_type == "visibility":
		if not left.is_empty() and not op.is_empty() and not right.is_empty():
			var visibility_when: Array = option.get("visibilityWhen", [])
			visibility_when.append("%s %s %s" % [left, op, right])
			option["visibilityWhen"] = visibility_when
	elif rule_type == "eligibility":
		if not left.is_empty():
			var eligibility: Dictionary = option.get("eligibility", {})
			if op.is_empty():
				eligibility[left] = right
			else:
				eligibility[left] = op + right
			option["eligibility"] = eligibility
	elif rule_type == "cost":
		if not key.is_empty():
			var cost: Dictionary = option.get("cost", {})
			cost[key] = _to_int(value_text, 0)
			option["cost"] = cost
	elif rule_type == "check":
		var check_variant: Variant = option.get("check", {})
		var check: Dictionary = {}
		if typeof(check_variant) == TYPE_DICTIONARY and check_variant != null:
			check = check_variant
		if key == "type":
			check["type"] = value_text
		elif key == "successRate":
			check["successRate"] = _to_float(value_text, 1.0)
		option["check"] = check
	elif rule_type == "resolution":
		if branch == "fail":
			var fail_check_variant: Variant = option.get("check", {})
			var fail_check: Dictionary = {}
			if typeof(fail_check_variant) == TYPE_DICTIONARY and fail_check_variant != null:
				fail_check = fail_check_variant
			var fail_resolution: Dictionary = fail_check.get(
				"onFailResolution",
				{
					"worldStatePatch": {},
					"forcedNextEventId": "",
					"chainContextPatch": {}
				}
			)
			_apply_effect_or_resolution_action(fail_resolution, target, op, key, value_text)
			fail_check["onFailResolution"] = fail_resolution
			option["check"] = fail_check
		else:
			var resolution: Dictionary = option.get("resolution", {})
			_apply_effect_or_resolution_action(resolution, target, op, key, value_text)
			option["resolution"] = resolution

	options[index] = option
	cp_item["options"] = options
	cp_map[cp_id] = cp_item


# 功能：统一应用 effects 与 resolution 行为动作。
# 说明：事件 effects 与选项 resolution 共享 target/op/key/value 语义，复用该函数。
static func _apply_effect_or_resolution_action(container: Dictionary, target: String, op: String, key: String, value_text: String) -> void:
	if target == "params" and op == "add":
		var params_patch: Dictionary = container.get("addParams", container.get("worldStatePatch", {}).get("params", {}))
		params_patch[key] = int(params_patch.get(key, 0)) + _to_int(value_text, 0)
		if container.has("worldStatePatch"):
			var world_patch_a: Dictionary = container.get("worldStatePatch", {})
			world_patch_a["params"] = params_patch
			container["worldStatePatch"] = world_patch_a
		else:
			container["addParams"] = params_patch
		return

	if target == "flags" and op == "set":
		var flags_patch: Dictionary = container.get("setFlags", container.get("worldStatePatch", {}).get("flags", {}))
		flags_patch[key] = _parse_literal(value_text)
		if container.has("worldStatePatch"):
			var world_patch_b: Dictionary = container.get("worldStatePatch", {})
			world_patch_b["flags"] = flags_patch
			container["worldStatePatch"] = world_patch_b
		else:
			container["setFlags"] = flags_patch
		return

	if target == "world" and op == "set_location":
		if container.has("worldStatePatch"):
			var world_patch_c: Dictionary = container.get("worldStatePatch", {})
			world_patch_c["currentLocationId"] = value_text
			container["worldStatePatch"] = world_patch_c
		else:
			container["setLocation"] = value_text
		return

	if target == "world" and op == "set_forced_next":
		if container.has("worldStatePatch"):
			container["forcedNextEventId"] = value_text
		else:
			container["forcedNextEventId"] = value_text
		return

	if target == "world" and op == "end_chain":
		container["endChain"] = _to_bool(value_text)
		return

	if target == "world" and op == "clear_forced_next":
		container["clearForcedNext"] = _to_bool(value_text)
		return

	if target == "chain_context" and op == "patch":
		var chain_patch: Dictionary = container.get("chainContextPatch", {})
		_apply_chain_patch_item(chain_patch, key, value_text)
		container["chainContextPatch"] = chain_patch


# 功能：应用 chain patch 单项。
# 说明：兼容 allowedTags/weightBias 的 JSON 文本与拆分字段写法。
static func _apply_chain_patch_item(patch: Dictionary, key: String, value_text: String) -> void:
	if key.is_empty():
		return

	if key == "chainId":
		patch[key] = value_text
		return
	if key == "stage" or key == "stageDelta" or key == "exitWhenStageGte":
		patch[key] = _to_int(value_text, 0)
		return

	if key == "allowedTags":
		var parsed_tags: Variant = JSON.parse_string(value_text)
		if typeof(parsed_tags) == TYPE_ARRAY:
			patch[key] = parsed_tags
		else:
			patch[key] = _split_text_list(value_text, ";")
		return

	if key == "weightBias":
		var parsed_bias: Variant = JSON.parse_string(value_text)
		if typeof(parsed_bias) == TYPE_DICTIONARY:
			patch[key] = parsed_bias
		return

	if key.begins_with("weightBias."):
		var tag := key.trim_prefix("weightBias.")
		if tag.is_empty():
			return
		var bias: Dictionary = patch.get("weightBias", {})
		bias[tag] = _to_int(value_text, 0)
		patch["weightBias"] = bias
		return

	patch[key] = _parse_literal(value_text)


# 功能：从 world_seed 的 chain section 提取 chainContext。
static func _build_chain_context_from_seed(chain_seed: Dictionary) -> Variant:
	var chain_id := str(chain_seed.get("chain_id", "")).strip_edges()
	if chain_id.is_empty():
		return null

	var ctx = {
		"chainId": chain_id,
		"stage": _to_int(chain_seed.get("stage", "1"), 1),
		"allowedTags": [],
		"weightBias": {},
		"exitWhenStageGte": _to_int(chain_seed.get("exit_when_stage_gte", "0"), 0)
	}

	var tags_text := str(chain_seed.get("allowed_tags_json", "")).strip_edges()
	if not tags_text.is_empty():
		var parsed_tags: Variant = JSON.parse_string(tags_text)
		if typeof(parsed_tags) == TYPE_ARRAY:
			ctx["allowedTags"] = parsed_tags

	var bias_text := str(chain_seed.get("weight_bias_json", "")).strip_edges()
	if not bias_text.is_empty():
		var parsed_bias: Variant = JSON.parse_string(bias_text)
		if typeof(parsed_bias) == TYPE_DICTIONARY:
			ctx["weightBias"] = parsed_bias

	return ctx


# 功能：按 display_order 升序排序选项。
static func _sort_options_by_display_order(options: Array) -> void:
	for i in range(1, options.size()):
		var current: Dictionary = options[i]
		var current_order := int(current.get("_display_order", 0))
		var j := i - 1
		while j >= 0:
			var left: Dictionary = options[j]
			if int(left.get("_display_order", 0)) <= current_order:
				break
			options[j + 1] = options[j]
			j -= 1
		options[j + 1] = current


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


# 功能：按分隔符拆分文本数组，并去除空项。
static func _split_text_list(text: String, sep: String) -> Array:
	var out: Array = []
	for item in text.split(sep, false):
		var normalized := str(item).strip_edges()
		if not normalized.is_empty():
			out.append(normalized)
	return out


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
