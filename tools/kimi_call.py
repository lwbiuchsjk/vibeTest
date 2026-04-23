#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kimi (Moonshot) API 调用脚本。

用途：封装对 Moonshot OpenAI 兼容接口的单次调用。供 Claude Code 通过 Bash
工具驱动，也可人工直接使用。未来的叙事重写专用脚本可封装本脚本。

使用方式（三选一）：
    # 从文件读 prompt
    python3 tools/kimi_call.py --prompt-file path/to/prompt.txt

    # 从 stdin 读 prompt
    echo "写一句金庸风格的话" | python3 tools/kimi_call.py

    # 带 system prompt
    python3 tools/kimi_call.py --system "你是叙事重写助手" --prompt-file prompt.txt

常用参数：
    --model          模型 ID（默认 moonshot-v1-8k；叙事任务建议 kimi-latest 或 kimi-k2-0711-preview）
    --temperature    采样温度（默认 0.6）
    --max-tokens     最大输出 token 数（默认 2000）
    --raw            打印完整 JSON 响应（调试用）

约定：
    - API Key 从 tools/local_env.json 的 moonshot_api_key 字段读取
    - 该文件已在 .gitignore，不会被提交
    - 响应内容打印到 stdout，错误信息打印到 stderr
"""

import argparse
import json
import sys
from pathlib import Path

# 默认模型：选 moonshot-v1-8k 做连通性测试（便宜、稳定）
# 叙事类任务建议通过 --model 指定 kimi-latest 或 kimi-k2-0711-preview
DEFAULT_MODEL = "moonshot-v1-8k"

# 配置文件位置（脚本所在目录下的 local_env.json）
CONFIG_PATH = Path(__file__).resolve().parent / "local_env.json"

# Moonshot 国内 API 端点（OpenAI 兼容）
API_BASE_URL = "https://api.moonshot.cn/v1"


def load_api_key() -> str:
    """从 tools/local_env.json 读取 moonshot_api_key 字段。"""
    if not CONFIG_PATH.exists():
        print(f"错误：配置文件不存在：{CONFIG_PATH}", file=sys.stderr)
        print("请参照 tools/local_env.example.json 创建该文件，并填入 moonshot_api_key。", file=sys.stderr)
        sys.exit(1)

    try:
        config: dict = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"错误：{CONFIG_PATH} 不是合法 JSON：{e}", file=sys.stderr)
        sys.exit(1)

    key: str = str(config.get("moonshot_api_key", "")).strip()
    if not key:
        print(f"错误：{CONFIG_PATH} 缺少 moonshot_api_key 字段或为空。", file=sys.stderr)
        print("请在该文件中添加 \"moonshot_api_key\": \"sk-...\"。", file=sys.stderr)
        sys.exit(1)
    return key


def load_prompt(prompt_file: str | None) -> str:
    """从文件或 stdin 读取 prompt。prompt_file 优先。"""
    if prompt_file:
        return Path(prompt_file).read_text(encoding="utf-8")
    # 从 stdin 读
    if sys.stdin.isatty():
        print("错误：未提供 --prompt-file 且 stdin 为交互终端。", file=sys.stderr)
        print("请用文件或管道传入 prompt。", file=sys.stderr)
        sys.exit(1)
    return sys.stdin.read()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="调用 Kimi (Moonshot) API，返回响应到 stdout。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"模型 ID（默认 {DEFAULT_MODEL}）")
    parser.add_argument("--system", default="", help="system prompt 字符串（可选；长内容建议用 --system-file）")
    parser.add_argument("--system-file", default=None, help="system prompt 文件路径（优先于 --system）")
    parser.add_argument("--prompt-file", default=None, help="prompt 文件路径（省略则从 stdin 读）")
    parser.add_argument("--temperature", type=float, default=0.6, help="采样温度（默认 0.6）")
    parser.add_argument("--max-tokens", type=int, default=2000, help="最大输出 token 数（默认 2000）")
    parser.add_argument("--raw", action="store_true", help="打印完整 JSON 响应而不仅是文本")
    parser.add_argument("--list-models", action="store_true", help="列出当前 API Key 可用的模型（不消耗 prompt）")
    args = parser.parse_args()

    # 惰性导入 openai，提供友好的安装提示
    try:
        from openai import OpenAI
    except ImportError:
        print("错误：未安装 openai 包。请运行：", file=sys.stderr)
        print("    tools/.venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple openai", file=sys.stderr)
        sys.exit(1)

    key: str = load_api_key()
    client = OpenAI(api_key=key, base_url=API_BASE_URL)

    # --list-models 模式：查询账号可用模型，不调用 chat endpoint
    if args.list_models:
        try:
            models = client.models.list()
        except Exception as e:
            print(f"查询模型列表失败：{e}", file=sys.stderr)
            sys.exit(2)
        for m in models.data:
            print(m.id)
        return

    prompt: str = load_prompt(args.prompt_file)

    if not prompt.strip():
        print("错误：prompt 为空。", file=sys.stderr)
        sys.exit(1)

    # 组装 messages：system prompt 可选，user 必填
    # --system-file 优先于 --system 字符串
    system_content: str = ""
    if args.system_file:
        system_content = Path(args.system_file).read_text(encoding="utf-8")
    elif args.system:
        system_content = args.system

    messages: list = []
    if system_content.strip():
        messages.append({"role": "system", "content": system_content})
    messages.append({"role": "user", "content": prompt})

    try:
        resp = client.chat.completions.create(
            model=args.model,
            messages=messages,
            temperature=args.temperature,
            max_tokens=args.max_tokens,
        )
    except Exception as e:
        # API 错误统一打到 stderr，退出码 2 区别于配置错误
        print(f"API 调用失败：{e}", file=sys.stderr)
        sys.exit(2)

    if args.raw:
        # 调试模式：打印完整 JSON（usage、finish_reason 等）
        print(json.dumps(resp.model_dump(), ensure_ascii=False, indent=2))
    else:
        # 常规模式：只打印生成的文本内容
        content = resp.choices[0].message.content
        print(content if content is not None else "")


if __name__ == "__main__":
    main()
