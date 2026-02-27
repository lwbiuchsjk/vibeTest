extends RefCounted
class_name WorldEventEngine

# 功能：世界与事件引擎（MVP）。
# 说明：单一主循环推进，forcedNextEventId 优先级最高，链式通过 chainContext 塑形分布。

const POLICY_RETURN := "ReturnToScheduler"
const POLICY_CHAIN := "ChainContinue"
const POLICY_CHAIN_FORCED := "ChainContinueWithForcedNext"

var world_state: Dictionary = {}
var events: Array = []
var choice_points: Array = []
var _event_map: Dictionary = {}
var _choice_point_map: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pending_choice_context: Dictionary = {}

# 功能：初始化随机源。
# 说明：seed=0 使用随机种子；指定 seed 可复现结果，便于测试回归。
func _init(random_seed: int = 0) -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

# 功能：从 JSON 文件加载 world_state、events、choice_points。
# 说明：返回统一结构 {"ok": bool, "error": String?}。
func load_from_files(
	world_state_path: String,
	events_path: String,
	choice_points_path: String = ""
) -> Dictionary:
	var world_text := FileAccess.get_file_as_string(world_state_path)
	if world_text.is_empty():
		return {"ok": false, "error": "world state file is empty or missing: %s" % world_state_path}

	var events_text := FileAccess.get_file_as_string(events_path)
	if events_text.is_empty():
		return {"ok": false, "error": "events file is empty or missing: %s" % events_path}

	var choice_points_text := ""
	if not choice_points_path.strip_edges().is_empty():
		choice_points_text = FileAccess.get_file_as_string(choice_points_path)
		if choice_points_text.is_empty():
			return {"ok": false, "error": "choice points file is empty or missing: %s" % choice_points_path}

	return load_from_json_text(world_text, events_text, choice_points_text)

# 功能：从 JSON 文本加载数据。
# 说明：适合测试/热重载，成功后会重建事件与选择点索引。
func load_from_json_text(
	world_state_json: String,
	events_json: String,
	choice_points_json: String = ""
) -> Dictionary:
	var parsed_world: Variant = JSON.parse_string(world_state_json)
	if typeof(parsed_world) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid world state json"}

	var parsed_events: Variant = JSON.parse_string(events_json)
	if typeof(parsed_events) != TYPE_ARRAY:
		return {"ok": false, "error": "invalid events json"}

	var parsed_choice_points: Variant = []
	if not choice_points_json.strip_edges().is_empty():
		parsed_choice_points = JSON.parse_string(choice_points_json)
		if typeof(parsed_choice_points) != TYPE_ARRAY:
			return {"ok": false, "error": "invalid choice points json"}

	world_state = (parsed_world as Dictionary).duplicate(true)
	events = (parsed_events as Array).duplicate(true)
	choice_points = (parsed_choice_points as Array).duplicate(true)
	_rebuild_event_map()
	_rebuild_choice_point_map()
	return {"ok": true}

