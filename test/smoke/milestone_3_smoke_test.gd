extends RefCounted

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")


# 功能：执行里程碑 3（任务终态评价）冒烟验收。
# 说明：覆盖 completed 分档与分流、failed/abandoned 非完成态、resultRecords 写入与评价后果应用。
static func run_from_csv(csv_dir: String = "res://scripts/config/world_event_mvp") -> Dictionary:
	var engine := WorldEventEngine.new(20260306)
	var load_result := engine.load_from_csv_dir(csv_dir)
	if not load_result.get("ok", false):
		return load_result

	var checks: Array = []

	# 说明：场景 1，task_exam 完成态，命中 base_grade 后再被 override 到 g_risky。
	var danger_before := int(engine.world_state.get("params", {}).get("danger", 0))
	var accepted_exam := engine._accept_task("task_exam")
	engine._advance_task("task_exam", "study", 51)
	var flags_exam: Dictionary = engine.world_state.get("flags", {})
	flags_exam["isWanted"] = true
	engine.world_state["flags"] = flags_exam
	var completed_exam := engine._complete_task("task_exam")
	var exam_record := _find_latest_result_record(engine, "task_exam")
	_append_check(checks, "exam_accept", accepted_exam, {"task": "task_exam"})
	_append_check(checks, "exam_complete", completed_exam, {"task": "task_exam"})
	_append_check(
		checks,
		"exam_grade_override",
		str(exam_record.get("gradeId", "")) == "g_risky",
		{"expected": "g_risky", "actual": str(exam_record.get("gradeId", ""))}
	)
	_append_check(
		checks,
		"exam_score",
		int(exam_record.get("score", -999)) == 4,
		{"expected": 4, "actual": exam_record.get("score", null)}
	)
	_append_check(
		checks,
		"exam_effect_applied",
		int(engine.world_state.get("params", {}).get("danger", 0)) == danger_before + 2,
		{"expected": danger_before + 2, "actual": int(engine.world_state.get("params", {}).get("danger", 0))}
	)

	# 说明：场景 2，task_part_time failed 终态，不应计算完成档位。
	var morale_before_failed := int(engine.world_state.get("params", {}).get("morale", 0))
	var accepted_part_time_failed := engine._accept_task("task_part_time")
	var finalized_failed := engine._finalize_task("task_part_time", "failed", "script_failed")
	var failed_record := _find_latest_result_record(engine, "task_part_time")
	_append_check(checks, "part_time_failed_accept", accepted_part_time_failed, {"task": "task_part_time"})
	_append_check(checks, "part_time_failed_finalize", finalized_failed, {"task": "task_part_time"})
	_append_check(
		checks,
		"part_time_failed_no_grade",
		str(failed_record.get("gradeId", "")) == "",
		{"expected": "", "actual": str(failed_record.get("gradeId", ""))}
	)
	_append_check(
		checks,
		"part_time_failed_no_score",
		failed_record.get("score", "not_null") == null,
		{"expected": null, "actual": failed_record.get("score", "missing")}
	)
	_append_check(
		checks,
		"part_time_failed_effect_applied",
		int(engine.world_state.get("params", {}).get("morale", 0)) == morale_before_failed - 1,
		{"expected": morale_before_failed - 1, "actual": int(engine.world_state.get("params", {}).get("morale", 0))}
	)

	# 说明：场景 3，task_smuggle abandoned 终态，不应计算完成档位。
	var morale_before_abandon := int(engine.world_state.get("params", {}).get("morale", 0))
	var accepted_smuggle := engine._accept_task("task_smuggle")
	var abandoned_smuggle := engine._abandon_task("task_smuggle")
	var abandoned_record := _find_latest_result_record(engine, "task_smuggle")
	_append_check(checks, "smuggle_accept", accepted_smuggle, {"task": "task_smuggle"})
	_append_check(checks, "smuggle_abandon", abandoned_smuggle, {"task": "task_smuggle"})
	_append_check(
		checks,
		"smuggle_abandon_no_grade",
		str(abandoned_record.get("gradeId", "")) == "",
		{"expected": "", "actual": str(abandoned_record.get("gradeId", ""))}
	)
	_append_check(
		checks,
		"smuggle_abandon_no_score",
		abandoned_record.get("score", "not_null") == null,
		{"expected": null, "actual": abandoned_record.get("score", "missing")}
	)
	_append_check(
		checks,
		"smuggle_abandon_effect_applied",
		int(engine.world_state.get("params", {}).get("morale", 0)) == morale_before_abandon - 2,
		{"expected": morale_before_abandon - 2, "actual": int(engine.world_state.get("params", {}).get("morale", 0))}
	)

	# 说明：场景 4，task_part_time completed 且无档位定义，验证 completed 通配效果与记录兼容。
	var prosperity_before := int(engine.world_state.get("params", {}).get("prosperity", 0))
	var accepted_part_time_completed := engine._accept_task("task_part_time")
	var completed_part_time := engine._complete_task("task_part_time")
	var completed_part_time_record := _find_latest_result_record(engine, "task_part_time")
	_append_check(checks, "part_time_completed_accept", accepted_part_time_completed, {"task": "task_part_time"})
	_append_check(checks, "part_time_completed_finalize", completed_part_time, {"task": "task_part_time"})
	_append_check(
		checks,
		"part_time_completed_no_grade",
		str(completed_part_time_record.get("gradeId", "")) == "",
		{"expected": "", "actual": str(completed_part_time_record.get("gradeId", ""))}
	)
	_append_check(
		checks,
		"part_time_completed_no_score",
		completed_part_time_record.get("score", "not_null") == null or int(completed_part_time_record.get("score", -999)) == 0,
		{"expected": "null_or_0", "actual": completed_part_time_record.get("score", "missing")}
	)
	_append_check(
		checks,
		"part_time_completed_effect_applied",
		int(engine.world_state.get("params", {}).get("prosperity", 0)) == prosperity_before + 1,
		{"expected": prosperity_before + 1, "actual": int(engine.world_state.get("params", {}).get("prosperity", 0))}
	)

	var failed_checks: Array = []
	for check_variant in checks:
		var check: Dictionary = check_variant
		if not bool(check.get("ok", false)):
			failed_checks.append(check)

	return {
		"ok": failed_checks.is_empty(),
		"checks": checks,
		"failed": failed_checks,
		"result_records": _array_or_empty(engine.world_state.get("tasks", {}).get("resultRecords", [])),
		"tasks": _dict_or_empty(engine.world_state.get("tasks", {})),
		"params": _dict_or_empty(engine.world_state.get("params", {})),
		"flags": _dict_or_empty(engine.world_state.get("flags", {}))
	}


# 功能：追加单条校验结果。
# 说明：统一输出格式，便于在 control.gd 中直接 JSON 打印和人工核对。
static func _append_check(checks: Array, name: String, ok: bool, detail: Dictionary = {}) -> void:
	checks.append(
		{
			"name": name,
			"ok": ok,
			"detail": detail
		}
	)


# 功能：从 resultRecords 中读取指定任务的最新记录。
# 说明：倒序查找用于验证重复结算场景下的最近一次结果。
static func _find_latest_result_record(engine: WorldEventEngine, task_id: String) -> Dictionary:
	var records: Array = _array_or_empty(engine.world_state.get("tasks", {}).get("resultRecords", []))
	for idx in range(records.size() - 1, -1, -1):
		var item := _dict_or_empty(records[idx])
		if str(item.get("taskId", "")).strip_edges() == task_id:
			return item
	return {}


# 功能：安全转换 Variant 为 Dictionary。
# 说明：避免测试脚本因空值/类型不符导致异常中断。
static func _dict_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY and value != null:
		return value
	return {}


# 功能：安全转换 Variant 为 Array。
# 说明：与 _dict_or_empty 配套，统一处理可选数组字段。
static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY and value != null:
		return value
	return []
