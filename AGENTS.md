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
helper_scripts/             Standalone dev helpers: asset generators, local FUnit runner, PR body/worktree helpers, Factorio docs CLI, release-boundary checker (NOT shipped)
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
workflow (`.github/workflows/funit.yml`) that runs it in a Factorio Docker container in four
scenarios: base and Space Age + Quality, each with entity replacements on and off. The suite is
development-only and is not shipped. CI should always use the `latest` Factorio image so tests run
against the newest engine release. Local headless runs have non-obvious harness requirements
(`auto_pause`, `mod-settings.dat`, the `====END====` signal, and report cleanup); see "Local headless
harness gotchas" in `test-mods/planetslib-funit-data/AGENTS.md`. There is still no general-purpose Lua
linter; `luac5.1 -p` can syntax-check test files that do not use `goto`.

#### Test-authoring principles

- **A test must be capable of failing.** Do not use `runner.assert(true, ...)`, early returns, or
  `pairs()` loops over whatever results happen to exist as a substitute for coverage.
- **Assert documented behavior, not current implementation details.** Derive expected values
  independently; do not call the helper under test to compute its own expected result.
- **Use explicit test/fixture IDs and explicit skips.** A missing result or an unexpected skip must
  fail the suite. Missing coverage is not a pass.
- **Execute the full scenario matrix.** Syntax checks are not tests. Run base and Space Age with
  entity replacements both on and off when the change can affect them.
- **Isolate mutable state.** Clear dedicated test areas, restore storage and migration baselines,
  and make cleanup run on failure as well as success.
- **Verify engine semantics before encoding them.** Prototype fields, ghost behavior, fixed-point
  positions, data/control-stage globals, and `remote.call` limitations are common sources of bogus
  tests.
- **Treat test failures as possible test bugs first.** Check fixtures, assumptions, stage ordering,
  and setup before changing production code.
- Detailed conventions and known pitfalls are in
  `test-mods/planetslib-funit-data/AGENTS.md`.

- **Testing is mandatory before a PR**: the contributor notes require changes to be tested, ideally with
  multiple planet mods installed. Add or extend the FUnit suite in
  `test-mods/planetslib-funit-data/` (see its `AGENTS.md` for the plan and conventions) and run it
  locally or let CI run it. Don't assume the suite runs automatically outside CI.
  Run `helper_scripts/lua_check.sh` for changed Lua files and the static conventions check
  (`python3 .github/scripts/check_funit_conventions.py`) before opening the PR.
- **Development test mods**: any test mod you write while developing a feature must be saved to
  `test-mods/<mod-name>/` (see `test-mods/README.md`). This keeps tests reproducible for reviewers
  while excluding them from release builds.
- **Docs**: `docs-source/` is the canonical documentation (Docusaurus). Build/serve it with
  `cd docs-source && npm install && npm start` (or `npm run build`).
  `./update_documentation.sh` rebuilds the committed `docs/` output (`rm -rf ../docs && mv build ../docs`)
  and writes the `CNAME`.
- **Release**: run `./bump_version.sh <minor|feature|major>` first. It bumps the version in `info.json`
  and prepends a `changelog.txt` entry with empty section headings for the release type
  (`minor`/`bugfix`/`patch` bump the patch digit and write `Bugfixes`;
  `feature` bumps the minor digit and writes `Features`, `Changes`; `major` bumps the major digit and writes
  `Features`, `Changes`, `Bugfixes`). It supports `--date YYYY-MM-DD|????` and `--dry-run`, and does not
  commit. `archive.sh` reads the version from `info.json`, so it needs no version update. Then fill in the
  changelog, commit, and push. `./archive.sh` remains the local packaging/docs-rebuild step: it creates a
  versioned zip (`git archive`) and regenerates the docs. To publish the committed version to the mod
  portal, run `node helper_scripts/publish_mod.mjs --dry-run` first and then
  `node helper_scripts/publish_mod.mjs`. The publisher reads the API key from the local-only,
  export-ignored `.env` file (`.env.example` is the tracked template) and uploads the version already in
  `info.json`; see `helper_scripts/README.md`. Use `--check-key` and `--verify` for non-publishing
  validation. Run `helper_scripts/export_check.sh` before packaging to verify the release boundary.
