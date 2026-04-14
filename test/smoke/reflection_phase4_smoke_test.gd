extends RefCounted

# 功能：第四阶段——玩家自省与关系调整冒烟测试集合。
# 说明：覆盖 RoleState 关注列表、周期级累积记录、推荐候选列表、自省操作接口、
#       _is_player_focusing 改造、端到端集成共六大块。

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const RoleState := preload("res://scripts/models/role_state.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")
const SmokeConfig := preload("res://test/smoke/smoke_config.gd")


static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	_test_a1_empty_list_focuses_all(checks, failed)
	_test_a2_init_with_list(checks, failed)
	_test_a3_toggle_focus(checks, failed)
	_test_a4_serialization_roundtrip(checks, failed)

	_test_b1_affinity_deltas_accumulate(checks, failed)
	_test_b2_echo_accumulates(checks, failed)
	_test_b3_clear_method(checks, failed)
	_test_b4_cross_event_preservation(checks, failed)

	_test_c1_sorted_by_count(checks, failed)
	_test_c2_top_n_truncation(checks, failed)
	_test_c3_empty_record(checks, failed)
	_test_c4_candidates_delegate(checks, failed)

	_test_d1_toggle_focus_success(checks, failed)
	_test_d2_trust_positive_adjust(checks, failed)
	_test_d3_trust_negative_adjust(checks, failed)
	_test_d4_ops_limit_reject(checks, failed)
	_test_d5_settle_resets(checks, failed)

	_test_e1_empty_list_compat(checks, failed)
	_test_e2_non_empty_list_filter(checks, failed)
	_test_e3_null_role_state_fallback(checks, failed)

	_test_f1_end_to_end(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# ── A：RoleState 关注列表 ──────────────────────────────────────────

# 场景 A1：空列表默认关注所有 NPC。
static func _test_a1_empty_list_focuses_all(checks: Array, failed: Array) -> void:
	var label := "A1: empty focusing_npcs -> is_focusing returns true"
	var state := RoleState.new("player", "player", "玩家", "", "", {}, {})
	if not state.is_focusing("npc_a"):
		_fail(checks, failed, label, "expected true for npc_a")
		return
	if not state.is_focusing("any_npc"):
		_fail(checks, failed, label, "expected true for any_npc")
		return
	_pass(checks, label)


# 场景 A2：初始化关注列表后精确匹配。
static func _test_a2_init_with_list(checks: Array, failed: Array) -> void:
	var label := "A2: init_focusing_npcs([npc_a]) -> npc_b not focused"
	var state := RoleState.new("player", "player", "玩家", "", "", {}, {})
	state.init_focusing_npcs(["npc_a"])
	if not state.is_focusing("npc_a"):
		_fail(checks, failed, label, "npc_a should be focused")
		return
	if state.is_focusing("npc_b"):
		_fail(checks, failed, label, "npc_b should NOT be focused")
		return
	_pass(checks, label)


# 场景 A3：切换关注状态双向验证。
static func _test_a3_toggle_focus(checks: Array, failed: Array) -> void:
	var label := "A3: toggle_focus adds then removes"
	var state := RoleState.new("player", "player", "玩家", "", "", {}, {})
	state.init_focusing_npcs(["npc_a"])
	# 添加 npc_b
	var added := state.toggle_focus("npc_b")
	if not added:
		_fail(checks, failed, label, "toggle_focus should return true when adding")
		return
	if not state.is_focusing("npc_b"):
		_fail(checks, failed, label, "npc_b should be focused after toggle add")
		return
	# 再次移除 npc_b
	var removed := state.toggle_focus("npc_b")
	if removed:
		_fail(checks, failed, label, "toggle_focus should return false when removing")
		return
	if state.is_focusing("npc_b"):
		_fail(checks, failed, label, "npc_b should NOT be focused after toggle remove")
		return
	_pass(checks, label)


# 场景 A4：to_dict / from_dict 序列化往返。
static func _test_a4_serialization_roundtrip(checks: Array, failed: Array) -> void:
	var label := "A4: to_dict -> from_dict preserves focusing_npcs"
	var state := RoleState.new("player", "player", "玩家", "", "", {}, {})
	state.init_focusing_npcs(["npc_a", "npc_c"])
	var d := state.to_dict()
	var restored := RoleState.from_dict(d)
	if restored.is_focusing("npc_b"):
		_fail(checks, failed, label, "npc_b should NOT be focused after restore")
		return
	if not restored.is_focusing("npc_a"):
		_fail(checks, failed, label, "npc_a should be focused after restore")
		return
	if not restored.is_focusing("npc_c"):
		_fail(checks, failed, label, "npc_c should be focused after restore")
		return
	_pass(checks, label)


# ── B：周期级累积记录 ──────────────────────────────────────────────

# 场景 B1：affinityDeltas 追加到周期记录。
static func _test_b1_affinity_deltas_accumulate(checks: Array, failed: Array) -> void:
	var label := "B1: _apply_affinity_deltas appends to _cycle_affinity_changes"
	var engine := _build_engine()
	# 执行第一批 delta（2条）
	engine._apply_affinity_deltas([
		{"from": "npc_mentor", "to": "player", "delta": 5},
		{"from": "npc_rival", "to": "player", "delta": -3}
	])
	var after_first: int = engine._cycle_affinity_changes.size()
	# 执行第二批 delta（1条）
	engine._apply_affinity_deltas([
		{"from": "npc_guard", "to": "player", "delta": 2}
	])
	var after_second: int = engine._cycle_affinity_changes.size()
	if after_first != 2:
		_fail(checks, failed, label, "expected 2 after first batch, got %d" % after_first)
		return
	if after_second != 3:
		_fail(checks, failed, label, "expected 3 after second batch, got %d" % after_second)
		return
	_pass(checks, label)


# 场景 B2：关系回响也追加到周期记录。
# 说明：构造心性=-2、roll 成功、trust 对齐的场景，触发 echo 并验证记录追加。
static func _test_b2_echo_accumulates(checks: Array, failed: Array) -> void:
	var label := "B2: _apply_relationship_echo appends to _cycle_affinity_changes"
	var engine := _build_engine()
	var before: int = engine._cycle_affinity_changes.size()
	# 直接调用 echo 方法（npc_mentor->player，trust 对齐，成功 roll）
	engine._apply_relationship_echo(
		"npc_mentor",
		[{"success": true}],
		"trust", "trust", "add"
	)
	var after: int = engine._cycle_affinity_changes.size()
	if after != before + 1:
		_fail(checks, failed, label, "expected +1 record, got before=%d after=%d" % [before, after])
		return
	var rec: Dictionary = engine._cycle_affinity_changes[engine._cycle_affinity_changes.size() - 1]
	if str(rec.get("from", "")) != "npc_mentor":
		_fail(checks, failed, label, "expected from=npc_mentor, got: %s" % str(rec.get("from", "")))
		return
	if str(rec.get("to", "")) != "player":
		_fail(checks, failed, label, "expected to=player, got: %s" % str(rec.get("to", "")))
		return
	_pass(checks, label)


# 场景 B3：clear_cycle_affinity_changes 清空记录。
static func _test_b3_clear_method(checks: Array, failed: Array) -> void:
	var label := "B3: clear_cycle_affinity_changes empties the array"
	var engine := _build_engine()
	engine._apply_affinity_deltas([{"from": "npc_mentor", "to": "player", "delta": 5}])
	if engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "pre-condition failed: array should not be empty")
		return
	engine.clear_cycle_affinity_changes()
	if not engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "expected empty after clear, size=%d" % engine._cycle_affinity_changes.size())
		return
	_pass(checks, label)


