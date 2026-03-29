extends RefCounted

# 功能：自省状态机冒烟测试集合。
# 说明：覆盖空自省短路、主菜单可用性、调整关系操作、关注操作、focusPatch 动作、端到端集成共六组。

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const RoleStateClass := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")


static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	# A：空自省短路
	_test_a1_empty_reflection(checks, failed)
	_test_a2_confirm_settles(checks, failed)

	# B：主菜单可用性
	_test_b1_both_lists_available(checks, failed)
	_test_b2_focus_nonempty_recommend_empty(checks, failed)
	_test_b3_focus_empty_recommend_nonempty(checks, failed)
	_test_b4_skip_settles(checks, failed)

	# C：调整关系操作
	_test_c1_trust_positive(checks, failed)
	_test_c2_trust_negative(checks, failed)
	_test_c3_query_no_consume(checks, failed)
	_test_c4_ops_exhaust_settles(checks, failed)

	# D：关注操作
	_test_d1_add_focus_under_limit(checks, failed)
	_test_d2_add_focus_at_limit(checks, failed)
	_test_d3_remove_then_add(checks, failed)
	_test_d4_recommend_excludes_focused(checks, failed)

	# E：focusPatch 动作
	_test_e1_focus_patch_add(checks, failed)
	_test_e2_focus_patch_remove(checks, failed)
	_test_e3_focus_patch_set(checks, failed)

	# F：端到端集成
	_test_f1_full_flow(checks, failed)
	_test_f2_focus_limit_flow(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# ── A：空自省短路 ─────────────────────────────────────────────────

# 场景 A1：推荐列表和关注列表都为空时，进入 EMPTY_REFLECTION 状态。
static func _test_a1_empty_reflection(checks: Array, failed: Array) -> void:
	var label := "A1: empty recommend + empty focus -> EMPTY_REFLECTION"
	var engine := _build_engine_with_player()
	# 不产生任何关系变动，推荐列表为空；关注列表也为空。
	var result: Dictionary = engine.start_reflection()
	if not result.get("ok", false):
		_fail(checks, failed, label, "start_reflection failed: %s" % str(result))
		return
	if result.get("state", "") != "EMPTY_REFLECTION":
		_fail(checks, failed, label, "expected EMPTY_REFLECTION, got %s" % result.get("state", ""))
		return
	if not result.has("text"):
		_fail(checks, failed, label, "expected text field in response")
		return
	_pass(checks, label)


# 场景 A2：confirm 后状态变为 SETTLED，累积记录已清空。
static func _test_a2_confirm_settles(checks: Array, failed: Array) -> void:
	var label := "A2: confirm -> SETTLED and records cleared"
	var engine := _build_engine_with_player()
	engine.start_reflection()
	var result: Dictionary = engine.reflection_confirm()
	if result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED, got %s" % result.get("state", ""))
		return
	if not engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "cycle changes should be empty after settle")
		return
	_pass(checks, label)


# ── B：主菜单可用性 ──────────────────────────────────────────────

# 场景 B1：有已关注NPC、有推荐NPC（不重叠），调整关系和关注均可选。
static func _test_b1_both_lists_available(checks: Array, failed: Array) -> void:
	var label := "B1: focus nonempty + recommend nonempty -> both enabled"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	engine.player_role_state.focus_limit = 3
	# 产生一些不涉及 npc_mentor 的关系变动，生成推荐列表。
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
		{"from": "npc_guard", "to": "player", "delta": -3},
	])
	var result: Dictionary = engine.start_reflection()
	if result.get("state", "") != "MAIN_MENU":
		_fail(checks, failed, label, "expected MAIN_MENU, got %s" % result.get("state", ""))
		return
	var actions: Array = result.get("available_actions", [])
	var adjust_action: Dictionary = _find_action(actions, "adjust_relation")
	var focus_action: Dictionary = _find_action(actions, "focus")
	if not adjust_action.get("enabled", false):
		_fail(checks, failed, label, "adjust_relation should be enabled")
		return
	if not focus_action.get("enabled", false):
		_fail(checks, failed, label, "focus should be enabled")
		return
	_pass(checks, label)


