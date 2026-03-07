extends RefCounted
class_name WorldEndMilestone1SmokeTest

const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const WorldEventConfigAssembler := preload("res://scripts/systems/world_event_config_assembler.gd")


# 功能：验证世界结束里程碑 1 的配置层能力。
# 说明：先验证现有 CSV 能正常编译出 isEndingEvent 字段，再验证 ending event + choice point 的强约束会被阻断。
static func run_from_csv(csv_dir: String = "res://scripts/config/world_event_mvp") -> Dictionary:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded({"world_event_csv_dir": csv_dir}, true)
	if not load_result.get("ok", false):
		return load_result

	var world_event_data := runtime.get_world_event_data()
	var events: Array = world_event_data.get("events", [])
	var all_events_have_ending_flag := true
	for event_variant in events:
		var event_def: Dictionary = event_variant
		if not event_def.has("isEndingEvent"):
			all_events_have_ending_flag = false
			break

	var invalid_constraint_result := WorldEventConfigAssembler._validate_ending_event_constraints(
		{
			"evt_invalid_ending": {
				"id": "evt_invalid_ending",
				"isEndingEvent": true,
				"choicePointId": "cp_invalid"
			}
		}
	)

	return {
		"ok": all_events_have_ending_flag and not invalid_constraint_result.get("ok", true),
		"all_events_have_ending_flag": all_events_have_ending_flag,
		"invalid_constraint_error": str(invalid_constraint_result.get("error", "")),
		"event_count": events.size()
	}
