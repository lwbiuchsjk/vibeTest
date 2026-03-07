extends RefCounted
class_name WorldEventEngine

# 功能：世界与事件引擎（MVP）。
# 说明：单一主循环推进，forcedNextEventId 优先级最高，链式通过 chainContext 塑形分布。
const POLICY_RETURN := "ReturnToScheduler"
const POLICY_CHAIN := "ChainContinue"
const POLICY_CHAIN_FORCED := "ChainContinueWithForcedNext"
const TASK_BIAS_ADVANCE_DEFAULT := 6
const TASK_BIAS_RISK_DEFAULT := -4
const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")

var world_state: Dictionary = {}
var events: Array = []
var choice_points: Array = []
var task_defs: Array = []
var task_evaluation: Dictionary = {}
var _event_map: Dictionary = {}
var _choice_point_map: Dictionary = {}
var _task_def_map: Dictionary = {}
var _task_eval_index_by_task: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pending_turn_context: Dictionary = {}
var _location_graph: LocationGraph

# 功能：初始化随机源。
# 说明：seed=0 使用随机种子；指定 seed 可复现结果，便于测试回归。
func _init(random_seed: int = 0) -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

# 功能：从 JSON 文件加载 world_state、events、choice_points。
# 说明：返回统一结构 {"ok": bool, "error": String?}。
func load_from_files(
	world_state_path: String,
	events_path: String,
	choice_points_path: String = ""
) -> Dictionary:
	var world_text := FileAccess.get_file_as_string(world_state_path)
	if world_text.is_empty():
		return {"ok": false, "error": "world state file is empty or missing: %s" % world_state_path}

	var events_text := FileAccess.get_file_as_string(events_path)
	if events_text.is_empty():
		return {"ok": false, "error": "events file is empty or missing: %s" % events_path}

	var choice_points_text := ""
	if not choice_points_path.strip_edges().is_empty():
		choice_points_text = FileAccess.get_file_as_string(choice_points_path)
		if choice_points_text.is_empty():
			return {"ok": false, "error": "choice points file is empty or missing: %s" % choice_points_path}

	return load_from_json_text(world_text, events_text, choice_points_text)

# 功能：从 CSV 配置目录加载 world_state、events、choice_points。
# 说明：统一通过 ConfigRuntime 管理配置加载与缓存，避免引擎层直接编译 CSV。
func load_from_csv_dir(csv_dir_path: String) -> Dictionary:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded({"world_event_csv_dir": csv_dir_path})
	if not load_result.get("ok", false):
		return load_result
	var context_result := runtime.build_context()
	if context_result.get("ok", false):
		_location_graph = context_result.get("graph", null)
	else:
		_location_graph = null
	var world_event_data := runtime.get_world_event_data()
	if world_event_data.is_empty():
		return {"ok": false, "error": "world event config is empty in config runtime"}
	return load_from_data(world_event_data, _location_graph)

# 功能：从 JSON 文本加载数据。
# 说明：适合测试与热重载，成功后会重建事件与选择点索引。
func load_from_json_text(
	world_state_json: String,
	events_json: String,
	choice_points_json: String = ""
) -> Dictionary:
	var parsed_world: Variant = JSON.parse_string(world_state_json)
	if typeof(parsed_world) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid world state json"}

	var parsed_events: Variant = JSON.parse_string(events_json)
	if typeof(parsed_events) != TYPE_ARRAY:
		return {"ok": false, "error": "invalid events json"}

	var parsed_choice_points: Variant = []
	if not choice_points_json.strip_edges().is_empty():
		parsed_choice_points = JSON.parse_string(choice_points_json)
		if typeof(parsed_choice_points) != TYPE_ARRAY:
			return {"ok": false, "error": "invalid choice points json"}

	world_state = (parsed_world as Dictionary).duplicate(true)
	events = (parsed_events as Array).duplicate(true)
	choice_points = (parsed_choice_points as Array).duplicate(true)
	task_defs = []
	task_evaluation = {}
	_ensure_run_state()
	_ensure_task_runtime_state()
	_rebuild_event_map()
	_rebuild_choice_point_map()
	_rebuild_task_def_map()
	_rebuild_task_evaluation_index()
	return {"ok": true}

# 功能：从内存对象加载数据。
# 说明：用于承接 CSV 编译结果，避免二次 JSON 序列化产生歧义。
func load_from_data(data: Dictionary, location_graph: Variant = null) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "error": "compiled data is empty"}
	var raw_world: Variant = data.get("world_state", null)
	var raw_events: Variant = data.get("events", null)
	var raw_choice_points: Variant = data.get("choice_points", [])
	var raw_task_defs: Variant = data.get("task_defs", [])
	var raw_task_evaluation: Variant = data.get("task_evaluation", {})

	if typeof(raw_world) != TYPE_DICTIONARY:
		return {"ok": false, "error": "compiled world_state is invalid"}
	if typeof(raw_events) != TYPE_ARRAY:
		return {"ok": false, "error": "compiled events is invalid"}
	if typeof(raw_choice_points) != TYPE_ARRAY:
		return {"ok": false, "error": "compiled choice_points is invalid"}
	if typeof(raw_task_defs) != TYPE_ARRAY:
		return {"ok": false, "error": "compiled task_defs is invalid"}
	if typeof(raw_task_evaluation) != TYPE_DICTIONARY:
		return {"ok": false, "error": "compiled task_evaluation is invalid"}

	world_state = (raw_world as Dictionary).duplicate(true)
	events = (raw_events as Array).duplicate(true)
	choice_points = (raw_choice_points as Array).duplicate(true)
	task_defs = (raw_task_defs as Array).duplicate(true)
	task_evaluation = (raw_task_evaluation as Dictionary).duplicate(true)
	_ensure_run_state()
	_ensure_task_runtime_state()
	_set_location_graph(location_graph)
	_rebuild_event_map()
	_rebuild_choice_point_map()
	_rebuild_task_def_map()
	_rebuild_task_evaluation_index()
	return {"ok": true}

# 功能：预览下一回合事件，但不立即结算。
# 说明：统一创建待处理上下文，并返回当前阶段的事件数据；若已有待处理事件，则直接复用当前上下文。
func preview_next_turn() -> Dictionary:
	if events.is_empty():
		return {"ok": false, "error": "event pool is empty"}
	if _is_world_ended():
		return _build_world_ended_response()

	if not _pending_turn_context.is_empty():
		return _build_pending_turn_response(_pending_turn_context)

	var next_event_result := _select_next_event()
	if not next_event_result.get("ok", false):
		return next_event_result

	var event_def: Dictionary = next_event_result.get("event_def", {})
	var next_event_id := str(next_event_result.get("event_id", ""))
	var route := str(next_event_result.get("route", "scheduler"))
	var expected_forced := str(next_event_result.get("expected_forced", ""))
	_pending_turn_context = _create_pending_turn_context(next_event_id, route, expected_forced, event_def)
	return _build_pending_turn_response(_pending_turn_context)

# 功能：确认并结算当前待处理事件。
# 说明：无选项事件传空字符串即可；有选项事件必须传入可选 option_id。
func confirm_pending_turn(selected_option_id: String = "") -> Dictionary:
	if _is_world_ended():
		return _build_world_ended_response()
	if _pending_turn_context.is_empty():
		return {"ok": false, "error": "no pending turn to confirm"}
	return _resolve_pending_turn(selected_option_id)

# 功能：执行一个回合。
# 说明：若已有待处理事件，则继续推进当前阶段；否则先选出事件，再通过统一的待处理上下文完成展示、选择或确认。
func run_turn(selected_option_id: String = "") -> Dictionary:
	if events.is_empty():
		return {"ok": false, "error": "event pool is empty"}

	# 说明：若上一回合停在选择点，本回合只允许继续完成该待处理事件。
	if not _pending_turn_context.is_empty():
		return _resolve_pending_turn(selected_option_id)
	if _is_world_ended():
		return _build_world_ended_response()

	var next_event_result := _select_next_event()
	if not next_event_result.get("ok", false):
		return next_event_result

	var expected_forced := str(next_event_result.get("expected_forced", ""))
	var next_event_id := str(next_event_result.get("event_id", ""))
	var route := str(next_event_result.get("route", "scheduler"))
	var event_def: Dictionary = next_event_result.get("event_def", {})
	_pending_turn_context = _create_pending_turn_context(next_event_id, route, expected_forced, event_def)
	return _resolve_pending_turn(selected_option_id)

