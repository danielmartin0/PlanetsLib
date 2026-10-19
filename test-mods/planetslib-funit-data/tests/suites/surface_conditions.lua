-- Surface-condition restriction/relaxation/removal helpers.
--
-- The pure helpers are tested directly; restrict_to_planet/restrict_to_surface
-- need data.raw and are covered by the `surface_conditions` data fixture.

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

local function find_condition(conditions, property)
	for _, condition in ipairs(conditions) do
		if condition.property == property then
			return condition
		end
	end
	return nil
end

return function(runner)
	package.loaded["util"] = require("__core__.lualib.util")
	package.loaded["lib.objects"] = require("__PlanetsLib__.lib.objects")
	local surface_conditions = require("__PlanetsLib__.lib.surface_conditions")

	runner.test("SFC-1 restrict_surface_conditions intersects ranges", function()
		local initial = {
			{ property = "pressure", min = 10, max = 100 },
			{ property = "gravity", min = 0, max = 20 },
		}
		local entity = { surface_conditions = initial }
		local condition = { property = "pressure", min = 50, max = 200 }

		surface_conditions.restrict_surface_conditions(entity, condition)
		local pressure = find_condition(entity.surface_conditions, "pressure")
		runner.assert(pressure.min == 50, "min should tighten to the larger value")
		runner.assert(pressure.max == 100, "max should stay at the smaller value")
		runner.assert(#entity.surface_conditions == 2, "restriction must not add a duplicate property")

		runner.assert(
			initial[1].min == 10 and initial[1].max == 100,
			"the input conditions were mutated"
		)
		runner.assert(
			entity.surface_conditions ~= initial,
			"restrict_surface_conditions must install a copy"
		)
		runner.assert(condition.min == 50 and condition.max == 200, "the input condition was mutated")

		-- A new property is appended.
		surface_conditions.restrict_surface_conditions(entity, { property = "temperature", min = 5 })
		local temperature = find_condition(entity.surface_conditions, "temperature")
		runner.assert(temperature and temperature.min == 5 and temperature.max == nil,
			"a new property was not appended correctly")
		runner.assert(#entity.surface_conditions == 3, "expected three conditions")
	end)

	runner.test("SFC-2 relax_surface_conditions widens existing ranges only", function()
		local entity = {
			surface_conditions = {
				{ property = "pressure", min = 50, max = 100 },
			},
		}
		surface_conditions.relax_surface_conditions(entity, { property = "pressure", min = 10, max = 200 })
		local pressure = find_condition(entity.surface_conditions, "pressure")
		runner.assert(pressure.min == 10, "min should widen downward")
		runner.assert(pressure.max == 200, "max should widen upward")

		-- Omitting max must not delete an existing maximum.
		surface_conditions.relax_surface_conditions(entity, { property = "pressure", min = 5 })
		pressure = find_condition(entity.surface_conditions, "pressure")
		runner.assert(pressure.min == 5, "min was not relaxed")
		runner.assert(pressure.max == 200, "omitting max must not remove the maximum")

		-- A missing property is not added.
		surface_conditions.relax_surface_conditions(entity, { property = "gravity", min = 1 })
		runner.assert(find_condition(entity.surface_conditions, "gravity") == nil,
			"relax_surface_conditions must not add missing properties")
	end)

	runner.test("SFC-3 remove_surface_condition by name and by exact table", function()
		local entity = {
			surface_conditions = {
				{ property = "pressure", min = 1, max = 2 },
				{ property = "pressure", min = 3, max = 4 },
				{ property = "gravity", min = 0, max = 10 },
			},
		}

		surface_conditions.remove_surface_condition(entity, { property = "pressure", min = 1, max = 2 })
		runner.assert(#entity.surface_conditions == 2, "exact-table removal removed the wrong number of entries")
		runner.assert(find_condition(entity.surface_conditions, "pressure").min == 3,
			"exact-table removal removed the wrong entry")
		runner.assert(find_condition(entity.surface_conditions, "gravity") ~= nil,
			"exact-table removal removed an unrelated condition")

		surface_conditions.remove_surface_condition(entity, "pressure")
		runner.assert(find_condition(entity.surface_conditions, "pressure") == nil,
			"string removal did not remove every condition with that property")
		runner.assert(#entity.surface_conditions == 1, "string removal left extra conditions")

		-- No match: leave the table untouched.
		surface_conditions.remove_surface_condition(entity, "temperature")
		runner.assert(#entity.surface_conditions == 1, "a no-op removal changed the list")
	end)

	runner.test("SFC-4 data-stage restriction fixture results", function()
		assert_fixture_namespace(runner, "surface_conditions")
	end)
end
