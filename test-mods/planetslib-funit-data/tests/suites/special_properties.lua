-- Planetary special properties (lib/planet.lua).
--
-- set_special_properties/get_special_property run in the data stage; the
-- `special_properties` and `special_properties_final` fixtures exercise them, and
-- the runtime reads the resulting mod-data.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"

local function assert_fixture_namespace(runner, suite)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	local entries = mod_data.data[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. suite .. "'")
	for id, entry in pairs(entries) do
		runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
	end
end

return function(runner)
	-- lib/planet.lua is loaded into the scenario's Lua state, so it needs the
	-- mod-data-backed `PlanetsLib` global that its runtime helpers read.
	package.loaded["util"] = require("__core__.lualib.util")
	package.loaded["lib.lib"] = require("__PlanetsLib__.lib.lib")
	package.loaded["lib.orbits"] = require("__PlanetsLib__.lib.orbits")
	local planet = require("__PlanetsLib__.lib.planet")

	_G.PlanetsLib = _G.PlanetsLib or {
		constants = prototypes.mod_data["Planetslib"].data,
	}
	_G.PlanetsLib.get_special_property = planet.get_special_property
	_G.PlanetsLib.get_special_properties = planet.get_special_properties

	runner.test("SP-1 set_special_properties data-stage behavior", function()
		assert_fixture_namespace(runner, "special_properties")
	end)

	runner.test("SP-2 set_special_properties is rejected in data-final-fixes", function()
		assert_fixture_namespace(runner, "special_properties_final")
	end)

	runner.test("SP-3 runtime get_special_property reads the stored values", function()
		local properties = prototypes.mod_data["Planetslib"].data.planet_special_properties
		runner.assert(properties, "Planetslib mod-data has no planet_special_properties table")

		local stored = properties["funit-sp"]
		runner.assert(stored, "the 'funit-sp' special properties were not stored")
		runner.assert(stored.rocket_lift_multiplier == 2, "rocket_lift_multiplier did not persist")
		runner.assert(stored.rocket_part_multiplier == 3, "the merged rocket_part_multiplier did not persist")

		runner.assert(
			PlanetsLib.get_special_property("funit-sp", "rocket_lift_multiplier") == 2,
			"PlanetsLib.get_special_property did not return the runtime value"
		)
		runner.assert(PlanetsLib.get_special_property("funit-sp").custom == "a",
			"PlanetsLib.get_special_property did not return the whole table")
		runner.assert(PlanetsLib.get_special_property("funit-sp", "missing") == nil,
			"a missing property should be nil")
		runner.assert(PlanetsLib.get_special_property("funit-sp-missing") == nil,
			"an unknown planet should be nil")
	end)
end