# 功能：处理待处理事件。
# 说明：根据 phase 推进展示阶段、选择阶段或确认阶段，并只在真正结算完成后推进 world_state 与回合数。
func _resolve_pending_turn(selected_option_id: String) -> Dictionary:
	var event_id := str(_pending_turn_context.get("event_id", ""))
	var route := str(_pending_turn_context.get("route", "scheduler"))
	var expected_forced := str(_pending_turn_context.get("expected_forced", ""))
	var phase := str(_pending_turn_context.get("phase", "confirm"))
	var resolution_mode := str(_pending_turn_context.get("resolution_mode", "event_effects"))
	var pending_has_choice := bool(_pending_turn_context.get("has_choice", false))
	var pending_choice: Dictionary = _dict_or_empty(_pending_turn_context.get("choice", {}))
	var event_def: Dictionary = _event_map.get(event_id, {})
	if event_def.is_empty():
		_pending_turn_context.clear()
		return {"ok": false, "error": "pending event not found: %s" % event_id}

	if phase == "presentation":
		# 说明：展示阶段只负责逐条推进展示文本，不执行事件效果，也不推进回合。
		var presentation_items := _get_event_presentation(event_def)
		var next_index := int(_pending_turn_context.get("presentation_index", 0)) + 1
		if next_index < presentation_items.size():
			_pending_turn_context["presentation_index"] = next_index
		else:
			_advance_pending_phase_after_presentation(event_def)
		return _build_pending_turn_response(_pending_turn_context)

	var choice_result := pending_choice.duplicate(true)
	if resolution_mode == "choice_resolution":
		var choice_point_id := str(event_def.get("choicePointId", "")).strip_edges()
		if choice_point_id.is_empty():
			_pending_turn_context.clear()
			return {"ok": false, "error": "pending event has no choice point: %s" % event_id}

		var choice_point_def: Dictionary = _choice_point_map.get(choice_point_id, {})
		if choice_point_def.is_empty():
			_pending_turn_context.clear()
			return {"ok": false, "error": "pending choice point not found: %s" % choice_point_id}

		var options_eval := _build_option_set(choice_point_def)
		choice_result["options"] = _option_public_states(options_eval)

		if selected_option_id.strip_edges().is_empty():
			choice_result["resolved_by"] = "pending_external_selection"
			return _build_result_payload(
				route,
				event_id,
				event_def,
				expected_forced,
				true,
				true,
				choice_result
			)

		var selected := _select_option_by_id(options_eval, selected_option_id)
		if selected.is_empty():
			return {
				"ok": false,
				"error": "selected option is not selectable: %s" % selected_option_id,
				"event_id": event_id,
				"choice_point_id": choice_point_id,
				"options": choice_result["options"]
			}

		# 说明：与 run_turn 保持一致，只有在真正落地选项结果时才消费 forcedNextEventId。
		world_state["forcedNextEventId"] = ""
		choice_result["selected_option_id"] = str(selected.get("id", ""))
		choice_result["resolved_by"] = "option_resolution"
		_apply_option_resolution(selected, event_def)
	else:
		# 说明：普通事件、缺失选择点或无可选项事件，都在这里统一按事件默认效果结算。
		world_state["forcedNextEventId"] = ""
		_apply_event_effects(event_def)
		_apply_continuation_policy(event_def)

	# 说明：任务自动完成判定必须发生在“本回合结算动作完成后、任务到期推进前”。
	_eval_complete_when_after_settlement()
	_record_history(event_id)
	_tick_tasks_after_turn()
	var ended_this_turn := false
	if bool(event_def.get("isEndingEvent", false)):
		_finalize_world(event_id)
		ended_this_turn = true
	if not ended_this_turn:
		world_state["turn"] = int(world_state.get("turn", 0)) + 1
		_pending_turn_context.clear()

	return _build_result_payload(
		route,
		event_id,
		event_def,
		expected_forced,
		false,
		pending_has_choice,
		choice_result
	)

# 功能：选择下一条事件路由并返回事件定义。
# 说明：该步骤只做选路，不产生副作用，便于“预览”和“直接执行”共用。
func _select_next_event() -> Dictionary:
	var expected_forced := str(world_state.get("forcedNextEventId", ""))
	var next_event_id := ""
	var route := "scheduler"

	if not expected_forced.is_empty():
		next_event_id = expected_forced
		route = "forced"
	else:
		var candidates := _build_candidates()
		if candidates.is_empty():
			next_event_id = _fallback_event_id()
			if next_event_id.is_empty():
				return {"ok": false, "error": "no eligible event and no fallback event"}
			route = "fallback"
		else:
			next_event_id = _weighted_pick(candidates)

	var event_def: Dictionary = _event_map.get(next_event_id, {})
	if event_def.is_empty():
		return {"ok": false, "error": "event not found: %s" % next_event_id}

	return {
		"ok": true,
		"expected_forced": expected_forced,
		"event_id": next_event_id,
		"route": route,
		"event_def": event_def
	}


# 功能：创建事件待处理上下文。
# 说明：统一收束展示、选择、确认三个阶段的初始化逻辑，并提前计算选项可见性与可选性。
func _create_pending_turn_context(
	event_id: String,
	route: String,
	expected_forced: String,
	event_def: Dictionary
) -> Dictionary:
	var choice_result := {
		"choice_point_id": "",
		"selected_option_id": "",
		"resolved_by": "",
		"options": []
	}
	var resolution_mode := "event_effects"
	var has_choice := false
	var phase := "confirm"
	var choice_point_id := str(event_def.get("choicePointId", "")).strip_edges()
	if not choice_point_id.is_empty():
		has_choice = true
		choice_result["choice_point_id"] = choice_point_id
		var choice_point_def: Dictionary = _choice_point_map.get(choice_point_id, {})
		if choice_point_def.is_empty():
			choice_result["resolved_by"] = "missing_choice_point_fallback_event_effects"
		else:
			var options_eval := _build_option_set(choice_point_def)
			choice_result["options"] = _option_public_states(options_eval)
			var first_selectable := _select_first_selectable(options_eval)
			if first_selectable.is_empty():
				choice_result["resolved_by"] = "no_selectable_option_fallback_event_effects"
			else:
				resolution_mode = "choice_resolution"
				choice_result["resolved_by"] = "pending_external_selection"
				phase = "choice"

	var presentation_items := _get_event_presentation(event_def)
	if not presentation_items.is_empty():
		phase = "presentation"

	return {
		"event_id": event_id,
		"route": route,
		"expected_forced": expected_forced,
		"resolution_mode": resolution_mode,
		"has_choice": has_choice,
		"choice": choice_result,
		"policy": str(event_def.get("continuationPolicy", POLICY_RETURN)),
		"phase": phase,
		"presentation_index": 0
	}


# 功能：在展示阶段结束后切换到下一个可交互阶段。
# 说明：优先进入 choice；若当前事件没有可交互选项，则退回到 confirm。
func _advance_pending_phase_after_presentation(event_def: Dictionary) -> void:
	var next_phase := "confirm"
	if str(_pending_turn_context.get("resolution_mode", "event_effects")) == "choice_resolution":
		next_phase = "choice"
	var choice_result: Dictionary = _dict_or_empty(_pending_turn_context.get("choice", {}))
	if next_phase == "choice" and choice_result.is_empty():
		next_phase = "confirm"
	_pending_turn_context["phase"] = next_phase
	_pending_turn_context["presentation_index"] = 0


# 功能：读取事件展示配置。
# 说明：统一收束展示数据的空值处理，便于后续扩展更多展示类型。
func _get_event_presentation(event_def: Dictionary) -> Array:
	var presentation: Variant = event_def.get("presentation", [])
	if typeof(presentation) == TYPE_ARRAY and presentation != null:
		return presentation
	return []


# 功能：构建返回给 Consumer 的展示阶段状态。
# 说明：Consumer 只消费当前展示项和索引信息，不直接解析事件定义原始结构。
func _build_presentation_state(event_def: Dictionary, phase: String) -> Dictionary:
	var presentation_items := _get_event_presentation(event_def)
	var state := {
		"active": false,
		"index": -1,
		"total": presentation_items.size(),
		"current_item": {}
	}
	if phase != "presentation" or presentation_items.is_empty():
		return state
	var current_index := clampi(int(_pending_turn_context.get("presentation_index", 0)), 0, presentation_items.size() - 1)
	state["active"] = true
	state["index"] = current_index
	state["current_item"] = presentation_items[current_index]
	return state

# 功能：构建待处理事件的统一返回结构。
# 说明：预览态、展示态、待选择态都复用此函数，避免界面层依赖多套字段格式。
func _build_pending_turn_response(pending_context: Dictionary) -> Dictionary:
	var event_id := str(pending_context.get("event_id", ""))
	var route := str(pending_context.get("route", "scheduler"))
	var expected_forced := str(pending_context.get("expected_forced", ""))
	var has_choice := bool(pending_context.get("has_choice", false))
	var resolution_mode := str(pending_context.get("resolution_mode", "event_effects"))
	var phase := str(pending_context.get("phase", "confirm"))
	var event_def: Dictionary = _event_map.get(event_id, {})
	if event_def.is_empty():
		return {"ok": false, "error": "pending event not found: %s" % event_id}

	var choice_result: Dictionary = _dict_or_empty(pending_context.get("choice", {})).duplicate(true)
	var awaiting_choice := phase == "choice" and resolution_mode == "choice_resolution"
	if awaiting_choice and choice_result.is_empty():
		choice_result = {
			"choice_point_id": str(event_def.get("choicePointId", "")),
			"selected_option_id": "",
			"resolved_by": "pending_external_selection",
			"options": []
		}

	return _build_result_payload(
		route,
		event_id,
		event_def,
		expected_forced,
		awaiting_choice,
		has_choice,
		choice_result
	)

