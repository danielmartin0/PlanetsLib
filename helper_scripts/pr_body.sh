#!/usr/bin/env bash
#
# pr_body.sh - generate the review-oriented bugfix pull request body for
# PlanetsLib, following the format in AGENTS.md ("Bugfix pull request format")
# as established by PR #130.
#
# The body is built from the commits between origin/<base> and HEAD, the
# repository's .github/PULL_REQUEST_TEMPLATE.md, and (optionally) an FUnit log. Links
# are pinned to commit SHAs and file diff anchors use the same sha256 fragment
# as GitHub:
#
#   printf %s "<repo-relative path>" | sha256sum
#
# This script only reads git metadata and local files. It never calls gh and
# never mutates GitHub, a branch, or the working tree.

set -euo pipefail

PROG="$(basename "$0")"
DEFAULT_REPO="danielmartin0/PlanetsLib"
DEFAULT_SIGNATURE='_Posted by DeepSeek V4.1 Flash._'

ISSUE=""
REPO="$DEFAULT_REPO"
BASE="main"
TEST_FILE=""
TEST_IDS_RAW=""
TEST_LINES=""
FUNIT_LOG=""
FACTORIO_VERSION=""
OUTPUT=""
SIGNATURE="$DEFAULT_SIGNATURE"

BODY_TMP=""

usage() {
  cat <<EOF
Usage:
  $PROG --issue N [options]
  $PROG --help

Generate the bugfix pull request body described in AGENTS.md. Markdown is
written to stdout unless --output is given.

Required:
  --issue N                 Issue number closed by the pull request.

Options:
  --repo OWNER/REPO         Repository for links (default: $DEFAULT_REPO).
  --base REF                Base branch/ref (default: main). origin/REF is
                            preferred when it exists; commits are read from
                            <base>..HEAD.
  --test-file PATH          Repo-relative (or absolute) FUnit test file used in
                            the commit-pinned test blob link.
  --test-ids ID,ID          Comma-separated FUnit test IDs to mention under
                            each bugfix entry.
  --test-lines L10-L25      Optional line range appended to the test blob URL.
  --funit-log FILE          FUnit stdout log. Test counts and the Factorio
                            version are parsed from __FUNIT__ result markers.
  --factorio-version VER    Exact local Factorio version for Testing Notes.
                            Overrides any version found in the FUnit log.
  --output FILE             Write Markdown to FILE instead of stdout. Use - to
                            keep writing to stdout.
  --signature TEXT          Signature at the top of the body (default:
                            $DEFAULT_SIGNATURE).
  -h, --help                Show this help and exit.

Behavior:
  - Splits commits into test:, fix:, and other commits. test: and fix: commits
    are listed separately; only fix: commits are in the bugfix review scope.
  - Reproduces the unchecked checklist items from .github/PULL_REQUEST_TEMPLATE.md.
  - Groups changed files from fix: commits by area and emits one unchecked
    review item per file, with a commit-pinned diff anchor.
  - Emits a clear warning instead of failing when no fix: commit exists.

Exit status:
  0  body generated
  1  runtime error (not a git repository, unreadable log, git failure)
  2  usage error

Examples:
  $PROG --issue 462 \\
    --test-file test-mods/planetslib-funit-data/tests/suites/entity_replacement_migration.lua \\
    --test-ids SMOKE-1 \\
    --funit-log /tmp/opencode/muluna-funit-final/stdout.log

  $PROG --issue 462 --base main --factorio-version 2.1.23 --output pr-body.md
EOF
}

warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
usage_error() {
  printf '%s: error: %s\n' "$PROG" "$*" >&2
  printf "Try '%s --help'.\n" "$PROG" >&2
  exit 2
}

cleanup() {
  if [ -n "$BODY_TMP" ]; then
    rm -f -- "$BODY_TMP"
  fi
  return 0
}
trap cleanup EXIT INT TERM

