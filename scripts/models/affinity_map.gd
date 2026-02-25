extends RefCounted
class_name AffinityMap

# 存储有向关系分值，键格式为：from->to。
var _scores: Dictionary = {}

# 生成有向关系键。A->B 与 B->A 是两条独立关系。
func _pair_key(from_role_id: String, to_role_id: String) -> String:
	return "%s->%s" % [from_role_id, to_role_id]

# 获取关系分值；当键不存在时返回默认值（默认0）。
func get_score(from_role_id: String, to_role_id: String, default_value: int = 0) -> int:
	return int(_scores.get(_pair_key(from_role_id, to_role_id), default_value))

# 设置关系分值。边界裁剪由规则层处理。
func set_score(from_role_id: String, to_role_id: String, score: int) -> void:
	_scores[_pair_key(from_role_id, to_role_id)] = score

# 导出完整关系表。
func to_dict() -> Dictionary:
	return _scores.duplicate(true)

# 从Dictionary恢复关系表。
static func from_dict(data: Dictionary) -> AffinityMap:
	var map := AffinityMap.new()
	map._scores = data.duplicate(true)
	return map