# 功能：执行一个回合（主循环单步）。
# 说明：先判 forced，再走调度；命中事件后执行效果/选择结算并推进状态。
func run_turn(selected_option_id: String = "") -> Dictionary:
	if events.is_empty():
		return {"ok": false, "error": "event pool is empty"}

	# 说明：若上回合停在选择点，本回合只允许等待或消费外部传入选项。
	if not _pending_choice_context.is_empty():
		return _resolve_pending_choice(selected_option_id)

	var expected_forced := str(world_state.get("forcedNextEventId", ""))
	var next_event_id := ""
	var route := "scheduler"

	if not expected_forced.is_empty():
		next_event_id = expected_forced
		route = "forced"
	else:
		var candidates := _build_candidates()
		if candidates.is_empty():
			next_event_id = _fallback_event_id()
			if next_event_id.is_empty():
				return {"ok": false, "error": "no eligible event and no fallback event"}
			route = "fallback"
		else:
			next_event_id = _weighted_pick(candidates)

	var event_def: Dictionary = _event_map.get(next_event_id, {})
	if event_def.is_empty():
		return {"ok": false, "error": "event not found: %s" % next_event_id}

	# 说明：forced 路由只消费一次，执行前清空，避免重复锁死。
	world_state["forcedNextEventId"] = ""

	var has_choice := false
	var choice_result := {
		"choice_point_id": "",
		"selected_option_id": "",
		"resolved_by": "",
		"options": []
	}
	var choice_point_id := str(event_def.get("choicePointId", "")).strip_edges()
	if not choice_point_id.is_empty():
		# 说明：事件声明 choicePointId 时，进入“构建选项 -> 选择 -> 结算”路径。
		has_choice = true
		var choice_point_def: Dictionary = _choice_point_map.get(choice_point_id, {})
		choice_result["choice_point_id"] = choice_point_id

		if choice_point_def.is_empty():
			# 说明：选择点数据缺失时，回退到事件默认 effects，保证主循环不中断。
			choice_result["resolved_by"] = "missing_choice_point_fallback_event_effects"
			_apply_event_effects(event_def)
			_apply_continuation_policy(event_def)
		else:
			var options_eval := _build_option_set(choice_point_def)
			choice_result["options"] = _option_public_states(options_eval)
			var selected := {}
			if selected_option_id.strip_edges().is_empty():
				selected = _select_first_selectable(options_eval)
				if selected.is_empty():
					# 说明：无可选项（全不可见/不可选）时，回退到事件默认效果。
					choice_result["resolved_by"] = "no_selectable_option_fallback_event_effects"
					_apply_event_effects(event_def)
					_apply_continuation_policy(event_def)
				else:
					# 说明：存在可选项但未传入外部选择时，进入等待态，不推进回合。
					_pending_choice_context = {
						"event_id": next_event_id,
						"route": route,
						"expected_forced": expected_forced
					}
					choice_result["resolved_by"] = "pending_external_selection"
					return {
						"ok": true,
						"awaiting_choice": true,
						"route": route,
						"event_id": next_event_id,
						"title": str(event_def.get("title", "")),
						"policy": str(event_def.get("continuationPolicy", POLICY_RETURN)),
						"expected_forced": expected_forced,
						"chain_active": not (world_state.get("chainContext", null) == null),
						"has_choice": true,
						"choice": choice_result
					}
			else:
				selected = _select_option_by_id(options_eval, selected_option_id)
				if selected.is_empty():
					return {
						"ok": false,
						"error": "selected option is not selectable: %s" % selected_option_id,
						"event_id": next_event_id,
						"choice_point_id": choice_point_id,
						"options": choice_result["options"]
					}
			if not selected.is_empty():
				choice_result["selected_option_id"] = str(selected.get("id", ""))
				choice_result["resolved_by"] = "option_resolution"
				_apply_option_resolution(selected, event_def)
	else:
		_apply_event_effects(event_def)
		_apply_continuation_policy(event_def)

	_record_history(next_event_id)
	world_state["turn"] = int(world_state.get("turn", 0)) + 1

	return {
		"ok": true,
		"route": route,
		"event_id": next_event_id,
		"title": str(event_def.get("title", "")),
		"policy": str(event_def.get("continuationPolicy", POLICY_RETURN)),
		"expected_forced": expected_forced,
		"chain_active": not (world_state.get("chainContext", null) == null),
		"has_choice": has_choice,
		"choice": choice_result
	}