# 场景 B2：关注列表非空但推荐列表为空，调整关系可选，关注置灰。
static func _test_b2_focus_nonempty_recommend_empty(checks: Array, failed: Array) -> void:
	var label := "B2: focus nonempty + recommend empty -> adjust enabled, focus disabled"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	# 不产生任何关系变动，推荐列表为空。
	var result: Dictionary = engine.start_reflection()
	if result.get("state", "") != "MAIN_MENU":
		_fail(checks, failed, label, "expected MAIN_MENU, got %s" % result.get("state", ""))
		return
	var actions: Array = result.get("available_actions", [])
	var adjust_action: Dictionary = _find_action(actions, "adjust_relation")
	var focus_action: Dictionary = _find_action(actions, "focus")
	if not adjust_action.get("enabled", false):
		_fail(checks, failed, label, "adjust_relation should be enabled (focus list has NPC)")
		return
	if focus_action.get("enabled", false):
		_fail(checks, failed, label, "focus should be disabled (no recommendations)")
		return
	_pass(checks, label)


# 场景 B3：关注列表为空、推荐列表非空，调整关系可选（显示推荐NPC），关注可选。
static func _test_b3_focus_empty_recommend_nonempty(checks: Array, failed: Array) -> void:
	var label := "B3: focus empty + recommend nonempty -> both enabled"
	var engine := _build_engine_with_player()
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
	])
	var result: Dictionary = engine.start_reflection()
	if result.get("state", "") != "MAIN_MENU":
		_fail(checks, failed, label, "expected MAIN_MENU, got %s" % result.get("state", ""))
		return
	var actions: Array = result.get("available_actions", [])
	var adjust_action: Dictionary = _find_action(actions, "adjust_relation")
	var focus_action: Dictionary = _find_action(actions, "focus")
	if not adjust_action.get("enabled", false):
		_fail(checks, failed, label, "adjust_relation should be enabled (recommend has NPC)")
		return
	if not focus_action.get("enabled", false):
		_fail(checks, failed, label, "focus should be enabled")
		return
	_pass(checks, label)


# 场景 B4：跳过后状态变为 SETTLED，累积记录已清空。
static func _test_b4_skip_settles(checks: Array, failed: Array) -> void:
	var label := "B4: skip -> SETTLED, records cleared"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	_inject_cycle_changes(engine, [{"from": "npc_rival", "to": "player", "delta": 5}])
	engine.start_reflection()
	var result: Dictionary = engine.reflection_act("skip")
	if result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED, got %s" % result.get("state", ""))
		return
	# 跳过触发结算，累积记录应被清空。
	if not engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "cycle changes should be empty after skip settle")
		return
	# 结算后自省不再活跃。
	if engine.is_reflection_active():
		_fail(checks, failed, label, "reflection should not be active after skip")
		return
	_pass(checks, label)


# ── C：调整关系操作 ──────────────────────────────────────────────

