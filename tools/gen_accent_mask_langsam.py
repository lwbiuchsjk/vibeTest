#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LangSAM 文本驱动 mask 生成脚本

适用范围(避免误用):
- ✓ 本工具仅产 face mask / accent mask (二值 RGBA PNG, A=mask×255)
- ✓ 供 text_mosaic_background.gd::set_exclude_mask 或
      text_mosaic_accent_marked.gd 通过 Image.get_pixel().a 判定 mask 区域
- ✗ **不是** mosaic 离线渲染工具——mosaic 是运行时效果,
      由 text_mosaic_background.gd::_draw 在 Godot 内反向采样源图实时渲染,
      不存在"离线 mosaic PNG"产物。源图入库走 Design/事件背景图入库工作流
- 工作流参考: Design/face_mask生成工作流.md (五步标准流程)

用途:输入源图 + 文本提示,调用 LangSAM(GroundingDINO + SAM 2.1)输出像素级 mask PNG。
产物为 RGBA PNG(RGB=白色,A=mask × 255),与源图同尺寸,供 Godot 引擎
text_mosaic_accent_marked.gd 通过 Image.get_pixel().a 判定 accent 区域。

使用方式:
    # 基础用法(top-1 mask)
    python3 tools/gen_accent_mask_langsam.py \
        --image assets/art/environments/backgrounds/training_ground.png \
        --prompt "red sash belt" \
        --output assets/art/environments/backgrounds/training_ground_accent_belt.png

    # prompt 调试:保存前 3 个候选 + 可视化叠加图
    python3 tools/gen_accent_mask_langsam.py \
        --image .../training_ground.png \
        --prompt "sword blade highlight" \
        --output /tmp/blade_test.png \
        --top-k 3 --debug

约定:
- 默认 sam_type=sam2.1_hiera_small(快速 PoC);精度不够时切 base_plus / large
- box-threshold / text-threshold 调低 → 更宽松检测(可能误报);调高 → 更严格(可能漏检)
- 首次运行会自动下载 GroundingDINO(~600MB) + SAM 2.1 权重(~38-220MB,看 sam_type)到
  ~/.cache/huggingface 与 ~/.cache/torch/hub,后续从缓存读

退出码:
- 0 = 成功(至少 1 个 mask 输出)
- 1 = 未检测到匹配对象(prompt 在当前阈值下无 GDINO 输出)
- 2 = 其他异常(输入文件不存在等)
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description="LangSAM 文本驱动 mask 生成(text_mosaic accent 路径)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--image", required=True, type=Path,
                        help="输入源图路径(PNG/JPG)")
    parser.add_argument("--prompt", required=True, type=str,
                        help="GroundingDINO 文本提示(建议英文,如 'red sash belt')")
    parser.add_argument("--output", required=True, type=Path,
                        help="输出 mask PNG 路径")
    parser.add_argument("--box-threshold", type=float, default=0.3,
                        help="GDINO 框置信度阈值(默认 0.3)")
    parser.add_argument("--text-threshold", type=float, default=0.25,
                        help="GDINO 文本-图像匹配阈值(默认 0.25)")
    parser.add_argument("--sam-type", type=str, default="sam2.1_hiera_small",
                        choices=[
                            "sam2.1_hiera_tiny",
                            "sam2.1_hiera_small",
                            "sam2.1_hiera_base_plus",
                            "sam2.1_hiera_large",
                        ],
                        help="SAM 2.1 变体(默认 small)")
    parser.add_argument("--device", type=str, default=None,
                        help="推理设备 cuda/cpu(默认自动:有 CUDA 用 cuda,否则 cpu)")
    parser.add_argument("--top-k", type=int, default=1,
                        help="保存前 K 个候选 mask(>1 时文件名插入 _0/_1/...)")
    parser.add_argument("--debug", action="store_true",
                        help="额外保存可视化叠加图(mask 半透明红色叠加源图)")
    parser.add_argument("--multimask", action="store_true",
                        help="启用 SAM 2 multimask_output:每个 GDINO box 出 3 个候选 mask "
                             "(whole/part/subpart 三粒度,whole 含背景大,subpart 仅核心区)。"
                             "文件名加 _b{box}_c{cand} 后缀。绕开 LangSAM 单 mask 限制")
    return parser.parse_args()


def to_rgba_mask(mask: np.ndarray, width: int, height: int) -> Image.Image:
    """二值 mask (bool/0-1) → RGBA PNG(RGB=白, A=mask × 255)。

    Godot 引擎读 alpha 判定:get_pixel(x, y).a > 0.5 即在 accent 区域内。
    RGB 设为白色仅为可视化方便(直接打开 PNG 看也能区分),引擎不读 RGB。
    """
    alpha = (mask.astype(np.uint8) * 255)
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    rgba[..., 0:3] = 255  # RGB = 白
    rgba[..., 3] = alpha
    return Image.fromarray(rgba, mode="RGBA")


