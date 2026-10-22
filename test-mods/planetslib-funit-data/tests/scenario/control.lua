-- FUnit test scenario for PlanetsLib.
--
-- This thin scenario is copied to <Factorio user data>/scenarios/funit and
-- loaded headlessly with:
--   factorio --start-server-load-scenario funit --mod-directory <mods>
-- (see .github/workflows/funit.yml). The actual tests live in the companion mod
-- under test-mods/planetslib-funit-data/tests/suites/ so that they are developed
-- alongside the data-stage fixtures whose prototypes they assert on.
--
-- FUnit runs the registered tests on the first tick and, when finished, writes:
--   script-output/funit-report-<report name>.json
-- The report name includes the scenario axes so that multiple scenarios can
-- write to the same script-output directory without overwriting each other.

require('__base__/script/freeplay/control.lua')

local runner = require("__funit__.test_runner")
runner.register("PlanetsLib")

local report_name = "planetslib-" .. (script.active_mods["space-age"] and "space-age" or "base")
if not settings.startup["PlanetsLib-enable-entity-replacements"].value then
	report_name = report_name .. "-no-replacements"
end
runner.report(report_name)

-- Suites require PlanetsLib modules into the scenario's Lua state, but
-- PlanetsLib's own control stage runs in a separate per-mod Lua state. Recreate
-- the runtime marker those modules read once here, instead of relying on an
-- individual suite to set it. Without this, lib/surface-property-lib.lua takes
-- its data-stage branch (indexing the absent `data` global) whenever the suites
-- that set the marker earlier in the manifest are skipped, which is exactly what
-- happened in the base-only scenarios.
PlanetsLib = PlanetsLib or {}
PlanetsLib.stage = "runtime"
PlanetsLib.constants = prototypes.mod_data["Planetslib"].data

-- Require suites from the companion mod. This is the same mechanism FUnit
-- itself uses to load "__funit__.test_runner" from a scenario, and avoids
-- relying on scenario-local require paths.
local MOD = "__planetslib-funit-data__"

local manifest = require(MOD .. ".tests.suites.manifest")
for _, suite in ipairs(manifest.order) do
	require(MOD .. ".tests.suites." .. suite)(runner)
end
