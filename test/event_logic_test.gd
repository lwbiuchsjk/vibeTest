extends Control

const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const TaskSummaryCard := preload("res://scripts/ui/task_summary_card.gd")
const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const WorldEndScreen := preload("res://scripts/ui/world_end_screen.gd")
const ResponsiveLayout := preload("res://scripts/ui/responsive_layout.gd")
const ButtonTheme := preload("res://scripts/ui/button_theme.gd")

const TEST_CONFIG_PATH := "res://test/event_logic_test_config.json"

var _engine: WorldEventEngine
var _event_logs: Array[String] = []
var _current_turn_result: Dictionary = {}
var _resizing := false              # 防止窗口尺寸调整时递归触发
# 主动押注切换状态：按选项 ID 记录各选项的押注模式（true=押注，false=默认）。
var _bet_mode_options: Dictionary = {}

@onready var screen_background: TextureRect = $ScreenBackground
@onready var root_margin: MarginContainer = $Root
@onready var right_column: VSplitContainer = $Root/RootContent/MainSplit/RightColumn
@onready var status_label: Label = $Root/RootContent/Header/StatusLabel
@onready var event_background_rect: TextureRect = $Root/RootContent/MainSplit/LeftPanel/LeftStack/EventBackground
@onready var character_panel: PanelContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/CharacterPanel
@onready var character_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/CharacterPanel/CharacterLabel
@onready var world_panel: PanelContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/WorldPanel
@onready var world_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/WorldPanel/WorldLabel
@onready var narrative_panel: PanelContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel
@onready var event_title_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel/NarrativeContent/EventTitle
@onready var event_detail_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel/NarrativeContent/EventDetail
@onready var option_header_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/OptionSection/OptionHeader
@onready var task_summary_card: TaskSummaryCard = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/TaskSummaryCard
@onready var main_split: HSplitContainer = $Root/RootContent/MainSplit
@onready var end_root: WorldEndScreen = $Root/RootContent/EndRoot
@onready var continue_button: Button = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/OptionSection/ActionBar/ContinueButton
@onready var option_list: VBoxContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/OptionSection/OptionScroll/OptionList
@onready var world_state_label: RichTextLabel = $Root/RootContent/MainSplit/RightColumn/RightPanel/RightMargin/RightContent/WorldStateValue
@onready var log_label: RichTextLabel = $Root/RootContent/MainSplit/RightColumn/BottomPanel/BottomMargin/BottomContent/LogValue


# 功能：初始化事件逻辑测试场景。
# 说明：加载配置后先预览首个事件，不在进入场景时立刻推进 world turn。
func _ready() -> void:
	continue_button.pressed.connect(_on_continue_button_pressed)
	end_root.action_requested.connect(_on_end_action_requested)
	_setup_overlay_styles()
	_setup_screen_background()
	# 响应式布局初始化：注册 viewport 监听并触发首次布局。
	ResponsiveLayout.setup(get_viewport(), _on_viewport_resized)
	var test_config := _load_test_config()
	_engine = WorldEventEngine.new(_get_test_random_seed(test_config))

	var load_result := _load_world_event_test_config(test_config)
	if not load_result.get("ok", false):
		status_label.text = "加载失败: %s" % str(load_result.get("error", "unknown"))
		return

	_append_log("测试环境启动，开始预览第一个事件。")
	_preview_next_event()


# 功能：预览下一个事件并停留在当前界面。
# 说明：预览阶段只展示事件内容，不执行结算，也不增加 world turn。
func _preview_next_event() -> void:
	_current_turn_result.clear()

	var turn_result := _engine.preview_next_turn()
	if not turn_result.get("ok", false):
		status_label.text = "事件预览失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	_handle_preview_turn_result(turn_result)


# 功能：统一处理预览结果。
# 说明：预览结果只负责记录日志、刷新当前缓存并渲染界面，不参与结算后的分流逻辑。
func _handle_preview_turn_result(turn_result: Dictionary) -> void:
	_current_turn_result = (turn_result as Dictionary).duplicate(true)
	_append_turn_log(turn_result)
	_render_current_event(turn_result)
	_update_side_panels()


# 功能：渲染当前事件。
# 说明：根据 phase 分别处理展示、选择、确认、心性风险入口等界面状态。
func _render_current_event(turn_result: Dictionary) -> void:
	if _is_world_ended_result(turn_result):
		_render_end_screen(turn_result)
		return

	var choice: Dictionary = turn_result.get("choice", {})
	var options: Array = choice.get("options", [])
	var phase := str(turn_result.get("phase", "confirm"))
	var presentation: Dictionary = turn_result.get("presentation", {})
	var presentation_item: Dictionary = presentation.get("current_item", {})
	var awaiting_choice := phase == "choice"
	# 进入新的选择阶段时重置各选项的押注切换状态
	if phase != "choice":
		_bet_mode_options.clear()

	_render_event_background(str(turn_result.get("resolved_background_art", "")))
	_set_end_screen_visible(false)
	_update_left_task_panel(turn_result)

	# 叙事面板：标题 + 展示文本 + 鉴定结果摘要
	event_title_label.text = str(turn_result.get("title", ""))
	var narrative_parts: Array[String] = []
	if phase == "presentation":
		var speaker := str(presentation_item.get("speaker", "")).strip_edges()
		var body := str(presentation_item.get("text", ""))
		if speaker.is_empty():
			narrative_parts.append(body)
		else:
			narrative_parts.append("%s: %s" % [speaker, body])
	var check_summary := _build_check_result_summary(turn_result)
	if not check_summary.is_empty():
		narrative_parts.append(check_summary)
	event_detail_label.text = "\n\n".join(narrative_parts)
	# 有标题或叙事内容时才显示叙事面板
	var has_narrative := not event_title_label.text.strip_edges().is_empty() or not narrative_parts.is_empty()
	narrative_panel.visible = has_narrative

	_clear_option_list()
	continue_button.visible = false
	continue_button.disabled = true
	if phase == "presentation":
		status_label.text = "当前处于展示阶段，点击继续查看下一条文本。"
		_add_continue_button_to_option_list("继续")
		return

	# 心性风险入口：孤注一掷
	if phase == "desperate_gamble":
		status_label.text = "鉴定失败，可以选择孤注一掷重新检定。"
		_render_risk_entry_buttons("孤注一掷：接受", "孤注一掷：放弃")
		return

	# 安全兜底：若引擎意外返回 preemptive_bet phase（正常流程由链式调用处理，不应到达此处），
	# 自动放弃押注并继续结算，避免 UI 卡死。
	if phase == "preemptive_bet":
		push_warning("preemptive_bet phase 未被链式调用消费，自动放弃押注。")
		var fallback_result := _engine.confirm_pending_turn("reject")
		_handle_resolved_turn_result(fallback_result, "自动放弃押注（兜底）")
		return

	# 自省事件：渲染自省交互界面。
	if phase == "reflection":
		_render_reflection_phase(turn_result)
		return

	if awaiting_choice:
		# 获取完整选项定义（含 check/cost/preemptiveBet）和心性风险配置。
		var risk_profile: Dictionary = turn_result.get("xinxing_risk_profile", {})
		var full_options := _get_full_option_defs_for_current_event()
		var any_bet_available := false
		for opt in full_options:
			if _can_option_trigger_bet(opt, risk_profile):
				any_bet_available = true
				break
		if any_bet_available:
			status_label.text = "等待选择：可切换主动押注模式获得额外鉴定骰。"
		else:
			status_label.text = "等待选择：点击下方任一可用选项。"
		_render_choice_options(full_options, risk_profile)
	else:
		status_label.text = "当前事件待确认，点击继续后结算并预览下一个事件。"
		_add_continue_button_to_option_list("确认结算，进入下一个事件")


