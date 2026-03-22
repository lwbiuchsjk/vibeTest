extends RefCounted

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const RuleEngine := preload("res://scripts/systems/rule_engine.gd")


# 功能：固定随机序列，便于在 smoke 中复现概率结果。
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

	# 功能：支持骰池 d10 掷骰的确定性模拟。
	# 说明：从 _values 依次取整数作为骰面值，范围裁剪到 [from, to]。
	func randi_range(from: int, to: int) -> int:
		if _values.is_empty():
			return from
		var idx := mini(_index, _values.size() - 1)
		var value := int(_values[idx])
		_index += 1
		return clampi(value, from, to)


# 功能：第二阶段 MVP 心性与风险结构冒烟测试集合。
# 说明：覆盖风险入口、概率结构、critical 分支和阶段约束。
static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	_test_a_desperate_gamble_available(checks, failed)
	_test_b_desperate_gamble_blocked_at_neg2(checks, failed)
	_test_c_preemptive_bet_available(checks, failed)
	_test_d_preemptive_bet_skipped(checks, failed)
	_test_e_phase1_compatibility(checks, failed)
	_test_f_probability_result_type_and_constraints(checks, failed)
	_test_g_bias_and_stability_bias_consumption(checks, failed)
	_test_h_critical_fail_resolution_end_to_end(checks, failed)
	_test_i_neg1_to_neg2_on_desperate_critical_fail(checks, failed)
	_test_j_dice_pool_assessment(checks, failed)
	_test_k_dice_pool_xinxing_constraints(checks, failed)
	_test_l_dice_pool_bonus_dice(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# 场景 A：心性 -1，检定失败后应出现孤注一掷入口。
static func _test_a_desperate_gamble_available(checks: Array, failed: Array) -> void:
	var label := "A: xinxing=-1, fail -> desperate_gamble available"
	var engine := _build_test_engine(-1)
	_inject_check_config(engine, "chance", 0.0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	if str(result.get("phase", "")) != "desperate_gamble":
		_fail(checks, failed, label, "expected phase desperate_gamble, got: %s" % str(result.get("phase", "")))
		return

	var gamble_result := engine.confirm_pending_turn("accept")
	if not gamble_result.get("ok", false):
		_fail(checks, failed, label, "gamble confirm failed: %s" % str(gamble_result.get("error", "")))
		return

	_pass(checks, label)


# 场景 B：心性 -2，检定失败后不应出现孤注一掷入口。
static func _test_b_desperate_gamble_blocked_at_neg2(checks: Array, failed: Array) -> void:
	var label := "B: xinxing=-2, fail -> no desperate_gamble"
	var engine := _build_test_engine(-2)
	_inject_check_config(engine, "chance", 0.0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	if str(result.get("phase", "")) == "desperate_gamble":
		_fail(checks, failed, label, "desperate_gamble should not appear at xinxing=-2")
		return

	_pass(checks, label)


# 场景 C：心性 -2 时应出现主动押注入口。
static func _test_c_preemptive_bet_available(checks: Array, failed: Array) -> void:
	var label := "C: xinxing=-2, preemptive_bet available"
	var engine := _build_test_engine(-2)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	if str(result.get("phase", "")) != "preemptive_bet":
		_fail(checks, failed, label, "expected phase preemptive_bet, got: %s" % str(result.get("phase", "")))
		return

	var bet_result := engine.confirm_pending_turn("accept")
	if not bet_result.get("ok", false):
		_fail(checks, failed, label, "bet confirm failed: %s" % str(bet_result.get("error", "")))
		return

	_pass(checks, label)


# 场景 D：心性 -2 跳过主动押注，应继续常规检定。
static func _test_d_preemptive_bet_skipped(checks: Array, failed: Array) -> void:
	var label := "D: xinxing=-2, preemptive_bet skipped -> normal check"
	var engine := _build_test_engine(-2)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	if str(result.get("phase", "")) != "preemptive_bet":
		_fail(checks, failed, label, "expected phase preemptive_bet, got: %s" % str(result.get("phase", "")))
		return

	var skip_result := engine.confirm_pending_turn("skip")
	if not skip_result.get("ok", false):
		_fail(checks, failed, label, "skip confirm failed: %s" % str(skip_result.get("error", "")))
		return

	_pass(checks, label)


# 场景 E：第一阶段配置（chance/assessment）兼容。
static func _test_e_phase1_compatibility(checks: Array, failed: Array) -> void:
	var label := "E: phase1 compatibility (xinxing=0, normal check)"
	var engine := _build_test_engine(0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	if str(result.get("phase", "")) == "preemptive_bet":
		_fail(checks, failed, label, "preemptive_bet should not appear at xinxing=0")
		return

	if str(result.get("phase", "")) == "desperate_gamble":
		var skip_result := engine.confirm_pending_turn("skip")
		if not skip_result.get("ok", false):
			_fail(checks, failed, label, "gamble skip failed: %s" % str(skip_result.get("error", "")))
			return

	_pass(checks, label)


# 场景 F：resolve_check 返回四结果，并按心性阶段约束 critical。
static func _test_f_probability_result_type_and_constraints(checks: Array, failed: Array) -> void:
	var label := "F: resolve_check result_type + xinxing constraints"

	var cf_blocked := RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.0},
		{},
		[],
		MockRng.new([0.99]),
		{"xinxing": 1}
	)
	if str(cf_blocked.get("result_type", "")) == "critical_fail":
		_fail(checks, failed, label, "critical_fail should be blocked at xinxing=1")
		return

	var cs_blocked := RuleEngine.resolve_check(
		{"type": "chance", "successRate": 1.0},
		{},
		[],
		MockRng.new([0.0]),
		{"xinxing": 0}
	)
	if str(cs_blocked.get("result_type", "")) != "success":
		_fail(checks, failed, label, "critical_success should remap to success at xinxing=0")
		return

	var cf_forced := RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.0},
		{},
		[],
		MockRng.new([0.2]),
		{"xinxing": -2}
	)
	if str(cf_forced.get("result_type", "")) != "critical_fail":
		_fail(checks, failed, label, "fail should remap to critical_fail at xinxing=-2")
		return

	_pass(checks, label)