- **Packaging ignore**: `info.json`'s `package.ignore` and `.gitattributes` `export-ignore` exclude
  `*.py`, `*.bat`, `*.sh`, `*.exe`, `*.ps1`, `test-mods/`, and `.env`/`.env.*` from the release. Python
  helper scripts, development test mods, and local environment files must never ship.

### Gotchas / known inconsistencies

- `.github/workflows/deploy-site.yml` and `.gitignore` still reference a `./site` directory, but the docs
  live in `docs-source/`. Verify the path before relying on the workflow.
- `config.ld` is a legacy LDoc configuration (`docs_templates`/`docs_topics` no longer exist). The live
  docs are the Docusaurus site; don't spend time on LDoc.
- `api.lua`'s header comment says API docs live in `README.md`, but the README now only links to the docs
  site. When documenting a new API, update `docs-source/docs/usage-documentation/*` and/or `README.md`.
- `helper_scripts/` contains standalone development tools (asset generators, local test runners
  and shell helpers); they manage their own dependencies and are excluded from releases.
- `.env` is local-only: it is git-ignored and export-ignored. `.env.example` is the only tracked
  environment template.
- `publish_mod.mjs` publishes only the version already committed in `info.json`; it does not bump
  versions or edit `changelog.txt`. Both it and `archive.sh` derive the archive name from `info.json`.
- `archive.sh` derives the release archive name from `info.json`, so only `info.json` and the newest
  `changelog.txt` entry need to be updated when releasing.

## AI agent communication

When posting GitHub comments, reviews, or review replies under the repository owner's account,
end the message with a signature that names the model used, for example:

```
_Posted by DeepSeek V4.1 Flash._
```

When posting Github pull requests, begin the message with a similar signature.

For Factorio prototype/runtime API questions, use the `factorio-docs` subagent
(defined in `.opencode/agents/factorio-docs.md`, with a Claude Code shim in
`.claude/agents/factorio-docs.md`). It uses `helper_scripts/fdoc.py` instead of
ad-hoc JSON snippets; see the helper section below for the available commands.

### Self-learning retrospective

After a substantial task, run `/self-learn [focus]`. It calls the read-only `self-learn` subagent,
which grounds the retrospective in `git` state and repository files and returns a brief for the
primary agent: evidence, what worked, recurring friction, and a short list of helper scripts worth
writing. The brief ends with a direct prompt that the primary agent then carries out, unless the
user asked for analysis only. Definitions live in `.opencode/agents/self-learn.md` and
`.opencode/commands/self-learn.md`; `.opencode/` is development-only and excluded from releases.
Claude Code users get the same flow through `.claude/agents/self-learn.md` and
`.claude/commands/self-learn.md`; `CLAUDE.md` imports this file and points at the canonical definitions.

### Bugfix pull request format