# 功能：渲染心性风险入口的接受/放弃按钮对（孤注一掷专用）。
# 说明：两个按钮分别绑定 "accept" 和 "reject"，走正常的 confirm_pending_turn 分流。
func _render_risk_entry_buttons(accept_text: String, reject_text: String) -> void:
	_add_option_section_label("— 心性风险入口 —")

	var accept_button := Button.new()
	accept_button.text = accept_text
	accept_button.pressed.connect(_on_option_pressed.bind("accept"))
	ButtonTheme.apply(accept_button, ButtonTheme.PRESET_DESPERATE)
	option_list.add_child(accept_button)

	var reject_button := Button.new()
	reject_button.text = reject_text
	reject_button.pressed.connect(_on_option_pressed.bind("reject"))
	ButtonTheme.apply(reject_button)
	option_list.add_child(reject_button)


# ── 自省事件 UI ──────────────────────────────────────────────────

# 功能：渲染自省交互界面。
# 说明：根据 reflection_state 和 reflection_actions 渲染操作按钮列表。
func _render_reflection_phase(turn_result: Dictionary) -> void:
	var ref_state := str(turn_result.get("reflection_state", ""))
	var ref_actions: Array = turn_result.get("reflection_actions", [])
	var ops_remaining := int(turn_result.get("reflection_ops_remaining", 0))
	var ref_extra: Dictionary = turn_result.get("reflection_extra", {})

	# 状态机尚未启动（preview 阶段），显示入口按钮。
	if ref_state.is_empty():
		event_detail_label.text = "闭上眼，回想最近发生的事……"
		narrative_panel.visible = true
		status_label.text = "自省事件，点击开始进入自省。"
		var start_btn := Button.new()
		start_btn.text = "开始自省"
		start_btn.pressed.connect(_on_reflection_action_pressed.bind(""))
		ButtonTheme.apply(start_btn)
		option_list.add_child(start_btn)
		return

	# 叙事区：根据状态显示不同说明文本。
	var narrative_parts: Array[String] = []
	match ref_state:
		"EMPTY_REFLECTION":
			narrative_parts.append(str(ref_extra.get("text", "一切如常，没有特别值得回顾的事。")))
		"MAIN_MENU":
			narrative_parts.append("静下心来回顾最近发生的事情。")
			narrative_parts.append("剩余操作次数: %d" % ops_remaining)
		"ADJUST_RELATION":
			narrative_parts.append("回想与他人的交往，重新审视自己的态度。")
			narrative_parts.append("剩余操作次数: %d" % ops_remaining)
		"FOCUS_SELECT":
			narrative_parts.append("有些人值得更多关注。")
		"FOCUS_REMOVE":
			var pending := str(ref_extra.get("pending_add", ""))
			narrative_parts.append("关注已满，需要先移除一位已关注的人，才能关注 %s。" % pending)
		_:
			narrative_parts.append("自省中...")

	# 查询结果追加到叙事区。
	if ref_extra.has("query_result"):
		var qr: Dictionary = ref_extra["query_result"]
		narrative_parts.append("\n【查询结果】%s: 分值 %d, 档位 %s" % [
			str(qr.get("npc_id", "")),
			int(qr.get("current_score", 0)),
			str(qr.get("current_tier", ""))
		])

	# 操作结果追加到叙事区。
	if ref_extra.has("op_result"):
		var op_r: Dictionary = ref_extra["op_result"]
		narrative_parts.append("\n【操作结果】%s: %d → %s (%s)" % [
			str(op_r.get("npc_id", "")),
			int(op_r.get("new_score", 0)),
			str(op_r.get("new_tier", "")),
			"%+d" % int(op_r.get("delta", 0))
		])

	event_detail_label.text = "\n".join(narrative_parts)
	narrative_panel.visible = true

	# 状态栏。
	match ref_state:
		"EMPTY_REFLECTION":
			status_label.text = "空自省，点击确认继续。"
		"MAIN_MENU":
			status_label.text = "自省主菜单 | 剩余操作: %d" % ops_remaining
		"ADJUST_RELATION":
			status_label.text = "选择要调整关系的对象 | 剩余操作: %d" % ops_remaining
		"FOCUS_SELECT":
			status_label.text = "选择要关注的人"
		"FOCUS_REMOVE":
			status_label.text = "关注已满，选择要移除的人"
		_:
			status_label.text = "自省中"

	# 操作按钮。
	for action_variant in ref_actions:
		var action_def: Dictionary = action_variant
		var action_id := str(action_def.get("action", ""))
		var label_text := str(action_def.get("label", action_id))
		var enabled := bool(action_def.get("enabled", true))
		var target := str(action_def.get("target", ""))

		var encoded := "%s:%s" % [action_id, target]
		var btn := Button.new()
		btn.text = label_text
		btn.disabled = not enabled
		btn.pressed.connect(_on_reflection_action_pressed.bind(encoded))
		ButtonTheme.apply(btn)
		option_list.add_child(btn)


# 功能：处理自省操作按钮点击。
# 说明：将编码后的 "action:target" 传入 confirm_pending_turn，根据返回的 phase 分流。
func _on_reflection_action_pressed(encoded_action: String) -> void:
	var turn_result := _engine.confirm_pending_turn(encoded_action)
	if not turn_result.get("ok", false):
		status_label.text = "自省操作失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	# 解码操作信息用于日志。
	var parts: Array = encoded_action.split(":", true, 1)
	var action_name := str(parts[0]) if parts.size() > 0 else ""
	var action_target := str(parts[1]) if parts.size() > 1 else ""
	var log_text := "自省: %s" % action_name
	if not action_target.is_empty():
		log_text += " -> %s" % action_target
	_append_log(log_text)

	var phase := str(turn_result.get("phase", ""))
	if phase == "reflection":
		# 自省尚未结算，刷新界面继续交互。
		_current_turn_result = (turn_result as Dictionary).duplicate(true)
		_render_current_event(turn_result)
		_update_side_panels()
	else:
		# 自省已结算（phase = resolved），走统一结算后分流。
		_handle_resolved_turn_result(turn_result, "自省结算完成")


# ── 选项与押注 UI ────────────────────────────────────────────────

