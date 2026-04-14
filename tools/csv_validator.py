#!/usr/bin/env python3
"""
CSV 配置静态检查脚本

功能：对事件引擎 CSV 配置（常规阶段 6 表）进行自动化静态检查，报告结构性问题。

用法：
  python tools/csv_validator.py --dir test/config/intro_flow_test
  python tools/csv_validator.py --dir test/config/intro_flow_test --ref-dir scripts/config
"""

import argparse
import csv
import re
import sys
from pathlib import Path


# ============================================================
# 知识来源声明
# ============================================================
# 本脚本的检查逻辑依赖以下引擎知识。
# 引擎功能变更时需同步检查本脚本（见 CLAUDE.md 脚本维护规则）。
#
# 【运行时读取】（引擎侧改了 CSV，本脚本自动生效）
#   - {ref_dir}/attribute_names.csv — 合法属性 key 集合
#
# 【硬编码常量】（引擎侧改了代码，需人工同步本脚本）
#   - RESOURCE_KEYS
#     来源: scripts/systems/world_event_engine.gd（资源消耗/恢复的 key）
#   - KNOWN_RULE_TYPES
#     来源: scripts/systems/world_event_config_assembler.gd（option_rules 行类型）
#   - KNOWN_CONDITION_TYPES
#     来源: scripts/systems/world_event_config_assembler.gd（event_conditions 行类型）
#   - AFFINITY_KEY_PATTERN
#     来源: scripts/systems/rule_engine.gd（关系效果 key 格式）
# ============================================================

# 资源 key（引擎硬编码，不在 attribute_names.csv 中）
RESOURCE_KEYS = {"energy", "spirit"}

# option_rules 的合法 rule_type
KNOWN_RULE_TYPES = {
    "visibility", "eligibility", "cost",
    "check", "resolution", "preemptive_bet",
}

# event_conditions 的合法 condition_type
KNOWN_CONDITION_TYPES = {
    "required_flag", "weight_rule",
    "required_npc", "required_location", "required_location_flag",
}

# 关系效果 key 的正则（affinity.player_001->npc_xxx）
AFFINITY_KEY_RE = re.compile(r"^affinity\.\w+->\w+$")


# ============================================================
# 工具函数
# ============================================================

def load_csv(path: Path) -> list[dict[str, str]]:
    """读取 CSV 为字典列表。文件不存在时返回空列表并打印提示。"""
    if not path.exists():
        print(f"  [跳过] 文件不存在: {path.name}")
        return []
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_attribute_keys(ref_dir: Path) -> set[str]:
    """从 attribute_names.csv 读取合法属性 key。"""
    path = ref_dir / "attribute_names.csv"
    if not path.exists():
        return set()
    rows = load_csv(path)
    keys: set[str] = set()
    for row in rows:
        key = row.get("internal_key", "").strip()
        if key:
            keys.add(key)
    return keys


def is_valid_effect_key(key: str, attribute_keys: set[str]) -> bool:
    """检查效果 key 是否属于已知集合。"""
    if key in attribute_keys:
        return True
    if key in RESOURCE_KEYS:
        return True
    if AFFINITY_KEY_RE.match(key):
        return True
    return False


# ============================================================
# 检查结果
# ============================================================

class ValidationResult:
    """收集检查结果并输出报告。"""

    def __init__(self) -> None:
        self.p1: list[str] = []
        self.p2: list[str] = []
        self.stats: dict[str, int] = {}

    def add_p1(self, msg: str) -> None:
        self.p1.append(msg)

    def add_p2(self, msg: str) -> None:
        self.p2.append(msg)

    def print_report(self) -> None:
        if self.p1:
            print("\n=== P1（必须修复） ===")
            for msg in self.p1:
                print(f"  {msg}")
        if self.p2:
            print("\n=== P2（建议检查） ===")
            for msg in self.p2:
                print(f"  {msg}")

        parts = [f"{len(self.p1)} P1", f"{len(self.p2)} P2"]
        stats_items = " / ".join(f"{k}: {v}" for k, v in sorted(self.stats.items()))
        status = "通过" if not self.p1 else "有问题"
        print(f"\n=== 检查完成: {', '.join(parts)} | {stats_items} | {status} ===")

    @property
    def ok(self) -> bool:
        return len(self.p1) == 0


# ============================================================
# 核心检查逻辑
# ============================================================