# 场景 C1：+信任增加分值，消耗1额度。
static func _test_c1_trust_positive(checks: Array, failed: Array) -> void:
	var label := "C1: trust positive increases score and consumes 1 op"
	var engine := _build_engine_with_player()
	# 设置 op_limit=2 以便测试不立即结束。
	engine._reflection_config["op_limit"] = 2
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	var score_before: int = engine._affinity_map.get_score("player", "npc_mentor")
	engine.start_reflection()
	engine.reflection_act("adjust_relation")
	var result: Dictionary = engine.reflection_act("trust", "npc_mentor")
	if not result.get("ok", false):
		_fail(checks, failed, label, "act failed: %s" % str(result))
		return
	var score_after: int = engine._affinity_map.get_score("player", "npc_mentor")
	var expected_delta: int = int(engine._reflection_config.get("trust_delta_positive", 5))
	if score_after != score_before + expected_delta:
		_fail(checks, failed, label, "expected score %d, got %d" % [score_before + expected_delta, score_after])
		return
	if result.get("state", "") != "MAIN_MENU":
		_fail(checks, failed, label, "expected MAIN_MENU (still have ops), got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# 场景 C2：+警惕减少分值。
static func _test_c2_trust_negative(checks: Array, failed: Array) -> void:
	var label := "C2: distrust decreases score"
	var engine := _build_engine_with_player()
	engine._reflection_config["op_limit"] = 2
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	var score_before: int = engine._affinity_map.get_score("player", "npc_mentor")
	engine.start_reflection()
	engine.reflection_act("adjust_relation")
	var result: Dictionary = engine.reflection_act("distrust", "npc_mentor")
	if not result.get("ok", false):
		_fail(checks, failed, label, "act failed: %s" % str(result))
		return
	var score_after: int = engine._affinity_map.get_score("player", "npc_mentor")
	var expected_delta: int = int(engine._reflection_config.get("trust_delta_negative", -5))
	if score_after != score_before + expected_delta:
		_fail(checks, failed, label, "expected score %d, got %d" % [score_before + expected_delta, score_after])
		return
	_pass(checks, label)


# 场景 C3：查询不消耗额度，状态仍为 ADJUST_RELATION。
static func _test_c3_query_no_consume(checks: Array, failed: Array) -> void:
	var label := "C3: query returns info, no op consumed, stays in ADJUST_RELATION"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	engine.start_reflection()
	engine.reflection_act("adjust_relation")
	var ops_before: int = engine.get_reflection_ops_remaining()
	var result: Dictionary = engine.reflection_act("query", "npc_mentor")
	if not result.get("ok", false):
		_fail(checks, failed, label, "act failed: %s" % str(result))
		return
	if result.get("state", "") != "ADJUST_RELATION":
		_fail(checks, failed, label, "expected ADJUST_RELATION, got %s" % result.get("state", ""))
		return
	var ops_after: int = engine.get_reflection_ops_remaining()
	if ops_after != ops_before:
		_fail(checks, failed, label, "ops should not change, before=%d after=%d" % [ops_before, ops_after])
		return
	var qr: Dictionary = result.get("query_result", {})
	if not qr.has("current_score") or not qr.has("current_tier"):
		_fail(checks, failed, label, "query_result missing score or tier fields")
		return
	_pass(checks, label)


# 场景 C4：额度耗尽后自动结算。
static func _test_c4_ops_exhaust_settles(checks: Array, failed: Array) -> void:
	var label := "C4: ops exhaust -> SETTLED"
	var engine := _build_engine_with_player()
	# op_limit=1，一次操作后应自动结算。
	engine._reflection_config["op_limit"] = 1
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	engine.start_reflection()
	engine.reflection_act("adjust_relation")
	var result: Dictionary = engine.reflection_act("trust", "npc_mentor")
	if result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED after single op, got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# ── D：关注操作 ──────────────────────────────────────────────────

# 场景 D1：关注未满，选推荐NPC直接添加。
static func _test_d1_add_focus_under_limit(checks: Array, failed: Array) -> void:
	var label := "D1: add focus under limit -> NPC added, 1 op consumed"
	var engine := _build_engine_with_player()
	engine._reflection_config["op_limit"] = 2
	engine.player_role_state.focus_limit = 3
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
	])
	engine.start_reflection()
	engine.reflection_act("focus")
	var result: Dictionary = engine.reflection_act("add_focus", "npc_rival")
	if not result.get("ok", false):
		_fail(checks, failed, label, "act failed: %s" % str(result))
		return
	if not engine.player_role_state.focusing_npcs.has("npc_rival"):
		_fail(checks, failed, label, "npc_rival should be in focusing_npcs")
		return
	_pass(checks, label)


# 场景 D2：关注已满时进入 FOCUS_REMOVE 状态。
static func _test_d2_add_focus_at_limit(checks: Array, failed: Array) -> void:
	var label := "D2: add focus at limit -> enters FOCUS_REMOVE"
	var engine := _build_engine_with_player()
	engine._reflection_config["op_limit"] = 2
	engine.player_role_state.focus_limit = 1
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
	])
	engine.start_reflection()
	engine.reflection_act("focus")
	var result: Dictionary = engine.reflection_act("add_focus", "npc_rival")
	if result.get("state", "") != "FOCUS_REMOVE":
		_fail(checks, failed, label, "expected FOCUS_REMOVE, got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# 场景 D3：在 FOCUS_REMOVE 中移除旧NPC，添加新NPC。
static func _test_d3_remove_then_add(checks: Array, failed: Array) -> void:
	var label := "D3: remove old + add new in FOCUS_REMOVE"
	var engine := _build_engine_with_player()
	engine._reflection_config["op_limit"] = 2
	engine.player_role_state.focus_limit = 1
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
	])
	engine.start_reflection()
	engine.reflection_act("focus")
	engine.reflection_act("add_focus", "npc_rival")
	# 现在在 FOCUS_REMOVE 状态，移除 npc_mentor。
	var result: Dictionary = engine.reflection_act("remove_focus", "npc_mentor")
	if not result.get("ok", false):
		_fail(checks, failed, label, "act failed: %s" % str(result))
		return
	if engine.player_role_state.focusing_npcs.has("npc_mentor"):
		_fail(checks, failed, label, "npc_mentor should be removed")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_rival"):
		_fail(checks, failed, label, "npc_rival should be added")
		return
	_pass(checks, label)


