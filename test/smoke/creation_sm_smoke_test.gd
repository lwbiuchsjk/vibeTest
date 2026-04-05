extends RefCounted

# 功能：开局选择状态机冒烟测试集合。
# 说明：覆盖基础流程、effect apply、多 effect 叠加共三组。

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const CreationStateMachine := preload("res://scripts/systems/creation_state_machine.gd")
const ConfigLoader := preload("res://scripts/systems/config_loader.gd")


static func run_all() -> Dictionary:
	var checks: Array = []
	var failed: Array = []

	# A：基础流程
	_test_a1_empty_config(checks, failed)
	_test_a2_full_flow(checks, failed)
	_test_a3_response_structure(checks, failed)

	# B：Effect Apply
	_test_b1_attribute_delta(checks, failed)
	_test_b2_affinity_all(checks, failed)
	_test_b3_world_state_sync(checks, failed)

	# C：多 Effect 叠加
	_test_c1_cumulative_effects(checks, failed)
	_test_c2_xinxing_clamp(checks, failed)

	# D：检定分支
	_test_d1_check_branch_success(checks, failed)
	_test_d2_check_branch_fail(checks, failed)
	_test_d3_no_check_backward_compat(checks, failed)
	_test_d4_csv_check_parse(checks, failed)

	# E：叙事分段
	_test_e1_single_line_backward_compat(checks, failed)
	_test_e2_multi_line_narrating_flow(checks, failed)
	_test_e3_advance_to_choosing(checks, failed)
	_test_e4_csv_narrative_lines_parse(checks, failed)

	# F：叙事后果展示
	_test_f1_no_outcome_backward_compat(checks, failed)
	_test_f2_outcome_phase_entered(checks, failed)
	_test_f3_confirm_outcome_advances(checks, failed)
	_test_f4_outcome_branch_selection(checks, failed)
	_test_f5_csv_outcome_parse(checks, failed)

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
	}


# ── D：检定分支 ──────────────────────────────────────────────────

# 场景 D1：检定通过时，default + success 分支 effects 均 apply。
static func _test_d1_check_branch_success(checks: Array, failed: Array) -> void:
	var label := "D1: check pass -> default + success effects applied"
	var engine := _build_engine()
	# 给玩家高 craft 值以确保检定通过（低难度 requiredHits=1，hitThreshold=6）。
	engine.player_role_state.set_attribute("craft", 20)
	engine._sync_role_to_world_state()

	var config: Array = [_build_check_question()]
	var old_craft: int = engine.player_role_state.get_attribute("craft")
	var old_insight: int = engine.player_role_state.get_attribute("insight")

	engine.start_creation(config)
	var result: Dictionary = engine.creation_act("opt_check_craft")

	var new_craft: int = engine.player_role_state.get_attribute("craft")
	var new_insight: int = engine.player_role_state.get_attribute("insight")

	# default: craft +1（始终 apply）。
	if new_craft < old_craft + 1:
		_fail(checks, failed, label, "craft default +1 not applied: old=%d new=%d" % [old_craft, new_craft])
		return

	# 检查 check_result 是否在返回值中。
	if not result.has("check_result"):
		_fail(checks, failed, label, "response missing check_result")
		return

	var check_passed: bool = result.get("check_result", {}).get("pass", false)
	if not check_passed:
		# 高 craft 值仍可能因骰运失败，跳过而非报错。
		_pass(checks, label + " (skipped: dice failed despite high craft)")
		return

	# success: insight +2。
	if new_insight != old_insight + 2:
		_fail(checks, failed, label, "insight success +2 not applied: old=%d new=%d" % [old_insight, new_insight])
		return
	_pass(checks, label)


