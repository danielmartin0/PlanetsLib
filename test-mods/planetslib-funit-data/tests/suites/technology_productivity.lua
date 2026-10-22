-- Recipe productivity technology helper field
-- (lib/technology.lua, PlanetsLib.process_technology_recipe_productivity_effects).
--
-- The data-stage behavior is exercised by the technology_productivity_setup
-- fixture, which calls the processing function directly and records each
-- check. This suite asserts those results plus the runtime technology
-- prototypes they produced.

local SUITE = "technology_productivity_setup"
local support = require("__planetslib-funit-data__.tests.suites.support")

local TECH_9_IDS = {
	"TECH-9-purge",
	"TECH-9-nopurge",
	"TECH-9-clears-input",
	"TECH-9-guard",
	"TECH-9-guard-match",
	"TECH-9-name-type",
	"TECH-9-recycling",
	"TECH-9-catbl",
	"TECH-9-blacklist",
	"TECH-9-ignored",
	"TECH-9-xor",
}
local TECH_10_IDS = {
	"TECH-10-single",
	"TECH-10-multiple",
	"TECH-10-dedupe",
	"TECH-10-noprod",
	"TECH-10-category",
	"TECH-10-vanilla",
}

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
		support.assert_all(runner, SUITE, { expected = TECH_9_IDS })
	end)

	runner.test("TECH-10 recipe productivity effects: results, allow flags, category, change", function()
		local allow_skips = {}
		if not support.has_space_age() then
			allow_skips["TECH-10-vanilla"] = true
		end
		support.assert_all(runner, SUITE, {
			expected = TECH_10_IDS,
			allow_skips = allow_skips,
		})
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
