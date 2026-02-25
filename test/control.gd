extends Control

const MilestoneASmokeTest := preload("res://scripts/systems/milestone_a_smoke_test.gd")

func _ready() -> void:
	var result: Dictionary = MilestoneASmokeTest.run()
	print(result)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