# 功能：处理等待中的选择点。
# 说明：无选项输入时返回等待态；有输入时仅在可选时结算并推进回合。
func _resolve_pending_choice(selected_option_id: String) -> Dictionary:
	var event_id := str(_pending_choice_context.get("event_id", ""))
	var route := str(_pending_choice_context.get("route", "scheduler"))
	var expected_forced := str(_pending_choice_context.get("expected_forced", ""))
	var event_def: Dictionary = _event_map.get(event_id, {})
	if event_def.is_empty():
		_pending_choice_context.clear()
		return {"ok": false, "error": "pending event not found: %s" % event_id}

	var choice_point_id := str(event_def.get("choicePointId", "")).strip_edges()
	if choice_point_id.is_empty():
		_pending_choice_context.clear()
		return {"ok": false, "error": "pending event has no choice point: %s" % event_id}

	var choice_point_def: Dictionary = _choice_point_map.get(choice_point_id, {})
	if choice_point_def.is_empty():
		_pending_choice_context.clear()
		return {"ok": false, "error": "pending choice point not found: %s" % choice_point_id}

	var options_eval := _build_option_set(choice_point_def)
	var choice_result := {
		"choice_point_id": choice_point_id,
		"selected_option_id": "",
		"resolved_by": "",
		"options": _option_public_states(options_eval)
	}

	if selected_option_id.strip_edges().is_empty():
		choice_result["resolved_by"] = "pending_external_selection"
		return {
			"ok": true,
			"awaiting_choice": true,
			"route": route,
			"event_id": event_id,
			"title": str(event_def.get("title", "")),
			"policy": str(event_def.get("continuationPolicy", POLICY_RETURN)),
			"expected_forced": expected_forced,
			"chain_active": not (world_state.get("chainContext", null) == null),
			"has_choice": true,
			"choice": choice_result
		}

	var selected := _select_option_by_id(options_eval, selected_option_id)
	if selected.is_empty():
		return {
			"ok": false,
			"error": "selected option is not selectable: %s" % selected_option_id,
			"event_id": event_id,
			"choice_point_id": choice_point_id,
			"options": choice_result["options"]
		}

	choice_result["selected_option_id"] = str(selected.get("id", ""))
	choice_result["resolved_by"] = "option_resolution"
	_apply_option_resolution(selected, event_def)
	_record_history(event_id)
	world_state["turn"] = int(world_state.get("turn", 0)) + 1
	_pending_choice_context.clear()

	return {
		"ok": true,
		"awaiting_choice": false,
		"route": route,
		"event_id": event_id,
		"title": str(event_def.get("title", "")),
		"policy": str(event_def.get("continuationPolicy", POLICY_RETURN)),
		"expected_forced": expected_forced,
		"chain_active": not (world_state.get("chainContext", null) == null),
		"has_choice": true,
		"choice": choice_result
	}

# 功能：重建事件索引。
# 说明：将 events 数组映射为 {event_id: event_def}，用于 O(1) 查找。
func _rebuild_event_map() -> void:
	_event_map.clear()
	for event_variant in events:
		var event_def: Dictionary = event_variant
		var event_id := str(event_def.get("id", ""))
		if event_id.is_empty():
			continue
		_event_map[event_id] = event_def

# 功能：重建选择点索引。
# 说明：将 choice_points 映射为 {choice_point_id: choice_point_def}。
func _rebuild_choice_point_map() -> void:
	_choice_point_map.clear()
	for choice_variant in choice_points:
		var choice_def: Dictionary = choice_variant
		var choice_id := str(choice_def.get("id", "")).strip_edges()
		if choice_id.is_empty():
			continue
		_choice_point_map[choice_id] = choice_def

# 功能：生成候选事件集。
# 说明：仅做可用性与权重计算，不做最终抽签。
func _build_candidates() -> Array:
	var out: Array = []
	for event_variant in events:
		var event_def: Dictionary = event_variant
		if _is_event_eligible(event_def):
			var weight := _compute_weight(event_def)
			out.append({"id": str(event_def.get("id", "")), "weight": weight})
	return out