# 功能：构建统一的回合结果字典。
# 说明：集中维护界面依赖字段，并额外暴露 phase 与 presentation 状态，避免不同执行路径返回结构漂移。
func _build_result_payload(
	route: String,
	event_id: String,
	event_def: Dictionary,
	expected_forced: String,
	awaiting_choice: bool,
	has_choice: bool,
	choice_result: Dictionary
) -> Dictionary:
	_ensure_run_state()
	var run_state_payload := _build_run_state_payload()
	var phase := "resolved"
	if not _pending_turn_context.is_empty() and str(_pending_turn_context.get("event_id", "")) == event_id:
		phase = str(_pending_turn_context.get("phase", "confirm"))
	elif awaiting_choice:
		phase = "choice"
	var presentation_state := _build_presentation_state(event_def, phase)
	return {
		"ok": true,
		"phase": phase,
		"awaiting_choice": awaiting_choice,
		"route": route,
		"event_id": event_id,
		"title": str(event_def.get("title", "")),
		"event_background_art": str(event_def.get("backgroundArt", "")),
		"location_background_art": _resolve_location_background_art(),
		"resolved_background_art": _resolve_background_art(event_def),
		"policy": str(event_def.get("continuationPolicy", POLICY_RETURN)),
		"expected_forced": expected_forced,
		"chain_active": not (world_state.get("chainContext", null) == null),
		"has_choice": has_choice,
		"presentation": presentation_state,
		"choice": choice_result,
		"world_ended": bool(run_state_payload.get("world_ended", false)),
		"run_status": str(run_state_payload.get("run_status", "running")),
		"ending_event_id": str(run_state_payload.get("ending_event_id", "")),
		"finished_turn": int(run_state_payload.get("finished_turn", 0))
	}

# 功能：确保世界运行态结构完整。
# 说明：兼容旧存档、旧测试数据与未包含 runState 的输入，统一补齐 ended 所需字段。
func _ensure_run_state() -> void:
	var run_state := _dict_or_empty(world_state.get("runState", {}))
	var status := str(run_state.get("status", "running")).strip_edges()
	if status.is_empty():
		status = "running"
	run_state["status"] = status
	run_state["endingEventId"] = str(run_state.get("endingEventId", "")).strip_edges()
	run_state["finishedTurn"] = maxi(0, int(run_state.get("finishedTurn", 0)))
	world_state["runState"] = run_state


# 功能：将当前世界标记为结束态。
# 说明：ending event 完成最终结算后调用，负责写入 ended 状态并清理执行锁与待处理上下文。
func _finalize_world(ending_event_id: String) -> void:
	_ensure_run_state()
	var run_state := _dict_or_empty(world_state.get("runState", {}))
	run_state["status"] = "ended"
	run_state["endingEventId"] = ending_event_id.strip_edges()
	run_state["finishedTurn"] = int(world_state.get("turn", 0))
	world_state["runState"] = run_state
	world_state["forcedNextEventId"] = ""
	world_state["chainContext"] = null
	_pending_turn_context.clear()


# 功能：判断当前世界是否已进入结束态。
# 说明：所有对外入口统一通过这里读取 runState.status，避免重复拼接 ended 判定。
func _is_world_ended() -> bool:
	_ensure_run_state()
	var run_state := _dict_or_empty(world_state.get("runState", {}))
	return str(run_state.get("status", "running")).strip_edges() == "ended"


# 功能：构建对外暴露的最小结束态字段。
# 说明：统一 world ended 的公开字段名，避免 payload 与 ended 短路返回之间出现结构漂移。
func _build_run_state_payload() -> Dictionary:
	_ensure_run_state()
	var run_state := _dict_or_empty(world_state.get("runState", {}))
	var status := str(run_state.get("status", "running")).strip_edges()
	return {
		"world_ended": status == "ended",
		"run_status": status,
		"ending_event_id": str(run_state.get("endingEventId", "")).strip_edges(),
		"finished_turn": maxi(0, int(run_state.get("finishedTurn", 0)))
	}


# 功能：在世界已结束时返回稳定结果。
# 说明：结束不是异常；后续入口统一返回 ended 状态，方便外部流程直接消费而不是走报错分支。
func _build_world_ended_response() -> Dictionary:
	var run_state_payload := _build_run_state_payload()
	return {
		"ok": true,
		"phase": "ended",
		"awaiting_choice": false,
		"route": "ended",
		"event_id": "",
		"title": "",
		"event_background_art": "",
		"location_background_art": _resolve_location_background_art(),
		"resolved_background_art": "",
		"policy": "",
		"expected_forced": "",
		"chain_active": false,
		"has_choice": false,
		"presentation": {
			"active": false,
			"index": -1,
			"total": 0,
			"current_item": {}
		},
		"choice": {
			"choice_point_id": "",
			"selected_option_id": "",
			"resolved_by": "world_ended",
			"options": []
		},
		"world_ended": bool(run_state_payload.get("world_ended", true)),
		"run_status": str(run_state_payload.get("run_status", "ended")),
		"ending_event_id": str(run_state_payload.get("ending_event_id", "")),
		"finished_turn": int(run_state_payload.get("finished_turn", 0))
	}


# 功能：设置引擎当前使用的地点图。
# 说明：用于解析当前地点对应的默认背景路径，供事件背景缺失时兜底。
func _set_location_graph(location_graph: Variant) -> void:
	if location_graph is LocationGraph:
		_location_graph = location_graph
	else:
		_location_graph = null

# 功能：解析事件最终应展示的背景路径。
# 说明：规则为“事件背景优先，地点背景兜底”；引擎统一产出，Consumer 不再自行判断。
func _resolve_background_art(event_def: Dictionary) -> String:
	var event_background_art := str(event_def.get("backgroundArt", "")).strip_edges()
	if not event_background_art.is_empty():
		return event_background_art
	return _resolve_location_background_art()

# 功能：解析当前地点的背景路径。
# 说明：若地点图缺失或地点未配置背景，则返回空字符串。
func _resolve_location_background_art() -> String:
	if _location_graph == null:
		return ""
	var current_location_id := str(world_state.get("currentLocationId", "")).strip_edges()
	if current_location_id.is_empty():
		return ""
	return _location_graph.get_art_path(current_location_id)

# 功能：重建事件索引。
# 说明：将 events 数组映射为 {event_id: event_def}，供 O(1) 查询。
func _rebuild_event_map() -> void:
	_event_map.clear()
	for event_variant in events:
		var event_def: Dictionary = event_variant
		var event_id := str(event_def.get("id", ""))
		if event_id.is_empty():
			continue
		_event_map[event_id] = event_def

# 功能：重建选择点索引。
# 说明：将 choice_points 映射为 {choice_point_id: choice_point_def}。
func _rebuild_choice_point_map() -> void:
	_choice_point_map.clear()
	for choice_variant in choice_points:
		var choice_def: Dictionary = choice_variant
		var choice_id := str(choice_def.get("id", "")).strip_edges()
		if choice_id.is_empty():
			continue
		_choice_point_map[choice_id] = choice_def


# 功能：重建任务定义索引。
# 说明：将 task_defs 映射为 {task_id: task_def}，供任务动作 O(1) 查询。
func _rebuild_task_def_map() -> void:
	_task_def_map.clear()
	for task_variant in task_defs:
		var task_def: Dictionary = task_variant
		var task_id := str(task_def.get("id", "")).strip_edges()
		if task_id.is_empty():
			continue
		_task_def_map[task_id] = task_def


# 功能：按 task_id 构建任务评价配置索引。
# 说明：将 grades/indicators/overrides/effects 预分组，降低结算阶段的遍历开销。
func _rebuild_task_evaluation_index() -> void:
	_task_eval_index_by_task.clear()
	var grades: Array = _array_or_empty(task_evaluation.get("grades", []))
	var indicators: Array = _array_or_empty(task_evaluation.get("indicators", []))
	var grade_overrides: Array = _array_or_empty(task_evaluation.get("gradeOverrides", []))
	var effects: Array = _array_or_empty(task_evaluation.get("effects", []))

	for grade_variant in grades:
		var grade: Dictionary = _dict_or_empty(grade_variant)
		var task_id := str(grade.get("taskId", "")).strip_edges()
		if task_id.is_empty():
			continue
		var bucket := _ensure_task_eval_bucket(task_id)
		var grade_rows: Array = _array_or_empty(bucket.get("grades", []))
		grade_rows.append(grade)
		bucket["grades"] = grade_rows
		var mode := str(grade.get("gradeMode", "")).strip_edges().to_lower()
		if mode == "score_band":
			var score_bands: Array = _array_or_empty(bucket.get("scoreBands", []))
			score_bands.append(grade)
			_sort_grade_score_bands_by_min(score_bands)
			bucket["scoreBands"] = score_bands
		_task_eval_index_by_task[task_id] = bucket

	for indicator_variant in indicators:
		var indicator: Dictionary = _dict_or_empty(indicator_variant)
		var task_id := str(indicator.get("taskId", "")).strip_edges()
		if task_id.is_empty():
			continue
		var bucket := _ensure_task_eval_bucket(task_id)
		var indicator_rows: Array = _array_or_empty(bucket.get("indicators", []))
		indicator_rows.append(indicator)
		bucket["indicators"] = indicator_rows
		_task_eval_index_by_task[task_id] = bucket

	for override_variant in grade_overrides:
		var override_row: Dictionary = _dict_or_empty(override_variant)
		var task_id := str(override_row.get("taskId", "")).strip_edges()
		if task_id.is_empty():
			continue
		var bucket := _ensure_task_eval_bucket(task_id)
		var override_rows: Array = _array_or_empty(bucket.get("gradeOverrides", []))
		override_rows.append(override_row)
		_sort_grade_overrides_by_priority_desc(override_rows)
		bucket["gradeOverrides"] = override_rows
		_task_eval_index_by_task[task_id] = bucket

	for effect_variant in effects:
		var effect: Dictionary = _dict_or_empty(effect_variant)
		var task_id := str(effect.get("taskId", "")).strip_edges()
		if task_id.is_empty():
			continue
		var bucket := _ensure_task_eval_bucket(task_id)
		var effect_rows: Array = _array_or_empty(bucket.get("effects", []))
		effect_rows.append(effect)
		bucket["effects"] = effect_rows
		_task_eval_index_by_task[task_id] = bucket