def to_debug_overlay(image: Image.Image, mask: np.ndarray) -> Image.Image:
    """生成 debug 可视化:源图 + 半透明红色 mask 叠加,便于人眼检视边缘贴合度。"""
    base = np.array(image).astype(np.float32)
    mask_3ch = np.stack([mask] * 3, axis=-1).astype(np.float32)
    red = np.array([255, 0, 0], dtype=np.float32)
    # alpha=0.4 红色叠加,mask=0 区域保持原色
    overlay = base * (1 - 0.4 * mask_3ch) + red * 0.4 * mask_3ch
    overlay = np.clip(overlay, 0, 255).astype(np.uint8)
    return Image.fromarray(overlay, mode="RGB")


def main() -> int:
    """主流程:加载图 → 初始化 LangSAM → 推理 → 排序 → 保存 top-K mask。"""
    args = parse_args()

    # 输入校验:延迟 import 重依赖(让 -h 快速响应)
    if not args.image.is_file():
        print(f"[error] 输入图不存在: {args.image}", file=sys.stderr)
        return 2

    print(f"[1/4] 加载图像: {args.image}")
    image = Image.open(args.image).convert("RGB")
    width, height = image.size
    print(f"  尺寸: {width}×{height}")

    print(f"[2/4] 初始化 LangSAM(sam_type={args.sam_type})")
    # 重依赖延迟到此处 import,避免 --help 时拖慢
    import torch
    from lang_sam import LangSAM

    device_name = args.device or ("cuda" if torch.cuda.is_available() else "cpu")
    print(f"  推理设备: {device_name}")
    print(f"  首次运行会下载 GroundingDINO + SAM 2.1 权重(~700MB),后续从缓存读")
    model = LangSAM(sam_type=args.sam_type, device=torch.device(device_name))

    print(f"[3/4] 推理:prompt='{args.prompt}'  "
          f"thresholds=(box={args.box_threshold}, text={args.text_threshold})  "
          f"multimask={args.multimask}")

    # 分两条路径:
    # - 默认:走 LangSAM model.predict,GDINO + SAM 一步出单 mask/box
    # - --multimask:绕开 LangSAM 单 mask 限制,gdino 出 box → sam.predictor 直接调
    #   带 multimask_output=True,每个 box 出 3 候选(whole/part/subpart)
    if args.multimask:
        return _run_multimask(args, model, image, width, height)
    return _run_single_mask(args, model, image, width, height)


def _run_single_mask(args, model, image: Image.Image, width: int, height: int) -> int:
    """默认路径:LangSAM 单 mask/box,按 GDINO score 排序保存 top-K。"""
    results = model.predict(
        images_pil=[image],
        texts_prompt=[args.prompt],
        box_threshold=args.box_threshold,
        text_threshold=args.text_threshold,
    )
    # results 是 list,本脚本单图调用 → 取 [0]
    result = results[0]

    # 解包字段:LangSAM 返回 boxes/scores/labels/masks/mask_scores
    # 边界处理:SAM 在单 box 场景会把 mask_scores 压成 0-d scalar、masks 压成 (H, W) 而非 (1, H, W)
    # 用 atleast_1d / 维度补齐保证后续按 (N, ...) 一致访问
    labels = list(result.get("labels", []))
    scores = np.atleast_1d(np.asarray(result.get("scores", []), dtype=np.float32))
    mask_scores = np.atleast_1d(np.asarray(result.get("mask_scores", []), dtype=np.float32))
    masks = np.asarray(result.get("masks", []))
    if masks.ndim == 2:
        # 单 mask 被压成 (H, W) → 补成 (1, H, W)
        masks = masks[None, ...]

    print(f"  检测到 {len(labels)} 个候选对象:")
    for i, lbl in enumerate(labels):
        gd = scores[i] if i < len(scores) else float("nan")
        ms = mask_scores[i] if i < len(mask_scores) else float("nan")
        print(f"    [{i}] label='{lbl}'  gdino_score={gd:.3f}  sam_score={ms:.3f}")

    # 无检测处理:GDINO 在当前阈值下没找到 prompt 对应对象
    if not labels or len(masks) == 0:
        _print_no_detection_hint(args)
        return 1

    # 按 GDINO score 降序选 top-K(GDINO 是检测置信度;SAM mask_score 是 mask 质量,通常排序差异小)
    order = np.argsort(-scores)

    print(f"[4/4] 保存 top-{args.top_k} mask")
    saved = 0
    for rank, idx in enumerate(order[: args.top_k]):
        idx = int(idx)
        mask = masks[idx]
        out_img = to_rgba_mask(mask, width, height)

        # 文件名规则:top-1 直接用 --output;top-N 在 stem 后插 _0/_1
        if args.top_k == 1:
            out_path = args.output
        else:
            out_path = args.output.with_name(
                f"{args.output.stem}_{rank}{args.output.suffix}"
            )

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_img.save(out_path)
        print(
            f"  rank={rank} idx={idx} label='{labels[idx]}' "
            f"gdino={scores[idx]:.3f} sam={mask_scores[idx]:.3f} → {out_path}"
        )

        # debug 叠加图:用于人眼检视 mask 边缘是否贴合 prompt 对应对象
        if args.debug:
            debug_img = to_debug_overlay(image, mask)
            debug_path = out_path.with_name(f"{out_path.stem}_debug{out_path.suffix}")
            debug_img.save(debug_path)
            print(f"    debug 叠加图 → {debug_path}")

        saved += 1

    print(f"[done] 已保存 {saved} 个 mask")
    return 0


