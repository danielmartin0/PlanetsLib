# FUnit CI helpers

These scripts are vendored from the [FUnit](https://gitlab.com/jfletcher94/funit)
GitHub Actions template, which is licensed under
`LGPL-3.0-or-later WITH FUnit-CI-Exception`. The exception permits
project-specific CI adaptations to be copied and modified without applying
copyleft to this repository.

Sources (FUnit commit `b69c2f277a467726e3a8c555d48df5b647ec5a64`):

- `entrypoint.sh` — `entrypoint.sh`
- `prepare_test_environment.sh` — `scripts/prepare_test_environment.sh`
- `parse_funit_json.rb` — `scripts/parse_funit_json.rb`

Project-specific changes:

- `prepare_test_environment.sh` uses `GITHUB_WORKSPACE` and reads the test
  config from `artifacts/PlanetsLib/test`, because PlanetsLib is a single-mod
  repository at the root and its fixtures live in
  `test-mods/planetslib-funit-data`.
- `entrypoint.sh` renames `funit-report-planetslib.json` to
  `funit-report-<scenario>.json` after each scenario, so all four scenarios
  produce a separate report in the same job. It also treats `recycler` as a
  built-in mod, alongside `space-age`, `quality` and `elevated-rails`, so the
  mod updater does not try to download it.

`.github/workflows/funit.yml` also uses static scenario mod lists instead of
`expand_dependencies.rb`: the test mod is local, and the paid DLC mods are
supplied by the Factorio image rather than fetched through the public mod API.
The base scenarios set `space-age`, `quality` and `elevated-rails` to
`enabled: false` explicitly; omitting them would let Factorio's default mod
manager enable them. FUnit itself is packaged from a shallow GitLab clone at a
pinned commit, so no mod-portal credentials are required for the base test
matrix.
