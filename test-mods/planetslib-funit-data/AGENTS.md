# AGENTS.md — PlanetsLib FUnit test suite

This folder is the **development-only** companion mod for testing
[PlanetsLib](../../). It is excluded from release builds (see the root
`AGENTS.md` and `.gitattributes`). Everything here is for testing; nothing here
ships to players.

> **Do not fan out the work across many parallel subagents.** Spawning one agent
> per test/suite hits provider rate limits almost immediately and creates
> conflicting edits. Implement **one suite at a time** (or a small sequential
> batch), run the linter, then move on. This file is the single source of truth
> for the plan and conventions.

---

## 1. Architecture

PlanetsLib runs Lua in two separate environments, and so do the tests:

| Stage | Where the code runs | How it is tested |
| --- | --- | --- |
| Data (`data.lua`, `data-updates.lua`, `data-final-fixes.lua`) | This mod's data-stage fixtures | Call the API inside `pcall`; record the result in the `PlanetsLib-funit-results` mod-data prototype. |
| Runtime (`control.lua`, scripts) | FUnit scenario + PlanetsLib's control stage | Real entities/events, FUnit's `assert`/`after_n_ticks_do`/`on_event_do`, and the `planetslib_funit` remote interface. |
| Pure helpers | Any stage | `require("__PlanetsLib__.lib.*")` directly from a suite. |

Because the data stage is gone by runtime, data-stage APIs are **called by the
fixtures** (this mod) and **asserted by the suites** (runtime) against the
read-only `prototypes` table and the recorded results bag. This is why the test
scenario lives inside this mod: every test depends on the prototypes and
fixtures defined here.

### Directory map

```
test-mods/planetslib-funit-data/
  AGENTS.md                  <- this file (plan + conventions)
  info.json, settings.lua
  data.lua                   <- creates results bag, requires data fixtures
  data-updates.lua           <- data-updates fixtures
  data-final-fixes.lua       <- final-fixes fixtures
  lib/results.lua            <- results.record(suite, id, ok, err) helper
  prototypes/fixtures/       <- one fixture file per data-stage area
    manifest.lua             <- stage-by-stage fixture lists
  test/
    server-settings.json     <- headless CI server settings
    player-data.json         <- headless CI player data
  tests/
    README.md
    scenario/                <- copy to <user data>/scenarios/funit
      control.lua            <- thin FUnit launcher
      description.json
      mod-list.json
    suites/                  <- one suite file per test area
      manifest.lua           <- ordered list of suite modules
    legacy/                  <- old non-FUnit scenario scripts, not run
```

The CI-only settings mod lives outside this mod at
`test-mods/planetslib-funit-settings`; it forces entity replacements off for the
no-replacements scenarios.

### Runtime seams (root `control.lua`)

When FUnit is active, PlanetsLib registers `planetslib_funit` and registers with
FUnit's event mocker. Available calls:

```lua
remote.call("planetslib_funit", "replace_entity", entity, new_entity, raise_built)
remote.call("planetslib_funit", "on_built_entity", event, swap_target, dont_raise_built)
remote.call("planetslib_funit", "construct_ground_digger", event)
remote.call("planetslib_funit", "on_entity_built", event)
remote.call("planetslib_funit", "on_configuration_changed", configuration_changed_data)
remote.call("planetslib_funit", "pod_contents_is_allowed", pod_contents, planet_name)
remote.call("planetslib_funit", "examine_cargo_pods", platform, planet_name)
```

These are additive and inert unless FUnit is active. Do not widen them without
updating this file and `tests/README.md`.

---

## 2. Conventions

### Suite file contract

Every `tests/suites/<name>.lua` returns a function taking the shared runner:

```lua
return function(runner)
  runner.test("PREFIX-1 short description", function()
    runner.assert(condition, "what failed and why")
  end)
end
```

- **One file per area.** The suite file is listed in `tests/suites/manifest.lua`.
  A stub exists for every listed name; the scenario fails if a listed file is
  missing.
- **Never call `runner.before_each` / `runner.after_each`.** FUnit has a single
  global hook pair; a suite setting it would silently replace every other
  suite's hook. Do setup/cleanup inside each test.
