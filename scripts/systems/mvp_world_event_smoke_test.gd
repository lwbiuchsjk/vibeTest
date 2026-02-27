extends RefCounted
class_name MvpWorldEventSmokeTest

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")

static func run() -> Dictionary:
	var engine := WorldEventEngine.new(20260226)
	var option_rng := RandomNumberGenerator.new()
	option_rng.seed = 20260227
	var load_result := engine.load_from_files(
		"res://world_state_seed.json",
		"res://events_mvp.json",
		"res://choice_points_mvp.json"
	)
	if not load_result.get("ok", false):
		return load_result

	var turns: Array = []
	var forced_checks := 0
	var chain_hits := 0
	var guard_location_block_verified := false
	var guard_npc_block_verified := false
	var option_state_seen := {
		"invisible": false,
		"disabled": false,
		"selectable": false
	}
	var choice_forced_verified := false
	var choice_resolution_applied := false

	var completed_turns := 0
	var safety_guard := 0
	while completed_turns < 20:
		safety_guard += 1
		if safety_guard > 80:
			return {"ok": false, "error": "turn loop safety guard triggered"}

		var turn_index := completed_turns + 1
		var expected_forced := str(engine.world_state.get("forcedNextEventId", ""))
		var before_location := str(engine.world_state.get("currentLocationId", ""))
		var before_presence: Dictionary = engine.world_state.get("npcPresence", {})
		var before_present_list: Array = before_presence.get(before_location, [])

		var turn_result := engine.run_turn()
		if not turn_result.get("ok", false):
			return turn_result
		if bool(turn_result.get("awaiting_choice", false)):
			var choice: Dictionary = turn_result.get("choice", {})
			# 说明：测试流程自动喂选项，但改为在所有可选项中随机选择一个。
			var selected_option_id := _random_selectable_option_id(choice.get("options", []), option_rng)
			if selected_option_id.is_empty():
				return {"ok": false, "error": "awaiting choice but no selectable option"}
			turn_result = engine.run_turn(selected_option_id)
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

		if bool(turn_result.get("has_choice", false)):
			var choice: Dictionary = turn_result.get("choice", {})
			var options: Array = choice.get("options", [])
			for option_variant in options:
				var option_def: Dictionary = option_variant
				var state := str(option_def.get("state", ""))
				if option_state_seen.has(state):
					option_state_seen[state] = true
			var selected_option_id := str(choice.get("selected_option_id", ""))
			if not selected_option_id.is_empty():
				choice_resolution_applied = true
			if selected_option_id == "opt_run":
				var after_forced := str(engine.world_state.get("forcedNextEventId", ""))
				if after_forced != "evt_guard_chase_001":
					return {
						"ok": false,
						"error": "choice forced next mismatch",
						"expected": "evt_guard_chase_001",
						"actual": after_forced
					}
				choice_forced_verified = true

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
		completed_turns += 1
		# 测试阶段按回合完整输出事件信息，便于定位调度链路问题。
		print("[MVP-WorldEvent][Turn-%02d] %s" % [completed_turns, JSON.stringify(turn_detail)])

	for key in option_state_seen.keys():
		if not bool(option_state_seen[key]):
			return {
				"ok": false,
				"error": "choice option state not observed",
				"missing_state": str(key)
			}

	if not choice_forced_verified:
		return {"ok": false, "error": "choice forced-next path not verified"}

	if not choice_resolution_applied:
		return {"ok": false, "error": "choice resolution path not observed"}

	return {
		"ok": true,
		"turn_count": turns.size(),
		"forced_checks": forced_checks,
		"chain_hits": chain_hits,
		"choice_option_states_seen": option_state_seen,
		"choice_forced_verified": choice_forced_verified,
		"choice_resolution_applied": choice_resolution_applied,
		"location_npc_gating_observed": guard_location_block_verified and guard_npc_block_verified,
		"last_turn": turns[-1] if not turns.is_empty() else {},
		"turns": turns
	}

# 功能：从选项列表中随机获取一个可选项 id。
# 说明：仅在 state=selectable 的候选集中抽样，模拟外部随机喂选项行为。
static func _random_selectable_option_id(options: Array, rng: RandomNumberGenerator) -> String:
	var selectable_ids: Array = []
	for option_variant in options:
		var option_def: Dictionary = option_variant
		if str(option_def.get("state", "")) == "selectable":
			selectable_ids.append(str(option_def.get("id", "")))
	if selectable_ids.is_empty():
		return ""
	var pick_index := rng.randi_range(0, selectable_ids.size() - 1)
	return str(selectable_ids[pick_index])
