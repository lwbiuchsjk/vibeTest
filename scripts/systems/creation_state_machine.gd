extends RefCounted

# 开局选择状态机：管理角色创建的逐题交互流程。
# 作为独立类由 WorldEventEngine 持有和驱动，与 UI 层无关。
# 对外暴露状态、当前问题、可用操作列表，供 UI 层消费。

# ── 状态枚举 ──────────────────────────────────────────────────────
enum State {
	IDLE,          # 未激活
	PRESENTING,    # 正在展示一个问题，等待玩家选择
	SETTLED,       # 全部问题完成
}

# ── 内部状态 ──────────────────────────────────────────────────────
var _state: int = State.IDLE
# 对 WorldEventEngine 的引用，用于访问游戏状态和 apply effect。
var _engine: RefCounted = null
# 全部问题配置（从 ConfigLoader 解析后传入）。
var _questions: Array = []
# 当前展示的问题在 _questions 中的索引。
var _current_index: int = 0
# 满足条件的有效问题索引列表（用于进度计算，每次 act 后重新扫描）。
var _valid_indices: Array = []
# 已回答的问题数量（用于进度计算）。
var _answered_count: int = 0


# ── 对外接口 ──────────────────────────────────────────────────────

# 功能：启动开局选择状态机。
# 说明：加载配置，定位第一个满足条件的问题。无有效问题时直接进入 SETTLED。
func start(engine: RefCounted, config: Array) -> Dictionary:
	_engine = engine
	_questions = config
	_current_index = 0
	_answered_count = 0
	_valid_indices = []

	if _questions.is_empty():
		_state = State.SETTLED
		print("[开局选择] 无配置，直接 SETTLED")
		return _build_response()

	# 预扫描所有满足条件的问题索引，用于进度显示。
	_valid_indices = _scan_valid_indices()
	if _valid_indices.is_empty():
		_state = State.SETTLED
		print("[开局选择] 无满足条件的问题，直接 SETTLED")
		return _build_response()

	_current_index = int(_valid_indices[0])
	_state = State.PRESENTING
	print("[开局选择] 开始，第一题: %s" % _get_current_question_id())
	return _build_response()


# 功能：查询当前状态。
func get_state() -> String:
	return State.keys()[_state]


# 功能：查询状态机是否处于活跃状态（非 IDLE / SETTLED）。
func is_active() -> bool:
	return _state != State.IDLE and _state != State.SETTLED


# 功能：获取当前问题的可用选项列表。
# 说明：格式与 ReflectionStateMachine 对齐：{action, label, enabled}。
func get_available_actions() -> Array:
	if _state != State.PRESENTING:
		return []
	var question: Dictionary = _questions[_current_index]
	var options: Array = question.get("options", [])
	var actions: Array = []
	for opt_variant in options:
		var opt: Dictionary = opt_variant
		actions.append({
			"action": str(opt.get("option_id", "")),
			"label": str(opt.get("option_text", "")),
			"enabled": true,
		})
	return actions


# 功能：玩家选择一个选项，立即 apply effect，推进到下一题或 SETTLED。
func act(option_id: String) -> Dictionary:
	if _state != State.PRESENTING:
		return {"ok": false, "error": "not_presenting", "state": get_state()}

	var question: Dictionary = _questions[_current_index]
	var selected_option: Dictionary = _find_option(question, option_id)
	if selected_option.is_empty():
		return {"ok": false, "error": "invalid_option", "state": get_state(), "option_id": option_id}

	# 立即 apply 该选项的所有 effect。
	var effects: Array = selected_option.get("effects", [])
	for effect_variant in effects:
		var effect: Dictionary = effect_variant
		_apply_effect(effect)

	# apply 完成后同步 world_state.player。
	if _engine != null and _engine.player_role_state != null:
		_engine._sync_role_to_world_state()

	print("[开局选择] 选择 %s (问题 %s)，已 apply %d 条 effect" % [
		option_id, str(question.get("question_id", "")), effects.size()
	])

	# effect 可能改变后续问题的条件判定结果，重新扫描有效问题列表。
	_valid_indices = _scan_valid_indices_from(_current_index + 1)
	# 推进到下一个满足条件的问题。
	var next_valid := _find_next_valid_index(_current_index + 1)
	if next_valid < 0:
		_state = State.SETTLED
		print("[开局选择] 全部问题完成，SETTLED")
		return _build_response({"selected_option": option_id, "settled": true})

	_current_index = next_valid
	_answered_count += 1
	print("[开局选择] 下一题: %s" % _get_current_question_id())
	return _build_response({"selected_option": option_id})