# 功能：从引擎内部获取当前事件的完整选项定义列表（含 check/cost/preemptiveBet）。
# 说明：UI 展示消耗与押注信息需要这些字段，公开 API 的简版结构不包含。
func _get_full_option_defs_for_current_event() -> Array:
	var event_id := str(_current_turn_result.get("event_id", ""))
	var event_def: Dictionary = _engine._event_map.get(event_id, {})
	var choice_point_id := str(event_def.get("choicePointId", "")).strip_edges()
	if choice_point_id.is_empty():
		return []
	var choice_point_def: Dictionary = _engine._choice_point_map.get(choice_point_id, {})
	if choice_point_def.is_empty():
		return []
	return _engine._build_option_set(choice_point_def)


# 功能：判断某个选项是否满足主动押注触发条件。
# 说明：条件与引擎 _apply_option_resolution 中一致：心性允许、选项含鉴定、未被 disabled。
func _can_option_trigger_bet(option_def: Dictionary, risk_profile: Dictionary) -> bool:
	if not bool(risk_profile.get("allow_preemptive_bet", false)):
		return false
	var check_raw: Variant = option_def.get("check", null)
	if typeof(check_raw) != TYPE_DICTIONARY or (check_raw as Dictionary).is_empty():
		return false
	var bet_cfg: Variant = option_def.get("preemptiveBet", null)
	var bet_disabled: bool = (typeof(bet_cfg) == TYPE_DICTIONARY and bool(bet_cfg.get("disabled", false)))
	if bet_disabled:
		return false
	if str(option_def.get("state", "disabled")) != "selectable":
		return false
	return true


# 功能：为指定选项构建主动押注信息（消耗、调整、是否可负担）。
# 说明：在 choice 阶段调用，读取选项定义和引擎全局默认合并后返回展示数据。
func _build_bet_info_for_option(option_def: Dictionary) -> Dictionary:
	var option_cost_raw: Variant = option_def.get("cost", null)
	var option_cost: Dictionary = option_cost_raw if typeof(option_cost_raw) == TYPE_DICTIONARY else {}
	var option_bet_cfg: Variant = option_def.get("preemptiveBet", null)
	var bet_cfg_dict: Dictionary = {}
	if typeof(option_bet_cfg) == TYPE_DICTIONARY:
		bet_cfg_dict = option_bet_cfg
	var effective_bet: Dictionary = _engine._merge_preemptive_bet_config(bet_cfg_dict)
	var bet_cost: Dictionary = effective_bet.get("cost", {})
	var bet_bias: Dictionary = effective_bet.get("bias", {})

	# 合并总消耗：选项 cost + 押注额外 cost，同名字段累加。
	var total_cost: Dictionary = {}
	for key in option_cost.keys():
		total_cost[str(key)] = int(option_cost[key])
	for key in bet_cost.keys():
		var k := str(key)
		total_cost[k] = int(total_cost.get(k, 0)) + int(bet_cost[key])

	# 构建消耗文本
	var cost_parts: Array[String] = []
	for key in total_cost.keys():
		var total := int(total_cost[key])
		var base := int(option_cost.get(key, 0))
		var extra := int(bet_cost.get(key, 0))
		if base > 0 and extra > 0:
			cost_parts.append("%s %d（基础 %d + 押注 %d）" % [str(key), total, base, extra])
		elif extra > 0:
			cost_parts.append("%s %d（押注消耗）" % [str(key), extra])
		else:
			cost_parts.append("%s %d" % [str(key), total])
	var cost_text := "无" if cost_parts.is_empty() else "、".join(cost_parts)

	# 构建调整文本
	var bias_parts: Array[String] = []
	var success_bias := int(bet_bias.get("successBias", 0))
	if success_bias != 0:
		bias_parts.append("+%d 鉴定骰" % success_bias if success_bias > 0 else "%d 鉴定骰" % success_bias)
	var bias_text := "无" if bias_parts.is_empty() else "、".join(bias_parts)

	var can_afford: bool = _engine._can_pay_bet_cost(bet_cost)

	return {"can_afford": can_afford, "cost_text": cost_text, "bias_text": bias_text}


# 功能：渲染选择阶段的选项列表，含鉴定选项支持默认/押注模式切换。
# 说明：遍历完整选项定义，对满足押注条件的选项渲染切换组件，其余渲染普通按钮。
func _render_choice_options(full_options: Array, risk_profile: Dictionary) -> void:
	var visible_count := 0
	for option_variant in full_options:
		var option_def: Dictionary = option_variant
		var state := str(option_def.get("state", "disabled"))
		if state == "invisible":
			continue

		visible_count += 1
		var option_id := str(option_def.get("id", ""))
		var can_bet := _can_option_trigger_bet(option_def, risk_profile)

		if can_bet:
			# 该选项支持主动押注，渲染带切换的选项组
			_render_option_with_bet_toggle(option_def, risk_profile)
		else:
			# 普通选项按钮
			var option_button := Button.new()
			option_button.text = _build_option_button_text(option_def)
			option_button.disabled = state != "selectable"
			option_button.pressed.connect(_on_option_pressed.bind(option_id))
			ButtonTheme.apply(option_button)
			option_list.add_child(option_button)

	if visible_count == 0:
		_add_option_hint("当前事件没有可见选项。")


# 功能：渲染单个支持主动押注的选项 — 根据当前切换状态显示默认或押注版本。
# 说明：选项按钮与切换按钮共用一个容器，切换按钮叠在选项按钮右侧上方，不额外占用列表空间。
func _render_option_with_bet_toggle(option_def: Dictionary, _risk_profile: Dictionary) -> void:
	var option_id := str(option_def.get("id", ""))
	var option_text := str(option_def.get("text", ""))
	var cost_raw: Variant = option_def.get("cost", null)
	var option_cost: Dictionary = cost_raw if typeof(cost_raw) == TYPE_DICTIONARY else {}
	var is_bet_mode: bool = bool(_bet_mode_options.get(option_id, false))

	# 构建选项按钮内容
	var confirm_button := Button.new()
	if is_bet_mode:
		# 押注模式：显示合并消耗和调整
		var bet_info := _build_bet_info_for_option(option_def)
		var can_afford := bool(bet_info.get("can_afford", true))
		var cost_text := str(bet_info.get("cost_text", ""))
		var bias_text := str(bet_info.get("bias_text", ""))
		var lines: Array[String] = [option_text]
		lines.append("    消耗: %s" % cost_text)
		lines.append("    调整: %s" % bias_text)
		if not can_afford:
			lines.append("    精力不足，无法发动押注")
		confirm_button.text = "\n".join(lines)
		confirm_button.disabled = not can_afford
		confirm_button.pressed.connect(_on_option_with_bet_pressed.bind(option_id, "accept"))
		ButtonTheme.apply(confirm_button, ButtonTheme.PRESET_BET)
	else:
		# 默认模式：显示原始选项消耗
		var lines: Array[String] = [option_text]
		if not option_cost.is_empty():
			var cost_parts: Array[String] = []
			for key in option_cost.keys():
				cost_parts.append("%s %d" % [str(key), int(option_cost[key])])
			lines.append("    消耗: %s" % "、".join(cost_parts))
		lines.append("    %s" % _build_option_state_text(option_def))
		confirm_button.text = "\n".join(lines)
		confirm_button.pressed.connect(_on_option_with_bet_pressed.bind(option_id, "reject"))
		ButtonTheme.apply(confirm_button)
	# 选项按钮右侧留出空间给切换按钮，避免文字被遮挡
	ButtonTheme.override_margin_right(confirm_button, 88)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 允许按钮高度随内容自适应（取消固定最小高度限制）
	confirm_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_button.custom_minimum_size.y = 0

	# 切换按钮：短文字，叠在选项按钮右侧，高度跟随选项按钮
	var toggle_button := Button.new()
	var toggle_text := "默认" if is_bet_mode else "押注"
	toggle_button.text = toggle_text
	toggle_button.pressed.connect(_on_bet_toggle_for_option.bind(option_id))
	ButtonTheme.apply(toggle_button, ButtonTheme.PRESET_TOGGLE)

	# 外层容器：HBoxContainer 让选项按钮自然撑高，切换按钮跟随高度
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	# 选项按钮占据剩余宽度
	wrapper.add_child(confirm_button)
	# 切换按钮固定宽度，高度跟随容器
	toggle_button.custom_minimum_size.x = 72
	toggle_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(toggle_button)
	option_list.add_child(wrapper)


