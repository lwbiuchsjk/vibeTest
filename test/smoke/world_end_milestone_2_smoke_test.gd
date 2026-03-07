extends RefCounted

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")


# 功能：验证世界结束里程碑 2 的运行态能力。
# 说明：使用内存数据构造一个 ending event，确认其结算后会写入 runState 并清理执行锁。
static func run() -> Dictionary:
	var engine := WorldEventEngine.new(20260307)
	var load_result: Dictionary = engine.load_from_data(
		{
			"world_state": {
				"turn": 3,
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
				"chainContext": {
					"chainId": "chain_test",
					"stage": 2,
					"allowedTags": ["ending"],
					"weightBias": {},
					"exitWhenStageGte": 0
				},
				"forcedNextEventId": "evt_ending_test"
			},
			"events": [
				{
					"id": "evt_ending_test",
					"title": "终局测试事件",
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

	var turn_result: Dictionary = engine.run_turn()
	if not turn_result.get("ok", false):
		return turn_result

	var run_state: Dictionary = engine.world_state.get("runState", {})
	return {
		"ok": str(run_state.get("status", "")) == "ended"
			and str(run_state.get("endingEventId", "")) == "evt_ending_test"
			and int(run_state.get("finishedTurn", -1)) == 3
			and str(engine.world_state.get("forcedNextEventId", "missing")) == ""
			and engine.world_state.get("chainContext", "missing") == null
			and int(engine.world_state.get("turn", -1)) == 3,
		"turn_result": turn_result,
		"run_state": run_state,
		"world_turn": int(engine.world_state.get("turn", -1)),
		"forced_next": str(engine.world_state.get("forcedNextEventId", "missing")),
		"chain_context": engine.world_state.get("chainContext", "missing")
	}