# 功能：确保 task 评价索引桶存在并返回副本。
# 说明：桶结构固定，避免后续结算阶段频繁判空分支。
func _ensure_task_eval_bucket(task_id: String) -> Dictionary:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	if _task_eval_index_by_task.has(normalized_id):
		return _dict_or_empty(_task_eval_index_by_task.get(normalized_id, {}))
	return {
		"grades": [],
		"scoreBands": [],
		"indicators": [],
		"gradeOverrides": [],
		"effects": []
	}


# 功能：按 minScore 升序排序 score_band 档位。
# 说明：后续基础档位映射按区间顺序匹配，排序可减少比较歧义。
func _sort_grade_score_bands_by_min(score_bands: Array) -> void:
	for i in range(1, score_bands.size()):
		var current: Dictionary = _dict_or_empty(score_bands[i])
		var current_min := float(current.get("minScore", 0.0))
		var j := i - 1
		while j >= 0:
			var left: Dictionary = _dict_or_empty(score_bands[j])
			if float(left.get("minScore", 0.0)) <= current_min:
				break
			score_bands[j + 1] = score_bands[j]
			j -= 1
		score_bands[j + 1] = current


# 功能：按 priority 降序排序档位分流规则。
# 说明：运行时遇到首个命中规则即终止，需保证高优先级在前。
func _sort_grade_overrides_by_priority_desc(grade_overrides: Array) -> void:
	for i in range(1, grade_overrides.size()):
		var current: Dictionary = _dict_or_empty(grade_overrides[i])
		var current_priority := int(current.get("priority", 0))
		var j := i - 1
		while j >= 0:
			var left: Dictionary = _dict_or_empty(grade_overrides[j])
			if int(left.get("priority", 0)) >= current_priority:
				break
			grade_overrides[j + 1] = grade_overrides[j]
			j -= 1
		grade_overrides[j + 1] = current

# 功能：生成候选事件集合。
# 说明：这里只做可用性与权重计算，不做最终抽签。
func _build_candidates() -> Array:
	var out: Array = []
	for event_variant in events:
		var event_def: Dictionary = event_variant
		if _is_event_eligible(event_def):
			var weight := _compute_weight(event_def)
			out.append({"id": str(event_def.get("id", "")), "weight": weight})
	return out


# 功能：导出当前候选事件权重快照。
# 说明：仅用于调试/测试，不改变世界状态。
func debug_get_candidate_weights() -> Dictionary:
	var candidates := _build_candidates()
	var weights: Dictionary = {}
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		var event_id := str(candidate.get("id", "")).strip_edges()
		if event_id.is_empty():
			continue
		weights[event_id] = int(candidate.get("weight", 1))
	return {
		"ok": true,
		"weights": weights,
		"candidates": candidates
	}

# 功能：执行事件硬约束过滤。
# 说明：地点、地点状态、NPC 在场、链 allowedTags 任一不满足即排除。
func _is_event_eligible(event_def: Dictionary) -> bool:
	var eligibility: Dictionary = event_def.get("eligibility", {})
	var current_location := str(world_state.get("currentLocationId", ""))

	# 说明：地点硬过滤。
	var required_locations: Array = eligibility.get("requiredLocations", [])
	if not required_locations.is_empty() and not (current_location in required_locations):
		return false

	# 说明：地点状态硬过滤。
	var location_state_all: Dictionary = world_state.get("locationState", {})
	var current_location_state: Dictionary = location_state_all.get(current_location, {})
	var required_location_flags: Array = eligibility.get("requiredLocationFlags", [])
	for clause_variant in required_location_flags:
		var clause: Dictionary = clause_variant
		var key := str(clause.get("key", ""))
		var op := str(clause.get("op", "=="))
		var expected: Variant = clause.get("value", 0)
		var actual: Variant = current_location_state.get(key, null)
		if not _compare_values(actual, op, expected):
			return false

	# 说明：NPC 在场硬过滤。
	var required_npcs: Array = eligibility.get("requiredNPCsPresent", [])
	if not required_npcs.is_empty():
		var npc_presence_all: Dictionary = world_state.get("npcPresence", {})
		var present_list: Array = npc_presence_all.get(current_location, [])
		for npc_id_variant in required_npcs:
			var npc_id := str(npc_id_variant)
			if not (npc_id in present_list):
				return false

	# 说明：链上下文额外过滤。
	var chain_context: Variant = world_state.get("chainContext", null)
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		var chain_dict: Dictionary = chain_context
		var allowed_tags: Array = chain_dict.get("allowedTags", [])
		if not allowed_tags.is_empty():
			var event_tags: Array = event_def.get("tags", [])
			if not _array_has_any(event_tags, allowed_tags):
				return false

	return true

# 功能：计算单个事件当前权重。
# 说明：综合 baseWeight、weightRules、历史惩罚、链式 tag 偏置与任务偏置。
func _compute_weight(event_def: Dictionary) -> int:
	var weight := int(event_def.get("baseWeight", 10))

	var rules: Array = event_def.get("weightRules", [])
	for rule_variant in rules:
		var rule: Dictionary = rule_variant
		var condition := str(rule.get("when", "")).strip_edges()
		if condition.is_empty():
			continue
		if _evaluate_condition(condition):
			weight += int(rule.get("delta", 0))

	# 说明：历史去重偏置，近期出现过的事件会轻微降权。
	var history: Array = world_state.get("history", [])
	if str(event_def.get("id", "")) in history:
		weight -= 3

	# 说明：链上下文偏置，通过 tag 映射提高链内事件权重。
	var chain_context: Variant = world_state.get("chainContext", null)
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		var chain_dict: Dictionary = chain_context
		var tag_bias: Dictionary = chain_dict.get("weightBias", {})
		var event_tags: Array = event_def.get("tags", [])
		for tag_variant in event_tags:
			var tag := str(tag_variant)
			if tag_bias.has(tag):
				weight += int(tag_bias[tag])

	# 说明：任务偏置由 event.taskLinks 与 active tasks 共同决定，只影响软权重。
	weight += _compute_task_bias(event_def)

	if weight < 1:
		return 1
	return weight


# 功能：计算任务偏置总和。
# 说明：同一事件可命中多个 taskLinks，并与并行 active 任务叠加。
func _compute_task_bias(event_def: Dictionary) -> int:
	var links := _array_or_empty(event_def.get("taskLinks", []))
	if links.is_empty():
		return 0

	var active_task_ids := _build_active_task_id_set()
	if active_task_ids.is_empty():
		return 0

	var bias := 0
	for link_variant in links:
		var parsed := _parse_task_link(str(link_variant))
		if parsed.is_empty():
			continue
		var task_id := str(parsed.get("taskId", ""))
		var link_type := str(parsed.get("type", ""))
		if task_id.is_empty() or link_type.is_empty():
			continue
		if not active_task_ids.has(task_id):
			continue
		bias += _get_task_bias_value(link_type)
	return bias


# 功能：构建 active 任务 ID 集合。
# 说明：用于在权重阶段快速判断某 task_id 是否处于 active 状态。
func _build_active_task_id_set() -> Dictionary:
	var out: Dictionary = {}
	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	for runtime_variant in active:
		var task_runtime := _dict_or_empty(runtime_variant)
		var task_id := str(task_runtime.get("taskId", "")).strip_edges()
		if task_id.is_empty():
			continue
		out[task_id] = true
	return out


# 功能：解析 taskLinks 单项语义。
# 说明：仅识别 advance:<task_id> 与 risk:<task_id>，其余值忽略。
func _parse_task_link(raw_link: String) -> Dictionary:
	var text := raw_link.strip_edges()
	if text.is_empty():
		return {}
	var pair := text.split(":", false, 1)
	if pair.size() != 2:
		return {}
	var link_type := str(pair[0]).strip_edges().to_lower()
	var task_id := str(pair[1]).strip_edges()
	if task_id.is_empty():
		return {}
	if link_type != "advance" and link_type != "risk":
		return {}
	return {
		"type": link_type,
		"taskId": task_id
	}


