#!/usr/bin/env bash
#
# Verify that the release version is recorded consistently:
#
#   * info.json      - the mod version
#   * changelog.txt  - the newest version entry
#   * archive.sh     - derives the archive prefix/filename from info.json and
#                      does not hard-code a version
#
# Usage:
#   .github/scripts/check_version.sh [REPOSITORY_ROOT]
#
# With no argument the repository root is derived from this script's path, so
# the check can be run from anywhere. The optional root lets CI check an
# untrusted pull-request checkout with this trusted copy of the script.
#
# Exits non-zero and prints what disagrees when the versions diverge.

set -euo pipefail

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

if [ "$#" -gt 1 ]; then
	fail "usage: $0 [repository-root]"
fi

if [ "$#" -eq 1 ]; then
	REPO_DIR="$(cd "$1" 2>/dev/null && pwd)" || fail "repository root not found: $1"
else
	REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

INFO_JSON="$REPO_DIR/info.json"
CHANGELOG="$REPO_DIR/changelog.txt"
ARCHIVE_SH="$REPO_DIR/archive.sh"

for file in "$INFO_JSON" "$CHANGELOG" "$ARCHIVE_SH"; do
	[ -f "$file" ] || fail "required file not found: $file"
done

info_version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$INFO_JSON" \
	| grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
[ -n "$info_version" ] || fail "could not read the version from info.json"
[[ "$info_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
	|| fail "info.json version is not MAJOR.MINOR.PATCH: '$info_version'"

changelog_version="$(grep -m1 -E '^Version: ' "$CHANGELOG" | sed -E 's/^Version: *//' || true)"
[ -n "$changelog_version" ] || fail "could not read the newest version from changelog.txt"

hardcoded_archive_versions="$(grep -oE 'PlanetsLib_[0-9]+\.[0-9]+\.[0-9]+' "$ARCHIVE_SH" \
	| sort -u || true)"
if [ -n "$hardcoded_archive_versions" ]; then
	fail "archive.sh must not hard-code a version (found $(printf '%s' "$hardcoded_archive_versions" | tr '\n' ' ')); read it from info.json instead"
fi
grep -qF 'info.json' "$ARCHIVE_SH" \
	|| fail "archive.sh does not read the version from info.json"
grep -qE 'PlanetsLib_\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' "$ARCHIVE_SH" \
	|| fail "archive.sh does not build a PlanetsLib_<version> archive name from a variable"

printf 'info.json version:      %s\n' "$info_version"
printf 'changelog.txt version:  %s\n' "$changelog_version"
printf 'archive.sh:             derives the release name from info.json\n'

[ "$info_version" = "$changelog_version" ] \
	|| fail "info.json ($info_version) and changelog.txt ($changelog_version) disagree"

printf 'Version consistency check passed for %s.\n' "$info_version"