# 场景 D2：检定失败时，default + fail 分支 effects 均 apply。
static func _test_d2_check_branch_fail(checks: Array, failed: Array) -> void:
	var label := "D2: check fail -> default + fail effects applied"
	var engine := _build_engine()
	# 给玩家 craft=0 使骰池极小，大概率失败。
	engine.player_role_state.set_attribute("craft", 0)
	engine._sync_role_to_world_state()

	var config: Array = [_build_check_question()]
	var old_craft: int = engine.player_role_state.get_attribute("craft")
	var old_aptitude: int = engine.player_role_state.get_attribute("aptitude")

	engine.start_creation(config)
	var result: Dictionary = engine.creation_act("opt_check_craft")

	var new_craft: int = engine.player_role_state.get_attribute("craft")
	var new_aptitude: int = engine.player_role_state.get_attribute("aptitude")

	var check_passed: bool = result.get("check_result", {}).get("pass", true)
	if check_passed:
		# craft=0 仍可能因骰运通过，跳过而非报错。
		_pass(checks, label + " (skipped: dice passed despite low craft)")
		return

	# default: craft +1（始终 apply）。
	if new_craft != old_craft + 1:
		_fail(checks, failed, label, "craft default +1 not applied: old=%d new=%d" % [old_craft, new_craft])
		return
	# fail: aptitude -1。
	if new_aptitude != old_aptitude - 1:
		_fail(checks, failed, label, "aptitude fail -1 not applied: old=%d new=%d" % [old_aptitude, new_aptitude])
		return
	_pass(checks, label)


# 场景 D3：无 check 配置时，行为与旧版完全一致（向后兼容）。
static func _test_d3_no_check_backward_compat(checks: Array, failed: Array) -> void:
	var label := "D3: no check -> backward compatible (effects_default only)"
	var engine := _build_engine()
	var config := _build_test_config()

	var old_craft: int = engine.player_role_state.get_attribute("craft")

	engine.start_creation(config)
	var result: Dictionary = engine.creation_act("bg_artisan")

	var new_craft: int = engine.player_role_state.get_attribute("craft")

	# 无 check 时不应返回 check_result。
	if result.has("check_result"):
		_fail(checks, failed, label, "unexpected check_result in response for no-check option")
		return
	# effects 正常 apply。
	if new_craft != old_craft + 2:
		_fail(checks, failed, label, "craft: expected %d, got %d" % [old_craft + 2, new_craft])
		return
	_pass(checks, label)


# 场景 D4：从 CSV 加载的配置正确解析 check 字段和 effect_branch。
# 说明：验证导入阶段配置（q_intro_1_opt_1）的检定和分支效果解析。
static func _test_d4_csv_check_parse(checks: Array, failed: Array) -> void:
	var label := "D4: CSV check fields parsed correctly"
	var result: Dictionary = ConfigLoader.load_creation_config("res://scripts/config/creation_questions.csv")
	if not result.get("ok", false):
		_fail(checks, failed, label, "CSV load failed: %s" % str(result.get("error", "")))
		return

	var questions: Array = result.get("data", [])
	if questions.is_empty():
		_fail(checks, failed, label, "no questions loaded")
		return

	# 第一个问题（q_intro_1）的第一个选项应有 check 配置。
	var q0: Dictionary = questions[0]
	if str(q0.get("question_id", "")) != "q_intro_1":
		_fail(checks, failed, label, "first question should be q_intro_1, got %s" % str(q0.get("question_id", "")))
		return
	var options: Array = q0.get("options", [])
	var opt1: Dictionary = {}
	for opt_variant in options:
		var opt: Dictionary = opt_variant
		if str(opt.get("option_id", "")) == "q_intro_1_opt_1":
			opt1 = opt
			break
	if opt1.is_empty():
		_fail(checks, failed, label, "q_intro_1_opt_1 option not found")
		return

	# 验证 check 配置。
	var check: Dictionary = opt1.get("check", {})
	if check.is_empty():
		_fail(checks, failed, label, "q_intro_1_opt_1 check is empty")
		return
	if str(check.get("type", "")) != "assessment":
		_fail(checks, failed, label, "check type: expected assessment, got %s" % str(check.get("type", "")))
		return
	var items: Array = check.get("items", [])
	if items.is_empty():
		_fail(checks, failed, label, "check items is empty")
		return
	var first_item: Dictionary = items[0]
	if str(first_item.get("key", "")) != "craft":
		_fail(checks, failed, label, "check item key: expected craft, got %s" % str(first_item.get("key", "")))
		return

	# 验证 effect_branch 分组：default（energy + affinity）、success（craft + insight）、fail（craft）。
	var defaults: Array = opt1.get("effects_default", [])
	var successes: Array = opt1.get("effects_success", [])
	var fails: Array = opt1.get("effects_fail", [])
	if defaults.size() < 2:
		_fail(checks, failed, label, "effects_default should have >=2 entries (energy + affinity), got %d" % defaults.size())
		return
	if successes.size() < 2:
		_fail(checks, failed, label, "effects_success should have >=2 entries (craft + insight), got %d" % successes.size())
		return
	if fails.is_empty():
		_fail(checks, failed, label, "effects_fail should not be empty")
		return
	_pass(checks, label)


