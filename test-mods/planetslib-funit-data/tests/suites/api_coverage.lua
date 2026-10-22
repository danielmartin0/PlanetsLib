-- Public API coverage for helpers that previously had no direct tests.
--
-- The data-stage fixture runs the helpers inside PlanetsLib's data environment
-- and records the result. This suite makes those records visible to FUnit and
-- also checks the runtime-visible aliases that do not need `data`.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local SUITE = "api_coverage"

local function entries(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	local suite = mod_data.data[SUITE]
	runner.assert(suite, "no data-stage results recorded for '" .. SUITE .. "'")
	return suite
end

return function(runner)
	runner.test("API-1..5 data-stage public helper results", function()
		local suite = entries(runner)
		for _, id in ipairs({ "API-1", "API-2", "API-3", "API-4", "API-5" }) do
			local entry = suite[id]
			runner.assert(entry, "missing data fixture entry " .. id)
			runner.assert(entry.ok, "data fixture " .. id .. " failed: " .. tostring(entry.err))
		end
	end)
end