# 功能：返回单条任务链接的偏置值。
# 说明：当前 MVP 先使用固定默认值；后续可按 weightBiasProfile 继续扩展。
func _get_task_bias_value(link_type: String) -> int:
	var normalized_type := link_type.strip_edges().to_lower()
	if normalized_type == "advance":
		return TASK_BIAS_ADVANCE_DEFAULT
	if normalized_type == "risk":
		return TASK_BIAS_RISK_DEFAULT
	return 0

# 功能：解析并执行简单条件表达式。
# 说明：格式为 "<path> <op> <literal>"，支持 >= <= == != > <。
func _evaluate_condition(condition: String) -> bool:
	var operators := [">=", "<=", "==", "!=", ">", "<"]
	for op_variant in operators:
		var op := str(op_variant)
		var token := " %s " % op
		if condition.find(token) == -1:
			continue
		var parts := condition.split(token)
		if parts.size() != 2:
			return false
		var left_text := str(parts[0]).strip_edges()
		var right_text := str(parts[1]).strip_edges()
		var actual: Variant = _resolve_path_value(left_text)
		var expected: Variant = _parse_literal(right_text)
		return _compare_values(actual, op, expected)
	return false

# 功能：按点路径读取 world_state 值。
# 说明：例如 flags.isWanted；任意层不存在时返回 null。
func _resolve_path_value(path: String) -> Variant:
	var segments := path.split(".", false)
	if segments.is_empty():
		return null

	var cursor: Variant = world_state
	for segment_variant in segments:
		var segment := str(segment_variant)
		if typeof(cursor) != TYPE_DICTIONARY:
			return null
		var dict_cursor: Dictionary = cursor
		if not dict_cursor.has(segment):
			return null
		cursor = dict_cursor[segment]
	return cursor

# 功能：将表达式右值文本解析为 GDScript 值。
# 说明：支持 bool、int、双引号字符串，其他保持原文本。
func _parse_literal(raw: String) -> Variant:
	var text := raw.strip_edges()
	var lowered := text.to_lower()
	if lowered == "true":
		return true
	if lowered == "false":
		return false
	if text.is_valid_int():
		return int(text)
	if text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2:
		return text.substr(1, text.length() - 2)
	return text

# 功能：统一比较函数。
# 说明：大小比较会先转为 float，再执行比较。
func _compare_values(actual: Variant, op: String, expected: Variant) -> bool:
	if actual == null:
		return false
	match op:
		"==":
			return actual == expected
		"!=":
			return actual != expected
		">":
			return float(actual) > float(expected)
		">=":
			return float(actual) >= float(expected)
		"<":
			return float(actual) < float(expected)
		"<=":
			return float(actual) <= float(expected)
		_:
			return false

# 功能：按权重随机抽取事件 id。
# 说明：当总权重异常（<=0）时回退第一个候选，保证不中断。
func _weighted_pick(candidates: Array) -> String:
	var total := 0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		total += maxi(1, int(candidate.get("weight", 1)))

	if total <= 0:
		return str((candidates[0] as Dictionary).get("id", ""))

	var roll := _rng.randi_range(1, total)
	var cursor := 0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		cursor += maxi(1, int(candidate.get("weight", 1)))
		if roll <= cursor:
			return str(candidate.get("id", ""))

	return str((candidates[0] as Dictionary).get("id", ""))

# 功能：选择兜底事件。
# 说明：优先 evt_idle，其次取事件池中第一个可用 id。
func _fallback_event_id() -> String:
	if _event_map.has("evt_idle"):
		return "evt_idle"
	for event_variant in events:
		var event_def: Dictionary = event_variant
		var event_id := str(event_def.get("id", ""))
		if not event_id.is_empty():
			return event_id
	return ""

# 功能：将事件 effects 应用到 world_state。
# 说明：支持 setFlags、addParams、setLocation、forcedNext、clearForced、endChain。
func _apply_event_effects(event_def: Dictionary) -> void:
	var effects: Dictionary = event_def.get("effects", {})

	var set_flags: Dictionary = effects.get("setFlags", {})
	if not set_flags.is_empty():
		var flags: Dictionary = world_state.get("flags", {})
		for key in set_flags.keys():
			flags[str(key)] = set_flags[key]
		world_state["flags"] = flags

	var add_params: Dictionary = effects.get("addParams", {})
	if not add_params.is_empty():
		var params: Dictionary = world_state.get("params", {})
		for key in add_params.keys():
			var param_key := str(key)
			params[param_key] = int(params.get(param_key, 0)) + int(add_params[key])
		world_state["params"] = params

	var set_location := str(effects.get("setLocation", "")).strip_edges()
	if not set_location.is_empty():
		world_state["currentLocationId"] = set_location

	var forced_id := str(effects.get("forcedNextEventId", "")).strip_edges()
	if not forced_id.is_empty():
		world_state["forcedNextEventId"] = forced_id

	if bool(effects.get("clearForcedNext", false)):
		world_state["forcedNextEventId"] = ""

	if bool(effects.get("endChain", false)):
		world_state["chainContext"] = null

	var task_actions := _array_or_empty(effects.get("taskActions", []))
	_apply_task_actions(task_actions)

# 功能：按 continuationPolicy 推进链上下文。
# 说明：forcedNextEventId 由 effects 或 resolution 驱动，不在这里判定。
func _apply_continuation_policy(event_def: Dictionary, chain_patch_override: Dictionary = {}) -> void:
	var policy := str(event_def.get("continuationPolicy", POLICY_RETURN))
	var base_chain_patch: Dictionary = event_def.get("chainPatch", {})
	var merged_chain_patch := _merge_dict(base_chain_patch, chain_patch_override)
	match policy:
		POLICY_CHAIN, POLICY_CHAIN_FORCED:
			_ensure_or_patch_chain_context(merged_chain_patch)
		POLICY_RETURN:
			# 说明：ReturnToScheduler 不主动建链；若显式给出 patch，则按 patch 执行。
			if not merged_chain_patch.is_empty():
				_ensure_or_patch_chain_context(merged_chain_patch)
		_:
			pass

# 功能：创建或更新 chainContext。
# 说明：首次按 patch 初始化，链内按 stageDelta 推进，并可按退出条件自动结束。
func _ensure_or_patch_chain_context(chain_patch: Dictionary) -> void:
	var raw_ctx: Variant = world_state.get("chainContext", null)
	var ctx: Dictionary = {}
	if typeof(raw_ctx) == TYPE_DICTIONARY and raw_ctx != null:
		ctx = (raw_ctx as Dictionary).duplicate(true)

	if ctx.is_empty():
		ctx = {
			"chainId": str(chain_patch.get("chainId", "chain_default")),
			"stage": int(chain_patch.get("stage", 1)),
			"allowedTags": chain_patch.get("allowedTags", []),
			"constraints": chain_patch.get("constraints", {}),
			"weightBias": chain_patch.get("weightBias", {}),
			"exitWhenStageGte": int(chain_patch.get("exitWhenStageGte", 0))
		}
	else:
		ctx["stage"] = int(ctx.get("stage", 0)) + int(chain_patch.get("stageDelta", 1))
		if chain_patch.has("allowedTags"):
			ctx["allowedTags"] = chain_patch.get("allowedTags", [])
		if chain_patch.has("constraints"):
			ctx["constraints"] = chain_patch.get("constraints", {})
		if chain_patch.has("weightBias"):
			ctx["weightBias"] = chain_patch.get("weightBias", {})
		if chain_patch.has("exitWhenStageGte"):
			ctx["exitWhenStageGte"] = int(chain_patch.get("exitWhenStageGte", 0))

	var exit_stage := int(ctx.get("exitWhenStageGte", 0))
	if exit_stage > 0 and int(ctx.get("stage", 0)) >= exit_stage:
		world_state["chainContext"] = null
	else:
		world_state["chainContext"] = ctx

# 功能：记录最近事件历史。
# 说明：固定窗口 12 条，供权重去重使用。
func _record_history(event_id: String) -> void:
	var history: Array = world_state.get("history", [])
	history.append(event_id)
	while history.size() > 12:
		history.pop_front()
	world_state["history"] = history

# 功能：判断两个数组是否存在任意交集。
# 说明：用于 tag 匹配。
func _array_has_any(left: Array, right: Array) -> bool:
	for left_item in left:
		if left_item in right:
			return true
	return false

# 功能：构建事件对应的选项集合。
# 说明：为每个选项标记三态：invisible、disabled、selectable。
func _build_option_set(choice_point_def: Dictionary) -> Array:
	var out: Array = []
	var options: Array = choice_point_def.get("options", [])
	for option_variant in options:
		var option_def: Dictionary = option_variant
		var item := option_def.duplicate(true)
		# 说明：选项三态分别表示不显示、显示但不可选、可选。
		var state := "selectable"
		if not _option_visible(option_def):
			state = "invisible"
		elif not _option_selectable(option_def):
			state = "disabled"
		item["state"] = state
		out.append(item)
	return out