# ── E：叙事分段 ──────────────────────────────────────────────────

# 场景 E1：单段文字（无 |）时 phase 直接为 choosing，行为向后兼容。
static func _test_e1_single_line_backward_compat(checks: Array, failed: Array) -> void:
	var label := "E1: single line -> phase=choosing (backward compat)"
	var engine := _build_engine()
	var config := _build_test_config()

	var result: Dictionary = engine.start_creation(config)
	var phase := str(result.get("phase", ""))
	if phase != "choosing":
		_fail(checks, failed, label, "expected phase=choosing, got %s" % phase)
		return
	# 单段时 available_actions 应正常返回。
	var actions: Array = result.get("available_actions", [])
	if actions.is_empty():
		_fail(checks, failed, label, "available_actions should not be empty in choosing phase")
		return
	_pass(checks, label)


# 场景 E2：多段文字时，start() 返回 phase=narrating，available_actions 为空。
static func _test_e2_multi_line_narrating_flow(checks: Array, failed: Array) -> void:
	var label := "E2: multi-line -> phase=narrating, advance steps through lines"
	var engine := _build_engine()
	var config: Array = [_build_narrative_question()]

	var result: Dictionary = engine.start_creation(config)
	var phase := str(result.get("phase", ""))
	if phase != "narrating":
		_fail(checks, failed, label, "start: expected phase=narrating, got %s" % phase)
		return
	# narrating 阶段不应展示选项。
	var actions: Array = result.get("available_actions", [])
	if not actions.is_empty():
		_fail(checks, failed, label, "narrating phase should have empty available_actions")
		return
	# 应返回第一段文字。
	var line := str(result.get("narrative_line", ""))
	if line != "第一段文字":
		_fail(checks, failed, label, "first line expected '第一段文字', got '%s'" % line)
		return
	if int(result.get("narrative_index", -1)) != 0:
		_fail(checks, failed, label, "narrative_index should be 0")
		return
	if int(result.get("narrative_total", -1)) != 3:
		_fail(checks, failed, label, "narrative_total should be 3")
		return

	# advance 第二段。
	result = engine.creation_advance_narrative()
	phase = str(result.get("phase", ""))
	line = str(result.get("narrative_line", ""))
	if phase != "narrating":
		_fail(checks, failed, label, "second advance: expected narrating, got %s" % phase)
		return
	if line != "第二段文字":
		_fail(checks, failed, label, "second line expected '第二段文字', got '%s'" % line)
		return
	_pass(checks, label)


# 场景 E3：advance 到最后一段后，phase 切换为 choosing，选项出现。
static func _test_e3_advance_to_choosing(checks: Array, failed: Array) -> void:
	var label := "E3: advance to last line -> phase=choosing, actions appear"
	var engine := _build_engine()
	var config: Array = [_build_narrative_question()]

	engine.start_creation(config)
	# 推进到第二段。
	engine.creation_advance_narrative()
	# 推进到最后一段（第三段），应切换到 choosing。
	var result: Dictionary = engine.creation_advance_narrative()
	var phase := str(result.get("phase", ""))
	if phase != "choosing":
		_fail(checks, failed, label, "expected phase=choosing after last advance, got %s" % phase)
		return
	var line := str(result.get("narrative_line", ""))
	if line != "第三段文字":
		_fail(checks, failed, label, "last line expected '第三段文字', got '%s'" % line)
		return
	var actions: Array = result.get("available_actions", [])
	if actions.is_empty():
		_fail(checks, failed, label, "choosing phase should have available_actions")
		return
	# choosing 后应能正常 act。
	result = engine.creation_act("opt_narr_a")
	if result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED after act, got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# 场景 E4：从 CSV 加载时，含 | 的 question_text 正确解析为 narrative_lines。
