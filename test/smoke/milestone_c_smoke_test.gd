extends RefCounted

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")


# 功能：执行里程碑 C 的任务偏置冒烟验证。
# 说明：验证点包含偏置生效、硬过滤不受影响、最终权重下限成立。
static func run_from_csv(csv_dir: String = "res://scripts/config/world_event_mvp") -> Dictionary:
	var base_engine := WorldEventEngine.new(20260305)
	var base_load := base_engine.load_from_csv_dir(csv_dir)
	if not base_load.get("ok", false):
		return base_load

	var with_task_engine := WorldEventEngine.new(20260305)
	var task_load := with_task_engine.load_from_csv_dir(csv_dir)
	if not task_load.get("ok", false):
		return task_load

	# 说明：手工挂载任务，构造“同一世界状态下，有/无任务”的对照组。
	_inject_active_tasks(with_task_engine, ["task_exam", "task_smuggle"])

	var base_snapshot := base_engine.debug_get_candidate_weights()
	var task_snapshot := with_task_engine.debug_get_candidate_weights()
	if not base_snapshot.get("ok", false):
		return {"ok": false, "error": "base snapshot failed"}
	if not task_snapshot.get("ok", false):
		return {"ok": false, "error": "task snapshot failed"}

	var base_weights: Dictionary = base_snapshot.get("weights", {})
	var task_weights: Dictionary = task_snapshot.get("weights", {})
	var checks: Array = []
	var failed: Array = []

	_assert_present(base_weights, checks, failed, "evt_study_001", "base snapshot contains study event")
	_assert_present(task_weights, checks, failed, "evt_study_001", "task snapshot contains study event")
	_assert_present(base_weights, checks, failed, "evt_market_001", "base snapshot contains market event")
	_assert_present(task_weights, checks, failed, "evt_market_001", "task snapshot contains market event")
	_assert_present(base_weights, checks, failed, "evt_story_force_001", "base snapshot contains story force event")
	_assert_present(task_weights, checks, failed, "evt_story_force_001", "task snapshot contains story force event")

	_assert_greater(
		checks,
		failed,
		task_weights.get("evt_study_001", -1),
		base_weights.get("evt_study_001", -1),
		"advance link increases study event weight"
	)
	_assert_less(
		checks,
		failed,
		task_weights.get("evt_market_001", -1),
		base_weights.get("evt_market_001", -1),
		"risk link decreases market event weight"
	)
	_assert_less(
		checks,
		failed,
		task_weights.get("evt_story_force_001", -1),
		base_weights.get("evt_story_force_001", -1),
		"risk link decreases story force event weight"
	)

	# 说明：港口事件受地点/NPC硬过滤约束；当前初始地点下不应因任务偏置被放出。
	_assert_absent(task_weights, checks, failed, "evt_harbor_deal_001", "hard filter still blocks harbor deal")

	# 说明：权重下限必须持续生效，任何候选事件权重都不应小于 1。
	_assert_weight_floor(base_weights, checks, failed, "base snapshot weight floor >= 1")
	_assert_weight_floor(task_weights, checks, failed, "task snapshot weight floor >= 1")

	return {
		"ok": failed.is_empty(),
		"checks": checks,
		"failed": failed,
		"base_weights": base_weights,
		"task_weights": task_weights
	}


# 功能：向引擎注入活动任务集合。
# 说明：只用于测试场景，业务逻辑不应依赖此写法。
static func _inject_active_tasks(engine: WorldEventEngine, task_ids: Array) -> void:
	var world_state: Dictionary = engine.world_state
	var tasks_state: Dictionary = world_state.get("tasks", {})
	var active: Array = []
	var current_turn := int(world_state.get("turn", 1))
	for task_id_variant in task_ids:
		var task_id := str(task_id_variant).strip_edges()
		if task_id.is_empty():
			continue
		active.append(
			{
				"taskId": task_id,
				"acceptedTurn": current_turn,
				"deadlineTurn": current_turn + 10,
				"status": "active",
				"progress": {}
			}
		)
	tasks_state["active"] = active
	tasks_state["completed"] = []
	tasks_state["failed"] = []
	tasks_state["abandoned"] = []
	world_state["tasks"] = tasks_state
	engine.world_state = world_state


# 功能：断言左值大于右值。
static func _assert_greater(checks: Array, failed: Array, left: Variant, right: Variant, name: String) -> void:
	var ok := int(left) > int(right)
	var item := {"name": name, "ok": ok, "left": int(left), "right": int(right)}
	checks.append(item)
	if not ok:
		failed.append(item)


# 功能：断言左值小于右值。
static func _assert_less(checks: Array, failed: Array, left: Variant, right: Variant, name: String) -> void:
	var ok := int(left) < int(right)
	var item := {"name": name, "ok": ok, "left": int(left), "right": int(right)}
	checks.append(item)
	if not ok:
		failed.append(item)


# 功能：断言权重映射中不包含目标事件。
static func _assert_absent(weights: Dictionary, checks: Array, failed: Array, event_id: String, name: String) -> void:
	var ok := not weights.has(event_id)
	var item := {"name": name, "ok": ok, "event_id": event_id}
	checks.append(item)
	if not ok:
		failed.append(item)


# 功能：断言权重映射中包含目标事件。
static func _assert_present(weights: Dictionary, checks: Array, failed: Array, event_id: String, name: String) -> void:
	var ok := weights.has(event_id)
	var item := {"name": name, "ok": ok, "event_id": event_id}
	checks.append(item)
	if not ok:
		failed.append(item)


# 功能：断言所有权重都不低于 1。
static func _assert_weight_floor(weights: Dictionary, checks: Array, failed: Array, name: String) -> void:
	var ok := true
	var min_weight := 999999
	for key in weights.keys():
		var weight := int(weights[key])
		min_weight = mini(min_weight, weight)
		if weight < 1:
			ok = false
	var item := {"name": name, "ok": ok, "min_weight": min_weight}
	checks.append(item)
	if not ok:
		failed.append(item)
