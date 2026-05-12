# -*- coding: utf-8 -*-
"""
一次性迁移脚本：把叙事 text 字段中的 CSV 真换行替换为字面 \n 两字符。

背景：event_presentations.csv / option_outcomes.csv / transition_text_pool.csv 等叙事文本
CSV 中曾混用「字段内真换行（quoted multi-line cell）」与「字面 \n 两字符」两种换行表达。
字面 \n 在 CSV 中是单行表达，编辑器/diff/grep 友好；真换行触发 quoted multi-line cell，
在非 CSV-aware 工具下显示为"伪行"。

统一方向：字面 \n 为正典；引擎装配层统一做 text.replace("\\n", "\n") 转义。

本脚本扫描指定 CSV 的 text 字段，把真换行（\n、\r\n、\r）替换为字面两字符 \n。
跑一次后即可删除。
"""

from __future__ import annotations

import csv
import io
import os
import sys
from typing import List, Dict


CONFIG_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "scripts",
    "config",
    "world_event_mvp",
)


# 要处理的 CSV 文件及其 text 字段名
TARGETS: List[Dict[str, str]] = [
    {"file": "event_presentations.csv", "text_field": "text"},
    {"file": "option_outcomes.csv", "text_field": "text"},
    {"file": "transition_text_pool.csv", "text_field": "text"},
]


def migrate_csv(path: str, text_field: str) -> int:
    """读取 CSV、迁移 text 字段中的真换行为字面 \n、写回。返回迁移的行数。"""
    if not os.path.exists(path):
        print(f"[SKIP] {path} 不存在")
        return 0

    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        if not fieldnames or text_field not in fieldnames:
            print(f"[SKIP] {path}: 无 {text_field} 字段")
            return 0
        rows = list(reader)

    migrated = 0
    for row in rows:
        original = row.get(text_field, "")
        # 把所有真换行（含 \r\n、\r、\n）替换为字面 \n（两字符 \ + n）
        if "\n" in original or "\r" in original:
            new_text = original.replace("\r\n", "\\n").replace("\r", "\\n").replace("\n", "\\n")
            row[text_field] = new_text
            migrated += 1

    if migrated == 0:
        print(f"[OK ] {path}: 0 行迁移（无真换行）")
        return 0

    # 写回 CSV。使用 \n 作为行终止符（Unix LF），与项目 .gitattributes 一致。
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(buf.getvalue())

    print(f"[FIX] {path}: 迁移 {migrated} 行")
    return migrated


def main() -> int:
    total = 0
    for entry in TARGETS:
        path = os.path.join(CONFIG_DIR, entry["file"])
        total += migrate_csv(path, entry["text_field"])
    print(f"\n总计迁移 {total} 行。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