# 功能：输出上层使用的选项简版结构。
# 说明：仅返回 id、text、state，避免暴露内部结算细节。
func _option_public_states(options_eval: Array) -> Array:
	var out: Array = []
	for option_variant in options_eval:
		var option_def: Dictionary = option_variant
		out.append(
			{
				"id": str(option_def.get("id", "")),
				"text": str(option_def.get("text", "")),
				"state": str(option_def.get("state", "disabled"))
			}
		)
	return out

# 功能：判定选项是否可见。
# 说明：visibilityWhen 条件需全部通过才可见。
func _option_visible(option_def: Dictionary) -> bool:
	var visibility_rules := _array_or_empty(option_def.get("visibilityWhen", []))
	for rule_variant in visibility_rules:
		var rule := str(rule_variant).strip_edges()
		if rule.is_empty():
			continue
		if not _evaluate_condition(rule):
			return false
	return true

# 功能：判定选项是否可选。
# 说明：需要同时通过 eligibility 与 cost 校验。
func _option_selectable(option_def: Dictionary) -> bool:
	if not _is_option_eligibility_pass(_dict_or_empty(option_def.get("eligibility", {}))):
		return false
	return _can_pay_cost(_dict_or_empty(option_def.get("cost", {})))

# 功能：逐条校验 eligibility 条件。
# 说明：支持字面量比较与内联规则字符串，例如 >=10。
func _is_option_eligibility_pass(eligibility: Dictionary) -> bool:
	for key_variant in eligibility.keys():
		var path := str(key_variant).strip_edges()
		var clause: Variant = eligibility[key_variant]
		var actual: Variant = _resolve_path_value(path)
		if typeof(clause) == TYPE_STRING:
			# 说明：规则示例：>=10、=true；左值来自 path 对应的 world_state 字段。
			var rule := str(clause).strip_edges()
			if rule.is_empty():
				continue
			if not _match_inline_rule(actual, rule):
				return false
		else:
			if actual != clause:
				return false
	return true

# 功能：解析并匹配内联规则。
# 说明：规则示例：>=10、=true，左值为 actual。
func _match_inline_rule(actual: Variant, rule: String) -> bool:
	var operators := [">=", "<=", "==", "!=", ">", "<"]
	for op_variant in operators:
		var op := str(op_variant)
		if not rule.begins_with(op):
			continue
		var right_text := rule.substr(op.length()).strip_edges()
		var expected: Variant = _parse_literal(right_text)
		return _compare_values(actual, op, expected)
	var expected_literal: Variant = _parse_literal(rule)
	return actual == expected_literal

