#!/usr/bin/env python3
"""
叙事文本静态检查脚本（L1 机械校验）

对事件卡 Markdown 文件进行结构解析和规则扫描，按 [[叙事文风规范]] / [[叙事重写工程规范]]
检查字数、结构、疑似越线的写法。

用法：
  python tools/narrative_validator.py Design/events/stage_2/
  python tools/narrative_validator.py Design/events/stage_2/xxx.md
  python tools/narrative_validator.py Design/events/stage_2/ --severity P0,P1

覆盖范围（L1 机械）：
  - 字数（屏、选项、后果上限）
  - 结构（frontmatter、叙事段落/选项/后果格式）
  - 跨时空关键词（后果里"晚上""第二天"等）
  - "像……一样/似的"比喻
  - 总结性评价（"闷气散了""胸口松快"等）
  - 主角专名出现在叙事文本中（"沈砚"等）
  - 引号一致性（""/「」混用）

不覆盖（L2 语义，由人工或 subagent 承担）：
  信息层重复、隐式场景跳跃、内心代言越界、声部契合度。
"""

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# ============================================================
# 规范锚点（修改规则前请回看对应条款）
# ============================================================
# [[叙事文风规范]]
#   原则一：第二人称、克制内心、主语省略
#   原则二：每一屏是一个镜头（四种切换）
#   原则三：字数（骨架 30-80 / 填充 30-60）、屏数（填充 1-2 屏）
#   原则四：选项 ≤15 字、不预告收益、不强求对仗
#   原则五：外部细节承担、与选项不同层、锁定此时此地
# ============================================================


# ============================================================
# L1 关键词表 ≠ 规则权威
# ============================================================
# 以下三个常量（CROSS_TIMESPACE_KEYWORDS / SUMMARY_PHRASES / SIMILE_PATTERN）
# 是**旧稿残留高频词筛查器**，不是规范规则的权威判定。
#
# 它们的真实定位：
#   - 批量重写时捕获旧声部叙事里**没清理干净的字样**（旧稿用词是已知集合）
#   - 对 LLM 新产出命中率会迅速衰减——这不是缺陷，是定位正确
#
# 召回不足（漏检）示例：
#   跨时空："晚上"能抓，"日落后""月亮升起时""夜色渐深"抓不到
#   总结性："胸口松快"能抓，"心中一宽""脚步轻了""呼吸也顺了"抓不到
# 精度不足（误报）示例：
#   "晚上" 可能出现在"傍晚上山"，不跨时空
#   "胸口" 可能是"胸口一紧"（身体反应，合法）而非"胸口松快"（情绪总结，违规）
#
# 实质语义判定交给 L2（LLM subagent），详见 [[叙事校验规范]]。
# ============================================================

# 主角专名（出现在叙事文本中属 P0 违规：新声部用第二人称"你"）
PROTAGONIST_NAMES = ["沈砚"]

# 跨时空关键词（P1；定位见上方说明，仅作旧稿残留筛查）
CROSS_TIMESPACE_KEYWORDS = [
    "晚上", "夜里", "入夜", "深夜", "到夜", "半夜",
    "次日", "翌日", "隔日", "第二天", "明日早", "明早", "明晨",
    "过了几天", "过了几日", "数日后", "之后几日", "后来几日",
    "回到屋里", "回到家", "到家时", "回家后", "回家时",
]

# 总结性评价/情绪代言关键词（P1；定位见上方说明，仅作旧稿残留筛查）
SUMMARY_PHRASES = [
    "胸口松快", "闷气散", "闷气也散", "那口气散",
    "心里安定", "心里踏实", "心气散了",
    "关系变好", "关系更近", "关系疏远", "更近了", "更远了",
    "心里酸", "心里暖", "心里发紧",
]

# "像……一样/似的/般" 比喻（P1；定位见上方说明，仅作旧稿残留筛查）
SIMILE_PATTERN = re.compile(r"像[^，。；！？\n]{0,20}(一样|似的|般)")

# 屏的引用块起始
SCREEN_PREFIX = "> "

# 斜体原始设计行
ORIG_DESIGN_PATTERN = re.compile(r"\*原始设计：.*\*")


@dataclass
class Issue:
    """单条校验结果"""
    file: str
    line: int
    severity: str  # P0 / P1 / P2
    rule: str
    message: str


@dataclass
class EventCard:
    """解析后的事件卡结构"""
    path: Path
    frontmatter: dict = field(default_factory=dict)
    frontmatter_end_line: int = 0
    narrative_screens: list = field(default_factory=list)  # [(line_no, text)]
    narrative_orig_design_line: int = 0
    options: list = field(default_factory=list)
    # 每个 option: {line, title, orig_line, 叙事后果: [(line, branch, text)], 叙事后果_orig: [(line, branch, text)]}
    raw_lines: list = field(default_factory=list)