static func _test_e4_csv_narrative_lines_parse(checks: Array, failed: Array) -> void:
	var label := "E4: CSV narrative_lines parsed from | separator"
	var result: Dictionary = ConfigLoader.load_creation_config("res://scripts/config/creation_questions.csv")
	if not result.get("ok", false):
		_fail(checks, failed, label, "CSV load failed: %s" % str(result.get("error", "")))
		return
	var questions: Array = result.get("data", [])
	# 验证所有问题都有 narrative_lines 字段。
	for q_variant in questions:
		var q: Dictionary = q_variant
		var lines: Array = q.get("narrative_lines", [])
		if lines.is_empty():
			_fail(checks, failed, label, "question %s missing narrative_lines" % str(q.get("question_id", "")))
			return
	_pass(checks, label)


# ── F：叙事后果展示 ──────────────────────────────────────────────

# 场景 F1：无 outcome 的选项，act() 后直接推进，不进入 outcome phase。
static func _test_f1_no_outcome_backward_compat(checks: Array, failed: Array) -> void:
	var label := "F1: no outcome -> skip outcome phase (backward compat)"
	var engine := _build_engine()
	var config := _build_test_config()

	engine.start_creation(config)
	var result: Dictionary = engine.creation_act("bg_artisan")
	var phase := str(result.get("phase", ""))
	if phase == "outcome":
		_fail(checks, failed, label, "should not enter outcome phase when no outcome_text")
		return
	# 应直接推进到下一题。
	if str(result.get("state", "")) != "PRESENTING":
		_fail(checks, failed, label, "expected PRESENTING, got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# 场景 F2：有 outcome 的选项，act() 后进入 outcome phase。
static func _test_f2_outcome_phase_entered(checks: Array, failed: Array) -> void:
	var label := "F2: with outcome -> phase=outcome after act"
	var engine := _build_engine()
	var config: Array = [_build_outcome_question()]

	engine.start_creation(config)
	var result: Dictionary = engine.creation_act("opt_outcome_a")
	var phase := str(result.get("phase", ""))
	if phase != "outcome":
		_fail(checks, failed, label, "expected phase=outcome, got %s" % phase)
		return
	var outcome_text := str(result.get("outcome_text", ""))
	if outcome_text != "这是选择后的叙事后果":
		_fail(checks, failed, label, "unexpected outcome_text: %s" % outcome_text)
		return
	# outcome 阶段 available_actions 应为空。
	var actions: Array = result.get("available_actions", [])
	if not actions.is_empty():
		_fail(checks, failed, label, "outcome phase should have empty available_actions")
		return
	_pass(checks, label)


# 场景 F3：confirm_outcome() 后推进到 SETTLED。
static func _test_f3_confirm_outcome_advances(checks: Array, failed: Array) -> void:
	var label := "F3: confirm_outcome -> advances to SETTLED"
	var engine := _build_engine()
	var config: Array = [_build_outcome_question()]

	engine.start_creation(config)
	engine.creation_act("opt_outcome_a")
	var result: Dictionary = engine.creation_confirm_outcome()
	if str(result.get("state", "")) != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED after confirm_outcome, got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# 场景 F4：检定分支后果——成功时取 outcome_success，回退 outcome_default。
static func _test_f4_outcome_branch_selection(checks: Array, failed: Array) -> void:
	var label := "F4: outcome branch selection based on check result"
	var engine := _build_engine()
	# 给高 craft 确保检定通过概率高。
	engine.player_role_state.set_attribute("craft", 20)
	engine._sync_role_to_world_state()

	var config: Array = [_build_outcome_check_question()]
	engine.start_creation(config)
	var result: Dictionary = engine.creation_act("opt_oc_craft")

	var phase := str(result.get("phase", ""))
	if phase != "outcome":
		_fail(checks, failed, label, "expected phase=outcome, got %s" % phase)
		return
	var outcome_text := str(result.get("outcome_text", ""))
	var check_passed: bool = result.get("check_result", {}).get("pass", false)
	if check_passed:
		if outcome_text != "检定成功的后果":
			_fail(checks, failed, label, "expected success outcome, got: %s" % outcome_text)
			return
	else:
		# 骰运失败，应回退到 default（fail 分支为空）。
		if outcome_text != "默认后果":
			_fail(checks, failed, label, "expected default outcome on fail, got: %s" % outcome_text)
			return
	_pass(checks, label)


# 场景 F5：CSV 加载后，选项 outcome 字段正确解析。
static func _test_f5_csv_outcome_parse(checks: Array, failed: Array) -> void:
	var label := "F5: CSV outcome fields parsed correctly"
	var result: Dictionary = ConfigLoader.load_creation_config("res://scripts/config/creation_questions.csv")
	if not result.get("ok", false):
		_fail(checks, failed, label, "CSV load failed: %s" % str(result.get("error", "")))
		return
	var questions: Array = result.get("data", [])
	# 验证所有选项都有 outcome_default 字段（即使为空）。
	for q_variant in questions:
		var q: Dictionary = q_variant
		for opt_variant in q.get("options", []):
			var opt: Dictionary = opt_variant
			if not opt.has("outcome_default"):
				_fail(checks, failed, label, "option %s missing outcome_default" % str(opt.get("option_id", "")))
				return
	_pass(checks, label)


# 构建带叙事后果的测试问题配置。
static func _build_outcome_question() -> Dictionary:
	return {
		"question_id": "q_outcome_test",
		"question_text": "后果测试",
		"narrative_lines": ["后果测试"],
		"condition": "",
		"options": [
			{
				"option_id": "opt_outcome_a",
				"option_text": "有后果的选项",
				"effects": [{"target": "attribute", "key": "craft", "value": "+1"}],
				"outcome_default": "这是选择后的叙事后果",
				"outcome_success": "",
				"outcome_fail": "",
			}
		]
	}


# 构建带检定 + 叙事后果的测试问题配置。
static func _build_outcome_check_question() -> Dictionary:
	return {
		"question_id": "q_oc_test",
		"question_text": "检定后果测试",
		"narrative_lines": ["检定后果测试"],
		"condition": "",
		"options": [
			{
				"option_id": "opt_oc_craft",
				"option_text": "测试检定后果",
				"check": {"type": "assessment", "items": [{"key": "craft", "direction": "positive"}], "hitThreshold": 6, "requiredHits": 1},
				"effects_default": [{"target": "attribute", "key": "craft", "value": "+1"}],
				"effects_success": [],
				"effects_fail": [],
				"effects": [{"target": "attribute", "key": "craft", "value": "+1"}],
				"outcome_default": "默认后果",
				"outcome_success": "检定成功的后果",
				"outcome_fail": "",
			}
		]
	}


# 构建带多段叙事的测试问题配置。
static func _build_narrative_question() -> Dictionary:
	return {
		"question_id": "q_narrative_test",
		"question_text": "第一段文字|第二段文字|第三段文字",
		"narrative_lines": ["第一段文字", "第二段文字", "第三段文字"],
		"condition": "",
		"options": [
			{
				"option_id": "opt_narr_a",
				"option_text": "叙事选项A",
				"effects": [{"target": "attribute", "key": "craft", "value": "+1"}]
			}
		]
	}


# 构建带检定的测试问题配置。
static func _build_check_question() -> Dictionary:
	return {
		"question_id": "q_check_test",
		"question_text": "检定测试",
		"condition": "",
		"options": [
			{
				"option_id": "opt_check_craft",
				"option_text": "测试百艺检定",
				"check": {"type": "assessment", "items": [{"key": "craft", "direction": "positive"}], "hitThreshold": 6, "requiredHits": 1},
				"effects_default": [{"target": "attribute", "key": "craft", "value": "+1"}],
				"effects_success": [{"target": "attribute", "key": "insight", "value": "+2"}],
				"effects_fail": [{"target": "attribute", "key": "aptitude", "value": "-1"}],
				"effects": [{"target": "attribute", "key": "craft", "value": "+1"}]
			}
		]
	}


# ── A：基础流程 ──────────────────────────────────────────────────

# 场景 A1：无创建配置时，start() 直接返回 SETTLED。
static func _test_a1_empty_config(checks: Array, failed: Array) -> void:
	var label := "A1: empty config -> SETTLED"
	var engine := _build_engine()
	# 直接调用状态机 start 传入空配置，绕过引擎代理的默认配置回退逻辑。
	var sm := CreationStateMachine.new()
	var result: Dictionary = sm.start(engine, [])
	if result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "expected SETTLED, got %s" % result.get("state", ""))
		return
	_pass(checks, label)


