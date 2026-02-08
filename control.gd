extends Control

@onready var label: Label = $Label
@onready var button: Button = $Button

func _ready() -> void:
	button.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	label.text = "测试成功"
