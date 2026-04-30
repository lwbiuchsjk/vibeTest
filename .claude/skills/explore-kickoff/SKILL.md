---
name: explore-kickoff
description: 启动 _explore 调研任务的标准流程。当用户说"我想调研 / 想了解 / 想对照 X"或显式 /explore-kickoff 时调用，引导用户经过澄清需求 → task 草稿 → 入队启动 → 监督 → 收口五阶段。自动应用项目级认知陷阱 memory 做前置自检。
allowed-tools: Bash(git *) Edit Write Read Grep Glob
argument-hint: "[topic]"
effort: medium
---

# Explore Kickoff

启动 _explore 调研任务的标准流程。详细参数见 [references/parameters.md](references/parameters.md)，task body 标准模板见 [references/task_body.md](references/task_body.md)。

## 何时使用

- 用户说"我想调研 X" / "想了解 X 在 Y 中的可行性" / "想对照"
- 显式 `/explore-kickoff` 调用（可带 `[topic]` 参数）
- 计划起多轮 _explore 调研

## 何时不用

- 用户已有 task body 直接让你入队（这是 add-task 场景）
- 询问已落地系统的现状（这是 ask 场景）
- 实施 / coding 任务（这是 implement 场景）

---

## 标准 5 阶段

### 阶段 1：需求澄清（7 问标准清单）

**为什么需要这一步**：避免 task body 里的隐含假设（如"文字必须可读" / "必须用 X 技术栈"）渗入 agent 工作前提。这些假设一旦未在 task 起草时明确质疑，会被 agent 当作既定事实跑下去——本项目 5 轮 _explore 中错误前提一路滚到第 4 轮的根因，正是阶段 1 没做透。

逐项确认（用户可能一次回答多项）：

1. **主题**：调研主题是什么？一句话目标
2. **动机**：为什么调研？支持什么决策？
3. **相关锚点**：已知文档 / 代码 / 参考案例（`[[]]` 链接 + 项目代码路径）
4. **期望产出形态**：推荐 / 对照表 / 子问题 / 落地步骤
5. **边界**：不做什么？避免哪些方向？
6. **预算**：几轮调研？手动 run 还是 cron？预留 1 轮中间梳理 + 1 轮最终收口
7. **三连前置自检**（强制；自动应用已沉淀的 3 条认知陷阱 memory）：
   - **核心 vs 增强**：核心成立条件是什么？哪些是可选增强？（`feedback_core_vs_enhancement_priority`）
   - **平台原生能力**：Godot 4.5 + Web 导出原生能否覆盖核心？参考案例是否锚定了外部技术栈？（`feedback_native_platform_capability_first`）
   - **职能定位**（美术 / 表现层）：承担"信息传达"还是"氛围 / 风格化"？（`feedback_visual_atmosphere_over_readability`）

### 阶段 2：task 草稿

**为什么需要这一步**：把 7 问回答整合成 agent 可直接消费的 task body 格式，避免 agent 重新猜测意图。展示草稿让用户审稿，是落盘前最经济的修正机会——一旦入队 + run，agent 就按 task body 跑下去了。

按 [references/task_body.md](references/task_body.md) 标准格式起草，整合 7 问回答。在主消息里展示草稿，**不立即落盘**。

### 阶段 3：审稿 + 执行

**为什么需要这一步**：审稿 + 执行不是仪式，是不可逆动作前的最后 checkpoint。一旦 `RemoteTrigger.run` 启动 agent，CCR API 没有 stop / cancel action，agent 会跑完 45 分钟预算或失败为止——错过审稿就只能等结果。

用户确认草稿后：

1. Edit 设计 repo `_explore/queue.md` 的"待办"区
2. PowerShell 中执行：`Set-Location "D:\坚果云\vibe-test-design"; git add _explore/queue.md; git commit -m "explore: 入队 #XXX ..."; git push origin main`
3. 调用 `RemoteTrigger run trigger_id` 启动 agent
4. 启动后台 Bash 监控（fetch + 检测 [STEP-4] 或 [FAIL-N]，60s 轮询，45 分钟超时）

### 阶段 4：监督（多轮）

**为什么需要这一步**：agent 跟着 task body 跑，**不会自己质疑前提**——它的工作目标是完成"期望产出"清单，不是反思任务本身的合理性。监督者必须在轮间做 4 项主动职责，弥补 agent 的盲区；否则错误前提会跨多轮一路滚（本项目 #001-#004 走偏的根因）。

每轮通知到达后：

1. Read 最新 `INDEX_<NUM>.md` 和 _INBOX 行
2. 应用 `feedback_explore_supervisor_responsibilities` 的 4 项职责：
   - **任务分层**：本轮属于核心层 / 增强层 / 中间梳理？
   - **前提质疑**：agent 假设了什么？参考案例锚定了什么？
   - **修正信号扫描**：用户最近话语有"等等" / "其实" / "重新" 等信号？
   - **阶段性收口**：第 2-3 轮强制做"中间梳理"，不要拖到末尾
3. 必要时读项目代码（`scripts/` `test/`）+ 设计文档作为本地证据
4. 决策下一轮：起新 task / 中间梳理 / 收口
5. 给用户 3 行同步（含本轮 layer 标记），不等回复直接执行
6. 失败处理：`[FAIL-N]` 出现时**不重试，直接停下来报告**——重试很可能撞同样的 root cause，浪费 quota

