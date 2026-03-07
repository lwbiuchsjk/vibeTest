extends RefCounted
class_name WorldEndMilestone4SmokeTest

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const WorldEndMilestone1SmokeTest := preload("res://scripts/systems/world_end_milestone_1_smoke_test.gd")
const WorldEndMilestone2SmokeTest := preload("res://scripts/systems/world_end_milestone_2_smoke_test.gd")
const WorldEndMilestone3SmokeTest := preload("res://scripts/systems/world_end_milestone_3_smoke_test.gd")


# 功能：汇总验证世界结束功能的回归与 smoke test。
# 说明：这里串联配置阻断、ending 正常结束、ended 接口封口与非 ending 兼容回归，作为当前阶段的闭环验收。
static func run() -> Dictionary:
	var m1_result: Dictionary = WorldEndMilestone1SmokeTest.run_from_csv()
	var m2_result: Dictionary = WorldEndMilestone2SmokeTest.run()
	var m3_result: Dictionary = WorldEndMilestone3SmokeTest.run()
	var non_ending_result: Dictionary = _run_non_ending_regression()
	return {
		"ok": bool(m1_result.get("ok", false))
			and bool(m2_result.get("ok", false))
			and bool(m3_result.get("ok", false))
			and bool(non_ending_result.get("ok", false)),
		"m1": m1_result,
		"m2": m2_result,
		"m3": m3_result,
		"non_ending": non_ending_result
	}


# 功能：验证普通事件不会误触发世界结束逻辑。
# 说明：兼容回归的重点是 world_ended 保持 false，runState 维持 running，且回合数照常推进。
static func _run_non_ending_regression() -> Dictionary:
	var engine := WorldEventEngine.new(20260307)
	var load_result: Dictionary = engine.load_from_data(
		{
			"world_state": {
				"turn": 1,
				"currentLocationId": "town_square",
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
				"forcedNextEventId": "evt_normal_test"
			},
			"events": [
				{
					"id": "evt_normal_test",
					"title": "普通回合测试事件",
					"baseWeight": 1,
					"tags": ["normal"],
					"taskLinks": [],
					"isEndingEvent": false,
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

	var turn_result: Dictionary = engine.run_turn()
	var run_state: Dictionary = engine.world_state.get("runState", {})
	return {
		"ok": bool(turn_result.get("ok", false))
			and not bool(turn_result.get("world_ended", true))
			and str(turn_result.get("run_status", "")) == "running"
			and str(turn_result.get("ending_event_id", "")) == ""
			and int(turn_result.get("finished_turn", -1)) == 0
			and str(run_state.get("status", "")) == "running"
			and str(run_state.get("endingEventId", "")) == ""
			and int(run_state.get("finishedTurn", -1)) == 0
			and int(engine.world_state.get("turn", -1)) == 2,
		"turn_result": turn_result,
		"run_state": run_state,
		"world_turn": int(engine.world_state.get("turn", -1))
	}
