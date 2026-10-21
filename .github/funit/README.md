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
  The workflow also passes `--min-tests` so a suite that silently stops loading
  fails the summary even if the remaining tests pass.
- The workflow pins Factorio `2.1.22` instead of using the floating `latest`
  tag, so CI results are reproducible. The minimum test counts are set slightly
  below the current totals (130 base, 157 Space Age) to catch a missing suite
  without making every additive test change update the workflow.

The Space Age, Quality, Elevated Rails and Recycler mods are installed by the
headless Factorio distribution. They cannot be obtained through the mod portal
API, so the scenario lists enable or disable them explicitly.
