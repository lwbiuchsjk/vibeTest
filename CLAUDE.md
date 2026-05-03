# 项目说明

## 项目概述
- 这是一款游戏demo，需要基于最小原型来推进。对于有价值有潜力的功能，需要明确提出，并记录下来，以供扩展。
- 这是一款涌现式剧情推进游戏，致力于用系统创造剧情。

## 技术栈
Godot 4.5，GDScript，Git 版本控制

## 项目结构

- scripts/      脚本文件
- assets/       资源文件（图片、音效等）
- test/         测试文件
- Design/       设计文档目录（路径由 `design_dir` 指定，Git submodule → 私有仓库 `vibe-test-design`）
- _kb_sync/     在线知识库同步工具目录（访问规则见共享 CLAUDE.md）

## 路径指定

- 项目环境配置集中在 `tools/local_env.json`（模板见 `tools/local_env.example.json`）。
- 共享 CLAUDE.md 中的"设计文档目录"对应本项目 `design_dir` 字段指定的路径。
- 新增文档应当放在 `design_dir` 指定的目录下。

## Obsidian CLI

- 路径和 vault 名称配置在 `tools/local_env.json`（模板见 `tools/local_env.example.json`）。
- 使用前读取该文件获取 `obsidian_cli` 和 `vault_name`。若当前环境为 WSL（`uname -r` 含 `microsoft`），需用 `wslpath -u` 将 Windows 路径转换为 WSL 路径。
- 示例：`"<obsidian_cli>" backlinks vault=<vault_name> file="文档名"`

### 优先使用 Obsidian CLI 的场景

操作 `design_dir` 下的 md 文档时，以下场景**优先使用 Obsidian CLI** 而非 Glob/Grep/Read（需 Obsidian 运行中；未运行时回退到 Grep）：

1. **链接关系查询**：`backlinks`（反向链接）、`links`（正向链接）、`orphans`（孤立文件）、`deadends`（终端文件）、`unresolved`（断链）。能识别所有 `[[]]` 链接形式包括别名链接，Grep 无法可靠替代。
2. **属性与标签查询/修改**：`tags`（标签列表与过滤）、`properties`（属性列表）、`property:read` / `property:set`（读写属性）。直接操作 YAML frontmatter，比手动解析更可靠。
3. **文档结构概览**：`outline`（标题层级树）。输出结构化层级信息，比 Grep 搜 `^#+` 更清晰。

### Design 目录文档操作规范

- **查询文档**时，优先读取 `_MOC.md` 定位目标，不直接 Glob 扫描根目录。
- **新增文档**后，必须在 `_MOC.md` 对应分区添加索引行。
- **删除或重命名文档**后，同步更新 `_MOC.md`（删除条目 / 修改链接）。
- 文档从根目录**移入子目录**时，更新 `_MOC.md` 中的分区说明。
- **`状态/已归档` 文件非必要不读取** —— 归档文件不进 `_MOC.md`，仅在被索引关系唤起时访问（如某文档明确引用归档文件以追溯历史）；正常会话不主动查阅。归档文件应在 frontmatter 标 `状态/已归档` + 文件开头加显眼归档注释（说明何时应当查询）。

### 文档删除与重命名规范

删除或重命名 `design_dir` 下的文档前，**必须先用 `backlinks` 检查引用关系**，避免产生断链。Obsidian 未运行时可用 Grep 搜索 `[[文档名]]` 作为备选（可能漏掉别名链接）。

1. 如果存在引用，先更新引用方文档，再执行删除或重命名。
2. 重命名文档优先使用 Obsidian CLI 的 `move` 命令，它会自动更新所有 `[[]]` 链接。

### 新增设计文档规范

在 `design_dir` 下新增设计文档后，必须检查并更新相关文档的双向链接（使用 Obsidian CLI `backlinks` 辅助定位）。至少覆盖：

1. 上游设计文档（被扩展的系统）
2. 配置翻译指南（如涉及 CSV 字段变更）
3. 活跃进度文档

**frontmatter 必填**：新建 `.md` 必须按 [[标签体系]] 填写 YAML frontmatter。格式 `tags: [类型/xxx, 模块/xxx, 状态/xxx]`，其中**类型和状态各一个**、**模块可多个**，所有值必须在 `标签体系.md` 白名单内。文档状态变化（草案→MVP→已落地→已归档）时同步更新 `状态/` 标签。

### 新引擎功能验证规范

新增或修改引擎功能后，在批量配置前，先用该功能的**首批用例**逐项检查功能覆盖度，确认是否存在超出当前实现能力的变体。

## CSV 配置流水线（Step 3）执行规范

