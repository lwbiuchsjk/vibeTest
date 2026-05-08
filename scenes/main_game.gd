extends Control

const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const TaskSummaryCard := preload("res://scripts/ui/task_summary_card.gd")
const WorldEventEngine := preload("res://scripts/systems/world_event_engine.gd")
const WorldEndScreen := preload("res://scripts/ui/world_end_screen.gd")
const ResponsiveLayout := preload("res://scripts/ui/responsive_layout.gd")
const ButtonTheme := preload("res://scripts/ui/button_theme.gd")
const SealPanel := preload("res://scripts/ui/seal_panel.gd")
const OptionCard := preload("res://scripts/ui/option_card.gd")

# UI 字体分工(参见 Design/进度/UI风格快速翻调_demo期进度.md):
# - 默认全局字体走 default_theme.tres 设的霞鹜文楷 Light(楷体,与 mosaic 素描笔触同源)
# - 印章字 / 叙事标题用思源宋体(方头宋体作"骨",与楷体"血肉"形成宋楷搭配)
const FONT_SERIF_BOLD: Font = preload("res://font/SourceHanSerifCN-Bold.otf")
const FONT_SERIF_MEDIUM: Font = preload("res://font/SourceHanSerifCN-Medium.otf")
# 青鸟华光简美黑:笔画粗壮、毛笔/书法感强,印章主字与装饰位用
const FONT_QINGNIAO_MEIHEI: Font = preload("res://font/QingNiaoHuaGuangJianMeiHei-2.ttf")
const TextMosaicBackground := preload("res://scripts/ui/text_mosaic_background.gd")
const TextMosaicParticles := preload("res://scripts/ui/text_mosaic_particles.gd")
const TextMosaicAccentMarked := preload("res://scripts/ui/text_mosaic_accent_marked.gd")

const TEST_CONFIG_PATH := "res://test/event_logic_test_config.json"

# UI 同源色板(参见 Design/进度/UI风格快速翻调_demo期进度.md § 颜色 Token 表)。
# 哲学锚点:碑刻+札记杂交风格,UI 复用底层 mosaic 的"字、墨、纸、朱"四原色,不引入异质材质。
# panel_paper 与 BackgroundColor #F4ECD8 完全同色 + 半透,叠加视觉是"局部纸面更干净"而非"灰布"。
# accent_zhu 仅用于"玩家伸手"位(选项 / 继续 / 朱批),其余位置克制使用,避免稀释"伸手"语义。
# 注:button_theme.gd PRESET_DEFAULT 字段含同色字面量,改这里也要同步那边;Phase 3 提取 ui_palette.gd 后消除重复。
const UI_PANEL_PAPER := Color(0.957, 0.925, 0.847, 0.75)
const UI_TEXT_PRIMARY := Color(0.180, 0.161, 0.141, 1.0)
const UI_TEXT_SECONDARY := Color(0.353, 0.310, 0.271, 1.0)
const UI_ACCENT_ZHU := Color(0.698, 0.180, 0.149, 1.0)

# 地点 → 文字马赛克 token 数组(v1 固定映射,详见 Design/文字马赛克美术背景_MVP设计.md §7.1)。
# **占位:以下词组为代码默认值以避免空运行,等用户从游戏内容(event_presentations / 角色状态等)
#   提供正式 token 池后替换。文字内容是用户领域,不应当作为引擎方设计方案的一部分。**
# v2 演进路径(剧情上下文驱动)留待 PoC 通过后实现;接口 set_text_tokens() 不变。
# 覆盖范围:scripts/config/location_graph.csv(town_square/market/harbor)
#       + test/config/intro_flow_test/location_graph.csv(loc_pharmacy/loc_market/loc_training_ground/loc_outskirts)。
# 注:GDScript const 仅允许字面量,故此处用 Array,使用处再转 PackedStringArray。
const LOCATION_TEXT_TOKENS: Dictionary = {
	"town_square": ["广场", "人来", "人往", "石板", "钟声", "市井"],
	"market": ["市集", "讨价", "喧闹", "货郎", "果蔬", "铜钱"],
	"harbor": ["港口", "潮汐", "船帆", "鸥鸣", "盐风", "渔获"],
	"loc_pharmacy": ["药铺", "苦汤", "草药", "杵臼", "症候", "良方"],
	"loc_market": ["市集", "讨价", "喧闹", "货郎", "果蔬", "铜钱"],
	"loc_training_ground": ["练场", "拳脚", "汗水", "号令", "招式", "刀光"],
	"loc_outskirts": ["镇外", "野径", "风沙", "歧路", "斥候", "尘烟"],
	# 周既明角色特化练武场——词由用户从《周既明角色内核》抽取（M1' 真实美术验证临时池）。
	# 物象层：木桩 / 刀架 / 暮色 / 练场 / 刀光；动作层：招式 / 切磋 / 独练；
	# 内核层：心气（周线主战场）/ 家书（缺席家庭）/ 习惯（"我习惯了"语气常态）/ 力气（"用过力气"情感色彩）。
	"loc_zhou_training_ground": ["木桩", "刀架", "暮色", "练场", "刀光", "招式", "切磋", "独练", "心气", "家书", "习惯", "力气"],
}

# 未匹配 location_id 时的 fallback token,避免文字层完全无渲染。
const DEFAULT_TEXT_TOKENS: Array = ["风", "云", "山", "水", "城", "镇", "人", "事"]

# 通用 mosaic 词库:供"装饰性 mosaic"层(选项卡阴影 / 印章斑驳层 等)复用,
# 与地点专属 LOCATION_TEXT_TOKENS 解耦。文字内容是用户领域,工程方仅提供数据结构与默认占位。
# 选词原则:泛用诗意双字词,不偏向任何具体地点 / 角色 / 事件;与背景层 mosaic 文风同源。
# 用户后续可从《标签体系》或核心设计文档抽取正式词库后替换此占位。
const COMMON_MOSAIC_TOKENS: Array = [
	"春秋", "寒暑", "风霜", "晨昏",
	"山水", "云月", "烟波", "草木",
	"光阴", "岁月", "朝夕", "枯荣",
]

# F8 调试键专用：周既明练武场背景图与对应 location_id。
# 用途：在不改 CSV 事件配置的前提下，验证 M1' 色相敏感算法在真实暖色调美术资源上的视觉效果。
const ZHOU_TRAINING_GROUND_PATH: String = "res://assets/art/environments/backgrounds/training_ground.png"
const ZHOU_TRAINING_GROUND_LOCATION: String = "loc_zhou_training_ground"

var _engine: WorldEventEngine
var _event_logs: Array[String] = []
var _current_turn_result: Dictionary = {}
var _resizing := false              # 防止窗口尺寸调整时递归触发
# 主动押注切换状态：按选项 ID 记录各选项的押注模式（true=押注，false=默认）。
var _bet_mode_options: Dictionary = {}
# 议题 B 聚合面板的"继续"页脚回调路由：不同 phase（普通事件 / 开局选择 narrating / 开局选择 outcome）
# 共享同一个 ContinueButton 节点,通过 _show_continue_footer 切换 _continue_handler 实现行为分流。
# 默认指向普通事件的 _on_continue_button_pressed,phase 切换时由 _show_continue_footer 重设。
var _continue_handler: Callable = Callable()

@onready var screen_background: TextureRect = $ScreenBackground
# 屏幕级文字马赛克衬底(油画式 3 层):粗(36px α 0.5)→ 中(18px α 0.45)→ 细(8px α 0.4),
# 全屏覆盖+四边 offset ±200 让节点 size 溢出屏幕(源图视觉放大但单字字号不变)。
# 三层与核心 LeftStack 共享源图+tokens,但因字号梯度产生不同 cell 网格的错位采样,
# 形成"层层叠叠"油画感。test 场景无这些节点,get_node_or_null → null。
@onready var screen_mosaic_coarse: TextMosaicBackground = get_node_or_null("ScreenMosaicCoarse") as TextMosaicBackground
@onready var screen_mosaic_medium: TextMosaicBackground = get_node_or_null("ScreenMosaicMedium") as TextMosaicBackground
@onready var screen_mosaic_bg: TextMosaicBackground = get_node_or_null("ScreenMosaicBackground") as TextMosaicBackground
@onready var root_margin: MarginContainer = $Root
# 测试场景特有的右侧调试面板。正式 main_game 场景已剥离,此处取值为 null,
# 所有访问点必须 null check。保留路径变量是为了让正式 / 测试场景共用同一份脚本。
@onready var right_column: VSplitContainer = get_node_or_null("Root/RootContent/MainSplit/RightColumn") as VSplitContainer
@onready var status_label: Label = $Root/RootContent/Header/StatusLabel
@onready var event_background_rect: TextureRect = $Root/RootContent/MainSplit/LeftPanel/LeftStack/EventBackground
# 油画式多层叠加:核心区 LeftStack 内 mosaic 由 3 层叠成,字号梯度做层次。
# coarse(24px α 0.25)粗笔触底色 → medium(14px α 0.45)中纹 → bg(8px α 1.0)精纹主层。
# 仅 main_game 场景有 coarse/medium,test 场景路径不存在 → null check。
@onready var text_mosaic_coarse: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicCoarse") as TextMosaicBackground
@onready var text_mosaic_medium: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicMedium") as TextMosaicBackground
@onready var text_mosaic_bg: TextMosaicBackground = $Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicBackground
# 素描式 V 切片多层(决策点 6 激进版):暗部 5 档 + 高光 1 档,与主层叠加形成
# 1~6 层密度梯度。各层 v_max/v_min 阈值不均匀步长——越暗切片越细,呼应人眼对
# 暗部分辨力强;α 阶梯 0.3 → 0.65 越深的层视觉权重越大(类比素描"反复涂死");
# grid_phase 全错开避免 cell 重叠在同位置 → 真.密度翻倍。
# 命中规则(自上而下递进):
#   主层  v∈[0,1.0]  α=1.0  → 全画
#   DarkLight  v≤0.7  α=0.3  → 中亮以下 +1 层
#   DarkAccent v≤0.5  α=0.35 → 中暗以下 +2 层
#   DarkDeep   v≤0.32 α=0.45 → 暗部     +3 层
#   DarkInk    v≤0.18 α=0.55 → 深暗     +4 层
#   DarkAbyss  v≤0.08 α=0.65 → 极暗     +5 层
#   Highlight  v≥0.75 α=0.4  → 亮区高光斑驳(独立维度,与暗部档位互斥)
# 仅 main_game 场景有这些节点,test 场景跳过(get_node_or_null → null)。
@onready var text_mosaic_dark_light: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicDarkLight") as TextMosaicBackground
@onready var text_mosaic_dark_accent: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicDarkAccent") as TextMosaicBackground
@onready var text_mosaic_dark_deep: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicDarkDeep") as TextMosaicBackground
@onready var text_mosaic_dark_ink: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicDarkInk") as TextMosaicBackground
# DarkBetween 在 DarkInk(0.18) 和 DarkAbyss(0.08) 之间补一档(v_max=0.13),让深暗段过渡更细
@onready var text_mosaic_dark_between: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicDarkBetween") as TextMosaicBackground
@onready var text_mosaic_dark_abyss: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicDarkAbyss") as TextMosaicBackground
# MidDark/MidLight 是中调"窗口层"(双边 v_min/v_max),用 6px 小字号在中调区
# 增加颗粒度,与 DarkLight/DarkAccent 等单边阈值层不同——这两层只贡献自己的 V 段。
# 配合 Coarse/Medium 加 v_max 退出亮区,中间灰阶在视觉上拉开区分度。
@onready var text_mosaic_mid_dark: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicMidDark") as TextMosaicBackground
@onready var text_mosaic_mid_light: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicMidLight") as TextMosaicBackground
@onready var text_mosaic_highlight: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicHighlight") as TextMosaicBackground
# 点缀色层:saturation_threshold + use_source_color + breathe 三件套,在源图高饱和度区域
# (配饰/眼神/灯笼等"焦点色")保留原色字符,整层 modulate.a 正弦呼吸让画面活起来。
# 与暗部档位/中调切片/高光层是不同语义维度——它在"S 维度"上挑出点睛位置,不参与素描灰阶。
@onready var text_mosaic_accent: TextMosaicBackground = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicAccent") as TextMosaicBackground
# 标注式点睛色层:读 flow_regions.json 中 accent_areas 字段(polygon + color + breathe 三件套),
# 在显式标注的多边形区域内画"点睛色"字符。每个 area 独立呼吸节奏(基于全局时间+各自 period)。
# 与 TextMosaicAccent 互补:Accent 是基于源图饱和度的"自动温和染色"(脸/手肤色),
# 此层是"显式标注的尖锐点睛"(腰带/刀光等设计语义位置)。
@onready var text_mosaic_accent_marked: TextMosaicAccentMarked = get_node_or_null("Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicAccentMarked") as TextMosaicAccentMarked
@onready var text_mosaic_particles: TextMosaicParticles = $Root/RootContent/MainSplit/LeftPanel/LeftStack/TextMosaicParticles
@onready var character_panel: PanelContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/CharacterPanel
@onready var character_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/CharacterPanel/CharacterLabel
@onready var world_panel: PanelContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/WorldPanel
@onready var world_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/WorldPanel/WorldLabel
@onready var narrative_panel: PanelContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel
@onready var event_title_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel/NarrativeContent/EventTitle
@onready var event_detail_label: Label = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel/NarrativeContent/EventDetail
@onready var task_summary_card: TaskSummaryCard = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/TaskSummaryCard
@onready var main_split: HSplitContainer = $Root/RootContent/MainSplit
@onready var end_root: WorldEndScreen = $Root/RootContent/EndRoot
# 议题 B:聚合面板结构 —— 继续按钮退化为叙事面板底部页脚朱字(SHRINK_END 右对齐 + flat=true 无 stylebox);
# OptionList 移入 NarrativeContent 内,选项 + 继续都属于"叙事面板下半部"的"伸手位"。
@onready var continue_button: Button = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel/NarrativeContent/ContinueButton
@onready var option_list: VBoxContainer = $Root/RootContent/MainSplit/LeftPanel/LeftStack/LeftOverlay/LeftContent/NarrativePanel/NarrativeContent/OptionList
# 测试场景特有的调试输出节点（同上 right_column 说明）。正式场景为 null,访问点 null check。
@onready var world_state_label: RichTextLabel = get_node_or_null("Root/RootContent/MainSplit/RightColumn/RightPanel/RightMargin/RightContent/WorldStateValue") as RichTextLabel
@onready var log_label: RichTextLabel = get_node_or_null("Root/RootContent/MainSplit/RightColumn/BottomPanel/BottomMargin/BottomContent/LogValue") as RichTextLabel
# intro 序列节点：main_game 场景有此节点，test 场景无此节点（get_node_or_null → null）。
# 存在时触发 intro 动画流程；否则直接调用 _start_game_after_intro() 跳过 intro。
@onready var intro_sequence: IntroSequence = get_node_or_null("IntroSequence") as IntroSequence
# intro 方案 B：核心区与顶部栏需独立透明度控制（不能用 root_margin 整体隐藏，否则少女层无法独立浮现）。
@onready var left_stack: Control = $Root/RootContent/MainSplit/LeftPanel/LeftStack
@onready var header: VBoxContainer = $Root/RootContent/Header