# 场景 G：验证 successBias/criticalBias/stability_bias 被实际消费。
static func _test_g_bias_and_stability_bias_consumption(checks: Array, failed: Array) -> void:
	var label := "G: bias and stability_bias are consumed"

	var baseline := RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.5},
		{},
		[],
		MockRng.new([0.55]),
		{"xinxing": 1}
	)
	var with_success_bias := RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.5},
		{},
		[],
		MockRng.new([0.55]),
		{"xinxing": 1, "successBias": 20}
	)
	if bool(baseline.get("pass", false)) or not bool(with_success_bias.get("pass", false)):
		_fail(checks, failed, label, "successBias should change the pass boundary")
		return

	var p_no_stable: Dictionary = RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.5},
		{},
		[],
		MockRng.new([0.4]),
		{"xinxing": 2, "stability_bias": 0}
	).get("probabilities", {})
	var p_with_stable: Dictionary = RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.5},
		{},
		[],
		MockRng.new([0.4]),
		{"xinxing": 2, "stability_bias": 1}
	).get("probabilities", {})
	if float(p_with_stable.get("success", 0.0)) <= float(p_no_stable.get("success", 0.0)):
		_fail(checks, failed, label, "stability_bias should positively adjust success probability")
		return

	var p_cs_base: Dictionary = RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.8},
		{},
		[],
		MockRng.new([0.1]),
		{"xinxing": 1}
	).get("probabilities", {})
	var p_cs_down: Dictionary = RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.8},
		{},
		[],
		MockRng.new([0.1]),
		{"xinxing": 1, "criticalSuccessBias": -20}
	).get("probabilities", {})
	if float(p_cs_down.get("critical_success", 0.0)) >= float(p_cs_base.get("critical_success", 0.0)):
		_fail(checks, failed, label, "criticalSuccessBias should reduce critical_success probability when negative")
		return

	var p_cf_base: Dictionary = RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.2},
		{},
		[],
		MockRng.new([0.9]),
		{"xinxing": -1}
	).get("probabilities", {})
	var p_cf_up: Dictionary = RuleEngine.resolve_check(
		{"type": "chance", "successRate": 0.2},
		{},
		[],
		MockRng.new([0.9]),
		{"xinxing": -1, "criticalFailBias": 20}
	).get("probabilities", {})
	if float(p_cf_up.get("critical_fail", 0.0)) <= float(p_cf_base.get("critical_fail", 0.0)):
		_fail(checks, failed, label, "criticalFailBias should increase critical_fail probability when positive")
		return

	_pass(checks, label)


