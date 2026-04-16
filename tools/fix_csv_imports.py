#!/usr/bin/env python3
"""
CSV 导入文件修正脚本

功能：扫描项目中所有 .csv.import 文件，将 Godot 默认生成的 csv_translation
     导入器改为 keep，防止生成无用的 .translation 产物。同时清理残留的
     .translation 文件。

用法：
  python tools/fix_csv_imports.py              # 检查模式（仅报告）
  python tools/fix_csv_imports.py --fix        # 修正模式（执行修改）

退出码：
  0 — 无需修正
  1 — 存在需修正的文件（检查模式），或修正过程出错
"""

import argparse
import sys
from pathlib import Path

# 项目根目录（脚本位于 tools/ 下）
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# 正确的 .csv.import 内容
KEEP_CONTENT = '[remap]\n\nimporter="keep"\n'


def find_csv_imports() -> list[Path]:
    """搜索项目中所有 .csv.import 文件（排除 .godot 目录）。"""
    return sorted(
        p for p in PROJECT_ROOT.rglob("*.csv.import")
        if ".godot" not in p.parts
    )


def find_stale_translations() -> list[Path]:
    """搜索项目中残留的 .translation 文件（排除 .godot 目录）。"""
    return sorted(
        p for p in PROJECT_ROOT.rglob("*.translation")
        if ".godot" not in p.parts
    )


def needs_fix(path: Path) -> bool:
    """判断 .csv.import 是否使用了 csv_translation 导入器。"""
    try:
        text = path.read_text(encoding="utf-8")
        return "csv_translation" in text
    except Exception:
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="修正 CSV 导入文件，阻止 Godot 生成 .translation 产物")
    parser.add_argument("--fix", action="store_true", help="执行修正（默认仅检查）")
    args = parser.parse_args()

    # 阶段 1：检查 .csv.import 文件
    imports = find_csv_imports()
    bad_imports = [p for p in imports if needs_fix(p)]

    # 阶段 2：检查残留 .translation 文件
    stale = find_stale_translations()

    # 报告
    if not bad_imports and not stale:
        print(f"✓ 全部 {len(imports)} 个 .csv.import 均为 keep，无残留 .translation 文件")
        return 0

    if bad_imports:
        print(f"✗ {len(bad_imports)} 个 .csv.import 使用了 csv_translation：")
        for p in bad_imports:
            print(f"  {p.relative_to(PROJECT_ROOT)}")

    if stale:
        print(f"✗ {len(stale)} 个残留 .translation 文件：")
        for p in stale:
            print(f"  {p.relative_to(PROJECT_ROOT)}")

    if not args.fix:
        print("\n使用 --fix 执行自动修正")
        return 1

    # 执行修正
    fixed = 0
    deleted = 0

    for p in bad_imports:
        try:
            p.write_text(KEEP_CONTENT, encoding="utf-8")
            fixed += 1
            print(f"  已修正: {p.relative_to(PROJECT_ROOT)}")
        except Exception as e:
            print(f"  失败: {p.relative_to(PROJECT_ROOT)} — {e}", file=sys.stderr)

    for p in stale:
        try:
            p.unlink()
            deleted += 1
            print(f"  已删除: {p.relative_to(PROJECT_ROOT)}")
        except Exception as e:
            print(f"  失败: {p.relative_to(PROJECT_ROOT)} — {e}", file=sys.stderr)

    print(f"\n完成：修正 {fixed} 个 .csv.import，删除 {deleted} 个 .translation 文件")
    return 0 if (fixed == len(bad_imports) and deleted == len(stale)) else 1


if __name__ == "__main__":
    sys.exit(main())