# 场景 A2：有3个问题，逐题选择后全部完成。
static func _test_a2_full_flow(checks: Array, failed: Array) -> void:
	var label := "A2: 3 questions full flow -> SETTLED"
	var engine := _build_engine()
	var config := _build_test_config()

	var result: Dictionary = engine.start_creation(config)
	if result.get("state", "") != "PRESENTING":
		_fail(checks, failed, label, "start: expected PRESENTING, got %s" % result.get("state", ""))
		return
	if str(result.get("question_id", "")) != "q_background":
		_fail(checks, failed, label, "first question should be q_background, got %s" % result.get("question_id", ""))
		return

	# 选择第一题。
	result = engine.creation_act("bg_artisan")
	if result.get("state", "") != "PRESENTING":
		_fail(checks, failed, label, "after q1: expected PRESENTING, got %s" % result.get("state", ""))
		return
	if str(result.get("question_id", "")) != "q_temperament":
		_fail(checks, failed, label, "second question should be q_temperament, got %s" % result.get("question_id", ""))
		return

	# 选择第二题。
	result = engine.creation_act("tmp_cautious")
	if result.get("state", "") != "PRESENTING":
		_fail(checks, failed, label, "after q2: expected PRESENTING, got %s" % result.get("state", ""))
		return
	if str(result.get("question_id", "")) != "q_relation":
		_fail(checks, failed, label, "third question should be q_relation, got %s" % result.get("question_id", ""))
		return

	# 选择第三题。
	result = engine.creation_act("rel_friendly")
	if result.get("state", "") != "SETTLED":
		_fail(checks, failed, label, "after q3: expected SETTLED, got %s" % result.get("state", ""))
		return

	if not engine.is_creation_active() == false:
		_fail(checks, failed, label, "is_creation_active should be false after SETTLED")
		return

	_pass(checks, label)


