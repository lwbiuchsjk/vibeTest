extends PanelContainer
class_name EventOptionCard

# 组件节点缓存
var title_label: Label
var meta_label: Label
var detail_label: RichTextLabel


func _ready() -> void:
	_cache_nodes()


# 功能：绑定选项数据并刷新组件显示。
# 说明：用于事件展示页将每个选项渲染为独立组件卡片。
func bind_data(option_def: Dictionary) -> void:
	_cache_nodes()
	if title_label == null or meta_label == null or detail_label == null:
		push_warning("EventOptionCard node binding is incomplete.")
		return

	var option_id := str(option_def.get("id", ""))
	var option_text := str(option_def.get("text", ""))
	title_label.text = "%s | %s" % [option_id, option_text]

	var cost_text := _format_kv_dict(option_def.get("cost", {}))
	var check_text := _format_check(option_def.get("check", null))
	meta_label.text = "cost: %s | check: %s" % [
		(cost_text if not cost_text.is_empty() else "-"),
		(check_text if not check_text.is_empty() else "-")
	]

	var eligibility_text := _format_kv_dict(option_def.get("eligibility", {}))
	var resolution_text := _format_resolution(option_def.get("resolution", {}))
	detail_label.text = "eligibility: %s\nresolution: %s" % [
		(eligibility_text if not eligibility_text.is_empty() else "-"),
		(resolution_text if not resolution_text.is_empty() else "-")
	]


# 功能：缓存组件内部节点引用。
# 说明：避免重复 get_node 并兼容先 bind 再 add_child 的调用顺序。
func _cache_nodes() -> void:
	if title_label != null:
		return
	title_label = get_node_or_null("Content/TitleLabel") as Label
	meta_label = get_node_or_null("Content/MetaLabel") as Label
	detail_label = get_node_or_null("Content/DetailLabel") as RichTextLabel


# 功能：格式化通用键值字典。
# 说明：将字典转成紧凑单行，便于组件内展示。
func _format_kv_dict(value_variant: Variant) -> String:
	if typeof(value_variant) != TYPE_DICTIONARY:
		return ""
	var value_dict: Dictionary = value_variant
	if value_dict.is_empty():
		return ""

	var parts: Array = []
	for key_variant in value_dict.keys():
		parts.append("%s=%s" % [str(key_variant), str(value_dict[key_variant])])
	return _join_items(parts, ", ")


# 功能：格式化 check 字段。
# 说明：识别成功率字段并进行摘要展示。
func _format_check(check_variant: Variant) -> String:
	if typeof(check_variant) != TYPE_DICTIONARY:
		return ""
	var check: Dictionary = check_variant
	if check.is_empty():
		return ""

	var check_type := str(check.get("type", "")).strip_edges()
	if check_type.is_empty():
		return ""
	if check.has("successRate"):
		return "%s(%s)" % [check_type, str(check.get("successRate", ""))]
	return check_type


# 功能：格式化 resolution 字段。
# 说明：优先抽取常用关键字段，其他结构化字段以 JSON 兜底。
func _format_resolution(resolution_variant: Variant) -> String:
	if typeof(resolution_variant) != TYPE_DICTIONARY:
		return ""
	var resolution: Dictionary = resolution_variant
	if resolution.is_empty():
		return ""

	var parts: Array = []
	if resolution.has("forcedNextEventId"):
		parts.append("forcedNextEventId=%s" % str(resolution.get("forcedNextEventId", "")))
	if resolution.has("worldStatePatch"):
		parts.append("worldStatePatch=%s" % JSON.stringify(resolution.get("worldStatePatch", {})))
	if resolution.has("chainContextPatch"):
		parts.append("chainContextPatch=%s" % JSON.stringify(resolution.get("chainContextPatch", {})))
	return _join_items(parts, " | ")


# 功能：数组拼接工具。
# 说明：避免依赖 String.join，兼容当前项目运行环境。
func _join_items(items: Array, sep: String) -> String:
	var out := ""
	for i in range(items.size()):
		if i > 0:
			out += sep
		out += str(items[i])
	return out
