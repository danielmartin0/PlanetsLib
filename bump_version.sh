#!/usr/bin/env bash
#
# bump_version.sh - Prepare a PlanetsLib release.
#
# Bumps the version in info.json, updates the hard-coded zip prefix in
# archive.sh, and prepends a changelog.txt entry for the new version.
#
# The release type decides how the version number changes and which changelog
# sections are written:
#
#   minor / bugfix / patch   2.1.1 -> 2.1.2   (Bugfixes)
#   feature                  2.1.1 -> 2.2.0   (Features, Changes)
#   major                    2.1.1 -> 3.0.0   (Features, Changes, Bugfixes)
#
# Usage:
#   ./bump_version.sh <minor|feature|major> [--date YYYY-MM-DD|????] [--dry-run]
#
# Options:
#   --date DATE   Date to record in the changelog. Defaults to today. Pass
#                 ???? to leave it unset until the release date, per AGENTS.md.
#   --dry-run     Show what would change without writing any files.
#   -h, --help    Show this help.
#
# The new changelog section headings are written empty for you to fill in.
# Nothing is committed; review the changes and commit them yourself.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFO_JSON="$REPO_DIR/info.json"
ARCHIVE_SH="$REPO_DIR/archive.sh"
CHANGELOG="$REPO_DIR/changelog.txt"

# The changelog uses a 99-dash divider before every version entry.
DIVIDER="$(printf '%0.s-' {1..99})"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

release_type=""
date="$(date +%F)"
dry_run=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            dry_run=true
            ;;
        --date)
            [ "$#" -ge 2 ] || die "--date requires a value"
            date="$2"
            shift
            ;;
        --date=*)
            date="${1#--date=}"
            ;;
        -*)
            die "unknown option '$1' (see --help)"
            ;;
        *)
            [ -z "$release_type" ] || die "only one release type may be given"
            release_type="$1"
            ;;
    esac
    shift
done

[ -n "$release_type" ] || { usage; exit 1; }

case "$date" in
    '????' | [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "invalid --date '$date' (expected YYYY-MM-DD or ????)" ;;
esac

for file in "$INFO_JSON" "$ARCHIVE_SH" "$CHANGELOG"; do
    [ -f "$file" ] || die "required file not found: $file"
done

current="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$INFO_JSON" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
[ -n "$current" ] || die "could not read the version from $INFO_JSON"

IFS=. read -r major minor patch <<< "$current"

case "$release_type" in
    minor|bugfix|patch)
        patch=$((patch + 1))
        sections=("Bugfixes")
        ;;
    feature)
        minor=$((minor + 1))
        patch=0
        sections=("Features" "Changes")
        ;;
    major)
        major=$((major + 1))
        minor=0
        patch=0
        sections=("Features" "Changes" "Bugfixes")
        ;;
    *)
        die "unknown release type '$release_type' (expected minor, feature or major)"
        ;;
esac

new="$major.$minor.$patch"

if grep -qE "^Version: $new\$" "$CHANGELOG"; then
    die "changelog.txt already contains an entry for version $new"
fi

printf '%s -> %s (%s release)\n' "$current" "$new" "$release_type"
printf '  date:       %s\n' "$date"
printf '  sections:   %s\n' "${sections[*]}"
printf '  changelog:  %s\n' "$CHANGELOG"
printf '  info.json:  %s\n' "$INFO_JSON"
printf '  archive.sh: PlanetsLib_%s -> PlanetsLib_%s\n' "$current" "$new"

if $dry_run; then
    printf '\nDry run: no files were changed.\n'
    exit 0
fi

# Prepend the new entry to changelog.txt. Its trailing divider is not needed
# because the existing first line already opens the previous version.
entry="$DIVIDER
Version: $new
Date: $date"
for section in "${sections[@]}"; do
    entry+="
  $section:"
done

tmp="$(mktemp "$REPO_DIR/.bump_version.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

printf '%s\n' "$entry" | cat - "$CHANGELOG" > "$tmp"
mv "$tmp" "$CHANGELOG"

# Bump the version in info.json.
sed "s/^\( *\"version\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\".*\)\$/\1$new\2/" \
    "$INFO_JSON" > "$tmp"
grep -qF "\"version\": \"$new\"" "$tmp" || die "failed to update the version in $INFO_JSON"
mv "$tmp" "$INFO_JSON"

# Update the hard-coded zip prefix and name in archive.sh.
escaped_current="${current//./\\.}"
grep -qF "PlanetsLib_$current" "$ARCHIVE_SH" \
    || die "could not find PlanetsLib_$current in $ARCHIVE_SH"
sed "s/PlanetsLib_$escaped_current/PlanetsLib_$new/g" "$ARCHIVE_SH" > "$tmp"
mv "$tmp" "$ARCHIVE_SH"

printf '\nDone. Next steps:\n'
printf '  1. Fill in the %s section(s) in changelog.txt.\n' "${sections[*]}"
printf '  2. Commit the changes.\n'
printf '  3. Run ./archive.sh once ready to release.\n'
