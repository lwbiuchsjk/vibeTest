extends RefCounted
class_name MvpWorldEventSmokeTest

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")

static func run() -> Dictionary:
	var engine := WorldEventEngine.new(20260226)
	var load_result := engine.load_from_files(
		"res://world_state_seed.json",
		"res://events_mvp.json"
	)
	if not load_result.get("ok", false):
		return load_result

	var turns: Array = []
	var forced_checks := 0
	var chain_hits := 0
	var guard_location_block_verified := false
	var guard_npc_block_verified := false

	for _i in range(20):
		var turn_index := _i + 1
		var expected_forced := str(engine.world_state.get("forcedNextEventId", ""))
		var before_location := str(engine.world_state.get("currentLocationId", ""))
		var before_presence: Dictionary = engine.world_state.get("npcPresence", {})
		var before_present_list: Array = before_presence.get(before_location, [])

		var turn_result := engine.run_turn()
		if not turn_result.get("ok", false):
			return turn_result

		if not expected_forced.is_empty():
			forced_checks += 1
			if str(turn_result.get("event_id", "")) != expected_forced:
				return {
					"ok": false,
					"error": "forced next mismatch",
					"expected": expected_forced,
					"actual": str(turn_result.get("event_id", ""))
				}

		if bool(turn_result.get("chain_active", false)):
			chain_hits += 1

		# 轻量验证：在非港口或无走私商人时，不应命中码头交易事件。
		var selected_id := str(turn_result.get("event_id", ""))
		if selected_id == "evt_harbor_deal_001":
			if before_location != "harbor":
				return {"ok": false, "error": "location gating broken for evt_harbor_deal_001"}
			if not ("npc_smuggler" in before_present_list):
				return {"ok": false, "error": "npc gating broken for evt_harbor_deal_001"}
			guard_location_block_verified = true
			guard_npc_block_verified = true

		var turn_detail := {
			"turn_index": turn_index,
			"before_location": before_location,
			"expected_forced": expected_forced,
			"event": turn_result,
			"after_location": str(engine.world_state.get("currentLocationId", "")),
			"after_forced": str(engine.world_state.get("forcedNextEventId", "")),
			"chain_context": engine.world_state.get("chainContext", null)
		}
		turns.append(turn_detail)
		# 测试阶段按回合完整输出事件信息，便于定位调度链路问题。
		print("[MVP-WorldEvent][Turn-%02d] %s" % [turn_index, JSON.stringify(turn_detail)])

	return {
		"ok": true,
		"turn_count": turns.size(),
		"forced_checks": forced_checks,
		"chain_hits": chain_hits,
		"location_npc_gating_observed": guard_location_block_verified and guard_npc_block_verified,
		"last_turn": turns[-1] if not turns.is_empty() else {},
		"turns": turns
	}
