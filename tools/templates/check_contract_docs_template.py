#!/usr/bin/env python3
"""
契约文档完整性检查（通用模板）。

与《工程开发积累》第 7 条"规范-工具-消费三端契约同步防御"配套使用。

适用场景：项目中存在"规范文档 + 自动化工具 + 消费端"三端链条，
例如 CSV 翻译流水线、proto/OpenAPI 代码生成、i18n 文案表、DB schema/ORM。
通过 pre-commit 阻断"误删规范文档"或"误删关键契约章节"的提交，
保证三端的同步基准不消失。

使用步骤：
  1. 复制本文件到项目的 tools/ 下并改名（如 check_xxx_contract_docs.py）
  2. 修改下方 CONTRACT_DOC / REQUIRED_ANCHORS 常量
  3. 在规范文档的关键契约段落埋 HTML 注释锚点：
       <!-- CONTRACT_ANCHOR: {锚点名} -->
       ...契约内容...
       <!-- CONTRACT_ANCHOR_END: {锚点名} -->
  4. 挂到项目的 .git/hooks/pre-commit：
       python3 "$ROOT/tools/check_xxx_contract_docs.py" || exit 1
  5. 建议在项目 CLAUDE.md 增加"契约三件套"规则段，声明代码侧回看约定

退出码：0 通过；1 失败。
"""

from __future__ import annotations

import sys
from pathlib import Path


# ============================================================
# 项目配置（使用本模板时请改这两项）
# ============================================================

# 契约真源文档路径（相对仓库根）
CONTRACT_DOC = "docs/your_contract.md"  # TODO: 改为项目实际路径

# 必须存在的契约锚点名（成对检查 START + END）
REQUIRED_ANCHORS: list[str] = [
    # TODO: 列出项目实际锚点名
    # "example_anchor_name",
]

# 锚点标签前缀（一般不需要改。保持全项目统一，避免不同脚本用不同约定）
ANCHOR_PREFIX = "CONTRACT_ANCHOR"


# ============================================================
# 通用实现（一般不需要改）
# ============================================================

def find_repo_root() -> Path:
    """返回仓库根目录（含 .git 的最近父目录）。"""
    here = Path(__file__).resolve().parent
    for p in [here, *here.parents]:
        if (p / ".git").exists():
            return p
    return here.parent


def main() -> int:
    if not REQUIRED_ANCHORS:
        print(
            "[契约检查] 跳过：REQUIRED_ANCHORS 为空，请先在脚本顶部填写项目锚点名",
            file=sys.stderr,
        )
        return 1

    root = find_repo_root()
    doc_path = root / CONTRACT_DOC

    # 1. 文件存在性
    if not doc_path.exists():
        print(f"[契约检查] 失败：契约真源文档缺失：{CONTRACT_DOC}", file=sys.stderr)
        print(
            "  此文档是三端契约（规范/工具/消费）的同步基准，"
            "删除会使下游脚本与消费端失去对齐依据。",
            file=sys.stderr,
        )
        print("  若确需删除，请先与项目负责人确认并迁移契约到新位置。", file=sys.stderr)
        return 1

    text = doc_path.read_text(encoding="utf-8")

    # 2. 锚点完整性
    missing: list[str] = []
    for anchor in REQUIRED_ANCHORS:
        start_tag = f"<!-- {ANCHOR_PREFIX}: {anchor} -->"
        end_tag = f"<!-- {ANCHOR_PREFIX}_END: {anchor} -->"
        if start_tag not in text or end_tag not in text:
            missing.append(anchor)

    if missing:
        print(
            f"[契约检查] 失败：{CONTRACT_DOC} 中以下契约锚点缺失或不完整：",
            file=sys.stderr,
        )
        for anchor in missing:
            print(
                f"  - {anchor}："
                f"需要 `<!-- {ANCHOR_PREFIX}: {anchor} -->` 与 "
                f"`<!-- {ANCHOR_PREFIX}_END: {anchor} -->` 配对",
                file=sys.stderr,
            )
        print(
            "  锚点标记的段落是契约真源的关键章节，误删会破坏"
            "三端（规范/工具/消费）的同步契约。",
            file=sys.stderr,
        )
        return 1

    print(
        f"[契约检查] 通过（文档齐全，{len(REQUIRED_ANCHORS)} 个锚点对完整）"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