# ============================================================
# 解析
# ============================================================

def parse_frontmatter(lines, card: EventCard) -> int:
    """解析 YAML frontmatter，返回结束行号（包含 '---'）"""
    if not lines or lines[0].rstrip() != "---":
        return 0
    end_idx = 0
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            end_idx = i
            break
    if end_idx == 0:
        return 0
    for line in lines[1:end_idx]:
        m = re.match(r"^([a-zA-Z_][\w\-]*)\s*:\s*(.*?)\s*$", line)
        if m:
            card.frontmatter[m.group(1)] = m.group(2).strip('"\'')
    card.frontmatter_end_line = end_idx + 1
    return end_idx + 1


def parse_event_card(path: Path) -> EventCard:
    """把事件卡 Markdown 解析为结构化对象"""
    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()
    card = EventCard(path=path, raw_lines=lines)

    idx = parse_frontmatter(lines, card)

    # 遍历正文，按一级段落（## 叙事段落 / ## 选项）和选项（### 选项 N）切分
    section = None  # "narrative" | "options"
    option = None

    i = idx
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("## 叙事段落"):
            section = "narrative"
            option = None
        elif stripped.startswith("## 选项"):
            section = "options"
            option = None
        elif stripped.startswith("## "):
            section = None
            option = None
        elif section == "narrative":
            if line.startswith(SCREEN_PREFIX):
                text = line[len(SCREEN_PREFIX):].rstrip()
                card.narrative_screens.append((i + 1, text))
            elif ORIG_DESIGN_PATTERN.search(line):
                card.narrative_orig_design_line = i + 1
        elif section == "options":
            m = re.match(r"^### 选项\s*(\d+)[：:]\s*(.+?)\s*$", stripped)
            if m:
                option = {
                    "line": i + 1,
                    "index": int(m.group(1)),
                    "title": m.group(2).strip(),
                    "orig_design_line": 0,
                    "outcomes": [],  # list of {line, branch, text, orig_line}
                }
                card.options.append(option)
            elif option is not None:
                # 匹配叙事后果：支持 "叙事后果：" 与 "叙事后果（检定成功）：" / "（检定失败）："
                om = re.match(r"^-\s*叙事后果(?:（(检定成功|检定失败)）)?[：:]\s*(.+?)\s*$", stripped)
                if om:
                    branch = om.group(1) or "default"
                    outcome = {
                        "line": i + 1,
                        "branch": branch,
                        "text": om.group(2),
                        "orig_line": 0,
                    }
                    option["outcomes"].append(outcome)
                elif ORIG_DESIGN_PATTERN.search(line):
                    # 第一个紧跟 ### 选项 的 *原始设计：...* 归到选项本身
                    # 紧跟叙事后果的归到最后一个 outcome
                    if option["outcomes"] and option["outcomes"][-1]["orig_line"] == 0:
                        option["outcomes"][-1]["orig_line"] = i + 1
                    elif option["orig_design_line"] == 0:
                        option["orig_design_line"] = i + 1
        i += 1

    return card


# ============================================================
# 字数统计
# ============================================================

def count_chars(text: str) -> int:
    """统计非空白字符数（中英文均计入，标点计入）"""
    return len(re.sub(r"\s+", "", text))


# ============================================================
# 规则
# ============================================================

def rule_frontmatter(card: EventCard, issues: list):
    """R-FM-01：frontmatter 必填 keys"""
    required = ["event_id", "stage", "type"]
    for key in required:
        if key not in card.frontmatter:
            issues.append(Issue(
                file=str(card.path),
                line=1,
                severity="P0",
                rule="R-FM-01",
                message=f"frontmatter 缺少必填字段: {key}",
            ))
    # 填充事件必须有 archetype
    if card.frontmatter.get("type") == "filler" and "archetype" not in card.frontmatter:
        issues.append(Issue(
            file=str(card.path),
            line=1,
            severity="P1",
            rule="R-FM-02",
            message="填充事件缺少 archetype 字段",
        ))


def rule_narrative_screen_count(card: EventCard, issues: list):
    """R-NR-01：屏数范围（骨架 2+、填充 1-2）"""
    event_type = card.frontmatter.get("type", "")
    n = len(card.narrative_screens)
    if n == 0:
        issues.append(Issue(
            file=str(card.path),
            line=1,
            severity="P0",
            rule="R-NR-01",
            message="叙事段落为空（未发现 `> ` 引用块）",
        ))
        return
    if event_type == "skeleton" and n < 2:
        issues.append(Issue(
            file=str(card.path),
            line=card.narrative_screens[0][0],
            severity="P1",
            rule="R-NR-01",
            message=f"骨架事件屏数={n}，规范建议 2+ 屏",
        ))
    if event_type == "filler" and n > 2:
        issues.append(Issue(
            file=str(card.path),
            line=card.narrative_screens[0][0],
            severity="P1",
            rule="R-NR-01",
            message=f"填充事件屏数={n}，规范建议 1-2 屏",
        ))


