#!/bin/bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

# The archive name is derived from info.json so release artifacts cannot drift
# from the mod version.
info_version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' info.json \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if ! [[ "$info_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: could not read a MAJOR.MINOR.PATCH version from info.json" >&2
    exit 1
fi

archive_name="PlanetsLib_${info_version}"
git archive --prefix="${archive_name}/" -o "${archive_name}.zip" HEAD
echo "Created ${archive_name}.zip"

# Rebuild the documentation only if docs-source/ changed since the commit that
# last rendered it into docs/. Uncommitted source edits and untracked source
# files also count, so a build is never skipped while the sources are stale.
docs_commit=$(git log -1 --format=%H -- docs)

if [ -z "$docs_commit" ] || [ ! -d docs ] \
    || ! git diff --quiet "$docs_commit" -- docs-source \
    || [ -n "$(git ls-files --others --exclude-standard docs-source)" ]; then
    sh update_documentation.sh
else
    echo "Documentation is up to date; skipping rebuild."
fi
