-- Rocket-part recipe assignment and cargo-drop whitelists.
--
-- All of these APIs write prototypes in the data stage, so the behavior is
-- exercised by the `mod_data` fixture and asserted here.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local support = require("__planetslib-funit-data__.tests.suites.support")

return function(runner)
	runner.test("MD-1 rocket-part and cargo-whitelist fixture results", function()
		support.assert_all(runner, "mod_data", { expected = { "MD-1" } })
	end)

	runner.test("MD-2 assignments survive into the runtime prototypes", function()
		if not script.active_mods["space-age"] then
			-- The fixture intentionally only exercises rocket-part assignment
			-- with Space Age. Assert the base-game expectation rather than
			-- returning as an unmarked pass.
			local recipe_map = prototypes.mod_data["Planetslib-planet-rocket-part-recipe"]
			runner.assert(recipe_map, "rocket-part recipe mod-data is missing in base")
			runner.assert(
				recipe_map.data["funit-md-1"] == nil,
				"the Space-Age-only rocket-part fixture leaked into the base-game mod-data"
			)
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
