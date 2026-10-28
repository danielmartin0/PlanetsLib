# helper_scripts

Development-only scripts and source assets. Nothing in this directory ships in
a PlanetsLib release (see `.gitattributes` and `info.json`'s `package.ignore`).

## Publish to the mod portal

`publish_mod.mjs` packages the current HEAD with `git archive` and uploads it to
the Factorio mod portal using the same endpoints as `semantic-release-factorio`:
`/api/v2/mods/releases/init_upload`, followed by the returned upload URL.

Bump the version with `./bump_version.sh`, fill in `changelog.txt`, commit, and
push before publishing. The script reads the API key from `.env` at the
repository root:

```sh
cp .env.example .env   # then put FACTORIO_API_KEY=<key> in .env
chmod 600 .env
node helper_scripts/publish_mod.mjs --check-key
node helper_scripts/publish_mod.mjs --dry-run
node helper_scripts/publish_mod.mjs
node helper_scripts/publish_mod.mjs --verify
```

The API key needs the `ModPortal: Upload Mods` permission. `--check-key` also
uses the `edit_details` endpoint, which requires `ModPortal: Edit Mods`.
`FACTORIO_TOKEN` and `MOD_UPLOAD_API_KEY` are accepted as aliases. `.env` is
ignored by git and excluded from release archives; `.env.example` is the tracked
template.

Useful options:

- `--dry-run` — validate and package without uploading. The generated
  `PlanetsLib_<version>.zip` is kept so it can be inspected.
- `--check-key` — check the API key with a non-publishing `edit_details`
  request and exit.
- `--verify` — check `/api/mods/<name>/full` for the `info.json` version and
  print its file name, SHA1, and release time; exits non-zero if the version is
  absent.
- `--zip PATH` — upload an existing zip instead of building one.
- `--keep-archive` — keep the generated `PlanetsLib_<version>.zip` after a real
  publish.
- `--yes` — skip the confirmation prompt.
- `--allow-dirty` / `--allow-any-branch` — relax the preflight checks.
- `--skip-version-check` — allow uploading a version already on the portal (the
  portal will normally reject it).
- `--api-base URL` — override the mod portal base URL, useful for local mocks.

Run the regression suite against a loopback mock portal with:

```sh
node helper_scripts/test_publish_mod.mjs
```

The suite creates a temporary git repository and never contacts the real mod
portal. The script requires Node.js 18 or newer for built-in `fetch`,
`FormData`, and `Blob`.

## Local FUnit matrix

`run_funit_local.py` builds PlanetsLib and the companion test mods from the
current working tree, runs the four CI scenarios, stops Factorio after FUnit's
`====END====` signal, and prints a compact report summary.

```sh
helper_scripts/run_funit_local.py \
    --factorio /opt/factorio_space_age_21 \
    --funit-zip /path/to/funit_1.1.0.zip
```

Useful options:

- `--scenario space-age` — run one scenario (repeatable).
- `--no-build` — reuse the zips already in the run directory.
- `--run-dir PATH` — scratch directory (default `/tmp/opencode/planetslib-funit`).
- `--timeout SECONDS` — per-scenario timeout (default 300).

The script writes reports and logs under `--run-dir/reports` and
`--run-dir/logs`. It never modifies the repository.

## Pull-request worktree

`pr_worktree.sh` fetches a pull request's head commit into a local `pr/<number>`
branch, creates a worktree, and prints its commits, diff stat, and changed files.

```sh
helper_scripts/pr_worktree.sh 135
helper_scripts/pr_worktree.sh 135 --dir /tmp/planetslib-pr-135 --base origin/main
```

It only fetches and checks out the PR; it does not execute PR code. Remove the
worktree with:

```sh
git worktree remove /tmp/opencode/planetslib-pr-135
```

## Pull-request diff links

`pr_diff_links.py` prints commit-pinned GitHub `#diff-<sha256>` links for every
file changed by a commit. The bugfix PR format uses these anchors so reviewers
can jump directly to the relevant file diff.

```sh
python3 helper_scripts/pr_diff_links.py 32d86ea
python3 helper_scripts/pr_diff_links.py 32d86ea --format json
python3 helper_scripts/pr_diff_links.py HEAD --base origin/main
```

Options:

- `COMMIT` — commit to link; defaults to `HEAD`.
- `--base REF` — use `REF...COMMIT`; without it the commit is compared with its
  first parent.
- `--repo OWNER/REPO` — override the GitHub repository inferred from `origin`.
- `--format markdown|json` — output Markdown bullets or structured JSON.

The script is read-only. It only reads git metadata, never checks out code,
contacts the network, or executes pull-request code. It exits with an
explanation if the origin remote is not a GitHub URL and `--repo` is omitted.

Validation:

```sh
python3 -m py_compile helper_scripts/pr_diff_links.py
python3 helper_scripts/pr_diff_links.py 32d86ea
```

## Bugfix PR body generator

`pr_body.sh` builds the review-oriented bugfix PR body described in `AGENTS.md`:
commit-pinned links, the checklist from `.github/PULL_REQUEST_TEMPLATE.md`,
Testing Notes from an FUnit log, and categorized diff links for the `fix:`
commits.

```sh
helper_scripts/pr_body.sh --issue 139 \
  --test-file test-mods/planetslib-funit-data/tests/suites/entity_replacement_migration.lua \
  --test-ids ENT-13i,ENT-13j --test-lines L610-L779 \
  --funit-log /tmp/opencode/planetslib-funit/logs/base.log
```

Use `--base REF` when the base is not `origin/main`, `--output FILE` to write
the Markdown to a file, and `--factorio-version` when no FUnit log is available.
The script only reads git metadata and local files; it never calls `gh` or
mutates the repository.

## Planet-discovery icon campaign

Three scripts support auditing and upstreaming planet-discovery icon changes.
They are read-only with respect to the repository and never call `gh` or push.

### `mod_portal_repos.py`

Checks whether mod-portal pages link to a live Git repository. It reads
`source_url` and `homepage` from `/api/mods/<name>/full`, classifies the host,
and performs an unauthenticated `HEAD` request. Results are Markdown by default;
`--json` returns structured data.

```sh
python3 helper_scripts/mod_portal_repos.py --mod linox --mod cubium
python3 helper_scripts/mod_portal_repos.py --mods-file mods.txt --json
```

`--delay` throttles requests. `--git-host` adds a self-hosted Git host.
Validation:

```sh
python3 -m py_compile helper_scripts/mod_portal_repos.py
python3 helper_scripts/mod_portal_repos.py --self-test
```

### `audit_planet_tech_icons.py`

Reads a `--dump-data` JSON file, finds technologies that unlock a `planet`
prototype, resolves the primary icon from the supplied `--mods-dir`, measures
the planet disc, and suggests `shadow_scale` using the vanilla ratio
(`0.84375 * icon_size / disc_px`). Baked-in shadows are a human decision:
`--decisions FILE` loads previous `true`/`false` values and writes a skeleton
for any technology that does not have one yet. `--out FILE` writes a campaign
JSON suitable for `mod_icon_pr_body.py`.

```sh
uv run helper_scripts/audit_planet_tech_icons.py \
    --dump /tmp/opencode/iconcheck/script-output/data-raw-dump.json \
    --mods-dir /tmp/opencode/perf-final/mods \
    --factorio-data /opt/factorio_space_age_21/data \
    --decisions /tmp/opencode/planet-icon-decisions.json \
    --out /tmp/opencode/planet-icon-campaign.json
```

Use `--mod NAME` to narrow the report, `--exclude-tech NAME` to drop a
non-discovery technology or a special case, and `--include-space-locations` to
include non-planet locations. Validation:

```sh
uv run helper_scripts/audit_planet_tech_icons.py --self-test
```

### `render_tech_icon_diff.py`

Runs Factorio twice with `--dump-icon-sprites` (original mod and modified mod),
then writes `before.png`, `after.png`, and a labelled `diff.png` per technology.
It builds scratch mod directories with symlinks and never edits the mod
repository or the supplied mods directory.

```sh
uv run helper_scripts/render_tech_icon_diff.py \
    --factorio /opt/factorio_space_age_21 \
    --mods-dir /tmp/opencode/planet-test/sets/linox/mods \
    --mod /tmp/opencode/planet-test/testroots/linox/linox_1.8.11 \
    --before-mod /tmp/opencode/perf-final/mods/linox_1.8.11.zip \
    --tech linox-technology_planet-discovery-linox \
    --out /tmp/opencode/linox-icon-diff
```

`--before-mod` may be a mod directory or a release zip; if omitted, the script
looks for the installed version in `--mods-dir`. `--keep` preserves the scratch
directories. Validation:

```sh
uv run helper_scripts/render_tech_icon_diff.py --self-test
```

### `mod_icon_pr_body.py`

Turns a campaign JSON file into the Markdown body used for the external icon
pull requests. It preserves the campaign intro, emits the per-technology
changes and shadow-scale rationale, embeds the screenshots, and appends the
testing notes and signature. It only writes Markdown; `--verify-urls` performs
GET/HEAD checks on the screenshot links.

```sh
python3 helper_scripts/mod_icon_pr_body.py \
    --campaign /tmp/opencode/planet-icon-campaign.json \
    --output /tmp/opencode/body.md --verify-urls
```

Validation:

```sh
python3 -m py_compile helper_scripts/mod_icon_pr_body.py
python3 helper_scripts/mod_icon_pr_body.py --self-test
```

## Lua syntax check

`lua_check.sh` runs `luac` over changed/untracked Lua files and checks
`git diff --check`. It uses `luac5.2` when available, otherwise `luac`; set
`LUAC` to override. `--all` checks every tracked/untracked Lua file.

```sh
helper_scripts/lua_check.sh
helper_scripts/lua_check.sh --all
LUAC=luac5.2 helper_scripts/lua_check.sh --no-diff-check
```

## Release export boundary

`export_check.sh` verifies with `git check-attr` that development paths are
`export-ignore`d and runtime files and `locale/en/` are not. `--ref` checks a
historical tree; `--require-path` is the negative self-test for the detector.

```sh
helper_scripts/export_check.sh
helper_scripts/export_check.sh --ref HEAD
helper_scripts/export_check.sh --require-path .github/funit/README.md
```

## Factorio API docs (`fdoc.py`)

`fdoc.py` is a fast, read-only CLI over the local Factorio documentation JSON
(`prototype-api.json` and `runtime-api.json`). It resolves inherited
prototype/class members and formats one answer per command instead of requiring
ad-hoc `json.load()` snippets.

```sh
python3 helper_scripts/fdoc.py info
python3 helper_scripts/fdoc.py prototype accumulator
python3 helper_scripts/fdoc.py class LuaInventory
python3 helper_scripts/fdoc.py event on_built_entity
python3 helper_scripts/fdoc.py search "circuit wire"
```

The default docs directory is `/opt/factorio_space_age_21/doc-html`; override it
with `--docs-dir` or `FACTORIO_DOCS_DIR`. The tracked
`.opencode/agents/factorio-docs.md` agent uses this helper, and
`.claude/agents/factorio-docs.md` is the Claude Code shim for the same
definition.

## Asset generators

These scripts use [uv](https://docs.astral.sh/uv/) and manage their own
dependencies:

- `generate_visit_planet_achievement.py <planet-icon.png>` — build a visit-planet
  achievement icon.
- `generate_orbit_graphics.py <distance> <planet_name> <mod_name>` — build orbit
  sprites.
