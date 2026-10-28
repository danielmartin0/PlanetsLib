#!/usr/bin/env python3
"""Check which mod-portal pages link to a live Git repository.

The Factorio mod portal exposes ``source_url`` and ``homepage`` through
``/api/mods/<name>/full``. This script reads those fields, classifies the URL,
and optionally checks that the repository is still reachable. It is useful when
auditing a set of planet mods before opening upstream pull requests: a portal
page may link a repository that has since been deleted, renamed, or made
private.

The script only performs unauthenticated GET/HEAD requests. It never clones,
pushes, or modifies anything.

Examples:
    python3 helper_scripts/mod_portal_repos.py --mod linox --mod cubium
    python3 helper_scripts/mod_portal_repos.py --mods-file mods.txt --json
    python3 helper_scripts/mod_portal_repos.py --self-test
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Callable, Iterable, NoReturn

DEFAULT_API_BASE = "https://mods.factorio.com/api/mods"
DEFAULT_GIT_HOSTS = (
    "github.com",
    "gitlab.com",
    "codeberg.org",
    "bitbucket.org",
)
USER_AGENT = "PlanetsLib-helper-scripts/1.0 (mod-portal-repo-check)"


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


@dataclass
class Result:
    mod: str
    source_url: str
    homepage: str
    repo_url: str
    host: str
    status: str
    http_status: int | None
    detail: str

    def as_dict(self) -> dict:
        return {
            "mod": self.mod,
            "source_url": self.source_url,
            "homepage": self.homepage,
            "repo_url": self.repo_url,
            "host": self.host,
            "status": self.status,
            "http_status": self.http_status,
            "detail": self.detail,
        }


def git_host(url: str, git_hosts: Iterable[str]) -> str | None:
    """Return the matching Git host for *url*, or None."""
    if not url:
        return None
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    for candidate in git_hosts:
        candidate = candidate.lower()
        if host == candidate or host.endswith("." + candidate):
            return candidate
    return None


def choose_url(source_url: str, homepage: str) -> str:
    """Prefer the portal's Source field, then its Homepage field."""
    return (source_url or homepage or "").strip()


def head_status(
    url: str,
    opener: Callable = urllib.request.urlopen,
    timeout: float = 20.0,
) -> tuple[int | None, str]:
    """Return (HTTP status, detail) for a HEAD request."""
    request = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": USER_AGENT},
    )
    try:
        with opener(request, timeout=timeout) as response:
            return int(getattr(response, "status", 0) or 0), ""
    except urllib.error.HTTPError as exc:
        return int(exc.code), str(exc.reason or "")
    except urllib.error.URLError as exc:
        return None, str(exc.reason or exc)
    except OSError as exc:
        return None, str(exc)


def classify_mod(
    name: str,
    data: dict,
    git_hosts: Iterable[str] = DEFAULT_GIT_HOSTS,
    opener: Callable = urllib.request.urlopen,
    timeout: float = 20.0,
) -> Result:
    """Classify one mod-portal API response."""
    source_url = (data.get("source_url") or "").strip()
    homepage = (data.get("homepage") or "").strip()
    repo_url = choose_url(source_url, homepage)
    if not repo_url:
        return Result(name, source_url, homepage, "", "", "no-linked-repo", None, "")

    host = git_host(repo_url, git_hosts)
    if not host:
        return Result(
            name,
            source_url,
            homepage,
            repo_url,
            "",
            "not-git",
            None,
            "linked URL is not a recognised Git host",
        )

    status, detail = head_status(repo_url, opener=opener, timeout=timeout)
    if status is None:
        return Result(name, source_url, homepage, repo_url, host, "error", None, detail)
    if 200 <= status < 400:
        return Result(name, source_url, homepage, repo_url, host, "ok", status, detail)
    if status == 404:
        return Result(name, source_url, homepage, repo_url, host, "404", status, detail)
    return Result(name, source_url, homepage, repo_url, host, "http-error", status, detail)


def fetch_mod_json(
    api_base: str,
    name: str,
    opener: Callable = urllib.request.urlopen,
    timeout: float = 30.0,
) -> dict:
    url = f"{api_base.rstrip('/')}/{urllib.parse.quote(name)}/full"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with opener(request, timeout=timeout) as response:
            payload = response.read()
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            fail(f"mod {name!r} was not found on the mod portal")
        fail(f"mod portal returned HTTP {exc.code} for {name!r}: {exc.reason}")
    except urllib.error.URLError as exc:
        fail(f"could not reach the mod portal for {name!r}: {exc.reason}")
    try:
        return json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"mod portal returned invalid JSON for {name!r}: {exc}")