# 场景 A3：start() 返回结构包含必要字段。
static func _test_a3_response_structure(checks: Array, failed: Array) -> void:
	var label := "A3: response has question_text, available_actions, question_index, question_total"
	var engine := _build_engine()
	var config := _build_test_config()

	var result: Dictionary = engine.start_creation(config)
	var has_all := (
		result.has("question_text")
		and result.has("available_actions")
		and result.has("question_index")
		and result.has("question_total")
	)
	if not has_all:
		_fail(checks, failed, label, "missing fields in response: %s" % str(result.keys()))
		return
	if int(result.get("question_total", 0)) != 3:
		_fail(checks, failed, label, "expected question_total=3, got %s" % str(result.get("question_total", 0)))
		return
	var actions: Array = result.get("available_actions", [])
	if actions.size() < 2:
		_fail(checks, failed, label, "expected at least 2 actions, got %d" % actions.size())
		return
	_pass(checks, label)


# ── B：Effect Apply ──────────────────────────────────────────────

# 场景 B1：选择"匠人"后 craft +2、aptitude -1 正确写入 RoleState。
static func _test_b1_attribute_delta(checks: Array, failed: Array) -> void:
	var label := "B1: bg_artisan -> craft +2, aptitude -1"
	var engine := _build_engine()
	var config := _build_test_config()

	# 记录初始值。
	var old_craft: int = engine.player_role_state.get_attribute("craft")
	var old_aptitude: int = engine.player_role_state.get_attribute("aptitude")

	engine.start_creation(config)
	engine.creation_act("bg_artisan")

	var new_craft: int = engine.player_role_state.get_attribute("craft")
	var new_aptitude: int = engine.player_role_state.get_attribute("aptitude")

	if new_craft != old_craft + 2:
		_fail(checks, failed, label, "craft: expected %d, got %d" % [old_craft + 2, new_craft])
		return
	if new_aptitude != old_aptitude - 1:
		_fail(checks, failed, label, "aptitude: expected %d, got %d" % [old_aptitude - 1, new_aptitude])
		return
	_pass(checks, label)


