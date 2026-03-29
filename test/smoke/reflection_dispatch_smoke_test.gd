extends RefCounted

# 功能：自省事件调度封装冒��测试集合。
# 说明：覆盖概率触发、主动触发、pending_turn 映射、展示衔接、端到端流程。

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const RoleStateClass := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")


static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	# A：概率触发
	_test_a1_reflection_in_candidates(checks, failed)
	_test_a2_eligibility_filters(checks, failed)
	_test_a3_weight_rules(checks, failed)

	# B：主动触发
	_test_b1_forced_reflection(checks, failed)
	_test_b2_forced_in_chain_context(checks, failed)

	# C：pending_turn 映射
	_test_c1_preview_shows_reflection_phase(checks, failed)
	_test_c2_confirm_adjust_relation(checks, failed)
	_test_c3_confirm_trust(checks, failed)
	_test_c4_multi_round_then_settled(checks, failed)
	_test_c5_skip_settles(checks, failed)

	# D：展示阶段衔接
	_test_d1_with_presentation(checks, failed)
	_test_d2_without_presentation(checks, failed)

	# E：端到端
	_test_e1_scheduler_full_flow(checks, failed)
	_test_e2_forced_full_flow(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# ── A：概率触发 ──────────────────────────────────────────────────

# 场景 A1：sys_reflection 在候选池中出现。
static func _test_a1_reflection_in_candidates(checks: Array, failed: Array) -> void:
	var label := "A1: sys_reflection appears in candidate pool"
	var engine := _build_engine_with_csv()
	var weights: Dictionary = engine.debug_get_candidate_weights()
	var weight_map: Dictionary = weights.get("weights", {})
	if not weight_map.has("sys_reflection"):
		_fail(checks, failed, label, "sys_reflection not in candidates, keys: %s" % str(weight_map.keys()))
		return
	_pass(checks, label)


# 场景 A2：eligibility 过滤生效（地点限制）。
static func _test_a2_eligibility_filters(checks: Array, failed: Array) -> void:
	var label := "A2: eligibility location filter works for reflection event"
	# 使用 JSON 构造一个有地点限制的自省事件。
	var world_state := '{"turn":0,"currentLocationId":"town_square","params":{},"flags":{},"forcedNextEventId":"","history":[]}'
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":["system","reflection"],"eligibility":{"requiredLocations":["harbor"]},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	var weights: Dictionary = engine.debug_get_candidate_weights()
	var weight_map: Dictionary = weights.get("weights", {})
	# 当前在 town_square，自省要求 harbor，应被过滤。
	if weight_map.has("sys_reflection"):
		_fail(checks, failed, label, "sys_reflection should be filtered out by location, but found in candidates")
		return
	_pass(checks, label)


# 场景 A3：weightRules 生效。
static func _test_a3_weight_rules(checks: Array, failed: Array) -> void:
	var label := "A3: weight rules adjust reflection event weight"
	var world_state := '{"turn":0,"currentLocationId":"town","params":{"danger":30},"flags":{},"forcedNextEventId":"","history":[]}'
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":[],"eligibility":{},"weightRules":[{"when":"params.danger >= 20","delta":15}],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	var weights: Dictionary = engine.debug_get_candidate_weights()
	var weight_map: Dictionary = weights.get("weights", {})
	var actual_weight: int = int(weight_map.get("sys_reflection", 0))
	# baseWeight 10 + delta 15 = 25。
	if actual_weight != 25:
		_fail(checks, failed, label, "expected weight 25, got %d" % actual_weight)
		return
	_pass(checks, label)


# ── B：主动触发 ──────────────────────────────────────────────────

# 场景 B1：forcedNextEventId 触发自省。
static func _test_b1_forced_reflection(checks: Array, failed: Array) -> void:
	var label := "B1: forcedNextEventId triggers reflection event"
	var engine := _build_engine_reflection_only("sys_reflection")
	var result: Dictionary = engine.preview_next_turn()
	if not result.get("ok", false):
		_fail(checks, failed, label, "preview_next_turn failed: %s" % str(result.get("error", "")))
		return
	if str(result.get("event_id", "")) != "sys_reflection":
		_fail(checks, failed, label, "expected event_id sys_reflection, got %s" % str(result.get("event_id", "")))
		return
	if str(result.get("route", "")) != "forced":
		_fail(checks, failed, label, "expected route forced, got %s" % str(result.get("route", "")))
		return
	_pass(checks, label)


# 场景 B2：事件链中通过 forced 触发自省。
static func _test_b2_forced_in_chain_context(checks: Array, failed: Array) -> void:
	var label := "B2: forced reflection within chain context"
	var world_state := '{"turn":0,"currentLocationId":"town","params":{},"flags":{},"forcedNextEventId":"sys_reflection","history":[],"chainContext":{"chainId":"test_chain","stage":1,"allowedTags":["system","reflection"]}}'
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":["system","reflection"],"eligibility":{},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	var result: Dictionary = engine.preview_next_turn()
	if not result.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(result.get("error", "")))
		return
	if str(result.get("route", "")) != "forced":
		_fail(checks, failed, label, "expected route forced, got %s" % str(result.get("route", "")))
		return
	if str(result.get("event_id", "")) != "sys_reflection":
		_fail(checks, failed, label, "expected sys_reflection, got %s" % str(result.get("event_id", "")))
		return
	_pass(checks, label)


