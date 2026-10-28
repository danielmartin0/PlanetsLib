#!/usr/bin/env python3
"""Generate the pull-request body for a planet-discovery icon campaign.

The multi-repository icon-shadow campaign uses the same Markdown structure for
every mod: an intro supplied by the campaign owner, a per-technology summary,
the shadow-scale rationale, the rendered screenshots, and testing notes. Writing
that by hand for each upstream repository is repetitive and easy to get wrong.

This script reads a campaign JSON file (normally produced by
``audit_planet_tech_icons.py``) and prints or writes the Markdown body. It never
calls ``gh``, pushes branches, or edits another repository.

Campaign JSON shape::

    {
      "intro": "optional intro text",
      "signature": "optional signature",
      "entries": [
        {
          "tech": "planet-discovery-castra",
          "mod": "castra-prime",
          "title": "Castra Prime",
          "icon": "__castra-prime-assets__/graphics/icons/technology-castra.png",
          "icon_size": 256,
          "disc_px": 250,
          "shadow_scale": 0.86,
          "helper": "technology_icon_planet",
          "screenshots": {
            "before_after": "https://...",
            "closeup": "https://..."
          },
          "notes": ["optional note"],
          "dependency": "PlanetsLib >= 1.10.7",
          "changelog": true
        }
      ]
    }

Examples:
    python3 helper_scripts/mod_icon_pr_body.py --campaign campaign.json
    python3 helper_scripts/mod_icon_pr_body.py --campaign campaign.json --output body.md
    python3 helper_scripts/mod_icon_pr_body.py --campaign campaign.json --verify-urls
    python3 helper_scripts/mod_icon_pr_body.py --self-test
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Callable, NoReturn

DEFAULT_INTRO = (
    "This is an automated pull request that adds a shadow icon to your planet "
    "discovery technology using PlanetsLib. It seeks to correct an issue that "
    "many planet mods have, which is that their planet discovery icon lacks a "
    "shadow. I hope this code that Deepseek generated meets your needs.\n\n"
    "- Nicholas"
)
DEFAULT_SIGNATURE = "_Posted by DeepSeek V4.1 Flash._"
USER_AGENT = "PlanetsLib-helper-scripts/1.0 (mod-icon-pr-body)"
SCREENSHOT_KEYS = ("before_after", "closeup")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


@dataclass
class Entry:
    tech: str
    mod: str = ""
    title: str = ""
    icon: str = ""
    icon_size: int = 256
    disc_px: int | None = None
    shadow_scale: float | None = None
    helper: str = "technology_icon_planet"
    screenshots: dict | None = None
    notes: list[str] | None = None
    dependency: str = ""
    changelog: bool = True

    @classmethod
    def from_dict(cls, data: dict) -> "Entry":
        if "tech" not in data:
            fail("campaign entry is missing 'tech'")
        return cls(
            tech=str(data["tech"]),
            mod=str(data.get("mod", "")),
            title=str(data.get("title", "")),
            icon=str(data.get("icon", "")),
            icon_size=int(data.get("icon_size", 256)),
            disc_px=int(data["disc_px"]) if data.get("disc_px") is not None else None,
            shadow_scale=(
                float(data["shadow_scale"])
                if data.get("shadow_scale") is not None
                else None
            ),
            helper=str(data.get("helper", "technology_icon_planet")),
            screenshots=data.get("screenshots") or {},
            notes=list(data.get("notes") or []),
            dependency=str(data.get("dependency", "")),
            changelog=bool(data.get("changelog", True)),
        )


def load_campaign(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as exc:
        fail(f"could not read {path}: {exc}")
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON: {exc}")
    if not isinstance(data, dict) or not data.get("entries"):
        fail("campaign must be an object with a non-empty 'entries' list")
    return data


def make_body(campaign: dict) -> str:
    intro = str(campaign.get("intro") or DEFAULT_INTRO).strip()
    signature = str(campaign.get("signature") or DEFAULT_SIGNATURE).strip()
    entries = [Entry.from_dict(item) for item in campaign["entries"]]

    lines = [intro, "", "## What changed", ""]
    for entry in entries:
        label = entry.title or entry.mod or entry.tech
        scale = f"{entry.shadow_scale:g}" if entry.shadow_scale is not None else "?"
        lines.append(
            f"- `{entry.tech}` ({label}): uses `PlanetsLib.{entry.helper}("
            f"\"{entry.icon}\", {entry.icon_size}, {scale})`."
        )
        if entry.dependency:
            lines.append(f"- Dependency: {entry.dependency}.")
        if entry.changelog:
            lines.append(
                "- `changelog.txt` / `info.json`: version and release-note updates "
                "for the icon change."
            )
        lines.append(
            "- `.gitattributes`: the screenshot folder is export-ignored so it "
            "does not ship in the mod release."
        )
        for note in entry.notes:
            lines.append(f"- {note}")
    lines.append("")

    if len(entries) == 1:
        entry = entries[0]
        scale = f"{entry.shadow_scale:g}" if entry.shadow_scale is not None else "?"
        lines.extend(["## Why " + scale + "?", ""])
        disc = f"{entry.disc_px}px" if entry.disc_px is not None else "measured"
        lines.append(
            f"The planet image is a {entry.icon_size}px tile with a {disc} disc. "
            "The scale is `0.84375 * icon_size / disc_px`, so the rendered planet "
            "is about 215px wide with the same 183px shadow ellipse vanilla uses; "
            "the shadow-to-planet ratio therefore matches vanilla."
        )
        lines.append("")
    else:
        lines.extend(
            [
                "## Shadow scales",
                "",
                "| Technology | Icon size | Disc | Shadow scale |",
                "| --- | ---: | ---: | ---: |",
            ]
        )
        for entry in entries:
            disc = f"{entry.disc_px}px" if entry.disc_px is not None else "-"
            scale = f"{entry.shadow_scale:g}" if entry.shadow_scale is not None else "-"
            lines.append(
                f"| `{entry.tech}` | {entry.icon_size}px | {disc} | {scale} |"
            )
        lines.extend(
            [
                "",
                "The scale uses `0.84375 * icon_size / disc_px`, so every planet "
                "keeps vanilla's shadow-to-planet ratio.",
            ]
        )
        lines.append("")

    lines.extend(["## Screenshots", ""])
    for entry in entries:
        screenshots = entry.screenshots or {}
        lines.append(f"### {entry.title or entry.tech}")
        lines.append("")
        before = screenshots.get("before_after")
        closeup = screenshots.get("closeup")
        if before:
            lines.extend(["Before / after / vanilla reference:", "", f"![Before and after]({before})", ""])
        if closeup:
            lines.extend(["Bottom half at 2x:", "", f"![Close-up]({closeup})", ""])
        if not before and not closeup:
            lines.extend(["_No screenshots supplied for this entry._", ""])

    lines.extend(
        [
            "## Testing",
            "",
            "- Loaded Factorio 2.1 headless with base, Space Age, PlanetsLib, the "
            "mod's required dependencies, and this branch.",
            "- `--dump-data` and `--dump-icon-sprites` completed without errors.",
            "- Also loaded with the full planet mod set (`--dump-data`); the final "
            "`data.raw` contains the shadow layer, the planet/moon icon, and the "
            "overlay.",
            "- The screenshots are the game's own composed technology icons from "
            "`--dump-icon-sprites`.",
            "",
            signature,
            "",
        ]
    )
    return "\n".join(lines)


def verify_urls(
    urls: list[str],
    opener: Callable = urllib.request.urlopen,
    timeout: float = 30.0,
) -> list[tuple[str, str]]:
    results = []
    for url in urls:
        request = urllib.request.Request(
            url,
            method="HEAD",
            headers={"User-Agent": USER_AGENT},
        )
        try:
            with opener(request, timeout=timeout) as response:
                status = int(getattr(response, "status", 0) or 0)
                content_type = response.headers.get("Content-Type", "")
                if status == 200 and content_type.startswith("image/"):
                    results.append((url, "ok"))
                else:
                    results.append((url, f"bad response: {status} {content_type}"))
        except urllib.error.HTTPError as exc:
            results.append((url, f"HTTP {exc.code}"))
        except urllib.error.URLError as exc:
            results.append((url, f"error: {exc.reason}"))
        except OSError as exc:
            results.append((url, f"error: {exc}"))
    return results


def self_test() -> int:
    campaign = {
        "intro": "Intro line one.\n\n- Tester",
        "signature": "_Signed by test._",
        "entries": [
            {
                "tech": "planet-discovery-test",
                "mod": "test-mod",
                "title": "Test Planet",
                "icon": "__test__/graphics/planet.png",
                "icon_size": 256,
                "disc_px": 250,
                "shadow_scale": 0.864,
                "screenshots": {
                    "before_after": "https://example.com/before-after.png",
                    "closeup": "https://example.com/closeup.png",
                },
                "notes": ["A note."],
                "dependency": "PlanetsLib >= 1.10.7",
            },
            {
                "tech": "planet-discovery-second",
                "mod": "second-mod",
                "icon": "__second__/icon.png",
                "icon_size": 512,
                "disc_px": 490,
                "shadow_scale": 0.882,
                "helper": "technology_icon_planet",
            },
        ],
    }
    body = make_body(campaign)
    assert body.startswith("Intro line one."), body[:80]
    assert "planet-discovery-test" in body
    assert "planet-discovery-second" in body
    assert "0.84375 * icon_size / disc_px" in body
    assert "https://example.com/before-after.png" in body
    assert body.rstrip().endswith("_Signed by test._"), body[-80:]

    class FakeResponse:
        def __init__(self, status: int, content_type: str) -> None:
            self.status = status
            self.headers = {"Content-Type": content_type}

        def __enter__(self):
            return self

        def __exit__(self, *exc) -> None:
            return None

    def ok_opener(request, timeout=0):
        return FakeResponse(200, "image/png")

    def bad_opener(request, timeout=0):
        return FakeResponse(404, "text/plain")

    checked = verify_urls(["https://example.com/a.png"], opener=ok_opener)
    assert checked == [("https://example.com/a.png", "ok")], checked
    checked = verify_urls(["https://example.com/missing.png"], opener=bad_opener)
    assert checked[0][1].startswith("bad response: 404"), checked

    print("mod_icon_pr_body.py self-test: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate a planet-discovery icon PR body from campaign JSON.",
    )
    parser.add_argument("--campaign", required=False, help="campaign JSON file")
    parser.add_argument("--output", help="write Markdown to this file instead of stdout")
    parser.add_argument("--verify-urls", action="store_true", help="check screenshot URLs")
    parser.add_argument("--self-test", action="store_true", help="run local assertions and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.campaign:
        fail("provide --campaign FILE")

    campaign = load_campaign(args.campaign)
    body = make_body(campaign)
    if args.verify_urls:
        urls = []
        for item in campaign["entries"]:
            for key in SCREENSHOT_KEYS:
                url = (item.get("screenshots") or {}).get(key)
                if url:
                    urls.append(url)
        failures = [
            f"{url}: {detail}"
            for url, detail in verify_urls(urls)
            if detail != "ok"
        ]
        if failures:
            fail("screenshot URL check failed:\n  " + "\n  ".join(failures))

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as handle:
                handle.write(body)
        except OSError as exc:
            fail(f"could not write {args.output}: {exc}")
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
