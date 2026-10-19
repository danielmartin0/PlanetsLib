-- Recipe productivity technology helper field
-- (lib/technology.lua, PlanetsLib.process_technology_recipe_productivity_effects).
--
-- The data-stage behavior is exercised by the technology_productivity_setup
-- fixture, which calls the processing function directly and records each
-- check. This suite asserts those results plus the runtime technology
-- prototypes they produced.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local SUITE = "technology_productivity_setup"

local function get_namespace(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	local namespace = mod_data.data[SUITE]
	runner.assert(namespace, "no data-stage results recorded for '" .. SUITE .. "'")
	return namespace
end

local function assert_prefix(runner, namespace, prefix)
	local found = false
	for id, entry in pairs(namespace) do
		if id:sub(1, #prefix) == prefix then
			found = true
			runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
		end
	end
	runner.assert(found, "no data-stage results recorded for '" .. prefix .. "'")
end

local function effect_for(tech, recipe_name)
	for _, effect in ipairs(tech.effects or {}) do
		if effect.recipe == recipe_name then
			return effect
		end
	end
	return nil
end

return function(runner)
	runner.test("TECH-9 recipe productivity effects: purge, guards, selection, blacklists", function()
		assert_prefix(runner, get_namespace(runner), "TECH-9")
	end)

	runner.test("TECH-10 recipe productivity effects: results, allow flags, category, change", function()
		assert_prefix(runner, get_namespace(runner), "TECH-10")
	end)

	runner.test("TECH-9a processed technology prototypes are present", function()
		local purge = prototypes.technology["funit-techprod-purge"]
		runner.assert(purge, "funit-techprod-purge is missing")
		runner.assert(
			effect_for(purge, "funit-techprod-recipe-single"),
			"the processed purge technology has no effect for the matching recipe"
		)
		runner.assert(
			effect_for(purge, "funit-techprod-recipe-cat"),
			"the processed purge technology lost its PlanetsLib_force_include effect"
		)
		runner.assert(
			not effect_for(purge, "funit-techprod-recipe-recycling"),
			"the processed purge technology targets the blacklisted recycling recipe"
		)

		local recycling = prototypes.technology["funit-techprod-recycling"]
		runner.assert(recycling, "funit-techprod-recycling is missing")
		runner.assert(
			effect_for(recycling, "funit-techprod-recipe-single"),
			"the recycling technology has no effect for the crafting recipe"
		)
		runner.assert(
			not effect_for(recycling, "funit-techprod-recipe-recycling"),
			"the default recycling blacklist was not applied to the prototype"
		)

		local category = prototypes.technology["funit-techprod-category"]
		runner.assert(category, "funit-techprod-category is missing")
		local category_effect = effect_for(category, "funit-techprod-recipe-cat")
		runner.assert(category_effect, "the category-filtered technology has no effect for the recipe")
		runner.assert(category_effect.change == 0.15, "the category effect change was not applied to the prototype")

		runner.assert(prototypes.recipe["funit-techprod-recipe-single"], "the fixture recipe prototype is missing")
	end)
end
