#!/usr/bin/env python3
"""Run PlanetsLib's FUnit scenarios against the current working tree.

This automates the local headless recipe documented in
test-mods/planetslib-funit-data/tests/README.md:

* package PlanetsLib and the companion test mods from the working tree, so
  uncommitted changes are tested;
* run the base / Space Age matrix with entity replacements on and off;
* stop Factorio after FUnit's ``====END====`` signal;
* parse the reports and print a compact summary.

The repository is never modified. Everything is written to --run-dir
(default: /tmp/opencode/planetslib-funit).

Examples:
    helper_scripts/run_funit_local.py --factorio /opt/factorio_space_age_21 \\
        --funit-zip /path/to/funit_1.1.0.zip

    helper_scripts/run_funit_local.py --scenario space-age --no-build
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
import zipfile
from pathlib import Path
from typing import NoReturn, Optional

REPO = Path(__file__).resolve().parent.parent
TEST_MOD = REPO / "test-mods" / "planetslib-funit-data"
SETTINGS_MOD = REPO / "test-mods" / "planetslib-funit-settings"
DEFAULT_RUN_DIR = Path("/tmp/opencode/planetslib-funit")

SCENARIOS = {
    "base": {"space_age": False, "replacements": True},
    "base-no-replacements": {"space_age": False, "replacements": False},
    "space-age": {"space_age": True, "replacements": True},
    "space-age-no-replacements": {"space_age": True, "replacements": False},
}

ROOT_SKIP_DIRS = {
    ".git",
    ".github",
    ".opencode",
    "artifacts",
    "docs",
    "docs-source",
    "helper_scripts",
    "node_modules",
    "test-mods",
    "venv",
    ".venv",
    "__pycache__",
    ".idea",
    ".vscode",
}
SKIP_FILE_SUFFIXES = {".pyc", ".pyo", ".zip"}
SKIP_FILE_NAMES = {".DS_Store", "opencode.json"}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def resolve_factorio(value: Optional[str]) -> Path:
    candidates = []
    if value:
        candidates.append(Path(value))
    if os.environ.get("FACTORIO_DIR"):
        candidates.append(Path(os.environ["FACTORIO_DIR"]))
    candidates.extend([Path("/opt/factorio_space_age_21"), Path("/opt/factorio")])

    for candidate in candidates:
        candidate = candidate.expanduser().resolve()
        if (candidate / "bin/x64/factorio").is_file() and (candidate / "data").is_dir():
            return candidate

    executable = shutil.which("factorio")
    if executable:
        candidate = Path(executable).resolve().parent.parent
        if (candidate / "data").is_dir():
            return candidate

    fail(
        "could not find a Factorio install with bin/x64/factorio and data/. "
        "Pass --factorio /path/to/factorio or set FACTORIO_DIR."
    )


def find_funit_zip(explicit: Optional[str], run_dir: Path) -> Path:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not path.is_file():
            fail(f"FUnit zip not found: {path}")
        return path

    candidates = []
    for directory in (
        run_dir / "mods",
        Path.home() / ".factorio" / "mods",
        REPO,
        Path("/tmp/opencode/funit-run/mods"),
    ):
        if directory.is_dir():
            candidates.extend(directory.glob("funit_*.zip"))

    if not candidates:
        fail(
            "could not find a funit_*.zip. Download FUnit and pass --funit-zip, "
            "or put it in ~/.factorio/mods."
        )
    return max(candidates, key=lambda path: path.stat().st_mtime).resolve()


def read_version(info_json: Path) -> str:
    try:
        version = json.loads(info_json.read_text(encoding="utf-8"))["version"]
    except (OSError, KeyError, json.JSONDecodeError) as error:
        fail(f"could not read a version from {info_json}: {error}")
    if not isinstance(version, str):
        fail(f"version in {info_json} is not a string")
    return version


def build_zip(source: Path, prefix: str, destination: Path, skip_dirs: set[str]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        destination.unlink()

    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, dirnames, filenames in os.walk(source):
            root_path = Path(root)
            dirnames[:] = sorted(
                name for name in dirnames if name not in skip_dirs and name not in SKIP_FILE_NAMES
            )
            for name in sorted(filenames):
                path = root_path / name
                if name in SKIP_FILE_NAMES or path.suffix in SKIP_FILE_SUFFIXES:
                    continue
                relative = path.relative_to(source)
                archive.write(path, f"{prefix}/{relative.as_posix()}")


def write_config(config: Path, factorio: Path, write_data: Path) -> None:
    write_data.mkdir(parents=True, exist_ok=True)
    config.write_text(
        "[path]\n"
        f"read-data={factorio / 'data'}\n"
        f"write-data={write_data}\n",
        encoding="utf-8",
    )


def write_server_settings(destination: Path) -> None:
    settings = json.loads((TEST_MOD / "test" / "server-settings.json").read_text(encoding="utf-8"))
    settings["username"] = "funit"
    settings["token"] = ""
    settings["auto_pause"] = False
    settings["autosave_interval"] = 0
    settings["visibility"] = {"public": False, "lan": False}
    destination.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def write_player_data(destination: Path) -> None:
    destination.write_text(
        json.dumps({"service-username": "funit", "service-token": ""}, indent=2) + "\n",
        encoding="utf-8",
    )


def write_mod_list(path: Path, space_age: bool, replacements: bool) -> None:
    mods = [
        {"name": "base", "enabled": True},
        {"name": "funit", "enabled": True},
        {"name": "PlanetsLib", "enabled": True},
        {"name": "planetslib-funit-data", "enabled": True},
        {"name": "space-age", "enabled": space_age},
        {"name": "quality", "enabled": space_age},
        {"name": "elevated-rails", "enabled": space_age},
        {"name": "recycler", "enabled": True},
        {"name": "planetslib-funit-settings", "enabled": not replacements},
    ]
    path.write_text(json.dumps({"mods": mods}, indent=2) + "\n", encoding="utf-8")


def terminate(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        process.terminate()
    else:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except ProcessLookupError:
            return
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            process.kill()
        else:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait(timeout=5)


def run_scenario(
    name: str,
    options: dict,
    factorio: Path,
    run_dir: Path,
    config: Path,
    server_settings: Path,
    timeout: int,
    quiet: bool,
) -> dict:
    mods_dir = run_dir / "mods"
    script_output = run_dir / "factorio" / "script-output"
    logs_dir = run_dir / "logs"
    reports_dir = run_dir / "reports"

    write_mod_list(mods_dir / "mod-list.json", options["space_age"], options["replacements"])
    try:
        (mods_dir / "mod-settings.dat").unlink()
    except FileNotFoundError:
        pass
    for old_report in script_output.glob("funit-report-*.json"):
        old_report.unlink()

    log_path = logs_dir / f"{name}.log"
    command = [
        str(factorio / "bin" / "x64" / "factorio"),
        "--config",
        str(config),
        "--mod-directory",
        str(mods_dir),
        "--start-server-load-scenario",
        "funit",
        "--server-settings",
        str(server_settings),
    ]

    if not quiet:
        print(f"[{name}] running...", flush=True)

    end_seen = threading.Event()
    started = time.monotonic()
    with log_path.open("w", encoding="utf-8", errors="replace") as log:

        def read_output(pipe):
            for line in pipe:
                log.write(line)
                log.flush()
                if "====END====" in line:
                    end_seen.set()

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            start_new_session=(os.name != "nt"),
        )
        assert process.stdout is not None
        reader = threading.Thread(target=read_output, args=(process.stdout,), daemon=True)
        reader.start()

        deadline = started + timeout
        while time.monotonic() < deadline:
            if end_seen.wait(0.2):
                break
            if process.poll() is not None:
                end_seen.wait(0.5)
                break

        timed_out = not end_seen.is_set() and process.poll() is None
        terminate(process)
        reader.join(timeout=5)

    if timed_out:
        return {
            "ok": False,
            "name": name,
            "tests": 0,
            "failures": [],
            "errors": [],
            "skipped": 0,
            "note": f"timed out after {timeout}s without ====END==== (log: {log_path})",
        }

    report_files = sorted(script_output.glob("funit-report-*.json"))
    if not report_files:
        return {
            "ok": False,
            "name": name,
            "tests": 0,
            "failures": [],
            "errors": [],
            "skipped": 0,
            "note": f"no FUnit report was written (log: {log_path})",
        }

    report_path = report_files[-1]
    reports_dir.mkdir(parents=True, exist_ok=True)
    saved_report = reports_dir / f"{name}.json"
    shutil.copyfile(report_path, saved_report)
    try:
        report = json.loads(saved_report.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return {
            "ok": False,
            "name": name,
            "tests": 0,
            "failures": [],
            "errors": [],
            "skipped": 0,
            "note": f"could not parse {saved_report}: {error}",
        }

    testcases = report.get("testcases", [])
    failures = [case for case in testcases if case.get("failure")]
    errors = [case for case in testcases if case.get("error")]
    skipped = [case for case in testcases if case.get("skipped")]
    return {
        "ok": not failures and not errors,
        "name": name,
        "tests": len(testcases),
        "failures": failures,
        "errors": errors,
        "skipped": len(skipped),
        "note": f"log: {log_path}",
    }


def short_message(case: dict) -> str:
    message = case.get("failure") or case.get("error") or ""
    if isinstance(message, dict):
        message = message.get("message", json.dumps(message))
    return str(message).splitlines()[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--factorio", help="Factorio install directory (contains bin/x64/factorio and data/)")
    parser.add_argument("--funit-zip", help="Path to funit_*.zip")
    parser.add_argument("--run-dir", type=Path, default=DEFAULT_RUN_DIR, help=f"Scratch directory (default: {DEFAULT_RUN_DIR})")
    parser.add_argument(
        "--scenario",
        action="append",
        choices=sorted(SCENARIOS),
        help="Run only this scenario (repeatable). Default: all four.",
    )
    parser.add_argument("--timeout", type=int, default=300, help="Per-scenario timeout in seconds (default: 300)")
    parser.add_argument("--no-build", action="store_true", help="Reuse the mod zips already in --run-dir/mods")
    parser.add_argument("--quiet", action="store_true", help="Only print the final summary")
    args = parser.parse_args()

    factorio = resolve_factorio(args.factorio)
    run_dir = args.run_dir.expanduser().resolve()
    funit_zip = find_funit_zip(args.funit_zip, run_dir)
    selected = args.scenario or list(SCENARIOS)

    run_dir.mkdir(parents=True, exist_ok=True)
    mods_dir = run_dir / "mods"
    mods_dir.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(run_dir / "factorio", ignore_errors=True)
    shutil.rmtree(run_dir / "logs", ignore_errors=True)
    shutil.rmtree(run_dir / "reports", ignore_errors=True)

    scenario_dir = run_dir / "factorio" / "scenarios" / "funit"
    scenario_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(TEST_MOD / "tests" / "scenario", scenario_dir)
    (run_dir / "factorio" / "script-output").mkdir(parents=True, exist_ok=True)
    (run_dir / "logs").mkdir(parents=True, exist_ok=True)
    (run_dir / "reports").mkdir(parents=True, exist_ok=True)

    config = run_dir / "config.ini"
    write_config(config, factorio, run_dir / "factorio")
    server_settings = run_dir / "server-settings.json"
    write_server_settings(server_settings)
    write_player_data(run_dir / "factorio" / "player-data.json")

    if not args.no_build:
        for old_zip in mods_dir.glob("PlanetsLib_*.zip"):
            old_zip.unlink()
        for old_zip in mods_dir.glob("planetslib-funit-data_*.zip"):
            old_zip.unlink()
        for old_zip in mods_dir.glob("planetslib-funit-settings_*.zip"):
            old_zip.unlink()

        mod_version = read_version(REPO / "info.json")
        test_version = read_version(TEST_MOD / "info.json")
        settings_version = read_version(SETTINGS_MOD / "info.json")

        build_zip(REPO, f"PlanetsLib_{mod_version}", mods_dir / f"PlanetsLib_{mod_version}.zip", ROOT_SKIP_DIRS)
        build_zip(
            TEST_MOD,
            f"planetslib-funit-data_{test_version}",
            mods_dir / f"planetslib-funit-data_{test_version}.zip",
            {"node_modules", ".git", "__pycache__"},
        )
        build_zip(
            SETTINGS_MOD,
            f"planetslib-funit-settings_{settings_version}",
            mods_dir / f"planetslib-funit-settings_{settings_version}.zip",
            {"node_modules", ".git", "__pycache__"},
        )

    mods_funit = mods_dir / funit_zip.name
    for old_funit in mods_dir.glob("funit_*.zip"):
        if old_funit.resolve() != funit_zip:
            old_funit.unlink()
    if not mods_funit.exists() or mods_funit.resolve() != funit_zip:
        shutil.copyfile(funit_zip, mods_funit)
    if not any(mods_dir.glob("PlanetsLib_*.zip")):
        fail(f"no PlanetsLib zip in {mods_dir}; rerun without --no-build")
    if not any(mods_dir.glob("planetslib-funit-data_*.zip")):
        fail(f"no planetslib-funit-data zip in {mods_dir}; rerun without --no-build")
    if not any(mods_dir.glob("planetslib-funit-settings_*.zip")):
        fail(f"no planetslib-funit-settings zip in {mods_dir}; rerun without --no-build")

    results = []
    for name in selected:
        results.append(
            run_scenario(
                name,
                SCENARIOS[name],
                factorio,
                run_dir,
                config,
                server_settings,
                args.timeout,
                args.quiet,
            )
        )

    print()
    print(f"{'scenario':<32} {'tests':>5} {'fail':>5} {'error':>5} {'skip':>5}")
    print("-" * 62)
    failed = False
    for result in results:
        print(
            f"{result['name']:<32} {result['tests']:>5} "
            f"{len(result['failures']):>5} {len(result['errors']):>5} {result['skipped']:>5}"
        )
        if not result["ok"]:
            failed = True
        for case in result["failures"] + result["errors"]:
            print(f"  - {case.get('name', '<unnamed>')}: {short_message(case)}")
        if result.get("note", "").startswith(("timed out", "no FUnit", "could not parse")):
            print(f"  ! {result['note']}")

    print()
    print(f"Reports: {run_dir / 'reports'}")
    print(f"Logs:    {run_dir / 'logs'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