### 阶段 5：收口

**为什么需要这一步**：多轮调研产出散落各份报告（本项目 5 轮 _explore 累计 ~110KB 报告 + 28 条 spawned_questions），需要综合成一份可执行决策。按 [[前端表现层方向收口]] pattern 落盘，便于未来回看 + 让后续 MVP 设计文档有明确引用对象（决策依据 / 战略层 vs 实施层 / 节点 API 的上下层分工）。

多轮综合后产出收口文档：

1. 收口文档落 `Design/<主题>方向收口.md`，frontmatter `[类型/讨论, 模块/<相关模块>, 状态/草案]`
2. 关联 4 处：
   - `_explore/queue.md`：超时 / 废弃 task 标记"已手动综合至 `[[<收口文档>]]`"（按 [[_explore/README]] 任务状态机规范）
   - `_explore/log/_INBOX.md`：追加一行综合标记
   - `_MOC.md`："讨论与思考"分区追加索引
   - 收口文档内 `[[]]` 反向链接所有调研报告
3. 设计 repo commit + push
4. 主 repo submodule 指针由用户自行更新（除非明确授权）

---

## 使用示例

### 示例 1：单轮调研启动

**用户**：我想调研 Godot RichTextLabel 在 Web 导出后的中文字体加载性能。

**Claude**（自动识别 explore-kickoff 触发）：

> 我用 explore-kickoff 流程帮你启动这个调研。先做需求澄清（7 问中关键的几条）：
>
> 1. **主题**：Godot RichTextLabel + Web 导出 + 中文字体加载性能 ← 确认
> 2. **动机**：是为了 PoC 前的可行性验证，还是已实施后发现性能问题？
> 3. **相关锚点**：已知设计文档 / 代码？是否与 [[文字马赛克美术背景_MVP设计]] 相关？
> 4-6. **期望产出 / 边界 / 预算**：……
> 7. **三连前置自检**：
>    - **核心 vs 增强**：核心是"中文字体能加载并稳定 60fps 渲染密集小字号"，还是更弱的"无加载阻塞"？字体子集化是核心还是增强？
>    - **平台原生**：Godot 4.5 RichTextLabel 已是原生方案，**无需引入 HTML overlay**——本调研是验证"原生能否覆盖"，不是"找替代技术栈"
>    - **职能定位**：这是"信息传达层"（描述文字必须可读）→ `feedback_visual_atmosphere_over_readability` 不适用，可读性是核心约束

[用户回答后，Claude 起草 task body 让用户审稿 → 入队 → RemoteTrigger.run → 后台监控]

---

### 示例 2：多轮调研中识别错误前提并修正

**背景**：用户已起 #002 调研某 JS 库可行性，Agent 给出"部分可行"判决，依据是"性能 OK 但叙事文字可读性矛盾"。

**用户**（反思后）：等等，我其实不需要这一层文字可读，它是氛围层。

**Claude**（识别"等等"是修正信号 → 应用 `feedback_design_lightbulb_moments`）：

> 你这个修正击中了 #002 的错误前提。Agent 假设了"文字必须可读"——这是被参考案例的展示形态锚定，不是你的真实需求。这正是 `feedback_visual_atmosphere_over_readability` 这条 memory 要预防的认知陷阱。
>
> 让我做修正动作：
>
> 1. 把 #002 task 标记"已废弃（方向修正）"（按 [[_explore/README]] 任务状态机的 `- [~]` 标记）
> 2. 起 #003 task body，明确"职能 = 氛围层，不要求可读"
> 3. #003 STEP-0.5 前置自检会强制 agent 重新评估"职能定位"，避免重蹈
> 4. 如果这是新的认知陷阱（已存 memory 未覆盖），存一条新 feedback memory

[Claude 执行修正 → 起 #003 → 用户审稿确认 → run]

---

## 已沉淀的认知陷阱（自动应用）

skill 在阶段 1 / 阶段 4 自动引用以下项目级 memory，避免已知陷阱：

| memory | 应用场景 |
|---|---|
| `feedback_core_vs_enhancement_priority` | 阶段 1 第 7 问 (a) / 阶段 4 任务分层 |
| `feedback_native_platform_capability_first` | 阶段 1 第 7 问 (b) / 阶段 4 前提质疑 |
| `feedback_visual_atmosphere_over_readability` | 阶段 1 第 7 问 (c)（仅美术 / 表现层） |
| `feedback_explore_supervisor_responsibilities` | 阶段 4 监督每轮 |
| `feedback_design_lightbulb_moments` | 阶段 4 修正信号扫描 |

---

## 项目特定参数（详见 [references/parameters.md](references/parameters.md)）

- RemoteTrigger trigger_id：`trig_01SYCxLscNXXiYDYTGLt4Yw7`
- 设计 repo URL：https://github.com/lwbiuchsjk/vibe-test-design.git
- 主 repo URL：https://github.com/lwbiuchsjk/vibeTest.git
- 上层规范：`[[_explore系统_MVP设计]]`（设计 repo 内）
- 任务状态机：`[[_explore/README]]`（设计 repo 内）
