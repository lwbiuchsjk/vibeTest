extends PanelContainer
class_name TaskSummaryCard

var _task_info_label: RichTextLabel


# 功能：缓存组件内部节点引用。
# 说明：避免外部每次刷新任务摘要时重复查找节点。
func _ready() -> void:
	_cache_nodes()


# 功能：绑定任务摘要数据并刷新显示。
# 说明：组件只负责展示进行中的任务和当前事件关联任务，不关心外部事件流转细节。
func bind_data(active_tasks: Array, task_links: Array, current_turn: int) -> void:
	_cache_nodes()
	if _task_info_label == null:
		push_warning("TaskSummaryCard node binding is incomplete.")
		return
	_task_info_label.text = _build_summary_text(active_tasks, task_links, current_turn)
	_task_info_label.call_deferred("scroll_to_line", 0)


# 功能：缓存任务摘要文本节点。
# 说明：允许场景先实例化、后绑定数据，兼容不同调用时机。
func _cache_nodes() -> void:
	if _task_info_label != null:
		return
	_task_info_label = get_node_or_null("TaskMargin/TaskContent/TaskInfo") as RichTextLabel


# 功能：构建任务摘要富文本。
# 说明：将进行中的任务和当前事件关联任务拆成两组，方便在左侧面板快速扫读。
func _build_summary_text(active_tasks: Array, task_links: Array, current_turn: int) -> String:
	var lines: Array[String] = []

	lines.append("[color=#1f2937][b]进行中的任务[/b][/color]")
	if active_tasks.is_empty():
		lines.append("[color=#6b7280]当前没有进行中的任务[/color]")
	else:
		for task_variant in active_tasks:
			var task: Dictionary = _to_dict(task_variant)
			var deadline_turn := int(task.get("deadlineTurn", 0))
			var turns_left: int = max(0, deadline_turn - current_turn)
			lines.append(
				"[color=#1d4d4f][b]%s[/b][/color]  [color=#0f766e]剩余 %s 回合[/color]" % [
					str(task.get("taskId", "")),
					str(turns_left)
				]
			)

	lines.append("")
	lines.append("[color=#1f2937][b]当前事件关联任务[/b][/color]")
	if task_links.is_empty():
		lines.append("[color=#6b7280]当前事件没有任务关联[/color]")
	else:
		for link_variant in task_links:
			lines.append("[color=#8a5a14][b]%s[/b][/color]" % _format_task_link_text(str(link_variant)))

	return "\n".join(lines)


# 功能：格式化 taskLinks 文本。
# 说明：将 advance/risk 语义转换为更易读的展示文案。
func _format_task_link_text(raw_link: String) -> String:
	var normalized_link := raw_link.strip_edges()
	if normalized_link.is_empty():
		return "未配置"

	var parts := normalized_link.split(":", false, 1)
	if parts.size() != 2:
		return normalized_link

	var link_type := str(parts[0]).strip_edges()
	var task_id := str(parts[1]).strip_edges()
	var label := link_type
	match link_type:
		"advance":
			label = "推进"
		"risk":
			label = "风险"
		_:
			label = link_type
	return "%s · %s" % [task_id, label]


# 功能：安全转换任务字典。
# 说明：组件层统一兜底 Variant 输入，避免因数据结构异常导致 UI 崩溃。
func _to_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY and value != null:
		return value
	return {}