# 场景 H：critical_fail 分支端到端生效（命中 onCriticalFailResolution）。
static func _test_h_critical_fail_resolution_end_to_end(checks: Array, failed: Array) -> void:
	var label := "H: critical_fail resolution branch end-to-end"
	var engine := _build_test_engine(-2)
	_inject_check_config(engine, "chance", 0.0)

	var baseline_morale := int(engine.world_state.get("params", {}).get("morale", 0))
	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var phase_result := engine.confirm_pending_turn("opt_market_bargain")
	if not phase_result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(phase_result.get("error", "")))
		return
	if str(phase_result.get("phase", "")) != "preemptive_bet":
		_fail(checks, failed, label, "expected preemptive_bet phase at xinxing=-2")
		return

	var settled := engine.confirm_pending_turn("skip")
	if not settled.get("ok", false):
		_fail(checks, failed, label, "settle failed: %s" % str(settled.get("error", "")))
		return

	var after_morale := int(engine.world_state.get("params", {}).get("morale", 0))
	if after_morale != baseline_morale - 5:
		_fail(checks, failed, label, "expected critical_fail morale delta -5, got %d" % (after_morale - baseline_morale))
		return

	_pass(checks, label)


# 场景 I：-1 阶段孤注一掷重判 critical_fail 时应跌入 -2。
static func _test_i_neg1_to_neg2_on_desperate_critical_fail(checks: Array, failed: Array) -> void:
	var label := "I: desperate critical_fail triggers -1 -> -2"
	var engine := _build_test_engine(-1)
	_inject_check_config(engine, "chance", 0.0)

	# 说明：查找一个随机种子，确保前两次 randf 都落在 critical_fail 区间。
	var forced_seed := _find_seed_for_min_roll(0.75, 2)
	if forced_seed == 0:
		_fail(checks, failed, label, "unable to find deterministic seed for critical_fail")
		return
	engine._rng.seed = forced_seed

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return
	if not _ensure_ready_for_option_choice(engine, checks, failed, label):
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return
	if str(result.get("phase", "")) != "desperate_gamble":
		_fail(checks, failed, label, "expected desperate_gamble phase")
		return

	var gamble_result := engine.confirm_pending_turn("accept")
	if not gamble_result.get("ok", false):
		_fail(checks, failed, label, "gamble confirm failed: %s" % str(gamble_result.get("error", "")))
		return

	if engine._get_current_xinxing() != -2:
		_fail(checks, failed, label, "expected xinxing=-2 after critical_fail recheck")
		return

	_pass(checks, label)


