-- Rocket-part recipe assignment and cargo-drop whitelists.
--
-- All of these APIs write prototypes in the data stage, so the behavior is
-- exercised by the `mod_data` fixture and asserted here.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"

local function get_results(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	return mod_data.data
end

local function assert_fixture_namespace(runner, suite)
	local entries = get_results(runner)[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. suite .. "'")
	for id, entry in pairs(entries) do
		runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
	end
end

return function(runner)
	runner.test("MD-1 rocket-part and cargo-whitelist fixture results", function()
		assert_fixture_namespace(runner, "mod_data")
	end)

	runner.test("MD-2 assignments survive into the runtime prototypes", function()
		if not script.active_mods["space-age"] then
			return
		end

		local recipe_map = prototypes.mod_data["Planetslib-planet-rocket-part-recipe"]
		local lock_map = prototypes.mod_data["Planetslib-planet-lock-rocket-silos"]
		runner.assert(recipe_map, "rocket-part recipe mod-data is missing")
		runner.assert(lock_map, "rocket-part lock mod-data is missing")

		runner.assert(recipe_map.data["funit-md-1"] == "copper-cable", "prototype-table assignment did not persist")
		runner.assert(recipe_map.data["funit-md-2"] == "iron-gear-wheel", "string assignment did not persist")
		runner.assert(recipe_map.data["funit-md-4"] == "_other", "'_other' assignment did not persist")

		runner.assert(lock_map.data["funit-md-1"] == false, "lock_silo = false did not persist")
		runner.assert(lock_map.data["funit-md-2"] == true, "default lock_silo did not persist")
		runner.assert(lock_map.data["funit-md-4"] == nil, "'_other' should not create a lock entry")
	end)
end