- **批量文件并行处理**：事件卡数量超过 10 个时，从读取阶段就使用并行 Agent 分批处理，不要串行逐个读取。
- **双轨工作流**：Step 3 使用脚本（`tools/csv_translator.py`）自动生成 + LLM 人工补全两条轨道并行：
  1. 脚本产出 5 张表（events, event_conditions, event_presentations, options, option_rules），仅处理含 `base_weight` frontmatter 的新格式事件卡。
  2. LLM 负责脚本不覆盖的部分：event_outcomes.csv、tasks.csv，以及需要人工判断的特殊情况（链式事件、非标效果等）。
  3. 新批次事件卡首次使用时，脚本与 LLM 分别独立翻译，**比较产出差异**以验证脚本可靠性。验证通过后，后续批次可信任脚本产出。
- **脚本维护规则**：当设计模板、引擎功能或 CSV 表结构发生变化时，需检查以下脚本是否覆盖对应变动，必要时同步更新：
  - `tools/csv_translator.py`（CSV 生成）
  - `tools/csv_validator.py`（CSV 静态检查，硬编码常量来源见脚本头部声明）

### CSV 契约三件套

CSV 配置流水线由以下三者互为契约，任一改动必须触发另两者的回看。忽视同步将导致脚本产出、静态校验、引擎消费三端失调（根因复盘：曾出现 `target=params` 误路由 affinity/player 效果且未被任何一环拦截的事故）。

1. **设计契约**：`Design/配置翻译指南.md` —— 真源。关键章节由 `<!-- CSV_CONTRACT_ANCHOR: xxx -->` 标记，锚点丢失会被 pre-commit 阻断（`tools/check_csv_contract_docs.py`）。当前锚点：`resolution_target_routing` / `rule_types` / `condition_types`。
2. **自动翻译**：`tools/csv_translator.py::parse_effect_expression` —— 按契约产出 target/op/key/value。
3. **静态校验**：`tools/csv_validator.py` —— 按契约校验 CSV。pre-commit 自动对本次提交涉及的配置目录（含 `events.csv`）执行。

**引擎侧触发源**：以下代码位置属于契约边界（查找 `【CSV 契约边界】` 注释锚点），改动时必须同步回看三件套：

- `scripts/systems/world_event_config_assembler.gd::_apply_effect_or_resolution_action`（target 路由分支）
- 引擎新增/删除的 `rule_type` / `condition_type` 行为分支
- 资源 key 集合（`RESOURCE_KEYS`）、affinity value 格式

**我（Claude）的操作守则**：接到"改引擎效果/路由/规则类型"的任务时，完成代码改动后必须主动走一遍三件套回看清单，逐项确认是否需要同步改动，再向用户汇报。不要等 pre-commit 报错才想起来。

## 忽略文件

- `.claude/settings.local.json` 的改动由用户自行管理，Claude 不主动提交。

## CSV 配置静态检查规范

- **鉴定选项必配 fail 分支**：`option_rules.csv` 中所有带 `rule_type=check` 的选项必须有对应的 `resolution,fail` 行。引擎 `_resolve_check_resolution()` 在无 `onFailResolution` 时 fallback 到 default 分支，导致鉴定失败与成功效果相同。fail 分支设计规则：
  - 有 affinity 效果的选项：fail 保留 affinity 效果，移除技能收益
  - 纯技能收益的选项：fail 给 `key,0`（无奖励）
- **自动化检查**：`tools/csv_validator.py` 覆盖以下检查项（Step 4 静态检查阶段运行）：
  1. fail 分支缺失：有 check 的选项必须有 resolution,fail 行
  2. 跨表 FK 一致性：option_rules → options → events，从表 → events
  3. key 合法性：cost/resolution key 对照 attribute_names.csv + 已知资源
  4. rule_type / condition_type 合法性
  5. cost value 正负号
  6. 任务保底完整性：`tasks.csv` 中 `on_expire=fail` 的任务，必须在 `task_eval_effects.csv` 中有对应的 `status=failed` 效果行

## 提交兜底（pre-commit hook）

本地 `.git/hooks/pre-commit` 会在每次提交前运行 `tools/fix_csv_imports.py`（CSV 导入格式检查）和 `tools/check_design_submodule.py`（Design submodule 模式检查），任一失败即阻断提交。背景、触发场景、手动修正方法、新环境启用步骤见 [[工程开发积累]] 第 6 条。

### Python 命令兼容（Windows + WSL）

Windows 11 下 `python3` 默认指向 Microsoft Store app execution alias（`C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\python3.exe`），调用返回 `Permission denied`；真实 Python 装在 `python`（无 3 后缀）路径下。WSL 下则相反——`python` 不存在，只有 `python3`。

两个 pre-commit hook（主项目 + Design submodule）采用**统一探测** pattern，同时兼容两环境：

