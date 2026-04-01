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

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed
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
