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

## Asset generators

These scripts use [uv](https://docs.astral.sh/uv/) and manage their own
dependencies:

- `generate_visit_planet_achievement.py <planet-icon.png>` — build a visit-planet
  achievement icon.
- `generate_orbit_graphics.py <distance> <planet_name> <mod_name>` — build orbit
  sprites.
