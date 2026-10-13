#!/usr/bin/env python3
"""
Glance logo extractor: optionally make a photographic negative for detection,
remove the background, isolate the center logo, recolor it, and export PNG/SVG.

Install:
    python -m pip install opencv-python numpy

Examples:
    # Negative/inverted source -> remove background -> apply Glance blue -> PNG
    python halftone_vectorizer.py logo.png --negative-before-remove --mask auto --bg-tolerance 45 --focus center --color "#3478F6" --format png --output glance_inverted.png

    # Same extraction without negative preprocessing
    python halftone_vectorizer.py logo.png --mask auto --bg-tolerance 45 --focus center --color "#3478F6" --format png --output glance_logo.png

    # Export both transparent PNG and SVG
    python halftone_vectorizer.py logo.png --negative-before-remove --mask auto --bg-tolerance 45 --focus center --color "#3478F6" --format both --output glance_logo
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

import cv2
import numpy as np


def parse_color(value: str) -> tuple[int, int, int]:
    value = value.strip()
    if not re.fullmatch(r"#?[0-9a-fA-F]{6}", value):
        raise argparse.ArgumentTypeError("Use a hex color such as #3478F6")
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def edge_background_mask(rgb: np.ndarray, tolerance: float) -> np.ndarray:
    """Find background-colored pixels connected to the image border."""
    border = np.concatenate(
        [rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]], axis=0
    )
    bg = np.median(border.astype(np.float32), axis=0)
    distance = np.linalg.norm(rgb.astype(np.float32) - bg, axis=2)
    candidates = (distance <= tolerance).astype(np.uint8)

    count, labels = cv2.connectedComponents(candidates, connectivity=8)
    if count <= 1:
        return np.zeros(rgb.shape[:2], dtype=bool)

    edge_labels = np.unique(
        np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])
    )
    edge_labels = edge_labels[edge_labels != 0]
    return np.isin(labels, edge_labels)


def keep_center_object(mask: np.ndarray) -> np.ndarray:
    """Keep the central connected component and nearby fragments of the logo."""
    h, w = mask.shape
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        mask.astype(np.uint8), connectivity=8
    )
    if count <= 1:
        return mask

    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    center_label = int(labels[int(round(cy)), int(round(cx))])
    valid = [
        i for i in range(1, count)
        if stats[i, cv2.CC_STAT_AREA] > 1
    ]
    if not valid:
        return np.zeros_like(mask, dtype=bool)

    if center_label > 0:
        main_label = center_label
    else:
        main_label = min(
            valid,
            key=lambda i:
                ((centroids[i][0] - cx) / max(w, 1)) ** 2
                + ((centroids[i][1] - cy) / max(h, 1)) ** 2
                - 1e-7 * stats[i, cv2.CC_STAT_AREA],
        )

    x = stats[main_label, cv2.CC_STAT_LEFT]
    y = stats[main_label, cv2.CC_STAT_TOP]
    bw = stats[main_label, cv2.CC_STAT_WIDTH]
    bh = stats[main_label, cv2.CC_STAT_HEIGHT]

    pad_x = max(int(w * 0.14), int(bw * 0.65), 4)
    pad_y = max(int(h * 0.14), int(bh * 0.65), 4)
    x0, y0 = max(0, x - pad_x), max(0, y - pad_y)
    x1, y1 = min(w, x + bw + pad_x), min(h, y + bh + pad_y)

    keep_labels = {main_label}
    for i in valid:
        px, py = centroids[i]
        if x0 <= px < x1 and y0 <= py < y1:
            keep_labels.add(i)

    result = np.isin(labels, list(keep_labels))
    k = max(3, (min(h, w) // 250) * 2 + 1)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    return cv2.morphologyEx(
        result.astype(np.uint8), cv2.MORPH_CLOSE, kernel
    ) > 0


def prepare_image(image: np.ndarray, negative_before_remove: bool) -> np.ndarray:
    """Optionally invert RGB like a photo negative, preserving the alpha channel."""
    if not negative_before_remove:
        return image.copy()

    result = image.copy()
    if result.ndim == 2:
        return 255 - result

    result[:, :, :3] = 255 - result[:, :, :3]
    # Keep alpha unchanged so existing transparent areas remain transparent.
    return result


def build_mask(
    image: np.ndarray,
    mode: str,
    threshold: int,
    tolerance: float,
    keep_background: bool,
    invert_mask: bool,
) -> np.ndarray:
    has_alpha = image.ndim == 3 and image.shape[2] == 4

    if image.ndim == 2:
        gray = image
        rgb = cv2.cvtColor(image, cv2.COLOR_GRAY2RGB)
    else:
        bgr = image[:, :, :3]
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)

    alpha = image[:, :, 3] if has_alpha else None
    alpha_has_transparency = alpha is not None and np.any(alpha < 250)

    if mode == "alpha" or (mode == "auto" and alpha_has_transparency):
        if alpha is None:
            raise ValueError("--mask alpha requires an image with an alpha channel")
        mask = alpha > 8
    elif mode == "dark":
        mask = gray <= threshold
        if has_alpha:
            mask &= alpha > 8
    elif mode == "light":
        mask = gray >= threshold
        if has_alpha:
            mask &= alpha > 8
    else:
        mask = (
            np.ones(gray.shape, dtype=bool)
            if keep_background
            else ~edge_background_mask(rgb, tolerance)
        )
        if has_alpha:
            mask &= alpha > 8

    if invert_mask:
        mask = ~mask
        if has_alpha:
            mask &= alpha > 8

    return mask


def contour_path(contour: np.ndarray, scale: float) -> str:
    points = contour.reshape(-1, 2)
    if len(points) < 3:
        return ""
    commands = [f"M {points[0, 0] * scale:.2f},{points[0, 1] * scale:.2f}"]
    commands.extend(
        f"L {x * scale:.2f},{y * scale:.2f}" for x, y in points[1:]
    )
    commands.append("Z")
    return " ".join(commands)


def write_svg(
    mask: np.ndarray,
    color_hex: str,
    path: Path,
    scale: float,
    simplify: float,
    title: str,
) -> None:
    h, w = mask.shape
    contours, _ = cv2.findContours(
        mask.astype(np.uint8) * 255,
        cv2.RETR_TREE,
        cv2.CHAIN_APPROX_SIMPLE,
    )

    paths = []
    for contour in contours:
        chosen = contour
        if simplify > 0:
            approx = cv2.approxPolyDP(contour, simplify, True)
            if len(approx) >= 3:
                chosen = approx
        d = contour_path(chosen, scale)
        if d:
            paths.append(d)

    if not paths:
        raise ValueError("No usable contours for SVG output")

    width, height = w * scale, h * scale
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:g}" '
        f'height="{height:g}" viewBox="0 0 {width:g} {height:g}">'
        f"<title>{title}</title>"
        f'<path d="{" ".join(paths)}" fill="{color_hex}" '
        f'fill-rule="evenodd"/></svg>'
    )
    path.write_text(svg, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Optionally invert the source like a negative, remove its background, "
            "isolate the central logo, recolor, and export transparent PNG/SVG."
        )
    )
    parser.add_argument("image", help="Input image path")
    parser.add_argument("--output", "-o", default=None, help="Output filename/path")
    parser.add_argument("--color", default="#3478F6", help="Output hex color")
    parser.add_argument("--format", choices=("png", "svg", "both"), default="png")
    parser.add_argument("--mask", choices=("auto", "alpha", "dark", "light"), default="auto")
    parser.add_argument("--focus", choices=("all", "center"), default="center")
    parser.add_argument("--threshold", type=int, default=100)
    parser.add_argument(
        "--negative-before-remove",
        action="store_true",
        help="Invert source RGB values like a photo negative before background detection",
    )
    parser.add_argument(
        "--invert-mask",
        action="store_true",
        help="Invert the detected foreground/background mask instead of image colors",
    )
    parser.add_argument("--keep-background", action="store_true")
    parser.add_argument("--bg-tolerance", type=float, default=35)
    parser.add_argument("--scale", type=float, default=1)
    parser.add_argument("--simplify", type=float, default=0.8)
    args = parser.parse_args()

    try:
        color_rgb = parse_color(args.color)
    except argparse.ArgumentTypeError as exc:
        parser.error(str(exc))

    color_hex = "#" + "".join(f"{c:02X}" for c in color_rgb)
    source = Path(args.image)
    if not source.is_file():
        parser.error(f"Input image not found: {source}")
    if (
        not 0 <= args.threshold <= 255
        or args.bg_tolerance < 0
        or args.scale <= 0
        or args.simplify < 0
    ):
        parser.error("Invalid threshold/tolerance/scale/simplification value")

    original = cv2.imread(str(source), cv2.IMREAD_UNCHANGED)
    if original is None:
        parser.error(f"Could not read input image: {source}")

    # Requested order: negative/invert source first, then remove background.
    processed = prepare_image(original, args.negative_before_remove)

    try:
        mask = build_mask(
            processed,
            args.mask,
            args.threshold,
            args.bg_tolerance,
            args.keep_background,
            args.invert_mask,
        )
    except ValueError as exc:
        parser.error(str(exc))

    if args.focus == "center":
        mask = keep_center_object(mask)

    # Remove tiny isolated noise components.
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask.astype(np.uint8), connectivity=8
    )
    if count > 1:
        keep = np.zeros(count, dtype=bool)
        minimum_area = max(2, int(mask.size * 0.0000005))
        for i in range(1, count):
            keep[i] = stats[i, cv2.CC_STAT_AREA] >= minimum_area
        mask = keep[labels]

    if int(mask.sum()) < max(10, mask.size * 0.00001):
        parser.error(
            "Too little foreground detected. Try --mask alpha, --mask dark, "
            "or --mask light; adjust --bg-tolerance if needed."
        )

    # Recolor the extracted logo AFTER background removal.
    # The logo gets the selected color; every background pixel gets alpha=0.
    h, w = mask.shape
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[:, :, 0] = color_rgb[0]
    rgba[:, :, 1] = color_rgb[1]
    rgba[:, :, 2] = color_rgb[2]
    rgba[:, :, 3] = mask.astype(np.uint8) * 255

    output = Path(args.output) if args.output else source.with_name(source.stem + "_inverted")
    output.parent.mkdir(parents=True, exist_ok=True)

    if args.format in ("png", "both"):
        png_path = output if output.suffix.lower() == ".png" else Path(str(output) + ".png")
        if not cv2.imwrite(str(png_path), cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA)):
            parser.error(f"Could not write PNG: {png_path}")
        print(f"Saved transparent PNG: {png_path.resolve()}")

    if args.format in ("svg", "both"):
        svg_path = output if output.suffix.lower() == ".svg" else Path(str(output) + ".svg")
        try:
            write_svg(mask, color_hex, svg_path, args.scale, args.simplify, f"Extracted logo from {source.name}")
        except ValueError as exc:
            parser.error(str(exc))
        print(f"Saved transparent SVG: {svg_path.resolve()}")

    print(
        f"Foreground pixels: {int(mask.sum())} | focus: {args.focus} | "
        f"color: {color_hex} | negative preprocessing: {args.negative_before_remove}"
    )
    print("Background: transparent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
