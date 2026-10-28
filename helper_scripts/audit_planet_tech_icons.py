# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Audit planet/moon discovery technology icons for shadow coverage.

This script reads a Factorio ``--dump-data`` JSON file, finds every technology
that unlocks a ``planet`` prototype, resolves the primary planet icon and
measures its disc fraction, and reports whether the icon already has a
PlanetsLib shadow layer and which ``shadow_scale`` would reproduce vanilla's
shadow-to-planet ratio.

The scale rule is::

    shadow_scale = TARGET_RATIO * icon_size / disc_px

where ``TARGET_RATIO`` is vanilla's shadow-ellipse width divided by the planet
disc width (183 / 216 = 0.84375). The helper scales the planet image so it
renders at about 216 px while the shadow ellipse remains 183 px.

Baked-in shadows cannot be detected reliably from pixels. Supply
``--decisions FILE`` to persist human ``true``/``false`` decisions; the script
writes a skeleton for any technology that does not have one yet.

Examples:
    uv run helper_scripts/audit_planet_tech_icons.py \
        --dump /tmp/opencode/iconcheck/script-output/data-raw-dump.json \
        --mods-dir /tmp/opencode/perf-final/mods \
        --factorio-data /opt/factorio_space_age_21/data \
        --decisions /tmp/opencode/planet-icon-decisions.json \
        --out /tmp/opencode/planet-icon-campaign.json

    uv run helper_scripts/audit_planet_tech_icons.py --self-test
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, NoReturn

try:
    from PIL import Image
except ImportError:  # pragma: no cover - handled by uv
    sys.stderr.write(
        "error: Pillow is required. Run this script with `uv run` so the inline "
        "dependencies are installed.\n"
    )
    raise SystemExit(1)

TARGET_RATIO = 183 / 216  # vanilla shadow ellipse width / planet disc width
DEFAULT_HELPER = "technology_icon_planet"
SHADOW_SUFFIX = "graphics/icons/planet-technology.png"
MOON_SYMBOL = "moon-technology-symbol.png"
OVERLAY_MARKERS = (
    "constant-planet.png",
    "effect-constant",
    "overlay/planet.png",
    "moon-technology-symbol.png",
    SHADOW_SUFFIX,
)
BUILTIN_MODS = {
    "core": "core",
    "base": "base",
    "space-age": "space-age",
    "elevated-rails": "elevated-rails",
    "quality": "quality",
    "recycler": "recycler",
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def chain_total(size: int) -> int:
    total = 0
    value = size
    while value >= 32:
        total += value
        value //= 2
    return total


def split_path(path: str) -> tuple[str, str]:
    if not path.startswith("__") or "__/" not in path[2:]:
        fail(f"icon path is not a Factorio path: {path!r}")
    mod, rest = path[2:].split("__/", 1)
    return mod, rest


def load_image(
    path: str,
    mods_dir: Path,
    factorio_data: Path | None,
) -> Image.Image | None:
    mod, rest = split_path(path)
    if mod in BUILTIN_MODS:
        if factorio_data is None:
            return None
        candidate = factorio_data / BUILTIN_MODS[mod] / rest
        if candidate.is_file():
            with Image.open(candidate) as image:
                return image.convert("RGBA").copy()
        return None

    direct = mods_dir / mod / rest
    if direct.is_file():
        with Image.open(direct) as image:
            return image.convert("RGBA").copy()

    # Some development setups use a versioned directory instead of ``mod/``.
    for directory in sorted(mods_dir.glob(f"{mod}*")):
        if not directory.is_dir():
            continue
        candidate = directory / rest
        if candidate.is_file():
            with Image.open(candidate) as image:
                return image.convert("RGBA").copy()

    for archive in sorted(mods_dir.glob(f"{mod}*.zip")):
        if archive.name != f"{mod}.zip" and not archive.name.startswith(f"{mod}_"):
            continue
        try:
            with zipfile.ZipFile(archive) as handle:
                candidates = [rest]
                candidates += [
                    name for name in handle.namelist() if name.endswith("/" + rest)
                ]
                for name in candidates:
                    try:
                        payload = handle.read(name)
                    except KeyError:
                        continue
                    with Image.open(io.BytesIO(payload)) as image:
                        return image.convert("RGBA").copy()
        except zipfile.BadZipFile:
            continue
    return None


def measure_icon(image: Image.Image, icon_size: int) -> tuple[int, int, int, bool]:
    """Return (disc_px, centre_x, widest_row, cropped_mipmaps)."""
    cropped = False
    if image.width == chain_total(icon_size) and image.height == icon_size:
        image = image.crop((0, 0, icon_size, icon_size))
        cropped = True

    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value > 8 else 0)
    best_width = 0
    best_centre = image.width // 2
    best_row = 0
    for y in range(image.height):
        bbox = mask.crop((0, y, image.width, y + 1)).getbbox()
        if not bbox:
            continue
        width = bbox[2] - bbox[0]
        if width > best_width:
            best_width = width
            best_centre = (bbox[0] + bbox[2]) // 2
            best_row = y
    return best_width, best_centre, best_row, cropped


