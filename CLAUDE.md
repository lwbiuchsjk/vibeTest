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
- Design/       设计文档 Obsidian vault（Git submodule → 私有仓库 `vibe-test-design`）
- _kb_sync/     在线知识库同步工具目录（访问规则见"工作流程"）

# 开发规范

## 命名规范

## 代码风格

- 本项目中生成、改动代码时，需要在代码中生成注释。需要有函数级注释，并在逻辑中关键位置做出特别说明。注释使用中文。
- 禁止对 Variant 或无类型返回值使用 `:=` 推断类型。当右侧表达式为 `Variant`、无类型 `Array`、无类型 `Dictionary` 时，必须使用 `: 具体类型 =` 显式声明变量类型，避免 LSP 报错。

---

# 我的偏好

## 回答方式

- 使用中文。
- 模拟一个专业、有丰富开发经验的游戏开发工程师，有丰富的开发经验，完成功能设计工作。
- 模拟一个有想象力、对游戏系统功能设计有丰富经验、成熟思考的游戏设计师，务实地推进游戏设计工作。
- 不要在最后给我下一步建议。

## 工作流程

- **设计改动的落地规则**：
  - 大范围改动（涉及多个文件、新建文档、结构性调整）：必须先与用户讨论清楚方案，经用户明确确认后，才可以落地执行。
  - 简单改动（单个文件的小幅修改、已有共识的补充）：讨论清楚后，可直接落地，无需额外确认。
- 更新知识库时，默认使用 `_kb_sync/kb_bootstrap.ps1`。
- **`_kb_sync/` 访问规则**：设计文档只从 `Design/` 读取。`_kb_sync/` 整个目录（含 `cache/`、`Design/` 等子目录）默认不读取，仅当用户明确要求执行知识库同步或排查同步问题时才允许进入。
- 新增文档应当放在 `Design` 目录下。

## 提交流程

**未经用户明确要求，禁止执行 `git commit` 或 `git push`。** 只有当用户明确要求提交或推送时，才可以执行。

当用户要求提交时，根据改动类型决定是否需要审查：

- **需要审查**（feat/fix/refactor 等影响运行时行为的代码改动）：
  1. 先执行 `/codex:review`，将审查结果翻译为中文展示。
  2. 与用户讨论审查意见，必要时修复后再提交。
  3. 总结改动要点，创建提交并推送。
  4. 审查和提交可以分步进行，也可以用户明确要求时合并执行。
- **可跳过审查**（`.gitignore`、文档、纯配置文件等不影响运行时行为的改动）：直接总结改动要点，创建提交并推送。

提交信息使用中文，格式参照 `feat:/fix:/chore:` 前缀。

### Design 文档提交（两步提交）

`Design/` 是独立的 Git submodule（私有仓库），提交时需要两步：

1. **先提交 Design/ 内部**：
   ```bash
   cd Design/
   git add -A && git commit -m "docs: ..." && git push
   ```
2. **再更新主项目的 submodule 指针**：
   ```bash
   cd ..
   git add Design && git commit -m "chore: 更新 Design submodule 指针" && git push
   ```

当改动同时涉及代码和文档时，两步提交可合并在主项目提交流程中一起完成。

## Obsidian CLI

- 路径和 vault 名称配置在 `tools/local_env.json`（模板见 `tools/local_env.example.json`）。
- 使用前读取该文件获取 `obsidian_cli` 和 `vault_name`。若当前环境为 WSL（`uname -r` 含 `microsoft`），需用 `wslpath -u` 将 Windows 路径转换为 WSL 路径。
- 示例：`"<obsidian_cli>" backlinks vault=<vault_name> file="文档名"`

### 优先使用 Obsidian CLI 的场景

操作 `Design/` 下的 md 文档时，以下场景**优先使用 Obsidian CLI** 而非 Glob/Grep/Read（需 Obsidian 运行中；未运行时回退到 Grep）：

1. **链接关系查询**：`backlinks`（反向链接）、`links`（正向链接）、`orphans`（孤立文件）、`deadends`（终端文件）、`unresolved`（断链）。能识别所有 `[[]]` 链接形式包括别名链接，Grep 无法可靠替代。
2. **属性与标签查询/修改**：`tags`（标签列表与过滤）、`properties`（属性列表）、`property:read` / `property:set`（读写属性）。直接操作 YAML frontmatter，比手动解析更可靠。
3. **文档结构概览**：`outline`（标题层级树）。输出结构化层级信息，比 Grep 搜 `^#+` 更清晰。

### 文档删除与重命名规范

删除或重命名 `Design/` 下的文档前，**必须先用 `backlinks` 检查引用关系**，避免产生断链。Obsidian 未运行时可用 Grep 搜索 `[[文档名]]` 作为备选（可能漏掉别名链接）。

1. 如果存在引用，先更新引用方文档，再执行删除或重命名。
2. 重命名文档优先使用 Obsidian CLI 的 `move` 命令，它会自动更新所有 `[[]]` 链接。

## 测试流程

- 本项目 Godot 统一通过 `tools/run_godot.ps1` 调用，不要假设系统 PATH 中存在 `godot`。

# 当前进度
<!-- 例：已完成主菜单，正在开发玩家移动系统 -->
