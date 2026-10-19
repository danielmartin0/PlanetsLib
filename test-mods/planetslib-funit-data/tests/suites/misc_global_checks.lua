-- PlanetsLib.check_global_variables().
--
-- The corrections happen in the data stage, so the behavior is exercised by the
-- `misc_global_checks` fixture and asserted here.
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
	runner.test("MISC-1a duplicate research ingredients and overridden helpers", function()
		assert_fixture_namespace(runner, "misc_global_checks")
	end)

	runner.test("MISC-1b corrected prototypes persist at runtime", function()
		local tech = prototypes.technology["funit-dup-research-array"]
		runner.assert(tech, "the duplicate-research technology did not persist")
		local ingredients = tech.research_unit_ingredients
		runner.assert(#ingredients == 2, "runtime ingredients were not combined")
		runner.assert(
			(ingredients[1].name or ingredients[1][1]) == "automation-science-pack"
				and (ingredients[1].amount or ingredients[1][2]) == 3,
			"the summed amount did not persist to runtime"
		)
	end)
end
