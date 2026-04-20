extends RefCounted

# 功能：冒烟测试共享配置入口。
# 说明：冒烟测试默认使用全局 world_event_mvp 作为 csv_dir；
#       各 smoke 若需自定义数据集，自行向 ConfigRuntime / WorldEventEngine 传入 csv_dir。
#       本模块不再读取任何量产期测试数据（如 intro_flow_test）——
#       量产数据集由 event_logic_test.gd 独立消费，与冒烟测试互不影响。
#
# 例外：以下 5 个测试因断言中硬编码了旧配置的事件/任务 ID（如 evt_market_001、task_exam），
#       不走 SmokeConfig，而是直接使用 DEFAULT_CSV_DIR（world_event_mvp）：
#       - milestone_c_smoke_test（任务偏置验证，引用 evt_study_001 等）
#       - milestone_3_smoke_test（任务终态评价，引用 task_exam / task_smuggle 等）
#       - xinxing_phase2_smoke_test（心性风险结构，引用 evt_market_001）
#       - relationship_phase3_smoke_test（关系骰池，引用 evt_market_001）
#       - mvp_world_event_smoke_test（完整回合循环，断言基于旧事件集）
#       这些测试验证的是引擎通用能力，与阶段内容配置无关。

const DEFAULT_CSV_DIR := "res://scripts/config/world_event_mvp"
const DEFAULT_CREATION_CSV := "res://scripts/config/creation_questions.csv"


# 功能：获取冒烟测试使用的 csv_dir 路径。
# 说明：直接返回全局默认路径，各 smoke 需要覆盖时自行传入。
static func get_csv_dir() -> String:
	return DEFAULT_CSV_DIR


# 功能：获取冒烟测试使用的 creation_questions.csv 路径。
# 说明：直接返回全局默认路径，不再从数据集目录探测。
static func get_creation_csv() -> String:
	return DEFAULT_CREATION_CSV
