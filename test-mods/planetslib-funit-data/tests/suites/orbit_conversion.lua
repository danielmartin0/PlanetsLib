-- Orbit composition, ordering and native `origin` conversion.
--
-- These functions read `data.raw`, so the actual behavior is exercised by the
-- `orbit_native` data-final-fixes fixture and asserted here. The pure star
-- pass-through and argument validation are also re-checked at runtime.
--
-- Fixture ids: ORB-5..16 and ORB-20. Runtime-only ids: ORB-17..19.

local support = require("__planetslib-funit-data__.tests.suites.support")

local ORBIT_NATIVE_IDS = {
	"ORB-5",
	"ORB-6",
	"ORB-7",
	"ORB-8",
	"ORB-9",
	"ORB-10",
	"ORB-11",
	"ORB-12",
	"ORB-13",
	"ORB-14",
	"ORB-15",
	"ORB-16",
	"ORB-20",
}

local EPSILON = 1e-6

local function approx(a, b)
	return math.abs(a - b) <= EPSILON
end

-- Native origins are MapPositions, which the engine stores in 1/256-tile
-- fixed point. Recomputing the same position from the prototype's
-- distance/orientation therefore agrees only to roughly one tile unit.
local POSITION_EPSILON = 0.01

local function approx_position(a, b)
	return math.abs(a - b) <= POSITION_EPSILON
end

return function(runner)
	if not script.active_mods["space-age"] then
		return
	end

	package.loaded["util"] = require("__core__.lualib.util")
	package.loaded["lib.lib"] = require("__PlanetsLib__.lib.lib")
	local orbits = require("__PlanetsLib__.lib.orbits")

	runner.test("ORB-5..16, ORB-20 orbit conversion fixture results", function()
		support.assert_all(runner, "orbit_native", { expected = ORBIT_NATIVE_IDS })
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
		local parent = prototypes.space_location["funit-parent-str"]
		local native = prototypes.space_location["funit-native-a"]
		runner.assert(parent, "funit-parent-str is missing")
		runner.assert(native, "funit-native-a is missing")
		runner.assert(native.origin, "the converted prototype has no native origin")
		runner.assert(
			type(native.origin.x) == "number" and type(native.origin.y) == "number",
			"the native origin is not an x/y table"
		)

		-- The origin is the parent's absolute position, and distance/orientation
		-- are rebased onto it (back to the orbit values).
		local parent_x, parent_y = orbits.get_absolute_position(parent)
		runner.assert(approx_position(native.origin.x, parent_x) and approx_position(native.origin.y, parent_y),
			"the native origin is not the parent's absolute position (origin="
				.. tostring(native.origin.x) .. "," .. tostring(native.origin.y)
				.. ", parent=" .. tostring(parent_x) .. "," .. tostring(parent_y) .. ")")
		runner.assert(approx(native.distance, 5) and approx(native.orientation, 0.25),
			"distance/orientation were not rebased onto the native origin (distance="
				.. tostring(native.distance) .. ", orientation=" .. tostring(native.orientation) .. ")")

		-- orbit.sprite enables draw_orbit during the conversion.
		local sprite = prototypes.space_location["funit-native-sprite"]
		runner.assert(sprite, "funit-native-sprite is missing")
		runner.assert(sprite.draw_orbit == true, "orbit.sprite did not enable draw_orbit")
	end)
end