# 功能：执行事件硬约束过滤。
# 说明：地点、地点状态、NPC 在场、链 allowedTags 任一不满足即排除。
func _is_event_eligible(event_def: Dictionary) -> bool:
	var eligibility: Dictionary = event_def.get("eligibility", {})
	var current_location := str(world_state.get("currentLocationId", ""))

	# 说明：地点硬过滤。
	var required_locations: Array = eligibility.get("requiredLocations", [])
	if not required_locations.is_empty() and not (current_location in required_locations):
		return false

	# 说明：地点状态硬过滤。
	var location_state_all: Dictionary = world_state.get("locationState", {})
	var current_location_state: Dictionary = location_state_all.get(current_location, {})
	var required_location_flags: Array = eligibility.get("requiredLocationFlags", [])
	for clause_variant in required_location_flags:
		var clause: Dictionary = clause_variant
		var key := str(clause.get("key", ""))
		var op := str(clause.get("op", "=="))
		var expected: Variant = clause.get("value", 0)
		var actual: Variant = current_location_state.get(key, null)
		if not _compare_values(actual, op, expected):
			return false

	# 说明：NPC 在场硬过滤。
	var required_npcs: Array = eligibility.get("requiredNPCsPresent", [])
	if not required_npcs.is_empty():
		var npc_presence_all: Dictionary = world_state.get("npcPresence", {})
		var present_list: Array = npc_presence_all.get(current_location, [])
		for npc_id_variant in required_npcs:
			var npc_id := str(npc_id_variant)
			if not (npc_id in present_list):
				return false

	# 说明：链上下文额外过滤。
	var chain_context: Variant = world_state.get("chainContext", null)
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		var chain_dict: Dictionary = chain_context
		var allowed_tags: Array = chain_dict.get("allowedTags", [])
		if not allowed_tags.is_empty():
			var event_tags: Array = event_def.get("tags", [])
			if not _array_has_any(event_tags, allowed_tags):
				return false

	return true

# 功能：计算单个事件当前权重。
# 说明：综合 baseWeight、weightRules、历史惩罚与链式 tag 偏置。
func _compute_weight(event_def: Dictionary) -> int:
	var weight := int(event_def.get("baseWeight", 10))

	var rules: Array = event_def.get("weightRules", [])
	for rule_variant in rules:
		var rule: Dictionary = rule_variant
		var condition := str(rule.get("when", "")).strip_edges()
		if condition.is_empty():
			continue
		if _evaluate_condition(condition):
			weight += int(rule.get("delta", 0))

	# 说明：历史去重偏置，近期出现过的事件轻微降权。
	var history: Array = world_state.get("history", [])
	if str(event_def.get("id", "")) in history:
		weight -= 3

	# 说明：链上下文偏置，通过 tag 映射提高链内事件权重。
	var chain_context: Variant = world_state.get("chainContext", null)
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		var chain_dict: Dictionary = chain_context
		var tag_bias: Dictionary = chain_dict.get("weightBias", {})
		var event_tags: Array = event_def.get("tags", [])
		for tag_variant in event_tags:
			var tag := str(tag_variant)
			if tag_bias.has(tag):
				weight += int(tag_bias[tag])

	if weight < 1:
		return 1
	return weight

# 功能：解析并执行简单条件表达式。
# 说明：格式为 "<path> <op> <literal>"，支持 >= <= == != > <。
func _evaluate_condition(condition: String) -> bool:
	var operators := [">=", "<=", "==", "!=", ">", "<"]
	for op_variant in operators:
		var op := str(op_variant)
		var token := " %s " % op
		if condition.find(token) == -1:
			continue
		var parts := condition.split(token)
		if parts.size() != 2:
			return false
		var left_text := str(parts[0]).strip_edges()
		var right_text := str(parts[1]).strip_edges()
		var actual: Variant = _resolve_path_value(left_text)
		var expected: Variant = _parse_literal(right_text)
		return _compare_values(actual, op, expected)
	return false

# 功能：按点路径读取 world_state 值（如 flags.isWanted）。
# 说明：任意层不存在时返回 null。
func _resolve_path_value(path: String) -> Variant:
	var segments := path.split(".", false)
	if segments.is_empty():
		return null

	var cursor: Variant = world_state
	for segment_variant in segments:
		var segment := str(segment_variant)
		if typeof(cursor) != TYPE_DICTIONARY:
			return null
		var dict_cursor: Dictionary = cursor
		if not dict_cursor.has(segment):
			return null
		cursor = dict_cursor[segment]
	return cursor