# 功能：构建选项状态辅助文本（可选/不可选 + ID）。
func _build_option_state_text(option_def: Dictionary) -> String:
	var state := str(option_def.get("state", "disabled"))
	var id := str(option_def.get("id", ""))
	var state_marker := "● 可选" if state == "selectable" else "○ 不可选"
	return "%s    [%s]" % [state_marker, id]


# 功能：处理带押注决策的选项点击。
# 说明：链式调用引擎 — 先提交选项选择，引擎挂起到 preemptive_bet phase 后
#       立即自动提交押注决策（accept/reject），一步完成选项结算。
func _on_option_with_bet_pressed(option_id: String, bet_decision: String) -> void:
	if _current_turn_result.is_empty():
		status_label.text = "当前没有待处理的事件选择。"
		return

	# 第一步：提交选项选择 → 引擎扣 cost、挂起到 preemptive_bet phase
	var mid_result := _engine.confirm_pending_turn(option_id)
	if not mid_result.get("ok", false):
		status_label.text = "选项结算失败: %s" % str(mid_result.get("error", "unknown"))
		_update_side_panels()
		return

	# 确认引擎已进入 preemptive_bet phase
	var mid_phase := str(mid_result.get("phase", ""))
	if mid_phase != "preemptive_bet":
		# 未挂起（可能条件不满足），直接按普通结算处理
		var choice: Dictionary = mid_result.get("choice", {})
		var resolved_log := "已选择 %s -> %s | %s" % [
			str(choice.get("selected_option_id", "")),
			str(mid_result.get("event_id", "")),
			str(mid_result.get("title", ""))
		]
		_handle_resolved_turn_result(mid_result, resolved_log)
		return

	# 第二步：立即提交押注决策 → 引擎执行检定并完成结算
	var turn_result := _engine.confirm_pending_turn(bet_decision)
	if not turn_result.get("ok", false):
		status_label.text = "押注结算失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var choice: Dictionary = turn_result.get("choice", {})
	var bet_label := "押注" if bet_decision == "accept" else "默认"
	var resolved_log := "已选择 %s [%s] -> %s | %s" % [
		str(choice.get("selected_option_id", "")),
		bet_label,
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	_handle_resolved_turn_result(turn_result, resolved_log)


# 功能：处理单个选项的押注模式切换按钮点击。
# 说明：翻转该选项的 _bet_mode_options 状态后重新渲染当前事件界面。
func _on_bet_toggle_for_option(option_id: String) -> void:
	var current: bool = bool(_bet_mode_options.get(option_id, false))
	_bet_mode_options[option_id] = not current
	_render_current_event(_current_turn_result)


# 功能：构建鉴定结果摘要文本，用于追加到事件详情区。
# 说明：仅在 check_result 非空时返回内容，包含骰池明细和关系修正。
func _build_check_result_summary(turn_result: Dictionary) -> String:
	var check_result: Dictionary = turn_result.get("check_result", {})
	if check_result.is_empty():
		return ""
	var lines: Array[String] = []
	var result_type := str(check_result.get("result_type", ""))
	var is_pass := bool(check_result.get("pass", true))
	var is_gamble := bool(check_result.get("is_desperate_gamble", false))
	var prefix := "【孤注一掷重掷】" if is_gamble else "【鉴定结果】"
	lines.append("%s %s (%s)" % [prefix, result_type, "通过" if is_pass else "失败"])

	var pool_size := int(check_result.get("pool_size", 0))
	if pool_size > 0:
		var dice: Array = check_result.get("dice", [])
		var hits := int(check_result.get("hits", 0))
		var required_hits := int(check_result.get("requiredHits", 1))
		lines.append("骰池: %dd10  骰面: %s  命中: %d/%d" % [pool_size, str(dice), hits, required_hits])

	# 关系修正摘要
	var rel_details: Array = check_result.get("relationship_details", [])
	for rel_entry_variant in rel_details:
		var rel_entry: Dictionary = rel_entry_variant
		var npc_id := str(rel_entry.get("npc_id", ""))
		var detail: Dictionary = rel_entry.get("detail", {})
		var bias := int(detail.get("bias", 0))
		var npc_tier := str(detail.get("npc_tier", ""))
		var direction := str(detail.get("direction", ""))
		lines.append("关系修正: %s (%s, %s) bias=%+d" % [npc_id, npc_tier, direction, bias])

	# 心性转移摘要
	var transition: Dictionary = turn_result.get("xinxing_transition", {})
	if not transition.is_empty():
		lines.append("心性转移: %d → %d" % [
			int(transition.get("old_value", 0)),
			int(transition.get("new_value", 0))
		])

	return "\n".join(lines)


# 功能：处理玩家点击选项。
# 说明：先结算当前待处理事件，再统一走结果分流入口，避免结束态判断散落在多个回调里。
func _on_option_pressed(option_id: String) -> void:
	if _current_turn_result.is_empty():
		status_label.text = "当前没有待处理的事件选择。"
		return

	var turn_result := _engine.confirm_pending_turn(option_id)
	if not turn_result.get("ok", false):
		status_label.text = "选项结算失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var choice: Dictionary = turn_result.get("choice", {})
	var resolved_log := "已选择 %s -> %s | %s" % [
		str(choice.get("selected_option_id", "")),
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	_handle_resolved_turn_result(turn_result, resolved_log)


# 功能：处理继续指令。
# 说明：展示阶段点击继续只推进到下一条展示文本；确认阶段点击继续才会真正结算当前事件。
func _on_continue_button_pressed() -> void:
	if _current_turn_result.is_empty():
		_preview_next_event()
		return
	var current_phase := str(_current_turn_result.get("phase", "confirm"))
	if current_phase == "choice":
		status_label.text = "当前事件需要先完成选项选择。"
		return
	if current_phase == "reflection":
		status_label.text = "自省进行中，请通过自省操作按钮交互。"
		return

	var turn_result := _engine.confirm_pending_turn()
	if not turn_result.get("ok", false):
		status_label.text = "事件结算失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var resolved_log := "已确认继续 -> %s | %s" % [
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	_handle_resolved_turn_result(turn_result, resolved_log)


# 功能：统一处理已结算的回合结果。
# 说明：将日志、鉴定摘要、关系变化、结束态分流、侧栏刷新和下一次预览收口到一个入口。
func _handle_resolved_turn_result(turn_result: Dictionary, resolved_log: String) -> void:
	_append_log(resolved_log)
	# 鉴定结果日志
	_append_check_result_log(turn_result)
	# 关系变化日志
	_append_affinity_changes_log(turn_result)
	# 心性转移日志
	_append_xinxing_transition_log(turn_result)

	_current_turn_result = (turn_result as Dictionary).duplicate(true)
	if _is_world_ended_result(turn_result):
		_append_end_log(turn_result)
		_render_current_event(turn_result)
		_update_side_panels()
		return

	_update_side_panels()
	_preview_next_event()


# 功能：构建当前事件的调试元数据文本，用于右侧面板展示。
# 说明：展示背景、route、policy、phase、展示进度与当前 world turn，便于核对”展示后结算”的推进时机。
func _build_event_debug_text(turn_result: Dictionary) -> String:
	var choice: Dictionary = turn_result.get("choice", {})
	var presentation: Dictionary = turn_result.get("presentation", {})
	var lines: Array[String] = []
	lines.append("event_background_art=%s" % str(turn_result.get("event_background_art", "")))
	lines.append("location_background_art=%s" % str(turn_result.get("location_background_art", "")))
	lines.append("resolved_background_art=%s" % str(turn_result.get("resolved_background_art", "")))
	lines.append("route=%s" % str(turn_result.get("route", "")))
	lines.append("policy=%s" % str(turn_result.get("policy", "")))
	lines.append("phase=%s" % str(turn_result.get("phase", "")))
	lines.append(
		"presentation=%s/%s" % [
			str(int(presentation.get("index", -1)) + 1 if bool(presentation.get("active", false)) else 0),
			str(presentation.get("total", 0))
		]
	)
	lines.append("choice_point=%s" % str(choice.get("choice_point_id", "")))
	lines.append("chain_active=%s" % str(turn_result.get("chain_active", false)))
	lines.append("world_turn=%s" % str(_engine.world_state.get("turn", 0)))
	lines.append("run_status=%s" % str(turn_result.get("run_status", "")))
	lines.append("world_ended=%s" % str(turn_result.get("world_ended", false)))
	lines.append("ending_event_id=%s" % str(turn_result.get("ending_event_id", "")))
	lines.append("finished_turn=%s" % str(turn_result.get("finished_turn", 0)))
	# 自省调试信息。
	if turn_result.has("reflection_state"):
		lines.append("reflection_state=%s" % str(turn_result.get("reflection_state", "")))
		lines.append("reflection_ops_remaining=%s" % str(turn_result.get("reflection_ops_remaining", 0)))
	return "\n".join(lines)


# 功能：生成选项按钮文本。
# 说明：主文本居前，ID 和状态标签放在第二行辅助区，方便一眼看清内容再核对元数据。
func _build_option_button_text(option_def: Dictionary) -> String:
	var state := str(option_def.get("state", "disabled"))
	var text := str(option_def.get("text", ""))
	var id := str(option_def.get("id", ""))
	var state_marker := "● 可选" if state == "selectable" else "○ 不可选"
	# 主文本 + 辅助信息行
	return "%s\n    %s    [%s]" % [text, state_marker, id]


# 功能：刷新左侧任务摘要面板。
# 说明：将进行中的任务和当前事件关联任务交给独立 UI 组件渲染，测试场景只负责准备数据。
func _update_left_task_panel(turn_result: Dictionary) -> void:
	var world_state := _engine.world_state
	var tasks_state: Dictionary = world_state.get("tasks", {})
	var active: Array = tasks_state.get("active", [])
	var current_turn := int(world_state.get("turn", 0))
	var event_id := str(turn_result.get("event_id", "")).strip_edges()
	var event_def: Dictionary = _engine._event_map.get(event_id, {})
	var task_links: Array = event_def.get("taskLinks", [])
	task_summary_card.bind_data(active, task_links, current_turn)


# 功能：刷新左侧角色/世界面板 + 右侧调试面板 + 底部日志。
# 说明：角色与世界信息展示在左侧背景图上方；右侧只保留调试/参考数据（事件元数据、关系、运行态、任务明细、历史）。
func _update_side_panels() -> void:
	var world_state := _engine.world_state
	var player: Dictionary = world_state.get("player", {})
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	var run_state: Dictionary = world_state.get("runState", {})
	var chain_context: Variant = world_state.get("chainContext", null)
	var history: Array = world_state.get("history", [])
	var task_config: Dictionary = world_state.get("taskConfig", {})
	var tasks_state: Dictionary = world_state.get("tasks", {})
	var xinxing_tracker: Dictionary = world_state.get("xinxingTracker", {})

	# ── 左侧：角色面板 ──
	_update_character_panel(player, xinxing_tracker)
	# ── 左侧：世界面板 ──
	_update_world_panel(world_state, params)

	# ── 右侧：调试/参考信息 ──
	var lines: Array[String] = []

	# 当前事件元数据
	if not _current_turn_result.is_empty():
		lines.append("═══ 当前事件 ═══")
		lines.append(_build_event_debug_text(_current_turn_result))
		lines.append("")

	# 关系
	var affinity_text := _build_affinity_display_text()
	if not affinity_text.is_empty():
		lines.append("═══ 关系 ═══")
		lines.append(affinity_text)
		lines.append("")

	# 运行态与标记
	lines.append("═══ 运行态 ═══")
	var flag_parts: Array[String] = []
	for flag_key in flags.keys():
		flag_parts.append("%s=%s" % [str(flag_key), str(flags[flag_key])])
	if not flag_parts.is_empty():
		lines.append("标记: %s" % "  ".join(flag_parts))
	lines.append(
		"status=%s  ending=%s  finished_turn=%s" % [
			str(run_state.get("status", "")),
			str(run_state.get("endingEventId", "")),
			str(run_state.get("finishedTurn", 0))
		]
	)
	if world_state.get("forcedNextEventId", "") != "":
		lines.append("强制下一事件: %s" % str(world_state.get("forcedNextEventId", "")))
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		lines.append("链上下文: %s" % JSON.stringify(chain_context))

	# 任务明细
	lines.append("")
	lines.append(_build_task_debug_text(task_config, tasks_state))

	# 最近历史
	lines.append("")
	lines.append("═══ 最近历史 ═══")
	lines.append(", ".join(_history_to_string_array(history)))

	world_state_label.text = "\n".join(lines)
	world_state_label.call_deferred("scroll_to_line", 0)
	log_label.text = "\n".join(_event_logs)


# 功能：更新左侧角色面板。
# 说明：用紧凑的两行展示资源和四维能力，心性单独标注。
func _update_character_panel(player: Dictionary, xinxing_tracker: Dictionary) -> void:
	var xinxing := int(player.get("xinxing", 0))
	var steady := int(xinxing_tracker.get("steady_count", 0))
	var gamble := int(xinxing_tracker.get("gamble_count", 0))
	var hp := int(player.get("hp", 0))
	var energy := int(player.get("energy", 0))
	var gold := int(player.get("gold", 0))

	var line1 := "生命 %d    精力 %d    金币 %d    ┃    心性 %d（稳健%d / 孤注%d）" % [
		hp, energy, gold, xinxing, steady, gamble
	]
	var line2 := _build_ability_display_text()
	character_label.text = "%s\n%s" % [line1, line2]


# 功能：更新左侧世界面板。
# 说明：回合、地点与三大参数紧凑排列，一眼可读。
func _update_world_panel(world_state: Dictionary, params: Dictionary) -> void:
	var turn := int(world_state.get("turn", 0))
	var location := str(world_state.get("currentLocationId", ""))
	var danger := int(params.get("danger", 0))
	var prosperity := int(params.get("prosperity", 0))
	var morale := int(params.get("morale", 0))

	world_label.text = "回合 %d    地点 %s    ┃    危险 %d    繁荣 %d    士气 %d" % [
		turn, location, danger, prosperity, morale
	]


# 功能：构建四大能力的展示文本，包含原始值和鉴定阶段。
# 说明：用紧凑的 "名称 数值·阶段N" 格式，横向排列四个能力。
func _build_ability_display_text() -> String:
	if _engine.player_role_state == null:
		return "能力数据缺失"
	var role: RoleState = _engine.player_role_state
	var thresholds: Array = _engine.get_assessment_thresholds()
	var ability_keys := ["aptitude", "physique", "craft", "insight"]
	var ability_names := {"aptitude": "资质", "physique": "体魄", "craft": "技艺", "insight": "见识"}
	var parts: Array[String] = []
	for key in ability_keys:
		var value := int(role.get_attribute(key, 0))
		var stage := RuleEngine.get_ability_stage(value, thresholds)
		parts.append("%s %d · 阶段%d" % [str(ability_names.get(key, key)), value, stage])
	return "    ".join(parts)


# 功能：构建关系面板展示文本。
# 说明：遍历 affinity_map 所有关系对，按 from→to 格式列出分值和档位。
func _build_affinity_display_text() -> String:
	var snapshot: Array = _engine.get_affinity_snapshot()
	if snapshot.is_empty():
		return ""
	var lines: Array[String] = []
	for pair_variant in snapshot:
		var pair: Dictionary = pair_variant
		lines.append("%s→%s: %d (%s)" % [
			str(pair.get("from", "")),
			str(pair.get("to", "")),
			int(pair.get("score", 0)),
			str(pair.get("tier", ""))
		])
	return "\n".join(lines)


# 功能：判断当前返回结果是否代表世界结束。
# 说明：统一消费引擎公开字段，避免界面层自行依赖内部 world_state 细节推断 ended。
func _is_world_ended_result(turn_result: Dictionary) -> bool:
	return bool(turn_result.get("world_ended", false)) \
		or str(turn_result.get("run_status", "")).strip_edges() == "ended" \
		or str(turn_result.get("phase", "")).strip_edges() == "ended"


# 功能：渲染世界结束界面。
# 说明：结束后切换到独立页面，隐藏事件交互区，保留终局事件与结束态摘要供手动验收。
func _render_end_screen(turn_result: Dictionary) -> void:
	_set_end_screen_visible(true)
	var ending_model := _build_end_screen_model(turn_result)
	end_root.render_model(ending_model)
	status_label.text = "本轮已结束，当前显示终局结果页。"


# 功能：切换结束界面的显示状态。
# 说明：非结束态时恢复原事件测试界面，避免结束页与事件页同时可见。
func _set_end_screen_visible(visible: bool) -> void:
	end_root.visible = visible
	main_split.visible = not visible


# 功能：构建结束界面的展示文本。
# 说明：聚合终局事件返回、world_state.runState 与关键世界摘要，便于人工核对结束封口是否正确。
func _build_end_summary_text(turn_result: Dictionary, ending_title: String) -> String:
	var world_state := _engine.world_state
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	var lines: Array[String] = []
	lines.append("你在第 %s 回合迎来了“%s”。" % [
		str(turn_result.get("finished_turn", 0)),
		ending_title
	])
	lines.append("")
	lines.append(
		"最终数值：danger=%s  prosperity=%s  morale=%s" % [
			str(params.get("danger", 0)),
			str(params.get("prosperity", 0)),
			str(params.get("morale", 0))
		]
	)
	lines.append(
		"关键标记：isWanted=%s  gotHarborIntel=%s" % [
			str(flags.get("isWanted", false)),
			str(flags.get("gotHarborIntel", false))
		]
	)
	lines.append("")
	lines.append("如需继续验证，请重新进入场景开始下一轮。")
	return "\n".join(lines)


# 功能：构建结束界面的视图模型。
# 说明：将终局页需要的数据先收束成稳定结构，后续挂接流程按钮或切换数据源时只扩展 model，不直接改渲染主链。
func _build_end_screen_model(turn_result: Dictionary) -> Dictionary:
	var ending_event_id := _resolve_end_event_id(turn_result)
	var ending_title := _resolve_end_event_title(turn_result, ending_event_id)
	return {
		"title": ending_title,
		"subtitle": "本轮流程已正式结束。以下是本次测试最关键的结果摘要。",
		"endingEventId": ending_event_id,
		"finishedTurn": int(turn_result.get("finished_turn", 0)),
		"taskSummary": _build_end_task_summary(),
		"stateSummary": _build_end_state_summary(),
		"summaryText": _build_end_summary_text(turn_result, ending_title),
		"actions": []
	}


# 功能：响应终局页动作请求。
# 说明：当前先记录占位日志，后续若接入重开、切配置或进入下一流程，可在这里统一分发。
func _on_end_action_requested(action_id: String) -> void:
	_append_log("终局页动作触发: %s" % action_id)


# 功能：记录世界结束日志。
# 说明：结束态单独加一条高优先级日志，便于从底部日志快速确认终局已经命中。
func _append_end_log(turn_result: Dictionary) -> void:
	_append_log(
		"世界结束 | ending_event=%s | finished_turn=%s" % [
			str(turn_result.get("ending_event_id", "")),
			str(turn_result.get("finished_turn", 0))
		]
	)


# 功能：将鉴定结果写入日志，展示骰池明细与关系修正。
# 说明：仅在 check_result 非空时输出，避免无检定事件产生空日志。
func _append_check_result_log(turn_result: Dictionary) -> void:
	var check_result: Dictionary = turn_result.get("check_result", {})
	if check_result.is_empty():
		return
	var result_type := str(check_result.get("result_type", ""))
	var is_pass := bool(check_result.get("pass", true))
	var pool_size := int(check_result.get("pool_size", 0))
	var dice: Array = check_result.get("dice", [])
	var hits := int(check_result.get("hits", 0))
	var required_hits := int(check_result.get("requiredHits", 1))
	var is_gamble := bool(check_result.get("is_desperate_gamble", false))
	var prefix := "孤注一掷重掷" if is_gamble else "鉴定"
	if pool_size > 0:
		_append_log(
			"%s | %s(%s) | 骰池:%dd10 骰面:%s 命中:%d/%d" % [
				prefix, result_type, "通过" if is_pass else "失败",
				pool_size, str(dice), hits, required_hits
			]
		)
	else:
		_append_log("%s | %s(%s)" % [prefix, result_type, "通过" if is_pass else "失败"])

	# 关系修正明细
	var rel_details: Array = check_result.get("relationship_details", [])
	for rel_entry_variant in rel_details:
		var rel_entry: Dictionary = rel_entry_variant
		var npc_id := str(rel_entry.get("npc_id", ""))
		var detail: Dictionary = rel_entry.get("detail", {})
		var bias := int(detail.get("bias", 0))
		if bias == 0:
			continue
		_append_log(
			"  关系修正 | %s | 档位:%s | 方向:%s | 对齐:%s | bias:%+d" % [
				npc_id,
				str(detail.get("npc_tier", "")),
				str(detail.get("direction", "")),
				str(detail.get("aligned", false)),
				bias
			]
		)


# 功能：将关系变化写入日志。
# 说明：仅在 affinity_changes 非空时输出。
func _append_affinity_changes_log(turn_result: Dictionary) -> void:
	var changes: Array = turn_result.get("affinity_changes", [])
	if changes.is_empty():
		return
	var parts: Array[String] = []
	for change_variant in changes:
		var change: Dictionary = change_variant
		parts.append("%s→%s: %+d (%d→%d, %s)" % [
			str(change.get("from", "")),
			str(change.get("to", "")),
			int(change.get("delta", 0)),
			int(change.get("old_score", 0)),
			int(change.get("new_score", 0)),
			str(change.get("new_tier", ""))
		])
	_append_log("关系变化 | %s" % " | ".join(parts))


# 功能：将心性转移写入日志。
func _append_xinxing_transition_log(turn_result: Dictionary) -> void:
	var transition: Dictionary = turn_result.get("xinxing_transition", {})
	if transition.is_empty():
		return
	_append_log("心性转移 | %d → %d" % [
		int(transition.get("old_value", 0)),
		int(transition.get("new_value", 0))
	])


# 功能：解析终局事件 id。
# 说明：优先使用引擎返回字段；若 ended 短路返回未携带 event_id，则回退读取 world_state.runState。
func _resolve_end_event_id(turn_result: Dictionary) -> String:
	var ending_event_id := str(turn_result.get("ending_event_id", "")).strip_edges()
	if not ending_event_id.is_empty():
		return ending_event_id
	var run_state: Dictionary = _engine.world_state.get("runState", {})
	return str(run_state.get("endingEventId", "")).strip_edges()


# 功能：解析终局事件标题。
# 说明：resolved 结果通常自带 title；若当前是 ended 短路返回，则通过 event_id 回查事件定义。
func _resolve_end_event_title(turn_result: Dictionary, ending_event_id: String) -> String:
	var title := str(turn_result.get("title", "")).strip_edges()
	if not title.is_empty():
		return title
	var event_def: Dictionary = _engine._event_map.get(ending_event_id, {})
	title = str(event_def.get("title", "")).strip_edges()
	if not title.is_empty():
		return title
	return "本轮已结束"


# 功能：构建任务结果摘要。
# 说明：终局页只显示必要统计，不再展开完整任务调试明细。
func _build_end_task_summary() -> String:
	var tasks_state: Dictionary = _engine.world_state.get("tasks", {})
	return "完成 %s / 失败 %s / 放弃 %s" % [
		str((tasks_state.get("completed", []) as Array).size()),
		str((tasks_state.get("failed", []) as Array).size()),
		str((tasks_state.get("abandoned", []) as Array).size())
	]


# 功能：构建最终状态摘要卡片。
# 说明：将最影响结果理解的状态压缩成一行，避免终局界面退化成调试面板。
func _build_end_state_summary() -> String:
	var world_state := _engine.world_state
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	return "danger=%s | morale=%s | wanted=%s" % [
		str(params.get("danger", 0)),
		str(params.get("morale", 0)),
		str(flags.get("isWanted", false))
	]


# 功能：构建任务调试信息文本。
# 说明：将任务配置、进行中任务、归档结果和最近结算记录整理成多行文本，便于在测试场景中直接观察任务推进。
func _build_task_debug_text(task_config: Dictionary, tasks_state: Dictionary) -> String:
	var lines: Array[String] = []
	var active: Array = tasks_state.get("active", [])
	var completed: Array = tasks_state.get("completed", [])
	var failed: Array = tasks_state.get("failed", [])
	var abandoned: Array = tasks_state.get("abandoned", [])
	var result_records: Array = tasks_state.get("resultRecords", [])

	lines.append("任务状态")
	lines.append("maxActiveCount=%s" % str(task_config.get("maxActiveCount", 1)))
	lines.append("active_count=%s" % str(active.size()))
	lines.append("completed=%s" % JSON.stringify(completed))
	lines.append("failed=%s" % JSON.stringify(failed))
	lines.append("abandoned=%s" % JSON.stringify(abandoned))
	lines.append("")

	lines.append("进行中任务")
	if active.is_empty():
		lines.append("无")
	else:
		for task_variant in active:
			var task: Dictionary = task_variant
			lines.append(
				"- %s | accepted=%s | deadline=%s | progress=%s" % [
					str(task.get("taskId", "")),
					str(task.get("acceptedTurn", 0)),
					str(task.get("deadlineTurn", 0)),
					JSON.stringify(task.get("progress", {}))
				]
			)

	lines.append("")
	lines.append("最近任务结算")
	if result_records.is_empty():
		lines.append("无")
	else:
		# 说明：仅展示最近 5 条结算记录，避免右侧调试面板被历史数据完全占满。
		for idx in range(maxi(0, result_records.size() - 5), result_records.size()):
			var record: Dictionary = result_records[idx]
			lines.append(
				"- %s | status=%s | grade=%s | score=%s | finished=%s | reason=%s | progress=%s" % [
					str(record.get("taskId", "")),
					str(record.get("status", "")),
					str(record.get("gradeId", "")),
					str(record.get("score", null)),
					str(record.get("finishedTurn", 0)),
					str(record.get("reason", "")),
					JSON.stringify(record.get("progress", {}))
				]
			)

	return "\n".join(lines)


# 功能：记录每次事件预览日志。
# 说明：将展示阶段、等待选择、等待确认显式写入日志，便于核对界面状态与引擎 phase 是否一致。
func _append_turn_log(turn_result: Dictionary) -> void:
	var phase := str(turn_result.get("phase", "confirm"))
	var line := "Turn %s | %s | %s | route=%s | policy=%s | background=%s" % [
		str(_engine.world_state.get("turn", 0)),
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", "")),
		str(turn_result.get("route", "")),
		str(turn_result.get("policy", "")),
		str(turn_result.get("resolved_background_art", ""))
	]
	if phase == "presentation":
		line += " | 展示阶段"
	elif turn_result.get("awaiting_choice", false):
		line += " | 等待选择"
	else:
		line += " | 等待确认"
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


# 功能：在选项列表中动态创建"继续"按钮，复用统一样式。
# 说明：替代场景中静态 ContinueButton，使继续操作与选项按钮视觉一致。
func _add_continue_button_to_option_list(label_text: String) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.pressed.connect(_on_continue_button_pressed)
	ButtonTheme.apply(btn)
	option_list.add_child(btn)


# 功能：在选项列表中插入分隔标签。
# 说明：用于区分普通选项和特殊入口（押注、孤注一掷等）。
func _add_option_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	option_list.add_child(label)


# 功能：添加选项区域提示文本。
# 说明：用于展示”无可见选项”等状态说明。
func _add_option_hint(text: String) -> void:
	var hint_label := Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1.0))
	option_list.add_child(hint_label)