# 场景 D4：推荐列表排除已关注NPC。
static func _test_d4_recommend_excludes_focused(checks: Array, failed: Array) -> void:
	var label := "D4: recommended list excludes focused NPCs"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	_inject_cycle_changes(engine, [
		{"from": "npc_mentor", "to": "player", "delta": 5},
		{"from": "npc_rival", "to": "player", "delta": 3},
	])
	var recommended: Array = engine.get_reflection_recommended_npcs()
	for item_variant in recommended:
		var item: Dictionary = item_variant
		if str(item.get("npc_id", "")) == "npc_mentor":
			_fail(checks, failed, label, "npc_mentor should NOT appear in recommendations (already focused)")
			return
	# npc_rival 应该在推荐列表中。
	var found_rival := false
	for item_variant in recommended:
		var item: Dictionary = item_variant
		if str(item.get("npc_id", "")) == "npc_rival":
			found_rival = true
			break
	if not found_rival:
		_fail(checks, failed, label, "npc_rival should appear in recommendations")
		return
	_pass(checks, label)


# ── E：focusPatch 动作 ───────────────────────────────────────────

# 场景 E1：add 操作添加到关注列表。
static func _test_e1_focus_patch_add(checks: Array, failed: Array) -> void:
	var label := "E1: focusPatch add -> NPC added to focusing_npcs"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	engine._apply_focus_patch({"op": "add", "npcs": ["npc_rival", "npc_guard"]})
	if not engine.player_role_state.focusing_npcs.has("npc_rival"):
		_fail(checks, failed, label, "npc_rival should be added")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_guard"):
		_fail(checks, failed, label, "npc_guard should be added")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_mentor"):
		_fail(checks, failed, label, "npc_mentor should still be present")
		return
	_pass(checks, label)


# 场景 E2：remove 操作从关注列表移除。
static func _test_e2_focus_patch_remove(checks: Array, failed: Array) -> void:
	var label := "E2: focusPatch remove -> NPC removed from focusing_npcs"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor", "npc_rival"])
	engine._apply_focus_patch({"op": "remove", "npcs": ["npc_mentor"]})
	if engine.player_role_state.focusing_npcs.has("npc_mentor"):
		_fail(checks, failed, label, "npc_mentor should be removed")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_rival"):
		_fail(checks, failed, label, "npc_rival should still be present")
		return
	_pass(checks, label)


# 场景 E3：set 操作替换整个关注列表。
static func _test_e3_focus_patch_set(checks: Array, failed: Array) -> void:
	var label := "E3: focusPatch set -> focusing_npcs replaced entirely"
	var engine := _build_engine_with_player()
	engine.player_role_state.init_focusing_npcs(["npc_mentor", "npc_rival"])
	engine._apply_focus_patch({"op": "set", "npcs": ["npc_guard"]})
	if engine.player_role_state.focusing_npcs.has("npc_mentor"):
		_fail(checks, failed, label, "npc_mentor should be gone after set")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_guard"):
		_fail(checks, failed, label, "npc_guard should be set")
		return
	if engine.player_role_state.focusing_npcs.size() != 1:
		_fail(checks, failed, label, "expected exactly 1 focused NPC, got %d" % engine.player_role_state.focusing_npcs.size())
		return
	_pass(checks, label)


# ── F：端到端集成 ────────────────────────────────────────────────

