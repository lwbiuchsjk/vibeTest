extends RefCounted
class_name LocationGraph

# 地点邻接图：location_id -> neighbor_ids[]。
var adjacency: Dictionary = {}

# 设置某地点的邻接列表，并统一转换为String。
func set_neighbors(location_id: String, neighbors: Array) -> void:
	var normalized: Array[String] = []
	for n in neighbors:
		normalized.append(str(n))
	adjacency[location_id] = normalized

# 获取某地点邻接列表；不存在时返回空数组。
func get_neighbors(location_id: String) -> Array[String]:
	var raw: Array = adjacency.get(location_id, [])
	var out: Array[String] = []
	for n in raw:
		out.append(str(n))
	return out

# 移动判定：同地点可达，否则必须在邻接列表中。
func is_neighbor(from_location_id: String, to_location_id: String) -> bool:
	if from_location_id == to_location_id:
		return true
	return to_location_id in get_neighbors(from_location_id)

# 导出邻接图数据。
func to_dict() -> Dictionary:
	return adjacency.duplicate(true)

# 从Dictionary恢复邻接图数据。
static func from_dict(data: Dictionary) -> LocationGraph:
	var graph := LocationGraph.new()
	for key in data.keys():
		var location_id := str(key)
		var neighbors: Array = data[key]
		graph.set_neighbors(location_id, neighbors)
	return graph
