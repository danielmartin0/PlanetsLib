# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Render before/after technology icons with Factorio and compose a diff image.

The icon-shadow campaign needs an honest before/after image. Factorio can dump
its own composed technology icons with ``--dump-icon-sprites``; this script runs
that command twice (once with the original mod and once with the modified mod),
then lays the resulting PNGs side by side with labels.

The script never edits the mod repository or the supplied mod directory. It
creates scratch mod directories under ``--out`` (or a temporary directory) and
uses symlinks to the supplied mods.

Examples:
    uv run helper_scripts/render_tech_icon_diff.py \
        --factorio /opt/factorio_space_age_21 \
        --mods-dir /tmp/opencode/perf-final/mods \
        --mod /tmp/opencode/planet-test/testroots/linox/linox_1.8.11 \
        --tech linox-technology_planet-discovery-linox \
        --out /tmp/opencode/linox-icon-diff

    uv run helper_scripts/render_tech_icon_diff.py --self-test
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NoReturn

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - handled by uv
    sys.stderr.write(
        "error: Pillow is required. Run this script with `uv run` so the inline "
        "dependencies are installed.\n"
    )
    raise SystemExit(1)

DEFAULT_OUT = Path("/tmp/opencode/planet-icon-diff")
LABEL_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def factorio_binary(factorio: Path) -> Path:
    candidates = [
        factorio / "bin" / "x64" / "factorio",
        factorio / "bin" / "factorio",
        factorio,
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    fail(f"could not find a Factorio binary under {factorio}")


def factorio_data(factorio: Path) -> Path:
    candidate = factorio / "data"
    if candidate.is_dir():
        return candidate
    fail(f"could not find Factorio's data directory under {factorio}")


def mod_name(mod_root: Path) -> str:
    info = mod_root / "info.json"
    if not info.is_file():
        fail(f"{mod_root} does not contain info.json")
    try:
        with open(info, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"could not read {info}: {exc}")
    name = data.get("name")
    if not name:
        fail(f"{info} has no name")
    return str(name)


def installed_mod(mods_dir: Path, name: str) -> Path | None:
    direct = mods_dir / name
    if direct.exists():
        return direct
    matches = sorted(mods_dir.glob(f"{name}*.zip"))
    if matches:
        return matches[0]
    return None


def make_scratch_mods(
    source: Path,
    destination: Path,
    name: str,
    replacement: Path,
) -> None:
    """Symlink every mod except *name*, then link *replacement* as *name*."""
    destination.mkdir(parents=True, exist_ok=True)
    for entry in sorted(source.iterdir()):
        if entry.name in ("mod-list.json", "mod-settings.dat", "mod-list.json.bak"):
            continue
        if entry.name == name or entry.name.startswith(name + "_"):
            continue
        os.symlink(entry.resolve(), destination / entry.name)
    link_name = replacement.name if replacement.suffix == ".zip" else name
    os.symlink(replacement.resolve(), destination / link_name)
    for filename in ("mod-list.json", "mod-settings.dat"):
        original = source / filename
        if original.is_file():
            shutil.copy2(original, destination / filename)


def write_config(path: Path, data_dir: Path, write_dir: Path) -> None:
    path.write_text(
        "[path]\n"
        f"read-data={data_dir}\n"
        f"write-data={write_dir}\n",
        encoding="utf-8",
    )


def dump_icon(
    binary: Path,
    data_dir: Path,
    mods_dir: Path,
    scratch: Path,
    tech: str,
) -> Path:
    config = scratch / "config.ini"
    write_config(config, data_dir, scratch)
    command = [
        str(binary),
        "--config",
        str(config),
        "--mod-directory",
        str(mods_dir),
        "--dump-icon-sprites",
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        tail = "\n".join((result.stdout + result.stderr).splitlines()[-12:])
        fail(f"Factorio failed while rendering {tech}:\n{tail}")
    icon = scratch / "script-output" / "technology" / f"{tech}.png"
    if not icon.is_file():
        fail(
            f"Factorio did not produce {icon}. Is the technology enabled and "
            "does the mod load?"
        )
    return icon


def compose(before: Path, after: Path, output: Path) -> None:
    with Image.open(before) as image:
        before_image = image.convert("RGBA")
    with Image.open(after) as image:
        after_image = image.convert("RGBA")
    cell = max(before_image.width, before_image.height, after_image.width, after_image.height)
    cell = max(cell, 128)
    margin = 16
    label_height = 34
    width = cell * 2 + margin * 3
    height = cell + margin * 2 + label_height
    canvas = Image.new("RGB", (width, height), (250, 250, 250))
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype(LABEL_FONT, 16)
    except OSError:
        font = ImageFont.load_default()

    for index, (image, label) in enumerate(
        ((before_image, "Before"), (after_image, "After"))
    ):
        x = margin + index * (cell + margin)
        y = margin
        square = Image.new("RGBA", (cell, cell), (255, 255, 255, 255))
        square.alpha_composite(
            image,
            ((cell - image.width) // 2, (cell - image.height) // 2),
        )
        canvas.paste(square.convert("RGB"), (x, y))
        text_width = draw.textlength(label, font=font)
        draw.text(
            (x + (cell - text_width) / 2, y + cell + 8),
            label,
            fill=(20, 20, 20),
            font=font,
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="planetslib-icon-diff-") as temp:
        root = Path(temp)
        before = root / "before.png"
        after = root / "after.png"
        Image.new("RGBA", (292, 292), (255, 0, 0, 255)).save(before)
        Image.new("RGBA", (292, 272), (0, 128, 255, 255)).save(after)
        output = root / "diff.png"
        compose(before, after, output)
        assert output.is_file(), output
        with Image.open(output) as image:
            assert image.width == 292 * 2 + 16 * 3, image.size
            assert image.height == 292 + 16 * 2 + 34, image.size
    print("render_tech_icon_diff.py self-test: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Render before/after technology icons with Factorio.",
    )
    parser.add_argument("--factorio", help="Factorio install directory or binary")
    parser.add_argument("--mods-dir", help="Factorio mod directory")
    parser.add_argument("--mod", help="path to the modified mod root")
    parser.add_argument("--before-mod", help="path to the original mod root")
    parser.add_argument("--tech", action="append", default=[], help="technology name; repeatable")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="output directory")
    parser.add_argument("--keep", action="store_true", help="keep scratch directories")
    parser.add_argument("--self-test", action="store_true", help="run local assertions and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    for required in ("factorio", "mods_dir", "mod"):
        if not getattr(args, required):
            fail(f"provide --{required.replace('_', '-')}")
    if not args.tech:
        fail("provide at least one --tech")

    factorio = Path(args.factorio).resolve()
    binary = factorio_binary(factorio)
    data_dir = factorio_data(factorio)
    mods_dir = Path(args.mods_dir).resolve()
    modified = Path(args.mod).resolve()
    name = mod_name(modified)
    before_mod = (
        Path(args.before_mod).resolve()
        if args.before_mod
        else installed_mod(mods_dir, name)
    )
    if before_mod is None:
        fail(f"could not find the original {name!r} in {mods_dir}; pass --before-mod")
    if before_mod == modified:
        fail("--before-mod and --mod resolve to the same path")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    scratch_root = out / ".scratch"
    if scratch_root.exists():
        shutil.rmtree(scratch_root)
    scratch_root.mkdir(parents=True)

    try:
        before_mods = scratch_root / "before" / "mods"
        after_mods = scratch_root / "after" / "mods"
        make_scratch_mods(mods_dir, before_mods, name, before_mod)
        make_scratch_mods(mods_dir, after_mods, name, modified)
        for tech in args.tech:
            before_icon = dump_icon(
                binary,
                data_dir,
                before_mods,
                scratch_root / "before",
                tech,
            )
            after_icon = dump_icon(
                binary,
                data_dir,
                after_mods,
                scratch_root / "after",
                tech,
            )
            target = out / tech
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(before_icon, target / "before.png")
            shutil.copy2(after_icon, target / "after.png")
            compose(before_icon, after_icon, target / "diff.png")
            print(target / "diff.png")
    finally:
        if not args.keep:
            shutil.rmtree(scratch_root, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
