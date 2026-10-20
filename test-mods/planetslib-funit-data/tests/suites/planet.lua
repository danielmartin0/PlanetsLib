-- PlanetsLib:extend / PlanetsLib:update / borrow_music / is_space_location.
--
-- The data-stage behavior is exercised by the planet_extend, planet_update and
-- planet_update_final fixtures; this suite asserts those results plus the pure
-- type predicates and the resulting runtime prototypes.

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
	package.loaded["lib.orbits"] = require("__PlanetsLib__.lib.orbits")
	local planet = require("__PlanetsLib__.lib.planet")

	runner.test("PLAN-1..6 PlanetsLib:extend fixture results", function()
		assert_fixture_namespace(runner, "planet_extend")
	end)

	runner.test("PLAN-7..8 PlanetsLib:update fixture results", function()
		assert_fixture_namespace(runner, "planet_update")
	end)

	runner.test("PLAN-9..10 PlanetsLib:update final-fixes fixture results", function()
		assert_fixture_namespace(runner, "planet_update_final")
	end)

	runner.test("PLAN-11 is_space_location and is_space_location_or_space_platform", function()
		runner.assert(planet.is_space_location({ type = "planet", name = "x" }), "planets are space locations")
		runner.assert(planet.is_space_location({ type = "space-location", name = "x" }),
			"space-locations are space locations")
		runner.assert(not planet.is_space_location({ type = "item", name = "x" }), "items are not space locations")
		runner.assert(not planet.is_space_location(nil), "nil is not a space location")

		runner.assert(planet.is_space_location_or_space_platform("space-platform"),
			"the space-platform string should be accepted")
		runner.assert(planet.is_space_location_or_space_platform({ type = "planet", name = "x" }),
			"planets are space locations or platforms")
		runner.assert(not planet.is_space_location_or_space_platform({ type = "item", name = "x" }),
			"items are not space locations or platforms")
	end)

	runner.test("PLAN-12 extended prototypes are present with the expected final state", function()
		local planet_a = prototypes.space_location["funit-planet-a"]
		runner.assert(planet_a, "funit-planet-a is missing")
		runner.assert(planet_a.draw_orbit == true, "draw_orbit was not carried over")
		-- The custom `orbit` table is converted to native distance/orientation/
		-- origin in data-final-fixes and is not exposed at runtime.
		runner.assert(planet_a.distance == 20 and math.abs(planet_a.orientation - 0.3) < 1e-6,
			"the final-fixes update did not apply to the prototype (distance="
				.. tostring(planet_a.distance) .. ", orientation=" .. tostring(planet_a.orientation) .. ")")
		runner.assert(planet_a.origin, "the native origin was not applied")

		local child = prototypes.space_location["funit-child-str"]
		local parent = prototypes.space_location["funit-parent-str"]
		runner.assert(child and parent, "the parent/child planets are missing")
		runner.assert(parent.surface_properties and parent.surface_properties["planet-str"],
			"the parent planet has no planet-str")
		runner.assert(
			child.surface_properties["parent-planet-str"] == parent.surface_properties["planet-str"],
			"parent-planet-str does not match the parent's planet-str"
		)
	end)
end