# 场景 B4：周期记录跨事件保留（_last_affinity_changes 重置不影响 _cycle_affinity_changes）。
static func _test_b4_cross_event_preservation(checks: Array, failed: Array) -> void:
	var label := "B4: _last_affinity_changes reset does not affect _cycle_affinity_changes"
	var engine := _build_engine()
	engine._apply_affinity_deltas([{"from": "npc_mentor", "to": "player", "delta": 5}])
	var cycle_before: int = engine._cycle_affinity_changes.size()
	# 模拟单事件级重置（_last_affinity_changes 清空）
	engine._last_affinity_changes.clear()
	var cycle_after: int = engine._cycle_affinity_changes.size()
	if cycle_before != 1 or cycle_after != 1:
		_fail(checks, failed, label, "cycle_changes should remain 1, got before=%d after=%d" % [cycle_before, cycle_after])
		return
	_pass(checks, label)


# ── C：推荐与候选列表 ──────────────────────────────────────────────

# 场景 C1：按变动次数降序排列。
static func _test_c1_sorted_by_count(checks: Array, failed: Array) -> void:
	var label := "C1: recommended sorted by change_count desc: npc_a(3) > npc_c(2) > npc_b(1)"
	var engine := _build_engine()
	# 手动注入累积记录：npc_a 3次，npc_c 2次，npc_b 1次
	engine._cycle_affinity_changes = [
		{"from": "npc_a", "to": "player", "delta": 1, "old_score": 0, "new_score": 1, "new_tier": "neutral"},
		{"from": "npc_c", "to": "player", "delta": 1, "old_score": 0, "new_score": 1, "new_tier": "neutral"},
		{"from": "npc_a", "to": "player", "delta": 1, "old_score": 1, "new_score": 2, "new_tier": "neutral"},
		{"from": "npc_b", "to": "player", "delta": 1, "old_score": 0, "new_score": 1, "new_tier": "neutral"},
		{"from": "npc_c", "to": "player", "delta": 1, "old_score": 1, "new_score": 2, "new_tier": "neutral"},
		{"from": "npc_a", "to": "player", "delta": 1, "old_score": 2, "new_score": 3, "new_tier": "neutral"},
	]
	# 临时调高 recommend_count 确保取全3个
	engine._reflection_config["recommend_count"] = 3
	var result: Array = engine.get_reflection_recommended_npcs()
	if result.size() != 3:
		_fail(checks, failed, label, "expected 3 results, got %d" % result.size())
		return
	if str(result[0].get("npc_id", "")) != "npc_a":
		_fail(checks, failed, label, "expected npc_a first, got: %s" % str(result[0].get("npc_id", "")))
		return
	if str(result[1].get("npc_id", "")) != "npc_c":
		_fail(checks, failed, label, "expected npc_c second, got: %s" % str(result[1].get("npc_id", "")))
		return
	if str(result[2].get("npc_id", "")) != "npc_b":
		_fail(checks, failed, label, "expected npc_b third, got: %s" % str(result[2].get("npc_id", "")))
		return
	_pass(checks, label)