need_value() {
  # need_value <flag> <remaining-args-count>
  if [ "$2" -lt 2 ]; then
    usage_error "$1 requires a value"
  fi
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
  esac
  return 0
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------- arg parsing

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --issue)
      need_value "$1" "$#"
      ISSUE="$2"; shift 2
      ;;
    --issue=*)
      ISSUE="${1#*=}"; shift
      ;;
    --repo)
      need_value "$1" "$#"
      REPO="$2"; shift 2
      ;;
    --repo=*)
      REPO="${1#*=}"; shift
      ;;
    --base)
      need_value "$1" "$#"
      BASE="$2"; shift 2
      ;;
    --base=*)
      BASE="${1#*=}"; shift
      ;;
    --test-file)
      need_value "$1" "$#"
      TEST_FILE="$2"; shift 2
      ;;
    --test-file=*)
      TEST_FILE="${1#*=}"; shift
      ;;
    --test-ids)
      need_value "$1" "$#"
      TEST_IDS_RAW="$2"; shift 2
      ;;
    --test-ids=*)
      TEST_IDS_RAW="${1#*=}"; shift
      ;;
    --test-lines)
      need_value "$1" "$#"
      TEST_LINES="$2"; shift 2
      ;;
    --test-lines=*)
      TEST_LINES="${1#*=}"; shift
      ;;
    --funit-log)
      need_value "$1" "$#"
      FUNIT_LOG="$2"; shift 2
      ;;
    --funit-log=*)
      FUNIT_LOG="${1#*=}"; shift
      ;;
    --factorio-version)
      need_value "$1" "$#"
      FACTORIO_VERSION="$2"; shift 2
      ;;
    --factorio-version=*)
      FACTORIO_VERSION="${1#*=}"; shift
      ;;
    --output)
      need_value "$1" "$#"
      OUTPUT="$2"; shift 2
      ;;
    --output=*)
      OUTPUT="${1#*=}"; shift
      ;;
    --signature)
      need_value "$1" "$#"
      SIGNATURE="$2"; shift 2
      ;;
    --signature=*)
      SIGNATURE="${1#*=}"; shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage_error "unknown option: $1"
      ;;
    *)
      usage_error "unexpected argument: $1"
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  usage_error "unexpected argument: $1"
fi

# ------------------------------------------------------------- validate input

if ! is_positive_int "$ISSUE"; then
  usage_error "--issue must be a positive integer"
fi

if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  usage_error "--repo must look like owner/repo"
fi

if [[ -z "$BASE" ]]; then
  usage_error "--base must not be empty"
fi

if [[ -n "$TEST_LINES" && -z "$TEST_FILE" ]]; then
  usage_error "--test-lines requires --test-file"
fi

if [[ -n "$TEST_LINES" && ! "$TEST_LINES" =~ ^L[0-9]+(-L[0-9]+)?$ ]]; then
  usage_error "--test-lines must look like L10-L25 or L10"
fi

if [[ -n "$SIGNATURE" ]]; then
  : # keep the supplied text verbatim
else
  usage_error "--signature must not be empty"
fi

if [[ -n "$FUNIT_LOG" && ! -r "$FUNIT_LOG" ]]; then
  die "FUnit log is not readable: $FUNIT_LOG"
fi

INVOCATION_DIR="$PWD"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || \
  die "not inside a git repository"
cd "$REPO_ROOT"

if ! git rev-parse --verify --quiet HEAD >/dev/null; then
  die "HEAD does not point to a commit"
fi

if ! command -v sha256sum >/dev/null 2>&1 && \
   ! command -v shasum >/dev/null 2>&1; then
  die "sha256sum or shasum is required to compute file diff anchors"
fi

