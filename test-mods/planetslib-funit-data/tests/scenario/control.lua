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
--   script-output/funit-report-planetslib.json

require('__base__/script/freeplay/control.lua')

local runner = require("__funit__.test_runner")
runner.register("PlanetsLib")
runner.report("planetslib")

-- Require suites from the companion mod. This is the same mechanism FUnit
-- itself uses to load "__funit__.test_runner" from a scenario, and avoids
-- relying on scenario-local require paths.
local MOD = "__planetslib-funit-data__"

local manifest = require(MOD .. ".tests.suites.manifest")
for _, suite in ipairs(manifest.order) do
	require(MOD .. ".tests.suites." .. suite)(runner)
end