```sh
PYTHON=$(command -v python 2>/dev/null || command -v python3 2>/dev/null)
if [ -z "$PYTHON" ]; then
    echo "[pre-commit] 未找到 python 或 python3" >&2
    exit 1
fi
# ... 后续 hook 内的 Python 调用全部用 "$PYTHON"
PYTHONUTF8=1 "$PYTHON" path/to/script.py
```

优先探测 `python`——Windows 下真 Python 就在这里；WSL 下探测失败自动 fallback 到 `python3`。`PYTHONUTF8=1` 环境变量始终保留（Windows 默认 console 编码是 GBK，print 中文会触发 `UnicodeEncodeError`）。

Design hook 中处理含中文的 junction 路径（`$ROOT` 解析到 `D:\坚果云\vibe-test-design`）仍用 `cd "$ROOT" && ...` 避免 bash 变量插值问题。

这些 hook 改动只在 `.git/hooks/` 本地生效，**不入 repo**；跨机器克隆后需手动重建 hook（模板在本节和[[工程开发积累]]第 6 条）。

# 当前进度

进度详情存放在 `design_dir` 的 `进度/` 子目录下，此处仅维护索引。

## 活跃

- [自我积累型_阶段2_拆解进度](Design/进度/自我积累型_阶段2_拆解进度.md) — Step 4 进行中，冒烟/静态检查通过
- [叙事声部迁移_第二人称重写进度](Design/进度/叙事声部迁移_第二人称重写进度.md) — 4 骨架 + 34 填充全部落盘，待 CSV 回写
- [叙事重写_Kimi接入与审校方案_讨论进度](Design/进度/叙事重写_Kimi接入与审校方案_讨论进度.md) — Z 方案 3 事件测试完成，待封装 kimi_rewrite.py
- [文字马赛克美术背景_落地进度](Design/进度/文字马赛克美术背景_落地进度.md) — 决策点 6 激进版 12 层素描式收口，素描感作最终风格
- [阶段3事件设计_预启动](Design/进度/阶段3事件设计_预启动.md) — **预启动**：6 线精调完成后的事件卡颗粒度撰写，当前可启动
- [intro_全盘重新设计_预启动](Design/进度/intro_全盘重新设计_预启动.md) — **预启动**：林秋禾 E 池塘开场触发的 intro 整体重做，当前可启动
- [阶段4与结局统一设计_预启动](Design/进度/阶段4与结局统一设计_预启动.md) — **预启动**：阶段 4 + 双结局合并设计，待阶段 3 推进到 60-80% 触发
- [阶段2回看调整_由阶段3触发_预启动](Design/进度/阶段2回看调整_由阶段3触发_预启动.md) — **预启动**：阶段 3 设计中浮现的阶段 2 回写需求触发，触发型

## 已归档

- [自我积累型_阶段1_拆解进度](Design/进度/自我积累型_阶段1_拆解进度.md)
- [required_flag 条件类型实现](Design/进度/required_flag_条件类型实现.md)
- [角色精调_新会话启动指南](Design/进度/角色精调_新会话启动指南.md) — 2026-05-04 归档；6 角色线精调全部完成
- [叙事包扩展与demo压缩_讨论进度](Design/进度/叙事包扩展与demo压缩_讨论进度.md) — 2026-05-04 归档；6 角色线收口
- [填充事件批量生产_阶段2](Design/进度/填充事件批量生产_阶段2.md) — 2026-05-04 归档；34 个已生产 + CSV 验证
- [intro_flow_test_叙事包改造进度](Design/进度/intro_flow_test_叙事包改造进度.md) — 2026-05-04 归档；A-E 完成，被 [intro_全盘重新设计_预启动] 取代

## 进度维护规则

1. **详情在进度文档，索引在此处**：CLAUDE.md 中每条进度只保留一行链接 + 状态摘要（≤20 字）。具体阻塞项、关键文档列表、注意事项等写在 `design_dir` 的 `进度/` 下的对应文档中。
2. **更新时机**：会话中产生实质性进展（完成步骤、新增/解除阻塞、新建任务）时，更新对应进度文档并同步此处的状态摘要。纯讨论不触发更新。
3. **新建进度文档**：当出现新的可独立追踪的工作项（新阶段拆解、新功能开发、新批量生产任务）时，在 `design_dir` 的 `进度/` 下新建文档，并在此处「活跃」区添加索引行。
4. **归档**：任务完成后，需满足以下条件才可归档：
   - 对应设计文档中的冒烟测试流程已执行且通过。
   - 将进度文档 frontmatter 中 `status` 改为 `已归档`，并将此处的索引行从「活跃」移至「已归档」。
5. **防膨胀**：「活跃」区条目控制在 10 条以内。如果接近上限，审视是否有可合并或已实际完成的条目。