- **Test names are stable IDs** (`ORB-1`, `TECH-9`, ...) so failures map back to
  this plan. Keep IDs unique.
- **Deterministic.** No wall-clock, no unordered-table assertions, no reliance
  on the game running for a fixed time. Use `after_n_ticks_do` when you need
  ticks and nest calls (FUnit only allows one non-nested call at a time).
- **Clean up** entities/surfaces you create, even on failure. Use a per-test
  `pcall` + `pcall(cleanup)` or unique positions/names so leftovers cannot
  affect later tests.
- **Unique prototype names**, always prefixed `funit-` (e.g. `funit-planet-a`).
- **Never edit `lib/` or `scripts/` to make a test pass.** If a test exposes a
  real bug, keep the test asserting the documented behavior and report the bug.
  Fixes are made separately (see §5).

### Data fixture pattern

```lua
local results = require("lib.results")

local ok, err = pcall(function()
  -- call the PlanetsLib data-stage API, then assert the result
  PlanetsLib.assign_entity_replacement("nauvis", "iron-chest", "steel-chest",
    "planetslib-funit-data-enable-entity-replacement-fixture")
  assert(data.raw.planet.nauvis, "nauvis missing")
end)
results.record("entity_replacement_data", "ENT-1", ok, err)
```

- `results.record(suite, id, ok, err)` writes to
  `data.raw["mod-data"]["PlanetsLib-funit-results"].data[suite][id]`.
- Fixtures on different stages: put `require(...)` names in the matching list in
  `prototypes/fixtures/manifest.lua`. Stage order is: all mods' `data.lua` → all
  `data-updates.lua` → all `data-final-fixes.lua`. PlanetsLib loads first
  (dependency), so PlanetsLib's own final-fixes has **already run** when this
  mod's final-fixes fixtures execute.
- Fixtures must not assume Space Age/Quality. Guard with `mods["space-age"]` or
  prototype existence checks. Fixtures whose whole area needs the
  space-travel feature are listed in `SPACE_AGE_ONLY` in
  `prototypes/fixtures/manifest.lua`; the matching runtime suite returns early
  when `script.active_mods["space-age"]` is nil. Keep the base scenario green.
