extends PanelContainer

signal action_requested(action_id: String)

@onready var title_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndTitle
@onready var subtitle_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndSubtitle
@onready var summary_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndSummary
@onready var ending_value_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndStats/EndingStat/EndingStatMargin/EndingStatContent/EndingStatValue
@onready var turn_value_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndStats/TurnStat/TurnStatMargin/TurnStatContent/TurnStatValue
@onready var task_value_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndStats/TaskStat/TaskStatMargin/TaskStatContent/TaskStatValue
@onready var state_value_label: Label = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndStats/StateStat/StateStatMargin/StateStatContent/StateStatValue
@onready var action_list: VBoxContainer = $EndMargin/EndCenter/EndCard/EndCardMargin/EndCardContent/EndActionList


# 功能：根据视图模型刷新终局页内容。
# 说明：终局页只消费外部传入的稳定数据结构，不直接依赖事件引擎状态。
func render_model(ending_model: Dictionary) -> void:
	title_label.text = str(ending_model.get("title", "本轮已结束"))
	subtitle_label.text = str(ending_model.get("subtitle", ""))
	ending_value_label.text = str(ending_model.get("endingEventId", ""))
	turn_value_label.text = str(ending_model.get("finishedTurn", 0))
	task_value_label.text = str(ending_model.get("taskSummary", ""))
	state_value_label.text = str(ending_model.get("stateSummary", ""))
	summary_label.text = str(ending_model.get("summaryText", ""))
	_render_actions(ending_model)


# 功能：根据动作配置渲染终局页操作区。
# 说明：当前先支持空动作提示，后续若接入切配置或进入下一流程，只需扩展 model.actions。
func _render_actions(ending_model: Dictionary) -> void:
	for child in action_list.get_children():
		child.queue_free()

	var actions: Array = ending_model.get("actions", [])
	if actions.is_empty():
		var hint_label := Label.new()
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.text = "当前版本暂未接入后续流程选项。"
		action_list.add_child(hint_label)
		return

	for action_variant in actions:
		var action_def: Dictionary = action_variant
		var action_button := Button.new()
		action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_button.text = str(action_def.get("label", "未命名操作"))
		action_button.disabled = bool(action_def.get("disabled", true))
		action_button.pressed.connect(_on_action_button_pressed.bind(str(action_def.get("id", ""))))
		action_list.add_child(action_button)


# 功能：把终局页的动作点击抛给宿主场景。
# 说明：终局页只负责发信号，不直接处理重开、切配置或数据加载。
func _on_action_button_pressed(action_id: String) -> void:
	action_requested.emit(action_id)
