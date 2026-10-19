-- Pure (runtime-stage) test suite for PlanetsLib's orbit math.
--
-- The orbit position helpers are stateless, so (per FUnit's documentation) it
-- is fine to require PlanetsLib's module directly from the scenario. Functions
-- that read `data.raw` (e.g. apply_native_orbit) only work in the data stage
-- and are exercised by the data fixtures instead.

-- Trig round-trips accumulate ~1e-8 of floating-point error.
local EPSILON = 1e-6

local function approx(actual, expected, tolerance)
	return math.abs(actual - expected) <= (tolerance or EPSILON)
end

return function(runner)
	local orbits = require("__PlanetsLib__.lib.orbits")

	runner.test("ORB-1 get_rectangular_position_from_polar cardinal directions", function()
		local x, y

		x, y = orbits.get_rectangular_position_from_polar(0, 0)
		runner.assert(x == 0 and y == 0, "distance 0 must map to the origin, got (" .. x .. ", " .. y .. ")")

		x, y = orbits.get_rectangular_position_from_polar(5, 0)
		runner.assert(approx(x, 0) and approx(y, -5), "orientation 0 must point to (0, -d), got (" .. x .. ", " .. y .. ")")

		x, y = orbits.get_rectangular_position_from_polar(5, 0.25)
		runner.assert(approx(x, 5) and approx(y, 0), "orientation 0.25 must point to (d, 0), got (" .. x .. ", " .. y .. ")")

		x, y = orbits.get_rectangular_position_from_polar(5, 0.5)
		runner.assert(approx(x, 0) and approx(y, 5), "orientation 0.5 must point to (0, d), got (" .. x .. ", " .. y .. ")")

		x, y = orbits.get_rectangular_position_from_polar(5, 0.75)
		runner.assert(approx(x, -5) and approx(y, 0), "orientation 0.75 must point to (-d, 0), got (" .. x .. ", " .. y .. ")")
	end)

	runner.test("ORB-2 polar -> rectangular -> polar round-trips", function()
		local cases = {
			{ distance = 3, orientation = 0.1 },
			{ distance = 12.5, orientation = 0.37 },
			{ distance = 7, orientation = 0.999 },
		}

		for _, case in ipairs(cases) do
			local x, y = orbits.get_rectangular_position_from_polar(case.distance, case.orientation)
			local distance, orientation = orbits.get_polar_position_from_rectangular(x, y)

			runner.assert(
				approx(distance, case.distance),
				"distance did not round-trip: expected " .. case.distance .. ", got " .. distance
			)
			runner.assert(
				approx(orientation, case.orientation),
				"orientation did not round-trip: expected " .. case.orientation .. ", got " .. orientation
			)
		end
	end)

	runner.test("ORB-3 get_absolute_position applies origin offset", function()
		-- No origin: the absolute position equals the rectangular position.
		local x, y = orbits.get_absolute_position({ distance = 5, orientation = 0.25 })
		runner.assert(approx(x, 5) and approx(y, 0), "expected (5, 0) without origin, got (" .. x .. ", " .. y .. ")")

		-- Origin as a table with x/y fields.
		x, y = orbits.get_absolute_position({ distance = 0, orientation = 0, origin = { x = 10, y = 20 } })
		runner.assert(approx(x, 10) and approx(y, 20), "expected (10, 20) with table origin, got (" .. x .. ", " .. y .. ")")

		-- Origin in native Factorio array form ({ x, y }).
		x, y = orbits.get_absolute_position({ distance = 0, orientation = 0, origin = { 7, -3 } })
		runner.assert(approx(x, 7) and approx(y, -3), "expected (7, -3) with array origin, got (" .. x .. ", " .. y .. ")")
	end)

	runner.test("ORB-4 get_absolute_position combines polar offset and origin", function()
		local x, y = orbits.get_absolute_position({ distance = 5, orientation = 0.25, origin = { x = 10, y = 20 } })
		runner.assert(approx(x, 15) and approx(y, 20), "expected (15, 20), got (" .. x .. ", " .. y .. ")")
	end)
end