- To create a valid test planet, deepcopy an existing planet before modifying it:

  ```lua
  local planet = table.deepcopy(data.raw.planet.nauvis)
  planet.name = "funit-my-planet"
  data:extend({ planet })
  ```

  (This mod's data stage has `table.deepcopy` via `util`.)

### Runtime suite pattern

```lua
local RESULTS = "PlanetsLib-funit-results"

local function fixture(runner, suite)
  local bag = prototypes.mod_data[RESULTS]
  runner.assert(bag, "results bag missing; is planetslib-funit-data enabled?")
  return bag.data[suite]
end

return function(runner)
  runner.test("ENT-5 ...", function()
    local entries = fixture(runner, "entity_replacement_data")
    runner.assert(entries["ENT-1"].ok, entries["ENT-1"].err)
    -- ... create entities, call remote.call("planetslib_funit", ...), assert
  end)
end
```

- Assert the **recorded** data-stage results (`entry.ok`) and, where useful, the
  real prototypes (`prototypes.planet[...]`, `prototypes.technology[...]`,
  `prototypes.recipe[...]`, `prototypes.mod_data[...]`).
- Player-action events that cannot be raised naturally may be mocked with
  `require("__funit__.mock").mock_event{...}`. Mocking does not respect event
  filters and only reaches handlers of mods that registered with the mocker
  (PlanetsLib now does when FUnit is active).
- Custom **inputs** (`PlanetsLib-build`, etc.) cannot be mocked or raised. Drive
  their handler through the `planetslib_funit` seam with a synthetic event
  table instead.

---

## 3. Full test plan

Status: every suite listed in `tests/suites/manifest.lua` is implemented (no
stubs), and every fixture listed in `prototypes/fixtures/manifest.lua` is
implemented for its stage. Against Factorio 2.1.22 the suite runs **143 tests
with 0 failures/errors** with Space Age + Quality and **121 tests with 0
failures/errors** in a base-only game; Space Age-only fixtures/suites are
filtered out when `mods["space-age"]` is nil (see `tests/README.md` for how to
run it). Check the files for the current state.

### A. Pure runtime helper suites

| Suite | IDs | What to cover |
| --- | --- | --- |
| `orbits` (done) | ORB-1..4 | Rectangular/polar cardinal values; round-trip; `origin` table and array forms; combined offset. |
| `lib_helpers` | LIB-1.. | `lib.merge/find/contains/sort/wrap_single_config/event_name/build+destroy events`; `rro.deep_equals` (incl. `_any`, functions), `remove/replace/no_duplicates`, `deep_replace/deep_gsub/deep_replace_field`, `replace_field/name`, `contains*`, `find_contains/find_many`, `soft_insert`, `merge/util_merge`, `get_concatenation`, `safe_find`, `copy_fields`, `count`, `keys`, `range`, `cut_paste`; `predicates.compare` all operators + invalid operator. |
| `planet_str` | PSTR-1..4 | `encode_string_to_double`/`decode_double_to_string` round-trip (empty, 8-byte boundary, high bytes), >8-char assertion; fixture: `set_planet_str` by name/prototype, `get_planet_str` explicit vs `name:sub(1,8)` fallback, `get_planet_str_double`; final-fixes fixture: auto-assignment for planets lacking it. |
| `recipe` | RCP-1..7 | Crushing/asteroid icon arrays; `advanced_crushing_recipe_icons` variants + invalid variant; `melting_icon`; `icon-entry.build_icon_entry` (singular/plural/placeholder, shift/scale/tint); `dual_icon`/`dual_icon_reversed`; `blur_technology_icon` count/tint/blend/no mutation/argument assertions. Fixture `icons`: documented `detect_type` precedence (surface > tool > capsule > fluid > planet > item), `get_prototype`, composite icons on real prototypes. |

### B. Data-stage APIs (fixtures + prototype assertions)

| Suite | IDs | What to cover |
| --- | --- | --- |
| `planet` | PLAN-1..15 | `PlanetsLib:extend` valid config, parent `planet-str` copy, `draw_orbit`, batch configs, every validation error, `special_properties` rejection; `PlanetsLib:update` in data/data-updates (moves descendants) and in data-final-fixes (rewrites `origin` + starmap layers), all validation errors; `borrow_music` (multi-planet fast path, space-platform copy, `track_types`, `modifier_function` arity). Fixtures: `planet_extend`, `planet_update`, `planet_update_final`. |
| `orbit_conversion` | ORB-5..20 | Missing-parent placeholders; non-star composition and polar-convention consistency; `ensure_all_locations_have_orbits`; `locations_ordered_by_orbits` (chains + cycle error); `is_parent`; `update_positions_of_all_children_via_orbits`; `apply_native_orbit` (origin, no-op with existing origin, `orbit.sprite` → `draw_orbit`, no parent); star survival / `sprite_only` cleanup. Fixture: `orbit_native`. |
| `special_properties` | SP-1..7 | `set_special_properties` deep-copy + merge + name/prototype input + return value; final-fixes rejection; runtime reads of `Planetslib.planet_special_properties`; unknown planet. Fixtures: `special_properties`, `special_properties_final`. |
| `technology` | TECH-1..8 | `get_child_technologies`; `excise_tech/recipe/effect_from_tech_tree` (prereq promotion, dedupe, hidden, empty-tech excision); `sort_science_pack_names`; `set_science_packs_from_lab` / vanilla-lab helper; planet/moon technology icons; `cargo_drops_technology_base` + effect/icon helpers and required-arg errors. Fixture: `technology`. |
| `technology_productivity` | TECH-9..10 | `PlanetsLib_recipe_productivity_effects`: `purge_other_effects` + `PlanetsLib_force_include`, `technology_name` guard, name+type vs category xor, default `category_blacklist` (`recycling`), `PlanetsLib_blacklist_technology_updates`, `ignored_by_productivity` filtering, single-vs-multiple results (`allow_multiple_results`, dedupe by name), `allow_recipes_without_productivity`; vanilla productivity techs inheriting `change`. Fixture: `technology_productivity_setup` (fields processed by PlanetsLib's data-final-fixes). |
| `surface_conditions` | SFC-1..6 | `restrict_surface_conditions` intersection/new property/no input mutation; `relax_surface_conditions` (widen only); `remove_surface_condition` by string and exact table; `restrict_to_planet` (hidden surface property, invert, idempotence); legacy `restrict_to_surface`; `fits_surface_conditions` data/runtime branches and default values. Fixture: `surface_conditions`. |
| `mod_data` | MD-1..5 | `assign_rocket_part_recipe` (recipe + lock data, `_other`, exclusivity restriction/removal); known table-input bug; planet/global cargo-drop whitelist helpers. Fixture: `mod_data`. |
| `achievements` | ACH-1..2 | `visit_planet_achievement` shape (`change-surface-achievement`, name/order/surface/icon), default icon size, custom localised name; invalid planet/icon errors. Fixture: `achievements`. |
| `misc_global_checks` | MISC-1 | `check_global_variables`: `fuel_category` → `fuel_categories` + correction list + tooltip; `AmbientSound::planet` → `planets[]` + planet tooltip; duplicate science-pack ingredients combined in both ingredient shapes; overridden `helpers` errors. Fixture: `misc_global_checks`. |
| `misc_science_lab` | MISC-2..3 | Unlink hidden prerequisites + `unlinked_prerequisites`; legacy lab-pack fields; `include_all_lab_science` / legacy sort fields; >12-pack lab `icons_positioning` with setting on/off. Fixtures: `misc_science_lab`, `misc_science_lab_final`. |
| `misc_visuals` | MISC-4..9 | Enhanced tooltips (freshness/reset/preserve, spoilage-only, `soft_insert` dedupe); `PlanetsLib_pipette_result` (string assertion, mutual exclusion with `placeable_by`); centrifuge fluidboxes + hidden extra boxes + tint; default item weights; gas-percentage assertion and `is-freezing`; star prototype and native-starmap cleanup. Fixtures: `misc_visuals_setup`, `misc_visuals_final`. |

### C. Entity replacement

| Suite | IDs | What to cover |
| --- | --- | --- |
| `entity_replacement_data` | ENT-0..4 | `ENT-0` asserts the CI scenario's `PlanetsLib-enable-entity-replacements` value; `assign_entity_replacement` (rule storage, default bound setting, duplicate error, recursion assertion, variant lists, mass-assignment and planet-table forms); `create_planet_entity_variant` (name suffix, deepcopy, localised fields, flags, Factoriopedia redirect/hide, `placeable_by`, icon corner, order suffix, `do_not_generate_variants`, multi-planet, invalid setting, item inference); rocket lift/part multiplier variant generation. Fixture: `entity_replacement_data`. |
| `entity_replacement_runtime` | ENT-5..11 | Place → replace; settings/inventory/crafting/health/temperature transfer; ghost preservation; robot-built path; inverse normalisation; modules/spill; fluid transfer; wire connections incl. self-referential; grid contents incl. ghost equipment; `storage.replaced_entities` + `get_replacement`; `PlanetsLib.events.on_entity_replaced`; disabled rule. |
| `entity_replacement_migration` | ENT-12..13 | Rolling-stock replacement (watch the undefined `rolling_stock_info` path); `on_configuration_changed` migration when a rule is added/disabled. Needs a prebuilt save or a controlled configuration change; if impossible headlessly, test the pure layout helpers and record the limitation. |

### D. Ground diggers

| Suite | IDs | What to cover |
| --- | --- | --- |
| `ground_diggers_data` | GD-1..5 | `enable_ground_diggers` validation, option normalisation (array + dictionary), late final-fixes call; `is_eligible_drill` exclusions (fluid output, non-square, no item, quality/resource-named, `do_not_generate_variants`); `create_ground_digger` field mapping/stripping/drain/surface condition/flags; `generate_ground_diggers` shared naming, recipe-category union, planet surface property, Factoriopedia note once, missing planet/recipe errors, `drills`/`blacklist`; mining-productivity effects. Fixtures: `ground_diggers_data`, `ground_diggers_late`. |
| `ground_diggers_runtime` | GD-6..9 | Built digger gets and locks the planet recipe; non-participating planet not converted; surface conditions respected; `construct_ground_digger` (no resources → convert, resources → no convert, collision, hidden tile, reach, remote-view ghost, wrong quality, cursor consumption + build stats); remote-view ghost without reach. |

### E. Runtime features and overrides

| Suite | IDs | What to cover |
| --- | --- | --- |
| `rocket_parts` | RP-1..4 | `on_built_rocket_silo` recipe assignment/default/`_other`, lock behaviour, auto-lock heuristic, ghost silo, non-rocket ignore; `fits_surface_conditions`. Fixture: `rocket_parts_setup`. |
| `cargo_pods` | CARGO-1..6 | Cargo-drop technology per space location + `nothing` effect; disallowed cargo pod destroyed, cargo to hub, throttled warning; whitelist variants (global/per-planet item/type + legacy); on-platform detection; deprecated remote interface add/remove; `init_storage` idempotence. |
| `unreachable_techs` | URT-1..4 | Hidden-prerequisite warnings + truncation; `warn_unlinked_prerequisites`; author auto-unban vs normal ban; on-join tick-0 warning gated by setting. |
| `recipe_effects` | REC-1..3 | Data prep (`add_to_stats`, `ignored_by_stats`, `amount_minus_ignored_by_productivity`, `inverse_batch_count`, `no_probability`, tooltip, fluid error); runtime no/shared/independent probability, batching, returned items to crafter input, production stats, `on_crafted_event` assertion; `storage.entity_info` cache create/clear. Fixture: `recipe_effects_setup`. |
| `remote_interfaces` | REM-1 | `PlanetsLib_transfer_storage` save/get/purge round-trip; missing key. |
| `smoke` (done) | SMOKE-1..3 | Results bag exists; every `suite` fixture entry passed; expected prototypes present. New fixtures must add their own namespace assertions in their suite (do not overload `smoke`). |

---

## 4. Stage ordering cheat-sheet

```
PlanetsLib data.lua
  -> planetslib-funit-data data.lua            (fixtures: data)
  -> PlanetsLib data-updates.lua
  -> planetslib-funit-data data-updates.lua    (fixtures: data_updates)
  -> PlanetsLib data-final-fixes.lua           (auto planet-str, native orbits,
                                                recipe productivity, ground diggers)
  -> planetslib-funit-data data-final-fixes.lua(fixtures: data_final_fixes)
  -> runtime: scenario control.lua loads suites
```

Consequences:
- A fixture that wants PlanetsLib's final-fixes to process something must set
  it up in `data.lua` or `data-updates.lua`.
- A fixture in `data-final-fixes.lua` runs **after** PlanetsLib finished, so it
  can test `PlanetsLib:update` in final-fixes, late ground-digger registration,
  or manual `orbits.apply_native_orbit` on freshly created prototypes.

---

## 5. Known / suspected bugs the suite should pin down

Keep the tests asserting the **documented** behavior. Fix the implementation
separately (with a regression test, `changelog.txt` entry, and docs update).

Fixed while implementing these suites (each has a regression test):

1. **`PlanetsLib.get_special_property`** (fixed) — returned the whole table and
   referenced an undefined `properties`. Now returns the requested property (or
   the table, or nil). (SP)
2. **`PlanetsLib.set_special_properties`** (fixed) — discarded the result of
   `rro.merge`, so later calls did not merge. (SP)
3. **`PlanetsLib.assign_rocket_part_recipe`** (fixed) — never unwrapped
   prototype-table arguments (`type(x) == "list"`), checked the wrong
   exclusivity field, left the single-planet surface restriction in place, and
   coerced `lock_silo = false` to `true`. (MD)
4. **`PlanetsLib:extend` parent `planet-str` copy** (fixed) — added a nil guard
   for parents without `surface_properties`/`planet-str`. (PLAN)
5. **Polar convention mismatch** (fixed) —
   `orbits.get_absolute_polar_position_from_orbit` now composes positions with
   the same `(x = d·sin, y = −d·cos)` / `+0.25` convention as the rectangular
   helpers. (ORB)
6. **`icon-entry.detect_type` precedence** (fixed) — removed the `item`
   short-circuit so the documented
   `surface > tool > capsule > fluid > planet > item` precedence applies. (RCP)
7. **`rro.deep_gsub`** (fixed) — the string branch assigned to a local instead
   of the list entry, and the recursive call passed the arguments in the wrong
   order (`deep_replace`). (LIB)
8. **`PlanetsLib.restrict_to_planet`** (fixed) — accepts a prototype table,
   ensures `surface_properties` exists, and is idempotent (repeated calls reuse
   the same condition; `invert` overrides rather than adding a contradiction).
   (SFC)
9. **Recipe effects without a probability** (fixed) —
   `prototypes/override-final/recipe-effects.lua` multiplied a nil probability
   by 100 while building the tooltip, so a `no_probability` returned ingredient
   crashed `data-final-fixes`. The tooltip now falls back to the amount-only
   form. (REC)
10. **Cargo-pod legacy whitelist semantics** (fixed) — the deprecated
    `planetslib` whitelist check required a global item entry and treated
    per-planet entries and entity types as vetoes. It now allows an item when
    any legacy whitelist entry (global/per-planet, name/type) matches, restoring
    the pre-refactor behaviour. (CARGO)
11. **`on_player_banned` nil `by_player`** (fixed) — `scripts/player-effects.lua`
    dereferenced `game.players[event.by_player].name`, but `by_player` is
    optional for script/server-console bans. It now falls back to `"server"`.
    (URT)
12. **`assign_entity_replacement` planet-list recursion** (fixed) — the planet
    key was derived before expanding a planet list, leaving a non-string key in
    the rule tables; the recursion also dropped `name_suffix` and indexed by the
    planet table for `{name = ...}` list elements. The list form is now expanded
    before key derivation and always recurses with the planet name and suffix.
    (ENT)
13. **`get_replacement` keyed by the new unit number** (fixed) —
    `scripts/entity-replacement.lua` stored only the replacement's own unit
    number, so the documented `get_replacement(old_unit_number)` always returned
    nil. Both the old and new unit numbers are now recorded. (ENT)
14. **Ground-digger debug spam** (fixed) — `scripts/ground-diggers.lua` printed
    `serpent.block(colliding_entities)` on every placement attempt. The leftover
    debug print was removed. (GD)
15. **`process_technology_recipe_productivity_effects` input cleanup** (fixed) —
    the function cleared a misspelled field
    (`PlanetsLib_recipe_producitivity_effects`), so the real input field survived
    and a second call could duplicate effects. It now clears
    `PlanetsLib_recipe_productivity_effects`. (TECH-9)
16. **Entity state transfer dropped fields with a nil default** (fixed) —
    `fields_to_transfer` stored `health = nil`, `crafting_progress = nil`, etc.
    In Lua those keys are absent, so `pairs()` never visited them; health,
    crafting progress, bonus progress, direction, turret orientation, loader
    type, recipe lock, custom status and the proxy/link fields were never
    transferred. The table now uses an explicit `NO_DEFAULT` sentinel, and each
    assignment is wrapped in `pcall` so fields that are read-only for a given
    entity type (for example `is_military_target` on a chest) are skipped
    instead of aborting the replacement. (ENT-6a)
17. **Generated variants had a different `fast_replaceable_group`** (fixed) —
    Factorio defaults an unspecified group to the prototype name, so a
    deep-copied variant ended up in `"<variant-name>"` rather than the base
    entity's group. The engine then refused `order_upgrade`/`apply_upgrade`
    between the variant and the original (notably locomotives). Variant
    generation now inherits the base group (or the base name when the base has
    no explicit group). (ENT-12)
18. **Rolling-stock replacement had no working fallback** (fixed) —
    `scripts/entity-replacement.lua` forced the `if true or
    rolling_stock_info...` in-place branch, so custom variants that the engine
    refuses to upgrade were never replaced. It now tries `order_upgrade` +
    `apply_upgrade`, then `apply_upgrade(nil, target)`, and finally recreates
    the rolling stock and restores the captured inventories/grid/train fields
    through `copy_info_to_new_rolling_stock`. The dead branch is gone; the
    fallback also fixes the undefined `entity` reference in the spill branch
    and tolerates read-only fields. (ENT-12)
19. **Raising script-built on a grid with equipment ghosts threw** (fixed) —
    `script.raise_script_built` on a newly created spidertron whose grid still
    contained ghost equipment raised `Equipment is not equipment-ghost`. The
    grid is transferred first; PlanetsLib now skips only the redundant built
    notification when the source grid contains ghost equipment. (ENT-10b)
20. **Lab `icons_positioning` duplicate** (fixed) — the >12-science-pack
    final-fixes pass appended a second `lab_input` entry even when one already
    existed. It now updates the existing entry in place (inventory index,
    shift, scale and max icons per row), so the lab has exactly one entry.
    (MISC-3)

Still open / needs a decision:

21. **planet-str encoding is lossy beyond 6 bytes** — a double only has 53 bits
    of integer precision, so 7-8 character planet names do not round-trip
    (`decode(encode("funit-a")) == "hunit-a"`; 8 characters decode to `""`). The
    implementation allows up to 8 characters. Tests stay within the safe range.
    Either document a 6-character limit or store the string differently. (PSTR)
22. **`rro.ammend`** — assigns the merged table to its local and neither returns
    it nor mutates `old`; effectively a no-op. (LIB)
23. **`get_planet_str_double` fallback** — encodes the full planet name while
    `get_planet_str` truncates to 8 characters, so the two fallbacks disagree
    for long names (and the encoder asserts above 8 characters). (PSTR)
24. **Ground-digger collision area** — the second collision check subtracts a
    `1.5` margin from a 3x3 drill, producing a zero-size area, so entities in the
    way are missed. The first check uses a different rounding convention. Needs
    a design decision. (GD)
25. **Ground-digger per-planet config** — `on_entity_built` assigns a recipe to
    any known digger on a planet with a recipe, even if that planet blacklists
    the drill; `construct_ground_digger` does check the config. (GD)
26. **Recipe-effect characterization** — skipped batches bypass production
    stats, `add_to_stats` is computed but unused, and the shared/independent
    probability tooltips use different units. These are pinned as
    characterization tests rather than treated as failures. (REC)
27. **Unreachable-tech warning precedence** — a non-empty
    `unlinked_prerequisites` list suppresses the hidden-prerequisite warning;
    pinned as current behaviour. (URT)

Test-harness fixes (not library bugs): the fixtures originally created a recipe
without an icon, used recipe-level `result_is_always_fresh`/
`reset_freshness_on_recipe` (those are item fields), reused item subtype names,
and called `PlanetsLib.extend`/`update` with dot syntax instead of method
syntax. All four were fixture mistakes and are fixed in
`prototypes/fixtures/`.

---

## 6. Implementing a suite (workflow)

1. Pick **one** suite from `tests/suites/manifest.lua` and open its stub.
2. Read the matching module(s) under `lib/`, `scripts/`, or `prototypes/`.
3. Write the fixture(s) for data-stage behavior first; record every expectation
   with `results.record(...)`.
4. Write the runtime tests; assert fixture entries with a clear message.
5. Lint:
   ```sh
   luac5.1 -p test-mods/planetslib-funit-data/tests/suites/<name>.lua
   luac5.1 -p test-mods/planetslib-funit-data/prototypes/fixtures/<name>.lua
   ```
   `luac5.1` cannot compile `goto` (PlanetsLib uses it in some files); keep test
   files goto-free, or validate with a Factorio 2.x/Lua 5.4 parser if available.
6. Run the scenario locally (see `tests/README.md`) or let CI do it.
7. Update this file only when the plan itself changes (new area, new fixture,
   new seam).

## 7. Definition of done for the suite

- Every suite listed in `tests/suites/manifest.lua` has real tests (no stubs).
- Every public documented API has at least one positive test and one
  error/edge test.
- Every fixture namespace has a runtime assertion that all its entries passed.
- The FUnit report has zero failures/errors in all four CI scenarios (base and
  Space Age + Quality, each with entity replacements on and off).
- Suspected bugs are either fixed (test + changelog + docs) or explicitly
  converted to characterization tests with a written justification.
