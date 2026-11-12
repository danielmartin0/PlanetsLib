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

local function get_max_belt_stack_size(runner)
	local constants = prototypes.utility_constants
	runner.assert(constants, "prototypes.utility_constants is missing")
	local value = constants.max_belt_stack_size
	if value == nil then
		local default = constants["default"]
		if default then
			value = default.max_belt_stack_size
		end
	end
	runner.assert(type(value) == "number", "could not read utility-constants.max_belt_stack_size")
	return value
end

local function find_product(recipe, name)
	for _, product in ipairs(recipe.products or {}) do
		if product.name == name then
			return product
		end
	end
	return nil
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
			config.diggers["funit-gd-restricted-drill"] == nil,
			"a drill restricted to specific resource sites was resolved"
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
		runner.assert(
			prototypes.entity["funit-gd-restricted-drill-ground-digger"] == nil,
			"a ground digger was generated for a drill restricted to specific resource sites"
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

	runner.test("GD-3c all-surface diggers delete surface conditions", function()
		assert_entry(runner, LATE_SUITE, "GD-3c")
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

	runner.test("GD-13 belt-stack variants for a simple recipe", function()
		assert_entry(runner, LATE_SUITE, "GD-1c")
		local max_stack = get_max_belt_stack_size(runner)
		runner.assert(max_stack >= 2, "the test scenario does not have belt stacking enabled")
		runner.assert(max_stack <= 255, "utility-constants.max_belt_stack_size is out of range")

		for stack = 2, max_stack do
			local name = "funit-gd-recipe-a-PlanetsLib-stack-" .. stack
			local recipe = prototypes.recipe[name]
			runner.assert(recipe, "the stack-" .. stack .. " variant is missing")
			runner.assert(recipe.hidden == true, "the stack-" .. stack .. " variant is not hidden")
			runner.assert(recipe.enabled == true, "the stack-" .. stack .. " variant is not enabled")
			runner.assert(
				recipe.energy == stack,
				"the stack-" .. stack .. " variant has the wrong energy requirement"
			)
			local stone = find_product(recipe, "stone")
			runner.assert(stone, "the stack-" .. stack .. " variant does not produce stone")
			runner.assert(stone.amount == stack, "the stack-" .. stack .. " variant has the wrong stone amount")
		end

		local metadata = prototypes.mod_data["Planetslib"].data.ground_digger_recipe_variants
			and prototypes.mod_data["Planetslib"].data.ground_digger_recipe_variants["funit-gd-recipe-a"]
		runner.assert(metadata, "the runtime variant metadata for funit-gd-recipe-a is missing")
		runner.assert(metadata.max_stack == max_stack, "the metadata max_stack is wrong")
		runner.assert(metadata.item_stack_size == 50, "the stone stack size was not recorded")
		runner.assert(metadata.main_product == "stone", "the metadata main_product is wrong")
		runner.assert(metadata.variants[1] == "funit-gd-recipe-a", "the metadata stack-1 entry is wrong")
		for stack = 2, max_stack do
			runner.assert(
				metadata.variants[stack] == "funit-gd-recipe-a-PlanetsLib-stack-" .. stack,
				"the metadata stack-" .. stack .. " entry is wrong"
			)
		end
	end)

	runner.test("GD-14 variants scale fluids, probabilities and extra counts", function()
		local max_stack = get_max_belt_stack_size(runner)

		local fluid_name = "funit-gd-recipe-fluid-PlanetsLib-stack-" .. max_stack
		local fluid = prototypes.recipe[fluid_name]
		runner.assert(fluid, "the fluid-product stack variant is missing")
		local fluid_stone = find_product(fluid, "stone")
		local fluid_water = find_product(fluid, "water")
		runner.assert(fluid_stone, "the fluid-product variant lost its item product")
		runner.assert(fluid_water, "the fluid-product variant lost its fluid product")
		runner.assert(
			fluid_stone.amount == max_stack,
			"the fluid-product variant has the wrong item amount"
		)
		runner.assert(
			fluid_water.amount == 10 * max_stack,
			"the fluid-product variant has the wrong fluid amount"
		)
		runner.assert(
			fluid.energy == max_stack,
			"the fluid-product variant has the wrong energy requirement"
		)

		local double_metadata = prototypes.mod_data["Planetslib"].data.ground_digger_recipe_variants
			and prototypes.mod_data["Planetslib"].data.ground_digger_recipe_variants["funit-gd-recipe-double"]
		runner.assert(double_metadata, "the double-output variant metadata is missing")
		runner.assert(
			double_metadata.variants[2] == "funit-gd-recipe-double",
			"a base recipe that already makes a full stack should use itself for stack 2"
		)
		if max_stack >= 3 then
			local expected = "funit-gd-recipe-double-PlanetsLib-stack-4"
			runner.assert(
				double_metadata.variants[3] == expected,
				"the stack-3 target did not map to a two-craft batch"
			)
			runner.assert(
				prototypes.recipe[expected].products[1].amount == 4,
				"the double-output batch has the wrong amount"
			)
			runner.assert(
				prototypes.recipe[expected].energy == 2,
				"the double-output batch has the wrong energy requirement"
			)
			runner.assert(
				prototypes.recipe["funit-gd-recipe-double-PlanetsLib-stack-2"] == nil,
				"an unnecessary stack-2 variant was generated"
			)
			runner.assert(
				prototypes.recipe["funit-gd-recipe-double-PlanetsLib-stack-3"] == nil,
				"an unnecessary stack-3 variant was generated"
			)
		end
		if max_stack >= 4 then
			runner.assert(
				double_metadata.variants[4] == "funit-gd-recipe-double-PlanetsLib-stack-4",
				"the stack-4 target did not reuse the stack-4 batch"
			)
		end

		local probability = prototypes.recipe["funit-gd-recipe-probability-PlanetsLib-stack-2"]
		runner.assert(probability, "the probability stack-2 variant is missing")
		local probability_stone = find_product(probability, "stone")
		local probability_copper = find_product(probability, "copper-ore")
		runner.assert(probability_stone, "the probability variant lost its main product")
		runner.assert(probability_copper, "the probability variant lost its secondary product")
		runner.assert(
			probability_stone.amount == 3,
			"extra_count_fraction was not converted into a guaranteed extra item"
		)
		runner.assert(
			probability_stone.extra_count_fraction == nil,
			"the converted extra_count_fraction should be nil"
		)
		runner.assert(
			probability_copper.amount == 2,
			"the probabilistic product amount was not scaled"
		)
		runner.assert(
			probability_copper.independent_probability == 0.25,
			"the probabilistic product probability changed"
		)
	end)

	runner.test("GD-15 unstackable products still get variants up to the utility limit", function()
		local max_stack = get_max_belt_stack_size(runner)
		local metadata = prototypes.mod_data["Planetslib"].data.ground_digger_recipe_variants
			and prototypes.mod_data["Planetslib"].data.ground_digger_recipe_variants["funit-gd-recipe-unstackable"]
		runner.assert(metadata, "the unstackable recipe metadata is missing")
		runner.assert(metadata.item_stack_size == 1, "the unstackable item stack size was not recorded")
		runner.assert(metadata.max_stack == max_stack, "the unstackable metadata max_stack is wrong")
		for stack = 2, max_stack do
			runner.assert(
				prototypes.recipe["funit-gd-recipe-unstackable-PlanetsLib-stack-" .. stack],
				"unstackable variants should still be generated up to the utility limit"
			)
		end
	end)
end