@dataclass
class Entry:
    tech: str
    locations: list[str]
    kind: str
    mod: str
    icon: str
    icon_size: int
    disc_px: int
    disc_fraction: float
    suggested_scale: float
    helper: str
    has_planetslib_shadow: bool
    baked_shadow: bool | None
    needs_shadow: bool | None
    warnings: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "tech": self.tech,
            "locations": self.locations,
            "kind": self.kind,
            "mod": self.mod,
            "icon": self.icon,
            "icon_size": self.icon_size,
            "disc_px": self.disc_px,
            "disc_fraction": round(self.disc_fraction, 4),
            "shadow_scale": round(self.suggested_scale, 3),
            "helper": self.helper,
            "has_planetslib_shadow": self.has_planetslib_shadow,
            "baked_shadow": self.baked_shadow,
            "needs_shadow": self.needs_shadow,
            "warnings": self.warnings,
            "snippet": (
                f'PlanetsLib.{self.helper}("{self.icon}", '
                f"{self.icon_size}, {round(self.suggested_scale, 3):g})"
            ),
        }


def primary_layer(layers: list[dict], tech_icon_size: int | None) -> tuple[dict, list[str]]:
    candidates = []
    warnings = []
    for layer in layers:
        icon = str(layer.get("icon") or "")
        if not icon:
            continue
        if any(marker in icon for marker in OVERLAY_MARKERS):
            continue
        candidates.append(layer)
    if not candidates:
        candidates = [layer for layer in layers if layer.get("icon")]
    if len(candidates) > 1:
        warnings.append("multiple_candidate_layers")
    layer = max(
        candidates,
        key=lambda item: int(item.get("icon_size") or tech_icon_size or 64),
    )
    if layer.get("scale") not in (None, 1, 1.0):
        warnings.append("existing_scale")
    shift = layer.get("shift")
    if shift not in (None, [0, 0], (0, 0)):
        warnings.append("existing_shift")
    return layer, warnings


def audit(
    dump: dict,
    mods_dir: Path,
    factorio_data: Path | None,
    decisions: dict[str, bool | None] | None = None,
    target_ratio: float = TARGET_RATIO,
    include_space_locations: bool = False,
) -> list[Entry]:
    planets = dump.get("planet", {})
    space_locations = dump.get("space-location", {})
    techs = dump.get("technology", {})
    decisions = decisions or {}

    entries = []
    for tech_name, tech in sorted(techs.items()):
        locations = []
        for effect in tech.get("effects") or []:
            if effect.get("type") == "unlock-space-location":
                location = effect.get("space_location")
                if location:
                    locations.append(location)
        planet_locations = [loc for loc in locations if loc in planets]
        if not planet_locations and not include_space_locations:
            continue
        if not planet_locations and not any(loc in space_locations for loc in locations):
            continue

        layers = tech.get("icons")
        if not layers:
            if tech.get("icon"):
                layers = [{"icon": tech["icon"], "icon_size": tech.get("icon_size")}]
            else:
                continue
        tech_icon_size = tech.get("icon_size")
        primary, warnings = primary_layer(layers, tech_icon_size)
        icon = str(primary.get("icon") or "")
        icon_size = int(primary.get("icon_size") or tech_icon_size or 64)
        mod, _ = split_path(icon)

        has_shadow = any(
            "planet-technology.png" in str(layer.get("icon") or "")
            for layer in layers
        )
        is_moon = any(MOON_SYMBOL in str(layer.get("icon") or "") for layer in layers)

        image = load_image(icon, mods_dir, factorio_data)
        if image is None:
            warnings.append("icon_not_found")
            disc_px = icon_size
        else:
            disc_px, centre_x, _, cropped = measure_icon(image, icon_size)
            if cropped:
                warnings.append("mipmap_cropped")
            measured_size = icon_size
            if not cropped and image.width != icon_size:
                warnings.append("image_size_mismatch")
                measured_size = image.width
            if abs(centre_x - measured_size / 2) > measured_size * 0.05:
                warnings.append("off_centre_disc")
            if disc_px <= 0:
                warnings.append("empty_icon")
                disc_px = icon_size

        fraction = disc_px / icon_size if icon_size else 1.0
        scale = target_ratio / fraction if fraction else target_ratio
        baked = decisions.get(tech_name)
        needs = None if baked is None else (not baked and not has_shadow)
        if has_shadow:
            needs = False

        entries.append(
            Entry(
                tech=tech_name,
                locations=locations,
                kind="moon" if is_moon else "planet",
                mod=mod,
                icon=icon,
                icon_size=icon_size,
                disc_px=disc_px,
                disc_fraction=fraction,
                suggested_scale=scale,
                helper="technology_icon_moon" if is_moon else DEFAULT_HELPER,
                has_planetslib_shadow=has_shadow,
                baked_shadow=baked,
                needs_shadow=needs,
                warnings=warnings,
            )
        )
    return entries