# 功能：初始化左侧叠加层各区域的半透明样式。
# 说明：所有覆盖在背景图上的面板统一使用半透明深色底 + 圆角，确保在图上可读。
func _setup_overlay_styles() -> void:
	# 通用半透明面板样式工厂
	var base_panel_style := StyleBoxFlat.new()
	base_panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.65)
	base_panel_style.corner_radius_top_left = 8
	base_panel_style.corner_radius_top_right = 8
	base_panel_style.corner_radius_bottom_left = 8
	base_panel_style.corner_radius_bottom_right = 8
	base_panel_style.content_margin_left = 14
	base_panel_style.content_margin_right = 14
	base_panel_style.content_margin_top = 10
	base_panel_style.content_margin_bottom = 10

	# 角色面板
	character_panel.add_theme_stylebox_override("panel", base_panel_style)
	character_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82, 0.95))
	character_label.add_theme_font_size_override("font_size", 13)

	# 世界面板
	var world_style: StyleBoxFlat = base_panel_style.duplicate()
	world_style.bg_color = Color(0.04, 0.06, 0.10, 0.60)
	world_panel.add_theme_stylebox_override("panel", world_style)
	world_label.add_theme_color_override("font_color", Color(0.80, 0.85, 0.92, 0.90))
	world_label.add_theme_font_size_override("font_size", 13)

	# 叙事面板
	var narrative_style: StyleBoxFlat = base_panel_style.duplicate()
	narrative_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	narrative_style.content_margin_left = 16
	narrative_style.content_margin_right = 16
	narrative_style.content_margin_top = 12
	narrative_style.content_margin_bottom = 12
	narrative_panel.add_theme_stylebox_override("panel", narrative_style)
	event_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	event_detail_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90, 0.9))

	# 选项区标题
	option_header_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 0.9))


