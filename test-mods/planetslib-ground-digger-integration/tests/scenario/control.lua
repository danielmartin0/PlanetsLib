-- FUnit scenario for the PlanetsLib ground-digger integration tests.
--
-- Run with planet-muluna and maraxsis enabled. The suite is development-only and
-- lives in the planetslib-ground-digger-integration mod.

require('__base__/script/freeplay/control.lua')

local runner = require("__funit__.test_runner")
runner.register("planetslib-ground-digger-integration")
runner.report("planetslib-gd-integration")

PlanetsLib = PlanetsLib or {}
PlanetsLib.stage = "runtime"
PlanetsLib.constants = prototypes.mod_data["Planetslib"].data

require("__planetslib-ground-digger-integration__.tests.suites.ground_diggers_integration")(runner)