def rule_screen_chars(card: EventCard, issues: list):
    """R-NR-02：单屏字数上限（骨架 ≤80 / 填充 ≤60，柔性）。下限不强制（第八轮补丁后）。"""
    event_type = card.frontmatter.get("type", "")
    if event_type == "skeleton":
        hi = 80
    elif event_type == "filler":
        hi = 60
    else:
        return
    for line_no, text in card.narrative_screens:
        n = count_chars(text)
        if n > hi:
            issues.append(Issue(
                file=str(card.path),
                line=line_no,
                severity="P1",
                rule="R-NR-02",
                message=f"单屏字数={n}，超过上限 {hi}（{event_type}）",
            ))


def rule_option_title_length(card: EventCard, issues: list):
    """R-OP-01：选项标题 ≤15 字"""
    for opt in card.options:
        n = count_chars(opt["title"])
        if n > 15:
            issues.append(Issue(
                file=str(card.path),
                line=opt["line"],
                severity="P0",
                rule="R-OP-01",
                message=f"选项 {opt['index']} 标题字数={n}，超过 15 上限",
            ))


def rule_outcome_chars(card: EventCard, issues: list):
    """R-OC-01：叙事后果字数建议 ≤60（柔性）"""
    for opt in card.options:
        for oc in opt["outcomes"]:
            n = count_chars(oc["text"])
            if n > 60:
                issues.append(Issue(
                    file=str(card.path),
                    line=oc["line"],
                    severity="P2",
                    rule="R-OC-01",
                    message=f"选项 {opt['index']} 叙事后果({oc['branch']}) 字数={n}，建议 ≤60",
                ))


def rule_cross_timespace(card: EventCard, issues: list):
    """R-OC-02：叙事后果锁定此时此地（跨时空关键词扫描，P1）"""
    for opt in card.options:
        for oc in opt["outcomes"]:
            for kw in CROSS_TIMESPACE_KEYWORDS:
                if kw in oc["text"]:
                    issues.append(Issue(
                        file=str(card.path),
                        line=oc["line"],
                        severity="P1",
                        rule="R-OC-02",
                        message=f"选项 {opt['index']} 叙事后果含跨时空关键词「{kw}」（原则五：锁定此时此地）",
                    ))


def rule_summary_phrases(card: EventCard, issues: list):
    """R-OC-03：叙事后果避免总结性评价 / 情绪代言"""
    for opt in card.options:
        for oc in opt["outcomes"]:
            for phrase in SUMMARY_PHRASES:
                if phrase in oc["text"]:
                    issues.append(Issue(
                        file=str(card.path),
                        line=oc["line"],
                        severity="P1",
                        rule="R-OC-03",
                        message=f"选项 {opt['index']} 叙事后果含总结性评价「{phrase}」（原则一/五）",
                    ))


def rule_simile(card: EventCard, issues: list):
    """R-NR-03：'像……一样/似的/般' 比喻扫描（需人复查）"""
    # 检查所有叙事文本（段落 + 后果）
    texts = [(line_no, text, "叙事段落") for line_no, text in card.narrative_screens]
    for opt in card.options:
        for oc in opt["outcomes"]:
            texts.append((oc["line"], oc["text"], f"选项{opt['index']}后果({oc['branch']})"))
    for line_no, text, loc in texts:
        for m in SIMILE_PATTERN.finditer(text):
            issues.append(Issue(
                file=str(card.path),
                line=line_no,
                severity="P1",
                rule="R-NR-03",
                message=f"{loc} 含「像…{m.group(1)}」比喻：{m.group(0)}（原则一：内心比喻违规；身体感比喻允许，需人复查）",
            ))


def rule_protagonist_name(card: EventCard, issues: list):
    """R-NR-04：主角专名出现在叙事文本中（新声部用"你"）"""
    texts = [(line_no, text, "叙事段落") for line_no, text in card.narrative_screens]
    for opt in card.options:
        texts.append((opt["line"], opt["title"], f"选项{opt['index']}标题"))
        for oc in opt["outcomes"]:
            texts.append((oc["line"], oc["text"], f"选项{opt['index']}后果({oc['branch']})"))
    for line_no, text, loc in texts:
        for name in PROTAGONIST_NAMES:
            if name in text:
                issues.append(Issue(
                    file=str(card.path),
                    line=line_no,
                    severity="P0",
                    rule="R-NR-04",
                    message=f'{loc} 出现主角专名「{name}」（新声部用第二人称"你"）',
                ))


