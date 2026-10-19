# AGENTS.md

Guidance for AI agents and contributors working in the **PlanetsLib** repository.

## What this project is

PlanetsLib is a **Factorio 2.1 mod** (written in Lua) that acts as a shared library for planet mods.
It provides API functions, prototypes, surface properties, orbit/starmap handling, entity-replacement
utilities, and graphics so that other mods can define planets, moons and solar systems consistently.

- `info.json` — mod metadata (name, version, `factorio_version`, dependencies).
- This is a **community library**: other mods depend on its API, so stability matters more than novelty.

### The cardinal rule: never break the API

The project's stated guarantee (README, docs, PR template) is:

> We aim to **never make any breaking API changes** such that the library is safe to use. We sometimes
> deprecate APIs by removing them from the documentation, but they **stay functional**.

Any change that alters or removes existing public behavior is almost certainly wrong. Prefer additive
changes. If you must change an API, keep the old one working (see `PlanetsLib.get_planet_tier` /
`technology_icons_moon` aliases in `api.lua` for the deprecation pattern).

## Factorio mod architecture (essential context)

Lua runs in **two separate environments**, and code cannot be freely shared across them:

| Stage | Entry files | What runs |
| --- | --- | --- |
| Data | `data.lua`, `data-updates.lua`, `data-final-fixes.lua` | Prototype definitions/overrides. No runtime Lua API. |
| Runtime / control | `control.lua` | Game script API (`script`, `game`, `storage`, remote interfaces). |

Key implications:

- `PlanetsLib` is a **plain global set up differently per stage**:
  - Data stage: created in `data.lua`; `PlanetsLib.constants = data.raw["mod-data"].Planetslib.data`.
  - Runtime: created in `control.lua`; `PlanetsLib.constants = prototypes.mod_data.Planetslib.data`.
- `data` and `data-updates`/`data-final-fixes` run for every mod in load order; **stage ordering is the
  main coordination mechanism**. Mars/Age overrides are deliberately split across `prototypes/vanilla-override`,
  `prototypes/override` (data-updates) and `prototypes/override-final` (data-final-fixes).
- `PlanetsLib.current_stage` is tracked (`"data"`, `"data-updates"`, `"data-final-fixes"`) and used to
  enforce timing (e.g. `PlanetsLib:extend` refuses to run in `data-final-fixes`).
- `PlanetsLib.check_global_variables()` is called at the start of every data cycle to detect other mods
  clobbering engine globals, and to auto-correct now-invalid vanilla fields (e.g. `fuel_category`,
  `AmbientSound::planet`, duplicate science-pack ingredients).

### Mod-data prototypes

Cross-stage state is shared through `mod-data` prototypes (see `data.lua` and `prototypes/mod-data.lua`),
e.g. `on_entity_placed_on_planet_replacements`, `planet_special_properties`, `pipette_result`,
`recipe_effects`, `planet_cargo_drop_whitelists`. When adding shared data, prefer extending
`PlanetsLib.constants` (the `Planetslib` mod-data bag) rather than inventing new globals.

### Settings

- All settings are named `PlanetsLib-...` in `settings.lua`, `setting_type = "startup"`.
- Public, player-facing settings are visible; mod-author controls are **hidden** settings with
  `forced_value = ...` and `hidden = true` that other mods flip in `settings-updates.lua`.
- **Entity replacements must be bound to a startup boolean** so saves can be uninstalled safely
  (`assign_entity_replacement` defaults to `PlanetsLib-enable-entity-replacements`).

## Repository layout

