extends RefCounted
class_name WorldEventEngine

# 世界与事件引擎（MVP）
# 说明：
# 1) 使用单一主循环推进。
# 2) ForcedNextEventId 具有最高优先级。
# 3) 连锁通过 ChainContext 塑形调度分布，而不是强制指定下一事件。

const POLICY_RETURN := "ReturnToScheduler"
const POLICY_CHAIN := "ChainContinue"
const POLICY_CHAIN_FORCED := "ChainContinueWithForcedNext"

var world_state: Dictionary = {}
var events: Array = []
var _event_map: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# 初始化随机源：
# - random_seed=0 时使用随机种子（每次运行结果不同）
# - 指定种子时可复现调度结果，便于测试与回归
func _init(random_seed: int = 0) -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

# 从 JSON 文件加载世界状态与事件池。
# 返回统一结构：{"ok": bool, "error": String?}
func load_from_files(world_state_path: String, events_path: String) -> Dictionary:
	var world_text := FileAccess.get_file_as_string(world_state_path)
	if world_text.is_empty():
		return {"ok": false, "error": "world state file is empty or missing: %s" % world_state_path}

	var events_text := FileAccess.get_file_as_string(events_path)
	if events_text.is_empty():
		return {"ok": false, "error": "events file is empty or missing: %s" % events_path}

	return load_from_json_text(world_text, events_text)

# 从 JSON 文本加载数据，适合测试或热重载。
# 成功后会重建 event_id 索引，加速后续查找。
func load_from_json_text(world_state_json: String, events_json: String) -> Dictionary:
	var parsed_world: Variant = JSON.parse_string(world_state_json)
	if typeof(parsed_world) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid world state json"}

	var parsed_events: Variant = JSON.parse_string(events_json)
	if typeof(parsed_events) != TYPE_ARRAY:
		return {"ok": false, "error": "invalid events json"}

	world_state = (parsed_world as Dictionary).duplicate(true)
	events = (parsed_events as Array).duplicate(true)
	_rebuild_event_map()
	return {"ok": true}

# 执行一个回合（主循环单步）：
# 1) 先看 forcedNextEventId（最高优先级）
# 2) 否则走过滤 + 权重 + 抽取
# 3) 执行事件效果并推进链上下文
func run_turn() -> Dictionary:
	if events.is_empty():
		return {"ok": false, "error": "event pool is empty"}

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

	# Forced 路由只消费一次，执行前清空，避免重复锁死。
	world_state["forcedNextEventId"] = ""

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
		"chain_active": not (world_state.get("chainContext", null) == null)
	}

# 将 events 数组重建为 {event_id: event_def} 索引。
# 用于 run_turn 中 O(1) 获取事件定义。
func _rebuild_event_map() -> void:
	_event_map.clear()
	for event_variant in events:
		var event_def: Dictionary = event_variant
		var event_id := str(event_def.get("id", ""))
		if event_id.is_empty():
			continue
		_event_map[event_id] = event_def

# 生成候选事件集（只做可用性与权重计算，不做最终抽签）。
func _build_candidates() -> Array:
	var out: Array = []
	for event_variant in events:
		var event_def: Dictionary = event_variant
		if _is_event_eligible(event_def):
			var weight := _compute_weight(event_def)
			out.append({"id": str(event_def.get("id", "")), "weight": weight})
	return out