# 功能：将表达式右值文本解析为 GDScript 值。
# 说明：支持 bool/int/双引号字符串，其他保持原文本。
func _parse_literal(raw: String) -> Variant:
	var text := raw.strip_edges()
	var lowered := text.to_lower()
	if lowered == "true":
		return true
	if lowered == "false":
		return false
	if text.is_valid_int():
		return int(text)
	if text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2:
		return text.substr(1, text.length() - 2)
	return text

# 功能：统一比较函数。
# 说明：大小比较会转为 float，再执行比较。
func _compare_values(actual: Variant, op: String, expected: Variant) -> bool:
	if actual == null:
		return false
	match op:
		"==":
			return actual == expected
		"!=":
			return actual != expected
		">":
			return float(actual) > float(expected)
		">=":
			return float(actual) >= float(expected)
		"<":
			return float(actual) < float(expected)
		"<=":
			return float(actual) <= float(expected)
		_:
			return false

# 功能：按权重随机抽取事件 id。
# 说明：当总权重异常（<=0）时回退第一个候选，保证不中断。
func _weighted_pick(candidates: Array) -> String:
	var total := 0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		total += maxi(1, int(candidate.get("weight", 1)))

	if total <= 0:
		return str((candidates[0] as Dictionary).get("id", ""))

	var roll := _rng.randi_range(1, total)
	var cursor := 0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		cursor += maxi(1, int(candidate.get("weight", 1)))
		if roll <= cursor:
			return str(candidate.get("id", ""))

	return str((candidates[0] as Dictionary).get("id", ""))

# 功能：兜底事件选择。
# 说明：优先 evt_idle，其次取事件池中第一个可用 id。
func _fallback_event_id() -> String:
	if _event_map.has("evt_idle"):
		return "evt_idle"
	for event_variant in events:
		var event_def: Dictionary = event_variant
		var event_id := str(event_def.get("id", ""))
		if not event_id.is_empty():
			return event_id
	return ""

# 功能：将事件 effects 应用到 world_state。
# 说明：支持 setFlags/addParams/setLocation/forcedNext/clearForced/endChain。
func _apply_event_effects(event_def: Dictionary) -> void:
	var effects: Dictionary = event_def.get("effects", {})

	var set_flags: Dictionary = effects.get("setFlags", {})
	if not set_flags.is_empty():
		var flags: Dictionary = world_state.get("flags", {})
		for key in set_flags.keys():
			flags[str(key)] = set_flags[key]
		world_state["flags"] = flags

	var add_params: Dictionary = effects.get("addParams", {})
	if not add_params.is_empty():
		var params: Dictionary = world_state.get("params", {})
		for key in add_params.keys():
			var param_key := str(key)
			params[param_key] = int(params.get(param_key, 0)) + int(add_params[key])
		world_state["params"] = params

	var set_location := str(effects.get("setLocation", "")).strip_edges()
	if not set_location.is_empty():
		world_state["currentLocationId"] = set_location

	var forced_id := str(effects.get("forcedNextEventId", "")).strip_edges()
	if not forced_id.is_empty():
		world_state["forcedNextEventId"] = forced_id

	if bool(effects.get("clearForcedNext", false)):
		world_state["forcedNextEventId"] = ""

	if bool(effects.get("endChain", false)):
		world_state["chainContext"] = null

# 功能：按 continuationPolicy 推进链上下文。
# 说明：forcedNextEventId 由 effects/resolution 驱动，不在此处判定。
func _apply_continuation_policy(event_def: Dictionary, chain_patch_override: Dictionary = {}) -> void:
	var policy := str(event_def.get("continuationPolicy", POLICY_RETURN))
	var base_chain_patch: Dictionary = event_def.get("chainPatch", {})
	var merged_chain_patch := _merge_dict(base_chain_patch, chain_patch_override)
	match policy:
		POLICY_CHAIN, POLICY_CHAIN_FORCED:
			_ensure_or_patch_chain_context(merged_chain_patch)
		POLICY_RETURN:
			# 说明：Return 不主动建链；若显式给出 patch，则按 patch 执行。
			if not merged_chain_patch.is_empty():
				_ensure_or_patch_chain_context(merged_chain_patch)
		_:
			pass

