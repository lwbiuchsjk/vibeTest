extends Control

const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const EventCard := preload("res://scripts/ui/event_card.gd")
const EventCardScene := preload("res://scripts/ui/event_card.tscn")

@onready var status_label: Label = $Root/StatusLabel
@onready var event_list: HBoxContainer = $Root/EventScroll/EventList

# 功能：加载配置并渲染事件配置列表。
# 说明：统一通过 ConfigRuntime 获取 world_event 快照，列表展示由 EventCard 预制组件负责。
func _ready() -> void:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded({}, true)
	if not load_result.get("ok", false):
		status_label.text = "Load failed: %s" % str(load_result.get("error", "unknown"))
		return

	var world_event_data := runtime.get_world_event_data()
	var events_variant: Variant = world_event_data.get("events", [])
	if typeof(events_variant) != TYPE_ARRAY:
		status_label.text = "Invalid events data type."
		return

	var events: Array = events_variant
	if events.is_empty():
		status_label.text = "No event data found."
		return

	var choice_point_map := _build_choice_point_map(world_event_data.get("choice_points", []))
	_render_events(events, choice_point_map)
	status_label.text = "Loaded %d events" % events.size()


# 功能：渲染所有事件卡片。
# 说明：每个事件占一列，具体内容由 EventCard 组件内部处理。
func _render_events(events: Array, choice_point_map: Dictionary) -> void:
	for child in event_list.get_children():
		child.queue_free()

	for event_variant in events:
		if typeof(event_variant) != TYPE_DICTIONARY:
			continue
		var event_def: Dictionary = event_variant
		var event_card: EventCard = EventCardScene.instantiate()
		event_list.add_child(event_card)
		event_card.bind_data(event_def, choice_point_map)


# 功能：构建 choice point 索引。
# 说明：将 choice_points 数组映射为 {choice_point_id: choice_point_def}，供 EventCard 关联选项。
func _build_choice_point_map(choice_points_variant: Variant) -> Dictionary:
	var cp_map: Dictionary = {}
	if typeof(choice_points_variant) != TYPE_ARRAY:
		return cp_map

	for cp_variant in choice_points_variant:
		if typeof(cp_variant) != TYPE_DICTIONARY:
			continue
		var cp: Dictionary = cp_variant
		var cp_id := str(cp.get("id", "")).strip_edges()
		if cp_id.is_empty():
			continue
		cp_map[cp_id] = cp
	return cp_map