def print_markdown(entries: Iterable[Entry]) -> None:
    print(
        "| Technology | Mod | Kind | Size | Disc | Scale | PlanetsLib shadow | Baked shadow | Needs shadow |"
    )
    print("| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |")
    for entry in entries:
        baked = "-" if entry.baked_shadow is None else ("yes" if entry.baked_shadow else "no")
        needs = "-" if entry.needs_shadow is None else ("yes" if entry.needs_shadow else "no")
        shadow = "yes" if entry.has_planetslib_shadow else "no"
        print(
            f"| `{entry.tech}` | {entry.mod} | {entry.kind} | {entry.icon_size}px | "
            f"{entry.disc_px}px | {entry.suggested_scale:.3f} | {shadow} | {baked} | {needs} |"
        )


def load_decisions(path: Path | None) -> dict[str, bool | None]:
    if path is None or not path.is_file():
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"could not read decisions file {path}: {exc}")
    if not isinstance(data, dict):
        fail(f"decisions file {path} must contain a JSON object")
    return {str(key): value for key, value in data.items()}


def write_decisions(path: Path, entries: Iterable[Entry], existing: dict) -> None:
    merged = dict(existing)
    for entry in entries:
        merged.setdefault(entry.tech, entry.baked_shadow)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(dict(sorted(merged.items())), handle, indent=2)
        handle.write("\n")


