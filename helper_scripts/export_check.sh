#!/usr/bin/env bash
# export_check.sh - verify the release zip boundary in .gitattributes.
#
# Development-only files must be marked `export-ignore`, while runtime files
# must not be. This catches a missing or non-recursive export rule before a
# release without building an archive.
#
# Usage:
#   helper_scripts/export_check.sh
#   helper_scripts/export_check.sh --ref HEAD
#   helper_scripts/export_check.sh --json
#   helper_scripts/export_check.sh --require-path .opencode/agents/self-learn.md
#
# Exit status:
#   0  all checks passed
#   1  a check failed
#   2  usage error
#
# Requires: bash and python3 (for attribute parsing and JSON output).

set -euo pipefail

PROG="$(basename "$0")"
REPO=""
REF=""
REQUIRE_PATH=""
JSON_OUTPUT=0

usage() {
  cat <<EOF
Usage:
  $PROG [options]

Check that development files are excluded from release exports and runtime
files are included.

Options:
  --ref REF               Check the tree at REF instead of the working tree.
  --require-path PATH     Assert that PATH is not export-ignored. This is the
                          negative self-test: passing a development path such
                          as .opencode/agents/self-learn.md must exit 1.
  --json                  Emit a machine-readable JSON report.
  --repo DIR              Repository root. Defaults to the git top-level
                          directory, then the current directory.
  -h, --help              Show this help and exit.

Exit status:
  0  all checks passed
  1  a check failed
  2  usage error

Examples:
  $PROG
  $PROG --ref HEAD
  $PROG --require-path .opencode/agents/self-learn.md
  $PROG --json
EOF
}

die() {
  printf '%s: error: %s\n' "$PROG" "$*" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --ref)
      [ "$#" -ge 2 ] || die "--ref requires a value"
      REF="$2"
      shift 2
      ;;
    --ref=*)
      REF="${1#*=}"
      shift
      ;;
    --require-path)
      [ "$#" -ge 2 ] || die "--require-path requires a value"
      REQUIRE_PATH="$2"
      shift 2
      ;;
    --require-path=*)
      REQUIRE_PATH="${1#*=}"
      shift
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --repo=*)
      REPO="${1#*=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      die "unexpected argument: $1"
      ;;
  esac
done
[ "$#" -eq 0 ] || die "unexpected argument: $1"

PROG="$PROG" REPO="$REPO" REF="$REF" REQUIRE_PATH="$REQUIRE_PATH" JSON_OUTPUT="$JSON_OUTPUT" \
  exec python3 - <<'PY'
import json
import os
import subprocess
import sys

PROG = os.environ["PROG"]
REPO_ARG = os.environ["REPO"]
REF = os.environ["REF"]
REQUIRE_PATH = os.environ["REQUIRE_PATH"]
JSON_OUTPUT = os.environ["JSON_OUTPUT"] == "1"

DEV_PREFIXES = (
    ".claude/",
    ".github/",
    ".opencode/",
    ".vscode/",
    "README_images/",
    "docs/",
    "docs-source/",
    "docs_templates/",
    "graphics/greenhouse/preview/",
    "graphics/mipgenerator/",
    "graphics/research-center/",
    "helper_scripts/",
    "test-mods/",
)

DEV_FILES = {
    ".gitattributes",
    ".gitignore",
    "AGENTS.md",
    "CLAUDE.md",
    "archive.sh",
    "bump_version.sh",
    "config.ld",
    "update_documentation.sh",
}

PRODUCTION_FILES = {
    "api.lua",
    "control.lua",
    "data-final-fixes.lua",
    "data-updates.lua",
    "data.lua",
    "info.json",
    "settings.lua",
}

checks = []


def add(name, status, detail=""):
    checks.append({"name": name, "status": status, "detail": detail})