# 场景 J：骰池 assessment 基本判定流程验证。
# 说明：用确定性骰面验证 success / fail / critical_success / critical_fail 四档。
#       physique=12 + thresholds=[0,3,7,12] → stage=3，加上 agility=8 → stage=2 → score=5 → pool=5。
static func _test_j_dice_pool_assessment(checks: Array, failed: Array) -> void:
	var label := "J: dice pool assessment basic result types"
	var check_cfg := {
		"type": "assessment", "hitThreshold": 6, "requiredHits": 2,
		"items": [
			{"key": "physique", "direction": "positive"},
			{"key": "agility", "direction": "positive"}
		]
	}
	var role := {"physique": 12, "agility": 8}
	var thresholds := [0, 3, 7, 12]
	# physique=12 → stage=3, agility=8 → stage=2 → score=5 → pool_size=5

	# 5 颗骰子 [8, 6, 3, 2, 4]，阈值 ≥6，需要 2 命中 → 命中 2 个(8,6) → success（无 10）
	var r_success := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([8, 6, 3, 2, 4]), {"xinxing": 1}
	)
	if str(r_success.get("result_type", "")) != "success":
		_fail(checks, failed, label, "expected success, got: %s" % str(r_success.get("result_type", "")))
		return
	if int(r_success.get("pool_size", 0)) != 5:
		_fail(checks, failed, label, "expected pool_size=5, got: %d" % int(r_success.get("pool_size", 0)))
		return

	# 5 颗骰子 [10, 7, 2, 3, 4]，阈值 ≥6，需要 2 命中 → 命中 2 个(10,7) + 有 10 → critical_success
	var r_cs := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([10, 7, 2, 3, 4]), {"xinxing": 1}
	)
	if str(r_cs.get("result_type", "")) != "critical_success":
		_fail(checks, failed, label, "expected critical_success, got: %s" % str(r_cs.get("result_type", "")))
		return

	# 5 颗骰子 [2, 3, 4, 5, 2]，阈值 ≥6，需要 2 命中 → 命中 0 个 + 无 1 → fail
	var r_fail := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([2, 3, 4, 5, 2]), {"xinxing": -1}
	)
	if str(r_fail.get("result_type", "")) != "fail":
		_fail(checks, failed, label, "expected fail, got: %s" % str(r_fail.get("result_type", "")))
		return

	# 5 颗骰子 [1, 3, 4, 2, 5]，阈值 ≥6，需要 2 命中 → 命中 0 个 + 有 1 → critical_fail
	var r_cf := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([1, 3, 4, 2, 5]), {"xinxing": -1}
	)
	if str(r_cf.get("result_type", "")) != "critical_fail":
		_fail(checks, failed, label, "expected critical_fail, got: %s" % str(r_cf.get("result_type", "")))
		return

	_pass(checks, label)


# 场景 K：骰池 assessment 心性约束验证。
# 说明：xinxing=0 时大成功降级为 success，大失败降级为 fail；xinxing=-2 时 fail 升级为 critical_fail。
static func _test_k_dice_pool_xinxing_constraints(checks: Array, failed: Array) -> void:
	var label := "K: dice pool xinxing constraints"
	var check_cfg := {
		"type": "assessment", "hitThreshold": 6, "requiredHits": 2,
		"items": [
			{"key": "physique", "direction": "positive"},
			{"key": "agility", "direction": "positive"}
		]
	}
	var role := {"physique": 12, "agility": 8}
	var thresholds := [0, 3, 7, 12]
	# score=5 → pool_size=5

	# xinxing=0：骰面 [10, 7, 2, 3, 4]，本应 critical_success → 降级为 success
	var r_cs_blocked := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([10, 7, 2, 3, 4]), {"xinxing": 0}
	)
	if str(r_cs_blocked.get("result_type", "")) != "success":
		_fail(checks, failed, label, "critical_success should remap to success at xinxing=0, got: %s" % str(r_cs_blocked.get("result_type", "")))
		return

	# xinxing=0：骰面 [1, 3, 4, 2, 5]，本应 critical_fail → 降级为 fail
	var r_cf_blocked := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([1, 3, 4, 2, 5]), {"xinxing": 0}
	)
	if str(r_cf_blocked.get("result_type", "")) != "fail":
		_fail(checks, failed, label, "critical_fail should remap to fail at xinxing=0, got: %s" % str(r_cf_blocked.get("result_type", "")))
		return

	# xinxing=-2：骰面 [2, 3, 4, 5, 2]，本应 fail → 升级为 critical_fail
	var r_fail_forced := RuleEngine.resolve_check(
		check_cfg, role, thresholds,
		MockRng.new([2, 3, 4, 5, 2]), {"xinxing": -2}
	)
	if str(r_fail_forced.get("result_type", "")) != "critical_fail":
		_fail(checks, failed, label, "fail should remap to critical_fail at xinxing=-2, got: %s" % str(r_fail_forced.get("result_type", "")))
		return

	_pass(checks, label)


