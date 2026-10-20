-- Orbit composition, ordering and native `origin` conversion.
--
-- These functions read `data.raw`, so the actual behavior is exercised by the
-- `orbit_native` data-final-fixes fixture and asserted here. The pure star
-- pass-through and argument validation are also re-checked at runtime.
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
	if not script.active_mods["space-age"] then
		return
	end

	package.loaded["util"] = require("__core__.lualib.util")
	package.loaded["lib.lib"] = require("__PlanetsLib__.lib.lib")
	local orbits = require("__PlanetsLib__.lib.orbits")

	runner.test("ORB-5..16 orbit conversion fixture results", function()
		assert_fixture_namespace(runner, "orbit_native")
	end)

	runner.test("ORB-17 star parents pass through at runtime", function()
		local distance, orientation = orbits.get_absolute_polar_position_from_orbit({
			parent = { type = "space-location", name = "star" },
			distance = 12,
			orientation = 0.75,
		})
		runner.assert(distance == 12, "star distance should pass through")
		runner.assert(orientation == 0.75, "star orientation should pass through")
	end)

	runner.test("ORB-18 unsupported parent types are rejected at runtime", function()
		runner.assert(
			not pcall(orbits.get_absolute_polar_position_from_orbit, {
				parent = { type = "item", name = "iron-plate" },
				distance = 1,
				orientation = 0,
			}),
			"an unsupported parent type should error"
		)
	end)

	runner.test("ORB-19 converted prototypes have native origins", function()
		local native = prototypes.space_location["funit-native-a"]
		runner.assert(native, "funit-native-a is missing")
		runner.assert(native.origin, "the converted prototype has no native origin")
		runner.assert(
			type(native.origin.x) == "number" and type(native.origin.y) == "number",
			"the native origin is not an x/y table"
		)
	end)
end
