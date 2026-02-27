extends PanelContainer
class_name EventCard

const EventOptionCard := preload("res://scripts/ui/event_option_card.gd")
const EventOptionCardScene := preload("res://scripts/ui/event_option_card.tscn")

var title_label: Label
var detail_label: RichTextLabel
var options_container: VBoxContainer


func _ready() -> void:
	_cache_nodes()


# 功能：绑定事件与选择点映射并刷新卡片。
# 说明：将事件基础信息与下属选项统一渲染，供外部场景直接复用。
func bind_data(event_def: Dictionary, choice_point_map: Dictionary) -> void:
	_cache_nodes()
	if title_label == null or detail_label == null or options_container == null:
		push_warning("EventCard node binding is incomplete.")
		return

	title_label.text = "%s | %s" % [
		str(event_def.get("id", "")),
		str(event_def.get("title", ""))
	]
	detail_label.text = _build_event_detail_text(event_def)
	_render_event_options(event_def, choice_point_map)


# 功能：缓存组件内部节点引用。
# 说明：避免重复 get_node，并兼容先 bind 再 add_child 的调用顺序。
func _cache_nodes() -> void:
	if title_label != null:
		return
	title_label = get_node_or_null("Content/TitleLabel") as Label
	detail_label = get_node_or_null("Content/DetailLabel") as RichTextLabel
	options_container = get_node_or_null("Content/OptionsContainer") as VBoxContainer


# 功能：构建事件详情文本。
# 说明：输出事件必要配置字段，便于快速核对数据。
func _build_event_detail_text(event_def: Dictionary) -> String:
	var base_weight := int(event_def.get("baseWeight", 0))
	var policy := str(event_def.get("continuationPolicy", ""))
	var choice_point_id := str(event_def.get("choicePointId", ""))
	var tags := _array_to_text(_to_string_array(event_def.get("tags", [])), ", ")
	var eligibility := _format_eligibility(event_def.get("eligibility", {}))
	var effects := _format_effects(event_def.get("effects", {}))

	var lines: Array = [
		"baseWeight: %d" % base_weight,
		"continuationPolicy: %s" % policy,
		"choicePointId: %s" % (choice_point_id if not choice_point_id.is_empty() else "-"),
		"tags: %s" % tags,
		"eligibility: %s" % eligibility,
		"effects: %s" % effects
	]
	return _join_items(lines, "\n")


# 功能：渲染事件下方的选项组件列表。
# 说明：按 choicePointId 关联配置，将每个选项实例化为独立组件卡片。
func _render_event_options(event_def: Dictionary, choice_point_map: Dictionary) -> void:
	for child in options_container.get_children():
		child.queue_free()

	var cp_id := str(event_def.get("choicePointId", "")).strip_edges()
	if cp_id.is_empty():
		_add_hint_label("-")
		return
	if not choice_point_map.has(cp_id):
		_add_hint_label("missing choice point (%s)" % cp_id)
		return

	var cp: Dictionary = choice_point_map[cp_id]
	var options_variant: Variant = cp.get("options", [])
	if typeof(options_variant) != TYPE_ARRAY:
		_add_hint_label("invalid options format (%s)" % cp_id)
		return

	var options: Array = options_variant
	if options.is_empty():
		_add_hint_label("empty (%s)" % cp_id)
		return

	for option_variant in options:
		if typeof(option_variant) != TYPE_DICTIONARY:
			continue
		var option: Dictionary = option_variant
		var option_card: EventOptionCard = EventOptionCardScene.instantiate()
		options_container.add_child(option_card)
		option_card.bind_data(option)


# 功能：在选项容器中添加提示文本。
# 说明：用于处理无 choice point 或配置异常时的占位显示。
func _add_hint_label(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	options_container.add_child(label)


# 功能：格式化 eligibility 信息。
# 说明：将复杂字典展开为可读文本，便于策划快速核对约束。
func _format_eligibility(eligibility_variant: Variant) -> String:
	if typeof(eligibility_variant) != TYPE_DICTIONARY:
		return "-"
	var eligibility: Dictionary = eligibility_variant
	if eligibility.is_empty():
		return "-"

	var parts: Array = []
	var locations := _to_string_array(eligibility.get("requiredLocations", []))
	if not locations.is_empty():
		parts.append("locations=[%s]" % _array_to_text(locations, ", "))

	var npcs := _to_string_array(eligibility.get("requiredNPCsPresent", []))
	if not npcs.is_empty():
		parts.append("npcs=[%s]" % _array_to_text(npcs, ", "))

	var flags_variant: Variant = eligibility.get("requiredLocationFlags", [])
	if typeof(flags_variant) == TYPE_ARRAY:
		var flag_chunks: Array = []
		for item_variant in flags_variant:
			var item: Dictionary = item_variant
			flag_chunks.append(
				"%s %s %s" % [
					str(item.get("key", "")),
					str(item.get("op", "==")),
					str(item.get("value", ""))
				]
			)
		if not flag_chunks.is_empty():
			parts.append("locationFlags=[%s]" % _array_to_text(flag_chunks, "; "))

	if parts.is_empty():
		return "-"
	return _array_to_text(parts, " | ")


# 功能：格式化 effects 信息。
# 说明：统一输出常见效果字段，减少阅读成本。
func _format_effects(effects_variant: Variant) -> String:
	if typeof(effects_variant) != TYPE_DICTIONARY:
		return "-"
	var effects: Dictionary = effects_variant
	if effects.is_empty():
		return "-"

	var parts: Array = []
	for key_variant in effects.keys():
		var key := str(key_variant)
		var value: Variant = effects[key_variant]
		if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
			parts.append("%s=%s" % [key, JSON.stringify(value)])
		else:
			parts.append("%s=%s" % [key, str(value)])
	return _array_to_text(parts, " | ")


# 功能：将 Variant 数组转换为字符串数组。
# 说明：展示层统一处理，避免类型不一致导致报错。
func _to_string_array(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(str(item))
	return out


# 功能：数组转文本。
# 说明：空数组时返回 "-"，便于界面显示。
func _array_to_text(items: Array, sep: String) -> String:
	if items.is_empty():
		return "-"
	return _join_items(items, sep)


# 功能：将字符串数组按分隔符拼接。
# 说明：手动拼接以兼容不支持 String.join 的运行环境。
func _join_items(items: Array, sep: String) -> String:
	var out := ""
	for i in range(items.size()):
		if i > 0:
			out += sep
		out += str(items[i])
	return out
