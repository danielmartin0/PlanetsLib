# FUnit CI helpers

These CI files are adapted from the [FUnit](https://gitlab.com/jfletcher94/funit)
GitHub Actions template, which is licensed under
`LGPL-3.0-or-later WITH FUnit-CI-Exception`. The exception permits
project-specific CI adaptations to be copied and modified without applying
copyleft to this repository.

Copied from FUnit commit `2eafa24a3c6096928b2c5a68ae5a411b9cec6d2f`:

- `entrypoint.sh` — `entrypoint.sh`
- `prepare_test_environment.sh` — `scripts/prepare_test_environment.sh`

The Ruby helper scripts are not vendored. The workflow downloads the current
`expand_dependencies.rb` and `parse_funit_json.rb` from FUnit's `master` branch
so that upstream fixes and improvements are picked up automatically. FUnit
keeps these scripts backwards-compatible for this reason.

Project-specific changes:

- `prepare_test_environment.sh` uses `GITHUB_WORKSPACE` and reads the test
  config from `artifacts/PlanetsLib/test`, because PlanetsLib is a single-mod
  repository at the root and its fixtures live in
  `test-mods/planetslib-funit-data`. It also sets `enable-new-mods=false`, so a
  zip that is present but disabled in the scenario `mod-list.json` stays
  disabled. `planetslib-funit-settings` is one of those zips.
- `entrypoint.sh` treats `recycler` as a built-in mod, alongside `space-age`,
  `quality` and `elevated-rails`, so the mod updater does not try to download
  it. Reports are not renamed after each scenario; the scenario names its
  report (see below).
- `tests/scenario/control.lua` derives a unique report name from the active
  scenario, for example `planetslib-base-no-replacements`. This lets all four
  scenarios write their reports into the same `script-output` directory.
- The workflow runs `expand_dependencies.rb` against each scenario. Symlinks to
  the local PlanetsLib, FUnit, fixture mod and settings mod let the script
  resolve their dependencies without querying the mod portal.
- `test-mods/planetslib-funit-settings` is a checked-in, text-based settings
  mod that forces `PlanetsLib-enable-entity-replacements = false` and
  `PlanetsLib-disable-all-entity-replacements = true` for the no-replacements
  scenarios. It replaces the previous inline generated mod.
- `summarize_funit_results.rb` is a project-specific helper (not copied from
  upstream). It reads the per-scenario JSON reports and writes a Markdown
  summary to the GitHub step summary: scenario totals plus every failing test,
  its message and log excerpt. Missing or malformed reports are called out and
  include the relevant tail of the captured headless log. Failing tests are
  also emitted as `::error` annotations. The helper exits 0 on test failures so
  that the JUnit conversion step remains the single source of the job result.
  `--comment` writes a second copy for a pull request comment, truncated to
  GitHub's comment size limit, and `--github-output` records `failed=true|false`
  for the workflow's comment steps (which publish the payload as an artifact
  rather than commenting directly, see below).
- `.github/scripts/check_funit_conventions.py` is a project-specific static
  checker run by the `conventions` job before the Factorio matrix. It verifies
  that the `planetslib_funit` seam list in `control.lua` matches both test-doc
  seam lists, that every suite is in `tests/suites/manifest.lua`, that test IDs
  are unique, and that suites do not use `runner.assert(true, ...)` or the
  global `before_each`/`after_each` hooks. It is read-only, needs no secrets or
  Factorio, and can be run locally with:

  ```sh
  python3 .github/scripts/check_funit_conventions.py
  ```
- On a failing run for a pull request, the summary is posted as a comment on
  that PR (marked with a hidden per-channel tag such as
  `<!-- funit-results:stable -->`). A later passing run of the same channel
  deletes that channel's comment, so stale failures do not linger on the PR
  without hiding a failure in the other channel. Repeated failures update the
  existing comment instead of adding another one. If the run stops before the
  tests report at all (for example a failed archive build), the comment says so
  and names the jobs that did not succeed, so a red check is never left
  unexplained.
  Posting is done by `.github/workflows/funit-comment.yml`, not by the test
  workflow: the test workflow runs on `pull_request`, where forked pull
  requests get a read-only token, while a `workflow_run` workflow runs from the
  default branch with write access. The commenter never checks out or executes
  pull request code; it only reads the `funit-comment-<channel>` artifacts
  published by the test workflow and comments on the pull request whose head
  commit matches the triggering run. Because `workflow_run` only fires for
  workflows on the default branch, `funit-comment.yml` must be merged to `main`
  before it takes effect.
- The workflow runs the four scenarios twice, once per Factorio release
  channel: `stable` (`factoriotools/factorio:stable`) and `experimental`
  (`factoriotools/factorio:latest`). The stable leg catches breakage on the
  release players actually run; the experimental leg catches breakage before a
  new Factorio release reaches stable.

The Space Age, Quality, Elevated Rails and Recycler mods are installed by the
headless Factorio distribution. They cannot be obtained through the mod portal
API, so the scenario lists enable or disable them explicitly.
