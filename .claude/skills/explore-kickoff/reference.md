# Explore Kickoff Reference

详细参数与 7 问完整清单。skill 工作时按需引用。

## 项目特定参数

| 参数 | 值 |
|---|---|
| 设计 repo URL | https://github.com/lwbiuchsjk/vibe-test-design.git |
| 主 repo URL | https://github.com/lwbiuchsjk/vibeTest.git |
| 设计 repo 本地路径（PowerShell） | `D:\坚果云\vibe-test-design` |
| 设计 repo 本地路径（IDE / Edit / Write） | `e:/Godot/project/vibeTest/vibe-test/Design`（junction） |
| RemoteTrigger trigger_id | `trig_01SYCxLscNXXiYDYTGLt4Yw7` |
| trigger 名称（用于查找） | "夜间设计探索 — vibe-test" |
| environment_id | `env_018VNviUfvb3nmv2jLTTZAev` |
| cron expression | `0 18 * * *`（UTC 18:00 = 北京 02:00） |
| LLM model | `claude-sonnet-4-6` |
| 单轮预算 | 45 分钟硬上限 |
| WebSearch 上限 | 6 次 / 轮 |
| 模块锁死标签（默认） | `模块/前端表现`（其他主题需 `RemoteTrigger update` 改这个标签） |

---

## 7 问标准清单（详细版）

### 1. 主题（一句话目标）

格式："我想 [验证 / 调研 / 对照] [对象 / 路径] 是否 / 如何 [具体诉求]"

### 2. 动机

- 为什么现在做？
- 期望支持什么决策？
- 是 PoC 前的可行性验证，还是已实施后的优化方向？

### 3. 相关锚点

- 已知设计文档（用 `[[]]` 链接，例如 `[[事件展示阶段_MVP设计]]`）
- 项目代码路径（如 `scripts/systems/world_event_engine.gd`）
- 外部参考案例（URL）

### 4. 期望产出形态

- 推荐方案（含落地步骤）
- 对照表（A vs B vs C）
- spawned_questions（衍生子问题供下一轮）
- 视觉案例库（URL + 描述）
- 代码骨架

### 5. 边界

- 不做：美术资产 / 改主项目 `scripts/` / 切换主框架等
- 不评估：超出 MVP 范围的方向
- 时间约束：45 分钟单轮上限

### 6. 预算

- 轮数：3-5 轮典型，预留 1 轮中间梳理 + 1 轮最终收口
- 节奏：手动 run（不消耗 routine quota）vs cron（每天自动跑）
- 单次 Max 5h usage 消耗约 +5%（按 tile-adventure 实测）

### 7. 三连前置自检（强制）

#### a. 核心 vs 增强

- 核心成立条件：缺它方案不成立的最小集
- 可选增强：在核心成立基础上的提升
- 不要把"高级技术"误当核心

#### b. 平台原生能力

- 目标平台：Godot 4.5 + Web 导出（整个引擎在浏览器内 WebAssembly + WebGL）
- 默认评估：原生 `draw_string` / `RichTextLabel` / `Label` / shader 是否已覆盖？
- 警觉信号：如果方案默认走 HTML overlay / JS 库 / WebWorker，先问"为什么不能 Godot 内做"
- 参考案例如果锚定了特定技术栈（如 `chenglou/pretext` → JS 库），剥离参考案例后原始需求是否仍成立？

#### c. 职能定位（仅美术 / 视觉 / 表现层）

- 信息传达层（菜单 / 对话框 / 描述文字）：可读性优先
- 氛围 / 风格化层（背景 / 装饰 / 动效）：视觉表现力优先
- **默认不假设"文字必须可读"**——除非已确认它承担信息传达职能

---

## 监督期 4 项职责（来自 `feedback_explore_supervisor_responsibilities`）

每轮起 task 前在脑里跑一遍：

### 任务分层

- 当前任务属于核心层 / 增强层 / 中间梳理？
- 核心未验证前不起增强类 task

### 前提质疑

- task body 里 agent 会假设什么？
- 这些假设是用户实际要的，还是参考案例带进来的？

### 修正信号扫描

- 用户最近话语有 "等等" / "其实" / "重新" / "如果反过来"？
- 用户展示了视觉 / 截图（强烈"我意识到 X"信号）？
- 主动追问背后的设计直觉

### 阶段性收口

- 每 2-3 轮做一次中间梳理（不要拖到末尾）
- 中间梳理产出："已收敛 / 仍发散 / 是否回头修正前提 / 后续聚焦哪里"

---

## 失败处理

| 失败模式 | 处理 |
|---|---|
| `[FAIL-N]` commit | **不重试，立即停下来报告** |
| 单轮超时（45 分钟） | 读残留 STEP-2 产出，监督者手动综合（不再起 #N+1 重跑） |
| 期望产出过多导致超时 | 拆分 task：核心层一个 task + 综合一个 task |
| trigger_id 失效 | 调 `RemoteTrigger list` 查找名为"夜间设计探索 — vibe-test"的 trigger |
| WSL 中文路径不稳定 | 改用 PowerShell（Windows 原生处理中文）；Bash cd 中文路径在某些 sandbox 环境不可用 |

---

## 收口文档标准 pattern

参考 `[[前端表现层方向收口]]` 作为已落地的样板：

- frontmatter：`[类型/讨论, 模块/<相关模块>, 状态/草案]`
- 章节：调研全程 / 当前收口判断 / 仍待验证不确定点 / 已"放下"的方案 / 留作未来的价值 / 与 MVP 设计文档的关系 / 关键认知陷阱 / 下一步
- 关联：4 处（`_explore/queue.md` / `_explore/log/_INBOX.md` / `_MOC.md` / 反向链接）

---

## 上层规范

- `[[_explore系统_MVP设计]]`（设计 repo 内）：完整搭建步骤、prompt 全文（已含 STEP-0.5 前置自检）、冒烟测试
- `[[_explore/README]]`（设计 repo 内）：区域使用层规范、任务状态机定义