# 功能：创建或更新 chainContext。
# 说明：首次按 patch 初始化，链内按 stageDelta 推进，并可按退出条件自动结束。
func _ensure_or_patch_chain_context(chain_patch: Dictionary) -> void:
	var raw_ctx: Variant = world_state.get("chainContext", null)
	var ctx: Dictionary = {}
	if typeof(raw_ctx) == TYPE_DICTIONARY and raw_ctx != null:
		ctx = (raw_ctx as Dictionary).duplicate(true)

	if ctx.is_empty():
		ctx = {
			"chainId": str(chain_patch.get("chainId", "chain_default")),
			"stage": int(chain_patch.get("stage", 1)),
			"allowedTags": chain_patch.get("allowedTags", []),
			"constraints": chain_patch.get("constraints", {}),
			"weightBias": chain_patch.get("weightBias", {}),
			"exitWhenStageGte": int(chain_patch.get("exitWhenStageGte", 0))
		}
	else:
		ctx["stage"] = int(ctx.get("stage", 0)) + int(chain_patch.get("stageDelta", 1))
		if chain_patch.has("allowedTags"):
			ctx["allowedTags"] = chain_patch.get("allowedTags", [])
		if chain_patch.has("constraints"):
			ctx["constraints"] = chain_patch.get("constraints", {})
		if chain_patch.has("weightBias"):
			ctx["weightBias"] = chain_patch.get("weightBias", {})
		if chain_patch.has("exitWhenStageGte"):
			ctx["exitWhenStageGte"] = int(chain_patch.get("exitWhenStageGte", 0))

	var exit_stage := int(ctx.get("exitWhenStageGte", 0))
	if exit_stage > 0 and int(ctx.get("stage", 0)) >= exit_stage:
		world_state["chainContext"] = null
	else:
		world_state["chainContext"] = ctx

# 功能：记录最近事件历史。
# 说明：固定窗口 12 条，供权重去重使用。
func _record_history(event_id: String) -> void:
	var history: Array = world_state.get("history", [])
	history.append(event_id)
	while history.size() > 12:
		history.pop_front()
	world_state["history"] = history

# 功能：判断两个数组是否存在任意交集。
# 说明：用于 tag 匹配。
func _array_has_any(left: Array, right: Array) -> bool:
	for left_item in left:
		if left_item in right:
			return true
	return false

# 功能：构建事件对应的选项集合。
# 说明：为每个选项标记三态（invisible/disabled/selectable）。
func _build_option_set(choice_point_def: Dictionary) -> Array:
	var out: Array = []
	var options: Array = choice_point_def.get("options", [])
	for option_variant in options:
		var option_def: Dictionary = option_variant
		var item := option_def.duplicate(true)
		# 说明：选项三态为 invisible（不显示）/disabled（显示不可选）/selectable（可选）。
		var state := "selectable"
		if not _option_visible(option_def):
			state = "invisible"
		elif not _option_selectable(option_def):
			state = "disabled"
		item["state"] = state
		out.append(item)
	return out

# 功能：输出上层使用的选项简版结构。
# 说明：仅返回 id/text/state，避免暴露内部结算细节。
func _option_public_states(options_eval: Array) -> Array:
	var out: Array = []
	for option_variant in options_eval:
		var option_def: Dictionary = option_variant
		out.append(
			{
				"id": str(option_def.get("id", "")),
				"text": str(option_def.get("text", "")),
				"state": str(option_def.get("state", "disabled"))
			}
		)
	return out

