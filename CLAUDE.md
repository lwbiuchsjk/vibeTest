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

### 文档删除与重命名规范

删除或重命名 `design_dir` 下的文档前，**必须先用 `backlinks` 检查引用关系**，避免产生断链。Obsidian 未运行时可用 Grep 搜索 `[[文档名]]` 作为备选（可能漏掉别名链接）。

1. 如果存在引用，先更新引用方文档，再执行删除或重命名。
2. 重命名文档优先使用 Obsidian CLI 的 `move` 命令，它会自动更新所有 `[[]]` 链接。

## CSV 配置流水线（Step 3）执行规范

- **批量文件并行处理**：事件卡数量超过 10 个时，从读取阶段就使用并行 Agent 分批处理，不要串行逐个读取。

# 当前进度

进度详情存放在 `design_dir` 的 `进度/` 子目录下，此处仅维护索引。

## 活跃

- [自我积累型_阶段2_拆解进度](Design/进度/自我积累型_阶段2_拆解进度.md) — Step 3 完成，待验证
- [填充事件批量生产_阶段2](Design/进度/填充事件批量生产_阶段2.md) — 34 个已生产，待审阅

## 已归档

- [自我积累型_阶段1_拆解进度](Design/进度/自我积累型_阶段1_拆解进度.md)
- [required_flag 条件类型实现](Design/进度/required_flag_条件类型实现.md)

## 进度维护规则

1. **详情在进度文档，索引在此处**：CLAUDE.md 中每条进度只保留一行链接 + 状态摘要（≤20 字）。具体阻塞项、关键文档列表、注意事项等写在 `design_dir` 的 `进度/` 下的对应文档中。
2. **更新时机**：会话中产生实质性进展（完成步骤、新增/解除阻塞、新建任务）时，更新对应进度文档并同步此处的状态摘要。纯讨论不触发更新。
3. **新建进度文档**：当出现新的可独立追踪的工作项（新阶段拆解、新功能开发、新批量生产任务）时，在 `design_dir` 的 `进度/` 下新建文档，并在此处「活跃」区添加索引行。
4. **归档**：任务完成后，将进度文档 frontmatter 中 `status` 改为 `已归档`，并将此处的索引行从「活跃」移至「已归档」。
5. **防膨胀**：「活跃」区条目控制在 10 条以内。如果接近上限，审视是否有可合并或已实际完成的条目。
