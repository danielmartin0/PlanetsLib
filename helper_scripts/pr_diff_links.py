#!/usr/bin/env python3
"""Generate commit-pinned GitHub file-diff links for a bugfix pull request.

The repository's bugfix PR format uses anchors of the form
``#diff-<sha256-of-repository-relative-path>``. Computing those by hand is
error-prone. This script prints them for every path changed by one commit.

The script is read-only: it only reads git metadata and prints Markdown or
JSON. It never checks out code, contacts the network, or executes a pull
request.

Examples:
    helper_scripts/pr_diff_links.py
    helper_scripts/pr_diff_links.py 32d86ea
    helper_scripts/pr_diff_links.py 32d86ea --format json
    helper_scripts/pr_diff_links.py origin/main --base origin/main
    helper_scripts/pr_diff_links.py 32d86ea --repo danielmartin0/PlanetsLib
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

REPO_ROOT = Path(__file__).resolve().parent.parent
GITHUB_REMOTE_RE = re.compile(
    r"^(?:"
    r"https?://(?:[^@/]+@)?github\.com/"
    r"|ssh://(?:[^@/]+@)?github\.com(?::\d+)?/"
    r"|git@github\.com:"
    r")([^/]+)/([^/]+?)(?:\.git)?/?$"
)
REPO_ARG_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def run_git(*args: str) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        fail("git is not installed")
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        fail(f"git {' '.join(args)} failed: {detail or 'unknown error'}")
    return result.stdout.strip()


def resolve_commit(revision: str) -> str:
    return run_git("rev-parse", "--verify", f"{revision}^{{commit}}")


def changed_paths(commit: str, base: str | None) -> list[str]:
    if base:
        resolve_commit(base)
        output = run_git("diff", "--name-only", "--find-renames", f"{base}...{commit}")
    else:
        parent = None
        try:
            parent = run_git("rev-parse", "--verify", f"{commit}^")
        except SystemExit:
            # Root commit: list the tree instead of diffing against a parent.
            parent = None
        if parent:
            output = run_git("diff", "--name-only", "--find-renames", parent, commit)
        else:
            output = run_git("ls-tree", "-r", "--name-only", commit)

    return sorted({line for line in output.splitlines() if line.strip()})


def infer_repo(explicit_repo: str | None) -> str:
    if explicit_repo:
        if not REPO_ARG_RE.fullmatch(explicit_repo):
            fail("--repo must be OWNER/REPO")
        return explicit_repo

    remote = run_git("remote", "get-url", "origin")
    match = GITHUB_REMOTE_RE.match(remote)
    if not match:
        fail(
            "could not infer a GitHub OWNER/REPO from origin remote "
            f"'{remote}'; pass --repo OWNER/REPO"
        )
    owner, repo = match.groups()
    return f"{owner}/{repo}"


def path_anchor(path: str) -> str:
    return hashlib.sha256(path.encode("utf-8")).hexdigest()


def build_links(repo: str, commit: str, paths: list[str]) -> list[dict[str, str]]:
    links = []
    for path in paths:
        digest = path_anchor(path)
        links.append(
            {
                "path": path,
                "sha256": digest,
                "url": f"https://github.com/{repo}/commit/{commit}#diff-{digest}",
            }
        )
    return links


def print_markdown(links: list[dict[str, str]]) -> None:
    for link in links:
        print(f"- [{link['path']}]({link['url']})")


def print_json(repo: str, commit: str, links: list[dict[str, str]]) -> None:
    payload = {"repository": repo, "commit": commit, "files": links}
    print(json.dumps(payload, indent=2))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Print GitHub #diff anchors for the files changed by a commit. "
            "Read-only: never checks out or executes code."
        )
    )
    parser.add_argument(
        "commit",
        nargs="?",
        default="HEAD",
        help="commit to link (default: HEAD)",
    )
    parser.add_argument(
        "--base",
        help="diff BASE...COMMIT instead of COMMIT against its first parent",
    )
    parser.add_argument(
        "--repo",
        help="GitHub OWNER/REPO; inferred from the origin remote by default",
    )
    parser.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="output format (default: markdown)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    commit = resolve_commit(args.commit)
    if args.base:
        resolve_commit(args.base)
    repo = infer_repo(args.repo)
    paths = changed_paths(commit, args.base)
    if not paths:
        fail(f"commit {commit} has no changed files")
    links = build_links(repo, commit, paths)
    if args.format == "json":
        print_json(repo, commit, links)
    else:
        print_markdown(links)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