# 功能：判定选项是否可见。
# 说明：visibilityWhen 条件需全部通过才可见。
func _option_visible(option_def: Dictionary) -> bool:
	var visibility_rules := _array_or_empty(option_def.get("visibilityWhen", []))
	for rule_variant in visibility_rules:
		var rule := str(rule_variant).strip_edges()
		if rule.is_empty():
			continue
		if not _evaluate_condition(rule):
			return false
	return true

# 功能：判定选项是否可选。
# 说明：需同时通过 eligibility 与 cost 校验。
func _option_selectable(option_def: Dictionary) -> bool:
	if not _is_option_eligibility_pass(_dict_or_empty(option_def.get("eligibility", {}))):
		return false
	return _can_pay_cost(_dict_or_empty(option_def.get("cost", {})))

# 功能：逐条校验 eligibility 条件。
# 说明：支持字面量比较与内联规则字符串（如 >=10）。
func _is_option_eligibility_pass(eligibility: Dictionary) -> bool:
	for key_variant in eligibility.keys():
		var path := str(key_variant).strip_edges()
		var clause: Variant = eligibility[key_variant]
		var actual: Variant = _resolve_path_value(path)
		if typeof(clause) == TYPE_STRING:
			# 说明：规则示例 >=10、==true；左值来自 path 对应的 world_state 字段。
			var rule := str(clause).strip_edges()
			if rule.is_empty():
				continue
			if not _match_inline_rule(actual, rule):
				return false
		else:
			if actual != clause:
				return false
	return true

# 功能：解析并匹配内联规则。
# 说明：规则示例 >=10、==true，左值为 actual。
func _match_inline_rule(actual: Variant, rule: String) -> bool:
	var operators := [">=", "<=", "==", "!=", ">", "<"]
	for op_variant in operators:
		var op := str(op_variant)
		if not rule.begins_with(op):
			continue
		var right_text := rule.substr(op.length()).strip_edges()
		var expected: Variant = _parse_literal(right_text)
		return _compare_values(actual, op, expected)
	var expected_literal: Variant = _parse_literal(rule)
	return actual == expected_literal