# 硬约束过滤：
# - 地点要求
# - 地点状态阈值
# - NPC 在场
# - 链上下文 allowedTags
# 任何一项不满足都直接排除。
func _is_event_eligible(event_def: Dictionary) -> bool:
	var eligibility: Dictionary = event_def.get("eligibility", {})
	var current_location := str(world_state.get("currentLocationId", ""))

	# 1) 地点硬过滤
	var required_locations: Array = eligibility.get("requiredLocations", [])
	if not required_locations.is_empty() and not (current_location in required_locations):
		return false

	# 2) 地点状态硬过滤
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

	# 3) NPC 在场硬过滤
	var required_npcs: Array = eligibility.get("requiredNPCsPresent", [])
	if not required_npcs.is_empty():
		var npc_presence_all: Dictionary = world_state.get("npcPresence", {})
		var present_list: Array = npc_presence_all.get(current_location, [])
		for npc_id_variant in required_npcs:
			var npc_id := str(npc_id_variant)
			if not (npc_id in present_list):
				return false

	# 4) 链上下文额外过滤
	var chain_context: Variant = world_state.get("chainContext", null)
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		var chain_dict: Dictionary = chain_context
		var allowed_tags: Array = chain_dict.get("allowedTags", [])
		if not allowed_tags.is_empty():
			var event_tags: Array = event_def.get("tags", [])
			if not _array_has_any(event_tags, allowed_tags):
				return false

	return true

# 计算单个事件当前权重。
# 权重来源：
# - baseWeight
# - weightRules 条件增减
# - 历史去重惩罚
# - 链上下文 tag 偏置
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

	# 历史去重偏置：近期出现过的事件轻微降权，减少重复感。
	var history: Array = world_state.get("history", [])
	if str(event_def.get("id", "")) in history:
		weight -= 3

	# 链上下文偏置：通过 tag 映射提高链内事件权重。
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

# 解析并执行简单条件表达式：
# 格式约定："<path> <op> <literal>"，例如 "params.danger >= 20"
# 当前支持 op: >= <= == != > <
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

# 通过点路径读取 world_state 值，例如 "flags.isWanted"。
# 任意层不存在时返回 null。
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

# 将表达式右值文本转为 GDScript 值：
# - true/false -> bool
# - 整数字符串 -> int
# - "xxx" -> String
# - 其他保持原文本
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

# 比较函数，统一处理表达式中的双值比较。
# 对大小比较会转成 float 后再比较。
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

# 加权随机抽取事件 id。
# 当总权重异常（<=0）时回退到第一个候选，保证流程不中断。
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

# 兜底事件选择策略：
# 优先 evt_idle，其次取事件池中第一个可用 id。
func _fallback_event_id() -> String:
	if _event_map.has("evt_idle"):
		return "evt_idle"
	for event_variant in events:
		var event_def: Dictionary = event_variant
		var event_id := str(event_def.get("id", ""))
		if not event_id.is_empty():
			return event_id
	return ""

# 应用事件效果到 world_state。
# 约定支持：
# - setFlags / addParams
# - setLocation
# - forcedNextEventId / clearForcedNext
# - endChain
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

# 根据 continuationPolicy 决定是否推进链上下文。
# 注意：forcedNextEventId 由 effects 字段驱动，不在这里判断。
func _apply_continuation_policy(event_def: Dictionary) -> void:
	var policy := str(event_def.get("continuationPolicy", POLICY_RETURN))
	match policy:
		POLICY_CHAIN, POLICY_CHAIN_FORCED:
			var chain_patch: Dictionary = event_def.get("chainPatch", {})
			_ensure_or_patch_chain_context(chain_patch)
		POLICY_RETURN:
			# Return 策略不主动创建链；是否退出链由 effects.endChain 决定。
			pass
		_:
			pass

# 创建或更新 chainContext：
# - 首次进入链：使用 chainPatch 初始化
# - 链内推进：按 stageDelta 增长并可局部覆盖约束与偏置
# - 达到 exitWhenStageGte 时自动退出链
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

# 记录最近事件历史（固定窗口 12 条），供去重权重使用。
func _record_history(event_id: String) -> void:
	var history: Array = world_state.get("history", [])
	history.append(event_id)
	while history.size() > 12:
		history.pop_front()
	world_state["history"] = history

# 判断两个数组是否存在任意交集（用于 tag 匹配）。
func _array_has_any(left: Array, right: Array) -> bool:
	for left_item in left:
		if left_item in right:
			return true
	return false