def read_mods(args: argparse.Namespace) -> list[str]:
    names = list(args.mod or [])
    if args.mods_file:
        try:
            with open(args.mods_file, encoding="utf-8") as handle:
                for line in handle:
                    line = line.split("#", 1)[0].strip()
                    if line:
                        names.extend(part.strip() for part in re.split(r"[\s,]+", line) if part.strip())
        except OSError as exc:
            fail(f"could not read {args.mods_file}: {exc}")
    # Preserve order, drop duplicates.
    seen = set()
    unique = []
    for name in names:
        if name not in seen:
            seen.add(name)
            unique.append(name)
    return unique


def print_markdown(results: list[Result]) -> None:
    print("| Mod | Status | Repo |")
    print("| --- | --- | --- |")
    for result in results:
        repo = result.repo_url or "-"
        detail = f" ({result.detail})" if result.detail else ""
        print(f"| `{result.mod}` | {result.status}{detail} | {repo} |")


def self_test() -> int:
    """Assert classification and URL handling with a fake HTTP opener."""
    class FakeResponse:
        def __init__(self, status: int) -> None:
            self.status = status

        def __enter__(self):
            return self

        def __exit__(self, *exc) -> None:
            return None

    def opener_for(status: int):
        def opener(request, timeout=0):
            return FakeResponse(status)

        return opener

    cases = [
        (
            "ok",
            {
                "source_url": "https://github.com/example/planet",
                "homepage": "",
            },
            opener_for(200),
            "ok",
            "github.com",
        ),
        (
            "missing",
            {
                "source_url": "https://github.com/example/gone",
                "homepage": "",
            },
            opener_for(404),
            "404",
            "github.com",
        ),
        (
            "homepage-fallback",
            {
                "source_url": "",
                "homepage": "https://gitlab.com/example/planet",
            },
            opener_for(200),
            "ok",
            "gitlab.com",
        ),
        (
            "no-link",
            {"source_url": "", "homepage": ""},
            opener_for(200),
            "no-linked-repo",
            "",
        ),
        (
            "not-git",
            {"source_url": "https://example.com/planet", "homepage": ""},
            opener_for(200),
            "not-git",
            "",
        ),
    ]
    for name, data, opener, expected_status, expected_host in cases:
        result = classify_mod(name, data, opener=opener)
        assert result.status == expected_status, (name, result.status, expected_status)
        assert result.host == expected_host, (name, result.host, expected_host)
    assert choose_url("", "https://github.com/a/b") == "https://github.com/a/b"
    assert choose_url("https://github.com/a/b", "https://example.com") == "https://github.com/a/b"
    assert git_host("https://github.com/a/b", DEFAULT_GIT_HOSTS) == "github.com"
    assert git_host("https://sub.github.com/a/b", DEFAULT_GIT_HOSTS) == "github.com"
    assert git_host("https://example.com/a/b", DEFAULT_GIT_HOSTS) is None
    print("mod_portal_repos.py self-test: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check which mod-portal pages link to a live Git repository.",
    )
    parser.add_argument("--mod", action="append", help="mod portal name; repeatable")
    parser.add_argument("--mods-file", help="file with one mod name per line")
    parser.add_argument("--api-base", default=DEFAULT_API_BASE, help=argparse.SUPPRESS)
    parser.add_argument("--json", action="store_true", help="print JSON instead of Markdown")
    parser.add_argument("--delay", type=float, default=0.5, help="seconds between requests")
    parser.add_argument("--timeout", type=float, default=20.0, help="HTTP timeout in seconds")
    parser.add_argument(
        "--git-host",
        action="append",
        dest="git_hosts",
        help="Git host to accept; repeatable (default: GitHub, GitLab, Codeberg, Bitbucket)",
    )
    parser.add_argument("--self-test", action="store_true", help="run local assertions and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    names = read_mods(args)
    if not names:
        fail("provide --mod NAME and/or --mods-file FILE")

    git_hosts = tuple(args.git_hosts or DEFAULT_GIT_HOSTS)
    results = []
    for index, name in enumerate(names):
        data = fetch_mod_json(args.api_base, name, timeout=args.timeout)
        results.append(
            classify_mod(
                name,
                data,
                git_hosts=git_hosts,
                timeout=args.timeout,
            )
        )
        if args.delay and index + 1 < len(names):
            time.sleep(args.delay)

    if args.json:
        print(json.dumps({"results": [r.as_dict() for r in results]}, indent=2))
    else:
        print_markdown(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
