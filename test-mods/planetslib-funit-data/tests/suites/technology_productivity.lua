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

	runner.test("TECH-18 processing excises technologies that end up with no effects", function()
		support.assert_entry(runner, SUITE, "TECH-18")

		local no_match = prototypes.technology["funit-techprod-excise-no-match"]
		runner.assert(no_match and no_match.hidden, "a no-op technology was not excised")
		runner.assert(#no_match.effects == 0, "the excised technology should have no effects")
		local child = prototypes.technology["funit-techprod-excise-no-match-child"]
		runner.assert(child, "funit-techprod-excise-no-match-child is missing")
		runner.assert(
			child.prerequisites["funit-techprod-excise-root"] ~= nil
				and child.prerequisites["funit-techprod-excise-no-match"] == nil,
			"prerequisites were not promoted when the no-op technology was excised"
		)

		local empty = prototypes.technology["funit-techprod-excise-empty"]
		runner.assert(empty and empty.hidden, "an empty effects list did not result in excision")

		local purged = prototypes.technology["funit-techprod-excise-purged"]
		runner.assert(purged and purged.hidden, "a technology emptied by purge_other_effects was not excised")
		runner.assert(#purged.effects == 0, "the purged technology should have no effects")
	end)

	runner.test("TECH-19 force_do_not_excise keeps an empty technology", function()
		support.assert_entry(runner, SUITE, "TECH-19")
		local forced = prototypes.technology["funit-techprod-excise-forced"]
		runner.assert(forced, "funit-techprod-excise-forced is missing")
		runner.assert(forced.hidden ~= true, "force_do_not_excise did not prevent excision")
		runner.assert(#forced.effects == 0, "the forced technology should still have no effects")
	end)

	runner.test("TECH-20 technologies with remaining effects are not excised", function()
		support.assert_entry(runner, SUITE, "TECH-20")
		local kept = prototypes.technology["funit-techprod-excise-kept"]
		runner.assert(kept, "funit-techprod-excise-kept is missing")
		runner.assert(kept.hidden ~= true, "a technology with remaining effects was hidden")
		runner.assert(
			effect_for(kept, "funit-techprod-recipe-single"),
			"the remaining unlock effect was lost"
		)
		runner.assert(#kept.effects == 1, "the technology should keep exactly its original effect")
	end)

	runner.test("TECH-21 technology_name mismatch clears the config without excision", function()
		support.assert_entry(runner, SUITE, "TECH-21")
		local guarded = prototypes.technology["funit-techprod-excise-guarded"]
		runner.assert(guarded, "funit-techprod-excise-guarded is missing")
		runner.assert(guarded.hidden ~= true, "a technology_name mismatch must not excise the technology")
		runner.assert(#guarded.effects == 0, "a technology_name mismatch must not add effects")
	end)

	runner.test("TECH-22 automatic final-fixes pass excises no-op technologies", function()
		support.assert_entry(runner, "technology_final", "TECH-22")
		local tech = prototypes.technology["funit-techprod-auto-excise"]
		runner.assert(tech and tech.hidden, "the no-op technology was not excised by the final-fixes pass")
		runner.assert(#tech.effects == 0, "the excised technology should have no effects")

		local child = prototypes.technology["funit-techprod-auto-excise-child"]
		runner.assert(child, "funit-techprod-auto-excise-child is missing")
		runner.assert(
			child.prerequisites["funit-techprod-auto-root"] ~= nil
				and child.prerequisites["funit-techprod-auto-excise"] == nil,
			"prerequisites were not promoted by the automatic excision"
		)
	end)

	runner.test("TECH-23 automatic final-fixes pass keeps non-empty technologies", function()
		support.assert_entry(runner, "technology_final", "TECH-23")
		local keep = prototypes.technology["funit-techprod-auto-keep"]
		runner.assert(keep, "funit-techprod-auto-keep is missing")
		runner.assert(keep.hidden ~= true, "a technology that gained an effect was hidden")
		runner.assert(
			effect_for(keep, "funit-techprod-recipe-single"),
			"the automatic pass did not add the configured productivity effect"
		)

		local root = prototypes.technology["funit-techprod-auto-root"]
		runner.assert(root and root.hidden ~= true, "an unconfigured technology was hidden")
	end)

	runner.test("TECH-24 force_do_not_excise survives the automatic pass", function()
		support.assert_entry(runner, "technology_final", "TECH-24")
		local force = prototypes.technology["funit-techprod-auto-force"]
		runner.assert(force, "funit-techprod-auto-force is missing")
		runner.assert(force.hidden ~= true, "force_do_not_excise did not prevent the automatic excision")
		runner.assert(#force.effects == 0, "the forced technology should still have no effects")
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
