extends RefCounted
class_name WorldEndMilestone3SmokeTest

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")


# 功能：验证世界结束里程碑 3 的接口封口行为。
# 说明：先让 ending event 完成结算，再验证结果 payload 与 ended 后的 preview/run/confirm 都返回稳定结束态。
static func run() -> Dictionary:
	var engine := WorldEventEngine.new(20260307)
	var load_result: Dictionary = engine.load_from_data(
		{
			"world_state": {
				"turn": 4,
				"currentLocationId": "harbor",
				"flags": {},
				"params": {},
				"locationState": {},
				"npcPresence": {},
				"player": {},
				"taskConfig": {
					"maxActiveCount": 1
				},
				"tasks": {
					"active": [],
					"completed": [],
					"failed": [],
					"abandoned": [],
					"resultRecords": []
				},
				"history": [],
				"chainContext": null,
				"forcedNextEventId": "evt_ending_payload"
			},
			"events": [
				{
					"id": "evt_ending_payload",
					"title": "终局接口测试事件",
					"baseWeight": 1,
					"tags": ["ending"],
					"taskLinks": [],
					"isEndingEvent": true,
					"eligibility": {},
					"weightRules": [],
					"continuationPolicy": "ReturnToScheduler",
					"effects": {}
				}
			],
			"choice_points": [],
			"task_defs": [],
			"task_evaluation": {}
		}
	)
	if not load_result.get("ok", false):
		return load_result

	var resolved_result: Dictionary = engine.run_turn()
	if not resolved_result.get("ok", false):
		return resolved_result

	var preview_result: Dictionary = engine.preview_next_turn()
	var run_result: Dictionary = engine.run_turn()
	var confirm_result: Dictionary = engine.confirm_pending_turn()

	var resolved_ok := _is_expected_resolved_payload(resolved_result)
	var preview_ok := _is_expected_ended_payload(preview_result)
	var run_ok := _is_expected_ended_payload(run_result)
	var confirm_ok := _is_expected_ended_payload(confirm_result)

	return {
		"ok": resolved_ok and preview_ok and run_ok and confirm_ok,
		"resolved_result": resolved_result,
		"preview_result": preview_result,
		"run_result": run_result,
		"confirm_result": confirm_result
	}


# 功能：检查终局事件完成结算当次返回结构。
# 说明：这里要求 resolved payload 已经带上 ended 公开字段，供后续外部流程直接消费。
static func _is_expected_resolved_payload(result: Dictionary) -> bool:
	return bool(result.get("ok", false)) \
		and str(result.get("phase", "")) == "resolved" \
		and bool(result.get("world_ended", false)) \
		and str(result.get("run_status", "")) == "ended" \
		and str(result.get("ending_event_id", "")) == "evt_ending_payload" \
		and int(result.get("finished_turn", -1)) == 4 \
		and str(result.get("event_id", "")) == "evt_ending_payload"


# 功能：检查 ended 后接口返回是否稳定。
# 说明：只要世界已经结束，后续入口都应返回相同语义的 ended 结果，而不是重新进入调度或报错。
static func _is_expected_ended_payload(result: Dictionary) -> bool:
	return bool(result.get("ok", false)) \
		and str(result.get("phase", "")) == "ended" \
		and bool(result.get("world_ended", false)) \
		and str(result.get("run_status", "")) == "ended" \
		and str(result.get("ending_event_id", "")) == "evt_ending_payload" \
		and int(result.get("finished_turn", -1)) == 4 \
		and str(result.get("event_id", "")) == ""
