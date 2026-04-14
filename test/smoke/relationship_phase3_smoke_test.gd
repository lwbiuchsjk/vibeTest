extends RefCounted

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const RuleEngine := preload("res://scripts/systems/rule_engine.gd")
const AffinityMap := preload("res://scripts/models/affinity_map.gd")
const SmokeConfig := preload("res://test/smoke/smoke_config.gd")


# 功能：固定随机序列，便于在 smoke 中复现骰面结果。
class MockRng:
	extends RefCounted
	var _values: Array = []
	var _index := 0

	func _init(values: Array = []) -> void:
		_values = values.duplicate(true)

	func randf() -> float:
		if _values.is_empty():
			return 0.5
		var idx := mini(_index, _values.size() - 1)
		var value := float(_values[idx])
		_index += 1
		return clampf(value, 0.0, 0.999999)

	func randi_range(from: int, to: int) -> int:
		if _values.is_empty():
			return from
		var idx := mini(_index, _values.size() - 1)
		var value := int(_values[idx])
		_index += 1
		return clampi(value, from, to)


# 功能：第三阶段关系接入鉴定冒烟测试集合。
# 说明：覆盖五档映射、关系修正判定、affinityDeltas、-2回响、端到端集成。
static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	_test_a_five_tier_mapping(checks, failed)
	_test_b_resolve_relationship_check_trust(checks, failed)
	_test_c_resolve_relationship_check_hatred(checks, failed)
	_test_d_resolve_relationship_check_neutral_no_intervention(checks, failed)
	_test_e_alignment_bonus(checks, failed)
	_test_f_relationship_bias_injected_into_pool(checks, failed)
	_test_g_affinity_deltas_applied(checks, failed)
	_test_h_neg2_echo_triggered(checks, failed)
	_test_i_neg2_echo_not_triggered_without_alignment(checks, failed)
	_test_j_end_to_end_csv_integration(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# 场景 A：五档映射验证。
# 说明：验证各分值区间正确映射到 hatred / distrust / neutral / trust / devotion。
static func _test_a_five_tier_mapping(checks: Array, failed: Array) -> void:
	var label := "A: five-tier affinity mapping"
	var thresholds := {
		"tier_hatred_max": -51,
		"tier_distrust_max": -11,
		"tier_trust_min": 11,
		"tier_devotion_min": 51
	}

	var cases := [
		[-100, "hatred"], [-51, "hatred"], [-52, "hatred"],
		[-50, "distrust"], [-11, "distrust"], [-12, "distrust"],
		[-10, "neutral"], [0, "neutral"], [10, "neutral"],
		[11, "trust"], [50, "trust"], [12, "trust"],
		[51, "devotion"], [100, "devotion"], [52, "devotion"]
	]

	for case in cases:
		var score: int = case[0]
		var expected: String = case[1]
		var actual := RuleEngine.affinity_tier(score, thresholds)
		if actual != expected:
			_fail(checks, failed, label, "score=%d: expected %s, got %s" % [score, expected, actual])
			return

	_pass(checks, label)


# 场景 B：trust 档位 NPC 关系修正判定（加骰方向）。
# 说明：NPC→玩家 score=20（trust），判定 1 次，方向 add。
#       用 MockRng 控制骰面，验证 bias 为 +1。
static func _test_b_resolve_relationship_check_trust(checks: Array, failed: Array) -> void:
	var label := "B: relationship check trust -> add bias"
	var thresholds := {"tier_hatred_max": -51, "tier_distrust_max": -11, "tier_trust_min": 11, "tier_devotion_min": 51}
	# NPC→玩家=20(trust)，玩家→NPC=0(neutral)，difficulty=2
	# hit_value = 5 - 2 + 0(不对齐) = 3，骰面=2 → 2 ≤ 3 → 成功
	var result := RuleEngine.resolve_relationship_check(20, 0, 2, thresholds, MockRng.new([2]))

	if str(result.get("npc_tier", "")) != "trust":
		_fail(checks, failed, label, "expected npc_tier=trust, got: %s" % str(result.get("npc_tier", "")))
		return
	if str(result.get("direction", "")) != "add":
		_fail(checks, failed, label, "expected direction=add, got: %s" % str(result.get("direction", "")))
		return
	if int(result.get("bias", 0)) != 1:
		_fail(checks, failed, label, "expected bias=1, got: %d" % int(result.get("bias", 0)))
		return
	var rolls: Array = result.get("rolls", [])
	if rolls.size() != 1:
		_fail(checks, failed, label, "expected 1 roll, got: %d" % rolls.size())
		return

	_pass(checks, label)


# 场景 C：hatred 档位 NPC 关系修正判定（减骰方向，2 次判定）。
# 说明：NPC→玩家 score=-60（hatred），判定 2 次，方向 remove。
static func _test_c_resolve_relationship_check_hatred(checks: Array, failed: Array) -> void:
	var label := "C: relationship check hatred -> remove bias (2 rolls)"
	var thresholds := {"tier_hatred_max": -51, "tier_distrust_max": -11, "tier_trust_min": 11, "tier_devotion_min": 51}
	# NPC→玩家=-60(hatred)，玩家→NPC=0(neutral)，difficulty=1
	# hit_value = 5 - 1 + 0 = 4
	# 骰面=[3, 7]: 第一次 3 ≤ 4 → 成功(-1)，第二次 7 > 4 → 失败
	var result := RuleEngine.resolve_relationship_check(-60, 0, 1, thresholds, MockRng.new([3, 7]))

	if str(result.get("npc_tier", "")) != "hatred":
		_fail(checks, failed, label, "expected npc_tier=hatred, got: %s" % str(result.get("npc_tier", "")))
		return
	if str(result.get("direction", "")) != "remove":
		_fail(checks, failed, label, "expected direction=remove, got: %s" % str(result.get("direction", "")))
		return
	if int(result.get("bias", 0)) != -1:
		_fail(checks, failed, label, "expected bias=-1, got: %d" % int(result.get("bias", 0)))
		return
	var rolls: Array = result.get("rolls", [])
	if rolls.size() != 2:
		_fail(checks, failed, label, "expected 2 rolls, got: %d" % rolls.size())
		return

	_pass(checks, label)


# 场景 D：neutral 档位 NPC 不介入判定。
static func _test_d_resolve_relationship_check_neutral_no_intervention(checks: Array, failed: Array) -> void:
	var label := "D: relationship check neutral -> no intervention"
	var thresholds := {"tier_hatred_max": -51, "tier_distrust_max": -11, "tier_trust_min": 11, "tier_devotion_min": 51}
	var result := RuleEngine.resolve_relationship_check(0, 0, 0, thresholds, MockRng.new([1]))

	if str(result.get("direction", "")) != "none":
		_fail(checks, failed, label, "expected direction=none, got: %s" % str(result.get("direction", "")))
		return
	if int(result.get("bias", 0)) != 0:
		_fail(checks, failed, label, "expected bias=0, got: %d" % int(result.get("bias", 0)))
		return
	var rolls: Array = result.get("rolls", [])
	if rolls.size() != 0:
		_fail(checks, failed, label, "expected 0 rolls, got: %d" % rolls.size())
		return

	_pass(checks, label)


# 场景 E：玩家态度对齐修正验证。
# 说明：NPC trust(add) + 玩家 trust → 对齐修正 +1，命中值 = 5 - 3 + 1 = 3。
#       NPC trust(add) + 玩家 devotion → 对齐修正 +2，命中值 = 5 - 3 + 2 = 4。
static func _test_e_alignment_bonus(checks: Array, failed: Array) -> void:
	var label := "E: alignment bonus increases hit value"
	var thresholds := {"tier_hatred_max": -51, "tier_distrust_max": -11, "tier_trust_min": 11, "tier_devotion_min": 51}

	# NPC→玩家=20(trust)，玩家→NPC=20(trust)，difficulty=3
	# hit_value = 5 - 3 + 1(trust对齐) = 3，骰面=3 → 3 ≤ 3 → 成功
	var r1 := RuleEngine.resolve_relationship_check(20, 20, 3, thresholds, MockRng.new([3]))
	if not bool(r1.get("aligned", false)):
		_fail(checks, failed, label, "expected aligned=true for trust+add")
		return
	if int(r1.get("bias", 0)) != 1:
		_fail(checks, failed, label, "trust alignment: expected bias=1, got: %d" % int(r1.get("bias", 0)))
		return

	# NPC→玩家=20(trust)，玩家→NPC=60(devotion)，difficulty=3
	# hit_value = 5 - 3 + 2(devotion对齐) = 4，骰面=4 → 4 ≤ 4 → 成功
	var r2 := RuleEngine.resolve_relationship_check(20, 60, 3, thresholds, MockRng.new([4]))
	if int(r2.get("bias", 0)) != 1:
		_fail(checks, failed, label, "devotion alignment: expected bias=1, got: %d" % int(r2.get("bias", 0)))
		return

	# NPC→玩家=20(trust, add)，玩家→NPC=-20(distrust) → 交叉不对齐
	# hit_value = 5 - 3 + 0 = 2，骰面=3 → 3 > 2 → 失败
	var r3 := RuleEngine.resolve_relationship_check(20, -20, 3, thresholds, MockRng.new([3]))
	if bool(r3.get("aligned", false)):
		_fail(checks, failed, label, "cross alignment should be false")
		return
	if int(r3.get("bias", 0)) != 0:
		_fail(checks, failed, label, "cross alignment: expected bias=0, got: %d" % int(r3.get("bias", 0)))
		return

	_pass(checks, label)


# 场景 F：relationship_bias 注入骰池验证。
# 说明：relationship_bias=+1 时骰池增加 1 颗骰子。
static func _test_f_relationship_bias_injected_into_pool(checks: Array, failed: Array) -> void:
	var label := "F: relationship_bias injected into dice pool"
	var check_cfg := {
		"type": "assessment", "hitThreshold": 6, "requiredHits": 1,
		"items": [{"key": "physique", "direction": "positive"}]
	}
	var role := {"physique": 5}
	var thresholds := [0, 3, 7, 12]

	# physique=5 → stage=1 → score=1
	# 无 relationship_bias: pool_size = 1
	var r1 := RuleEngine.resolve_check(check_cfg, role, thresholds, MockRng.new([8]), {"xinxing": 0})
	if int(r1.get("pool_size", 0)) != 1:
		_fail(checks, failed, label, "without bias: expected pool=1, got: %d" % int(r1.get("pool_size", 0)))
		return

	# 有 relationship_bias=2: pool_size = 1 + 2 = 3
	var r2 := RuleEngine.resolve_check(check_cfg, role, thresholds, MockRng.new([8, 3, 4]), {"xinxing": 0, "relationship_bias": 2})
	if int(r2.get("pool_size", 0)) != 3:
		_fail(checks, failed, label, "with bias=2: expected pool=3, got: %d" % int(r2.get("pool_size", 0)))
		return

	_pass(checks, label)


# 场景 G：affinityDeltas 执行验证。
# 说明：模拟 _apply_affinity_deltas 后 AffinityMap 分值变化。
static func _test_g_affinity_deltas_applied(checks: Array, failed: Array) -> void:
	var label := "G: affinityDeltas applied to AffinityMap"
	var engine := _build_relationship_engine(0)

	# 初始分值：player->npc_mentor=20, npc_mentor->player=15
	var before_p2m := engine._affinity_map.get_score("player", "npc_mentor")
	var before_m2p := engine._affinity_map.get_score("npc_mentor", "player")
	if before_p2m != 20:
		_fail(checks, failed, label, "init player->npc_mentor: expected 20, got: %d" % before_p2m)
		return
	if before_m2p != 15:
		_fail(checks, failed, label, "init npc_mentor->player: expected 15, got: %d" % before_m2p)
		return

	# 执行 affinityDeltas
	var deltas := [
		{"from": "player", "to": "npc_mentor", "delta": 10},
		{"from": "npc_mentor", "to": "player", "delta": 5}
	]
	engine._apply_affinity_deltas(deltas)

	var after_p2m := engine._affinity_map.get_score("player", "npc_mentor")
	var after_m2p := engine._affinity_map.get_score("npc_mentor", "player")
	if after_p2m != 30:
		_fail(checks, failed, label, "after delta player->npc_mentor: expected 30, got: %d" % after_p2m)
		return
	if after_m2p != 20:
		_fail(checks, failed, label, "after delta npc_mentor->player: expected 20, got: %d" % after_m2p)
		return

	_pass(checks, label)


# 场景 H：-2 阶段关系回响触发验证。
# 说明：心性 -2 + 双方信赖对齐 + 掷骰成功 → NPC→玩家关系自动增加。
static func _test_h_neg2_echo_triggered(checks: Array, failed: Array) -> void:
	var label := "H: -2 echo triggered with aligned trust"
	var engine := _build_relationship_engine(-2)

	# npc_mentor->player 初始=15，echo_trust_delta=5
	var before := engine._affinity_map.get_score("npc_mentor", "player")

	# 构造 check_result，模拟关系判定成功
	var check_result := {
		"relationship_details": [
			{
				"npc_id": "npc_mentor",
				"detail": {
					"npc_tier": "trust",
					"player_tier": "trust",
					"direction": "add",
					"aligned": true,
					"bias": 1,
					"rolls": [{"die": 3, "hit_value": 5, "success": true}]
				}
			}
		]
	}

	engine._try_relationship_echo(check_result)
	var after := engine._affinity_map.get_score("npc_mentor", "player")
	if after != before + 5:
		_fail(checks, failed, label, "expected npc_mentor->player=%d, got: %d" % [before + 5, after])
		return

	_pass(checks, label)


# 场景 I：-2 阶段回响不触发（不对齐时）。
# 说明：NPC 加骰方向 + 玩家 distrust → 交叉不对齐 → 不触发回响。
static func _test_i_neg2_echo_not_triggered_without_alignment(checks: Array, failed: Array) -> void:
	var label := "I: -2 echo not triggered without alignment"
	var engine := _build_relationship_engine(-2)

	var before := engine._affinity_map.get_score("npc_mentor", "player")

	# NPC trust(add) + 玩家 distrust → 不对齐
	var check_result := {
		"relationship_details": [
			{
				"npc_id": "npc_mentor",
				"detail": {
					"npc_tier": "trust",
					"player_tier": "distrust",
					"direction": "add",
					"aligned": false,
					"bias": 0,
					"rolls": [{"die": 3, "hit_value": 5, "success": true}]
				}
			}
		]
	}

	engine._try_relationship_echo(check_result)
	var after := engine._affinity_map.get_score("npc_mentor", "player")
	if after != before:
		_fail(checks, failed, label, "expected no change, but npc_mentor->player=%d → %d" % [before, after])
		return

	_pass(checks, label)


# 场景 J：端到端 CSV 集成验证。
# 说明：从 CSV 加载配置，选择 opt_market_bargain（含 relationshipNpcs），
#       验证关系修正详情出现在 check_result 中，affinityDeltas 执行后分值变化。
static func _test_j_end_to_end_csv_integration(checks: Array, failed: Array) -> void:
	var label := "J: end-to-end CSV integration with relationshipNpcs"
	var engine := _build_relationship_engine(0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	# 记录关系初始值
	var before_p2m := engine._affinity_map.get_score("player", "npc_mentor")
	var before_m2p := engine._affinity_map.get_score("npc_mentor", "player")
	var before_r2p := engine._affinity_map.get_score("npc_rival", "player")

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	# 验证 affinityDeltas 已执行（default resolution 配置了 player->npc_mentor:+10, npc_mentor->player:+5）
	var after_p2m := engine._affinity_map.get_score("player", "npc_mentor")
	var after_m2p := engine._affinity_map.get_score("npc_mentor", "player")

	# 注意：若进入 desperate_gamble 或 preemptive_bet phase，resolution 尚未执行
	var phase := str(result.get("phase", ""))
	if phase == "confirm" or phase == "resolved":
		# resolution 已执行，验证 affinityDeltas
		if after_p2m != before_p2m + 10:
			_fail(checks, failed, label, "affinityDelta player->npc_mentor: expected %d, got %d" % [before_p2m + 10, after_p2m])
			return
		if after_m2p != before_m2p + 5:
			_fail(checks, failed, label, "affinityDelta npc_mentor->player: expected %d, got %d" % [before_m2p + 5, after_m2p])
			return
		print("  [INFO] J: affinityDeltas verified: player->npc_mentor=%d(+10), npc_mentor->player=%d(+5)" % [after_p2m, after_m2p])
	else:
		# 挂起在风险入口阶段，affinityDeltas 尚未执行，只验证关系系统已初始化
		print("  [INFO] J: pending at phase=%s, affinityDeltas deferred — verifying init only" % phase)
		if before_p2m != 20 or before_m2p != 15:
			_fail(checks, failed, label, "init values unexpected: p2m=%d, m2p=%d" % [before_p2m, before_m2p])
			return

	_pass(checks, label)


# ---- 辅助方法 ----

# 功能：构建带关系数据的测试引擎。
# 注意：断言引用旧配置事件 ID（evt_market_001），必须使用 world_event_mvp 配置。
#       详见 smoke_config.gd 例外说明。
static func _build_relationship_engine(xinxing_value: int) -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260324)
	engine.load_from_csv_dir(SmokeConfig.DEFAULT_CSV_DIR)
	if engine.player_role_state != null:
		engine.player_role_state.set_xinxing(xinxing_value)
	else:
		var player_a: Dictionary = engine.world_state.get("player", {})
		player_a["xinxing"] = xinxing_value
		engine.world_state["player"] = player_a

	if engine.player_role_state != null:
		engine.player_role_state.set_resource("energy", 10)
	else:
		var player_b: Dictionary = engine.world_state.get("player", {})
		player_b["energy"] = 10
		engine.world_state["player"] = player_b

	if engine.player_role_state != null:
		engine._sync_role_to_world_state()

	engine.world_state["currentLocationId"] = "market"
	engine.world_state["forcedNextEventId"] = "evt_market_001"
	return engine


# 功能：推进当前挂起回合，直到离开展示阶段。
# 说明：测试脚本在选择选项前先消费 presentation，避免因 phase=presentation 导致断言偏差。
static func _ensure_ready_for_option_choice(engine: WorldEventEngine, checks: Array, failed: Array, label: String) -> bool:
	for _i in 16:
		var phase := str(engine._pending_turn_context.get("phase", "confirm"))
		if phase != "presentation":
			return true
		var step := engine.confirm_pending_turn()
		if not step.get("ok", false):
			_fail(checks, failed, label, "presentation advance failed: %s" % str(step.get("error", "")))
			return false
	_fail(checks, failed, label, "presentation did not finish within expected steps")
	return false


static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)


static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s -> %s" % [label, reason])