def self_test() -> int:
    from PIL import ImageDraw

    with tempfile.TemporaryDirectory(prefix="planetslib-icon-audit-") as temp:
        root = Path(temp)
        mods = root / "mods"
        mod_root = mods / "TestMod_1.0.0"
        graphics = mod_root / "graphics"
        graphics.mkdir(parents=True)
        (mod_root / "info.json").write_text('{"name":"TestMod","version":"1.0.0"}')

        image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.ellipse((3, 3, 252, 252), fill=(120, 80, 60, 255))
        image.save(graphics / "icon.png")

        moon_image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        draw = ImageDraw.Draw(moon_image)
        draw.ellipse((10, 10, 245, 245), fill=(180, 180, 180, 255))
        moon_image.save(graphics / "moon.png")

        dump = {
            "planet": {"test-planet": {}},
            "space-location": {"test-orbit": {}},
            "technology": {
                "planet-discovery-test": {
                    "icons": [
                        {"icon": "__TestMod__/graphics/icon.png", "icon_size": 256},
                        {
                            "icon": "__core__/graphics/icons/technology/constants/constant-planet.png",
                            "icon_size": 128,
                        },
                    ],
                    "effects": [
                        {
                            "type": "unlock-space-location",
                            "space_location": "test-planet",
                        }
                    ],
                },
                "planet-discovery-moon": {
                    "icons": [
                        {"icon": "__TestMod__/graphics/moon.png", "icon_size": 256},
                        {
                            "icon": "__PlanetsLib__/graphics/icons/moon-technology-symbol.png",
                            "icon_size": 128,
                        },
                    ],
                    "effects": [
                        {
                            "type": "unlock-space-location",
                            "space_location": "test-planet",
                        }
                    ],
                },
                "planet-discovery-orbit": {
                    "icons": [
                        {"icon": "__TestMod__/graphics/icon.png", "icon_size": 256}
                    ],
                    "effects": [
                        {
                            "type": "unlock-space-location",
                            "space_location": "test-orbit",
                        }
                    ],
                },
            },
        }

        entries = audit(dump, mods, None)
        assert len(entries) == 2, [entry.tech for entry in entries]
        by_tech = {entry.tech: entry for entry in entries}
        planet = by_tech["planet-discovery-test"]
        assert planet.mod == "TestMod"
        assert planet.icon_size == 256
        assert planet.disc_px == 250, planet.disc_px
        assert abs(planet.suggested_scale - (TARGET_RATIO * 256 / 250)) < 1e-9
        assert planet.has_planetslib_shadow is False
        assert planet.needs_shadow is None
        assert planet.helper == "technology_icon_planet"

        moon = by_tech["planet-discovery-moon"]
        assert moon.kind == "moon", moon.kind
        assert moon.helper == "technology_icon_moon", moon.helper
        assert moon.disc_px == 236, moon.disc_px

        decisions = {"planet-discovery-test": True}
        decided = audit(dump, mods, None, decisions=decisions)
        assert {e.tech: e for e in decided}["planet-discovery-test"].needs_shadow is False

        # A zip-packaged icon must resolve too.
        zip_path = mods / "ZippedMod_2.0.0.zip"
        with zipfile.ZipFile(zip_path, "w") as handle:
            buffer = io.BytesIO()
            image.save(buffer, format="PNG")
            handle.writestr("ZippedMod_2.0.0/graphics/icon.png", buffer.getvalue())
        dump["technology"]["planet-discovery-test"]["icons"][0]["icon"] = (
            "__ZippedMod__/graphics/icon.png"
        )
        zipped = audit(dump, mods, None)
        zipped_test = {entry.tech: entry for entry in zipped}["planet-discovery-test"]
        assert zipped_test.mod == "ZippedMod", zipped_test.mod
        assert zipped_test.disc_px == 250, zipped_test.disc_px

    print("audit_planet_tech_icons.py self-test: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Audit planet/moon discovery technology icons for shadow coverage.",
    )
    parser.add_argument("--dump", help="Factorio data-raw-dump.json")
    parser.add_argument("--mods-dir", help="Factorio mod directory")
    parser.add_argument("--factorio-data", help="Factorio data directory (for vanilla icons)")
    parser.add_argument("--mod", action="append", help="only report this mod namespace; repeatable")
    parser.add_argument(
        "--exclude-tech",
        action="append",
        default=[],
        help="exclude this technology name; repeatable",
    )
    parser.add_argument(
        "--target-ratio",
        type=float,
        default=TARGET_RATIO,
        help="shadow ellipse width / planet disc width (default: 183/216)",
    )
    parser.add_argument("--decisions", help="JSON file of baked-shadow decisions")
    parser.add_argument("--out", help="write campaign JSON to this file")
    parser.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="stdout format",
    )
    parser.add_argument(
        "--include-space-locations",
        action="store_true",
        help="also include technologies that only unlock non-planet space locations",
    )
    parser.add_argument("--self-test", action="store_true", help="run local assertions and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.dump:
        fail("provide --dump FILE")
    if not args.mods_dir:
        fail("provide --mods-dir DIR")

    try:
        with open(args.dump, encoding="utf-8") as handle:
            dump = json.load(handle)
    except OSError as exc:
        fail(f"could not read {args.dump}: {exc}")
    except json.JSONDecodeError as exc:
        fail(f"{args.dump} is not valid JSON: {exc}")

    decisions = load_decisions(Path(args.decisions) if args.decisions else None)
    entries = audit(
        dump,
        Path(args.mods_dir),
        Path(args.factorio_data) if args.factorio_data else None,
        decisions=decisions,
        target_ratio=args.target_ratio,
        include_space_locations=args.include_space_locations,
    )
    if args.mod:
        wanted = set(args.mod)
        entries = [entry for entry in entries if entry.mod in wanted]
    if args.exclude_tech:
        excluded = set(args.exclude_tech)
        entries = [entry for entry in entries if entry.tech not in excluded]

    if args.decisions:
        write_decisions(Path(args.decisions), entries, decisions)
    if args.out:
        payload = {
            "meta": {
                "dump": args.dump,
                "mods_dir": args.mods_dir,
                "factorio_data": args.factorio_data,
                "target_ratio": args.target_ratio,
            },
            "entries": [entry.as_dict() for entry in entries],
        }
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")

    if args.format == "json":
        print_json = {"entries": [entry.as_dict() for entry in entries]}
        print(json.dumps(print_json, indent=2))
    else:
        print_markdown(entries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