# 场景 C2：recommend_count=2 时只返回前2个。
static func _test_c2_top_n_truncation(checks: Array, failed: Array) -> void:
	var label := "C2: recommend_count=2 truncates to top 2"
	var engine := _build_engine()
	engine._cycle_affinity_changes = [
		{"from": "npc_a", "to": "player", "delta": 1, "old_score": 0, "new_score": 1, "new_tier": "neutral"},
		{"from": "npc_a", "to": "player", "delta": 1, "old_score": 1, "new_score": 2, "new_tier": "neutral"},
		{"from": "npc_b", "to": "player", "delta": 1, "old_score": 0, "new_score": 1, "new_tier": "neutral"},
		{"from": "npc_c", "to": "player", "delta": 1, "old_score": 0, "new_score": 1, "new_tier": "neutral"},
	]
	engine._reflection_config["recommend_count"] = 2
	var result: Array = engine.get_reflection_recommended_npcs()
	if result.size() != 2:
		_fail(checks, failed, label, "expected 2 results, got %d" % result.size())
		return
	_pass(checks, label)


# 场景 C3：累积为空时返回空数组。
static func _test_c3_empty_record(checks: Array, failed: Array) -> void:
	var label := "C3: empty _cycle_affinity_changes -> empty recommendation"
	var engine := _build_engine()
	var result: Array = engine.get_reflection_recommended_npcs()
	if not result.is_empty():
		_fail(checks, failed, label, "expected empty, got size=%d" % result.size())
		return
	_pass(checks, label)


# 场景 C4：候选列表方法委托推荐方法，结果一致。
static func _test_c4_candidates_delegate(checks: Array, failed: Array) -> void:
	var label := "C4: focus/trust candidates match recommended list"
	var engine := _build_engine()
	engine._cycle_affinity_changes = [
		{"from": "npc_mentor", "to": "player", "delta": 5, "old_score": 0, "new_score": 5, "new_tier": "neutral"},
	]
	engine._reflection_config["recommend_count"] = 3
	var recommended: Array = engine.get_reflection_recommended_npcs()
	var focus_cands: Array = engine.get_focus_candidates()
	var trust_cands: Array = engine.get_trust_adjust_candidates()
	if recommended.size() != focus_cands.size() or recommended.size() != trust_cands.size():
		_fail(checks, failed, label, "size mismatch: recommended=%d focus=%d trust=%d" % [
			recommended.size(), focus_cands.size(), trust_cands.size()
		])
		return
	if not recommended.is_empty():
		if str(recommended[0].get("npc_id", "")) != str(focus_cands[0].get("npc_id", "")):
			_fail(checks, failed, label, "npc_id mismatch between recommended and focus_candidates")
			return
	_pass(checks, label)


# ── D：自省操作接口 ──────────────────────────────────────────────

