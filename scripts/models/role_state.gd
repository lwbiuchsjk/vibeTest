extends RefCounted
class_name RoleState

# 玩家与NPC共用的角色状态模型。
var role_id: String
var role_type: String
var display_name: String
var location_id: String
var portrait_path: String
var attributes: Dictionary
var resources: Dictionary

# 初始化角色数据。字典会深拷贝，避免外部引用污染内部状态。
func _init(
	p_role_id: String = "",
	p_role_type: String = "npc",
	p_display_name: String = "",
	p_location_id: String = "",
	p_portrait_path: String = "",
	p_attributes: Dictionary = {},
	p_resources: Dictionary = {}
) -> void:
	role_id = p_role_id
	role_type = p_role_type
	display_name = p_display_name
	location_id = p_location_id
	portrait_path = p_portrait_path
	attributes = p_attributes.duplicate(true)
	resources = p_resources.duplicate(true)

func has_portrait() -> bool:
	return not portrait_path.strip_edges().is_empty()

func load_portrait_texture() -> Texture2D:
	if not has_portrait():
		return null
	if not ResourceLoader.exists(portrait_path):
		return null
	var resource := load(portrait_path)
	if resource is Texture2D:
		return resource
	return null

# 获取属性值；当键不存在时返回默认值（默认1）。
func get_attribute(key: String, default_value: int = 1) -> int:
	return int(attributes.get(key, default_value))

# 设置属性值。边界裁剪由规则层统一处理。
func set_attribute(key: String, value: int) -> void:
	attributes[key] = value

# 获取资源值；当键不存在时返回默认值（默认0）。
func get_resource(key: String, default_value: int = 0) -> int:
	return int(resources.get(key, default_value))

# 设置资源值。按设计允许负数。
func set_resource(key: String, value: int) -> void:
	resources[key] = value

# 序列化为Dictionary，便于存档、传输与调试输出。
func to_dict() -> Dictionary:
	return {
		"role_id": role_id,
		"role_type": role_type,
		"display_name": display_name,
		"location_id": location_id,
		"portrait_path": portrait_path,
		"attributes": attributes.duplicate(true),
		"resources": resources.duplicate(true)
	}

# 从Dictionary快照反序列化为RoleState。
static func from_dict(data: Dictionary) -> RoleState:
	return RoleState.new(
		str(data.get("role_id", "")),
		str(data.get("role_type", "npc")),
		str(data.get("display_name", "")),
		str(data.get("location_id", "")),
		str(data.get("portrait_path", "")),
		data.get("attributes", {}),
		data.get("resources", {})
	)