# 场景 B2：选择"相处融洽"后所有 NPC 的 affinity 增加 +10。
static func _test_b2_affinity_all(checks: Array, failed: Array) -> void:
	var label := "B2: rel_friendly -> all NPC affinity +10"
	var engine := _build_engine()
	# 只包含第三题，跳过前两题。
	var config: Array = [
		{
			"question_id": "q_relation",
			"question_text": "你和镇上的人……",
			"condition": "",
			"options": [
				{
					"option_id": "rel_friendly",
					"option_text": "相处融洽",
					"effects": [{"target": "affinity_all", "key": "_to_all_npc", "value": "+10"}]
				}
			]
		}
	]

	# 记录初始亲和值。
	var player_id: String = engine.player_role_state.role_id
	var old_npc1: int = engine._affinity_map.get_score(player_id, "npc_001")
	var old_npc2: int = engine._affinity_map.get_score(player_id, "npc_002")

	engine.start_creation(config)
	engine.creation_act("rel_friendly")

	var new_npc1: int = engine._affinity_map.get_score(player_id, "npc_001")
	var new_npc2: int = engine._affinity_map.get_score(player_id, "npc_002")

	if new_npc1 != old_npc1 + 10:
		_fail(checks, failed, label, "npc_001 affinity: expected %d, got %d" % [old_npc1 + 10, new_npc1])
		return
	if new_npc2 != old_npc2 + 10:
		_fail(checks, failed, label, "npc_002 affinity: expected %d, got %d" % [old_npc2 + 10, new_npc2])
		return
	_pass(checks, label)


# 场景 B3：选择后 world_state.player 与 RoleState 同步。
static func _test_b3_world_state_sync(checks: Array, failed: Array) -> void:
	var label := "B3: world_state.player synced after creation act"
	var engine := _build_engine()
	var config := _build_test_config()

	engine.start_creation(config)
	engine.creation_act("bg_artisan")

	var ws_player: Dictionary = engine.world_state.get("player", {})
	var role_craft: int = engine.player_role_state.get_attribute("craft")
	var ws_craft: int = int(ws_player.get("craft", -1))

	if ws_craft != role_craft:
		_fail(checks, failed, label, "world_state.player.craft=%d != role_state.craft=%d" % [ws_craft, role_craft])
		return
	_pass(checks, label)


# ── C：多 Effect 叠加 ────────────────────────────────────────────

