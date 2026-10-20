-- Data-fixture smoke tests.
--
-- test-mods/planetslib-funit-data runs PlanetsLib's data-stage API inside pcall
-- and records the outcome into the "PlanetsLib-funit-results" mod-data
-- prototype. This suite reads it back at runtime and fails if any fixture
-- reported an error, which is how data-stage failures surface in the FUnit
-- report.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"

local function get_results(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(
		mod_data,
		"mod-data prototype '" .. RESULTS_MOD_DATA .. "' not found. Is the planetslib-funit-data test mod enabled?"
	)
	return mod_data.data
end

return function(runner)
	runner.test("SMOKE-1 results bag exists", function()
		local results = get_results(runner)
		runner.assert(type(results) == "table", "results bag is not a table")
	end)

	runner.test("SMOKE-2 example data-stage fixtures succeeded", function()
		local results = get_results(runner)
		local suite = results.suite
		runner.assert(suite, "results bag has no 'suite' namespace")

		for id, entry in pairs(suite) do
			runner.assert(
				entry.ok,
				"data fixture '" .. id .. "' failed: " .. tostring(entry.err)
			)
		end
	end)

	runner.test("SMOKE-3 expected PlanetsLib prototypes are present", function()
		if script.active_mods["space-age"] then
			runner.assert(prototypes.space_location["nauvis"], "space location prototype 'nauvis' not found")
		else
			runner.assert(prototypes.entity["iron-chest"], "base prototype 'iron-chest' not found")
		end
	end)
end
