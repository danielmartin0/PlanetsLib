#!/usr/bin/env python3
"""Check static FUnit conventions that syntax checks and test runs cannot catch.

The checker is read-only and safe to run on pull-request checkouts. It verifies:

* every `planetslib_funit` seam in `control.lua` is listed in the test docs;
* every seam requested by a suite exists;
* every suite file is in `tests/suites/manifest.lua`, and vice versa;
* test IDs are unique across the suite;
* suites do not use vacuous `runner.assert(true, ...)` assertions or the
  global `before_each`/`after_each` hooks that would replace other suites'
  hooks.

Usage:
    python3 .github/scripts/check_funit_conventions.py
    python3 .github/scripts/check_funit_conventions.py --root /path/to/checkout
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import NoReturn

SCRIPT_ROOT = Path(__file__).resolve().parents[2]
CONTROL_PATH = Path("control.lua")
TEST_MOD = Path("test-mods/planetslib-funit-data")
SUITES_PATH = TEST_MOD / "tests" / "suites"
README_PATH = TEST_MOD / "tests" / "README.md"
AGENTS_PATH = TEST_MOD / "AGENTS.md"
MANIFEST_PATH = SUITES_PATH / "manifest.lua"

SEAM_DEFINITION_RE = re.compile(
    r"^\t\t([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b", re.MULTILINE
)
README_SEAM_RE = re.compile(r"`([A-Za-z_][A-Za-z0-9_]*)`")
AGENTS_SEAM_RE = re.compile(
    r'remote\.call\(\s*"planetslib_funit"\s*,\s*"([A-Za-z_][A-Za-z0-9_]*)"'
)
MANIFEST_ORDER_RE = re.compile(r"order\s*=\s*\{(.*?)\n\t*\}", re.DOTALL)
MANIFEST_NAME_RE = re.compile(r'"([^"]+)"')
TEST_NAME_RE = re.compile(r'runner\.test\(\s*"([^"]+)"')
REQUIRE_SEAM_RE = re.compile(
    r'require_seam\(\s*runner\s*,\s*"([A-Za-z_][A-Za-z0-9_]*)"'
)
SEAM_CALL_RE = re.compile(r'\bseam\(\s*"([A-Za-z_][A-Za-z0-9_]*)"')
REMOTE_CALL_RE = re.compile(
    r'remote\.call\(\s*"planetslib_funit"\s*,\s*"([A-Za-z_][A-Za-z0-9_]*)"'
)
FORBIDDEN_PATTERNS = (
    (re.compile(r"runner\.assert\(\s*true\b"), "runner.assert(true) is a vacuous assertion"),
    (re.compile(r"runner\.before_each\b"), "runner.before_each is a global hook; do not use it"),
    (re.compile(r"runner\.after_each\b"), "runner.after_each is a global hook; do not use it"),
)


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def read_text(root: Path, relative: Path) -> str:
    path = root / relative
    if not path.is_file():
        fail(f"required file not found: {relative}")
    return path.read_text(encoding="utf-8")


def brace_body(text: str, start: int, path: Path) -> tuple[str, int]:
    """Return the text inside the first brace at or after `start`."""
    brace_start = text.find("{", start)
    if brace_start < 0:
        fail(f"{path}: could not find the planetslib_funit interface table")
    depth = 0
    in_string: str | None = None
    escaped = False
    for index in range(brace_start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == in_string:
                in_string = None
            continue
        if char in ('"', "'"):
            in_string = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_start + 1 : index], brace_start + 1
    fail(f"{path}: unterminated planetslib_funit interface table")
    raise AssertionError("unreachable")


def parse_control_seams(root: Path, problems: list[tuple[str, int, str]]) -> set[str]:
    relative = CONTROL_PATH
    text = read_text(root, relative)
    marker = text.find('remote.add_interface("planetslib_funit"')
    if marker < 0:
        problems.append((str(relative), 1, "could not find the planetslib_funit remote interface"))
        return set()
    body, body_start = brace_body(text, marker, relative)
    seams = set(SEAM_DEFINITION_RE.findall(body))
    if not seams:
        problems.append((str(relative), line_number(text, body_start), "no seam functions found"))
    return seams


def parse_readme_seams(root: Path, problems: list[tuple[str, int, str]]) -> set[str]:
    text = read_text(root, README_PATH)
    marker = text.find("Available seam functions:")
    if marker < 0:
        problems.append((str(README_PATH), 1, "missing 'Available seam functions:' list"))
        return set()
    end = text.find("\n\n", marker)
    if end < 0:
        end = len(text)
    block = text[marker:end]
    seams = set(README_SEAM_RE.findall(block))
    if not seams:
        problems.append(
            (str(README_PATH), line_number(text, marker), "no seam names found in the seam list")
        )
    return seams


def parse_agents_seams(root: Path, problems: list[tuple[str, int, str]]) -> set[str]:
    text = read_text(root, AGENTS_PATH)
    matches = list(AGENTS_SEAM_RE.finditer(text))
    if not matches:
        problems.append((str(AGENTS_PATH), 1, "no planetslib_funit seam calls found"))
        return set()
    return {match.group(1) for match in matches}


def compare_seam_lists(
    control: set[str],
    documented: set[str],
    relative: Path,
    section_text: str,
    section_line: int,
    problems: list[tuple[str, int, str]],
) -> None:
    for name in sorted(control - documented):
        problems.append((str(relative), section_line, f"missing seam in documentation: {name}"))
    for name in sorted(documented - control):
        problems.append((str(relative), section_line, f"documented seam is not registered in control.lua: {name}"))


def parse_manifest(root: Path, problems: list[tuple[str, int, str]]) -> list[str]:
    text = read_text(root, MANIFEST_PATH)
    match = MANIFEST_ORDER_RE.search(text)
    if not match:
        problems.append((str(MANIFEST_PATH), 1, "could not find the order table"))
        return []
    names = MANIFEST_NAME_RE.findall(match.group(1))
    if not names:
        problems.append((str(MANIFEST_PATH), line_number(text, match.start()), "order table is empty"))
    return names


def suite_files(root: Path) -> list[Path]:
    suites_dir = root / SUITES_PATH
    if not suites_dir.is_dir():
        fail(f"required directory not found: {SUITES_PATH}")
    return sorted(
        path
        for path in suites_dir.glob("*.lua")
        if path.name not in {"manifest.lua", "support.lua"}
    )


def display(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def check_manifest(
    root: Path,
    manifest: list[str],
    files: list[Path],
    problems: list[tuple[str, int, str]],
) -> dict[str, Path]:
    by_name = {path.stem: path for path in files}
    for name in manifest:
        if name not in by_name:
            problems.append(
                (str(MANIFEST_PATH), 1, f"listed suite has no file: {name}.lua")
            )
    for name, path in by_name.items():
        if name not in manifest:
            problems.append((display(root, path), 1, "suite is not listed in tests/suites/manifest.lua"))
    return by_name


def check_suites(
    root: Path,
    control_seams: set[str],
    files: list[Path],
    problems: list[tuple[str, int, str]],
) -> tuple[int, dict[str, tuple[str, int]]]:
    seen_tests: dict[str, tuple[str, int]] = {}
    test_count = 0
    for path in files:
        relative = display(root, path)
        text = path.read_text(encoding="utf-8")
        for match in TEST_NAME_RE.finditer(text):
            name = match.group(1)
            line = line_number(text, match.start())
            test_count += 1
            if name in seen_tests:
                first_path, first_line = seen_tests[name]
                problems.append(
                    (relative, line, f"duplicate test ID '{name}' (first at {first_path}:{first_line})")
                )
            else:
                seen_tests[name] = (relative, line)

        for match in (
            list(REQUIRE_SEAM_RE.finditer(text))
            + list(SEAM_CALL_RE.finditer(text))
            + list(REMOTE_CALL_RE.finditer(text))
        ):
            name = match.group(1)
            if name not in control_seams:
                problems.append(
                    (
                        relative,
                        line_number(text, match.start()),
                        f"suite requests unknown planetslib_funit seam: {name}",
                    )
                )

        for index, line in enumerate(text.splitlines(), start=1):
            for pattern, message in FORBIDDEN_PATTERNS:
                if pattern.search(line):
                    problems.append((relative, index, message))
    return test_count, seen_tests


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Check static FUnit seam, manifest, ID and hook conventions."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=SCRIPT_ROOT,
        help="repository root (default: derived from this script)",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve()
    if not (root / CONTROL_PATH).is_file():
        fail(f"{root} does not look like the PlanetsLib repository (missing control.lua)")

    problems: list[tuple[str, int, str]] = []
    control_seams = parse_control_seams(root, problems)
    readme_seams = parse_readme_seams(root, problems)
    agents_seams = parse_agents_seams(root, problems)

    readme_text = read_text(root, README_PATH)
    readme_marker = readme_text.find("Available seam functions:")
    compare_seam_lists(
        control_seams,
        readme_seams,
        README_PATH,
        readme_text,
        line_number(readme_text, readme_marker) if readme_marker >= 0 else 1,
        problems,
    )

    agents_text = read_text(root, AGENTS_PATH)
    agents_marker = agents_text.find("### Runtime seams")
    compare_seam_lists(
        control_seams,
        agents_seams,
        AGENTS_PATH,
        agents_text,
        line_number(agents_text, agents_marker) if agents_marker >= 0 else 1,
        problems,
    )

    manifest = parse_manifest(root, problems)
    files = suite_files(root)
    check_manifest(root, manifest, files, problems)
    test_count, _ = check_suites(root, control_seams, files, problems)

    if problems:
        for path, line, message in sorted(set(problems)):
            print(f"{path}:{line}: {message}")
        print(f"\n{len(set(problems))} FUnit convention problem(s) found.")
        return 1

    print(
        f"FUnit conventions OK: {len(control_seams)} seams, "
        f"{len(files)} suites, {test_count} tests."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