# 功能：初始化全屏装饰衬底。
# 说明：优先加载美术资源作为窗口超宽时的侧边装饰；未找到资源时用深色渐变兜底。
func _setup_screen_background() -> void:
	# 尝试加载装饰衬底贴图（可替换为任意美术资源路径）
	var bg_path := "res://assets/art/environments/backgrounds/town.svg"
	var bg_res: Variant = ResourceLoader.load(bg_path)
	if bg_res is Texture2D:
		screen_background.texture = bg_res
		screen_background.modulate = Color(0.25, 0.25, 0.30, 1.0)
	else:
		# 兜底：无贴图时用纯深色，通过 modulate 控制
		screen_background.texture = null
	# 确保衬底始终处于最底层
	screen_background.show_behind_parent = true


# 功能：响应视口尺寸变化，委托 ResponsiveLayout 计算后应用业务层布局。
# 说明：三阶段布局计算由工具库完成，本方法只负责业务响应（右栏显隐、衬底显隐）。
func _on_viewport_resized() -> void:
	if _resizing:
		return
	_resizing = true

	var layout := ResponsiveLayout.calc_layout(get_viewport())

	# 阶段1：比例锁定
	ResponsiveLayout.apply_aspect_lock(layout)

	# 阶段2：右栏显隐 — 高度触顶后宽度自由，右栏出现
	right_column.visible = bool(layout.get("height_capped", false))

	# 阶段3：超宽居中 margin + 装饰衬底显隐
	ResponsiveLayout.apply_margins(root_margin, layout)
	screen_background.visible = bool(layout.get("is_ultrawide", false))

	_resizing = false