def run_git(args, stdin=None):
    return subprocess.run(
        ["git", "-C", repo] + args,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def fail_now(message):
    add("repository", "FAIL", message)
    report()


def report():
    counts = {
        "pass": sum(1 for check in checks if check["status"] == "PASS"),
        "fail": sum(1 for check in checks if check["status"] == "FAIL"),
        "warn": sum(1 for check in checks if check["status"] == "WARN"),
    }
    status = "FAIL" if counts["fail"] else "OK"

    if JSON_OUTPUT:
        print(
            json.dumps(
                {
                    "repo": repo,
                    "ref": REF or None,
                    "require_path": REQUIRE_PATH or None,
                    "status": status,
                    "ok": status == "OK",
                    "summary": counts,
                    "checks": checks,
                },
                indent=2,
            )
        )
    else:
        for check in checks:
            print("[%s] %s: %s" % (check["status"], check["name"], check["detail"]))
        print(
            "\nSummary: %s (%d passed, %d failed, %d warnings)"
            % (status, counts["pass"], counts["fail"], counts["warn"])
        )

    sys.exit(0 if status == "OK" else 1)


if REPO_ARG:
    repo = os.path.abspath(REPO_ARG)
else:
    probe = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    repo = probe.stdout.strip() if probe.returncode == 0 and probe.stdout.strip() else os.getcwd()
repo = os.path.realpath(repo)

if not os.path.isdir(repo):
    fail_now("repository directory does not exist: %s" % repo)

inside = run_git(["rev-parse", "--is-inside-work-tree"])
if inside.returncode != 0:
    fail_now("not a git working tree: %s" % repo)

if REF:
    resolved = run_git(["rev-parse", "--verify", REF + "^{tree}"])
    if resolved.returncode != 0:
        fail_now("ref does not resolve to a tree: %s" % REF)
    add("ref", "PASS", REF)
else:
    add("ref", "PASS", "working tree")

if os.path.isfile(os.path.join(repo, ".gitattributes")):
    add("gitattributes", "PASS", ".gitattributes exists")
else:
    add("gitattributes", "FAIL", ".gitattributes is missing")

if REF:
    listing = run_git(["ls-tree", "-r", "--name-only", "-z", REF])
else:
    listing = run_git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
if listing.returncode != 0:
    fail_now("could not list files: %s" % listing.stderr.decode("utf-8", "replace").strip())
files = [path for path in listing.stdout.decode("utf-8", "replace").split("\0") if path]

if not files:
    fail_now("no files found in the selected tree")

attr_args = ["check-attr", "--stdin", "-z", "export-ignore", "--"]
if REF:
    attr_args = ["check-attr", "--source", REF, "--stdin", "-z", "export-ignore", "--"]
attributes = run_git(attr_args, stdin=("\0".join(files) + "\0").encode("utf-8"))
if attributes.returncode != 0:
    fail_now("git check-attr failed: %s" % attributes.stderr.decode("utf-8", "replace").strip())

records = attributes.stdout.decode("utf-8", "replace").split("\0")
values = {}
for index in range(0, len(records) - 2, 3):
    path = records[index]
    attr = records[index + 1]
    value = records[index + 2]
    if path and attr == "export-ignore":
        values[path] = value

missing_dev = []
for path in files:
    if path in DEV_FILES or path.startswith(DEV_PREFIXES):
        if values.get(path) != "set":
            missing_dev.append(path)

if missing_dev:
    preview = ", ".join(missing_dev[:10])
    if len(missing_dev) > 10:
        preview += ", ..."
    add(
        "dev-files-ignored",
        "FAIL",
        "%d development file(s) lack export-ignore: %s" % (len(missing_dev), preview),
    )
else:
    add("dev-files-ignored", "PASS", "all development paths are export-ignored")

marked_runtime = []
for path in files:
    if path in PRODUCTION_FILES or path.startswith("locale/en/"):
        if values.get(path) == "set":
            marked_runtime.append(path)

if marked_runtime:
    add(
        "runtime-files-included",
        "FAIL",
        "runtime file(s) are export-ignored: %s" % ", ".join(marked_runtime[:10]),
    )
else:
    add("runtime-files-included", "PASS", "runtime files and locale/en are not export-ignored")

missing_production = sorted(path for path in PRODUCTION_FILES if path not in files)
if missing_production:
    add(
        "runtime-files-present",
        "WARN",
        "runtime file(s) not present in this tree: %s" % ", ".join(missing_production),
    )
else:
    add("runtime-files-present", "PASS", "all expected runtime files are present")

if REQUIRE_PATH:
    required = REQUIRE_PATH.replace("\\", "/")
    if not os.path.isabs(required):
        required = os.path.join(repo, required)
    absolute = os.path.realpath(required)
    if absolute.startswith(repo + os.sep):
        required = os.path.relpath(absolute, repo).replace("\\", "/")
    if values.get(required) == "set":
        add(
            "required-path",
            "FAIL",
            "required path is export-ignored: %s" % required,
        )
    else:
        add(
            "required-path",
            "PASS",
            "%s is not export-ignored (attribute: %s)"
            % (required, values.get(required, "unspecified")),
        )

report()
PY
