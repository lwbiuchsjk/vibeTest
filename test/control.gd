extends Control

const MilestoneASmokeTest := preload("res://scripts/systems/milestone_a_smoke_test.gd")
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")

func _ready() -> void:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded()
	if not load_result.get("ok", false):
		push_error("Config load failed: %s" % load_result.get("error", "unknown"))
		return

	var context := runtime.build_context()
	if not context.get("ok", false):
		push_error("Config context build failed: %s" % context.get("error", "unknown"))
		return

	var result: Dictionary = MilestoneASmokeTest.run_with_context(context)
	print(result)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
