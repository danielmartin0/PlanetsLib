#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_2.3.2/ -o PlanetsLib_2.3.2.zip HEAD

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