# ── C：pending_turn 映射 ─────────────────────────────────────────

# 场景 C1：preview_next_turn 返回 reflection phase。
static func _test_c1_preview_shows_reflection_phase(checks: Array, failed: Array) -> void:
	var label := "C1: preview returns reflection phase"
	var engine := _build_engine_reflection_only("sys_reflection")
	var result: Dictionary = engine.preview_next_turn()
	if str(result.get("phase", "")) != "reflection":
		_fail(checks, failed, label, "expected phase reflection, got %s" % str(result.get("phase", "")))
		return
	if not result.has("reflection_state"):
		_fail(checks, failed, label, "missing reflection_state in response")
		return
	if not result.has("reflection_actions"):
		_fail(checks, failed, label, "missing reflection_actions in response")
		return
	_pass(checks, label)


# 场景 C2：confirm_pending_turn("adjust_relation:") 进入调整关系。
static func _test_c2_confirm_adjust_relation(checks: Array, failed: Array) -> void:
	var label := "C2: confirm adjust_relation enters ADJUST_RELATION state"
	var engine := _build_engine_with_changes("sys_reflection")
	engine.preview_next_turn()
	# 首次 confirm 空字符串让状态机启动。
	engine.confirm_pending_turn("")
	var result: Dictionary = engine.confirm_pending_turn("adjust_relation:")
	if str(result.get("reflection_state", "")) != "ADJUST_RELATION":
		_fail(checks, failed, label, "expected ADJUST_RELATION, got %s" % str(result.get("reflection_state", "")))
		return
	_pass(checks, label)


# 场景 C3：confirm_pending_turn("trust:npc_a") 执行信任调整。
static func _test_c3_confirm_trust(checks: Array, failed: Array) -> void:
	var label := "C3: confirm trust:npc_a adjusts trust score"
	var engine := _build_engine_with_changes("sys_reflection")
	engine.preview_next_turn()
	engine.confirm_pending_turn("")
	engine.confirm_pending_turn("adjust_relation:")
	var result: Dictionary = engine.confirm_pending_turn("trust:npc_a")
	# op_limit=1，执行一次操作后应 SETTLED。
	if str(result.get("phase", "")) != "resolved":
		# 操作后额度耗尽应结算，phase 变为 resolved。
		if str(result.get("reflection_state", "")) != "SETTLED":
			_fail(checks, failed, label, "expected SETTLED or resolved, got state=%s phase=%s" % [
				str(result.get("reflection_state", "")), str(result.get("phase", ""))])
			return
	_pass(checks, label)


# 场景 C4：多轮交互后状态机 SETTLED，turn +1。
static func _test_c4_multi_round_then_settled(checks: Array, failed: Array) -> void:
	var label := "C4: multi-round interaction then SETTLED with turn+1"
	var engine := _build_engine_with_changes_and_ops("sys_reflection", 2)
	var initial_turn: int = int(engine.world_state.get("turn", 0))
	engine.preview_next_turn()
	engine.confirm_pending_turn("")
	# 第一次操作：进入调整关系。
	engine.confirm_pending_turn("adjust_relation:")
	# 第一次信任调整，消耗 1 额度，剩余 1，回主菜单。
	var r1: Dictionary = engine.confirm_pending_turn("trust:npc_a")
	if str(r1.get("reflection_state", "")) != "MAIN_MENU":
		_fail(checks, failed, label, "expected MAIN_MENU after first op, got %s" % str(r1.get("reflection_state", "")))
		return
	# 第二次操作：跳过。
	var r2: Dictionary = engine.confirm_pending_turn("skip:")
	# 跳过后应结算完毕，turn +1。
	var final_turn: int = int(engine.world_state.get("turn", 0))
	if final_turn != initial_turn + 1:
		_fail(checks, failed, label, "expected turn %d, got %d" % [initial_turn + 1, final_turn])
		return
	_pass(checks, label)