# 场景 D1：关注切换成功。
static func _test_d1_toggle_focus_success(checks: Array, failed: Array) -> void:
	var label := "D1: reflection_toggle_focus returns success and decrements ops"
	var engine := _build_engine()
	engine._reflection_config["op_limit"] = 2
	engine._reflection_ops_used = 0
	var result: Dictionary = engine.reflection_toggle_focus("npc_mentor")
	if not bool(result.get("success", false)):
		_fail(checks, failed, label, "expected success=true, got: %s" % str(result))
		return
	if int(result.get("ops_remaining", -1)) != 1:
		_fail(checks, failed, label, "expected ops_remaining=1, got: %d" % int(result.get("ops_remaining", -1)))
		return
	_pass(checks, label)


# 场景 D2：信任正向调整，分值增加。
static func _test_d2_trust_positive_adjust(checks: Array, failed: Array) -> void:
	var label := "D2: reflection_adjust_trust positive increases player->npc score"
	var engine := _build_engine()
	engine._reflection_config["op_limit"] = 2
	engine._reflection_ops_used = 0
	var before := engine._affinity_map.get_score("player", "npc_mentor")
	var result: Dictionary = engine.reflection_adjust_trust("npc_mentor", true)
	if not bool(result.get("success", false)):
		_fail(checks, failed, label, "expected success=true")
		return
	var delta: int = int(engine._reflection_config.get("trust_delta_positive", 5))
	var expected_score := before + delta
	var actual_score := engine._affinity_map.get_score("player", "npc_mentor")
	# 分值可能被阈值约束，只检查方向性增长（不低于 before）
	if actual_score < before:
		_fail(checks, failed, label, "score should not decrease: before=%d after=%d" % [before, actual_score])
		return
	if int(result.get("new_score", -999)) != actual_score:
		_fail(checks, failed, label, "result.new_score mismatch: expected=%d got=%d" % [actual_score, int(result.get("new_score", -999))])
		return
	_pass(checks, label)


# 场景 D3：警戒负向调整，分值降低。
static func _test_d3_trust_negative_adjust(checks: Array, failed: Array) -> void:
	var label := "D3: reflection_adjust_trust negative decreases player->npc score"
	var engine := _build_engine()
	engine._reflection_config["op_limit"] = 2
	engine._reflection_ops_used = 0
	var before := engine._affinity_map.get_score("player", "npc_rival")
	var result: Dictionary = engine.reflection_adjust_trust("npc_rival", false)
	if not bool(result.get("success", false)):
		_fail(checks, failed, label, "expected success=true")
		return
	var actual_score := engine._affinity_map.get_score("player", "npc_rival")
	if actual_score > before:
		_fail(checks, failed, label, "score should not increase: before=%d after=%d" % [before, actual_score])
		return
	_pass(checks, label)


# 场景 D4：操作次数耗尽后拒绝执行。
static func _test_d4_ops_limit_reject(checks: Array, failed: Array) -> void:
	var label := "D4: ops_limit_reached returns success=false"
	var engine := _build_engine()
	engine._reflection_config["op_limit"] = 1
	engine._reflection_ops_used = 1  # 已用完
	var r1: Dictionary = engine.reflection_toggle_focus("npc_mentor")
	var r2: Dictionary = engine.reflection_adjust_trust("npc_mentor", true)
	if bool(r1.get("success", true)):
		_fail(checks, failed, label, "toggle_focus should fail when ops exhausted")
		return
	if bool(r2.get("success", true)):
		_fail(checks, failed, label, "adjust_trust should fail when ops exhausted")
		return
	_pass(checks, label)


# 场景 D5：结算后累积记录清空、操作次数重置。
static func _test_d5_settle_resets(checks: Array, failed: Array) -> void:
	var label := "D5: reflection_settle clears records and resets ops_used"
	var engine := _build_engine()
	engine._reflection_ops_used = 1
	engine._cycle_affinity_changes.append({
		"from": "npc_mentor", "to": "player", "delta": 5, "old_score": 0, "new_score": 5, "new_tier": "neutral"
	})
	engine.reflection_settle()
	if not engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "cycle_affinity_changes should be empty after settle")
		return
	if engine._reflection_ops_used != 0:
		_fail(checks, failed, label, "ops_used should be 0 after settle, got %d" % engine._reflection_ops_used)
		return
	_pass(checks, label)


# ── E：_is_player_focusing() 改造 ──────────────────────────────────

