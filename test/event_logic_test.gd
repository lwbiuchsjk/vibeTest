extends Control

const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")

const CSV_DIR := "res://scripts/config/world_event_mvp"

var _engine := WorldEventEngine.new(20260228)
var _event_logs: Array[String] = []
var _current_turn_result: Dictionary = {}

@onready var status_label: Label = $Root/Header/StatusLabel
@onready var event_title_label: Label = $Root/LeftPanel/LeftMargin/LeftContent/EventTitle
@onready var event_detail_label: Label = $Root/LeftPanel/LeftMargin/LeftContent/EventDetail
@onready var continue_button: Button = $Root/LeftPanel/LeftMargin/LeftContent/ActionBar/ContinueButton
@onready var option_list: VBoxContainer = $Root/LeftPanel/LeftMargin/LeftContent/OptionScroll/OptionList
@onready var world_state_label: RichTextLabel = $Root/RightPanel/RightMargin/RightContent/WorldStateValue
@onready var log_label: RichTextLabel = $Root/BottomPanel/BottomMargin/BottomContent/LogValue


# 功能：初始化事件逻辑测试场景。
# 说明：加载配置后先预览首个事件，不在进入场景时立即推进 world turn。
func _ready() -> void:
	continue_button.pressed.connect(_on_continue_button_pressed)

	var load_result := _engine.load_from_csv_dir(CSV_DIR)
	if not load_result.get("ok", false):
		status_label.text = "加载失败：%s" % str(load_result.get("error", "unknown"))
		return

	_append_log("测试环境启动，开始预览第一个事件。")
	_preview_next_event()


# 功能：预览下一事件并停留在当前界面。
# 说明：预览阶段只展示事件内容，不执行结算，也不增加 world turn。
func _preview_next_event() -> void:
	_current_turn_result.clear()

	var turn_result := _engine.preview_next_turn()
	if not turn_result.get("ok", false):
		status_label.text = "事件预览失败：%s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	_current_turn_result = (turn_result as Dictionary).duplicate(true)
	_append_turn_log(turn_result)
	_render_current_event(turn_result)
	_update_side_panels()


# 功能：渲染当前事件。
# 说明：若事件带可选项，则显示选项按钮；若事件待继续确认，则仅显示继续按钮。
func _render_current_event(turn_result: Dictionary) -> void:
	var choice: Dictionary = turn_result.get("choice", {})
	var options: Array = choice.get("options", [])
	var awaiting_choice := bool(turn_result.get("awaiting_choice", false))

	event_title_label.text = "%s | %s" % [
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	event_detail_label.text = _build_event_detail_text(turn_result)

	_clear_option_list()
	continue_button.visible = false
	continue_button.disabled = true

	if awaiting_choice:
		status_label.text = "等待选择：点击下方任一可用选项。"
	else:
		status_label.text = "当前事件待确认，点击继续后结算并预览下一个事件。"
		continue_button.visible = true
		continue_button.disabled = false

	var visible_count := 0
	for option_variant in options:
		var option_def: Dictionary = option_variant
		var state := str(option_def.get("state", "disabled"))
		if state == "invisible":
			continue

		visible_count += 1
		var option_button := Button.new()
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		option_button.text = _build_option_button_text(option_def)
		option_button.disabled = state != "selectable"
		option_button.pressed.connect(_on_option_pressed.bind(str(option_def.get("id", ""))))
		option_list.add_child(option_button)

	if visible_count == 0:
		_add_option_hint("当前事件没有可见选项。")


# 功能：处理玩家点击选项。
# 说明：先结算当前待处理事件，再预览下一事件，保证界面总是停在“未结算事件”上。
func _on_option_pressed(option_id: String) -> void:
	if _current_turn_result.is_empty():
		status_label.text = "当前没有待处理的事件选择。"
		return

	var turn_result := _engine.confirm_pending_turn(option_id)
	if not turn_result.get("ok", false):
		status_label.text = "选项结算失败：%s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var choice: Dictionary = turn_result.get("choice", {})
	_append_log(
		"已选择 %s -> %s | %s" % [
			str(choice.get("selected_option_id", "")),
			str(turn_result.get("event_id", "")),
			str(turn_result.get("title", ""))
		]
	)
	_update_side_panels()
	_preview_next_event()


# 功能：处理继续指令。
# 说明：继续按钮用于确认当前待继续事件，然后再预览下一事件。
func _on_continue_button_pressed() -> void:
	if _current_turn_result.is_empty():
		_preview_next_event()
		return
	if bool(_current_turn_result.get("awaiting_choice", false)):
		status_label.text = "当前事件需要先完成选项选择。"
		return

	var turn_result := _engine.confirm_pending_turn()
	if not turn_result.get("ok", false):
		status_label.text = "事件结算失败：%s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	_append_log(
		"已确认继续 -> %s | %s" % [
			str(turn_result.get("event_id", "")),
			str(turn_result.get("title", ""))
		]
	)
	_update_side_panels()
	_preview_next_event()


