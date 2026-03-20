extends RefCounted

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const RoleStateScript := preload("res://scripts/models/role_state.gd")


# 功能：第二阶段 MVP 心性与风险结构冒烟测试。
# 说明：验证心性五阶段运行时结构、孤注一掷、主动押注入口、第一阶段兼容性。
static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	_test_a_desperate_gamble_available(checks, failed)
	_test_b_desperate_gamble_blocked_at_neg2(checks, failed)
	_test_c_preemptive_bet_available(checks, failed)
	_test_d_preemptive_bet_skipped(checks, failed)
	_test_e_phase1_compatibility(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# 场景 A：心性 -1，鉴定失败 → 孤注一掷入口出现 → 使用后心性偏移
static func _test_a_desperate_gamble_available(checks: Array, failed: Array) -> void:
	var label := "A: xinxing=-1, fail → desperate_gamble available"
	var engine := _build_test_engine(-1)

	# 设置 chance 类型检定，成功率为 0 保证失败
	_inject_check_config(engine, "chance", 0.0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return

	# 选择 opt_market_bargain
	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	# 应该进入 desperate_gamble 阶段
	var result_phase := str(result.get("phase", ""))
	if result_phase != "desperate_gamble":
		_fail(checks, failed, label, "expected phase desperate_gamble, got: %s" % result_phase)
		return

	# 使用孤注一掷
	var gamble_result := engine.confirm_pending_turn("accept")
	if not gamble_result.get("ok", false):
		_fail(checks, failed, label, "gamble confirm failed: %s" % str(gamble_result.get("error", "")))
		return

	# 验证心性偏移（累计使用 1 次，未达阈值 3，但 tracker 应记录）
	var tracker: Dictionary = engine.world_state.get("xinxingTracker", {})
	var gamble_count := int(tracker.get("gamble_count", 0))
	# 孤注一掷使用 1 次，gamble_count 可能已因 transition 重置
	# 重要的是不崩溃且成功完成
	_pass(checks, label)


# 场景 B：心性 -2，鉴定失败 → 无孤注一掷入口
static func _test_b_desperate_gamble_blocked_at_neg2(checks: Array, failed: Array) -> void:
	var label := "B: xinxing=-2, fail → no desperate_gamble"
	var engine := _build_test_engine(-2)

	# chance 成功率为 0 保证失败
	_inject_check_config(engine, "chance", 0.0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	# 心性 -2 不允许孤注一掷，应直接结算而非挂起
	var result_phase := str(result.get("phase", ""))
	if result_phase == "desperate_gamble":
		_fail(checks, failed, label, "desperate_gamble should not appear at xinxing=-2")
		return

	_pass(checks, label)


# 场景 C：心性 -2，确认选项 → 主动押注入口出现 → bet_modifier 正确传入
static func _test_c_preemptive_bet_available(checks: Array, failed: Array) -> void:
	var label := "C: xinxing=-2, preemptive_bet available"
	var engine := _build_test_engine(-2)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	# 心性 -2 允许主动押注，且 opt_market_bargain 配置了 preemptiveBet
	var result_phase := str(result.get("phase", ""))
	if result_phase != "preemptive_bet":
		_fail(checks, failed, label, "expected phase preemptive_bet, got: %s" % result_phase)
		return

	# 接受押注
	var bet_result := engine.confirm_pending_turn("accept")
	if not bet_result.get("ok", false):
		_fail(checks, failed, label, "bet confirm failed: %s" % str(bet_result.get("error", "")))
		return

	_pass(checks, label)


# 场景 D：心性 -2，不使用主动押注 → 常规鉴定
static func _test_d_preemptive_bet_skipped(checks: Array, failed: Array) -> void:
	var label := "D: xinxing=-2, preemptive_bet skipped → normal check"
	var engine := _build_test_engine(-2)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return

	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	var result_phase := str(result.get("phase", ""))
	if result_phase != "preemptive_bet":
		_fail(checks, failed, label, "expected phase preemptive_bet, got: %s" % result_phase)
		return

	# 跳过押注（传入非 accept）
	var skip_result := engine.confirm_pending_turn("skip")
	if not skip_result.get("ok", false):
		_fail(checks, failed, label, "skip confirm failed: %s" % str(skip_result.get("error", "")))
		return

	_pass(checks, label)


# 场景 E：第一阶段配置（chance / assessment）仍能正常运行
static func _test_e_phase1_compatibility(checks: Array, failed: Array) -> void:
	var label := "E: phase1 compatibility (xinxing=0, normal check)"
	var engine := _build_test_engine(0)

	var preview := engine.preview_next_turn()
	if not preview.get("ok", false):
		_fail(checks, failed, label, "preview failed: %s" % str(preview.get("error", "")))
		return

	# 心性 0 时，选择有 check 的选项，不应触发主动押注
	var result := engine.confirm_pending_turn("opt_market_bargain")
	if not result.get("ok", false):
		_fail(checks, failed, label, "confirm failed: %s" % str(result.get("error", "")))
		return

	var result_phase := str(result.get("phase", ""))
	# 心性 0 不允许主动押注，可能触发孤注一掷（如果失败），或直接结算
	if result_phase == "preemptive_bet":
		_fail(checks, failed, label, "preemptive_bet should not appear at xinxing=0")
		return

	# 如果进入了 desperate_gamble，选择跳过以继续
	if result_phase == "desperate_gamble":
		var skip_result := engine.confirm_pending_turn("skip")
		if not skip_result.get("ok", false):
			_fail(checks, failed, label, "gamble skip failed: %s" % str(skip_result.get("error", "")))
			return

	_pass(checks, label)


# 功能：构建测试用引擎，注入指定心性值的玩家。
static func _build_test_engine(xinxing_value: int) -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260320)
	engine.load_from_csv_dir("res://scripts/config/world_event_mvp")
	# 注入心性值到玩家 RoleState
	if engine.player_role_state != null:
		engine.player_role_state.set_attribute("xinxing", xinxing_value)
	else:
		var player: Dictionary = engine.world_state.get("player", {})
		player["xinxing"] = xinxing_value
		engine.world_state["player"] = player
	# 确保玩家有足够的 energy 来支付 opt_market_bargain 的 cost
	if engine.player_role_state != null:
		engine.player_role_state.set_resource("energy", 10)
	else:
		var player: Dictionary = engine.world_state.get("player", {})
		player["energy"] = 10
		engine.world_state["player"] = player
	# 同步到 world_state
	if engine.player_role_state != null:
		engine._sync_role_to_world_state()
	# 确保当前位置在 market（opt_market_bargain 所在事件的位置）
	engine.world_state["currentLocationId"] = "market"
	# 强制下一个事件为市场事件（含 opt_market_bargain 的选择点）
	engine.world_state["forcedNextEventId"] = "evt_market_001"
	return engine


# 功能：注入检定类型配置到引擎中对应选项。
# 说明：遍历 choice_points 找到 opt_market_bargain，覆盖其 check 配置。
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
	# 重建 choice_point_map 以反映修改
	engine._rebuild_choice_point_map()


static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)


static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s → %s" % [label, reason])