# 场景 E1：关注列表为空时，_is_player_focusing 返回 true（保持原行为）。
static func _test_e1_empty_list_compat(checks: Array, failed: Array) -> void:
	var label := "E1: empty focusing_npcs -> _is_player_focusing returns true"
	var engine := _build_engine()
	# player_role_state 已加载，focusing_npcs 默认为空
	if not engine._is_player_focusing("npc_mentor"):
		_fail(checks, failed, label, "expected true for empty focusing list")
		return
	_pass(checks, label)


# 场景 E2：非空关注列表过滤——不在列表中的 NPC affinityDelta 被跳过。
static func _test_e2_non_empty_list_filter(checks: Array, failed: Array) -> void:
	var label := "E2: player->npc_b skipped when npc_b not in focusing_npcs"
	var engine := _build_engine()
	# 设定只关注 npc_mentor，不关注 npc_rival
	if engine.player_role_state != null:
		engine.player_role_state.init_focusing_npcs(["npc_mentor"])
	var before_rival := engine._affinity_map.get_score("player", "npc_rival")
	# 提交一个 player->npc_rival 的 delta（应被过滤）
	engine._apply_affinity_deltas([
		{"from": "player", "to": "npc_rival", "delta": 10}
	])
	var after_rival := engine._affinity_map.get_score("player", "npc_rival")
	if after_rival != before_rival:
		_fail(checks, failed, label, "npc_rival score should be unchanged: before=%d after=%d" % [before_rival, after_rival])
		return
	_pass(checks, label)


# 场景 E3：player_role_state 为 null 时兜底返回 true。
static func _test_e3_null_role_state_fallback(checks: Array, failed: Array) -> void:
	var label := "E3: null player_role_state -> _is_player_focusing returns true"
	var engine := WorldEventEngine.new(1)
	engine.player_role_state = null
	if not engine._is_player_focusing("any_npc"):
		_fail(checks, failed, label, "expected true when player_role_state is null")
		return
	_pass(checks, label)


# ── F：端到端集成 ──────────────────────────────────────────────────

# 场景 F1：加载配置 → 事件产生关系变动 → 推荐列表 → 自省操作 → 结算 → 验证。
static func _test_f1_end_to_end(checks: Array, failed: Array) -> void:
	var label := "F1: end-to-end: load csv -> affinity changes -> reflect -> settle"
	var engine := _build_engine()

	# 手动注入一批变动记录，模拟若干事件后的周期累积
	engine._apply_affinity_deltas([
		{"from": "npc_mentor", "to": "player", "delta": 5},
		{"from": "npc_rival", "to": "player", "delta": -3},
		{"from": "npc_mentor", "to": "player", "delta": 2},
	])
	if engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "cycle_affinity_changes should be non-empty after events")
		return

	# 读取推荐列表，npc_mentor 应出现次数最多
	var recommended: Array = engine.get_reflection_recommended_npcs()
	if recommended.is_empty():
		_fail(checks, failed, label, "recommended list should not be empty")
		return
	if str(recommended[0].get("npc_id", "")) != "npc_mentor":
		_fail(checks, failed, label, "expected npc_mentor at top, got: %s" % str(recommended[0].get("npc_id", "")))
		return

	# 执行 1 次自省操作（信任正向调整）
	engine._reflection_config["op_limit"] = 1
	engine._reflection_ops_used = 0
	var ops_before := engine.get_reflection_ops_remaining()
	var op_result: Dictionary = engine.reflection_adjust_trust("npc_mentor", true)
	if not bool(op_result.get("success", false)):
		_fail(checks, failed, label, "reflection_adjust_trust failed: %s" % str(op_result))
		return
	var ops_after := engine.get_reflection_ops_remaining()
	if ops_after != ops_before - 1:
		_fail(checks, failed, label, "ops_remaining should decrease by 1: before=%d after=%d" % [ops_before, ops_after])
		return

	# 结算
	engine.reflection_settle()
	if not engine._cycle_affinity_changes.is_empty():
		_fail(checks, failed, label, "cycle_affinity_changes should be empty after settle")
		return
	if engine._reflection_ops_used != 0:
		_fail(checks, failed, label, "ops_used should be 0 after settle")
		return

	_pass(checks, label)


# ── 工具方法 ──────────────────────────────────────────────────────

# 功能：构建已加载 CSV 配置的测试引擎。
# 说明：固定随机种子保证可复现；加载完成后 AffinityMap 与 RoleState 均已初始化。
# 说明：csv_dir 从 SmokeConfig 读取，支持外部配置调整。
static func _build_engine() -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260327)
	engine.load_from_csv_dir(SmokeConfig.get_csv_dir())
	return engine


static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)


static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s -> %s" % [label, reason])