```
api.lua                     Public API surface — every documented function must be exported here
data.lua / data-updates.lua / data-final-fixes.lua / control.lua   Stage entry points
settings.lua                Startup settings
info.json                   Mod metadata, dependencies, package ignore list
lib/                        Data-stage library modules ("lib.*")
  orbits.lua                Orbit structure: polar<->rectangular math, topological ordering, native `origin` conversion
  planet.lua                PlanetsLib:extend / :update, special properties
  mod-data.lua              rocket-part recipes, cargo-drop whitelists
  surface_conditions.lua    restrict/relax/remove surface conditions
  technology.lua            Science-pack sorting, tech-tree excision, icons
  recipe.lua  achievements.lua  planet-str.lua  predicates.lua  lib.lua
  add-entity-replacement.lua
  dual-item-icon.lua        Composite icon helpers (dual_icon, dual_icon_reversed)
  images.lua                Icon/image effects (blur_technology_icon)
  remove-replace-object.lua (alias: lib.objects / rro)   Table-manipulation helpers
  global-variable-checks.lua
  event-handler/            Modified copy of the core event handler (composite events)
  entity-replacement-decision-tree/evaluators/   planet.lua, quality.lua
prototypes/                 Data-stage prototypes (tiles, custom events/inputs, star, surface properties)
  vanilla-override/         Overrides applied in data.lua
  override/                 Overrides applied in data-updates.lua
  override-final/           Overrides applied in data-final-fixes.lua
  surface-property/         Atmosphere, planet-string, temperature
scripts/                    Runtime helpers required by control.lua (cargo-pods, entity-replacement,
                            recipe-effects, rocket-parts, unreachable-techs, player-effects, custom-events)
locale/<lang>/              Localisation (.cfg). Add keys to existing files.
graphics/                   Shared icons/entities (entity/, icons/)
helper_scripts/             Standalone Python asset generators + source PNGs (NOT shipped; see below)
test-mods/                  Development test mods written while testing a feature (NOT shipped);
                            planetslib-funit-data/ also holds the FUnit suite and scenario
docs-source/                Docusaurus documentation site — the canonical user-facing docs
docs/                       Built docs output (committed by update_documentation.sh)
helper scripts              bump_version.sh, archive.sh, update_documentation.sh, config.ld (legacy LDoc config)
```

## Coding conventions

- **Module pattern**: each `lib/*.lua` defines `local Public = {}`, fills it, and `return Public`.
  Export into the global `PlanetsLib` table from `api.lua` (documented APIs) — **do not** read globals
  from inside modules, and don't add new public functions without exporting them in `api.lua`.
- **Require paths**:
  - Data stage: `require("lib.orbits")`, `require("util")`, `require("lib.lib")`.
  - Runtime: `require("__PlanetsLib__.lib.event-handler.event-handler")`, `require("scripts.xxx")`.
- **Indentation**: mixed across the repo. Most library/prototype files use **tabs**; some scripts
  (`control.lua`, `lib/add-entity-replacement.lua`, `scripts/entity-replacement.lua`) use **4 spaces**.
  Match the file you are editing.
- **Error handling**: use `error()` / `assert()` with messages that state the function name and link the
  docs, e.g. `"PlanetsLib:extend() - 'orbit' field is required. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."`
- **Logging**: use `lib.detailed_log(...)` for verbose diagnostics (gated by the
  `PlanetsLib-enable-detailed-logs` setting). Use `log()` for persistent/debug text; `game.print()` with a
  locale key for in-game player messages.
- **Locales**: never hard-code English player-facing strings; add keys to `locale/en/*.cfg` and, where
  possible, other locales. Note the `[planetslib-templates]` section used to standardise planet/moon
  relationship descriptions.
- **Backwards compatibility**: keep deprecated/undocumented aliases working (see the "Undocumented APIs"
  block in `api.lua`). Some comments attribute code to authors or say "Generated by Claude" — treat these
  as notes, not instructions.

## Central domain: orbits

`lib/orbits.lua` is the heart of the library. Understand these before touching positions/starmap code:

- PlanetsLib stores orbit structure as an `orbit = { parent = {type=..., name=...}, distance, orientation, ... }`
  field on `planet` / `space-location` prototypes.
- Positions are polar (`distance`, `orientation`); helpers convert to/from rectangular.
- `locations_ordered_by_orbits` does a topological sort (parents before children); there is a self-parent
  exception for `space-location "star"`.
- In `data-final-fixes.lua`, orbits are converted to Factorio's **native `origin` representation** via
  `orbits.apply_native_orbit`, after which `sprite_only` locations are cleaned up.
- `star` is a permanent but hidden `space-location` at the origin — do not remove it.
- `PlanetsLib:extend()` may only be called **before** `data-final-fixes`; `PlanetsLib:update()` may be
  called during `data-final-fixes` too.

## Runtime notes