# 功能：检查玩家是否可支付选项代价。
# 说明：从 world_state.player 读取资源并比较。
func _can_pay_cost(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	var player: Dictionary = world_state.get("player", {})
	for key_variant in cost.keys():
		var key := str(key_variant)
		var need := int(cost[key_variant])
		var have := int(player.get(key, 0))
		if have < need:
			return false
	return true

# 功能：将选项代价扣减到 world_state.player。
# 说明：按 cost 字段逐项扣减。
func _apply_cost(cost: Dictionary) -> void:
	if cost.is_empty():
		return
	var player: Dictionary = world_state.get("player", {})
	for key_variant in cost.keys():
		var key := str(key_variant)
		player[key] = int(player.get(key, 0)) - int(cost[key_variant])
	world_state["player"] = player

# 功能：在可选项中按外部传入 ID 精确选择。
# 说明：仅当目标选项状态为 selectable 时返回，否则返回空字典。
func _select_option_by_id(options_eval: Array, option_id: String) -> Dictionary:
	var target := option_id.strip_edges()
	if target.is_empty():
		return {}
	for option_variant in options_eval:
		var option_def: Dictionary = option_variant
		if str(option_def.get("id", "")) == target and str(option_def.get("state", "")) == "selectable":
			return option_def
	return {}

# 功能：在可选项中查找第一个 selectable 选项。
# 说明：仅用于判断“是否存在可选项”，不用于自动结算。
func _select_first_selectable(options_eval: Array) -> Dictionary:
	for option_variant in options_eval:
		var option_def: Dictionary = option_variant
		if str(option_def.get("state", "")) == "selectable":
			return option_def
	return {}

# 功能：执行选项结算主流程。
# 说明：流程为扣代价、检定、应用 resolution。
func _apply_option_resolution(selected_option: Dictionary, event_def: Dictionary) -> void:
	var cost := _dict_or_empty(selected_option.get("cost", {}))
	if not _can_pay_cost(cost):
		# 说明：正常情况下不应进入该分支，这里保留为防御性兜底。
		_apply_event_effects(event_def)
		_apply_continuation_policy(event_def)
		return

	_apply_cost(cost)

	var resolution := _dict_or_empty(selected_option.get("resolution", {}))
	var check := _dict_or_empty(selected_option.get("check", {}))
	if not _is_check_pass(check):
		# 说明：检定失败时，可用 onFailResolution 覆盖默认 resolution。
		var fail_resolution := _dict_or_empty(check.get("onFailResolution", {}))
		if not fail_resolution.is_empty():
			resolution = fail_resolution

	_apply_resolution(resolution, event_def)

# 功能：执行选项检定。
# 说明：当前仅支持 chance；无 check 或未知类型默认通过。
func _is_check_pass(check: Dictionary) -> bool:
	if check.is_empty():
		return true
	var check_type := str(check.get("type", "")).strip_edges()
	if check_type == "chance":
		var rate := clampf(float(check.get("successRate", 1.0)), 0.0, 1.0)
		return _rng.randf() <= rate
	return true

# 功能：应用 resolution，并衔接执行锁更新。
# 说明：统一处理 worldStatePatch、forcedNextEventId、chainContextPatch。
func _apply_resolution(resolution: Dictionary, event_def: Dictionary) -> void:
	# 说明：resolution 统一处理三类后果：worldStatePatch、forcedNextEventId、chainContextPatch。
	var world_patch := _dict_or_empty(resolution.get("worldStatePatch", {}))
	_apply_world_state_patch(world_patch)

	if resolution.has("forcedNextEventId"):
		var forced_id := str(resolution.get("forcedNextEventId", "")).strip_edges()
		world_state["forcedNextEventId"] = forced_id

	var chain_patch := _dict_or_empty(resolution.get("chainContextPatch", {}))
	_apply_continuation_policy(event_def, chain_patch)

	var task_actions := _array_or_empty(resolution.get("taskActions", []))
	_apply_task_actions(task_actions)


# 功能：确保任务运行时结构完整。
# 说明：兼容旧存档或缺省配置，保证任务系统逻辑始终有稳定结构可写。
func _ensure_task_runtime_state() -> void:
	var task_config := _dict_or_empty(world_state.get("taskConfig", {}))
	task_config["maxActiveCount"] = maxi(1, int(task_config.get("maxActiveCount", 1)))
	world_state["taskConfig"] = task_config

	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	var completed := _array_or_empty(tasks_state.get("completed", []))
	var failed := _array_or_empty(tasks_state.get("failed", []))
	var abandoned := _array_or_empty(tasks_state.get("abandoned", []))
	var result_records := _array_or_empty(tasks_state.get("resultRecords", []))
	tasks_state["active"] = active
	tasks_state["completed"] = completed
	tasks_state["failed"] = failed
	tasks_state["abandoned"] = abandoned
	tasks_state["resultRecords"] = result_records
	world_state["tasks"] = tasks_state


# 功能：执行任务动作数组。
# 说明：任务动作属于软失败链路，单条动作异常不会中断主循环。
func _apply_task_actions(task_actions: Array) -> void:
	if task_actions.is_empty():
		return
	_ensure_task_runtime_state()
	for action_variant in task_actions:
		if typeof(action_variant) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = action_variant
		_apply_task_action(action)


# 功能：执行单条任务动作。
# 说明：支持 accept_task、advance_task、abandon_task、complete_task 四类 MVP 动作。
func _apply_task_action(action: Dictionary) -> void:
	var op := str(action.get("op", "")).strip_edges()
	var task_id := str(action.get("taskId", "")).strip_edges()
	match op:
		"accept_task":
			_accept_task(task_id)
		"advance_task":
			var progress_key := str(action.get("progressKey", "progress")).strip_edges()
			var delta := int(action.get("delta", 1))
			_advance_task(task_id, progress_key, delta)
		"abandon_task":
			_abandon_task(task_id)
		"complete_task":
			_complete_task(task_id)
		_:
			pass


# 功能：接取任务并写入 active 列表。
# 说明：接取时会校验并行上限与任务定义存在性，重复接取同一 active 任务会被忽略。
func _accept_task(task_id: String) -> bool:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return false
	if _find_active_task_index(normalized_id) >= 0:
		return true

	var task_def := _dict_or_empty(_task_def_map.get(normalized_id, {}))
	if task_def.is_empty():
		return false

	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	var task_config := _dict_or_empty(world_state.get("taskConfig", {}))
	var max_active_count := maxi(1, int(task_config.get("maxActiveCount", 1)))
	if active.size() >= max_active_count:
		return false

	var current_turn := int(world_state.get("turn", 1))
	var duration_turns := maxi(1, int(task_def.get("durationTurns", 1)))
	active.append(
		{
			"taskId": normalized_id,
			"acceptedTurn": current_turn,
			# 说明：duration_turns 不包含接取任务的当回合，而是从下一回合开始计算。
			"deadlineTurn": current_turn + duration_turns,
			"status": "active",
			"progress": {}
		}
	)
	tasks_state["active"] = active
	_remove_task_id_from_archives(tasks_state, normalized_id)
	world_state["tasks"] = tasks_state
	return true


# 功能：推进任务进度。
# 说明：仅对 active 任务生效；progressKey 为空时回退到默认 progress。
func _advance_task(task_id: String, progress_key: String, delta: int) -> bool:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return false
	var index := _find_active_task_index(normalized_id)
	if index < 0:
		return false

	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	if index >= active.size():
		return false

	var task_runtime := _dict_or_empty(active[index])
	var key := progress_key.strip_edges()
	if key.is_empty():
		key = "progress"
	var progress := _dict_or_empty(task_runtime.get("progress", {}))
	progress[key] = int(progress.get(key, 0)) + delta
	task_runtime["progress"] = progress
	active[index] = task_runtime
	tasks_state["active"] = active
	world_state["tasks"] = tasks_state
	return true


# 功能：放弃任务。
# 说明：只对 active 任务生效，放弃后会归档到 abandoned 列表。
func _abandon_task(task_id: String) -> bool:
	return _finalize_task(task_id, "abandoned", "manual")


# 功能：完成任务。
# 说明：只对 active 任务生效，完成后会归档到 completed 列表。
func _complete_task(task_id: String) -> bool:
	return _finalize_task(task_id, "completed", "manual")


# 功能：结束 active 任务并归档。
# 说明：封装 completed/abandoned 两类共享迁移动作。
# 功能：统一处理任务终态结算。
# 说明：里程碑 3 在同一入口串联状态归档、完成档位计算、评价后果应用和结果记录。
func _finalize_task(task_id: String, status: String, reason: String = "") -> bool:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return false
	var normalized_status := status.strip_edges().to_lower()
	if normalized_status != "completed" and normalized_status != "failed" and normalized_status != "abandoned":
		return false

	var index := _find_active_task_index(normalized_id)
	if index < 0:
		return false

	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	if index >= active.size():
		return false
	var task_runtime := _dict_or_empty(active[index]).duplicate(true)
	active.remove_at(index)
	tasks_state["active"] = active

	var score: Variant = null
	var grade_id := ""
	if normalized_status == "completed":
		var task_def := _dict_or_empty(_task_def_map.get(normalized_id, {}))
		var grade_eval := _evaluate_task_grade(task_runtime, task_def)
		score = grade_eval.get("score", null)
		var base_grade_id := str(grade_eval.get("baseGradeId", "")).strip_edges()
		grade_id = _apply_grade_overrides(task_runtime, task_def, base_grade_id)

	_apply_task_evaluation_effects(normalized_id, normalized_status, grade_id)
	_archive_task_id(tasks_state, normalized_status, normalized_id)
	_append_task_result_record(tasks_state, task_runtime, normalized_status, grade_id, score, reason)
	world_state["tasks"] = tasks_state
	return true


# 功能：回合结束后推进任务并处理到期状态。
# 说明：任务到期后按 onExpire 归档，默认归档到 failed。
func _tick_tasks_after_turn() -> void:
	_ensure_task_runtime_state()
	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	if active.is_empty():
		return

	var current_turn := int(world_state.get("turn", 1))
	var expire_actions: Array = []
	for runtime_variant in active:
		var task_runtime := _dict_or_empty(runtime_variant)
		var task_id := str(task_runtime.get("taskId", "")).strip_edges()
		var deadline_turn := int(task_runtime.get("deadlineTurn", 0))
		if task_id.is_empty():
			continue
		if deadline_turn > 0 and current_turn >= deadline_turn:
			var task_def := _dict_or_empty(_task_def_map.get(task_id, {}))
			var on_expire := str(task_def.get("onExpire", "fail")).strip_edges().to_lower()
			var final_status := "failed"
			match on_expire:
				"abandon", "abandoned":
					final_status = "abandoned"
				"complete", "completed", "success":
					final_status = "completed"
			expire_actions.append({"taskId": task_id, "status": final_status, "reason": "expired"})

	for action_variant in expire_actions:
		var action := _dict_or_empty(action_variant)
		var task_id := str(action.get("taskId", "")).strip_edges()
		var status := str(action.get("status", "failed")).strip_edges()
		var reason := str(action.get("reason", "expired")).strip_edges()
		_finalize_task(task_id, status, reason)

# 功能：计算任务完成时的基础档位。
# 说明：按指标累计 score，再映射 score_band 得到 baseGradeId。
func _evaluate_task_grade(task_runtime: Dictionary, task_def: Dictionary) -> Dictionary:
	var task_id := str(task_runtime.get("taskId", task_def.get("id", ""))).strip_edges()
	if task_id.is_empty():
		return {"score": 0, "baseGradeId": ""}
	var eval_bucket := _dict_or_empty(_task_eval_index_by_task.get(task_id, {}))
	if eval_bucket.is_empty():
		return {"score": 0, "baseGradeId": ""}

	var indicators: Array = _array_or_empty(eval_bucket.get("indicators", []))
	var score := 0
	for indicator_variant in indicators:
		var indicator := _dict_or_empty(indicator_variant)
		var left := str(indicator.get("left", "")).strip_edges()
		var op := str(indicator.get("op", "")).strip_edges()
		var right := str(indicator.get("right", "")).strip_edges()
		if left.is_empty() or op.is_empty() or right.is_empty():
			score += int(indicator.get("failScore", 0))
			continue
		var actual: Variant = _resolve_task_condition_value(task_runtime, left)
		var expected: Variant = _parse_literal(right)
		if _compare_values(actual, op, expected):
			score += int(indicator.get("passScore", 0))
		else:
			score += int(indicator.get("failScore", 0))

	var base_grade_id := ""
	var score_bands: Array = _array_or_empty(eval_bucket.get("scoreBands", []))
	for grade_variant in score_bands:
		var grade := _dict_or_empty(grade_variant)
		var min_score := float(grade.get("minScore", 0.0))
		var max_score := float(grade.get("maxScore", 0.0))
		if float(score) >= min_score and float(score) <= max_score:
			base_grade_id = str(grade.get("gradeId", "")).strip_edges()
			break

	return {"score": score, "baseGradeId": base_grade_id}


# 功能：应用任务档位分流规则。
# 说明：按 priority 降序匹配，命中首条即返回最终档位。
func _apply_grade_overrides(task_runtime: Dictionary, task_def: Dictionary, base_grade: String) -> String:
	var task_id := str(task_runtime.get("taskId", task_def.get("id", ""))).strip_edges()
	if task_id.is_empty():
		return base_grade
	var eval_bucket := _dict_or_empty(_task_eval_index_by_task.get(task_id, {}))
	if eval_bucket.is_empty():
		return base_grade

	var final_grade := base_grade
	var grade_overrides: Array = _array_or_empty(eval_bucket.get("gradeOverrides", []))
	for override_variant in grade_overrides:
		var override_row := _dict_or_empty(override_variant)
		var from_grade_id := str(override_row.get("fromGradeId", "")).strip_edges()
		if not from_grade_id.is_empty() and from_grade_id != final_grade:
			continue
		var when_condition := str(override_row.get("when", "")).strip_edges()
		if not when_condition.is_empty() and not _is_task_complete_when_satisfied(task_runtime, when_condition):
			continue
		var to_grade_id := str(override_row.get("toGradeId", "")).strip_edges()
		if to_grade_id.is_empty():
			continue
		final_grade = to_grade_id
		break
	return final_grade


# 功能：按 task/status/grade 应用任务评价后果。
# 说明：优先精确命中 gradeId，若无精确项则回退到 gradeId 为空的通配项。
func _apply_task_evaluation_effects(task_id: String, status: String, grade_id: String) -> void:
	var normalized_task_id := task_id.strip_edges()
	var normalized_status := status.strip_edges().to_lower()
	if normalized_task_id.is_empty() or normalized_status.is_empty():
		return
	var eval_bucket := _dict_or_empty(_task_eval_index_by_task.get(normalized_task_id, {}))
	if eval_bucket.is_empty():
		return

	var effect_rows: Array = _array_or_empty(eval_bucket.get("effects", []))
	if effect_rows.is_empty():
		return

	var exact_effects: Array = []
	var fallback_effects: Array = []
	for effect_variant in effect_rows:
		var effect := _dict_or_empty(effect_variant)
		var row_status := str(effect.get("status", "")).strip_edges().to_lower()
		if row_status != normalized_status:
			continue
		var row_grade_id := str(effect.get("gradeId", "")).strip_edges()
		if not row_grade_id.is_empty() and row_grade_id == grade_id:
			exact_effects.append(effect)
		elif row_grade_id.is_empty():
			fallback_effects.append(effect)

	var matched_effects: Array = exact_effects if not exact_effects.is_empty() else fallback_effects
	for effect_variant in matched_effects:
		_apply_task_evaluation_effect_action(_dict_or_empty(effect_variant))


# 功能：执行单条任务评价效果动作。
# 说明：动作语义与配置侧 option_rules/event_outcomes 保持一致。
func _apply_task_evaluation_effect_action(effect: Dictionary) -> void:
	var target := str(effect.get("target", "")).strip_edges()
	var op := str(effect.get("op", "")).strip_edges()
	var key := str(effect.get("key", "")).strip_edges()
	var value_text := str(effect.get("value", "")).strip_edges()

	if target == "params" and op == "add":
		if key.is_empty():
			return
		_apply_world_state_patch({"params": {key: int(_parse_literal(value_text))}})
		return

	if target == "flags" and op == "set":
		if key.is_empty():
			return
		_apply_world_state_patch({"flags": {key: _parse_literal(value_text)}})
		return

	if target == "player" and op == "add":
		if key.is_empty():
			return
		_apply_world_state_patch({"player": {key: int(_parse_literal(value_text))}})
		return

	if target == "world" and op == "set_location":
		_apply_world_state_patch({"currentLocationId": value_text})
		return

	if target == "world" and op == "set_forced_next":
		world_state["forcedNextEventId"] = value_text
		return

	if target == "world" and op == "clear_forced_next":
		if _to_bool_text(value_text):
			world_state["forcedNextEventId"] = ""
		return

	if target == "world" and op == "end_chain":
		if _to_bool_text(value_text):
			world_state["chainContext"] = null
		return


# 功能：写入任务终态记录。
# 说明：用于验收和后续 UI 展示，保留任务完成时快照信息。
func _append_task_result_record(
	tasks_state: Dictionary,
	task_runtime: Dictionary,
	status: String,
	grade_id: String,
	score: Variant,
	reason: String
) -> void:
	var task_id := str(task_runtime.get("taskId", "")).strip_edges()
	if task_id.is_empty():
		return
	var result_records := _array_or_empty(tasks_state.get("resultRecords", []))
	result_records.append(
		{
			"taskId": task_id,
			"status": status,
			"gradeId": grade_id,
			"score": score,
			"acceptedTurn": int(task_runtime.get("acceptedTurn", 0)),
			"finishedTurn": int(world_state.get("turn", 0)),
			"reason": reason,
			"progress": _dict_or_empty(task_runtime.get("progress", {})).duplicate(true)
		}
	)
	tasks_state["resultRecords"] = result_records


# 功能：将文本转换为 bool。
# 说明：仅文本 true 视为 true，其余一律 false。
func _to_bool_text(raw: String) -> bool:
	return raw.strip_edges().to_lower() == "true"


# 功能：在结算后评估并自动完成任务。
# 说明：判定时机为“事件/选项动作全部落地后，任务回合推进前”，保证同回合达成不会被到期失败覆盖。
func _eval_complete_when_after_settlement() -> void:
	_ensure_task_runtime_state()
	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	if active.is_empty():
		return

	var complete_ids: Array = []
	for runtime_variant in active:
		var task_runtime := _dict_or_empty(runtime_variant)
		var task_id := str(task_runtime.get("taskId", "")).strip_edges()
		if task_id.is_empty():
			continue
		var task_def := _dict_or_empty(_task_def_map.get(task_id, {}))
		if task_def.is_empty():
			continue
		var complete_when := str(task_def.get("completeWhen", "")).strip_edges()
		if complete_when.is_empty():
			continue
		if _is_task_complete_when_satisfied(task_runtime, complete_when):
			complete_ids.append(task_id)

	for task_id_variant in complete_ids:
		_complete_task(str(task_id_variant))


# 功能：判断任务 complete_when 是否命中。
# 说明：表达式格式为 "<path> <op> <literal>"，支持路径来源 task/progress/world_state。
func _is_task_complete_when_satisfied(task_runtime: Dictionary, condition: String) -> bool:
	var operators := [">=", "<=", "==", "!=", ">", "<"]
	for op_variant in operators:
		var op := str(op_variant)
		var token := " %s " % op
		if condition.find(token) == -1:
			continue
		var parts := condition.split(token)
		if parts.size() != 2:
			return false
		var left_text := str(parts[0]).strip_edges()
		var right_text := str(parts[1]).strip_edges()
		var actual: Variant = _resolve_task_condition_value(task_runtime, left_text)
		var expected: Variant = _parse_literal(right_text)
		return _compare_values(actual, op, expected)
	return false


# 功能：解析任务条件表达式左值。
# 说明：支持 progress.*、task.*，其余按 world_state 路径读取。
func _resolve_task_condition_value(task_runtime: Dictionary, path: String) -> Variant:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		return null

	if normalized_path.begins_with("progress."):
		var key_path := normalized_path.trim_prefix("progress.")
		return _resolve_dict_path(_dict_or_empty(task_runtime.get("progress", {})), key_path)

	if normalized_path == "progress":
		return _dict_or_empty(task_runtime.get("progress", {}))

	if normalized_path.begins_with("task."):
		var task_path := normalized_path.trim_prefix("task.")
		return _resolve_dict_path(task_runtime, task_path)

	return _resolve_path_value(normalized_path)


# 功能：按点路径读取字典值。
# 说明：任意层级缺失时返回 null。
func _resolve_dict_path(source: Dictionary, path: String) -> Variant:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		return null
	var segments := normalized_path.split(".", false)
	if segments.is_empty():
		return null

	var cursor: Variant = source
	for segment_variant in segments:
		var segment := str(segment_variant).strip_edges()
		if segment.is_empty():
			return null
		if typeof(cursor) != TYPE_DICTIONARY:
			return null
		var dict_cursor: Dictionary = cursor
		if not dict_cursor.has(segment):
			return null
		cursor = dict_cursor[segment]
	return cursor


# 功能：查找 active 任务下标。
# 说明：未找到时返回 -1。
func _find_active_task_index(task_id: String) -> int:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return -1
	var tasks_state := _dict_or_empty(world_state.get("tasks", {}))
	var active := _array_or_empty(tasks_state.get("active", []))
	for idx in range(active.size()):
		var task_runtime := _dict_or_empty(active[idx])
		if str(task_runtime.get("taskId", "")).strip_edges() == normalized_id:
			return idx
	return -1


# 功能：归档任务 ID。
# 说明：同一归档列表内会做去重，避免重复写入。
func _archive_task_id(tasks_state: Dictionary, archive_key: String, task_id: String) -> void:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return
	var archive := _array_or_empty(tasks_state.get(archive_key, []))
	for item_variant in archive:
		if str(item_variant).strip_edges() == normalized_id:
			tasks_state[archive_key] = archive
			return
	archive.append(normalized_id)
	tasks_state[archive_key] = archive


# 功能：从所有归档列表移除任务 ID。
# 说明：接取任务时执行此操作，保证任务只存在于 active 或单一归档槽位。
func _remove_task_id_from_archives(tasks_state: Dictionary, task_id: String) -> void:
	var normalized_id := task_id.strip_edges()
	if normalized_id.is_empty():
		return
	var archive_keys := ["completed", "failed", "abandoned"]
	for key_variant in archive_keys:
		var key := str(key_variant)
		var source := _array_or_empty(tasks_state.get(key, []))
		var filtered: Array = []
		for item_variant in source:
			if str(item_variant).strip_edges() != normalized_id:
				filtered.append(item_variant)
		tasks_state[key] = filtered

# 功能：应用 worldStatePatch 到 world_state。
# 说明：params 与 player 为增量写入，flags 为覆盖写入。
func _apply_world_state_patch(patch: Dictionary) -> void:
	if patch.is_empty():
		return

	var flags_patch: Dictionary = patch.get("flags", {})
	if not flags_patch.is_empty():
		var flags: Dictionary = world_state.get("flags", {})
		for key in flags_patch.keys():
			flags[str(key)] = flags_patch[key]
		world_state["flags"] = flags

	var params_patch: Dictionary = patch.get("params", {})
	if not params_patch.is_empty():
		var params: Dictionary = world_state.get("params", {})
		for key in params_patch.keys():
			var param_key := str(key)
			params[param_key] = int(params.get(param_key, 0)) + int(params_patch[key])
		world_state["params"] = params

	var player_patch: Dictionary = patch.get("player", {})
	if not player_patch.is_empty():
		var player: Dictionary = world_state.get("player", {})
		for key in player_patch.keys():
			var player_key := str(key)
			player[player_key] = int(player.get(player_key, 0)) + int(player_patch[key])
		world_state["player"] = player

	var set_location := str(patch.get("currentLocationId", "")).strip_edges()
	if not set_location.is_empty():
		world_state["currentLocationId"] = set_location

# 功能：合并两个字典。
# 说明：right 覆盖 left 的同名键，并返回新字典。
func _merge_dict(left: Dictionary, right: Dictionary) -> Dictionary:
	var merged := left.duplicate(true)
	for key in right.keys():
		merged[key] = right[key]
	return merged

# 功能：将任意值安全转换为 Dictionary。
# 说明：JSON 允许 null；这里统一收敛为 {}，避免 Nil 到 Dictionary 的赋值错误。
func _dict_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY and value != null:
		return value
	return {}

# 功能：将任意值安全转换为 Array。
# 说明：与 _dict_or_empty 同理，用于兼容 visibilityWhen 等可选数组字段。
func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY and value != null:
		return value
	return []
