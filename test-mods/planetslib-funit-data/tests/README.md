# FUnit tests for PlanetsLib

Headless [FUnit](https://mods.factorio.com/mod/funit) test suite for PlanetsLib.

Current status: both entity-replacements axes must finish with zero failures and
zero errors in the base and Space Age + Quality scenarios. The FUnit report and
JUnit conversion in CI are the source of truth for test counts; do not hardcode
totals here. Space Age-only fixtures and suites are skipped dynamically
(`mods["space-age"]` at the data stage, `script.active_mods["space-age"]` at
runtime). The base scenario keeps the built-in `recycler` mod enabled but
disables Space Age, Quality and Elevated Rails.

The same suite runs in CI in four scenarios: base and Space Age + Quality, each
with entity replacements on and off. The CI-only
`test-mods/planetslib-funit-settings` mod forces
`PlanetsLib-enable-entity-replacements = false` for the no-replacements
scenarios; `ENT-0` asserts that the setting matches the scenario. All four
scenario runs were validated locally against Factorio 2.1.23; the container
workflow itself is exercised by GitHub Actions.

Everything lives inside the `planetslib-funit-data` companion mod so the tests
can be developed next to the data-stage fixtures whose prototypes they assert
on. The scenario is only a thin launcher; the suites are required from this mod
as `__planetslib-funit-data__.tests.suites.<name>`.

See [`../AGENTS.md`](../AGENTS.md) for the full test plan, conventions and the
list of known bugs the suite pins down.

## Layout

- `scenario/control.lua` — scenario entry point. Loads
  `__base__/script/freeplay/control.lua`, registers PlanetsLib with FUnit, sets
  a scenario-specific report name (for example `planetslib-base`), then loads
  each suite listed in `suites/manifest.lua`.
- `suites/manifest.lua` — ordered list of suite module names.
- `suites/<name>.lua` — a suite returning `function(runner) ... end`.
- `scenario/description.json` / `scenario/mod-list.json` — scenario metadata and
  required mods.
- `../test/server-settings.json` / `../test/player-data.json` — server settings
  used by the headless CI run.
- `legacy/` — old non-FUnit scenario scripts, retained for reference. They are
  not loaded by the scenario.

## Running locally

For the full four-scenario matrix, use the local runner:

```sh
helper_scripts/run_funit_local.py \
  --factorio /path/to/factorio \
  --funit-zip /path/to/funit_1.1.0.zip
```

It packages the working tree (including uncommitted changes), runs base and
Space Age with entity replacements on and off, stops Factorio after FUnit's
`====END====` signal, and prints a report summary. The manual steps below are
useful when debugging the harness itself.

1. Install [FUnit](https://mods.factorio.com/mod/funit).
2. Put `PlanetsLib` and `test-mods/planetslib-funit-data` in your mods directory.
3. Copy `scenario/` to `<Factorio user data>/scenarios/funit`.
4. Enable the mods listed in `scenario/mod-list.json`. The checked-in list is the
   base scenario: Space Age, Quality and Elevated Rails are explicitly disabled
   (and the built-in `recycler` mod is enabled). The optional
   `planetslib-funit-settings` mod is also disabled. Set the three DLC entries
   to `"enabled": true` to run the full Space Age + Quality suite.
5. Run:
   ```
   factorio --start-server-load-scenario funit --mod-directory <mods>
   ```
6. The report is written to
   `script-output/funit-report-planetslib-base.json`. The report name reflects
   the active DLC and entity-replacement setting; the CI scenarios use
   `planetslib-base`, `planetslib-base-no-replacements`,
   `planetslib-space-age` and `planetslib-space-age-no-replacements`. The CI
   workflow overrides `mod-list.json` for each scenario, so the checked-in list
   only affects local runs.

The CI workflow (`.github/workflows/funit.yml`) does steps 2–5 automatically
inside the `factoriotools/factorio:latest` job container. It builds PlanetsLib,
this companion mod, the settings mod and FUnit as local zips, runs the four
scenarios, and converts the per-scenario JSON reports to JUnit XML. Each
scenario starts from a list with explicit DLC and `recycler` entries, then runs
FUnit's upstream `expand_dependencies.rb` against local copies of the mods so no
mod-portal lookup is needed. The base scenarios explicitly disable `space-age`,
`quality` and `elevated-rails`; the DLC mods are installed by the headless
Factorio distribution and cannot be downloaded through the mod portal API. The
CI-only `test-mods/planetslib-funit-settings` mod forces entity replacements off
for the no-replacements scenarios. The helper scripts and their upstream
provenance are documented in [`.github/funit/README.md`](../../../.github/funit/README.md).

## Tests that drive stateful PlanetsLib internals

Functions that manipulate `storage` or entities cannot be called from another
mod's Lua environment. PlanetsLib registers a test-only remote interface,
`planetslib_funit`, when FUnit is active (see the guarded block at the end of the
root `control.lua`). Call it as:

```
remote.call("planetslib_funit", "replace_entity", entity, "new-entity", false)
```

Available seam functions: `replace_entity`, `on_built_entity`,
`construct_ground_digger`, `on_entity_built`, `ground_digger_collisions`,
`revive_ground_digger_ghost`, `select_digger_ghost`,
`on_configuration_changed`, `migrate_entity_replacement_rules`,
`orientations_differ`, `warn_on_join`, `should_warn_on_join`,
`warn_cargo_pod_canceled`, `pod_contents_is_allowed`, `examine_cargo_pods`,
`entity_removal_floors_is_enabled`,
`entity_removal_floors_on_marked_for_deconstruction`,
`entity_removal_floors_on_tile_built`,
`entity_removal_floors_on_script_raised_set_tiles`,
`entity_removal_floors_on_tile_mined`, `entity_removal_floors_on_undo_applied`,
`entity_removal_floors_process_pending_tile_cleanup`,
`entity_removal_floors_prune_invalid_entries`,
`entity_removal_floors_floor_bounds`, `entity_removal_floors_analyse_floor`,
`entity_removal_floors_select_replacement_tile`,
`entity_removal_floors_select_replacement_tile_for_tile`,
`entity_removal_floors_has_stationary_roboport_coverage`,
`entity_removal_floors_queue_entity`, `entity_removal_floors_apply_undo_actions`,
`entity_removal_floors_clear_surface_state`,
`entity_removal_floors_get_queued`, `entity_removal_floors_get_cleanup`.

## Data-stage fixtures

`planetslib-funit-data` exercises PlanetsLib's data-stage API inside `pcall` and
records pass/fail into the `PlanetsLib-funit-results` mod-data prototype. Suite
files assert on that bag at runtime. Fixtures are split across the `data`,
`data-updates` and `data-final-fixes` stages via separate lists under
`../prototypes/fixtures/manifest.lua`.

Use `lib/results.lua` deliberately:

* `results.record(suite, id, ok, err)` for a real check.
* `results.skip(suite, id, reason)` when the check cannot run in this scenario
  (for example, a Space-Age-only fixture in a base game). Skips are recorded as
  `skipped = true`; `tests/suites/smoke.lua` fails on any skip that is not in
  its scenario-specific allowlist, so a scenario cannot pass by skipping the
  feature it was meant to test.
* `results.note(suite, id, text)` for information that is not a check.

Prefer `tests/suites/support.lua` when asserting fixture results. Pass an
explicit `expected` id list so a fixture that silently stops recording an id
fails the suite; a `pairs()` loop over whatever happens to be present cannot
detect that.
