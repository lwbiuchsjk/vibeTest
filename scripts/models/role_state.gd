extends RefCounted
class_name RoleState

# 角色形象资源固定目录：配置中只填写文件名（如 icon.svg）。
const PORTRAIT_BASE_DIR := "res://assets/art/characters/portraits"

# 玩家与 NPC 共用的角色状态模型。
var role_id: String
var role_type: String
var display_name: String
var location_id: String
var portrait_file: String
var attributes: Dictionary
var resources: Dictionary

# 初始化角色数据。字典会深拷贝，避免外部引用污染内部状态。
func _init(
	p_role_id: String = "",
	p_role_type: String = "npc",
	p_display_name: String = "",
	p_location_id: String = "",
	p_portrait_file: String = "",
	p_attributes: Dictionary = {},
	p_resources: Dictionary = {}
) -> void:
	role_id = p_role_id
	role_type = p_role_type
	display_name = p_display_name
	location_id = p_location_id
	portrait_file = p_portrait_file.strip_edges()
	attributes = p_attributes.duplicate(true)
	resources = p_resources.duplicate(true)

func has_portrait() -> bool:
	return not portrait_file.is_empty()

func get_portrait_path() -> String:
	if not has_portrait():
		return ""
	return "%s/%s" % [PORTRAIT_BASE_DIR, portrait_file]

func load_portrait_texture() -> Texture2D:
	if not has_portrait():
		return null

	var portrait_path := get_portrait_path()
	var resource := ResourceLoader.load(portrait_path)
	if resource is Texture2D:
		return resource

	# 兜底：若资源未被导入，尝试按文件直接加载。
	return _load_texture_from_file(portrait_path)

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

# 序列化为 Dictionary，便于存档、传输与调试输出。
func to_dict() -> Dictionary:
	return {
		"role_id": role_id,
		"role_type": role_type,
		"display_name": display_name,
		"location_id": location_id,
		"portrait_file": portrait_file,
		"attributes": attributes.duplicate(true),
		"resources": resources.duplicate(true)
	}

# 从 Dictionary 快照反序列化为 RoleState。
static func from_dict(data: Dictionary) -> RoleState:
	return RoleState.new(
		str(data.get("role_id", "")),
		str(data.get("role_type", "npc")),
		str(data.get("display_name", "")),
		str(data.get("location_id", "")),
		str(data.get("portrait_file", "")),
		data.get("attributes", {}),
		data.get("resources", {})
	)

static func _load_texture_from_file(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null

	var image := Image.new()
	var err := image.load(path)
	if err == OK:
		return ImageTexture.create_from_image(image)

	# SVG 文件在未导入时走字符串解析兜底。
	if path.get_extension().to_lower() == "svg":
		var svg_text := FileAccess.get_file_as_string(path)
		if svg_text.is_empty():
			return null
		var svg_image := Image.new()
		var svg_err := svg_image.load_svg_from_string(svg_text)
		if svg_err == OK:
			return ImageTexture.create_from_image(svg_image)

	return null