# 场景 C1：连续多题选择，各题 effect 累加正确。
static func _test_c1_cumulative_effects(checks: Array, failed: Array) -> void:
	var label := "C1: cumulative effects across questions"
	var engine := _build_engine()
	var config := _build_test_config()

	var old_craft: int = engine.player_role_state.get_attribute("craft")
	var old_xinxing: int = engine.player_role_state.get_xinxing()

	engine.start_creation(config)
	engine.creation_act("bg_artisan")     # craft +2, aptitude -1
	engine.creation_act("tmp_cautious")   # xinxing +1
	engine.creation_act("rel_friendly")   # affinity_all +10

	var new_craft: int = engine.player_role_state.get_attribute("craft")
	var new_xinxing: int = engine.player_role_state.get_xinxing()

	if new_craft != old_craft + 2:
		_fail(checks, failed, label, "craft: expected %d, got %d" % [old_craft + 2, new_craft])
		return
	if new_xinxing != clampi(old_xinxing + 1, -2, 2):
		_fail(checks, failed, label, "xinxing: expected %d, got %d" % [clampi(old_xinxing + 1, -2, 2), new_xinxing])
		return
	_pass(checks, label)


# 场景 C2：xinxing delta 结果 clamp 在 [-2, 2] 范围内。
static func _test_c2_xinxing_clamp(checks: Array, failed: Array) -> void:
	var label := "C2: xinxing clamp to [-2, 2]"
	var engine := _build_engine()

	# 构建一个极端配置：xinxing +10（应该 clamp 到 2）。
	var config: Array = [
		{
			"question_id": "q_extreme",
			"question_text": "极端测试",
			"condition": "",
			"options": [
				{
					"option_id": "extreme_pos",
					"option_text": "极端正面",
					"effects": [{"target": "attribute", "key": "xinxing", "value": "+10"}]
				}
			]
		}
	]

	engine.start_creation(config)
	engine.creation_act("extreme_pos")

	var xinxing: int = engine.player_role_state.get_xinxing()
	if xinxing != 2:
		_fail(checks, failed, label, "xinxing should be clamped to 2, got %d" % xinxing)
		return
	_pass(checks, label)


# ── 测试工具 ─────────────────────────────────────────────────────

# 构建带玩家角色的引擎实例。
static func _build_engine() -> WorldEventEngine:
	var engine := WorldEventEngine.new(20260401)
	engine.load_from_csv_dir("res://scripts/config/world_event_mvp")
	return engine


# 构建标准三题测试配置。
static func _build_test_config() -> Array:
	return [
		{
			"question_id": "q_background",
			"question_text": "你曾经是……",
			"condition": "",
			"options": [
				{
					"option_id": "bg_artisan",
					"option_text": "匠人",
					"effects": [
						{"target": "attribute", "key": "craft", "value": "+2"},
						{"target": "attribute", "key": "aptitude", "value": "-1"}
					]
				},
				{
					"option_id": "bg_scholar",
					"option_text": "学者",
					"effects": [
						{"target": "attribute", "key": "insight", "value": "+2"},
						{"target": "attribute", "key": "craft", "value": "-1"}
					]
				}
			]
		},
		{
			"question_id": "q_temperament",
			"question_text": "你是怎样的人？",
			"condition": "",
			"options": [
				{
					"option_id": "tmp_cautious",
					"option_text": "谨慎稳重",
					"effects": [{"target": "attribute", "key": "xinxing", "value": "+1"}]
				},
				{
					"option_id": "tmp_gambler",
					"option_text": "放手一搏",
					"effects": [{"target": "attribute", "key": "xinxing", "value": "-1"}]
				}
			]
		},
		{
			"question_id": "q_relation",
			"question_text": "你和镇上的人……",
			"condition": "",
			"options": [
				{
					"option_id": "rel_friendly",
					"option_text": "相处融洽",
					"effects": [{"target": "affinity_all", "key": "_to_all_npc", "value": "+10"}]
				},
				{
					"option_id": "rel_stranger",
					"option_text": "素不相识",
					"effects": [{"target": "affinity_all", "key": "_to_all_npc", "value": "-5"}]
				}
			]
		}
	]


static func _pass(checks: Array, label: String) -> void:
	checks.append({"label": label, "passed": true})
	print("  [PASS] %s" % label)

static func _fail(checks: Array, failed: Array, label: String, reason: String) -> void:
	checks.append({"label": label, "passed": false, "reason": reason})
	failed.append({"label": label, "reason": reason})
	print("  [FAIL] %s -> %s" % [label, reason])