# 功能：渲染当前事件背景图。
# 说明：只消费引擎已解析好的最终背景路径；Consumer 不再自行实现事件/地点 fallback 规则。
func _render_event_background(background_art_path: String) -> void:
	var normalized_path := background_art_path.strip_edges()
	if normalized_path.is_empty():
		event_background_rect.texture = null
		return

	var resource := ResourceLoader.load(normalized_path)
	if resource is Texture2D:
		event_background_rect.texture = resource
	else:
		event_background_rect.texture = null


# 功能：将历史事件数组转为字符串数组。
# 说明：统一处理 Variant 数组，确保可安全拼接为文本。
func _history_to_string_array(history: Array) -> Array[String]:
	var result: Array[String] = []
	for item in history:
		result.append(str(item))
	return result


# 功能：读取测试场景的配置文件。
# 说明：仅测试场景使用该配置；当配置缺失或格式异常时，回退为空配置。
func _load_test_config() -> Dictionary:
	if not FileAccess.file_exists(TEST_CONFIG_PATH):
		return {}

	var config_text := FileAccess.get_file_as_string(TEST_CONFIG_PATH)
	if config_text.strip_edges().is_empty():
		return {}

	var parsed_config: Variant = JSON.parse_string(config_text)
	if typeof(parsed_config) != TYPE_DICTIONARY or parsed_config == null:
		return {}

	return parsed_config