# ── Effect Apply ─────────────────────────────────────────────────

# 功能：根据 effect_target 分发并执行单条 effect。
# 说明：MVP 阶段实现 attribute/resource/affinity/affinity_all/focus，
#       其余类型预留分支但仅打印警告。
func _apply_effect(effect: Dictionary) -> void:
	var target := str(effect.get("target", ""))
	var key := str(effect.get("key", ""))
	var raw_value := str(effect.get("value", ""))

	match target:
		"attribute":
			_apply_attribute_delta(key, raw_value)
		"resource":
			_apply_resource_delta(key, raw_value)
		"affinity":
			_apply_affinity_delta(key, raw_value)
		"affinity_all":
			_apply_affinity_all_delta(raw_value)
		"focus":
			_apply_focus(key)
		"flag":
			_apply_flag(key, raw_value)
		"param":
			_apply_param_delta(key, raw_value)
		"location":
			_apply_location(raw_value)
		"npc_presence":
			_apply_npc_presence(key, raw_value)
		_:
			print("[开局选择] 未知 effect_target: %s" % target)


# 功能：属性 delta 累加。
func _apply_attribute_delta(key: String, raw_value: String) -> void:
	if _engine == null or _engine.player_role_state == null:
		return
	var delta := _parse_delta(raw_value)
	var old_val: int = _engine.player_role_state.get_attribute(key, 1)
	_engine.player_role_state.set_attribute(key, old_val + delta)
	print("[开局选择] attribute %s: %d → %d" % [key, old_val, old_val + delta])


# 功能：资源 delta 累加。
func _apply_resource_delta(key: String, raw_value: String) -> void:
	if _engine == null or _engine.player_role_state == null:
		return
	var delta := _parse_delta(raw_value)
	var old_val: int = _engine.player_role_state.get_resource(key)
	_engine.player_role_state.set_resource(key, old_val + delta)
	print("[开局选择] resource %s: %d → %d" % [key, old_val, old_val + delta])


# 功能：单条亲和关系 delta 累加。
# 说明：key 格式为 "from->to"。
func _apply_affinity_delta(key: String, raw_value: String) -> void:
	if _engine == null or _engine._affinity_map == null:
		return
	var parts := key.split("->")
	if parts.size() != 2:
		print("[开局选择] affinity key 格式错误: %s" % key)
		return
	var from_id := str(parts[0]).strip_edges()
	var to_id := str(parts[1]).strip_edges()
	var delta := _parse_delta(raw_value)
	var old_val: int = _engine._affinity_map.get_score(from_id, to_id)
	_engine._affinity_map.set_score(from_id, to_id, old_val + delta)
	print("[开局选择] affinity %s->%s: %d → %d" % [from_id, to_id, old_val, old_val + delta])


# 功能：对所有 NPC 批量设置亲和关系 delta。
# 说明：遍历引擎中 ConfigRuntime 的 roles，对 role_type=="npc" 的条目批量操作。
func _apply_affinity_all_delta(raw_value: String) -> void:
	if _engine == null or _engine._affinity_map == null or _engine.player_role_state == null:
		return
	var delta := _parse_delta(raw_value)
	var player_id: String = _engine.player_role_state.role_id
	# 从 ConfigRuntime 获取所有角色，筛选 NPC。
	var runtime: RefCounted = _engine.ConfigRuntime.shared()
	var roles: Array = runtime.get_roles()
	for role_variant in roles:
		if role_variant == null:
			continue
		if str(role_variant.role_type) != "npc":
			continue
		var npc_id: String = str(role_variant.role_id)
		var old_val: int = _engine._affinity_map.get_score(player_id, npc_id)
		_engine._affinity_map.set_score(player_id, npc_id, old_val + delta)
		print("[开局选择] affinity_all %s->%s: %d → %d" % [player_id, npc_id, old_val, old_val + delta])


# 功能：添加 NPC 到关注列表。
func _apply_focus(key: String) -> void:
	if _engine == null or _engine.player_role_state == null:
		return
	_engine.player_role_state.add_focus(key)
	print("[开局选择] focus add: %s" % key)


# 功能：设置 world_state flag（预留，MVP 阶段可用但暂无配置使用）。
func _apply_flag(key: String, raw_value: String) -> void:
	if _engine == null:
		return
	var flags: Dictionary = _engine.world_state.get("flags", {})
	var parsed: Variant = _parse_flag_value(raw_value)
	flags[key] = parsed
	_engine.world_state["flags"] = flags
	print("[开局选择] flag %s = %s" % [key, str(parsed)])