# 功能：初始化场景。
# 说明：若存在 IntroSequence 节点（main_game 场景）则先播放 intro 动画，
#       结束后通过信号回调进入正式游戏逻辑。
#       无 IntroSequence 时（test 场景）直接调用 _start_game_after_intro() 跳过 intro。
func _ready() -> void:
	# 议题 B:ContinueButton pressed 经由路由 handler 分发,通过 _continue_handler 切换不同 phase 的回调
	continue_button.pressed.connect(_on_continue_footer_pressed_router)
	# 议题 B 调整 4:整张叙事面板作为"继续"扩展点击区域,仅 ContinueButton 可见时启用
	# (handler 内部检查 continue_button.visible 决定是否转发)
	narrative_panel.gui_input.connect(_on_narrative_panel_gui_input)
	end_root.action_requested.connect(_on_end_action_requested)
	_setup_overlay_styles()
	_setup_seal_row_mock()  # Phase 1.5 mock:验证印章式状态条形态后整体重构
	_setup_screen_background()
	_setup_platform_default_layers()
	# 响应式布局初始化：注册 viewport 监听并触发首次布局。
	ResponsiveLayout.setup(get_viewport(), _on_viewport_resized)
	var test_config := _load_test_config()
	_engine = WorldEventEngine.new(_get_test_random_seed(test_config))

	var load_result := _load_world_event_test_config(test_config)
	if not load_result.get("ok", false):
		status_label.text = "加载失败: %s" % str(load_result.get("error", "unknown"))
		return

	# intro 分支：main_game 场景存在 IntroSequence 节点时进入 intro 流程
	if intro_sequence != null:
		# 隐藏屏幕级大字层（intro 期间用 IntroSequence 自己的文字马赛克层）
		if screen_mosaic_coarse != null:
			screen_mosaic_coarse.visible = false
		if screen_mosaic_medium != null:
			screen_mosaic_medium.visible = false
		if screen_mosaic_bg != null:
			screen_mosaic_bg.visible = false
		# 隐藏核心区（LeftStack 整体透明：含 EventBackground 少女图 + BackgroundColor 米色底 + 各 mosaic 层）。
		# reveal_core_girl 阶段整体淡入实现少女独立浮现；LeftOverlay (UI 容器) tscn 默认 visible=false，
		# 由游戏后续逻辑（事件预览 / 创建阶段）显示，与 intro 时序解耦。
		left_stack.modulate.a = 0.0
		# === 用户尝试方案：隐藏 LeftStack 所有背景渲染节点，让核心区透出底层 ScreenMosaic 屏幕级渲染 ===
		# 目的：让 LeftStack 区域 = LeftStack 外区域 = 整屏统一的 ScreenMosaic 视觉（同字号、同深浅、同图片尺寸）
		# LeftOverlay (UI 容器) 默认 visible=false 由游戏后续逻辑控制，此处保留不动。
		# 副作用：reveal_core_girl 的 LeftStack Tween 不再有视觉效果（容器内无可见节点），但 Tween 保留以备未来扩展。
		# 恢复 LeftStack 自有渲染：删除以下 for 循环。
		for child: Node in left_stack.get_children():
			if child.name != "LeftOverlay":
				child.visible = false
		# 注：Header (TitleLabel/StatusLabel) 是 demo 期占位，tscn 默认 visible=false 不显示，无需在此控制 modulate。
		# root_margin 整体保持 modulate.a=1（不能整体隐藏，否则 LeftStack 也跟着不可见，少女无法独立显现）。
		# 连接 intro 信号到对应 handler
		intro_sequence.intro_click_received.connect(_on_intro_click_received)
		intro_sequence.intro_reveal_screen_mosaic.connect(_on_intro_reveal_screen_mosaic)
		intro_sequence.intro_reveal_core_girl.connect(_on_intro_reveal_core_girl)
		intro_sequence.intro_reveal_ui.connect(_on_intro_reveal_ui)
		intro_sequence.intro_completed.connect(_on_intro_completed)
		# 启动池塘涟漪动画（信号已连接完毕后调用）
		intro_sequence.start_pond_animation()
		return  # 跳过正式游戏启动逻辑，等待 intro_completed 信号

	# test 场景（无 IntroSequence 节点）：直接进入正式游戏逻辑
	_start_game_after_intro()


# 功能：intro 完成后（或 test 场景）进入正式游戏逻辑。
# 说明：原 _ready() 末尾的开局选择阶段判断 + 首个事件预览逻辑提取至此。
#       由 _on_intro_completed 信号回调触发（main_game 场景），或 _ready() 直接调用（test 场景）。
func _start_game_after_intro() -> void:
	# 开局选择阶段：如果有创建配置，先进入角色创建流程。
	if _engine.has_creation_config():
		var creation_result: Dictionary = _engine.start_creation()
		if creation_result.get("state", "") == "PRESENTING":
			_append_log("进入开局选择阶段。")
			_render_creation_phase(creation_result)
			return
	_append_log("测试环境启动，开始预览第一个事件。")
	_preview_next_event()


# ============================================================
# intro 信号 handler（仅 main_game 场景有 IntroSequence 时触发）
# ============================================================

# 功能：intro_click_received 回调（t=0.0s）。
# 说明：玩家点击瞬间，立即将核心区源图切换到少女图，利用 0.4s 缓冲期完成 GPU 上传。
#       此时 left_stack.modulate.a=0，核心区不可见，切图操作对玩家无感知。
func _on_intro_click_received() -> void:
	_render_event_background("res://assets/art/environments/backgrounds/pond_girl_enter.png")


# 功能：intro_reveal_screen_mosaic 回调（t=0.4s）。
# 说明：当前为空 handler。原设计是 ScreenMosaic 屏幕级大字层浮现接管屏幕渲染；
#       现改为 IntroSequence 13 层 mosaic 永久承担屏幕渲染（cross-fade 涟漪→girl_enter 不淡出），
#       ScreenMosaic 不再参与（在 _ready 已 visible=false 持续保持）。
#       本 handler 保留作为未来扩展点（信号契约不变）。
func _on_intro_reveal_screen_mosaic() -> void:
	pass


# 功能：intro_reveal_core_girl 回调（t=0.8s）。
# 说明：当前无视觉效果——LeftStack 内背景节点已在 _ready 全部 visible=false 隐藏，
#       核心区透出 IntroSequence 屏幕级渲染。Tween LeftStack.modulate.a 0→1 仍执行，
#       让 LeftOverlay (UI 容器) 未来由游戏后续逻辑显示时 alpha 已就绪（=1），
#       不需要后续代码额外管理 LeftStack 整体 alpha。保留作未来扩展点。
func _on_intro_reveal_core_girl() -> void:
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(left_stack, "modulate:a", 1.0, 0.4)


# 功能：intro_reveal_ui 回调（t=1.2s）。
# 说明：当前为空 handler（不浮现任何 UI 元素）。
#       Header (TitleLabel="Main Game" + StatusLabel 动态状态) 是 demo 期占位，
#       tscn 默认 visible=false，本阶段保持不显示。
#       LeftOverlay (UI 容器) tscn 默认 visible=false，由游戏后续逻辑
#       (_start_game_after_intro → _preview_next_event) 显示。
#       root_margin 在 intro 期间始终保持完全可见 (modulate.a=1)，不参与本阶段 Tween。
#       本 handler 保留作为未来正式 UI 浮现的扩展点 (例如新增正式 HUD 时在此 Tween 浮现)。
func _on_intro_reveal_ui() -> void:
	pass


# 功能：intro_completed 回调（t=2.0s）。
# 说明：IntroSequence 已隐藏，进入正式游戏逻辑。
#       Step 2：注入 sys_opening_reflection 作为开场首个事件（首个自省，含池塘开场叙事 +
#       4 地点选择末屏）。事件不存在时引擎在 _select_next_event 报 missing_event_def fatal，
#       配置者应确保 CSV 中存在该 event_id；老 demo 配置无此事件时直接跳过 forced 注入。
func _on_intro_completed() -> void:
	const OPENING_REFLECTION_EVENT_ID := "sys_opening_reflection"
	# 注入前先用 has_event 校验存在性，避免老 demo 配置（无 sys_opening_reflection）触发
	# _select_next_event 的 missing_event_def fatal。仅在外部 forced 字段未占用时注入，
	# 避免覆盖既有 forced 安排。
	if _engine.has_event(OPENING_REFLECTION_EVENT_ID) and _engine.world_state.get("forcedNextEventId", "") == "":
		_engine.world_state["forcedNextEventId"] = OPENING_REFLECTION_EVENT_ID
	_start_game_after_intro()


# 功能：预览下一个事件并停留在当前界面。
# 说明：预览阶段只展示事件内容，不执行结算，也不增加 world turn。
func _preview_next_event() -> void:
	_current_turn_result.clear()

	var turn_result := _engine.preview_next_turn()
	if not turn_result.get("ok", false):
		status_label.text = "事件预览失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	_handle_preview_turn_result(turn_result)


# 功能：统一处理预览结果。
# 说明：预览结果只负责记录日志、刷新当前缓存并渲染界面，不参与结算后的分流逻辑。
func _handle_preview_turn_result(turn_result: Dictionary) -> void:
	_current_turn_result = (turn_result as Dictionary).duplicate(true)
	_append_turn_log(turn_result)
	_render_current_event(turn_result)
	_update_side_panels()


# 功能：渲染当前事件。
# 说明：根据 phase 分别处理展示、选择、确认、心性风险入口等界面状态。
func _render_current_event(turn_result: Dictionary) -> void:
	if _is_world_ended_result(turn_result):
		_render_end_screen(turn_result)
		return

	var choice: Dictionary = turn_result.get("choice", {})
	var options: Array = choice.get("options", [])
	var phase := str(turn_result.get("phase", "confirm"))
	var presentation: Dictionary = turn_result.get("presentation", {})
	var presentation_item: Dictionary = presentation.get("current_item", {})
	var awaiting_choice := phase == "choice"
	# 进入新的选择阶段时重置各选项的押注切换状态
	if phase != "choice":
		_bet_mode_options.clear()

	_render_event_background(str(turn_result.get("resolved_background_art", "")))
	_set_end_screen_visible(false)
	_update_left_task_panel(turn_result)

	# 叙事面板：标题 + 展示文本 + 鉴定结果摘要
	event_title_label.text = str(turn_result.get("title", ""))
	var narrative_parts: Array[String] = []
	if phase == "presentation":
		var speaker := str(presentation_item.get("speaker", "")).strip_edges()
		var body := str(presentation_item.get("text", ""))
		if speaker.is_empty():
			narrative_parts.append(body)
		else:
			narrative_parts.append("%s: %s" % [speaker, body])
	var check_summary := _build_check_result_summary(turn_result)
	if not check_summary.is_empty():
		narrative_parts.append(check_summary)
	event_detail_label.text = "\n\n".join(narrative_parts)
	# 有标题或叙事内容时才显示叙事面板
	var has_narrative := not event_title_label.text.strip_edges().is_empty() or not narrative_parts.is_empty()
	narrative_panel.visible = has_narrative

	_clear_option_list()
	if phase == "presentation":
		# Step 2：检测末屏 presents=location_select → 同屏渲染叙事文本 + 地点按钮组
		# （由 confirm_reflection_location_select API 处理玩家选择并追加过渡叙事）。
		var current_presents: String = str(presentation_item.get("presents", "text"))
		if current_presents == "location_select":
			status_label.text = "选择前往的地点。"
			_render_reflection_location_buttons(turn_result)
			return
		status_label.text = "当前处于展示阶段，点击继续查看下一条文本。"
		_show_continue_footer("继续 ›")
		return

	# 心性风险入口：孤注一掷
	if phase == "desperate_gamble":
		status_label.text = "鉴定失败，可以选择孤注一掷重新检定。"
		_render_risk_entry_buttons("孤注一掷：接受", "孤注一掷：放弃")
		return

	# 安全兜底：若引擎意外返回 preemptive_bet phase（正常流程由链式调用处理，不应到达此处），
	# 自动放弃押注并继续结算，避免 UI 卡死。
	if phase == "preemptive_bet":
		push_warning("preemptive_bet phase 未被链式调用消费，自动放弃押注。")
		var fallback_result := _engine.confirm_pending_turn("reject")
		_handle_resolved_turn_result(fallback_result, "自动放弃押注（兜底）")
		return

	# 自省事件：渲染自省交互界面。
	if phase == "reflection":
		_render_reflection_phase(turn_result)
		return

	# 地点选择：包结束或首次进入时，由引擎返回 phase=location_select，options 在顶层。
	if phase == "location_select":
		_render_location_select(turn_result)
		return

	if awaiting_choice:
		# 获取完整选项定义（含 check/cost/preemptiveBet）和心性风险配置。
		var risk_profile: Dictionary = turn_result.get("xinxing_risk_profile", {})
		var full_options := _get_full_option_defs_for_current_event()
		var any_bet_available := false
		for opt in full_options:
			if _can_option_trigger_bet(opt, risk_profile):
				any_bet_available = true
				break
		if any_bet_available:
			status_label.text = "等待选择：可切换主动押注模式获得额外鉴定骰。"
		else:
			status_label.text = "等待选择：点击下方任一可用选项。"
		_render_choice_options(full_options, risk_profile)
	else:
		status_label.text = "当前事件待确认，点击继续后结算并预览下一个事件。"
		_show_continue_footer("确认结算 ›")


# 功能：渲染心性风险入口的接受/放弃按钮对（孤注一掷专用）。
# 说明：两个按钮分别绑定 "accept" 和 "reject"，走正常的 confirm_pending_turn 分流。
#       孤注一掷入口属于系统级风险交互(独立色彩 PRESET_DESPERATE),不在议题 B"普通选项"
#       范围内,刻意保留 Button 路径,议题 E(选项效果精调)再评估迁移。
func _render_risk_entry_buttons(accept_text: String, reject_text: String) -> void:
	_add_option_section_label("— 心性风险入口 —")

	var accept_button := Button.new()
	accept_button.text = accept_text
	accept_button.pressed.connect(_on_option_pressed.bind("accept"))
	ButtonTheme.apply(accept_button, ButtonTheme.PRESET_DESPERATE)
	option_list.add_child(accept_button)

	var reject_button := Button.new()
	reject_button.text = reject_text
	reject_button.pressed.connect(_on_option_pressed.bind("reject"))
	ButtonTheme.apply(reject_button)
	option_list.add_child(reject_button)


