## 事件配置展示测试场景
## 用途：可视化验证 world_event 配置数据的加载与渲染流程。
## 流程：ConfigRuntime 加载配置 → 提取 events 和 choice_points → 逐事件实例化 EventCard 展示。
## 依赖：ConfigRuntime（配置加载与缓存）、EventCard/EventCardScene（单事件卡片 UI）。
extends Control

const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const EventCard := preload("res://scripts/ui/event_card.gd")
const EventCardScene := preload("res://scripts/ui/event_card.tscn")

@onready var status_label: Label = $Root/StatusLabel   ## 顶部状态提示，显示加载结果或错误信息
@onready var event_list: HBoxContainer = $Root/EventScroll/EventList  ## 水平滚动容器，承载所有事件卡片

# 功能：场景入口，加载配置并渲染事件列表。
# 流程：ensure_loaded() 初始化配置 → 取 world_event 数据 → 构建 choice_point 索引 → 渲染卡片。
# 错误处理：加载失败、数据类型异常、事件为空均会在 status_label 中给出提示。
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
# 说明：先清空旧子节点，再逐条实例化 EventCard 并通过 bind_data() 绑定数据。
# 参数：events — 事件定义数组；choice_point_map — {choice_point_id: 定义} 索引，传递给卡片用于关联选项。
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
# 参数：choice_points_variant — 来自 world_event_data 的原始 choice_points，类型不确定需校验。
# 返回：Dictionary，键为 choice_point id（String），值为完整的 choice_point 定义（Dictionary）。
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