def validate(csv_dir: Path, ref_dir: Path) -> ValidationResult:
    """对指定目录执行全部静态检查。"""
    result = ValidationResult()

    # ── 加载配置表 ──
    events = load_csv(csv_dir / "events.csv")
    event_conditions = load_csv(csv_dir / "event_conditions.csv")
    event_outcomes = load_csv(csv_dir / "event_outcomes.csv")
    event_presentations = load_csv(csv_dir / "event_presentations.csv")
    options = load_csv(csv_dir / "options.csv")
    option_rules = load_csv(csv_dir / "option_rules.csv")

    # ── 加载参考数据 ──
    attribute_keys = load_attribute_keys(ref_dir)
    if not attribute_keys:
        result.add_p2(f"未找到 {ref_dir / 'attribute_names.csv'}，跳过 key 合法性检查")

    # ── 构建索引 ──
    event_ids: set[str] = {
        r.get("event_id", "").strip() for r in events
        if r.get("event_id", "").strip()
    }
    event_cp_ids: set[str] = {
        r.get("choice_point_id", "").strip() for r in events
        if r.get("choice_point_id", "").strip()
    }
    option_ids: set[str] = {
        r.get("option_id", "").strip() for r in options
        if r.get("option_id", "").strip()
    }

    result.stats["事件"] = len(event_ids)
    result.stats["选项"] = len(option_ids)

    # ── 检查 1: FK — option_rules.option_id → options.option_id ──
    rule_option_ids: set[str] = {
        r.get("option_id", "").strip() for r in option_rules
        if r.get("option_id", "").strip()
    }
    for oid in sorted(rule_option_ids - option_ids):
        result.add_p1(f"option_rules: option_id '{oid}' 不存在于 options.csv")

    # ── 检查 2: FK — options.choice_point_id → events.choice_point_id ──
    for row in options:
        cp_id = row.get("choice_point_id", "").strip()
        if cp_id and cp_id not in event_cp_ids:
            oid = row.get("option_id", "")
            result.add_p1(f"options: '{oid}' 的 choice_point_id '{cp_id}' 不存在于 events.csv")

    # ── 检查 3: FK — 从表 event_id → events.event_id ──
    for table_name, rows in [
        ("event_conditions", event_conditions),
        ("event_presentations", event_presentations),
        ("event_outcomes", event_outcomes),
    ]:
        seen_eids: set[str] = {
            r.get("event_id", "").strip() for r in rows
            if r.get("event_id", "").strip()
        }
        for eid in sorted(seen_eids - event_ids):
            result.add_p1(f"{table_name}: event_id '{eid}' 不存在于 events.csv")

    # ── 检查 4: fail 分支缺失 ──
    options_with_check: set[str] = set()
    options_with_fail: set[str] = set()
    for row in option_rules:
        oid = row.get("option_id", "").strip()
        rule_type = row.get("rule_type", "").strip()
        branch = row.get("branch", "").strip()
        if rule_type == "check":
            options_with_check.add(oid)
        if rule_type == "resolution" and branch == "fail":
            options_with_fail.add(oid)

    for oid in sorted(options_with_check - options_with_fail):
        result.add_p1(
            f"option_rules: '{oid}' 有 check 但无 resolution,fail 行"
            "（引擎将 fallback 到 default，导致失败=成功）"
        )

    result.stats["鉴定选项"] = len(options_with_check)
    result.stats["有fail分支"] = len(options_with_check & options_with_fail)

    # ── 检查 5: rule_type 合法性 ──
    for row in option_rules:
        rt = row.get("rule_type", "").strip()
        if rt and rt not in KNOWN_RULE_TYPES:
            oid = row.get("option_id", "")
            result.add_p2(f"option_rules: '{oid}' 使用未知 rule_type '{rt}'")

    # ── 检查 6: condition_type 合法性 ──
    for row in event_conditions:
        ct = row.get("condition_type", "").strip()
        if ct and ct not in KNOWN_CONDITION_TYPES:
            eid = row.get("event_id", "")
            result.add_p2(f"event_conditions: '{eid}' 使用未知 condition_type '{ct}'")

    # ── 检查 7: cost / resolution key 合法性 ──
    if attribute_keys:
        for row in option_rules:
            rt = row.get("rule_type", "").strip()
            key = row.get("key", "").strip()
            oid = row.get("option_id", "")
            if not key:
                continue
            if rt == "cost":
                if not is_valid_effect_key(key, attribute_keys):
                    result.add_p1(f"option_rules: '{oid}' cost key '{key}' 不在已知集合中")
            elif rt == "resolution":
                target = row.get("target", "").strip()
                # 仅检查 params target 的 key（flags/world 的 key 是自由命名）
                if target == "params" and not is_valid_effect_key(key, attribute_keys):
                    result.add_p1(
                        f"option_rules: '{oid}' resolution key '{key}' 不在已知集合中"
                    )

    # ── 检查 8: cost value 应为正数 ──
    for row in option_rules:
        rt = row.get("rule_type", "").strip()
        if rt != "cost":
            continue
        val_str = row.get("value", "").strip()
        oid = row.get("option_id", "")
        if val_str:
            try:
                val = float(val_str)
                if val < 0:
                    result.add_p2(
                        f"option_rules: '{oid}' cost value={val_str} 为负数"
                        "（cost 应为正数，引擎自动扣除）"
                    )
            except ValueError:
                result.add_p1(f"option_rules: '{oid}' cost value '{val_str}' 不是有效数字")

    return result


# ============================================================
# 入口
# ============================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="CSV 配置静态检查（常规阶段事件引擎 6 表）"
    )
    parser.add_argument("--dir", required=True, help="待检查的 CSV 配置目录")
    parser.add_argument(
        "--ref-dir", default="scripts/config",
        help="参考 CSV 目录，含 attribute_names.csv 等（默认 scripts/config）",
    )
    args = parser.parse_args()

    csv_dir = Path(args.dir)
    ref_dir = Path(args.ref_dir)

    if not csv_dir.exists():
        print(f"错误：目录不存在 {csv_dir}")
        sys.exit(1)

    print(f"检查目录: {csv_dir}")
    print(f"参考目录: {ref_dir}")

    result = validate(csv_dir, ref_dir)
    result.print_report()

    sys.exit(0 if result.ok else 1)


if __name__ == "__main__":
    main()
