extends PanelContainer
class_name RoleCard

const RoleState := preload("res://scripts/models/role_state.gd")
const LocationGraph := preload("res://scripts/models/location_graph.gd")

# 预制内核心节点引用（通过 _cache_nodes 延迟绑定，避免 onready 时机限制）。
var portrait: TextureRect
var portrait_missing_label: Label
var name_label: Label
var location_name_label: Label
var location_art: TextureRect
var location_art_missing_label: Label

func _ready() -> void:
	# 进入场景树后预热一次节点缓存。
	_cache_nodes()

# 对外绑定入口：传入角色数据和地点图，刷新卡片可见内容。
func bind_data(role: RoleState, graph: LocationGraph) -> void:
	# 兼容“先 bind_data 后 add_child”的调用顺序。
	_cache_nodes()
	if name_label == null or portrait == null or portrait_missing_label == null:
		push_warning("RoleCard node binding is incomplete.")
		return
	if location_name_label == null or location_art == null or location_art_missing_label == null:
		push_warning("RoleCard location node binding is incomplete.")
		return

	# 角色基础信息
	name_label.text = role.display_name

	# 角色立绘信息（缺失时显示提示文本）
	portrait.texture = role.load_portrait_texture()
	portrait_missing_label.visible = portrait.texture == null
	if portrait_missing_label.visible:
		portrait_missing_label.text = "No portrait: %s" % role.get_portrait_path()

	# 地点信息（名称 + 地点美术）
	location_name_label.text = "地点：%s" % graph.get_display_name(role.location_id)
	location_art.texture = graph.load_art_texture(role.location_id)
	location_art_missing_label.visible = location_art.texture == null
	if location_art_missing_label.visible:
		location_art_missing_label.text = "地点美术缺失：%s" % graph.get_art_path(role.location_id)

# 懒加载并缓存预制节点，避免重复 get_node 和空引用问题。
func _cache_nodes() -> void:
	if name_label != null:
		return
	portrait = get_node_or_null("Content/Portrait") as TextureRect
	portrait_missing_label = get_node_or_null("Content/PortraitMissingLabel") as Label
	name_label = get_node_or_null("Content/NameLabel") as Label
	location_name_label = get_node_or_null("Content/LocationNameLabel") as Label
	location_art = get_node_or_null("Content/LocationArt") as TextureRect
	location_art_missing_label = get_node_or_null("Content/LocationArtMissingLabel") as Label
