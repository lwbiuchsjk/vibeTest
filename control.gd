extends Control

const NetClientScript := preload("res://scripts/net_client.gd")
const USE_MOCK_BACKEND := true
const BASE_URL := "http://127.0.0.1:8000"

# 游戏主场景路径。替换此常量即可切换正式功能场景。
# 正式入口走 scenes/main_game.tscn(玩家面向,剥离了测试调试面板);
# test/event_logic_test.tscn 仍可 F6 直接跑做后续功能/文本验证。
const GAME_SCENE_PATH := "res://scenes/main_game.tscn"

@onready var login_panel: VBoxContainer = $LoginPanel
@onready var account_input: LineEdit = $LoginPanel/AccountInput
@onready var login_button: Button = $LoginPanel/ButtonRow/LoginButton
@onready var create_button: Button = $LoginPanel/ButtonRow/CreateButton
@onready var status_label: Label = $LoginPanel/StatusLabel
@onready var game_wrapper: VBoxContainer = $GameWrapper
@onready var account_bar_label: Label = $GameWrapper/TopBar/AccountBarLabel
@onready var logout_button: Button = $GameWrapper/TopBar/LogoutButton
@onready var game_container: Control = $GameWrapper/GameContainer
@onready var http_request: HTTPRequest = $HTTPRequest

var _net_client: RefCounted
var _is_submitting := false
# 当前加载的游戏场景实例，登出时销毁。
var _game_scene_instance: Control = null

func _ready() -> void:
	_net_client = NetClientScript.new()
	login_button.pressed.connect(_on_login_pressed)
	create_button.pressed.connect(_on_create_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	_show_login("Ready.")

func _on_login_pressed() -> void:
	var account := account_input.text.strip_edges()
	if account.is_empty():
		_set_status("Please enter an account, or use Create Account.")
		return
	await _submit_login(account)

func _on_create_pressed() -> void:
	await _submit_login("")

func _on_logout_pressed() -> void:
	_unload_game_scene()
	account_input.text = ""
	_show_login("Logged out.")

func _submit_login(account: String) -> void:
	if _is_submitting:
		return

	_is_submitting = true
	_set_inputs_enabled(false)
	_set_status("Logging in...")

	var result: Dictionary = await _net_client.login_or_create(
		http_request,
		BASE_URL,
		account,
		USE_MOCK_BACKEND
	)

	_is_submitting = false
	_set_inputs_enabled(true)

	if not result.get("ok", false):
		_set_status("Login failed: %s" % result.get("error", "Unknown error"))
		return

	var account_text := str(result.get("account", ""))
	_show_game(account_text)

# 功能：切换到游戏界面，动态加载 GAME_SCENE_PATH 指定的场景。
func _show_game(account: String) -> void:
	login_panel.visible = false
	game_wrapper.visible = true
	account_bar_label.text = account

	_load_game_scene()

# 功能：切换到登录界面。
func _show_login(message: String) -> void:
	login_panel.visible = true
	game_wrapper.visible = false
	_set_status(message)

# 功能：加载并实例化游戏场景到 GameContainer。
func _load_game_scene() -> void:
	_unload_game_scene()
	var scene_resource: PackedScene = load(GAME_SCENE_PATH)
	if scene_resource == null:
		push_error("无法加载游戏场景: %s" % GAME_SCENE_PATH)
		return
	_game_scene_instance = scene_resource.instantiate() as Control
	if _game_scene_instance == null:
		push_error("游戏场景实例化失败: %s" % GAME_SCENE_PATH)
		return
	# 让游戏场景填满容器。
	_game_scene_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_container.add_child(_game_scene_instance)

# 功能：卸载当前游戏场景实例，释放资源。
func _unload_game_scene() -> void:
	if _game_scene_instance != null:
		_game_scene_instance.queue_free()
		_game_scene_instance = null

func _set_inputs_enabled(enabled: bool) -> void:
	login_button.disabled = not enabled
	create_button.disabled = not enabled
	account_input.editable = enabled

func _set_status(message: String) -> void:
	status_label.text = message
