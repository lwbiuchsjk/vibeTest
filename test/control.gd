extends Control

const MilestoneASmokeTest := preload("res://scripts/systems/milestone_a_smoke_test.gd")
const MvpWorldEventSmokeTest := preload("res://scripts/systems/mvp_world_event_smoke_test.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")

func _ready() -> void:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded()
	if not load_result.get("ok", false):
		push_error("Config load failed: %s" % load_result.get("error", "unknown"))
		return
	var world_event_data := runtime.get_world_event_data()
	_print_milestone_a_acceptance(world_event_data)

	var context := runtime.build_context()
	if not context.get("ok", false):
		push_error("Config context build failed: %s" % context.get("error", "unknown"))
		return

	var milestone_result: Dictionary = MilestoneASmokeTest.run_with_context(context)
	#print("[MilestoneA]", milestone_result)

	# MVP 世界与事件引擎回归输出。
	var mvp_result: Dictionary = MvpWorldEventSmokeTest.run_from_csv()
	#print("[MVP-WorldEvent]", mvp_result)
	if mvp_result.get("ok", false):
		var turns: Array = mvp_result.get("turns", [])
		print("[MVP-WorldEvent] Triggered Events Summary (ordered):")
		for turn_variant in turns:
			var turn_detail: Dictionary = turn_variant
			var event: Dictionary = turn_detail.get("event", {})
			var choice_text := "无"
			var choice: Dictionary = event.get("choice", {})
			var selected_option_id := str(choice.get("selected_option_id", ""))
			# 说明：打印本次选择时，优先输出“选项ID + 选项文本”，便于快速核对分支路径。
			if not selected_option_id.is_empty():
				var selected_option_label := ""
				var options: Array = choice.get("options", [])
				for option_variant in options:
					var option_def: Dictionary = option_variant
					if str(option_def.get("id", "")) == selected_option_id:
						selected_option_label = str(option_def.get("text", ""))
						break
				if selected_option_label.is_empty():
					choice_text = selected_option_id
				else:
					choice_text = "%s (%s)" % [selected_option_id, selected_option_label]
			print(
				"  - Turn %s | event_id=%s | title=%s | route=%s | policy=%s | 本次选择=%s" % [
					str(turn_detail.get("turn_index", "")),
					str(event.get("event_id", "")),
					str(event.get("title", "")),
					str(event.get("route", "")),
					str(event.get("policy", "")),
					choice_text
				]
			)


func _process(delta: float) -> void:
	pass


# 功能：打印里程碑 A 的关键验收数据。
# 说明：该输出仅用于本地验收，不参与任何业务逻辑分支。
func _print_milestone_a_acceptance(world_event_data: Dictionary) -> void:
	var world_state: Dictionary = world_event_data.get("world_state", {})
	var task_config: Dictionary = world_state.get("taskConfig", {})
	var tasks_state: Dictionary = world_state.get("tasks", {})
	var task_defs: Array = world_event_data.get("task_defs", [])
	var events: Array = world_event_data.get("events", [])

	print("[MilestoneA] world_state.taskConfig = %s" % JSON.stringify(task_config))
	print("[MilestoneA] world_state.tasks = %s" % JSON.stringify(tasks_state))
	print("[MilestoneA] task_defs.count = %d" % task_defs.size())
	print("[MilestoneA] task_defs = %s" % JSON.stringify(task_defs))

	var event_links: Array = []
	for event_variant in events:
		var event_def: Dictionary = event_variant
		event_links.append(
			{
				"id": str(event_def.get("id", "")),
				"taskLinks": event_def.get("taskLinks", [])
			}
		)
	print("[MilestoneA] events.taskLinks = %s" % JSON.stringify(event_links))