# 场景 F1：完整流程——产生变动 → 自省 → 调整关系 → 额度耗尽 → 验证。
static func _test_f1_full_flow(checks: Array, failed: Array) -> void:
	var label := "F1: full flow - changes -> reflection -> adjust -> settle"
	var engine := _build_engine_with_player()
	engine._reflection_config["op_limit"] = 1
	engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	# 产生关系变动。
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
	])
	var score_before: int = engine._affinity_map.get_score("player", "npc_mentor")
	# 启动自省。
	var start_result: Dictionary = engine.start_reflection()
	if start_result.get("state", "") != "MAIN_MENU":
		_fail(checks, failed, label, "expected MAIN_MENU, got %s" % start_result.get("state", ""))
		return
	# 进入调整关系。
	engine.reflection_act("adjust_relation")
	# 执行 +信任。
	var act_result: Dictionary = engine.reflection_act("trust", "npc_mentor")
	if act_result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED after op, got %s" % act_result.get("state", ""))
		return
	# 验证分值变化。
	var score_after: int = engine._affinity_map.get_score("player", "npc_mentor")
	var expected_delta: int = int(engine._reflection_config.get("trust_delta_positive", 5))
	if score_after != score_before + expected_delta:
		_fail(checks, failed, label, "score mismatch: expected %d, got %d" % [score_before + expected_delta, score_after])
		return
	# 验证累积记录已清空。
	if not engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "cycle changes should be empty after settle")
		return
	# 验证自省不再活跃。
	if engine.is_reflection_active():
		_fail(checks, failed, label, "reflection should not be active after settle")
		return
	_pass(checks, label)


# 场景 F2：关注上限流程——关注已满 → 移除 → 添加 → 验证。
static func _test_f2_focus_limit_flow(checks: Array, failed: Array) -> void:
	var label := "F2: focus limit flow - full -> remove -> add -> verify"
	var engine := _build_engine_with_player()
	engine._reflection_config["op_limit"] = 2
	engine.player_role_state.focus_limit = 2
	engine.player_role_state.init_focusing_npcs(["npc_mentor", "npc_guard"])
	# 产生变动让 npc_rival 进入推荐列表。
	_inject_cycle_changes(engine, [
		{"from": "npc_rival", "to": "player", "delta": 5},
	])
	# 启动自省。
	engine.start_reflection()
	# 选择关注。
	engine.reflection_act("focus")
	# 添加 npc_rival → 应进入 FOCUS_REMOVE（关注已满）。
	var add_result: Dictionary = engine.reflection_act("add_focus", "npc_rival")
	if add_result.get("state", "") != "FOCUS_REMOVE":
		_fail(checks, failed, label, "expected FOCUS_REMOVE, got %s" % add_result.get("state", ""))
		return
	# 移除 npc_guard。
	var remove_result: Dictionary = engine.reflection_act("remove_focus", "npc_guard")
	if not remove_result.get("ok", false):
		_fail(checks, failed, label, "remove act failed: %s" % str(remove_result))
		return
	# 验证关注列表。
	if engine.player_role_state.focusing_npcs.has("npc_guard"):
		_fail(checks, failed, label, "npc_guard should be removed")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_rival"):
		_fail(checks, failed, label, "npc_rival should be added")
		return
	if not engine.player_role_state.focusing_npcs.has("npc_mentor"):
		_fail(checks, failed, label, "npc_mentor should still be present")
		return
	if engine.player_role_state.focusing_npcs.size() != 2:
		_fail(checks, failed, label, "expected 2 focused NPCs, got %d" % engine.player_role_state.focusing_npcs.size())
		return
	_pass(checks, label)


# ── 辅助方法 ─────────────────────────────────────────────────────

# 构建带玩家角色的引擎实例。
static func _build_engine_with_player() -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260329)
	engine.load_from_csv_dir("res://scripts/config/world_event_mvp")
	return engine

# 向引擎注入周期级累积变动记录（绕过事件执行流程，直接写入）。
static func _inject_cycle_changes(engine: WorldEventEngine, changes: Array) -> void:
	for change in changes:
		engine._cycle_affinity_changes.append(change)

# 在操作列表中查找指定 action 的项。
static func _find_action(actions: Array, action_name: String) -> Dictionary:
	for action_variant in actions:
		var action: Dictionary = action_variant
		if str(action.get("action", "")) == action_name:
			return action
	return {}

static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)

static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s -> %s" % [label, reason])