# 场景 C5：skip 直接结算。
static func _test_c5_skip_settles(checks: Array, failed: Array) -> void:
	var label := "C5: skip settles immediately"
	var engine := _build_engine_with_changes("sys_reflection")
	var initial_turn: int = int(engine.world_state.get("turn", 0))
	engine.preview_next_turn()
	engine.confirm_pending_turn("")
	var result: Dictionary = engine.confirm_pending_turn("skip:")
	var final_turn: int = int(engine.world_state.get("turn", 0))
	if final_turn != initial_turn + 1:
		_fail(checks, failed, label, "expected turn +1, got turn %d -> %d" % [initial_turn, final_turn])
		return
	_pass(checks, label)


# ── D：展示阶段衔接 ─────────────────────────────────────────────

# 场景 D1：有 presentation 时先走展示再进 reflection。
static func _test_d1_with_presentation(checks: Array, failed: Array) -> void:
	var label := "D1: presentation phase before reflection"
	var world_state := '{"turn":0,"currentLocationId":"town","params":{},"flags":{},"forcedNextEventId":"sys_reflection","history":[]}'
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":[],"eligibility":{},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{},"presentation":[{"type":"text","text":"内心独白..."}]}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	var r1: Dictionary = engine.preview_next_turn()
	# 初次应处于展示阶段。
	if str(r1.get("phase", "")) != "presentation":
		_fail(checks, failed, label, "expected presentation phase, got %s" % str(r1.get("phase", "")))
		return
	# confirm 推过展示阶段后应进入 reflection。
	var r2: Dictionary = engine.confirm_pending_turn("")
	if str(r2.get("phase", "")) != "reflection":
		_fail(checks, failed, label, "expected reflection phase after presentation, got %s" % str(r2.get("phase", "")))
		return
	_pass(checks, label)


# 场景 D2：无 presentation 时直接进入 reflection。
static func _test_d2_without_presentation(checks: Array, failed: Array) -> void:
	var label := "D2: no presentation, directly enters reflection"
	var engine := _build_engine_reflection_only("sys_reflection")
	var result: Dictionary = engine.preview_next_turn()
	if str(result.get("phase", "")) != "reflection":
		_fail(checks, failed, label, "expected reflection phase, got %s" % str(result.get("phase", "")))
		return
	_pass(checks, label)


# ── E：端到端 ────────────────────────────────────────────────────

# 场景 E1：概率触发完整流程。
static func _test_e1_scheduler_full_flow(checks: Array, failed: Array) -> void:
	var label := "E1: scheduler trigger full flow"
	# 构造只有 sys_reflection 的事件池，确保被选中。
	var world_state := '{"turn":0,"currentLocationId":"town","params":{},"flags":{},"forcedNextEventId":"","history":[],"reflectionConfig":{"op_limit":1,"trust_delta_positive":5,"trust_delta_negative":-5,"recommend_count":3}}'
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":["system","reflection"],"eligibility":{},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	# 注入关系变动以确保自省有可操作内容。
	_inject_affinity_and_changes(engine)
	var initial_turn: int = int(engine.world_state.get("turn", 0))
	# preview → 进入 reflection phase。
	var r1: Dictionary = engine.preview_next_turn()
	if str(r1.get("route", "")) != "scheduler":
		_fail(checks, failed, label, "expected scheduler route, got %s" % str(r1.get("route", "")))
		return
	# 启动状态机。
	engine.confirm_pending_turn("")
	# 跳过自省。
	var r2: Dictionary = engine.confirm_pending_turn("skip:")
	var final_turn: int = int(engine.world_state.get("turn", 0))
	if final_turn != initial_turn + 1:
		_fail(checks, failed, label, "expected turn+1, got %d -> %d" % [initial_turn, final_turn])
		return
	# 验证历史记录包含 sys_reflection。
	var history: Array = engine.world_state.get("history", [])
	if not ("sys_reflection" in history):
		_fail(checks, failed, label, "sys_reflection not in history: %s" % str(history))
		return
	_pass(checks, label)


