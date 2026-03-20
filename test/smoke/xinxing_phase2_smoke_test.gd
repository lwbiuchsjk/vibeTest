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
