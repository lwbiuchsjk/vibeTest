extends RefCounted

# 功能：冒烟测试共享配置入口。
# 说明：从 test_config.json 读取 csv_dir 等路径配置，读取失败时 fallback 到默认路径。
#       所有冒烟测试脚本通过此类获取配置路径，避免各处硬编码。
#
# 例外：以下 5 个测试因断言中硬编码了旧配置的事件/任务 ID（如 evt_market_001、task_exam），
#       不走 SmokeConfig，而是直接使用 DEFAULT_CSV_DIR（world_event_mvp）：
#       - milestone_c_smoke_test（任务偏置验证，引用 evt_study_001 等）
#       - milestone_3_smoke_test（任务终态评价，引用 task_exam / task_smuggle 等）
#       - xinxing_phase2_smoke_test（心性风险结构，引用 evt_market_001）
#       - relationship_phase3_smoke_test（关系骰池，引用 evt_market_001）
#       - mvp_world_event_smoke_test（完整回合循环，断言基于旧事件集）
#       这些测试验证的是引擎通用能力，与阶段内容配置无关。
#       若后续旧配置淘汰，需同步更新这些测试的断言。

const TEST_CONFIG_PATH := "res://test/config/intro_flow_test/test_config.json"
const DEFAULT_CSV_DIR := "res://scripts/config/world_event_mvp"
const DEFAULT_CREATION_CSV := "res://scripts/config/creation_questions.csv"


# 功能：获取冒烟测试使用的 csv_dir 路径。
# 说明：优先读取 test_config.json 中的 world_event_csv_dir，读取失败则返回默认路径。
static func get_csv_dir() -> String:
	var config := _load_test_config()
	var dir := str(config.get("world_event_csv_dir", "")).strip_edges()
	if dir.is_empty():
		return DEFAULT_CSV_DIR
	return dir


# 功能：获取冒烟测试使用的 creation_questions.csv 路径。
# 说明：基于 csv_dir 拼接，若 csv_dir 下存在 creation_questions.csv 则使用，否则返回默认路径。
static func get_creation_csv() -> String:
	var dir := get_csv_dir()
	var candidate := dir.path_join("creation_questions.csv")
	if FileAccess.file_exists(candidate):
		return candidate
	return DEFAULT_CREATION_CSV


# 功能：读取 test_config.json 文件。
# 说明：返回解析后的 Dictionary，文件不存在或解析失败时返回空 Dictionary。
static func _load_test_config() -> Dictionary:
	if not FileAccess.file_exists(TEST_CONFIG_PATH):
		return {}
	var file := FileAccess.open(TEST_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if data is Dictionary:
		return data
	return {}
