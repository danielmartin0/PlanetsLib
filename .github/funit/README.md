# FUnit CI helpers

These CI files are adapted from the [FUnit](https://gitlab.com/jfletcher94/funit)
GitHub Actions template, which is licensed under
`LGPL-3.0-or-later WITH FUnit-CI-Exception`. The exception permits
project-specific CI adaptations to be copied and modified without applying
copyleft to this repository.

Copied from FUnit commit `b69c2f277a467726e3a8c555d48df5b647ec5a64`:

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
  `test-mods/planetslib-funit-data`.
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
  for the workflow's comment steps.
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
- On a failing run of a same-repository pull request, the workflow posts the
  summary as a new comment on that PR (marked with a hidden per-channel tag such
  as `<!-- funit-results:stable -->`). A later passing run of the same channel
  deletes that channel's comments, so stale failures do not linger on the PR
  without hiding a failure in the other channel. Fork PRs are skipped because
  their `GITHUB_TOKEN` is read-only; their summary remains in the step summary
  and annotations.
- The workflow runs the four scenarios twice, once per Factorio release
  channel: `stable` (`factoriotools/factorio:stable`) and `experimental`
  (`factoriotools/factorio:latest`). The stable leg catches breakage on the
  release players actually run; the experimental leg catches breakage before a
  new Factorio release reaches stable.

The Space Age, Quality, Elevated Rails and Recycler mods are installed by the
headless Factorio distribution. They cannot be obtained through the mod portal
API, so the scenario lists enable or disable them explicitly.
