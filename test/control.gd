extends Control

const MilestoneASmokeTest := preload("res://test/smoke/milestone_a_smoke_test.gd")
const MilestoneCSmokeTest := preload("res://test/smoke/milestone_c_smoke_test.gd")
const Milestone3SmokeTest := preload("res://test/smoke/milestone_3_smoke_test.gd")
const MvpWorldEventSmokeTest := preload("res://test/smoke/mvp_world_event_smoke_test.gd")
const WorldEndMilestone1SmokeTest := preload("res://test/smoke/world_end_milestone_1_smoke_test.gd")
const WorldEndMilestone2SmokeTest := preload("res://test/smoke/world_end_milestone_2_smoke_test.gd")
const WorldEndMilestone3SmokeTest := preload("res://test/smoke/world_end_milestone_3_smoke_test.gd")
const WorldEndMilestone4SmokeTest := preload("res://test/smoke/world_end_milestone_4_smoke_test.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")


# 功能：测试入口，加载配置并打印各里程碑验收结果。
# 说明：该脚本只负责验收输出，不参与业务逻辑。
func _ready() -> void:
	# 说明：启动标记，确认 test/control.tscn 已执行到脚本入口。
	print("[ControlTest] _ready started")
	print("[ControlTest] scene=%s" % str(get_tree().current_scene.scene_file_path))

	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded()
	if not load_result.get("ok", false):
		var load_error := str(load_result.get("error", "unknown"))
		push_error("Config load failed: %s" % load_error)
		print("[ControlTest] Config load failed: %s" % load_error)
		return

	var world_event_data := runtime.get_world_event_data()
	_print_milestone_a_acceptance(world_event_data)
	_print_milestone_1_acceptance(world_event_data)

	var context := runtime.build_context()
	if not context.get("ok", false):
		var context_error := str(context.get("error", "unknown"))
		push_error("Config context build failed: %s" % context_error)
		print("[ControlTest] Config context build failed: %s" % context_error)
		return

	var milestone_result: Dictionary = MilestoneASmokeTest.run_with_context(context)
	#print("[MilestoneA]", milestone_result)
	var milestone_c_result: Dictionary = MilestoneCSmokeTest.run_from_csv()
	print("[MilestoneC] %s" % JSON.stringify(milestone_c_result))
	var milestone_3_result: Dictionary = Milestone3SmokeTest.run_from_csv()
	print("[Milestone3] %s" % JSON.stringify(milestone_3_result))
	# 功能：输出世界结束里程碑 1 的配置层验收结果。
	# 说明：这里只验证 ending 标记编译与 ending 事件强约束，不涉及运行时结束流程。
	var world_end_m1_result: Dictionary = WorldEndMilestone1SmokeTest.run_from_csv()
	print("[WorldEnd-M1] %s" % JSON.stringify(world_end_m1_result))
	# 功能：输出世界结束里程碑 2 的运行态验收结果。
	# 说明：这里验证 ending event 结算后 runState 写入与执行锁清理是否正确。
	var world_end_m2_result: Dictionary = WorldEndMilestone2SmokeTest.run()
	print("[WorldEnd-M2] %s" % JSON.stringify(world_end_m2_result))
	# 功能：输出世界结束里程碑 3 的接口封口验收结果。
	# 说明：这里验证 ending event 当次 payload 已带 ended 字段，且 ended 后的 preview/run/confirm 都会稳定短路。
	var world_end_m3_result: Dictionary = WorldEndMilestone3SmokeTest.run()
	print("[WorldEnd-M3] %s" % JSON.stringify(world_end_m3_result))
	# 功能：输出世界结束里程碑 4 的汇总回归结果。
	# 说明：这里汇总非法配置阻断、ending 正常结束、ended 封口与非 ending 兼容回归，便于一次性验收。
	var world_end_m4_result: Dictionary = WorldEndMilestone4SmokeTest.run()
	print("[WorldEnd-M4] %s" % JSON.stringify(world_end_m4_result))

	# 说明：执行 MVP 世界事件回归测试并输出摘要。
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
			# 说明：优先打印“选项ID + 选项文本”，便于快速核对分支路径。
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
# 说明：用于核对任务配置和事件任务链接是否成功编译。
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


# 功能：打印里程碑 1（任务档位评价配置接入）的验收结果。
# 说明：仅验证配置编译与透传，不验证运行时结算逻辑。
func _print_milestone_1_acceptance(world_event_data: Dictionary) -> void:
	var task_evaluation: Dictionary = world_event_data.get("task_evaluation", {})
	var grades: Array = task_evaluation.get("grades", [])
	var indicators: Array = task_evaluation.get("indicators", [])
	var grade_overrides: Array = task_evaluation.get("gradeOverrides", [])
	var effects: Array = task_evaluation.get("effects", [])

	# 说明：先输出计数，快速确认四张 task_eval_* 表已成功编译进入运行时数据。
	var milestone_1_counts := "[Milestone1] counts grades=%d indicators=%d gradeOverrides=%d effects=%d" % [
		grades.size(),
		indicators.size(),
		grade_overrides.size(),
		effects.size()
	]
	print(milestone_1_counts)
	# 说明：再输出完整结构，便于逐字段核对 CSV -> 运行时映射是否正确。
	var milestone_1_detail := "[Milestone1] task_evaluation = %s" % JSON.stringify(task_evaluation)
	print(milestone_1_detail)