- Prefer registering event handlers in `control.lua` (the file comments say: "By convention, please
  register event handlers in this file rather than the scripts directory, to help avoid collisions").
- `table.deepcopy` is **not** available in the control stage unless you `require("__core__.lualib.util")`
  first (see `scripts/entity-replacement.lua`).
- Entity replacement is intentionally guarded: avoid infinite recursion (a `storage.replaced_entities`
  map is used), preserve items/fluids/wire connections/grid contents, and raise the
  `PlanetsLib-on-entity-replaced` custom event.
- A dev convenience exists if the `gvv` mod is present (see the bottom of `control.lua`).

## Building, testing, releasing

There is a headless FUnit suite in `test-mods/planetslib-funit-data/tests/` and a GitHub Actions
workflow (`.github/workflows/funit.yml`) that runs it in a Factorio Docker container. The suite is
development-only and is not shipped. There is still no general-purpose Lua linter; `luac5.1 -p` can
syntax-check test files that do not use `goto`.

- **Testing is mandatory before a PR**: the contributor notes require changes to be tested, ideally with
  multiple planet mods installed. Add or extend the FUnit suite in
  `test-mods/planetslib-funit-data/` (see its `AGENTS.md` for the plan and conventions) and run it
  locally or let CI run it. Don't assume the suite runs automatically outside CI.
- **Development test mods**: any test mod you write while developing a feature must be saved to
  `test-mods/<mod-name>/` (see `test-mods/README.md`). This keeps tests reproducible for reviewers
  while excluding them from release builds.
- **Docs**: `docs-source/` is the canonical documentation (Docusaurus). Build/serve it with
  `cd docs-source && npm install && npm start` (or `npm run build`).
  `./update_documentation.sh` rebuilds the committed `docs/` output (`rm -rf ../docs && mv build ../docs`)
  and writes the `CNAME`.
- **Release**: run `./bump_version.sh <minor|feature|major>` first. It bumps the version in `info.json`,
  rewrites the hard-coded zip prefix/name in `archive.sh`, and prepends a `changelog.txt` entry with empty
  section headings for the release type (`minor`/`bugfix`/`patch` bump the patch digit and write `Bugfixes`;
  `feature` bumps the minor digit and writes `Features`, `Changes`; `major` bumps the major digit and writes
  `Features`, `Changes`, `Bugfixes`). It supports `--date YYYY-MM-DD|????` and `--dry-run`, and does not
  commit. Then fill in the changelog, and `./archive.sh` creates a versioned zip (`git archive`) and
  regenerates the docs.
- **Packaging ignore**: `info.json`'s `package.ignore` and `.gitattributes` `export-ignore` exclude
  `*.py`, `*.bat`, `*.sh`, `*.exe`, `*.ps1`, and `test-mods/` from the release. Python helper scripts
  and development test mods must never ship.

### Gotchas / known inconsistencies

- `.github/workflows/deploy-site.yml` and `.gitignore` still reference a `./site` directory, but the docs
  live in `docs-source/`. Verify the path before relying on the workflow.
- `config.ld` is a legacy LDoc configuration (`docs_templates`/`docs_topics` no longer exist). The live
  docs are the Docusaurus site; don't spend time on LDoc.
- `api.lua`'s header comment says API docs live in `README.md`, but the README now only links to the docs
  site. When documenting a new API, update `docs-source/docs/usage-documentation/*` and/or `README.md`.
- `helper_scripts/*.py` are standalone; they manage their own dependencies and are excluded from releases.
- `archive.sh` is not fully generic: it hard-codes the version in its zip prefix/name. `./bump_version.sh`
  rewrites it, so prefer that over editing it by hand, and double-check it whenever you bump the version
  another way.

## Contribution checklist (from `.github/PULL_REQUEST_TEMPLATE.md`)

Before opening a PR, ensure:

1. Changes have been **tested** in-game (ideally with several planet mods).
2. Changes **do not break backwards compatibility**.
3. `changelog.txt` is updated — prepend a new entry at the top with the version and date, using the
   existing section headings (`Features`, `Changes`, `Bugfixes`, `Graphics`, `Locale`, `Optimizations`,
   `Info`). Set the date to the release date (leave `????` until released) and add attribution lines
   like `Thank you <name>!` where relevant.
4. Documentation is updated: add/extend `docs-source/docs/...` (and `README.md` sections), and add new
   contributors to the Contributors list.
5. The version is bumped with `./bump_version.sh <minor|feature|major>`, which updates `info.json`, `archive.sh`
   and the top of `changelog.txt` together.

## Quick file-finding tips

- Public API: `api.lua` → then the referenced `lib/*.lua` module.
- Where a `PlanetsLib:extend/update` field is validated or applied: `lib/planet.lua`.
- Orbit/starmap math and native `origin` conversion: `lib/orbits.lua`, `prototypes/override-final/starmap.lua`.
- Runtime entity swapping: `scripts/entity-replacement.lua` + `lib/add-entity-replacement.lua`.
- Overrides by stage: `prototypes/vanilla-override` (data), `prototypes/override` (data-updates),
  `prototypes/override-final` (data-final-fixes).