# ── 开局选择 UI ──────────────────────────────────────────────────

# 功能：渲染开局选择阶段界面。
# 说明：根据 phase 字段分支渲染：narrating 展示文字+继续按钮，choosing 展示文字+选项。
func _render_creation_phase(result: Dictionary) -> void:
	var question_index: int = int(result.get("question_index", 0))
	var question_total: int = int(result.get("question_total", 0))
	var phase := str(result.get("phase", "choosing"))
	var narrative_line := str(result.get("narrative_line", result.get("question_text", "")))

	# 渲染背景图。
	_render_event_background(str(result.get("background_art", "")))

	# 更新状态栏进度提示。
	status_label.text = "角色创建 (%d/%d)" % [question_index + 1, question_total]

	# 渲染当前叙事段落到叙事面板。
	event_title_label.text = "开局选择"
	event_detail_label.text = narrative_line

	# 清空选项列表。
	_clear_option_list()

	if phase == "narrating":
		# narrating 阶段：仅展示页脚朱字"继续 ›"（议题 B 状态 A）
		_show_continue_footer("继续 ›", Callable(self, "_on_creation_continue_pressed"))
	else:
		# choosing 阶段：渲染 OptionCard 选项卡片堆（议题 B 状态 B）
		var shadow_tokens: PackedStringArray = PackedStringArray(COMMON_MOSAIC_TOKENS)
		var actions: Array = result.get("available_actions", [])
		var idx: int = 0
		for action_variant in actions:
			var action: Dictionary = action_variant
			var label_text: String = str(action.get("label", ""))
			var option_id: String = str(action.get("action", ""))
			var enabled: bool = bool(action.get("enabled", true))
			var card: OptionCard = OptionCard.new()
			option_list.add_child(card)
			var seed_val: int = (idx + 1) * 137 + abs(hash(option_id)) % 100
			card.set_option(label_text, option_id, null, 17, enabled, seed_val, shadow_tokens)
			card.pressed.connect(_on_creation_option_pressed.bind(option_id))
			idx += 1

	_update_side_panels()


# 功能：处理开局选择叙事阶段的【继续】按钮点击。
# 说明：调用引擎代理推进叙事段落，根据返回的 phase 刷新界面。
func _on_creation_continue_pressed() -> void:
	var result: Dictionary = _engine.creation_advance_narrative()
	if not result.get("ok", false):
		status_label.text = "叙事推进失败: %s" % str(result.get("error", "unknown"))
		return
	_render_creation_phase(result)


# 功能：渲染开局选择的叙事后果展示界面。
# 说明：展示后果文本 + 【继续】按钮，继续后推进到下一题或事件流程。
func _render_creation_outcome(result: Dictionary) -> void:
	var outcome_text := str(result.get("outcome_text", ""))
	event_detail_label.text = outcome_text
	_clear_option_list()
	# 议题 B：开局后果是状态 A（无真选项），用页脚朱字承担"继续"
	_show_continue_footer("继续 ›", Callable(self, "_on_creation_outcome_confirmed"))
	_update_side_panels()


# 功能：处理叙事后果展示的【继续】按钮点击。
# 说明：调用引擎代理确认后果，根据返回状态决定渲染下一题或进入事件流程。
func _on_creation_outcome_confirmed() -> void:
	var result: Dictionary = _engine.creation_confirm_outcome()
	if not result.get("ok", false):
		status_label.text = "后果确认失败: %s" % str(result.get("error", "unknown"))
		return
	var state := str(result.get("state", ""))
	if state == "PRESENTING":
		_render_creation_phase(result)
	else:
		_append_log("开局选择完成，开始预览第一个事件。")
		_preview_next_event()


# 功能：处理开局选择的选项按钮点击。
# 说明：调用引擎代理执行选择，根据返回状态决定渲染下一题或进入事件流程。
func _on_creation_option_pressed(option_id: String) -> void:
	var result := _engine.creation_act(option_id)
	if not result.get("ok", false):
		status_label.text = "开局选择操作失败: %s" % str(result.get("error", "unknown"))
		return

	_append_log("开局选择: %s" % option_id)

	var phase := str(result.get("phase", ""))
	if phase == "outcome":
		# 有叙事后果，展示后果文本 + 继续按钮。
		_render_creation_outcome(result)
		return

	var state := str(result.get("state", ""))
	if state == "PRESENTING":
		# 还有下一题，渲染。
		_render_creation_phase(result)
	else:
		# 全部完成，进入正常事件流程。
		_append_log("开局选择完成，开始预览第一个事件。")
		_preview_next_event()


# ── 自省事件 UI ──────────────────────────────────────────────────

# 功能：渲染自省交互界面。
# 说明：根据 reflection_state 和 reflection_actions 渲染操作按钮列表。
func _render_reflection_phase(turn_result: Dictionary) -> void:
	var ref_state := str(turn_result.get("reflection_state", ""))
	var ref_actions: Array = turn_result.get("reflection_actions", [])
	var ops_remaining := int(turn_result.get("reflection_ops_remaining", 0))
	var ref_extra: Dictionary = turn_result.get("reflection_extra", {})

	# 状态机尚未启动（preview 阶段），显示入口按钮。
	if ref_state.is_empty():
		event_detail_label.text = "闭上眼，回想最近发生的事……"
		narrative_panel.visible = true
		status_label.text = "自省事件，点击开始进入自省。"
		var start_btn := Button.new()
		start_btn.text = "开始自省"
		start_btn.pressed.connect(_on_reflection_action_pressed.bind(""))
		ButtonTheme.apply(start_btn)
		option_list.add_child(start_btn)
		return

	# 叙事区：根据状态显示不同说明文本。
	var narrative_parts: Array[String] = []
	match ref_state:
		"EMPTY_REFLECTION":
			narrative_parts.append(str(ref_extra.get("text", "一切如常，没有特别值得回顾的事。")))
		"MAIN_MENU":
			narrative_parts.append("静下心来回顾最近发生的事情。")
			narrative_parts.append("剩余操作次数: %d" % ops_remaining)
		"ADJUST_RELATION":
			narrative_parts.append("回想与他人的交往，重新审视自己的态度。")
			narrative_parts.append("剩余操作次数: %d" % ops_remaining)
		"FOCUS_SELECT":
			narrative_parts.append("有些人值得更多关注。")
		"FOCUS_REMOVE":
			var pending := str(ref_extra.get("pending_add", ""))
			narrative_parts.append("关注已满，需要先移除一位已关注的人，才能关注 %s。" % pending)
		_:
			narrative_parts.append("自省中...")

	# 查询结果追加到叙事区。
	if ref_extra.has("query_result"):
		var qr: Dictionary = ref_extra["query_result"]
		narrative_parts.append("\n【查询结果】%s: 分值 %d, 档位 %s" % [
			str(qr.get("npc_id", "")),
			int(qr.get("current_score", 0)),
			str(qr.get("current_tier", ""))
		])

	# 操作结果追加到叙事区。
	if ref_extra.has("op_result"):
		var op_r: Dictionary = ref_extra["op_result"]
		narrative_parts.append("\n【操作结果】%s: %d → %s (%s)" % [
			str(op_r.get("npc_id", "")),
			int(op_r.get("new_score", 0)),
			str(op_r.get("new_tier", "")),
			"%+d" % int(op_r.get("delta", 0))
		])

	event_detail_label.text = "\n".join(narrative_parts)
	narrative_panel.visible = true

	# 状态栏。
	match ref_state:
		"EMPTY_REFLECTION":
			status_label.text = "空自省，点击确认继续。"
		"MAIN_MENU":
			status_label.text = "自省主菜单 | 剩余操作: %d" % ops_remaining
		"ADJUST_RELATION":
			status_label.text = "选择要调整关系的对象 | 剩余操作: %d" % ops_remaining
		"FOCUS_SELECT":
			status_label.text = "选择要关注的人"
		"FOCUS_REMOVE":
			status_label.text = "关注已满，选择要移除的人"
		_:
			status_label.text = "自省中"

	# 操作按钮。
	# ADJUST_RELATION 状态下按 group 分组渲染复合按钮行；其他状态逐条渲染。
	if ref_state == "ADJUST_RELATION":
		_render_adjust_relation_actions(ref_actions)
	else:
		for action_variant in ref_actions:
			var action_def: Dictionary = action_variant
			var action_id := str(action_def.get("action", ""))
			var label_text := str(action_def.get("label", action_id))
			var enabled := bool(action_def.get("enabled", true))
			var target := str(action_def.get("target", ""))

			var encoded := "%s:%s" % [action_id, target]
			var btn := Button.new()
			btn.text = label_text
			btn.disabled = not enabled
			btn.pressed.connect(_on_reflection_action_pressed.bind(encoded))
			ButtonTheme.apply(btn)
			option_list.add_child(btn)


# 功能：渲染 ADJUST_RELATION 状态下的复合按钮行。
# 说明：同一 NPC 的 query（查看信息）、trust（+信任）、distrust（+警惕）三个操作
#       合并为一行：查看信息按钮垫底撑满宽度，+信任 / +警惕 两个小按钮竖排叠在右侧。
#       布局参考选项的"主动押注 / 切换默认"按钮组。
func _render_adjust_relation_actions(ref_actions: Array) -> void:
	# 按 group（NPC ID）收集同组操作。
	var groups: Dictionary = {}
	var group_order: Array[String] = []
	for action_variant in ref_actions:
		var action_def: Dictionary = action_variant
		var group_id := str(action_def.get("group", ""))
		if group_id.is_empty():
			group_id = str(action_def.get("target", ""))
		if not groups.has(group_id):
			groups[group_id] = {}
			group_order.append(group_id)
		var role := str(action_def.get("role", ""))
		var action := str(action_def.get("action", ""))
		# 用 action 名做 key（query / trust / distrust）
		groups[group_id][action] = action_def

	for group_id in group_order:
		var defs: Dictionary = groups[group_id]
		var base_def: Dictionary = defs.get("query", {})
		var trust_def: Dictionary = defs.get("trust", {})
		var distrust_def: Dictionary = defs.get("distrust", {})

		# ── 底层：查看信息按钮，撑满宽度 ──
		var base_btn := Button.new()
		base_btn.text = str(base_def.get("label", group_id))
		base_btn.disabled = not bool(base_def.get("enabled", true))
		var base_target := str(base_def.get("target", group_id))
		base_btn.pressed.connect(_on_reflection_action_pressed.bind("query:%s" % base_target))
		ButtonTheme.apply(base_btn)
		# 右侧预留空间给叠加按钮
		ButtonTheme.override_margin_right(base_btn, 136)
		base_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		base_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		base_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		base_btn.custom_minimum_size.y = 0

		# ── 右侧叠加：+信任 / +警惕 横排 ──
		var trust_btn := Button.new()
		trust_btn.text = str(trust_def.get("label", "+信任"))
		trust_btn.disabled = not bool(trust_def.get("enabled", true))
		var trust_target := str(trust_def.get("target", group_id))
		trust_btn.pressed.connect(_on_reflection_action_pressed.bind("trust:%s" % trust_target))
		ButtonTheme.apply(trust_btn, ButtonTheme.PRESET_RELATION_TRUST)
		trust_btn.custom_minimum_size.x = 64
		trust_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var distrust_btn := Button.new()
		distrust_btn.text = str(distrust_def.get("label", "+警惕"))
		distrust_btn.disabled = not bool(distrust_def.get("enabled", true))
		var distrust_target := str(distrust_def.get("target", group_id))
		distrust_btn.pressed.connect(_on_reflection_action_pressed.bind("distrust:%s" % distrust_target))
		ButtonTheme.apply(distrust_btn, ButtonTheme.PRESET_RELATION_DISTRUST)
		distrust_btn.custom_minimum_size.x = 64
		distrust_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# 右侧横排容器
		var right_row := HBoxContainer.new()
		right_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_row.add_theme_constant_override("separation", 2)
		right_row.add_child(trust_btn)
		right_row.add_child(distrust_btn)

		# 外层容器
		var wrapper := HBoxContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.add_theme_constant_override("separation", 0)
		wrapper.add_child(base_btn)
		wrapper.add_child(right_row)
		option_list.add_child(wrapper)


# 功能：处理自省操作按钮点击。
# 说明：将编码后的 "action:target" 传入 confirm_pending_turn，根据返回的 phase 分流。
func _on_reflection_action_pressed(encoded_action: String) -> void:
	var turn_result := _engine.confirm_pending_turn(encoded_action)
	if not turn_result.get("ok", false):
		status_label.text = "自省操作失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	# 解码操作信息用于日志。
	var parts: Array = encoded_action.split(":", true, 1)
	var action_name := str(parts[0]) if parts.size() > 0 else ""
	var action_target := str(parts[1]) if parts.size() > 1 else ""
	var log_text := "自省: %s" % action_name
	if not action_target.is_empty():
		log_text += " -> %s" % action_target
	_append_log(log_text)

	var phase := str(turn_result.get("phase", ""))
	if phase == "reflection":
		# 自省尚未结算，刷新界面继续交互。
		_current_turn_result = (turn_result as Dictionary).duplicate(true)
		_render_current_event(turn_result)
		_update_side_panels()
	else:
		# 自省已结算（phase = resolved），走统一结算后分流。
		_handle_resolved_turn_result(turn_result, "自省结算完成")


# ── 地点选择 UI ──────────────────────────────────────────────────

# 功能：渲染地点选择阶段的按钮列表。
# 说明：引擎返回的 options 在顶层（区别于普通事件 choice.options），每个 option 带
#       location_id / npc_present / has_pending_forced / is_current 等元数据，按地点一行渲染。
func _render_location_select(turn_result: Dictionary) -> void:
	status_label.text = "选择前往的地点（不消耗回合）"
	var options: Array = turn_result.get("options", [])
	if options.is_empty():
		_add_option_hint("无可选地点，请检查 location_graph 与 currentLocationId 配置。")
		return
	for opt_variant in options:
		var opt: Dictionary = opt_variant
		var location_id := str(opt.get("location_id", ""))
		var option_text := str(opt.get("text", location_id))
		# 辅助信息行：NPC 在场列表 + 待触发 forcedNext 标记。
		var hints: Array[String] = []
		var npc_present: Array = opt.get("npc_present", [])
		if not npc_present.is_empty():
			var npc_parts: Array[String] = []
			for n in npc_present:
				npc_parts.append(str(n))
			hints.append("在场: %s" % ", ".join(npc_parts))
		if bool(opt.get("has_pending_forced", false)):
			hints.append("★ 有待触发事件")
		var button_text := option_text
		if not hints.is_empty():
			button_text = "%s\n    %s" % [option_text, "    ".join(hints)]
		var btn := Button.new()
		btn.text = button_text
		btn.pressed.connect(_on_location_select_pressed.bind(location_id))
		ButtonTheme.apply(btn)
		option_list.add_child(btn)