# 场景 E2：forced 触发完整流程。
static func _test_e2_forced_full_flow(checks: Array, failed: Array) -> void:
	var label := "E2: forced trigger full flow"
	var world_state := '{"turn":5,"currentLocationId":"town","params":{},"flags":{},"forcedNextEventId":"sys_reflection","history":[],"reflectionConfig":{"op_limit":1,"trust_delta_positive":5,"trust_delta_negative":-5,"recommend_count":3}}'
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":["system","reflection"],"eligibility":{},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	_inject_affinity_and_changes(engine)
	# preview → forced 路由。
	var r1: Dictionary = engine.preview_next_turn()
	if str(r1.get("route", "")) != "forced":
		_fail(checks, failed, label, "expected forced route, got %s" % str(r1.get("route", "")))
		return
	# 启动状态机。
	engine.confirm_pending_turn("")
	# 执行调整关系。
	engine.confirm_pending_turn("adjust_relation:")
	var r2: Dictionary = engine.confirm_pending_turn("trust:npc_a")
	# op_limit=1，应结算。
	var final_turn: int = int(engine.world_state.get("turn", 0))
	if final_turn != 6:
		_fail(checks, failed, label, "expected turn 6, got %d" % final_turn)
		return
	# forcedNextEventId 应被清空。
	var forced: String = str(engine.world_state.get("forcedNextEventId", ""))
	if not forced.is_empty():
		_fail(checks, failed, label, "forcedNextEventId should be cleared, got: %s" % forced)
		return
	_pass(checks, label)


# ── 工具函数 ─────────────────────────────────────────────────────

# 构建从 CSV 加载的完整引擎（包含 sys_reflection 和所有其他事件）。
static func _build_engine_with_csv() -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260329)
	engine.load_from_csv_dir("res://scripts/config/world_event_mvp")
	return engine


# 构建只有 sys_reflection 事件的引擎，通过 forced 路由触发。
static func _build_engine_reflection_only(forced_id: String) -> WorldEventEngine:
	var world_state := '{"turn":0,"currentLocationId":"town","params":{},"flags":{},"forcedNextEventId":"%s","history":[],"reflectionConfig":{"op_limit":1,"trust_delta_positive":5,"trust_delta_negative":-5,"recommend_count":3}}' % forced_id
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":["system","reflection"],"eligibility":{},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	_inject_affinity_and_changes(engine)
	return engine


# 构建有关系变动的引擎（确保自省有可操作内容），forced 触发。
static func _build_engine_with_changes(forced_id: String) -> WorldEventEngine:
	var engine := _build_engine_reflection_only(forced_id)
	return engine


# 构建有关系变动的引擎，自定义 op_limit。
static func _build_engine_with_changes_and_ops(forced_id: String, op_limit: int) -> WorldEventEngine:
	var world_state := '{"turn":0,"currentLocationId":"town","params":{},"flags":{},"forcedNextEventId":"%s","history":[],"reflectionConfig":{"op_limit":%d,"trust_delta_positive":5,"trust_delta_negative":-5,"recommend_count":3}}' % [forced_id, op_limit]
	var events := '[{"id":"sys_reflection","title":"自省","type":"reflection","baseWeight":10,"tags":["system","reflection"],"eligibility":{},"weightRules":[],"continuationPolicy":"ReturnToScheduler","effects":{}}]'
	var engine := WorldEventEngine.new(1)
	engine.load_from_json_text(world_state, events)
	_inject_affinity_and_changes(engine)
	return engine


# 注入 AffinityMap 和周期级累积变动，确保自省推荐列表非空。
static func _inject_affinity_and_changes(engine: WorldEventEngine) -> void:
	# 注入 AffinityMap。
	if engine._affinity_map == null:
		engine._affinity_map = AffinityMap.new()
	engine._affinity_map.set_score("player", "npc_a", 10)
	engine._affinity_map.set_score("npc_a", "player", 5)
	# 注入周期级变动记录。
	engine._cycle_affinity_changes.append({"from": "player", "to": "npc_a", "delta": 5})
	engine._cycle_affinity_changes.append({"from": "npc_a", "to": "player", "delta": 3})


static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)


static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s -> %s" % [label, reason])