# 功能：检查玩家是否可支付选项代价。
# 说明：从 world_state.player 读取资源并比较。
func _can_pay_cost(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	var player: Dictionary = world_state.get("player", {})
	for key_variant in cost.keys():
		var key := str(key_variant)
		var need := int(cost[key_variant])
		var have := int(player.get(key, 0))
		if have < need:
			return false
	return true

# 功能：将选项代价扣减到 world_state.player。
# 说明：按 cost 字段逐项扣减。
func _apply_cost(cost: Dictionary) -> void:
	if cost.is_empty():
		return
	var player: Dictionary = world_state.get("player", {})
	for key_variant in cost.keys():
		var key := str(key_variant)
		player[key] = int(player.get(key, 0)) - int(cost[key_variant])
	world_state["player"] = player

# 功能：在可选项中按外部传入 ID 精确选择。
# 说明：仅当目标选项状态为 selectable 时返回，否则返回空字典。
func _select_option_by_id(options_eval: Array, option_id: String) -> Dictionary:
	var target := option_id.strip_edges()
	if target.is_empty():
		return {}
	for option_variant in options_eval:
		var option_def: Dictionary = option_variant
		if str(option_def.get("id", "")) == target and str(option_def.get("state", "")) == "selectable":
			return option_def
	return {}

# 功能：在可选项中查找第一个 selectable 选项。
# 说明：仅用于判断“是否存在可选项”，不用于自动结算。
func _select_first_selectable(options_eval: Array) -> Dictionary:
	for option_variant in options_eval:
		var option_def: Dictionary = option_variant
		if str(option_def.get("state", "")) == "selectable":
			return option_def
	return {}

# 功能：执行选项结算主流程。
# 说明：流程为扣代价 -> 检定 -> 应用 resolution。
func _apply_option_resolution(selected_option: Dictionary, event_def: Dictionary) -> void:
	var cost := _dict_or_empty(selected_option.get("cost", {}))
	if not _can_pay_cost(cost):
		# 说明：正常不应进入该分支，保留防御兜底。
		_apply_event_effects(event_def)
		_apply_continuation_policy(event_def)
		return

	_apply_cost(cost)

	var resolution := _dict_or_empty(selected_option.get("resolution", {}))
	var check := _dict_or_empty(selected_option.get("check", {}))
	if not _is_check_pass(check):
		# 说明：检定失败时可用 onFailResolution 覆盖默认 resolution。
		var fail_resolution := _dict_or_empty(check.get("onFailResolution", {}))
		if not fail_resolution.is_empty():
			resolution = fail_resolution

	_apply_resolution(resolution, event_def)

# 功能：执行选项检定。
# 说明：当前仅支持 chance；无 check 或未知类型默认通过。
func _is_check_pass(check: Dictionary) -> bool:
	if check.is_empty():
		return true
	var check_type := str(check.get("type", "")).strip_edges()
	if check_type == "chance":
		var rate := clampf(float(check.get("successRate", 1.0)), 0.0, 1.0)
		return _rng.randf() <= rate
	return true

# 功能：应用 resolution 并衔接执行锁更新。
# 说明：统一处理 worldStatePatch、forcedNextEventId、chainContextPatch。
func _apply_resolution(resolution: Dictionary, event_def: Dictionary) -> void:
	# 说明：resolution 统一处理三类后果：worldStatePatch、forcedNextEventId、chainContextPatch。
	var world_patch := _dict_or_empty(resolution.get("worldStatePatch", {}))
	_apply_world_state_patch(world_patch)

	if resolution.has("forcedNextEventId"):
		var forced_id := str(resolution.get("forcedNextEventId", "")).strip_edges()
		world_state["forcedNextEventId"] = forced_id

	var chain_patch := _dict_or_empty(resolution.get("chainContextPatch", {}))
	_apply_continuation_policy(event_def, chain_patch)

# 功能：应用 worldStatePatch 到 world_state。
# 说明：params/player 为增量写入，flags 为覆盖写入。
func _apply_world_state_patch(patch: Dictionary) -> void:
	if patch.is_empty():
		return

	var flags_patch: Dictionary = patch.get("flags", {})
	if not flags_patch.is_empty():
		var flags: Dictionary = world_state.get("flags", {})
		for key in flags_patch.keys():
			flags[str(key)] = flags_patch[key]
		world_state["flags"] = flags

	var params_patch: Dictionary = patch.get("params", {})
	if not params_patch.is_empty():
		var params: Dictionary = world_state.get("params", {})
		for key in params_patch.keys():
			var param_key := str(key)
			params[param_key] = int(params.get(param_key, 0)) + int(params_patch[key])
		world_state["params"] = params

	var player_patch: Dictionary = patch.get("player", {})
	if not player_patch.is_empty():
		var player: Dictionary = world_state.get("player", {})
		for key in player_patch.keys():
			var player_key := str(key)
			player[player_key] = int(player.get(player_key, 0)) + int(player_patch[key])
		world_state["player"] = player

	var set_location := str(patch.get("currentLocationId", "")).strip_edges()
	if not set_location.is_empty():
		world_state["currentLocationId"] = set_location

# 功能：合并两个字典。
# 说明：right 覆盖 left 同名键，返回新字典。
func _merge_dict(left: Dictionary, right: Dictionary) -> Dictionary:
	var merged := left.duplicate(true)
	for key in right.keys():
		merged[key] = right[key]
	return merged

func _dict_or_empty(value: Variant) -> Dictionary:
	# 说明：JSON 允许 null；统一收敛为 {}，避免 Nil -> Dictionary 赋值错误。
	if typeof(value) == TYPE_DICTIONARY and value != null:
		return value
	return {}

func _array_or_empty(value: Variant) -> Array:
	# 说明：与 _dict_or_empty 同理，用于兼容 visibilityWhen 等可选数组字段。
	if typeof(value) == TYPE_ARRAY and value != null:
		return value
	return []
