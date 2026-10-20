-- Ground diggers: data-stage API and generated prototypes.
--
-- The data fixtures call enable_ground_diggers(), generate_ground_diggers() and
-- create_ground_digger(); this suite asserts their recorded results and the
-- prototypes that survived into the runtime stage.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local MARKER = "PlanetsLib-has-ground-diggers"

local DATA_SUITE = "ground_diggers_data"
local LATE_SUITE = "ground_diggers_late"

local function get_results(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	return mod_data.data
end

local function assert_entry(runner, suite, id)
	local entries = get_results(runner)[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. suite .. "'")
	local entry = entries[id]
	runner.assert(entry, "data fixture '" .. suite .. " " .. id .. "' was not recorded")
	runner.assert(entry.ok, "data fixture '" .. suite .. " " .. id .. "' failed: " .. tostring(entry.err))
end

local function assert_entries(runner, suite, ids)
	for _, id in ipairs(ids) do
		assert_entry(runner, suite, id)
	end
end

local function get_configs(runner)
	local mod_data = prototypes.mod_data["Planetslib"]
	runner.assert(mod_data, "PlanetsLib mod-data prototype is missing")
	local configs = mod_data.data.ground_diggers
	runner.assert(configs, "PlanetsLib ground_diggers mod-data is missing")
	return configs
end

local function find_condition(conditions, property)
	for _, condition in ipairs(conditions or {}) do
		if condition.property == property then
			return condition
		end
	end
	return nil
end

local function effects_for(technology, recipe_name)
	local matches = {}
	for _, effect in ipairs(technology.effects or {}) do
		if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
			matches[#matches + 1] = effect
		end
	end
	return matches
end

return function(runner)
	if not script.active_mods["space-age"] then
		return
	end

	runner.test("GD-1 enable_ground_diggers validation and normalisation", function()
		assert_entries(runner, DATA_SUITE, { "GD-0-setup", "GD-1a", "GD-1b" })
		assert_entry(runner, LATE_SUITE, "GD-1c")

		local config = get_configs(runner)["funit-gd-planet"]
		runner.assert(config, "the configured planet has no ground-digger config")
		runner.assert(config.recipe == "funit-gd-recipe-a", "the configured recipe is wrong")

		-- GD-1b restores the explicit drills list and the burner blacklist.
		runner.assert(
			config.drills and config.drills["electric-mining-drill"] == true,
			"the drills option was not normalised to a dictionary"
		)
		runner.assert(config.drills["burner-mining-drill"] == true, "the drills option lost a listed drill")
		runner.assert(config.drills[1] == nil, "the drills option kept numeric keys")
		runner.assert(
			config.blacklist and config.blacklist["burner-mining-drill"] == true,
			"the blacklist option was not normalised to a dictionary"
		)

		local late_config = get_configs(runner)["funit-gd-late"]
		runner.assert(late_config, "the late enable_ground_diggers() call did not persist its config")
		runner.assert(late_config.recipe == "funit-gd-late-recipe", "the late config has the wrong recipe")
		runner.assert(late_config.diggers and next(late_config.diggers), "the late config has no resolved diggers")
	end)

	runner.test("GD-2 is_eligible_drill exclusions on real prototypes", function()
		assert_entry(runner, DATA_SUITE, "GD-2")

		local config = get_configs(runner)["funit-gd-planet"]
		runner.assert(config, "the configured planet has no ground-digger config")
		runner.assert(config.diggers["electric-mining-drill"], "the electric mining drill was not resolved")
		runner.assert(
			config.diggers["burner-mining-drill"] == nil,
			"the blacklisted burner mining drill was resolved"
		)
		runner.assert(
			config.diggers["funit-gd-conditioned-drill"],
			"the conditioned drill was not resolved"
		)

		runner.assert(
			prototypes.entity["electric-mining-drill-ground-digger"],
			"the electric mining drill's shared digger is missing"
		)
		runner.assert(
			prototypes.entity["burner-mining-drill-ground-digger"],
			"the burner mining drill's shared digger should exist for default planets"
		)
		runner.assert(
			prototypes.entity["funit-gd-conditioned-drill-ground-digger"],
			"the conditioned drill's shared digger is missing"
		)
		runner.assert(
			prototypes.entity["pumpjack-ground-digger"] == nil,
			"a pumpjack ground digger was generated even though it outputs fluid"
		)
	end)

	runner.test("GD-3 create_ground_digger field mapping on the shared prototype", function()
		assert_entry(runner, DATA_SUITE, "GD-3")

		local digger = prototypes.entity["electric-mining-drill-ground-digger"]
		runner.assert(digger, "the shared electric mining drill digger is missing")
		runner.assert(digger.type == "assembling-machine", "the digger is not an assembling machine")

		for _, category in ipairs({ "funit-gd-category-a", "funit-gd-category-b", "crafting" }) do
			runner.assert(
				digger.crafting_categories and digger.crafting_categories[category] == true,
				"the shared digger is missing the '" .. category .. "' crafting category"
			)
		end

		for _, effect in ipairs({ "productivity", "consumption", "speed", "pollution", "quality" }) do
			runner.assert(
				digger.allowed_effects and digger.allowed_effects[effect] == true,
				"the shared digger does not allow the '" .. effect .. "' effect"
			)
		end

		runner.assert(
			digger.fast_replaceable_group == "mining-drill-ground-digger",
			"the shared digger has the wrong fast_replaceable_group"
		)
		runner.assert(digger.hidden_in_factoriopedia == false, "the shared digger should be visible in Factoriopedia")
		runner.assert(
			digger.localised_name and digger.localised_name[1] == "entity-name.PlanetsLib-ground-digger",
			"the shared digger's localised name does not use the shared key"
		)
		runner.assert(
			digger.localised_description
				and digger.localised_description[1] == "entity-description.PlanetsLib-ground-digger",
			"the shared digger's localised description does not use the shared key"
		)

		runner.assert(
			digger.flags and digger.flags["not-in-made-in"] == true,
			"the shared digger is missing the not-in-made-in flag"
		)
		runner.assert(
			digger.flags and digger.flags["not-in-bonus-gui"] == true,
			"the shared digger is missing the not-in-bonus-gui flag"
		)

		local marker = find_condition(digger.surface_conditions, MARKER)
		runner.assert(marker, "the shared digger has no participating-planet surface condition")
		runner.assert(marker.min == 1 and marker.max == 1, "the marker surface condition is not exactly 1")

		runner.assert(
			digger.electric_energy_source_prototype,
			"the electric digger lost its electric energy source"
		)
		runner.assert(
			digger.electric_energy_source_prototype.drain == 0,
			"the electric digger should default to no drain"
		)
	end)

	runner.test("GD-4 generation, late registration and error paths", function()
		assert_entries(runner, LATE_SUITE, { "GD-4a", "GD-4b", "GD-4c", "GD-4d", "GD-4e", "GD-4f" })
		assert_entry(runner, LATE_SUITE, "GD-1c")

		local configs = get_configs(runner)
		local late_planet = prototypes.space_location["funit-gd-late"]
		runner.assert(late_planet, "the late planet prototype is missing")
		runner.assert(
			late_planet.surface_properties and late_planet.surface_properties[MARKER] == 1,
			"the late planet was not marked as participating"
		)

		local digger = prototypes.entity["electric-mining-drill-ground-digger"]
		runner.assert(digger, "the shared electric mining drill digger is missing")
		for _, category in ipairs({ "funit-gd-category-a", "funit-gd-category-b", "funit-gd-late-category", "crafting" }) do
			runner.assert(
				digger.crafting_categories and digger.crafting_categories[category] == true,
				"the shared digger does not accept the union category '" .. category .. "'"
			)
		end

		local late_config = configs["funit-gd-late"]
		runner.assert(late_config and late_config.diggers, "the late planet has no resolved diggers")
		runner.assert(
			late_config.diggers["electric-mining-drill"],
			"the late planet did not resolve the electric mining drill"
		)

		local conditioned = prototypes.entity["funit-gd-conditioned-drill-ground-digger"]
		runner.assert(conditioned, "the conditioned drill's shared digger is missing")
		runner.assert(
			find_condition(conditioned.surface_conditions, "pressure"),
			"the conditioned digger did not inherit the drill's pressure condition"
		)
		runner.assert(
			find_condition(conditioned.surface_conditions, MARKER),
			"the conditioned digger is missing the participating-planet condition"
		)

		runner.assert(
			prototypes.entity["pumpjack-ground-digger"] == nil,
			"a pumpjack ground digger was generated"
		)
	end)

	runner.test("GD-5 mining-productivity effects", function()
		assert_entry(runner, LATE_SUITE, "GD-5")

		local recipes = {
			"funit-gd-recipe-a",
			"funit-gd-recipe-b",
			"funit-gd-recipe-default",
			"funit-gd-late-recipe",
		}

		local test_tech = prototypes.technology["funit-gd-productivity-tech"]
		runner.assert(test_tech, "the test productivity technology is missing")
		for _, recipe_name in ipairs(recipes) do
			local effects = effects_for(test_tech, recipe_name)
			runner.assert(
				#effects == 1,
				"expected one change-recipe-productivity effect for '"
					.. recipe_name
					.. "', got "
					.. #effects
			)
			runner.assert(effects[1].change == 0.2, "the productivity change for '" .. recipe_name .. "' is wrong")
			runner.assert(effects[1].hidden == true, "the productivity effect for '" .. recipe_name .. "' is not hidden")
		end

		local vanilla = prototypes.technology["mining-productivity-1"]
		if vanilla then
			for _, recipe_name in ipairs(recipes) do
				local effects = effects_for(vanilla, recipe_name)
				runner.assert(
					#effects == 1,
					"expected one change-recipe-productivity effect for '"
						.. recipe_name
						.. "' on mining-productivity-1, got "
						.. #effects
				)
				runner.assert(
					effects[1].change == 0.1,
					"the vanilla productivity change for '" .. recipe_name .. "' is wrong"
				)
			end
		end
	end)
end