# 功能：读取测试场景的随机种子配置。
# 说明：当配置缺失、格式错误或不是非负整数时，回退为 0 以启用随机种子。
func _get_test_random_seed(test_config: Dictionary) -> int:
	var raw_seed: Variant = test_config.get("random_seed", 0)
	var seed_text := str(raw_seed).strip_edges()
	if seed_text.is_empty() or not seed_text.is_valid_int():
		return 0

	var seed := int(seed_text)
	if seed < 0:
		return 0
	return seed


# 功能：按测试配置加载世界事件 CSV 数据。
# 说明：CSV 目录选择交由测试配置显式控制，但实际加载、编译与缓存仍统一走 ConfigRuntime。
func _load_world_event_test_config(test_config: Dictionary) -> Dictionary:
	var runtime := ConfigRuntime.shared()
	var override_paths: Dictionary = {}
	var csv_dir := str(test_config.get("world_event_csv_dir", "")).strip_edges()
	if not csv_dir.is_empty():
		override_paths["world_event_csv_dir"] = csv_dir

	var load_result := runtime.ensure_loaded(override_paths)
	if not load_result.get("ok", false):
		return load_result

	var world_event_data := runtime.get_world_event_data()
	if world_event_data.is_empty():
		return {"ok": false, "error": "world event config is empty in config runtime"}

	var context_result := runtime.build_context()
	var location_graph = null
	if context_result.get("ok", false):
		location_graph = context_result.get("graph", null)

	# 从 ConfigRuntime 获取玩家 RoleState，通过 load_from_data 统一注入。
	var p_role_state: Variant = null
	var roles: Array = runtime.get_roles()
	for role_variant in roles:
		if role_variant != null and role_variant.role_type == "player":
			p_role_state = role_variant
			break

	return _engine.load_from_data(world_event_data, location_graph, p_role_state)
