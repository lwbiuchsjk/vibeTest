extends RefCounted
class_name RuleEngine

# 将属性值裁剪到[min_value, max_value]区间，默认最小值为1。
static func clamp_attribute(value: int, min_value: int = 1, max_value: int = 999999) -> int:
	return clampi(value, min_value, max_value)

# 应用资源增减。按设计资源允许为负数。
static func apply_resource_delta(current_value: int, delta: int) -> int:
	return current_value + delta

# 将好感度分值映射为粗粒度档位标签。
static func affinity_tier(score: int) -> String:
	if score < -25:
		return "hatred"
	if score <= 25:
		return "neutral"
	return "favor"

# 应用好感度变化，并裁剪到[-100, 100]后返回分值与档位。
static func apply_affinity_delta(current_score: int, delta: int) -> Dictionary:
	var next_score := clampi(current_score + delta, -100, 100)
	return {
		"score": next_score,
		"tier": affinity_tier(next_score)
	}

# 检查移动是否合法。支持LocationGraph对象或原始Dictionary两种输入。
static func can_move(location_graph: Variant, from_location_id: String, to_location_id: String) -> bool:
	if from_location_id == to_location_id:
		return true
	if location_graph == null:
		return false
	if location_graph.has_method("is_neighbor"):
		return location_graph.is_neighbor(from_location_id, to_location_id)
	if typeof(location_graph) == TYPE_DICTIONARY:
		var neighbors: Array = location_graph.get(from_location_id, [])
		return to_location_id in neighbors
	return false

# 统一应用角色变化入口：
# 1) 属性按最小值1与配置的最大值进行裁剪。
# 2) 资源直接执行加减（允许负数）。
static func apply_role_delta(
	role_state: Variant,
	attribute_deltas: Dictionary,
	resource_deltas: Dictionary,
	attribute_max: Dictionary
) -> Dictionary:
	if role_state == null:
		return {"ok": false, "error": "role_state is null"}
	if not role_state.has_method("get_attribute"):
		return {"ok": false, "error": "role_state does not provide get_attribute"}

	for key in attribute_deltas.keys():
		var attr_key := str(key)
		var current := int(role_state.get_attribute(attr_key, 1))
		var delta := int(attribute_deltas[key])
		var max_value := int(attribute_max.get(attr_key, 99))
		var next_value := clamp_attribute(current + delta, 1, max_value)
		role_state.set_attribute(attr_key, next_value)

	for key in resource_deltas.keys():
		var resource_key := str(key)
		var current_resource := int(role_state.get_resource(resource_key, 0))
		var resource_delta := int(resource_deltas[key])
		var next_resource := apply_resource_delta(current_resource, resource_delta)
		role_state.set_resource(resource_key, next_resource)

	return {"ok": true, "role": role_state.to_dict()}