def rule_quote_consistency(card: EventCard, issues: list):
    """R-FT-01：叙事文本区 ""/「」 引号混用（P2；跳过 frontmatter 的 YAML 引号）"""
    # 只扫描正文区（frontmatter 之后）
    body_lines = card.raw_lines[card.frontmatter_end_line:] if card.frontmatter_end_line else card.raw_lines
    content = "\n".join(body_lines)
    cnt_double = content.count('"')
    cnt_bracket = content.count("「") + content.count("」")
    if cnt_double > 0 and cnt_bracket > 0:
        issues.append(Issue(
            file=str(card.path),
            line=1,
            severity="P2",
            rule="R-FT-01",
            message=f"文件内 \"\" 与 「」 混用（\"={cnt_double}, 「」={cnt_bracket}），建议统一",
        ))


def rule_structure(card: EventCard, issues: list):
    """R-ST-01：基础结构完整性（选项必须有原始设计斜体行，后果亦然）"""
    for opt in card.options:
        if opt["orig_design_line"] == 0:
            issues.append(Issue(
                file=str(card.path),
                line=opt["line"],
                severity="P1",
                rule="R-ST-01",
                message=f"选项 {opt['index']}「{opt['title']}」缺少 *原始设计：...* 斜体行",
            ))
        for oc in opt["outcomes"]:
            if oc["orig_line"] == 0:
                issues.append(Issue(
                    file=str(card.path),
                    line=oc["line"],
                    severity="P2",
                    rule="R-ST-01",
                    message=f"选项 {opt['index']} 叙事后果({oc['branch']}) 缺少 *原始设计：...* 斜体行",
                ))


RULES = [
    rule_frontmatter,
    rule_narrative_screen_count,
    rule_screen_chars,
    rule_option_title_length,
    rule_outcome_chars,
    rule_cross_timespace,
    rule_summary_phrases,
    rule_simile,
    rule_protagonist_name,
    rule_quote_consistency,
    rule_structure,
]


# ============================================================
# 主流程
# ============================================================

def validate_file(path: Path) -> list:
    """校验单个事件卡文件，返回 Issue 列表"""
    issues = []
    try:
        card = parse_event_card(path)
    except Exception as e:
        issues.append(Issue(
            file=str(path),
            line=0,
            severity="P0",
            rule="R-PARSE",
            message=f"解析失败：{e}",
        ))
        return issues
    for rule in RULES:
        rule(card, issues)
    return issues


def discover_files(target: Path) -> list:
    """收集待校验文件：若为目录，递归找事件卡；若为文件直接返回"""
    if target.is_file():
        return [target]
    if not target.is_dir():
        return []
    # 事件卡命名模式：*evt_*.md（避开 _index_ / _MOC 等）
    files = []
    for p in sorted(target.rglob("*.md")):
        name = p.name
        if name.startswith("_"):
            continue
        if "evt_" not in name and "sk_" not in name and "fl_" not in name:
            continue
        files.append(p)
    return files


def format_report(all_issues: list, severity_filter: set) -> str:
    """按文件聚合输出报告"""
    filtered = [i for i in all_issues if i.severity in severity_filter]
    if not filtered:
        return "无问题。\n"
    by_file = {}
    for issue in filtered:
        by_file.setdefault(issue.file, []).append(issue)
    lines = []
    for f in sorted(by_file):
        lines.append(f"\n=== {f} ===")
        file_issues = sorted(by_file[f], key=lambda x: (x.severity, x.line))
        for issue in file_issues:
            lines.append(f"  [{issue.severity}] L{issue.line} {issue.rule}: {issue.message}")
    # 汇总
    p0 = sum(1 for i in filtered if i.severity == "P0")
    p1 = sum(1 for i in filtered if i.severity == "P1")
    p2 = sum(1 for i in filtered if i.severity == "P2")
    lines.append(f"\n--- 汇总 ---")
    lines.append(f"  P0 (硬违规): {p0}")
    lines.append(f"  P1 (疑似违规): {p1}")
    lines.append(f"  P2 (风格提醒): {p2}")
    lines.append(f"  文件数: {len(by_file)}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", help="目标文件或目录")
    parser.add_argument("--severity", default="P0,P1,P2",
                        help="输出的严重度过滤（逗号分隔，默认 P0,P1,P2）")
    parser.add_argument("--exit-on", default="P0",
                        help="遇到指定严重度时以非零码退出（默认 P0；可选 P0,P1 或 none）")
    args = parser.parse_args()

    target = Path(args.target)
    files = discover_files(target)
    if not files:
        print(f"未找到事件卡文件：{target}", file=sys.stderr)
        return 2

    all_issues = []
    for f in files:
        all_issues.extend(validate_file(f))

    severity_filter = set(s.strip() for s in args.severity.split(",") if s.strip())
    print(format_report(all_issues, severity_filter))

    if args.exit_on != "none":
        exit_severities = set(s.strip() for s in args.exit_on.split(","))
        if any(i.severity in exit_severities for i in all_issues):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
