extends Control

const NetClientScript := preload("res://scripts/net_client.gd")
const USE_MOCK_BACKEND := true
const BASE_URL := "http://127.0.0.1:8000"

@onready var login_panel: VBoxContainer = $LoginPanel
@onready var account_input: LineEdit = $LoginPanel/AccountInput
@onready var login_button: Button = $LoginPanel/ButtonRow/LoginButton
@onready var create_button: Button = $LoginPanel/ButtonRow/CreateButton
@onready var status_label: Label = $LoginPanel/StatusLabel
@onready var game_panel: VBoxContainer = $GamePanel
@onready var account_label: Label = $GamePanel/AccountLabel
@onready var clear_count_label: Label = $GamePanel/ClearCountLabel
@onready var logout_button: Button = $GamePanel/LogoutButton
@onready var http_request: HTTPRequest = $HTTPRequest

var _net_client: RefCounted
var _is_submitting := false

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
	var clear_count := int(result.get("clear_count", 0))
	_show_game(account_text, clear_count)

func _show_login(message: String) -> void:
	login_panel.visible = true
	game_panel.visible = false
	_set_status(message)

func _show_game(account: String, clear_count: int) -> void:
	login_panel.visible = false
	game_panel.visible = true
	account_label.text = "Account: %s" % account
	clear_count_label.text = "Clear Count: %d" % clear_count

func _set_inputs_enabled(enabled: bool) -> void:
	login_button.disabled = not enabled
	create_button.disabled = not enabled
	account_input.editable = enabled

func _set_status(message: String) -> void:
	status_label.text = message