# 功能：处理地点选择按钮点击。
# 说明：调用引擎 confirm_location_select 初始化新包，再预览包内首个事件。
func _on_location_select_pressed(location_id: String) -> void:
	var result := _engine.confirm_location_select(location_id)
	if not result.get("ok", false):
		status_label.text = "地点选择失败: %s" % str(result.get("error", "unknown"))
		_update_side_panels()
		return
	_append_log("前往地点: %s（包容量 %d）" % [location_id, int(result.get("pack_capacity", 0))])
	_preview_next_event()


# 功能：渲染自省末屏地点选择按钮组（Step 2 新增）。
# 说明：与 _render_location_select 的差别：
#       1. 候选地点由 engine.get_reflection_location_options() 提供（已按 reflection_mode +
#          visited_locations 过滤），区别于独立 location_select phase 的全量邻居；
#       2. 按钮 connect 到 _on_reflection_location_select_pressed，调用引擎
#          confirm_reflection_location_select API（写 visited_locations + 切地点 +
#          追加过渡叙事虚拟 presentation 行）；
#       3. 不显示"继续"按钮——末屏的"继续"被地点选择替代。
#       叙事文本仍由上层 _render_current_event 中的 narrative panel 渲染（同屏共存）。
func _render_reflection_location_buttons(_turn_result: Dictionary) -> void:
	var options: Array = _engine.get_reflection_location_options()
	if options.is_empty():
		_add_option_hint("无可选地点（visited_locations 已覆盖全图或邻居为空）。")
		return
	for opt_variant in options:
		var opt: Dictionary = opt_variant
		var location_id := str(opt.get("location_id", ""))
		var option_text := str(opt.get("text", location_id))
		var btn := Button.new()
		btn.text = option_text
		btn.pressed.connect(_on_reflection_location_select_pressed.bind(location_id))
		ButtonTheme.apply(btn)
		option_list.add_child(btn)


# 功能：处理自省末屏地点选择按钮点击（Step 2 新增）。
# 说明：调用引擎 confirm_reflection_location_select，引擎处理：写 visited_locations + 切
#       currentLocationId + 抽 transition_text_pool 追加为虚拟 presentation 行 + 推进 index。
#       返回的 turn_result 即更新后的 pending presentation 状态，按 _handle_preview_turn_result
#       常规渲染（下一屏可能是过渡叙事 text 或 confirm 阶段）。
func _on_reflection_location_select_pressed(location_id: String) -> void:
	var result: Dictionary = _engine.confirm_reflection_location_select(location_id)
	if not result.get("ok", false):
		status_label.text = "自省地点选择失败: %s" % str(result.get("error", "unknown"))
		_update_side_panels()
		return
	_append_log("自省末屏选地点: %s" % location_id)
	_handle_preview_turn_result(result)


# ── 选项与押注 UI ────────────────────────────────────────────────

# 功能：从引擎内部获取当前事件的完整选项定义列表（含 check/cost/preemptiveBet）。
# 说明：UI 展示消耗与押注信息需要这些字段，公开 API 的简版结构不包含。
func _get_full_option_defs_for_current_event() -> Array:
	var event_id := str(_current_turn_result.get("event_id", ""))
	var event_def: Dictionary = _engine._event_map.get(event_id, {})
	var choice_point_id := str(event_def.get("choicePointId", "")).strip_edges()
	if choice_point_id.is_empty():
		return []
	var choice_point_def: Dictionary = _engine._choice_point_map.get(choice_point_id, {})
	if choice_point_def.is_empty():
		return []
	return _engine._build_option_set(choice_point_def)


# 功能：判断某个选项是否满足主动押注触发条件。
# 说明：条件与引擎 _apply_option_resolution 中一致：心性允许、选项含鉴定、未被 disabled。
func _can_option_trigger_bet(option_def: Dictionary, risk_profile: Dictionary) -> bool:
	if not bool(risk_profile.get("allow_preemptive_bet", false)):
		return false
	var check_raw: Variant = option_def.get("check", null)
	if typeof(check_raw) != TYPE_DICTIONARY or (check_raw as Dictionary).is_empty():
		return false
	var bet_cfg: Variant = option_def.get("preemptiveBet", null)
	var bet_disabled: bool = (typeof(bet_cfg) == TYPE_DICTIONARY and bool(bet_cfg.get("disabled", false)))
	if bet_disabled:
		return false
	if str(option_def.get("state", "disabled")) != "selectable":
		return false
	return true


# 功能：为指定选项构建主动押注信息（消耗、调整、是否可负担）。
# 说明：在 choice 阶段调用，读取选项定义和引擎全局默认合并后返回展示数据。
func _build_bet_info_for_option(option_def: Dictionary) -> Dictionary:
	var option_cost_raw: Variant = option_def.get("cost", null)
	var option_cost: Dictionary = option_cost_raw if typeof(option_cost_raw) == TYPE_DICTIONARY else {}
	var option_bet_cfg: Variant = option_def.get("preemptiveBet", null)
	var bet_cfg_dict: Dictionary = {}
	if typeof(option_bet_cfg) == TYPE_DICTIONARY:
		bet_cfg_dict = option_bet_cfg
	var effective_bet: Dictionary = _engine._merge_preemptive_bet_config(bet_cfg_dict)
	var bet_cost: Dictionary = effective_bet.get("cost", {})
	var bet_bias: Dictionary = effective_bet.get("bias", {})

	# 合并总消耗：选项 cost + 押注额外 cost，同名字段累加。
	var total_cost: Dictionary = {}
	for key in option_cost.keys():
		total_cost[str(key)] = int(option_cost[key])
	for key in bet_cost.keys():
		var k := str(key)
		total_cost[k] = int(total_cost.get(k, 0)) + int(bet_cost[key])

	# 构建消耗文本
	var cost_parts: Array[String] = []
	for key in total_cost.keys():
		var total := int(total_cost[key])
		var base := int(option_cost.get(key, 0))
		var extra := int(bet_cost.get(key, 0))
		if base > 0 and extra > 0:
			cost_parts.append("%s %d（基础 %d + 押注 %d）" % [str(key), total, base, extra])
		elif extra > 0:
			cost_parts.append("%s %d（押注消耗）" % [str(key), extra])
		else:
			cost_parts.append("%s %d" % [str(key), total])
	var cost_text := "无" if cost_parts.is_empty() else "、".join(cost_parts)

	# 构建调整文本
	var bias_parts: Array[String] = []
	var success_bias := int(bet_bias.get("successBias", 0))
	if success_bias != 0:
		bias_parts.append("+%d 鉴定骰" % success_bias if success_bias > 0 else "%d 鉴定骰" % success_bias)
	var bias_text := "无" if bias_parts.is_empty() else "、".join(bias_parts)

	var can_afford: bool = _engine._can_pay_bet_cost(bet_cost)

	return {"can_afford": can_afford, "cost_text": cost_text, "bias_text": bias_text}


# 功能：渲染选择阶段的选项列表，含鉴定选项支持默认/押注模式切换。
# 说明：遍历完整选项定义，对满足押注条件的选项渲染切换组件，其余渲染普通按钮。
func _render_choice_options(full_options: Array, risk_profile: Dictionary) -> void:
	var visible_count := 0
	# OptionCard 阴影 mosaic 词库:议题 B 用通用诗意词,与背景 mosaic 同源风格
	var shadow_tokens: PackedStringArray = PackedStringArray(COMMON_MOSAIC_TOKENS)
	for option_variant in full_options:
		var option_def: Dictionary = option_variant
		var state := str(option_def.get("state", "disabled"))
		if state == "invisible":
			continue

		visible_count += 1
		var option_id := str(option_def.get("id", ""))
		var can_bet := _can_option_trigger_bet(option_def, risk_profile)

		if can_bet:
			# 该选项支持主动押注，渲染带切换的选项组(保留旧 Button 路径,带 cost/check 议题再扩展)
			_render_option_with_bet_toggle(option_def, risk_profile)
		else:
			# 议题 B 纯文本选项 → OptionCard(mosaic 阴影 + 米白底 + 朱字)
			# 各卡 noise_seed 用 visible_count + option_id hash,确保各异斑驳模式
			var card: OptionCard = OptionCard.new()
			option_list.add_child(card)
			var seed_val: int = visible_count * 137 + abs(hash(option_id)) % 100
			card.set_option(
				str(option_def.get("text", "")),
				option_id,
				null,  # font=null:OptionCard 内部 fallback 到主题字体(霞鹜文楷)
				17,
				state == "selectable",
				seed_val,
				shadow_tokens
			)
			card.pressed.connect(_on_option_pressed.bind(option_id))

	if visible_count == 0:
		_add_option_hint("当前事件没有可见选项。")


# 功能：渲染单个支持主动押注的选项 — 根据当前切换状态显示默认或押注版本。
# 说明：选项按钮与切换按钮共用一个容器，切换按钮叠在选项按钮右侧上方，不额外占用列表空间。
func _render_option_with_bet_toggle(option_def: Dictionary, _risk_profile: Dictionary) -> void:
	var option_id := str(option_def.get("id", ""))
	var option_text := str(option_def.get("text", ""))
	var cost_raw: Variant = option_def.get("cost", null)
	var option_cost: Dictionary = cost_raw if typeof(cost_raw) == TYPE_DICTIONARY else {}
	var is_bet_mode: bool = bool(_bet_mode_options.get(option_id, false))

	# 构建选项按钮内容
	var confirm_button := Button.new()
	if is_bet_mode:
		# 押注模式：显示合并消耗和调整
		var bet_info := _build_bet_info_for_option(option_def)
		var can_afford := bool(bet_info.get("can_afford", true))
		var cost_text := str(bet_info.get("cost_text", ""))
		var bias_text := str(bet_info.get("bias_text", ""))
		var lines: Array[String] = [option_text]
		lines.append("    消耗: %s" % cost_text)
		lines.append("    调整: %s" % bias_text)
		if not can_afford:
			lines.append("    精力不足，无法发动押注")
		confirm_button.text = "\n".join(lines)
		confirm_button.disabled = not can_afford
		confirm_button.pressed.connect(_on_option_with_bet_pressed.bind(option_id, "accept"))
		ButtonTheme.apply(confirm_button, ButtonTheme.PRESET_BET)
	else:
		# 默认模式：显示原始选项消耗
		var lines: Array[String] = [option_text]
		if not option_cost.is_empty():
			var cost_parts: Array[String] = []
			for key in option_cost.keys():
				cost_parts.append("%s %d" % [str(key), int(option_cost[key])])
			lines.append("    消耗: %s" % "、".join(cost_parts))
		lines.append("    %s" % _build_option_state_text(option_def))
		confirm_button.text = "\n".join(lines)
		confirm_button.pressed.connect(_on_option_with_bet_pressed.bind(option_id, "reject"))
		ButtonTheme.apply(confirm_button)
	# 选项按钮右侧留出空间给切换按钮，避免文字被遮挡
	ButtonTheme.override_margin_right(confirm_button, 88)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 允许按钮高度随内容自适应（取消固定最小高度限制）
	confirm_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_button.custom_minimum_size.y = 0

	# 切换按钮：短文字，叠在选项按钮右侧，高度跟随选项按钮
	var toggle_button := Button.new()
	var toggle_text := "默认" if is_bet_mode else "押注"
	toggle_button.text = toggle_text
	toggle_button.pressed.connect(_on_bet_toggle_for_option.bind(option_id))
	ButtonTheme.apply(toggle_button, ButtonTheme.PRESET_TOGGLE)

	# 外层容器：HBoxContainer 让选项按钮自然撑高，切换按钮跟随高度
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	# 选项按钮占据剩余宽度
	wrapper.add_child(confirm_button)
	# 切换按钮固定宽度，高度跟随容器
	toggle_button.custom_minimum_size.x = 72
	toggle_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(toggle_button)
	option_list.add_child(wrapper)


# 功能：构建选项状态辅助文本（可选/不可选 + ID）。
func _build_option_state_text(option_def: Dictionary) -> String:
	var state := str(option_def.get("state", "disabled"))
	var id := str(option_def.get("id", ""))
	var state_marker := "● 可选" if state == "selectable" else "○ 不可选"
	return "%s    [%s]" % [state_marker, id]


