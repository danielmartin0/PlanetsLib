-- visit_planet_achievement builds a prototype during the data stage, so it is
-- exercised by the `achievements` fixture and asserted here.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"

return function(runner)
	runner.test("ACH-1 visit_planet_achievement fixture results", function()
		local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
		runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")

		local entries = mod_data.data.achievements
		runner.assert(entries, "no achievements fixture results recorded")
		for id, entry in pairs(entries) do
			runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
		end
	end)
end
