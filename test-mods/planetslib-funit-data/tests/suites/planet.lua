-- PlanetsLib:extend / PlanetsLib:update / borrow_music / is_space_location.
--
-- The data-stage behavior is exercised by the planet_extend, planet_update and
-- planet_update_final fixtures; this suite asserts those results plus the pure
-- type predicates, the special-property getters and the resulting runtime
-- prototypes.
--
-- PLAN ids:
--   PLAN-1..6   extend (valid configs, planet-str copy, validation, borrow_music)
--   PLAN-7..8   update in data/data-updates (moves descendants, validation)
--   PLAN-9..10  update in data-final-fixes and the extend guard
--   PLAN-11     is_space_location / is_space_location_or_space_platform
--   PLAN-12     final prototype state
--   PLAN-13     update batch configs and non-orbit fields
--   PLAN-14     borrow_music from a prototype table to the space platform
--   PLAN-15     get_special_properties and prototype-table inputs

local support = require("__planetslib-funit-data__.tests.suites.support")

-- The fixture ids recorded in each namespace. Keep these explicit so a fixture
-- that stops recording an id fails here instead of disappearing from a pairs()
-- loop.
local PLAN_EXTEND_IDS = {
	"PLAN-1",
	"PLAN-5a",
	"PLAN-5b",
	"PLAN-5c",
	"PLAN-5d",
	"PLAN-5e",
	"PLAN-5f",
	"PLAN-5g",
	"PLAN-6",
	"PLAN-14",
}
local PLAN_UPDATE_IDS = {
	"PLAN-7",
	"PLAN-8a",
	"PLAN-8b",
	"PLAN-8c",
	"PLAN-8d",
	"PLAN-8e",
	"PLAN-8f",
	"PLAN-8g",
	"PLAN-13",
}
local PLAN_UPDATE_FINAL_IDS = {
	"PLAN-9",
	"PLAN-10",
}

return function(runner)
	if not script.active_mods["space-age"] then
		return
	end

	package.loaded["util"] = require("__core__.lualib.util")
	package.loaded["lib.lib"] = require("__PlanetsLib__.lib.lib")
	package.loaded["lib.orbits"] = require("__PlanetsLib__.lib.orbits")
	local planet = require("__PlanetsLib__.lib.planet")

	runner.test("PLAN-1..6, PLAN-14 PlanetsLib:extend fixture results", function()
		support.assert_all(runner, "planet_extend", { expected = PLAN_EXTEND_IDS })
	end)

	runner.test("PLAN-7..8, PLAN-13 PlanetsLib:update fixture results", function()
		support.assert_all(runner, "planet_update", { expected = PLAN_UPDATE_IDS })
	end)

	runner.test("PLAN-9..10 PlanetsLib:update final-fixes fixture results", function()
		support.assert_all(runner, "planet_update_final", { expected = PLAN_UPDATE_FINAL_IDS })
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

	runner.test("PLAN-15 get_special_properties and prototype-table inputs", function()
		local mod_data = prototypes.mod_data["Planetslib"]
		runner.assert(mod_data, "Planetslib mod-data is missing")
		local constants = mod_data.data
		local stored = constants.planet_special_properties and constants.planet_special_properties["funit-sp"]
		runner.assert(stored, "the special_properties fixture did not record 'funit-sp'")

		-- lib/planet.lua reads the PlanetsLib global, which is not created by the
		-- scenario itself. Point it at the real mod-data constants rather than a
		-- suite-local shim, so the getter reads the same table as the fixture.
		_G.PlanetsLib = _G.PlanetsLib or {}
		_G.PlanetsLib.constants = constants

		runner.assert(planet.get_special_properties("funit-sp") == stored,
			"get_special_properties did not return the stored table")
		runner.assert(planet.get_special_properties({ name = "funit-sp" }) == stored,
			"get_special_properties did not accept a prototype table")
		runner.assert(planet.get_special_property({ name = "funit-sp" }, "custom") == "a",
			"get_special_property did not accept a prototype table")
		runner.assert(planet.get_special_properties("funit-sp-unknown") == nil,
			"an unknown planet should have no special properties")
	end)
end