# 功能：world_state param delta 累加（预留）。
func _apply_param_delta(key: String, raw_value: String) -> void:
	if _engine == null:
		return
	var params: Dictionary = _engine.world_state.get("params", {})
	var delta := _parse_delta(raw_value)
	var old_val: int = int(params.get(key, 0))
	params[key] = old_val + delta
	_engine.world_state["params"] = params
	print("[开局选择] param %s: %d → %d" % [key, old_val, old_val + delta])


# 功能：设置玩家当前位置（预留）。
func _apply_location(raw_value: String) -> void:
	if _engine == null:
		return
	_engine.world_state["currentLocationId"] = raw_value
	print("[开局选择] location → %s" % raw_value)


# 功能：追加 NPC 到指定地点的 npcPresence（预留）。
func _apply_npc_presence(location_key: String, npc_id: String) -> void:
	if _engine == null:
		return
	var presence: Dictionary = _engine.world_state.get("npcPresence", {})
	var list: Array = presence.get(location_key, [])
	if not list.has(npc_id):
		list.append(npc_id)
	presence[location_key] = list
	_engine.world_state["npcPresence"] = presence
	print("[开局选择] npc_presence %s += %s" % [location_key, npc_id])


# ── 内部工具 ─────────────────────────────────────────────────────

# 功能：解析 delta 值（支持 +/- 前缀）。
func _parse_delta(raw: String) -> int:
	var text := raw.strip_edges()
	if text.is_empty():
		return 0
	if text.is_valid_int():
		return int(text)
	# 带 + 前缀的情况。
	if text.begins_with("+") and text.substr(1).is_valid_int():
		return int(text.substr(1))
	return 0


# 功能：解析 flag 值（支持 bool、int、字符串）。
func _parse_flag_value(raw: String) -> Variant:
	var text := raw.strip_edges().to_lower()
	if text == "true":
		return true
	if text == "false":
		return false
	if raw.strip_edges().is_valid_int():
		return int(raw.strip_edges())
	return raw.strip_edges()


# 功能：在指定问题中查找选项。
func _find_option(question: Dictionary, option_id: String) -> Dictionary:
	var options: Array = question.get("options", [])
	for opt_variant in options:
		var opt: Dictionary = opt_variant
		if str(opt.get("option_id", "")) == option_id:
			return opt
	return {}


# 功能：从指定索引开始，查找下一个满足条件的问题索引。
# 返回：找到的索引；未找到时返回 -1。
func _find_next_valid_index(from_index: int) -> int:
	var i := from_index
	while i < _questions.size():
		if _is_question_valid(i):
			return i
		i += 1
	return -1


# 功能：预扫描所有满足条件的问题索引。
func _scan_valid_indices() -> Array:
	return _scan_valid_indices_from(0)


# 功能：从指定索引开始，扫描所有满足条件的问题索引。
# 说明：用于 effect apply 后重新计算剩余有效问题，确保 question_total 准确。
func _scan_valid_indices_from(from_index: int) -> Array:
	var indices: Array = []
	for i in range(from_index, _questions.size()):
		if _is_question_valid(i):
			indices.append(i)
	return indices


# 功能：判断指定索引的问题是否满足条件。
func _is_question_valid(index: int) -> bool:
	var question: Dictionary = _questions[index]
	var condition := str(question.get("condition", ""))
	if condition.is_empty():
		return true
	# 通过引擎代理调用条件判定。
	if _engine != null and _engine.has_method("evaluate_condition"):
		return _engine.evaluate_condition(condition)
	return false


# 功能：获取当前问题 ID（用于日志）。
func _get_current_question_id() -> String:
	if _current_index < _questions.size():
		return str(_questions[_current_index].get("question_id", ""))
	return ""


# 功能：构建统一返回结构。
func _build_response(extra: Dictionary = {}) -> Dictionary:
	var response: Dictionary = {
		"ok": true,
		"state": get_state(),
		"available_actions": get_available_actions(),
	}
	# PRESENTING 状态下附加问题信息。
	if _state == State.PRESENTING and _current_index < _questions.size():
		var question: Dictionary = _questions[_current_index]
		response["question_id"] = str(question.get("question_id", ""))
		response["question_text"] = str(question.get("question_text", ""))
		response["question_index"] = _answered_count
		response["question_total"] = _answered_count + _valid_indices.size()
	for key in extra.keys():
		response[key] = extra[key]
	return response