def _run_multimask(args, model, image: Image.Image, width: int, height: int) -> int:
    """multimask 路径:每个 GDINO box 出 3 个候选 mask(whole/part/subpart 三粒度)。

    SAM 2 设计本身支持一个 box 输出 3 个不同粒度的 mask:整体 / 部分 / 子部分。
    LangSAM 0.2.1 把 multimask_output hardcode 为 False(只取最大粒度),这里绕开
    单独调 model.gdino.predict 拿 box → model.sam.predictor.predict(multimask_output=True)。
    """
    import torch  # 已在 main 里 import,这里复用即可,但函数独立保险起见再 import

    # Step 1: 直接调 GDINO 拿 box(不走 LangSAM 的 SAM 部分)
    gdino_results = model.gdino.predict(
        images_pil=[image],
        texts_prompt=[args.prompt],
        box_threshold=args.box_threshold,
        text_threshold=args.text_threshold,
    )
    gd = gdino_results[0]

    # GDINO 返回的字段是 torch.Tensor,转 numpy 后续好处理
    def _to_np(v):
        return v.detach().cpu().numpy() if hasattr(v, "cpu") else np.asarray(v)

    labels = list(gd.get("labels", []))
    boxes = _to_np(gd.get("boxes", np.zeros((0, 4))))  # shape (N, 4) xyxy
    gdino_scores = _to_np(gd.get("scores", np.zeros((0,)))).astype(np.float32)
    gdino_scores = np.atleast_1d(gdino_scores)

    print(f"  GDINO 检测到 {len(labels)} 个 box:")
    for i, lbl in enumerate(labels):
        gs = gdino_scores[i] if i < len(gdino_scores) else float("nan")
        print(f"    box[{i}] label='{lbl}'  gdino_score={gs:.3f}")

    if not labels or len(boxes) == 0:
        _print_no_detection_hint(args)
        return 1

    # Step 2: 直接调 SAM 2 predictor,带 multimask_output=True
    sam_pred = model.sam.predictor  # SAM2ImagePredictor 实例
    sam_pred.set_image(np.asarray(image))

    masks_multi, sam_scores, _ = sam_pred.predict(
        box=boxes,                  # shape (N, 4)
        multimask_output=True,      # 关键:每 box 出 3 候选 mask
    )
    # masks_multi: 单 box 时 shape (3, H, W);多 box 时 shape (N, 3, H, W)
    # sam_scores: 单 box (3,);多 box (N, 3)
    masks_multi = np.asarray(masks_multi)
    sam_scores = np.asarray(sam_scores)
    if masks_multi.ndim == 3:
        # 单 box 被压成 (3, H, W) → 补成 (1, 3, H, W)
        masks_multi = masks_multi[None, ...]
        sam_scores = np.atleast_2d(sam_scores)

    n_boxes, n_cand = masks_multi.shape[0], masks_multi.shape[1]
    print(f"  SAM 给出 {n_boxes} box × {n_cand} 候选 mask = {n_boxes * n_cand} 个 mask")

    # Step 3: 保存所有 (box, candidate) 组合
    print(f"[4/4] 保存 multimask 候选 → 文件名 {{stem}}_b{{box}}_c{{cand}}{{suffix}}")
    saved = 0
    for b in range(n_boxes):
        for c in range(n_cand):
            mask = masks_multi[b, c]
            sc = float(sam_scores[b, c])
            out_img = to_rgba_mask(mask, width, height)

            out_path = args.output.with_name(
                f"{args.output.stem}_b{b}_c{c}{args.output.suffix}"
            )
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_img.save(out_path)
            print(
                f"  box={b} cand={c} label='{labels[b]}' "
                f"gdino={gdino_scores[b]:.3f} sam={sc:.3f} → {out_path}"
            )

            if args.debug:
                debug_img = to_debug_overlay(image, mask)
                debug_path = out_path.with_name(
                    f"{out_path.stem}_debug{out_path.suffix}"
                )
                debug_img.save(debug_path)
                print(f"    debug 叠加图 → {debug_path}")

            saved += 1

    print(f"[done] 已保存 {saved} 个 mask")
    return 0


def _print_no_detection_hint(args) -> None:
    """统一打印"无检出"时的调参建议。"""
    print(
        f"[error] 未检测到匹配对象。建议:\n"
        f"  - 降低 --box-threshold(当前 {args.box_threshold},可试 0.2 / 0.15)\n"
        f"  - 降低 --text-threshold(当前 {args.text_threshold},可试 0.2 / 0.15)\n"
        f"  - 换 prompt(如把 '腰带绛朱' 改 'red sash' 或 'crimson belt')",
        file=sys.stderr,
    )


if __name__ == "__main__":
    sys.exit(main())