# 功能：处理带押注决策的选项点击。
# 说明：链式调用引擎 — 先提交选项选择，引擎挂起到 preemptive_bet phase 后
#       立即自动提交押注决策（accept/reject），一步完成选项结算。
func _on_option_with_bet_pressed(option_id: String, bet_decision: String) -> void:
	if _current_turn_result.is_empty():
		status_label.text = "当前没有待处理的事件选择。"
		return

	# 第一步：提交选项选择 → 引擎扣 cost、挂起到 preemptive_bet phase
	var mid_result := _engine.confirm_pending_turn(option_id)
	if not mid_result.get("ok", false):
		status_label.text = "选项结算失败: %s" % str(mid_result.get("error", "unknown"))
		_update_side_panels()
		return

	# 确认引擎已进入 preemptive_bet phase
	var mid_phase := str(mid_result.get("phase", ""))
	if mid_phase != "preemptive_bet":
		# 未挂起（可能条件不满足），直接按普通结算处理
		var choice: Dictionary = mid_result.get("choice", {})
		var resolved_log := "已选择 %s -> %s | %s" % [
			str(choice.get("selected_option_id", "")),
			str(mid_result.get("event_id", "")),
			str(mid_result.get("title", ""))
		]
		_handle_resolved_turn_result(mid_result, resolved_log)
		return

	# 第二步：立即提交押注决策 → 引擎执行检定并完成结算
	var turn_result := _engine.confirm_pending_turn(bet_decision)
	if not turn_result.get("ok", false):
		status_label.text = "押注结算失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var choice: Dictionary = turn_result.get("choice", {})
	var bet_label := "押注" if bet_decision == "accept" else "默认"
	var resolved_log := "已选择 %s [%s] -> %s | %s" % [
		str(choice.get("selected_option_id", "")),
		bet_label,
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	_handle_resolved_turn_result(turn_result, resolved_log)


# 功能：处理单个选项的押注模式切换按钮点击。
# 说明：翻转该选项的 _bet_mode_options 状态后重新渲染当前事件界面。
func _on_bet_toggle_for_option(option_id: String) -> void:
	var current: bool = bool(_bet_mode_options.get(option_id, false))
	_bet_mode_options[option_id] = not current
	_render_current_event(_current_turn_result)


# 功能：构建鉴定结果摘要文本，用于追加到事件详情区。
# 说明：仅在 check_result 非空时返回内容，包含骰池明细和关系修正。
func _build_check_result_summary(turn_result: Dictionary) -> String:
	var check_result: Dictionary = turn_result.get("check_result", {})
	if check_result.is_empty():
		return ""
	var lines: Array[String] = []
	var result_type := str(check_result.get("result_type", ""))
	var is_pass := bool(check_result.get("pass", true))
	var is_gamble := bool(check_result.get("is_desperate_gamble", false))
	var prefix := "【孤注一掷重掷】" if is_gamble else "【鉴定结果】"
	lines.append("%s %s (%s)" % [prefix, result_type, "通过" if is_pass else "失败"])

	var pool_size := int(check_result.get("pool_size", 0))
	if pool_size > 0:
		var dice: Array = check_result.get("dice", [])
		var hits := int(check_result.get("hits", 0))
		var required_hits := int(check_result.get("requiredHits", 1))
		lines.append("骰池: %dd10  骰面: %s  命中: %d/%d" % [pool_size, str(dice), hits, required_hits])

	# 关系修正摘要
	var rel_details: Array = check_result.get("relationship_details", [])
	for rel_entry_variant in rel_details:
		var rel_entry: Dictionary = rel_entry_variant
		var npc_id := str(rel_entry.get("npc_id", ""))
		var detail: Dictionary = rel_entry.get("detail", {})
		var bias := int(detail.get("bias", 0))
		var npc_tier := str(detail.get("npc_tier", ""))
		var direction := str(detail.get("direction", ""))
		lines.append("关系修正: %s (%s, %s) bias=%+d" % [npc_id, npc_tier, direction, bias])

	# 心性转移摘要
	var transition: Dictionary = turn_result.get("xinxing_transition", {})
	if not transition.is_empty():
		lines.append("心性转移: %d → %d" % [
			int(transition.get("old_value", 0)),
			int(transition.get("new_value", 0))
		])

	return "\n".join(lines)


# 功能：处理玩家点击选项。
# 说明：先结算当前待处理事件，再统一走结果分流入口，避免结束态判断散落在多个回调里。
func _on_option_pressed(option_id: String) -> void:
	if _current_turn_result.is_empty():
		status_label.text = "当前没有待处理的事件选择。"
		return

	var turn_result := _engine.confirm_pending_turn(option_id)
	if not turn_result.get("ok", false):
		status_label.text = "选项结算失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var choice: Dictionary = turn_result.get("choice", {})
	var resolved_log := "已选择 %s -> %s | %s" % [
		str(choice.get("selected_option_id", "")),
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	_handle_resolved_turn_result(turn_result, resolved_log)


# 功能：处理继续指令。
# 说明：展示阶段点击继续只推进到下一条展示文本；确认阶段点击继续才会真正结算当前事件。
func _on_continue_button_pressed() -> void:
	if _current_turn_result.is_empty():
		_preview_next_event()
		return
	var current_phase := str(_current_turn_result.get("phase", "confirm"))
	if current_phase == "choice":
		status_label.text = "当前事件需要先完成选项选择。"
		return
	if current_phase == "reflection":
		status_label.text = "自省进行中，请通过自省操作按钮交互。"
		return

	var turn_result := _engine.confirm_pending_turn()
	if not turn_result.get("ok", false):
		status_label.text = "事件结算失败: %s" % str(turn_result.get("error", "unknown"))
		_update_side_panels()
		return

	var resolved_log := "已确认继续 -> %s | %s" % [
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", ""))
	]
	_handle_resolved_turn_result(turn_result, resolved_log)


# 功能：统一处理已结算的回合结果。
# 说明：将日志、鉴定摘要、关系变化、结束态分流、侧栏刷新和下一次预览收口到一个入口。
func _handle_resolved_turn_result(turn_result: Dictionary, resolved_log: String) -> void:
	_append_log(resolved_log)
	# 鉴定结果日志
	_append_check_result_log(turn_result)
	# 关系变化日志
	_append_affinity_changes_log(turn_result)
	# 心性转移日志
	_append_xinxing_transition_log(turn_result)

	_current_turn_result = (turn_result as Dictionary).duplicate(true)
	if _is_world_ended_result(turn_result):
		_append_end_log(turn_result)
		_render_current_event(turn_result)
		_update_side_panels()
		return

	_update_side_panels()
	_preview_next_event()


# 功能：构建当前事件的调试元数据文本，用于右侧面板展示。
# 说明：展示背景、route、policy、phase、展示进度与当前 world turn，便于核对”展示后结算”的推进时机。
func _build_event_debug_text(turn_result: Dictionary) -> String:
	var choice: Dictionary = turn_result.get("choice", {})
	var presentation: Dictionary = turn_result.get("presentation", {})
	var lines: Array[String] = []
	lines.append("event_background_art=%s" % str(turn_result.get("event_background_art", "")))
	lines.append("location_background_art=%s" % str(turn_result.get("location_background_art", "")))
	lines.append("resolved_background_art=%s" % str(turn_result.get("resolved_background_art", "")))
	lines.append("route=%s" % str(turn_result.get("route", "")))
	lines.append("policy=%s" % str(turn_result.get("policy", "")))
	lines.append("phase=%s" % str(turn_result.get("phase", "")))
	lines.append(
		"presentation=%s/%s" % [
			str(int(presentation.get("index", -1)) + 1 if bool(presentation.get("active", false)) else 0),
			str(presentation.get("total", 0))
		]
	)
	lines.append("choice_point=%s" % str(choice.get("choice_point_id", "")))
	lines.append("chain_active=%s" % str(turn_result.get("chain_active", false)))
	lines.append("world_turn=%s" % str(_engine.world_state.get("turn", 0)))
	lines.append("run_status=%s" % str(turn_result.get("run_status", "")))
	lines.append("world_ended=%s" % str(turn_result.get("world_ended", false)))
	lines.append("ending_event_id=%s" % str(turn_result.get("ending_event_id", "")))
	lines.append("finished_turn=%s" % str(turn_result.get("finished_turn", 0)))
	# 自省调试信息。
	if turn_result.has("reflection_state"):
		lines.append("reflection_state=%s" % str(turn_result.get("reflection_state", "")))
		lines.append("reflection_ops_remaining=%s" % str(turn_result.get("reflection_ops_remaining", 0)))
	# 叙事包调试信息。
	var pack_ctx: Dictionary = _engine.world_state.get("packContext", {})
	if not pack_ctx.is_empty():
		lines.append("pack=%s turns=%d/%d interrupted=%s" % [
			str(pack_ctx.get("locationId", "")),
			int(pack_ctx.get("turnsElapsed", 0)),
			int(pack_ctx.get("turnCapacity", 0)),
			str(pack_ctx.get("interrupted", false))
		])
	return "\n".join(lines)


# 功能：生成选项按钮文本。
# 说明：主文本居前，ID 和状态标签放在第二行辅助区，方便一眼看清内容再核对元数据。
func _build_option_button_text(option_def: Dictionary) -> String:
	var state := str(option_def.get("state", "disabled"))
	var text := str(option_def.get("text", ""))
	var id := str(option_def.get("id", ""))
	var state_marker := "● 可选" if state == "selectable" else "○ 不可选"
	# 主文本 + 辅助信息行
	return "%s\n    %s    [%s]" % [text, state_marker, id]


# 功能：刷新左侧任务摘要面板。
# 说明：将进行中的任务和当前事件关联任务交给独立 UI 组件渲染，测试场景只负责准备数据。
func _update_left_task_panel(turn_result: Dictionary) -> void:
	var world_state := _engine.world_state
	var tasks_state: Dictionary = world_state.get("tasks", {})
	var active: Array = tasks_state.get("active", [])
	var current_turn := int(world_state.get("turn", 0))
	var event_id := str(turn_result.get("event_id", "")).strip_edges()
	var event_def: Dictionary = _engine._event_map.get(event_id, {})
	var task_links: Array = event_def.get("taskLinks", [])
	task_summary_card.bind_data(active, task_links, current_turn)


# 功能：刷新左侧角色/世界面板 + 右侧调试面板 + 底部日志。
# 说明：角色与世界信息展示在左侧背景图上方；右侧只保留调试/参考数据（事件元数据、关系、运行态、任务明细、历史）。
func _update_side_panels() -> void:
	var world_state := _engine.world_state
	var player: Dictionary = world_state.get("player", {})
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	var run_state: Dictionary = world_state.get("runState", {})
	var chain_context: Variant = world_state.get("chainContext", null)
	var history: Array = world_state.get("history", [])
	var task_config: Dictionary = world_state.get("taskConfig", {})
	var tasks_state: Dictionary = world_state.get("tasks", {})
	var xinxing_tracker: Dictionary = world_state.get("xinxingTracker", {})

	# ── 左侧：角色面板 ──
	_update_character_panel(player, xinxing_tracker)
	# ── 左侧：世界面板 ──
	_update_world_panel(world_state, params)

	# ── 右侧：调试/参考信息 ──
	var lines: Array[String] = []

	# 当前事件元数据
	if not _current_turn_result.is_empty():
		lines.append("═══ 当前事件 ═══")
		lines.append(_build_event_debug_text(_current_turn_result))
		lines.append("")

	# 关系
	var affinity_text := _build_affinity_display_text()
	if not affinity_text.is_empty():
		lines.append("═══ 关系 ═══")
		lines.append(affinity_text)
		lines.append("")

	# 运行态与标记
	lines.append("═══ 运行态 ═══")
	var flag_parts: Array[String] = []
	for flag_key in flags.keys():
		flag_parts.append("%s=%s" % [str(flag_key), str(flags[flag_key])])
	if not flag_parts.is_empty():
		lines.append("标记: %s" % "  ".join(flag_parts))
	lines.append(
		"status=%s  ending=%s  finished_turn=%s" % [
			str(run_state.get("status", "")),
			str(run_state.get("endingEventId", "")),
			str(run_state.get("finishedTurn", 0))
		]
	)
	if world_state.get("forcedNextEventId", "") != "":
		lines.append("强制下一事件: %s" % str(world_state.get("forcedNextEventId", "")))
	if typeof(chain_context) == TYPE_DICTIONARY and chain_context != null:
		lines.append("链上下文: %s" % JSON.stringify(chain_context))

	# 任务明细
	lines.append("")
	lines.append(_build_task_debug_text(task_config, tasks_state))

	# 最近历史
	lines.append("")
	lines.append("═══ 最近历史 ═══")
	lines.append(", ".join(_history_to_string_array(history)))

	# 调试输出:仅在测试场景(节点存在)时写入;正式场景节点为 null,跳过。
	if world_state_label != null:
		world_state_label.text = "\n".join(lines)
		world_state_label.call_deferred("scroll_to_line", 0)
	if log_label != null:
		log_label.text = "\n".join(_event_logs)


# 功能：更新左侧角色面板。
# 说明：用紧凑的两行展示资源和四维能力，心性单独标注。
func _update_character_panel(player: Dictionary, xinxing_tracker: Dictionary) -> void:
	var xinxing := int(player.get("xinxing", 0))
	var steady := int(xinxing_tracker.get("steady_count", 0))
	var gamble := int(xinxing_tracker.get("gamble_count", 0))
	var hp := int(player.get("hp", 0))
	var energy := int(player.get("energy", 0))
	var gold := int(player.get("gold", 0))

	var line1 := "生命 %d    精力 %d    金币 %d    ┃    心性 %d（稳健%d / 孤注%d）" % [
		hp, energy, gold, xinxing, steady, gamble
	]
	var line2 := _build_ability_display_text()
	character_label.text = "%s\n%s" % [line1, line2]


# 功能：更新左侧世界面板。
# 说明：回合、地点、叙事包回合与三大参数紧凑排列，一眼可读。
func _update_world_panel(world_state: Dictionary, params: Dictionary) -> void:
	var turn := int(world_state.get("turn", 0))
	var location := str(world_state.get("currentLocationId", ""))
	var danger := int(params.get("danger", 0))
	var prosperity := int(params.get("prosperity", 0))
	var morale := int(params.get("morale", 0))
	# 叙事包回合：locationId 为空表示尚未开始包（首次进入或刚结束）。
	var pack_ctx: Dictionary = world_state.get("packContext", {})
	var pack_text := "未开始"
	if not str(pack_ctx.get("locationId", "")).is_empty():
		var elapsed := int(pack_ctx.get("turnsElapsed", 0))
		var capacity := int(pack_ctx.get("turnCapacity", 0))
		var interrupted_suffix := "（打断）" if bool(pack_ctx.get("interrupted", false)) else ""
		pack_text = "%d/%d%s" % [elapsed, capacity, interrupted_suffix]

	world_label.text = "回合 %d    地点 %s    包 %s    ┃    危险 %d    繁荣 %d    士气 %d" % [
		turn, location, pack_text, danger, prosperity, morale
	]


# 功能：构建四大能力的展示文本，包含原始值和鉴定阶段。
# 说明：用紧凑的 "名称 数值·阶段N" 格式，横向排列四个能力。
func _build_ability_display_text() -> String:
	if _engine.player_role_state == null:
		return "能力数据缺失"
	var role: RoleState = _engine.player_role_state
	var thresholds: Array = _engine.get_assessment_thresholds()
	var ability_keys := ["aptitude", "physique", "craft", "insight"]
	var parts: Array[String] = []
	for key in ability_keys:
		var value := int(role.get_attribute(key, 0))
		var stage := RuleEngine.get_ability_stage(value, thresholds)
		parts.append("%s %d · 阶段%d" % [RoleState.get_display_name(key), value, stage])
	return "    ".join(parts)


# 功能：构建关系面板展示文本。
# 说明：遍历 affinity_map 所有关系对，按 from→to 格式列出分值和档位。
func _build_affinity_display_text() -> String:
	var snapshot: Array = _engine.get_affinity_snapshot()
	if snapshot.is_empty():
		return ""
	var lines: Array[String] = []
	for pair_variant in snapshot:
		var pair: Dictionary = pair_variant
		lines.append("%s→%s: %d (%s)" % [
			str(pair.get("from", "")),
			str(pair.get("to", "")),
			int(pair.get("score", 0)),
			str(pair.get("tier", ""))
		])
	return "\n".join(lines)


# 功能：判断当前返回结果是否代表世界结束。
# 说明：统一消费引擎公开字段，避免界面层自行依赖内部 world_state 细节推断 ended。
func _is_world_ended_result(turn_result: Dictionary) -> bool:
	return bool(turn_result.get("world_ended", false)) \
		or str(turn_result.get("run_status", "")).strip_edges() == "ended" \
		or str(turn_result.get("phase", "")).strip_edges() == "ended"


# 功能：渲染世界结束界面。
# 说明：结束后切换到独立页面，隐藏事件交互区，保留终局事件与结束态摘要供手动验收。
func _render_end_screen(turn_result: Dictionary) -> void:
	_set_end_screen_visible(true)
	var ending_model := _build_end_screen_model(turn_result)
	end_root.render_model(ending_model)
	status_label.text = "本轮已结束，当前显示终局结果页。"


# 功能：切换结束界面的显示状态。
# 说明：非结束态时恢复原事件测试界面，避免结束页与事件页同时可见。
func _set_end_screen_visible(visible: bool) -> void:
	end_root.visible = visible
	main_split.visible = not visible


# 功能：构建结束界面的展示文本。
# 说明：聚合终局事件返回、world_state.runState 与关键世界摘要，便于人工核对结束封口是否正确。
func _build_end_summary_text(turn_result: Dictionary, ending_title: String) -> String:
	var world_state := _engine.world_state
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	var lines: Array[String] = []
	lines.append("你在第 %s 回合迎来了“%s”。" % [
		str(turn_result.get("finished_turn", 0)),
		ending_title
	])
	lines.append("")
	lines.append(
		"最终数值：danger=%s  prosperity=%s  morale=%s" % [
			str(params.get("danger", 0)),
			str(params.get("prosperity", 0)),
			str(params.get("morale", 0))
		]
	)
	lines.append(
		"关键标记：isWanted=%s  gotHarborIntel=%s" % [
			str(flags.get("isWanted", false)),
			str(flags.get("gotHarborIntel", false))
		]
	)
	lines.append("")
	lines.append("如需继续验证，请重新进入场景开始下一轮。")
	return "\n".join(lines)


# 功能：构建结束界面的视图模型。
# 说明：将终局页需要的数据先收束成稳定结构，后续挂接流程按钮或切换数据源时只扩展 model，不直接改渲染主链。
func _build_end_screen_model(turn_result: Dictionary) -> Dictionary:
	var ending_event_id := _resolve_end_event_id(turn_result)
	var ending_title := _resolve_end_event_title(turn_result, ending_event_id)
	return {
		"title": ending_title,
		"subtitle": "本轮流程已正式结束。以下是本次测试最关键的结果摘要。",
		"endingEventId": ending_event_id,
		"finishedTurn": int(turn_result.get("finished_turn", 0)),
		"taskSummary": _build_end_task_summary(),
		"stateSummary": _build_end_state_summary(),
		"summaryText": _build_end_summary_text(turn_result, ending_title),
		"actions": []
	}


# 功能：响应终局页动作请求。
# 说明：当前先记录占位日志，后续若接入重开、切配置或进入下一流程，可在这里统一分发。
func _on_end_action_requested(action_id: String) -> void:
	_append_log("终局页动作触发: %s" % action_id)


# 功能：记录世界结束日志。
# 说明：结束态单独加一条高优先级日志，便于从底部日志快速确认终局已经命中。
func _append_end_log(turn_result: Dictionary) -> void:
	_append_log(
		"世界结束 | ending_event=%s | finished_turn=%s" % [
			str(turn_result.get("ending_event_id", "")),
			str(turn_result.get("finished_turn", 0))
		]
	)


# 功能：将鉴定结果写入日志，展示骰池明细与关系修正。
# 说明：仅在 check_result 非空时输出，避免无检定事件产生空日志。
func _append_check_result_log(turn_result: Dictionary) -> void:
	var check_result: Dictionary = turn_result.get("check_result", {})
	if check_result.is_empty():
		return
	var result_type := str(check_result.get("result_type", ""))
	var is_pass := bool(check_result.get("pass", true))
	var pool_size := int(check_result.get("pool_size", 0))
	var dice: Array = check_result.get("dice", [])
	var hits := int(check_result.get("hits", 0))
	var required_hits := int(check_result.get("requiredHits", 1))
	var is_gamble := bool(check_result.get("is_desperate_gamble", false))
	var prefix := "孤注一掷重掷" if is_gamble else "鉴定"
	if pool_size > 0:
		_append_log(
			"%s | %s(%s) | 骰池:%dd10 骰面:%s 命中:%d/%d" % [
				prefix, result_type, "通过" if is_pass else "失败",
				pool_size, str(dice), hits, required_hits
			]
		)
	else:
		_append_log("%s | %s(%s)" % [prefix, result_type, "通过" if is_pass else "失败"])

	# 关系修正明细
	var rel_details: Array = check_result.get("relationship_details", [])
	for rel_entry_variant in rel_details:
		var rel_entry: Dictionary = rel_entry_variant
		var npc_id := str(rel_entry.get("npc_id", ""))
		var detail: Dictionary = rel_entry.get("detail", {})
		var bias := int(detail.get("bias", 0))
		if bias == 0:
			continue
		_append_log(
			"  关系修正 | %s | 档位:%s | 方向:%s | 对齐:%s | bias:%+d" % [
				npc_id,
				str(detail.get("npc_tier", "")),
				str(detail.get("direction", "")),
				str(detail.get("aligned", false)),
				bias
			]
		)


# 功能：将关系变化写入日志。
# 说明：仅在 affinity_changes 非空时输出。
func _append_affinity_changes_log(turn_result: Dictionary) -> void:
	var changes: Array = turn_result.get("affinity_changes", [])
	if changes.is_empty():
		return
	var parts: Array[String] = []
	for change_variant in changes:
		var change: Dictionary = change_variant
		parts.append("%s→%s: %+d (%d→%d, %s)" % [
			str(change.get("from", "")),
			str(change.get("to", "")),
			int(change.get("delta", 0)),
			int(change.get("old_score", 0)),
			int(change.get("new_score", 0)),
			str(change.get("new_tier", ""))
		])
	_append_log("关系变化 | %s" % " | ".join(parts))


# 功能：将心性转移写入日志。
func _append_xinxing_transition_log(turn_result: Dictionary) -> void:
	var transition: Dictionary = turn_result.get("xinxing_transition", {})
	if transition.is_empty():
		return
	_append_log("心性转移 | %d → %d" % [
		int(transition.get("old_value", 0)),
		int(transition.get("new_value", 0))
	])


# 功能：解析终局事件 id。
# 说明：优先使用引擎返回字段；若 ended 短路返回未携带 event_id，则回退读取 world_state.runState。
func _resolve_end_event_id(turn_result: Dictionary) -> String:
	var ending_event_id := str(turn_result.get("ending_event_id", "")).strip_edges()
	if not ending_event_id.is_empty():
		return ending_event_id
	var run_state: Dictionary = _engine.world_state.get("runState", {})
	return str(run_state.get("endingEventId", "")).strip_edges()


# 功能：解析终局事件标题。
# 说明：resolved 结果通常自带 title；若当前是 ended 短路返回，则通过 event_id 回查事件定义。
func _resolve_end_event_title(turn_result: Dictionary, ending_event_id: String) -> String:
	var title := str(turn_result.get("title", "")).strip_edges()
	if not title.is_empty():
		return title
	var event_def: Dictionary = _engine._event_map.get(ending_event_id, {})
	title = str(event_def.get("title", "")).strip_edges()
	if not title.is_empty():
		return title
	return "本轮已结束"


# 功能：构建任务结果摘要。
# 说明：终局页只显示必要统计，不再展开完整任务调试明细。
func _build_end_task_summary() -> String:
	var tasks_state: Dictionary = _engine.world_state.get("tasks", {})
	return "完成 %s / 失败 %s / 放弃 %s" % [
		str((tasks_state.get("completed", []) as Array).size()),
		str((tasks_state.get("failed", []) as Array).size()),
		str((tasks_state.get("abandoned", []) as Array).size())
	]


# 功能：构建最终状态摘要卡片。
# 说明：将最影响结果理解的状态压缩成一行，避免终局界面退化成调试面板。
func _build_end_state_summary() -> String:
	var world_state := _engine.world_state
	var params: Dictionary = world_state.get("params", {})
	var flags: Dictionary = world_state.get("flags", {})
	return "danger=%s | morale=%s | wanted=%s" % [
		str(params.get("danger", 0)),
		str(params.get("morale", 0)),
		str(flags.get("isWanted", false))
	]


# 功能：构建任务调试信息文本。
# 说明：将任务配置、进行中任务、归档结果和最近结算记录整理成多行文本，便于在测试场景中直接观察任务推进。
func _build_task_debug_text(task_config: Dictionary, tasks_state: Dictionary) -> String:
	var lines: Array[String] = []
	var active: Array = tasks_state.get("active", [])
	var completed: Array = tasks_state.get("completed", [])
	var failed: Array = tasks_state.get("failed", [])
	var abandoned: Array = tasks_state.get("abandoned", [])
	var result_records: Array = tasks_state.get("resultRecords", [])

	lines.append("任务状态")
	lines.append("maxActiveCount=%s" % str(task_config.get("maxActiveCount", 1)))
	lines.append("active_count=%s" % str(active.size()))
	lines.append("completed=%s" % JSON.stringify(completed))
	lines.append("failed=%s" % JSON.stringify(failed))
	lines.append("abandoned=%s" % JSON.stringify(abandoned))
	lines.append("")

	lines.append("进行中任务")
	if active.is_empty():
		lines.append("无")
	else:
		for task_variant in active:
			var task: Dictionary = task_variant
			lines.append(
				"- %s | accepted=%s | deadline=%s | progress=%s" % [
					str(task.get("taskId", "")),
					str(task.get("acceptedTurn", 0)),
					str(task.get("deadlineTurn", 0)),
					JSON.stringify(task.get("progress", {}))
				]
			)

	lines.append("")
	lines.append("最近任务结算")
	if result_records.is_empty():
		lines.append("无")
	else:
		# 说明：仅展示最近 5 条结算记录，避免右侧调试面板被历史数据完全占满。
		for idx in range(maxi(0, result_records.size() - 5), result_records.size()):
			var record: Dictionary = result_records[idx]
			lines.append(
				"- %s | status=%s | grade=%s | score=%s | finished=%s | reason=%s | progress=%s" % [
					str(record.get("taskId", "")),
					str(record.get("status", "")),
					str(record.get("gradeId", "")),
					str(record.get("score", null)),
					str(record.get("finishedTurn", 0)),
					str(record.get("reason", "")),
					JSON.stringify(record.get("progress", {}))
				]
			)

	return "\n".join(lines)


# 功能：记录每次事件预览日志。
# 说明：将展示阶段、等待选择、等待确认显式写入日志，便于核对界面状态与引擎 phase 是否一致。
func _append_turn_log(turn_result: Dictionary) -> void:
	var phase := str(turn_result.get("phase", "confirm"))
	var line := "Turn %s | %s | %s | route=%s | policy=%s | background=%s" % [
		str(_engine.world_state.get("turn", 0)),
		str(turn_result.get("event_id", "")),
		str(turn_result.get("title", "")),
		str(turn_result.get("route", "")),
		str(turn_result.get("policy", "")),
		str(turn_result.get("resolved_background_art", ""))
	]
	if phase == "presentation":
		line += " | 展示阶段"
	elif turn_result.get("awaiting_choice", false):
		line += " | 等待选择"
	else:
		line += " | 等待确认"
	_append_log(line)


# 功能：向日志列表追加文本。
# 说明：只保留最近 18 条，避免测试界面日志无限增长。
func _append_log(line: String) -> void:
	_event_logs.append(line)
	while _event_logs.size() > 18:
		_event_logs.pop_front()


# 功能：清空选项列表 + 隐藏继续页脚。
# 说明：切换到新事件前先移除旧选项卡 / 按钮 / 提示文本,并默认隐藏底部继续朱字。
#       具体路径会按需通过 _show_continue_footer 重新显示继续页脚。
#       同时清空 _continue_handler 防御 stale callback —— 即使未来有路径绕过 _show_continue_footer
#       直接将 continue_button.visible 改回 true,旧 phase 的回调也不会被静默触发。
func _clear_option_list() -> void:
	for child in option_list.get_children():
		child.queue_free()
	# 议题 B:每次清空时默认隐藏继续页脚,由调用方按状态决定是否再显示
	if continue_button != null:
		continue_button.visible = false
		continue_button.disabled = true
	_continue_handler = Callable()


# 功能：议题 B 聚合面板的"继续"页脚 —— 显示叙事面板底部的小朱字提示。
# 说明：替代旧 _add_continue_button_to_option_list（不再把"继续"作为列表项渲染）;
#       状态 A（无真选项）调用此函数显示"继续 ›";
#       状态 B（有真选项）不调用,由 _clear_option_list 默认隐藏。
# 参数 callback:可选回调（默认走普通事件 _on_continue_button_pressed）;
#       开局选择 / 开局后果等 phase 传入对应的 advance/confirm 回调。
func _show_continue_footer(label_text: String, callback: Callable = Callable()) -> void:
	if continue_button == null:
		return
	continue_button.text = label_text
	continue_button.visible = true
	continue_button.disabled = false
	# 路由切换:回调有效则改 _continue_handler,否则回到默认普通事件路径
	if callback.is_valid():
		_continue_handler = callback
	else:
		_continue_handler = Callable(self, "_on_continue_button_pressed")


# 功能：ContinueButton.pressed 信号的统一路由器。
# 说明：根据当前 phase 的 _continue_handler 分流到对应回调（普通事件 / 创建 narrating / 创建 outcome）;
#       _continue_handler 未设置时兜底走普通事件路径,避免开局阶段误触导致 null 调用。
func _on_continue_footer_pressed_router() -> void:
	if _continue_handler.is_valid():
		_continue_handler.call()
	else:
		_on_continue_button_pressed()


# 功能：议题 B 调整 4 —— 把整张叙事面板作为"继续"扩展点击区域。
# 说明：仅 continue_button 可见时(状态 A)接收转发；状态 B(有 OptionCard)时 continue_button 隐藏,handler 直接 return。
#       OptionCard 自身 mouse_filter=STOP 会拦截卡片区域点击,NarrativePanel 只收到空白区点击,与 OptionCard 不冲突。
#       依赖 EventDetail / EventTitle 的 mouse_filter=IGNORE(在 tscn 中配置),让事件传递到 NarrativePanel。
func _on_narrative_panel_gui_input(event: InputEvent) -> void:
	if continue_button == null or not continue_button.visible:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_on_continue_footer_pressed_router()
			accept_event()


# 功能：在选项列表中插入分隔标签。
# 说明：用于区分普通选项和特殊入口（押注、孤注一掷等）。
func _add_option_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UI_TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	option_list.add_child(label)


# 功能：添加选项区域提示文本。
# 说明：用于展示”无可见选项”等状态说明。
func _add_option_hint(text: String) -> void:
	var hint_label := Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", UI_TEXT_SECONDARY)
	option_list.add_child(hint_label)


# 功能:初始化左侧叠加层各区域的样式(UI 风格快速翻调 Phase 1)。
# 说明:从"半透明深色面板 + 浅色字"翻转为"米白半透纸面 + 深褐墨字",
#       上层 UI 与底层文字马赛克同源(共用 BackgroundColor 的米白纸面色),
#       视觉上是"局部 mosaic 字符稀疏化"而非"灰布贴在画上"。
#       三个面板共享同一种 panel_paper 颜色:层级靠透明度/字号/间距区分,不靠颜色拼贴。
func _setup_overlay_styles() -> void:
	# 通用米白半透纸面样式工厂
	var base_panel_style := StyleBoxFlat.new()
	base_panel_style.bg_color = UI_PANEL_PAPER
	# 圆角降到极小(2px),保留极轻微圆角避免硬切感,但不再像"卡片"
	base_panel_style.corner_radius_top_left = 2
	base_panel_style.corner_radius_top_right = 2
	base_panel_style.corner_radius_bottom_left = 2
	base_panel_style.corner_radius_bottom_right = 2
	base_panel_style.content_margin_left = 14
	base_panel_style.content_margin_right = 14
	base_panel_style.content_margin_top = 10
	base_panel_style.content_margin_bottom = 10

	# 角色面板
	character_panel.add_theme_stylebox_override("panel", base_panel_style)
	character_label.add_theme_color_override("font_color", UI_TEXT_PRIMARY)
	character_label.add_theme_font_size_override("font_size", 13)

	# 世界面板(与角色面板同 stylebox 复用,同源色板下不再做多色面板)
	var world_style: StyleBoxFlat = base_panel_style.duplicate()
	world_panel.add_theme_stylebox_override("panel", world_style)
	world_label.add_theme_color_override("font_color", UI_TEXT_PRIMARY)
	world_label.add_theme_font_size_override("font_size", 13)

	# 叙事面板(承担当前事件焦点,视觉权重最重):
	#   - alpha 0.85 比状态条 0.75 略实,纸面更"凝",焦点感出来 ← 调 alpha 改这一行第 4 个分量
	#   - 标题用焦墨色 + 22px,与正文 17px 拉开内部层级(标题已隐藏,保留逻辑兼容)
	#   - padding 比状态条更舒展
	#   - 信笺风格描边:细线浅墨 1px + 极小圆角 2px,模拟"内嵌细边"的纸面信笺感,
	#     与底层 mosaic 字符同源(都是 ink),不引入异质材质
	# 不引入朱色到标题:朱色严格只给"玩家伸手"位(选项/继续),标题是事件信息不破规。
	var narrative_style: StyleBoxFlat = base_panel_style.duplicate()
	narrative_style.bg_color = Color(0.957, 0.925, 0.847, 0.75)
	narrative_style.content_margin_left = 16
	narrative_style.content_margin_right = 16
	narrative_style.content_margin_top = 12
	narrative_style.content_margin_bottom = 12
	# 信笺细描边
	narrative_style.border_color = Color(0.353, 0.310, 0.271, 0.55)
	narrative_style.border_width_left = 1
	narrative_style.border_width_right = 1
	narrative_style.border_width_top = 1
	narrative_style.border_width_bottom = 1
	narrative_style.corner_radius_top_left = 2
	narrative_style.corner_radius_top_right = 2
	narrative_style.corner_radius_bottom_left = 2
	narrative_style.corner_radius_bottom_right = 2
	narrative_panel.add_theme_stylebox_override("panel", narrative_style)
	# 焦墨:比 text_primary(深褐墨)更深的标题色,与正文形成层级压差
	var ink_focal_color := Color(0.102, 0.086, 0.071, 1.0)
	event_title_label.add_theme_color_override("font_color", ink_focal_color)
	event_title_label.add_theme_font_size_override("font_size", 22)
	# 标题用思源宋体 Bold,方头字形与印章字呼应("宋骨楷血"搭配)
	event_title_label.add_theme_font_override("font", FONT_SERIF_BOLD)
	event_detail_label.add_theme_color_override("font_color", UI_TEXT_PRIMARY)
	event_detail_label.add_theme_font_size_override("font_size", 17)

	# 继续按钮(议题 B 聚合面板页脚朱字):flat=true 已让按钮无 stylebox,这里只控字色 + 字号,
	# 视觉降级为"叙事末尾的小提示" —— 朱色保留"伸手"语义,字号小于正文减弱权重。
	# 状态 A(无真选项):显示"继续 ›";状态 B(有真选项):隐藏(由 _render_choice_options 路径控制)。
	continue_button.add_theme_color_override("font_color", UI_ACCENT_ZHU)
	continue_button.add_theme_color_override("font_hover_color", UI_ACCENT_ZHU)
	continue_button.add_theme_color_override("font_pressed_color", UI_ACCENT_ZHU)
	continue_button.add_theme_color_override("font_focus_color", UI_ACCENT_ZHU)
	continue_button.add_theme_font_size_override("font_size", 14)


# 功能：Phase 1.5 印章式状态条 mock(参见 [[UI风格快速翻调_demo期进度]] § 印章方向讨论)。
# 说明：暂时隐藏 CharacterPanel/WorldPanel,在 LeftContent 顶部插入 5 枚朱印 PanelContainer
#       占位,看"小尖锐朱印 vs 大叙事面板"的视觉权重对比是否对路。
#       内容用现有标签+数值占位(不做 icon 字 / 定性化,那是用户领域,确认形态后单独议题)。
#       哲学锚点:朱印是国画的内置语言(鉴藏印 / 钤印 / 题款印),与"修行者凝视画里世界 +
#       留下行动痕迹"哲学契合;朱色语义从"玩家伸手"扩展为"看画人 / 修行者的痕迹"。
#       回退方法:注释掉 _ready() 中本函数调用 + 删除/隐藏 SealRow_Mock 节点即可恢复原状态条。
#       后续:形态确认后由大模型美术出图(朱印 PNG 资产)优化精致度。
func _setup_seal_row_mock() -> void:
	# 隐藏现有状态面板(原 CharacterPanel / WorldPanel 数值仍由后续逻辑更新但不显示)
	character_panel.visible = false
	world_panel.visible = false

	# 朱印占位内容:5 枚,主字 + 副字独立配置(主字大、青鸟美黑;副字小、宋体 Medium)。
	# icon 字取核心义("命/力/金/心/回"是 Claude 占位选字,最终由用户裁断);
	# 数值 2 位处理:>99 capped / 1 位前导 0 / 负号占位 → 各印章宽度相近便于排版观察。
	var seal_items: Array = [
		{"main": "命", "value": "99"},
		{"main": "力", "value": "99"},
		{"main": "金", "value": "30"},
		{"main": "心", "value": "-2"},
		{"main": "回", "value": "01"},
	]

	# 墨印阴刻 SealPanel(自定义 Control,三层叠加渲染:实色墨底 + 斑驳墨层 + 反白主字)
	# 哲学锚点(2026-05-06 用户设计修订):
	#   状态 = 修行者内观自己 → 墨色(与画面 mosaic 字符同源,含蓄内向)
	#   选项 = 修行者伸手介入 → 朱色(独一份,关键时刻用在刀刃上)
	#   斑驳墨层用 sin(x,y,seed) noise 驱动字符密度,模拟印泥不均;各印章 seed 不同
	#   产生各异斑驳模式 —— 与 text_mosaic_background.gd 同源算法的简化版,
	#   把"印章质感"做到美术资源 80% 效果(余 20% 等出图后替换 SealPanel 实现)。
	# 朱印容器:HBoxContainer + 右对齐 + separation 10(用户反馈紧凑些)
	var seal_row := HBoxContainer.new()
	seal_row.name = "SealRow_Mock"
	seal_row.add_theme_constant_override("separation", 10)
	seal_row.alignment = BoxContainer.ALIGNMENT_END
	seal_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for i in range(seal_items.size()):
		var item: Dictionary = seal_items[i]
		var seal: SealPanel = SealPanel.new()
		# 主字青鸟美黑 22(粗壮书法感) + 副字宋体 Medium 11(规整数字);各印章 seed 不同
		seal.set_seal(
			item["main"], item["value"],
			FONT_QINGNIAO_MEIHEI, 22,
			FONT_SERIF_MEDIUM, 15,
			i
		)
		seal_row.add_child(seal)

	# 插入到 LeftContent 顶部(原 character_panel 位置)
	var left_content: Node = character_panel.get_parent()
	left_content.add_child(seal_row)
	left_content.move_child(seal_row, 0)


# 功能：初始化全屏装饰衬底。
# 说明：优先加载美术资源作为窗口超宽时的侧边装饰；未找到资源时用深色渐变兜底。
func _setup_screen_background() -> void:
	# 尝试加载装饰衬底贴图（可替换为任意美术资源路径）
	var bg_path := "res://assets/art/environments/backgrounds/town.svg"
	var bg_res: Variant = ResourceLoader.load(bg_path)
	if bg_res is Texture2D:
		screen_background.texture = bg_res
		screen_background.modulate = Color(0.25, 0.25, 0.30, 1.0)
	else:
		# 兜底：无贴图时用纯深色，通过 modulate 控制
		screen_background.texture = null
	# 确保衬底始终处于最底层
	screen_background.show_behind_parent = true


# 功能：响应视口尺寸变化，委托 ResponsiveLayout 计算后应用业务层布局。
# 说明：三阶段布局计算由工具库完成，本方法只负责业务响应（右栏显隐、衬底显隐）。
func _on_viewport_resized() -> void:
	if _resizing:
		return
	_resizing = true

	var layout := ResponsiveLayout.calc_layout(get_viewport())

	# 阶段1：比例锁定
	ResponsiveLayout.apply_aspect_lock(layout)

	# 阶段2：右栏显隐 — 高度触顶后宽度自由，右栏出现(仅测试场景有右栏;正式场景跳过)
	if right_column != null:
		right_column.visible = bool(layout.get("height_capped", false))

	# 阶段3：超宽居中 margin + 装饰衬底显隐
	ResponsiveLayout.apply_margins(root_margin, layout)
	screen_background.visible = bool(layout.get("is_ultrawide", false))

	_resizing = false


# 功能：渲染当前事件背景图。
# 说明：只消费引擎已解析好的最终背景路径；Consumer 不再自行实现事件/地点 fallback 规则。
#       同步驱动三层视觉:
#         - EventBackground(原图层,作为 fallback)
#         - TextMosaicBackground(静态文字层)
#         - TextMosaicParticles(动态粒子层,在 flow_regions JSON 定义的主体内流动)
#       从 _engine.world_state.currentLocationId 取地点 ID 决定 token 集合。
func _render_event_background(background_art_path: String) -> void:
	# Step 3：消费引擎已解析的最终背景路径（事件 backgroundArt → 地点 art_file → 空字符串）。
	# 路径为空时进入空白底兜底分支，清空所有 mosaic 层。
	# 自省事件（sys_*_reflection）通过 events.csv background_art 字段配 pond_girl_enter.png，
	# 走引擎 fallback 链产出 girl_enter 路径，复用 IntroSequence 终态视觉（不需 Consumer 特判）。
	var normalized_path := background_art_path.strip_edges()
	if normalized_path.is_empty():
		event_background_rect.texture = null
		text_mosaic_bg.set_source_image(null)
		text_mosaic_particles.set_source_image(null)
		text_mosaic_particles.clear_flow_data()
		if text_mosaic_coarse != null:
			text_mosaic_coarse.set_source_image(null)
		if text_mosaic_medium != null:
			text_mosaic_medium.set_source_image(null)
		if text_mosaic_dark_light != null:
			text_mosaic_dark_light.set_source_image(null)
		if text_mosaic_dark_accent != null:
			text_mosaic_dark_accent.set_source_image(null)
		if text_mosaic_dark_deep != null:
			text_mosaic_dark_deep.set_source_image(null)
		if text_mosaic_dark_ink != null:
			text_mosaic_dark_ink.set_source_image(null)
		if text_mosaic_dark_between != null:
			text_mosaic_dark_between.set_source_image(null)
		if text_mosaic_dark_abyss != null:
			text_mosaic_dark_abyss.set_source_image(null)
		if text_mosaic_mid_dark != null:
			text_mosaic_mid_dark.set_source_image(null)
		if text_mosaic_mid_light != null:
			text_mosaic_mid_light.set_source_image(null)
		if text_mosaic_highlight != null:
			text_mosaic_highlight.set_source_image(null)
		if text_mosaic_accent != null:
			text_mosaic_accent.set_source_image(null)
		if text_mosaic_accent_marked != null:
			text_mosaic_accent_marked.set_source_image(null)
			text_mosaic_accent_marked.clear_accent_data()
		if screen_mosaic_coarse != null:
			screen_mosaic_coarse.set_source_image(null)
		if screen_mosaic_medium != null:
			screen_mosaic_medium.set_source_image(null)
		if screen_mosaic_bg != null:
			screen_mosaic_bg.set_source_image(null)
		return

	var resource := ResourceLoader.load(normalized_path)
	var texture: Texture2D = resource if resource is Texture2D else null
	# Step 3 决策（方案 A）：原图层显隐策略延后到 Step 4/5 美术资产入库阶段定。
	# 当前所有事件背景统一走 mosaic 层渲染（texture 仅作 source 生成字符），
	# EventBackground TextureRect 保持 null，叠加 BackgroundColor 米色底保持宣纸视觉。
	# 多事件原图引入时（Step 4/5），按事件类型差异化是否显示原图（如 reflection 走 girl_enter
	# 时 EventBackground 仍 null 避免浅水面偏白；其他场景按设计开启）。
	event_background_rect.texture = null

	# 文字马赛克静态层:复用同一 Texture2D,按当前 location_id 选 tokens。
	# 角色创建阶段 _engine 可能尚未完全初始化 world_state,此处做 null 防御。
	# 未匹配的 location_id 落到 DEFAULT_TEXT_TOKENS,确保文字层始终有内容可渲染。
	text_mosaic_bg.set_source_image(texture)
	var location_id: String = ""
	if _engine != null:
		location_id = str(_engine.world_state.get("currentLocationId", ""))
	var raw_tokens: Array = LOCATION_TEXT_TOKENS.get(location_id, DEFAULT_TEXT_TOKENS)
	var tokens: PackedStringArray = PackedStringArray(raw_tokens)
	text_mosaic_bg.set_text_tokens(tokens)

	# 油画式多层叠加:核心区 coarse/medium 两层与 bg 共享源图+tokens,
	# 字号梯度由各节点 .tscn 属性配置(24 / 14 / 8)。
	# 仅 main_game 场景有 coarse/medium 节点,test 场景跳过。
	if text_mosaic_coarse != null:
		text_mosaic_coarse.set_source_image(texture)
		text_mosaic_coarse.set_text_tokens(tokens)
	if text_mosaic_medium != null:
		text_mosaic_medium.set_source_image(texture)
		text_mosaic_medium.set_text_tokens(tokens)
	if text_mosaic_dark_light != null:
		text_mosaic_dark_light.set_source_image(texture)
		text_mosaic_dark_light.set_text_tokens(tokens)
	if text_mosaic_dark_accent != null:
		text_mosaic_dark_accent.set_source_image(texture)
		text_mosaic_dark_accent.set_text_tokens(tokens)
	if text_mosaic_dark_deep != null:
		text_mosaic_dark_deep.set_source_image(texture)
		text_mosaic_dark_deep.set_text_tokens(tokens)
	if text_mosaic_dark_ink != null:
		text_mosaic_dark_ink.set_source_image(texture)
		text_mosaic_dark_ink.set_text_tokens(tokens)
	if text_mosaic_dark_between != null:
		text_mosaic_dark_between.set_source_image(texture)
		text_mosaic_dark_between.set_text_tokens(tokens)
	if text_mosaic_dark_abyss != null:
		text_mosaic_dark_abyss.set_source_image(texture)
		text_mosaic_dark_abyss.set_text_tokens(tokens)
	if text_mosaic_mid_dark != null:
		text_mosaic_mid_dark.set_source_image(texture)
		text_mosaic_mid_dark.set_text_tokens(tokens)
	if text_mosaic_mid_light != null:
		text_mosaic_mid_light.set_source_image(texture)
		text_mosaic_mid_light.set_text_tokens(tokens)
	if text_mosaic_highlight != null:
		text_mosaic_highlight.set_source_image(texture)
		text_mosaic_highlight.set_text_tokens(tokens)
	if text_mosaic_accent != null:
		text_mosaic_accent.set_source_image(texture)
		text_mosaic_accent.set_text_tokens(tokens)

	# 屏幕级 mosaic 衬底(油画式 3 层):粗 36px → 中 18px → 细 8px,字号梯度由 .tscn 配置。
	# 仅 main_game 场景有此节点,test 场景跳过。
	if screen_mosaic_coarse != null:
		screen_mosaic_coarse.set_source_image(texture)
		screen_mosaic_coarse.set_text_tokens(tokens)
	if screen_mosaic_medium != null:
		screen_mosaic_medium.set_source_image(texture)
		screen_mosaic_medium.set_text_tokens(tokens)
	if screen_mosaic_bg != null:
		screen_mosaic_bg.set_source_image(texture)
		screen_mosaic_bg.set_text_tokens(tokens)

	# 文字马赛克粒子层:加载与 art_file 同名的 flow_regions.json,驱动粒子在主体区域内流动。
	# JSON 不存在时清空粒子,粒子层渲染为空(不影响静态层)。
	text_mosaic_particles.set_source_image(texture)
	text_mosaic_particles.set_text_tokens(tokens)
	var flow_data: Dictionary = _load_flow_regions_for(normalized_path)
	if flow_data.is_empty():
		text_mosaic_particles.clear_flow_data()
		if text_mosaic_accent_marked != null:
			text_mosaic_accent_marked.set_source_image(null)
			text_mosaic_accent_marked.clear_accent_data()
	else:
		var regions: Array = flow_data.get("flow_regions", [])
		var img_size_arr: Array = flow_data.get("image_size", [0, 0])
		var img_size: Vector2 = Vector2(
			float(img_size_arr[0]), float(img_size_arr[1])
		)
		text_mosaic_particles.set_flow_data(regions, img_size)
		# 标注式点睛色层:从同一 flow_regions.json 读 accent_areas 字段(可选,缺省 = 无点睛)
		# accent_layers 的 mix_source > 0 时需要源图,这里同步注入(与 set_accent_data 顺序无关,
		# 但 set_source_image 在前更直观——先有源图,再有 area 数据)
		if text_mosaic_accent_marked != null:
			var accent_areas: Array = flow_data.get("accent_areas", [])
			text_mosaic_accent_marked.set_source_image(texture)
			text_mosaic_accent_marked.set_accent_data(accent_areas, img_size)
			text_mosaic_accent_marked.set_text_tokens(tokens)


# 功能:从背景图路径推导 flow_regions.json 路径并加载。
# 说明:约定 art_file 与 flow_regions.json 同目录、同 stem;
#       e.g. ".../town.svg" → ".../town.flow_regions.json"。
#       JSON 不存在或解析失败时返回空 Dictionary,粒子层会被清空。
func _load_flow_regions_for(art_path: String) -> Dictionary:
	var dir: String = art_path.get_base_dir()
	var stem: String = art_path.get_file().get_basename()
	var json_path: String = "%s/%s.flow_regions.json" % [dir, stem]
	if not FileAccess.file_exists(json_path):
		return {}
	var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		push_warning("flow_regions: 无法打开 %s" % json_path)
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("flow_regions: %s 解析失败或不是 Dictionary" % json_path)
		return {}
	return parsed


# 功能：根据运行平台决定 EventBackground 默认可见性。
# 说明：Web 端默认仅显示文字马赛克层（静态 + 粒子 + 米色宣纸底），不显示原图衬底——
#       文字马赛克独立扛起色调传递（M1' 色相敏感算法）。这层设计让 Web 端避开
#       大图 GPU 上传与每帧 sampling 的双重成本，同时强化"涌现式叙事——文字本身就是画面"的项目定位。
#       F9 可随时切回原图层进行视觉对比；编辑器 / 桌面端默认显示原图。
func _setup_platform_default_layers() -> void:
	if OS.has_feature("web"):
		event_background_rect.visible = false
		text_mosaic_bg.visible = true
		# 粒子飘落层 + accent_marked 点睛层已停用(决策点 7 收口 + 视觉简化决定)
		# 节点保留供未来重启,但默认 visible=false,F9 切层也不再覆盖
		text_mosaic_particles.visible = false
		# 多层叠加架构下,Web 默认显示所有 mosaic 层(显式设置便于与 F9 切换语义保持一致)
		if text_mosaic_coarse != null:
			text_mosaic_coarse.visible = true
		if text_mosaic_medium != null:
			text_mosaic_medium.visible = true
		if text_mosaic_dark_light != null:
			text_mosaic_dark_light.visible = true
		if text_mosaic_dark_accent != null:
			text_mosaic_dark_accent.visible = true
		if text_mosaic_dark_deep != null:
			text_mosaic_dark_deep.visible = true
		if text_mosaic_dark_ink != null:
			text_mosaic_dark_ink.visible = true
		if text_mosaic_dark_between != null:
			text_mosaic_dark_between.visible = true
		if text_mosaic_dark_abyss != null:
			text_mosaic_dark_abyss.visible = true
		if text_mosaic_mid_dark != null:
			text_mosaic_mid_dark.visible = true
		if text_mosaic_mid_light != null:
			text_mosaic_mid_light.visible = true
		if text_mosaic_highlight != null:
			text_mosaic_highlight.visible = true
		if text_mosaic_accent != null:
			text_mosaic_accent.visible = true
		# accent_marked 已停用(同上),Web 默认强制 false 防回潮
		if text_mosaic_accent_marked != null:
			text_mosaic_accent_marked.visible = false
		if screen_mosaic_coarse != null:
			screen_mosaic_coarse.visible = true
		if screen_mosaic_medium != null:
			screen_mosaic_medium.visible = true
		if screen_mosaic_bg != null:
			screen_mosaic_bg.visible = true


# 功能：F9 互斥切换"原图层"与"文字马赛克层(静态+粒子)"；F8 强制渲染周既明练武场背景。
# 说明：仅开发期使用；正式发布前可移除或限制为 OS.is_debug_build() 才生效。
#       粒子层属于 mosaic 体系，跟随 mosaic 静态层一起 toggle。
#       F8 用于在不改 CSV 事件配置的前提下验证 M1' 算法在真实暖色调美术上的视觉效果。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F9:
				var show_mosaic: bool = not text_mosaic_bg.visible
				text_mosaic_bg.visible = show_mosaic
				# 粒子飘落层 + accent_marked 点睛层已停用(决策点 7 收口 + 视觉简化决定)
				# F9 不再切换这两层,显式锁 false 防止某次 visible 被外部置 true 后回潮
				text_mosaic_particles.visible = false
				# 多层叠加架构下,F9 必须覆盖所有 mosaic 层,否则 A/B 对比时
				# coarse/medium/dark_accent + 屏幕衬底 3 层会残留可见
				if text_mosaic_coarse != null:
					text_mosaic_coarse.visible = show_mosaic
				if text_mosaic_medium != null:
					text_mosaic_medium.visible = show_mosaic
				if text_mosaic_dark_light != null:
					text_mosaic_dark_light.visible = show_mosaic
				if text_mosaic_dark_accent != null:
					text_mosaic_dark_accent.visible = show_mosaic
				if text_mosaic_dark_deep != null:
					text_mosaic_dark_deep.visible = show_mosaic
				if text_mosaic_dark_ink != null:
					text_mosaic_dark_ink.visible = show_mosaic
				if text_mosaic_dark_between != null:
					text_mosaic_dark_between.visible = show_mosaic
				if text_mosaic_dark_abyss != null:
					text_mosaic_dark_abyss.visible = show_mosaic
				if text_mosaic_mid_dark != null:
					text_mosaic_mid_dark.visible = show_mosaic
				if text_mosaic_mid_light != null:
					text_mosaic_mid_light.visible = show_mosaic
				if text_mosaic_highlight != null:
					text_mosaic_highlight.visible = show_mosaic
				if text_mosaic_accent != null:
					text_mosaic_accent.visible = show_mosaic
				# accent_marked 已停用,锁 false 防回潮
				if text_mosaic_accent_marked != null:
					text_mosaic_accent_marked.visible = false
				if screen_mosaic_coarse != null:
					screen_mosaic_coarse.visible = show_mosaic
				if screen_mosaic_medium != null:
					screen_mosaic_medium.visible = show_mosaic
				if screen_mosaic_bg != null:
					screen_mosaic_bg.visible = show_mosaic
				event_background_rect.visible = not show_mosaic
			KEY_F8:
				_force_render_zhou_training_ground()


# 功能：F8 调试键——强制把 EventBackground 切到周既明练武场背景，token 池切到周既明专池。
# 说明：临时改写 world_state.currentLocationId 让 _render_event_background 内部按地点取
#       loc_zhou_training_ground 池；下一次正常事件流会自然刷新该值，污染窗口仅当前一帧。
#       与 F9 配套使用——F8 切图源 + token，F9 切显示模式（原图 vs 马赛克）。
func _force_render_zhou_training_ground() -> void:
	if _engine != null and _engine.world_state is Dictionary:
		_engine.world_state["currentLocationId"] = ZHOU_TRAINING_GROUND_LOCATION
	_render_event_background(ZHOU_TRAINING_GROUND_PATH)
	_append_log("[F8] 强制渲染周既明练武场背景（loc_zhou_training_ground 池）")


# 功能：将历史事件数组转为字符串数组。
# 说明：统一处理 Variant 数组，确保可安全拼接为文本。
func _history_to_string_array(history: Array) -> Array[String]:
	var result: Array[String] = []
	for item in history:
		result.append(str(item))
	return result


# 功能：读取测试场景的配置文件。
# 说明：外层入口文件仅指定 dataset_dir；实际数据集配置在 <dataset_dir>/test_config.json 里。
#       合并顺序：以内层为基底，外层同名字段覆盖（便于临时调整 random_seed 等）。
#       dataset_dir 字段本身只用于定位内层文件，不传给下游 override 逻辑。
#       若外层没有 dataset_dir，则退回读取外层字段（兼容旧格式、缺失配置不阻断）。
func _load_test_config() -> Dictionary:
	var outer := _read_json_dict(TEST_CONFIG_PATH)
	var dataset_dir := str(outer.get("dataset_dir", "")).strip_edges()
	if dataset_dir.is_empty():
		return outer

	var inner_path := dataset_dir.path_join("test_config.json")
	var merged: Dictionary = _read_json_dict(inner_path)
	for key in outer.keys():
		if str(key) == "dataset_dir":
			continue
		merged[str(key)] = outer[key]
	return merged


# 功能：读取 JSON 文件并解析为 Dictionary。
# 说明：文件缺失、空内容、非 Dictionary 结构时统一返回空 Dictionary，便于调用方写短路判断。
func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or parsed == null:
		return {}
	return parsed


# 功能：读取测试场景的随机种子配置。
# 说明：当配置缺失、格式错误或不是非负整数时，回退为 0 以启用随机种子。
func _get_test_random_seed(test_config: Dictionary) -> int:
	var raw_seed: Variant = test_config.get("random_seed", 0)
	var seed_text := str(raw_seed).strip_edges()
	if seed_text.is_empty() or not seed_text.is_valid_int():
		return 0

	var seed := int(seed_text)
	if seed < 0:
		return 0
	return seed


# 功能：按测试配置加载世界事件 CSV 数据。
# 说明：CSV 目录选择交由测试配置显式控制，但实际加载、编译与缓存仍统一走 ConfigRuntime。
func _load_world_event_test_config(test_config: Dictionary) -> Dictionary:
	var runtime := ConfigRuntime.shared()
	var override_paths: Dictionary = {}
	var csv_dir := str(test_config.get("world_event_csv_dir", "")).strip_edges()
	if not csv_dir.is_empty():
		override_paths["world_event_csv_dir"] = csv_dir
	# 说明：量产测试数据集（如 intro_flow_test）自带人物/地点/关系配置，
	# 这里按 test_config.json 里显式指定的 key 逐项 override，未指定则回退全局默认。
	for override_key in ["roles", "location_graph", "affinity"]:
		var override_path := str(test_config.get(override_key, "")).strip_edges()
		if not override_path.is_empty():
			override_paths[override_key] = override_path

	var load_result := runtime.ensure_loaded(override_paths)
	if not load_result.get("ok", false):
		return load_result

	var world_event_data := runtime.get_world_event_data()
	if world_event_data.is_empty():
		return {"ok": false, "error": "world event config is empty in config runtime"}

	var context_result := runtime.build_context()
	var location_graph = null
	if context_result.get("ok", false):
		location_graph = context_result.get("graph", null)

	# 从 ConfigRuntime 获取玩家 RoleState，通过 load_from_data 统一注入。
	var p_role_state: Variant = null
	var roles: Array = runtime.get_roles()
	for role_variant in roles:
		if role_variant != null and role_variant.role_type == "player":
			p_role_state = role_variant
			break

	var data_result: Dictionary = _engine.load_from_data(world_event_data, location_graph, p_role_state)
	if not data_result.get("ok", false):
		return data_result
	# 补充加载开局选择配置（load_from_data 路径不经过 load_from_csv_dir，需手动触发）。
	var creation_csv_dir := str(test_config.get("world_event_csv_dir", "res://scripts/config/world_event_mvp")).strip_edges()
	_engine._load_creation_config(creation_csv_dir)
	return data_result
