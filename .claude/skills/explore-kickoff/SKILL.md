---
name: explore-kickoff
description: 启动 _explore 调研任务的标准流程。当用户说"我想调研 / 想了解 / 想对照 X"或显式 /explore-kickoff 时调用，引导用户经过澄清需求 → task 草稿 → 入队启动 → 监督 → 收口五阶段。自动应用项目级认知陷阱 memory 做前置自检。
allowed-tools: Bash(git *) Edit Write Read Grep Glob
argument-hint: "[topic]"
effort: medium
---

# Explore Kickoff

启动 _explore 调研任务的标准流程。详细参数见 [reference.md](reference.md)，task body 标准模板见 [templates/task_body.md](templates/task_body.md)。

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

按 [templates/task_body.md](templates/task_body.md) 标准格式起草，整合 7 问回答。在主消息里展示草稿，**不立即落盘**。

### 阶段 3：审稿 + 执行

用户确认草稿后：

1. Edit 设计 repo `_explore/queue.md` 的"待办"区
2. PowerShell 中执行：`Set-Location "D:\坚果云\vibe-test-design"; git add _explore/queue.md; git commit -m "explore: 入队 #XXX ..."; git push origin main`
3. 调用 `RemoteTrigger run trigger_id` 启动 agent
4. 启动后台 Bash 监控（fetch + 检测 [STEP-4] 或 [FAIL-N]，60s 轮询，45 分钟超时）

### 阶段 4：监督（多轮）

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
6. 失败处理：`[FAIL-N]` 出现时**不重试，直接停下来报告**

### 阶段 5：收口

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

## 项目特定参数（详见 [reference.md](reference.md)）

- RemoteTrigger trigger_id：`trig_01SYCxLscNXXiYDYTGLt4Yw7`
- 设计 repo URL：https://github.com/lwbiuchsjk/vibe-test-design.git
- 主 repo URL：https://github.com/lwbiuchsjk/vibeTest.git
- 上层规范：`[[_explore系统_MVP设计]]`（设计 repo 内）
- 任务状态机：`[[_explore/README]]`（设计 repo 内）