# Resolve the base: prefer a remote-tracking ref (fresher in CI and worktrees)
# but accept a local branch/tag/SHA as a fallback.
BASE_REF=""
if [[ "$BASE" == */* ]]; then
  if git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    BASE_REF="$BASE"
  fi
else
  if git rev-parse --verify --quiet "origin/$BASE^{commit}" >/dev/null; then
    BASE_REF="origin/$BASE"
  elif git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    BASE_REF="$BASE"
  fi
fi
if [[ -z "$BASE_REF" ]]; then
  die "cannot resolve base ref '$BASE' (tried origin/$BASE and $BASE)"
fi
BASE_DISPLAY="${BASE#origin/}"

SOURCE_BRANCH=""
if SOURCE_BRANCH="$(git symbolic-ref --short -q HEAD)"; then
  :
else
  SOURCE_BRANCH="detached HEAD at $(git rev-parse --short=12 HEAD)"
fi

REPO_URL="https://github.com/$REPO"

# Resolve the test file into a repo-relative path so blob links work even when
# the helper is invoked from outside the repository root.
TEST_FILE_REL=""
if [[ -n "$TEST_FILE" ]]; then
  test_abs=""
  if [[ "$TEST_FILE" == /* ]]; then
    test_abs="$TEST_FILE"
  elif [[ -e "$REPO_ROOT/$TEST_FILE" ]]; then
    test_abs="$REPO_ROOT/$TEST_FILE"
  elif [[ -e "$INVOCATION_DIR/$TEST_FILE" ]]; then
    test_abs="$INVOCATION_DIR/$TEST_FILE"
  fi

  if [[ -n "$test_abs" ]]; then
    case "$test_abs" in
      "$REPO_ROOT"/*) TEST_FILE_REL="${test_abs#"$REPO_ROOT"/}" ;;
      *) TEST_FILE_REL="$TEST_FILE" ;;
    esac
  else
    TEST_FILE_REL="$TEST_FILE"
    warn "test file not found in the working tree: $TEST_FILE"
  fi
fi

TEST_IDS=()
if [[ -n "$TEST_IDS_RAW" ]]; then
  IFS=',' read -r -a raw_ids <<< "$TEST_IDS_RAW"
  for raw_id in "${raw_ids[@]}"; do
    id="$(trim "$raw_id")"
    if [[ -n "$id" ]]; then
      TEST_IDS+=("$id")
    fi
  done
fi

# ------------------------------------------------------------------ git data

COMMIT_SHAS=()
COMMIT_SUBJECTS=()
COMMIT_TYPES=()
FIX_IDX=()
OTHER_COUNT=0
TEST_COUNT=0
FIX_COUNT=0
FIRST_TEST_IDX=-1
FIRST_FIX_IDX=-1

# Type extraction handles Conventional Commit scopes and breaking markers:
# fix:, fix(scope):, fix(scope)!:, and any casing.
commit_type() {
  local subject="$1" prefix
  if [[ "$subject" == *:* ]]; then
    prefix="${subject%%:*}"
    prefix="$(printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')"
    prefix="${prefix%%(*}"
    prefix="${prefix%!}"
    printf '%s' "$prefix"
  else
    printf 'other'
  fi
}

while IFS=$'\t' read -r sha subject; do
  [[ -n "$sha" ]] || continue
  if [[ -z "$subject" ]]; then
    subject="$(git log -1 --format='%s' "$sha")"
  fi
  type="$(commit_type "$subject")"
  idx="${#COMMIT_SHAS[@]}"
  COMMIT_SHAS+=("$sha")
  COMMIT_SUBJECTS+=("$subject")
  COMMIT_TYPES+=("$type")

  case "$type" in
    test)
      TEST_COUNT=$((TEST_COUNT + 1))
      if [[ "$FIRST_TEST_IDX" -lt 0 ]]; then
        FIRST_TEST_IDX="$idx"
      fi
      ;;
    fix)
      FIX_IDX+=("$idx")
      FIX_COUNT=$((FIX_COUNT + 1))
      if [[ "$FIRST_FIX_IDX" -lt 0 ]]; then
        FIRST_FIX_IDX="$idx"
      fi
      ;;
    *)
      OTHER_COUNT=$((OTHER_COUNT + 1))
      ;;
  esac
done < <(git log --reverse --format='%H%x09%s' "$BASE_REF..HEAD")

# Changed files for one commit. -z keeps unusual file names intact. A merge
# commit has no first-parent diff by default, so fall back to an explicit
# parent comparison.
CUR_FILES=()
load_commit_files() {
  local sha="$1" file
  CUR_FILES=()
  while IFS= read -r -d '' file; do
    [[ -n "$file" ]] && CUR_FILES+=("$file")
  done < <(git diff-tree --no-commit-id --name-only -r -z --no-renames "$sha")

  if [[ ${#CUR_FILES[@]} -eq 0 ]] && \
     git rev-parse --verify --quiet "${sha}^" >/dev/null; then
    while IFS= read -r -d '' file; do
      [[ -n "$file" ]] && CUR_FILES+=("$file")
    done < <(git diff-tree --no-commit-id --name-only -r -z --no-renames "${sha}^" "$sha")
  fi
}

short_sha() {
  printf '%s' "${1:0:12}"
}

commit_url() {
  printf '%s/commit/%s' "$REPO_URL" "$1"
}

# GitHub's file diff anchor is the sha256 of the repository-relative path.
diff_anchor() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

diff_url() {
  local sha="$1" path="$2"
  printf '%s/commit/%s#diff-%s' "$REPO_URL" "$sha" "$(diff_anchor "$path")"
}

# Percent-encode a path for the blob URL, leaving path separators alone.
url_path() {
  local path="$1" out="" ch code i
  for ((i = 0; i < ${#path}; i++)); do
    ch="${path:i:1}"
    case "$ch" in
      [A-Za-z0-9._~/-]) out+="$ch" ;;
      *)
        printf -v code '%%%02X' "'$ch"
        out+="$code"
        ;;
    esac
  done
  printf '%s' "$out"
}

classify_path() {
  case "$1" in
    locale/*) printf 'Localisation' ;;
    compat/*) printf 'Compatibility' ;;
    migrations/*) printf 'Migrations and save compatibility' ;;
    prototypes/override/*|prototypes/override-final/*|prototypes/vanilla-override/*) printf 'Prototype overrides' ;;
    prototypes/*|data.lua|data-updates.lua|data-final-fixes.lua|settings.lua|settings-updates.lua)
      printf 'Load stages and data' ;;
    scripts/*|control.lua) printf 'Control-stage events' ;;
    lib/*) printf 'Shared libraries' ;;
    test-mods/*) printf 'Tests and test infrastructure' ;;
    .github/*|helper_scripts/*) printf 'CI and tooling' ;;
    docs/*|docs-source/*|*.md) printf 'Documentation' ;;
    *) printf 'Other changed files' ;;
  esac
}

CATEGORIES=(
  "Load stages and data"
  "Prototype overrides"
  "Control-stage events"
  "Compatibility"
  "Migrations and save compatibility"
  "Localisation"
  "Shared libraries"
  "Tests and test infrastructure"
  "CI and tooling"
  "Documentation"
  "Other changed files"
)

# ------------------------------------------------------------------ checklist

CHECKLIST_MD=""
TEMPLATE="$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
if [[ -r "$TEMPLATE" ]]; then
  CHECKLIST_MD="$(
    awk '
      BEGIN { in_section = 0; keep = 0 }
      /^##[[:space:]]+Checklist[[:space:]]*:?[[:space:]]*$/ { in_section = 1; next }
      in_section && /^##[[:space:]]/ { exit }
      !in_section { next }
      /^- \[ \]/ { keep = 1; print; next }
      /^- \[[xX]\]/ { keep = 0; next }
      /^[[:space:]]*$/ { if (keep) print ""; next }
      /^[[:space:]]/ { if (keep) print; next }
      { keep = 0 }
    ' "$TEMPLATE"
  )"
fi

if [[ -z "$CHECKLIST_MD" ]]; then
  CHECKLIST_MD='- [ ] Changes have been tested
- [ ] Changes do not break backwards compatibility
- [ ] `changelog.txt` has been updated
- [ ] `README.md` has been updated (documentation section and/or Contributors list)'
fi

# ------------------------------------------------------------------- FUnit log

FT_SUCC=0
FT_FAIL=0
FT_ERR=0
FT_MARKERS=0
FT_VERSION=""
FT_FAIL_NAMES=()

if [[ -n "$FUNIT_LOG" ]]; then
  PARSED="$(
    awk '
      BEGIN { OFS = "\t"; succ = 0; fail = 0; err = 0; markers = 0; version = "" }
      {
        if (version == "" && match($0, /Factorio [0-9]+\.[0-9]+\.[0-9]+/)) {
          version = substr($0, RSTART + 9, RLENGTH - 9)
        }
        if (index($0, "__FUNIT__") == 0) next
        if (match($0, /__SUCCESS__/))       status = "SUCCESS"
        else if (match($0, /__FAILURE__/))  status = "FAILURE"
        else if (match($0, /__ERROR__/))    status = "ERROR"
        else next

        name = substr($0, RSTART + RLENGTH)
        sub(/^[[:space:]]+/, "", name)
        sub(/[[:space:]]+$/, "", name)
        markers++
        if (status == "SUCCESS") succ++
        else if (status == "FAILURE") { fail++; fail_names[fail] = name }
        else { err++; err_names[err] = name }
      }
      END {
        print succ, fail, err, markers, version
        for (i = 1; i <= fail; i++) print "FAILURE", fail_names[i]
        for (i = 1; i <= err; i++)  print "ERROR", err_names[i]
      }
    ' "$FUNIT_LOG"
  )"

  first_line="$(printf '%s\n' "$PARSED" | sed -n '1p')"
  IFS=$'\t' read -r FT_SUCC FT_FAIL FT_ERR FT_MARKERS FT_VERSION <<< "$first_line"
  [[ -n "$FT_SUCC" ]] || FT_SUCC=0
  [[ -n "$FT_FAIL" ]] || FT_FAIL=0
  [[ -n "$FT_ERR" ]] || FT_ERR=0
  [[ -n "$FT_MARKERS" ]] || FT_MARKERS=0
  [[ -n "$FT_VERSION" ]] || FT_VERSION=""

  while IFS=$'\t' read -r kind name; do
    [[ -n "$kind" ]] || continue
    FT_FAIL_NAMES+=("$kind: $name")
  done < <(printf '%s\n' "$PARSED" | sed '1d')
fi

FT_TOTAL=$((FT_SUCC + FT_FAIL + FT_ERR))

# Pin the test blob link to the newest commit in the range where the test file
# still exists. Falling back to HEAD keeps the link usable when the file was
# not part of the branch's commit range.
TEST_SHA="$(git rev-parse HEAD)"
if [[ -n "$TEST_FILE_REL" ]]; then
  for ((idx = ${#COMMIT_SHAS[@]} - 1; idx >= 0; idx--)); do
    candidate="${COMMIT_SHAS[$idx]}"
    if ! git cat-file -e "${candidate}:${TEST_FILE_REL}" 2>/dev/null; then
      continue
    fi
    load_commit_files "$candidate" 2>/dev/null || true
    for file in "${CUR_FILES[@]}"; do
      if [[ "$file" == "$TEST_FILE_REL" ]]; then
        TEST_SHA="$candidate"
        break 2
      fi
    done
  done
fi

# Whitespace check over the commit range. Record output without aborting under
# set -e, because a nonzero status is information for the body, not an error.
DIFF_CHECK_STATUS=0
DIFF_CHECK_OUTPUT=""
if DIFF_CHECK_OUTPUT="$(git diff --check "${BASE_REF}...HEAD" 2>&1)"; then
  DIFF_CHECK_STATUS=0
else
  DIFF_CHECK_STATUS=$?
fi

# -------------------------------------------------------------------- helpers

emit_commits_of_type() {
  local want="$1" idx found=0
  for idx in "${!COMMIT_SHAS[@]}"; do
    [[ "${COMMIT_TYPES[$idx]}" == "$want" ]] || continue
    found=1
    printf -- '- [`%s`](%s) — %s\n' \
      "$(short_sha "${COMMIT_SHAS[$idx]}")" \
      "$(commit_url "${COMMIT_SHAS[$idx]}")" \
      "${COMMIT_SUBJECTS[$idx]}"
  done
  if [[ "$found" -eq 0 ]]; then
    printf '_None._\n'
  fi
  printf '\n'
}

emit_other_commits() {
  local idx found=0
  for idx in "${!COMMIT_SHAS[@]}"; do
    if [[ "${COMMIT_TYPES[$idx]}" == "test" || "${COMMIT_TYPES[$idx]}" == "fix" ]]; then
      continue
    fi
    found=1
    printf -- '- [`%s`](%s) — %s\n' \
      "$(short_sha "${COMMIT_SHAS[$idx]}")" \
      "$(commit_url "${COMMIT_SHAS[$idx]}")" \
      "${COMMIT_SUBJECTS[$idx]}"
  done
  if [[ "$found" -eq 0 ]]; then
    printf '_None._\n'
  fi
  printf '\n'
}

render_test_ids() {
  local first=1 id
  for id in "${TEST_IDS[@]}"; do
    if [[ "$first" -eq 0 ]]; then
      printf ', '
    fi
    printf '`%s`' "$id"
    first=0
  done
}

emit_tests_line() {
  local sha="$1" url=""
  if [[ -n "$TEST_FILE_REL" ]]; then
    url="$REPO_URL/blob/$sha/$(url_path "$TEST_FILE_REL")"
    if [[ -n "$TEST_LINES" ]]; then
      url="$url#$TEST_LINES"
      printf '**Tests:** [`%s#%s`](%s)' "$TEST_FILE_REL" "$TEST_LINES" "$url"
    else
      printf '**Tests:** [`%s`](%s)' "$TEST_FILE_REL" "$url"
    fi
    if [[ ${#TEST_IDS[@]} -gt 0 ]]; then
      printf ' — test IDs: '
      render_test_ids
      printf '.\n\n'
    else
      printf ' — no specific test IDs supplied.\n\n'
    fi
  else
    printf '**Tests:** No automated test was provided for this change'
    if [[ ${#TEST_IDS[@]} -gt 0 ]]; then
      printf ' (test IDs: '
      render_test_ids
      printf ')'
    fi
    printf '; manual verification is required.\n\n'
  fi
}

category_risk_note() {
  case "$1" in
    "Prototype overrides")
      printf '> Cross-mod load-order risk: confirm the guard still holds when another mod removes or renames the prototype.\n\n'
      ;;
    "Control-stage events")
      printf '> Event-contract risk: confirm the handler stays idempotent and never touches `data.raw` in the control stage.\n\n'
      ;;
    "Compatibility")
      printf '> Compatibility risk: confirm the patch is still guarded by the dependency check that gates it.\n\n'
      ;;
    "Migrations and save compatibility")
      printf '> Save-compatibility risk: verify the migration is safe on existing saves and leaves no dangling prototype references.\n\n'
      ;;
  esac
}

# ---------------------------------------------------------------------- body

emit_body() {
  local idx sha subject file matched category printed_category entries=0

  printf '%s\n\n' "$SIGNATURE"

  if [[ "$FIX_COUNT" -eq 0 ]]; then
    if [[ ${#COMMIT_SHAS[@]} -eq 0 ]]; then
      printf '> **No commits were found between `%s` and `HEAD`.** The branch is at the base commit, so this body has no `fix:` commits and no diff anchors. Commit the fix first, or pass a different `--base`.\n\n' "$BASE_REF"
    else
      printf '> **No `fix:` commit was found between `%s` and `HEAD`.** This body was generated anyway, but the bugfix review scope is empty. Add the fix commit, or pass a different `--base`.\n\n' "$BASE_REF"
    fi
  fi

  # ---- Description
  printf '## Description\n\n'
  printf '**Source branch:** `%s`  \n' "$SOURCE_BRANCH"
  printf '**Target branch:** `%s`\n\n' "$BASE_DISPLAY"

  if [[ "$TEST_COUNT" -gt 0 && "$FIX_COUNT" -gt 0 && "$FIRST_TEST_IDX" -lt "$FIRST_FIX_IDX" ]]; then
    printf 'The test suite was hardened first: the `test:` commits below add or extend automated coverage, and the `fix:` commits contain the production change. The commit structure keeps them separate so a reviewer can verify the test fails without the fix and passes with it.\n\n'
  elif [[ "$TEST_COUNT" -gt 0 && "$FIX_COUNT" -gt 0 ]]; then
    printf 'Separate `test:` and `fix:` commits are present, but the first test commit does not precede the fix commit. The commit structure is still separated so the coverage can be reviewed independently, but the history does not demonstrate a test-first flow.\n\n'
  elif [[ "$FIX_COUNT" -gt 0 ]]; then
    printf 'No `test:` commit was found on this branch, so the test-first structure described in `AGENTS.md` is not represented in the commit history. The `fix:` commits contain the production change.\n\n'
  elif [[ "$TEST_COUNT" -gt 0 ]]; then
    printf 'The branch contains `test:` commits but no `fix:` commit, so the test-first structure is incomplete.\n\n'
  else
    printf 'The branch contains no `test:` or `fix:` commits, so neither the test-first structure nor a production fix is present yet.\n\n'
  fi

  printf 'Commit structure:\n\n'
  printf '### `test:` commits\n\n'
  emit_commits_of_type test
  printf '### `fix:` commits\n\n'
  emit_commits_of_type fix
  if [[ "$OTHER_COUNT" -gt 0 ]]; then
    printf '### Other commits\n\n'
    printf 'Merges, CI changes, documentation, and commits without a Conventional Commit type are listed here for context.\n\n'
    emit_other_commits
  fi

  # ---- Checklist
  printf '## Checklist\n\n'
  printf 'The unchecked items below are reproduced from `.github/PULL_REQUEST_TEMPLATE.md`. Check an item only when it has actually been done; leave it unchecked otherwise.\n\n'
  printf '%s\n\n' "$CHECKLIST_MD"

  # ---- Testing Notes
  printf '## Testing Notes\n\n'

  if [[ -n "$FACTORIO_VERSION" ]]; then
    printf -- '- **Factorio version:** `%s` (supplied with `--factorio-version`).\n' "$FACTORIO_VERSION"
  elif [[ -n "$FT_VERSION" ]]; then
    printf -- '- **Factorio version:** `%s` (read from the supplied FUnit log).\n' "$FT_VERSION"
  else
    printf -- '- **Factorio version:** not supplied and not found in the FUnit log.\n'
  fi

  if [[ -n "$FUNIT_LOG" ]]; then
    if [[ "$FT_MARKERS" -gt 0 ]]; then
      printf -- '- **FUnit suite:** %s tests, %s failures, %s errors (parsed from `%s`).\n' \
        "$FT_TOTAL" "$FT_FAIL" "$FT_ERR" "$(basename "$FUNIT_LOG")"
      if [[ ${#FT_FAIL_NAMES[@]} -gt 0 ]]; then
        printf -- '- **FUnit failures/errors:**\n'
        for name in "${FT_FAIL_NAMES[@]}"; do
          printf '  - `%s`\n' "$name"
        done
      fi
    else
      printf -- '- **FUnit suite:** the supplied log `%s` did not contain `__FUNIT__` result markers, so counts could not be parsed.\n' \
        "$(basename "$FUNIT_LOG")"
    fi
  else
    printf -- '- **FUnit suite:** no log supplied (`--funit-log` was not given), so test counts are unavailable.\n'
  fi

  if [[ "$DIFF_CHECK_STATUS" -eq 0 ]]; then
    printf -- '- **`git diff --check`:** clean (`git diff --check %s...HEAD`).\n' "$BASE_REF"
  else
    printf -- '- **`git diff --check`:** reported whitespace errors (`git diff --check %s...HEAD`):\n\n' "$BASE_REF"
    printf '  ```text\n'
    while IFS= read -r line; do
      printf '  %s\n' "$line"
    done <<< "$DIFF_CHECK_OUTPUT"
    printf '  ```\n'
  fi

  printf -- '- CI runs the floating `latest` Factorio image, so CI may validate a newer build than the local version listed above.\n\n'

  # ---- Bugfix review scope
  printf '## Bugfix review scope\n\n'
  if [[ "$FIX_COUNT" -gt 0 ]]; then
    printf 'The production changes under review are:\n\n'
    for idx in "${FIX_IDX[@]}"; do
      printf -- '- [`%s`](%s) — %s\n' \
        "$(short_sha "${COMMIT_SHAS[$idx]}")" \
        "$(commit_url "${COMMIT_SHAS[$idx]}")" \
        "${COMMIT_SUBJECTS[$idx]}"
    done
    printf '\n'
    printf 'Test-only commits (`test:`) and other commits are excluded from the bugfix checklist; they appear in the Description only for context. Do not treat a bot-authored pull request as pre-approved.\n\n'
  else
    printf 'No `fix:` commit was found between `%s` and `HEAD`. There is no production change in the bugfix review scope yet.\n\n' "$BASE_REF"
    printf 'Test-only commits (`test:`) and other commits are excluded from the bugfix checklist; they appear in the Description only for context.\n\n'
  fi

  # ---- Categorized bugfix checklist
  printf '## Categorized bugfix checklist\n\n'
  if [[ "$FIX_COUNT" -eq 0 ]]; then
    printf '_No `fix:` commit was found, so there are no bugfix files to review. This section will populate after a fix is committed._\n\n'
    if [[ -n "$TEST_FILE_REL" ]]; then
      printf 'Coverage supplied with this branch, for reference:\n\n'
      emit_tests_line "$TEST_SHA"
    fi
  else
    printf 'One unchecked item per changed file, grouped by area and pinned to the `fix:` commit that introduced it. Check an item only after verifying the behavior change.\n\n'

    for category in "${CATEGORIES[@]}"; do
      printed_category=0
      for idx in "${FIX_IDX[@]}"; do
        sha="${COMMIT_SHAS[$idx]}"
        subject="${COMMIT_SUBJECTS[$idx]}"
        load_commit_files "$sha"

        matched=0
        for file in "${CUR_FILES[@]}"; do
          if [[ "$(classify_path "$file")" == "$category" ]]; then
            matched=$((matched + 1))
          fi
        done
        [[ "$matched" -eq 0 ]] && continue

        if [[ "$printed_category" -eq 0 ]]; then
          printf '### %s\n\n' "$category"
          category_risk_note "$category"
          printed_category=1
        fi

        printf '#### [`%s`](%s) — %s\n\n' \
          "$(short_sha "$sha")" "$(commit_url "$sha")" "$subject"

        for file in "${CUR_FILES[@]}"; do
          if [[ "$(classify_path "$file")" != "$category" ]]; then
            continue
          fi
          printf -- '- [ ] `%s` — verify the behavior change matches the fix described above ([diff](%s)).\n' \
            "$file" "$(diff_url "$sha" "$file")"
          entries=$((entries + 1))
        done
        printf '\n'
        emit_tests_line "$TEST_SHA"
      done
    done

    if [[ "$entries" -eq 0 ]]; then
      printf '_The `fix:` commit(s) did not report any changed files, so there are no file-level review items._\n\n'
    fi
  fi

  # ---- Review note
  printf '## Review note\n\n'
  printf '_Known limitations and follow-up checks go here. Replace this placeholder before opening the pull request; call out anything the automated suite cannot cover, such as migrations, save compatibility, event contracts, or manual gameplay checks._\n\n'

  # ---- Related Issues
  printf '## Related Issues\n\n'
  printf 'Fixes #%s\n' "$ISSUE"
}

BODY_TMP="$(mktemp "${TMPDIR:-/tmp}/planetslib-pr-body.XXXXXX")"
emit_body > "$BODY_TMP"

if [[ -n "$OUTPUT" && "$OUTPUT" != "-" ]]; then
  if ! cat "$BODY_TMP" > "$OUTPUT"; then
    die "cannot write output file: $OUTPUT"
  fi
  printf '%s: wrote %s\n' "$PROG" "$OUTPUT" >&2
else
  cat "$BODY_TMP"
fi
