#!/usr/bin/env bash
#
# Fetch a GitHub pull request into a local worktree and print a review summary.
#
# Usage:
#   helper_scripts/pr_worktree.sh <pull-request-number> [--dir PATH] [--base REF]
#
# The default worktree path is ${TMPDIR:-/tmp}/planetslib-pr-<number> (or
# /tmp/opencode/planetslib-pr-<number> when /tmp/opencode exists). The default
# comparison base is origin/main.
#
# This only fetches and checks out the PR head. It does not run PR code.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pr=""
worktree=""
base="origin/main"

usage() {
	sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--dir)
			[ "$#" -ge 2 ] || { echo "error: --dir requires a path" >&2; exit 1; }
			worktree="$2"
			shift
			;;
		--dir=*)
			worktree="${1#--dir=}"
			;;
		--base)
			[ "$#" -ge 2 ] || { echo "error: --base requires a ref" >&2; exit 1; }
			base="$2"
			shift
			;;
		--base=*)
			base="${1#--base=}"
			;;
		-*)
			echo "error: unknown option '$1' (see --help)" >&2
			exit 1
			;;
		*)
			[ -z "$pr" ] || { echo "error: only one pull request number may be given" >&2; exit 1; }
			pr="$1"
			;;
	esac
	shift
done

[ -n "$pr" ] || { usage; exit 1; }
case "$pr" in
	''|*[!0-9]*) echo "error: pull request number must be numeric: '$pr'" >&2; exit 1 ;;
esac

if [ -z "$worktree" ]; then
	base_dir="${TMPDIR:-/tmp}"
	[ -d /tmp/opencode ] && base_dir=/tmp/opencode
	worktree="$base_dir/planetslib-pr-$pr"
fi
if [[ "$worktree" != /* ]]; then
	worktree="$PWD/$worktree"
fi

if ! git -C "$repo_dir" rev-parse --verify --quiet "$base" >/dev/null; then
	git -C "$repo_dir" fetch origin main
fi

git -C "$repo_dir" fetch origin "+refs/pull/$pr/head:refs/heads/pr/$pr"

if git -C "$repo_dir" worktree list --porcelain | grep -qxF "worktree $worktree"; then
	echo "Worktree already exists: $worktree"
else
	if [ -e "$worktree" ]; then
		echo "error: path already exists and is not a registered worktree: $worktree" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$worktree")"
	git -C "$repo_dir" worktree add "$worktree" "pr/$pr"
fi

echo
echo "Worktree: $worktree"
echo "PR head:  $(git -C "$worktree" rev-parse --short HEAD) $(git -C "$worktree" log -1 --format=%s)"
echo "Base:     $base"
echo
echo "Commits:"
git -C "$worktree" log --oneline "$base..HEAD"
echo
echo "Diff stat:"
git -C "$worktree" diff --stat "$base...HEAD"
echo
echo "Changed files:"
git -C "$worktree" diff --name-status "$base...HEAD"
echo
echo "Remove the worktree later with:"
echo "  git -C \"$repo_dir\" worktree remove \"$worktree\""