For pull requests that contain PlanetsLib bugfixes, use the review-oriented format established by
[PR #130](https://github.com/danielmartin0/PlanetsLib/pull/130). That PR is the canonical example for
future AI-written bugfix PRs.

The body should contain, in order:

1. **Description** — state the source and target branches, explain that the test suite was hardened
   first, and summarize the commit structure. Keep the original bugfix commits separate from test
   infrastructure and CI changes.
2. **Checklist** — use the repository's pull request checklist. Do not check `README.md` unless the
   README itself was updated; mention documentation changes in `docs-source/` separately.
3. **Testing Notes** — list every tested Factorio scenario with the scenario name, test count, and
   failures/errors. Include the Factorio version used locally and note that CI runs the latest image.
   Also list syntax, Ruby, and diff checks that were run.
4. **Bugfix review scope** — identify the bugfix commits explicitly and state that test-only commits
   are excluded from the bugfix checklist.
5. **Categorized bugfix checklist** — group entries by area (for example entity replacement, ground
   diggers, backwards-compatibility helpers). For every entry:
   - start with an unchecked checkbox;
   - link each relevant file to its GitHub commit diff;
   - explain in plain language what behavior changed and what a reviewer should verify;
   - include a **Tests:** line linking every relevant automated test, preferably to the test
     file/section with a commit-pinned `blob` URL such as
     `https://github.com/<owner>/<repo>/blob/<full-commit-sha>/<path>#L10-L25`; list the test IDs
     covered. If there is genuinely no direct automated test, say so explicitly and link the closest
     related coverage instead of omitting the line;
   - call out migration, save-compatibility, or event-contract risks rather than hiding them.
   - when editing an existing pull request checklist, preserve every checkbox that a human has
     already marked `[x]`. Do not reset user-checked entries unless the user explicitly asks.

   Use a GitHub file-diff anchor rather than a generic repository link:

   ```text
   https://github.com/<owner>/<repo>/commit/<full-commit-sha>#diff-<sha256-of-file-path>
   ```

   The `diff-` fragment is the SHA-256 hex digest of the repository-relative file path. Link every
   file that contains a reviewable part of that bugfix, and use the commit that introduced the
   change rather than the PR's compare view. Generate the links with
   `python3 helper_scripts/pr_diff_links.py <commit>` instead of computing the SHA-256 by hand, or
   generate the complete body with `helper_scripts/pr_body.sh --issue <N>`.
6. **Review note** — add a short section for any known limitation or follow-up check that does not
   block the PR but should be considered by a human reviewer.
7. **Related Issues** — link related PRs or issues.

Titles for AI-generated PRs should start with `(AI-generated)` and describe the change, for example
`(AI-generated) FUnit hardening and PlanetsLib bugfixes`.

## Contribution checklist (from `.github/PULL_REQUEST_TEMPLATE.md`)

Before opening a PR, ensure:

1. Changes have been **tested** in-game (ideally with several planet mods).
2. Changes **do not break backwards compatibility**.
3. `changelog.txt` is updated — prepend a new entry at the top with the version and date, using the
   existing section headings (`Features`, `Changes`, `Bugfixes`, `Graphics`, `Locale`, `Optimizations`,
   `Info`). Set the date to the release date (leave `????` until released) and add attribution lines
   like `Thank you <name>!` for code, graphics, locale, or testing contributions. Do not credit people
   solely for reporting issues.
4. Documentation is updated: add/extend `docs-source/docs/...` (and `README.md` sections), and add new
   contributors to the Contributors list.
5. The version is bumped with `./bump_version.sh <minor|feature|major>`, which updates `info.json` and the
   top of `changelog.txt` together. `archive.sh` reads the version from `info.json`. The `Version` GitHub
   Actions workflow runs `.github/scripts/check_version.sh` to enforce consistency and comments the failure
   on the pull request, so a changelog entry cannot be added without bumping the mod version.

## Quick file-finding tips

- Public API: `api.lua` → then the referenced `lib/*.lua` module.
- Where a `PlanetsLib:extend/update` field is validated or applied: `lib/planet.lua`.
- Orbit/starmap math and native `origin` conversion: `lib/orbits.lua`, `prototypes/override-final/starmap.lua`.
- Runtime entity swapping: `scripts/entity-replacement.lua` + `lib/add-entity-replacement.lua`.
- Overrides by stage: `prototypes/vanilla-override` (data), `prototypes/override` (data-updates),
  `prototypes/override-final` (data-final-fixes).

## Factorio API docs helper

The `factorio-docs` agent answers prototype/runtime API questions from the local
Factorio documentation JSON under `/opt/factorio_space_age_21/doc-html`. Its
canonical definition is `.opencode/agents/factorio-docs.md`; Claude Code uses the
shim in `.claude/agents/factorio-docs.md`.

Lookups go through `helper_scripts/fdoc.py`, a single-file, stdlib-only CLI that
resolves prototype/class inheritance and formats results readably instead of
dumping raw JSON. Run `python3 helper_scripts/fdoc.py --help` for the commands
(`prototype`, `type`, `class`, `event`, `concept`, `define`, `get`, `member`,
`search`, `list`, `info`). Use `--docs-dir` or `FACTORIO_DOCS_DIR` when the
documentation lives elsewhere.