# 场景 L：骰池偏置（加减骰子）验证。
# 说明：successBias=1 应额外加 1 颗骰子，增大通过概率。
static func _test_l_dice_pool_bonus_dice(checks: Array, failed: Array) -> void:
	var label := "L: dice pool bonus dice from successBias"

	# 基础 score=0（items 为空），无偏置 → pool_size=1（最小值保护）
	var r_base := RuleEngine.resolve_check(
		{"type": "assessment", "hitThreshold": 6, "requiredHits": 1, "items": []},
		{},
		[0, 3, 7, 12],
		MockRng.new([8]),
		{"xinxing": 1}
	)
	if int(r_base.get("pool_size", 0)) != 1:
		_fail(checks, failed, label, "base pool_size should be 1, got: %d" % int(r_base.get("pool_size", 0)))
		return

	# successBias=2 → pool_size = max(1, 0+2) = 2
	var r_biased := RuleEngine.resolve_check(
		{"type": "assessment", "hitThreshold": 6, "requiredHits": 1, "items": []},
		{},
		[0, 3, 7, 12],
		MockRng.new([8, 8]),
		{"xinxing": 1, "successBias": 2}
	)
	if int(r_biased.get("pool_size", 0)) != 2:
		_fail(checks, failed, label, "biased pool_size should be 2, got: %d" % int(r_biased.get("pool_size", 0)))
		return

	# stability_bias=1 也应加骰：pool_size = max(1, 0+0+1) = 1
	var r_stable := RuleEngine.resolve_check(
		{"type": "assessment", "hitThreshold": 6, "requiredHits": 1, "items": []},
		{},
		[0, 3, 7, 12],
		MockRng.new([8]),
		{"xinxing": 2, "stability_bias": 1}
	)
	if int(r_stable.get("pool_size", 0)) != 1:
		_fail(checks, failed, label, "stability pool_size should be 1, got: %d" % int(r_stable.get("pool_size", 0)))
		return

	_pass(checks, label)


# 功能：推进当前挂起回合，直到离开展示阶段。
# 说明：测试脚本在选择选项前先消费 presentation，避免因 phase= presentation 导致断言偏差。
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


# 功能：构建测试引擎并注入心性值。
static func _build_test_engine(xinxing_value: int) -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260320)
	engine.load_from_csv_dir("res://scripts/config/world_event_mvp")
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


# 功能：向 opt_market_bargain 注入 check 配置。
static func _inject_check_config(engine: WorldEventEngine, check_type: String, success_rate: float = 1.0) -> void:
	for cp_variant in engine.choice_points:
		var cp: Dictionary = cp_variant
		var options: Array = cp.get("options", [])
		for idx in options.size():
			var option: Dictionary = options[idx]
			if str(option.get("id", "")) == "opt_market_bargain":
				var check: Dictionary = option.get("check", {})
				check["type"] = check_type
				check["successRate"] = success_rate
				option["check"] = check
				options[idx] = option
		cp["options"] = options
	engine._rebuild_choice_point_map()


# 功能：查找满足最小随机阈值的种子。
# 说明：用于构造可复现的 critical_fail 场景，避免测试偶发波动。
static func _find_seed_for_min_roll(min_roll: float, count: int, max_seed: int = 200000) -> int:
	for seed in max_seed:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + 1
		var ok := true
		for i in count:
			if rng.randf() < min_roll:
				ok = false
				break
		if ok:
			return seed + 1
	return 0


static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)


static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s -> %s" % [label, reason])