# 功能：构建事件详情文本。
# 说明：补充 route、policy、chain 状态与当前 world turn，便于核对推进时机。
func _build_event_detail_text(turn_result: Dictionary) -> String:
	var choice: Dictionary = turn_result.get("choice", {})
	var lines: Array[String] = []
	lines.append("route=%s" % str(turn_result.get("route", "")))
	lines.append("policy=%s" % str(turn_result.get("policy", "")))
	lines.append("choice_point=%s" % str(choice.get("choice_point_id", "")))
	lines.append("chain_active=%s" % str(turn_result.get("chain_active", false)))
	lines.append("world_turn=%s" % str(_engine.world_state.get("turn", 0)))
	return "\n".join(lines)


# 功能：生成选项按钮文本。
# 说明：在按钮上直接标记状态，便于确认选项可选性是否符合预期。
func _build_option_button_text(option_def: Dictionary) -> String:
	var state := str(option_def.get("state", "disabled"))
	var state_text := "可选"
	if state == "disabled":
		state_text = "不可选"
	return "%s | %s\n状态：%s" % [
		str(option_def.get("id", "")),
		str(option_def.get("text", "")),
		state_text
	]


# 功能：刷新右侧世界状态与底部日志。
# 说明：集中展示玩家数据、世界参数、链上下文和历史事件，便于验证结算结果。
func _update_side_panels() -> void:
	var world_state := _engine.world_state
	var player: Dictionary = world_state.get("player", {})
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	var chain_context: Variant = world_state.get("chainContext", null)
	var history: Array = world_state.get("history", [])

	var lines: Array[String] = []
	lines.append("回合：%s" % str(world_state.get("turn", 0)))
	lines.append("地点：%s" % str(world_state.get("currentLocationId", "")))
	lines.append("强制下一事件：%s" % str(world_state.get("forcedNextEventId", "")))
	lines.append("")
	lines.append("玩家")
	lines.append(
		"hp=%s  gold=%s  energy=%s" % [
			str(player.get("hp", 0)),
			str(player.get("gold", 0)),
			str(player.get("energy", 0))
		]
	)
	lines.append("")
	lines.append("参数")
	lines.append(
		"danger=%s  prosperity=%s  morale=%s" % [
			str(params.get("danger", 0)),
			str(params.get("prosperity", 0)),
			str(params.get("morale", 0))
		]
	)
	lines.append("")
	lines.append("标记")
	lines.append(
		"isWanted=%s  gotHarborIntel=%s" % [
			str(flags.get("isWanted", false)),
			str(flags.get("gotHarborIntel", false))
		]
	)
	lines.append("")
	lines.append("链上下文")
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		lines.append(JSON.stringify(chain_context))
	else:
		lines.append("null")
	lines.append("")
	lines.append("最近历史")
	lines.append(", ".join(_history_to_string_array(history)))

	world_state_label.text = "\n".join(lines)
	# 说明：文本刷新后延迟一帧再复位滚动，避免 RichTextLabel 重排后覆盖滚动位置。
	world_state_label.call_deferred("scroll_to_line", 0)
	log_label.text = "\n".join(_event_logs)


# 功能：记录每次事件预览日志。
# 说明：将“等待选择”和“等待继续”显式写入日志，便于核对界面状态。
func _append_turn_log(turn_result: Dictionary) -> void:
	var line := "Turn %s | %s | %s | route=%s | policy=%s" % [
		str(_engine.world_state.get("turn", 0)),
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", "")),
		str(turn_result.get("route", "")),
		str(turn_result.get("policy", ""))
	]
	if turn_result.get("awaiting_choice", false):
		line += " | 等待选择"
	else:
		line += " | 等待继续"
	_append_log(line)


# 功能：向日志列表追加文本。
# 说明：只保留最近 18 条，避免测试界面日志无限增长。
func _append_log(line: String) -> void:
	_event_logs.append(line)
	while _event_logs.size() > 18:
		_event_logs.pop_front()


# 功能：清空选项列表。
# 说明：切换到新事件前先移除旧按钮和提示文本。
func _clear_option_list() -> void:
	for child in option_list.get_children():
		child.queue_free()


# 功能：添加选项区域提示文本。
# 说明：用于展示“无可见选项”等状态说明。
func _add_option_hint(text: String) -> void:
	var hint_label := Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.text = text
	option_list.add_child(hint_label)


# 功能：将历史事件数组转为字符串数组。
# 说明：统一处理 Variant 数组，确保可安全拼接为文本。
func _history_to_string_array(history: Array) -> Array[String]:
	var result: Array[String] = []
	for item in history:
		result.append(str(item))
	return result
