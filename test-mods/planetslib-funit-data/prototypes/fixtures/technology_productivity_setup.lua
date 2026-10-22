-- Data-stage fixture: PlanetsLib_recipe_productivity_effects processing
-- (lib/technology.lua, PlanetsLib.process_technology_recipe_productivity_effects).
--
-- The fixture runs in the `data` stage, before PlanetsLib's own
-- data-final-fixes, so it creates the recipes/technologies it needs and calls
-- the processing function directly. That keeps the assertions independent of
-- PlanetsLib's final-fixes timing.
--
-- Every created technology has its PlanetsLib_recipe_productivity_effects field
-- cleared after the direct call. The source now clears the correctly spelled
-- field too (TECH-9-clears-input); the helper keeps clearing it so a regression
-- cannot make PlanetsLib's later final-fixes pass reprocess the technology.
local results = require("lib.results")

local SUITE = "technology_productivity_setup"

-- == Prototype helpers == == --

local function make_item(name)
	local item = table.deepcopy(data.raw.item["iron-plate"])
	item.name = name
	data:extend({ item })
end

local function make_category(name)
	if data.raw["recipe-category"][name] then
		return
	end
	local category = table.deepcopy(data.raw["recipe-category"]["crafting"])
	category.name = name
	data:extend({ category })
end

local function make_recipe(name, recipe_results, options)
	options = options or {}
	local recipe = {
		type = "recipe",
		name = name,
		icon = "__base__/graphics/icons/iron-plate.png",
		icon_size = 64,
		categories = options.categories or { "crafting" },
		ingredients = { { type = "item", name = "iron-plate", amount = 1 } },
		results = recipe_results,
		energy_required = 1,
		enabled = true,
	}
	if options.allow_productivity ~= nil then
		recipe.allow_productivity = options.allow_productivity
	end
	if options.blacklist then
		recipe.PlanetsLib_blacklist_technology_updates = true
	end
	data:extend({ recipe })
end

local TECH_TEMPLATE

local function make_tech(name, existing_effects, config)
	local tech = table.deepcopy(TECH_TEMPLATE)
	tech.name = name
	tech.prerequisites = nil
	tech.effects = existing_effects or {}
	tech.PlanetsLib_recipe_productivity_effects = config
	data:extend({ tech })
	return data.raw.technology[name]
end

-- Run the processing, then always clear the (correctly spelled) field so the
-- later final-fixes pass skips this test technology.
local function process(tech)
	local ok, err = pcall(PlanetsLib.process_technology_recipe_productivity_effects, tech)
	tech.PlanetsLib_recipe_productivity_effects = nil
	if not ok then
		error(err, 0)
	end
end

local function process_expecting_error(tech)
	local ok, err = pcall(PlanetsLib.process_technology_recipe_productivity_effects, tech)
	tech.PlanetsLib_recipe_productivity_effects = nil
	return ok, err
end

local function effect_for(tech, recipe_name)
	for _, effect in ipairs(tech.effects or {}) do
		if effect.recipe == recipe_name then
			return effect
		end
	end
	return nil
end

local function check(id, fn)
	local ok, err = pcall(fn)
	results.record(SUITE, id, ok, err)
end

-- == Setup == == --

local setup_ok, setup_err = pcall(function()
	TECH_TEMPLATE = data.raw.technology["automation"]
		or data.raw.technology["electronics"]
		or data.raw.technology["steel-processing"]
	assert(TECH_TEMPLATE, "no vanilla technology is available to use as a template")

	make_category("funit-techprod-cat")
	make_category("funit-techprod-blk")
	-- The default category_blacklist targets "recycling"; Space Age defines it,
	-- but the base game does not, so create it when it is missing.
	make_category("recycling")

	for _, name in ipairs({ "a", "b", "c", "d", "e", "f", "g", "i" }) do
		make_item("funit-techprod-" .. name)
	end

	-- One productivity-capable result; allow_productivity is on.
	make_recipe("funit-techprod-recipe-single", {
		{ type = "item", name = "funit-techprod-a", amount = 1 },
	}, { allow_productivity = true })

	-- Two different productivity-capable results (skipped without
	-- allow_multiple_results).
	make_recipe("funit-techprod-recipe-multi", {
		{ type = "item", name = "funit-techprod-b", amount = 1 },
		{ type = "item", name = "funit-techprod-c", amount = 1 },
	}, { allow_productivity = true })

	-- Two results with the same name/type: counted as a single result.
	make_recipe("funit-techprod-recipe-dup", {
		{ type = "item", name = "funit-techprod-b", amount = 1 },
		{ type = "item", name = "funit-techprod-b", amount = 1 },
	}, { allow_productivity = true })

	-- allow_productivity is absent (false).
	make_recipe("funit-techprod-recipe-noprod", {
		{ type = "item", name = "funit-techprod-d", amount = 1 },
	})

	-- Same output as recipe-single, but in the default-blacklisted category.
	make_recipe("funit-techprod-recipe-recycling", {
		{ type = "item", name = "funit-techprod-a", amount = 1 },
	}, { allow_productivity = true, categories = { "recycling" } })

	-- Category-only recipe.
	make_recipe("funit-techprod-recipe-cat", {
		{ type = "item", name = "funit-techprod-c", amount = 1 },
	}, { allow_productivity = true, categories = { "funit-techprod-cat" } })

	-- Documented recipe blacklist field.
	make_recipe("funit-techprod-recipe-blacklisted", {
		{ type = "item", name = "funit-techprod-e", amount = 1 },
	}, { allow_productivity = true, blacklist = true })

	-- Partially ignored by productivity: 1 < 2, so the result still counts.
	make_recipe("funit-techprod-recipe-ignored-in", {
		{ type = "item", name = "funit-techprod-f", amount = 2, ignored_by_productivity = 1 },
	}, { allow_productivity = true })

	-- Fully ignored by productivity: 1 >= 1, so the recipe is ineligible.
	make_recipe("funit-techprod-recipe-ignored-out", {
		{ type = "item", name = "funit-techprod-g", amount = 1, ignored_by_productivity = 1 },
	}, { allow_productivity = true })

	-- Recipe used by the custom category_blacklist check.
	make_recipe("funit-techprod-recipe-blkcat", {
		{ type = "item", name = "funit-techprod-i", amount = 1 },
	}, { allow_productivity = true, categories = { "funit-techprod-blk" } })
end)
results.record(SUITE, "TECH-9-setup", setup_ok, setup_err)

if not setup_ok then
	return true
end

-- == TECH-9: purge/force-include, guards, selection, blacklists == --

check("TECH-9-purge", function()
	local tech = make_tech("funit-techprod-purge", {
		{ type = "unlock-recipe", recipe = "funit-techprod-recipe-single" },
		{
			type = "change-recipe-productivity",
			recipe = "funit-techprod-recipe-cat",
			change = 0.5,
			PlanetsLib_force_include = true,
		},
	}, {
		purge_other_effects = true,
		effects = { { type = "item", name = "funit-techprod-a", change = 0.1 } },
	})
	process(tech)

	assert(effect_for(tech, "funit-techprod-recipe-cat"), "the PlanetsLib_force_include effect was purged")
	assert(effect_for(tech, "funit-techprod-recipe-single"), "the matching recipe was not added")
	assert(
		effect_for(tech, "funit-techprod-recipe-single").change == 0.1,
		"the configured change value was not propagated"
	)
	for _, effect in ipairs(tech.effects) do
		assert(effect.type ~= "unlock-recipe", "an effect without PlanetsLib_force_include was not purged")
	end
	assert(#tech.effects == 2, "expected the force-included effect plus the new one, got " .. #tech.effects)
end)

check("TECH-9-nopurge", function()
	local tech = make_tech("funit-techprod-nopurge", {
		{ type = "unlock-recipe", recipe = "funit-techprod-recipe-multi" },
	}, {
		effects = { { type = "item", name = "funit-techprod-a", change = 0.2 } },
	})
	process(tech)

	assert(
		effect_for(tech, "funit-techprod-recipe-multi"),
		"existing effects must be preserved without purge_other_effects"
	)
	assert(effect_for(tech, "funit-techprod-recipe-single"), "the matching recipe was not added")
end)

check("TECH-9-clears-input", function()
	local tech = make_tech("funit-techprod-clears-input", {}, {
		effects = { { type = "item", name = "funit-techprod-a", change = 0.1 } },
	})
	PlanetsLib.process_technology_recipe_productivity_effects(tech)
	assert(
		tech.PlanetsLib_recipe_productivity_effects == nil,
		"process_technology_recipe_productivity_effects must clear its input field"
	)
	tech.PlanetsLib_recipe_productivity_effects = nil
end)

check("TECH-9-guard", function()
	local tech = make_tech("funit-techprod-guard-mismatch", {}, {
		technology_name = "funit-techprod-someone-else",
		effects = { { type = "item", name = "funit-techprod-a", change = 0.1 } },
	})
	process(tech)

	assert(#tech.effects == 0, "a technology_name mismatch must leave the technology unprocessed")
end)

check("TECH-9-guard-match", function()
	local tech = make_tech("funit-techprod-guard-match", {}, {
		technology_name = "funit-techprod-guard-match",
		effects = { { type = "item", name = "funit-techprod-a", change = 0.1 } },
	})
	process(tech)

	assert(
		effect_for(tech, "funit-techprod-recipe-single"),
		"a matching technology_name must not block processing"
	)
end)

check("TECH-9-name-type", function()
	local matching = make_tech("funit-techprod-name-type", {}, {
		effects = { { type = "item", name = "funit-techprod-a", change = 0.1 } },
	})
	process(matching)
	assert(effect_for(matching, "funit-techprod-recipe-single"), "a name+type filter should match the recipe")

	local wrong_type = make_tech("funit-techprod-wrong-type", {}, {
		effects = { { type = "fluid", name = "funit-techprod-a", change = 0.1 } },
	})
	process(wrong_type)
	assert(
		not effect_for(wrong_type, "funit-techprod-recipe-single"),
		"a name filter with the wrong result type must not match"
	)
end)

check("TECH-9-recycling", function()
	local tech = make_tech("funit-techprod-recycling", {}, {
		effects = { { type = "item", name = "funit-techprod-a", change = 0.1 } },
	})
	process(tech)

	assert(effect_for(tech, "funit-techprod-recipe-single"), "the crafting recipe should be added")
	assert(
		not effect_for(tech, "funit-techprod-recipe-recycling"),
		"the default category_blacklist must exclude the 'recycling' category"
	)
end)

check("TECH-9-catbl", function()
	local tech = make_tech("funit-techprod-catbl", {}, {
		category_blacklist = { "funit-techprod-blk" },
		effects = { { type = "item", name = "funit-techprod-i", change = 0.1 } },
	})
	process(tech)

	assert(
		not effect_for(tech, "funit-techprod-recipe-blkcat"),
		"a custom category_blacklist must exclude recipes in that category"
	)
end)

-- Documented behavior: a recipe with PlanetsLib_blacklist_technology_updates
-- set is skipped. The implementation reads the correctly-spelled field in
-- lib/technology.lua; this check guards that behavior.
check("TECH-9-blacklist", function()
	local tech = make_tech("funit-techprod-blacklist", {}, {
		effects = { { type = "item", name = "funit-techprod-e", change = 0.1 } },
	})
	process(tech)

	assert(
		not effect_for(tech, "funit-techprod-recipe-blacklisted"),
		"a recipe with PlanetsLib_blacklist_technology_updates = true must be skipped"
	)
end)

check("TECH-9-ignored", function()
	local included = make_tech("funit-techprod-ignored-in", {}, {
		effects = { { type = "item", name = "funit-techprod-f", change = 0.1 } },
	})
	process(included)
	assert(
		effect_for(included, "funit-techprod-recipe-ignored-in"),
		"a result that is only partially ignored by productivity should still qualify"
	)

	local excluded = make_tech("funit-techprod-ignored-out", {}, {
		effects = { { type = "item", name = "funit-techprod-g", change = 0.1 } },
	})
	process(excluded)
	assert(
		not effect_for(excluded, "funit-techprod-recipe-ignored-out"),
		"a recipe whose only result is fully ignored by productivity must be skipped"
	)
end)

check("TECH-9-xor", function()
	local both = make_tech("funit-techprod-xor-both", {}, {
		effects = { { type = "item", name = "funit-techprod-a", category = "crafting", change = 0.1 } },
	})
	local both_ok = process_expecting_error(both)
	assert(not both_ok, "name and category together must be rejected")

	local neither = make_tech("funit-techprod-xor-none", {}, {
		effects = { { change = 0.1 } },
	})
	local neither_ok = process_expecting_error(neither)
	assert(not neither_ok, "neither name nor category must be rejected")

	local no_type = make_tech("funit-techprod-xor-notype", {}, {
		effects = { { name = "funit-techprod-a", change = 0.1 } },
	})
	local no_type_ok = process_expecting_error(no_type)
	assert(not no_type_ok, "a name filter without a type must be rejected")

	local category_and_blacklist = make_tech("funit-techprod-xor-catbl", {}, {
		category_blacklist = { "recycling" },
		effects = { { category = "crafting", change = 0.1 } },
	})
	local catbl_ok = process_expecting_error(category_and_blacklist)
	assert(not catbl_ok, "category with category_blacklist must be rejected")
end)

-- == TECH-10: result counting, allow flags, category, vanilla change == --

check("TECH-10-single", function()
	local tech = make_tech("funit-techprod-single-result", {}, {
		effects = { { type = "item", name = "funit-techprod-b", change = 0.1 } },
	})
	process(tech)

	assert(
		not effect_for(tech, "funit-techprod-recipe-multi"),
		"a recipe with multiple productivity-capable results must be skipped by default"
	)
	assert(
		effect_for(tech, "funit-techprod-recipe-dup"),
		"duplicate result names must be counted as a single result"
	)
end)

check("TECH-10-multiple", function()
	local tech = make_tech("funit-techprod-multiple-results", {}, {
		effects = {
			{ type = "item", name = "funit-techprod-b", change = 0.1, allow_multiple_results = true },
		},
	})
	process(tech)

	assert(
		effect_for(tech, "funit-techprod-recipe-multi"),
		"allow_multiple_results must include recipes with several results"
	)
	assert(effect_for(tech, "funit-techprod-recipe-dup"), "the single-result recipe should still be included")
end)

check("TECH-10-dedupe", function()
	local tech = make_tech("funit-techprod-dedupe", {}, {
		effects = {
			{ type = "item", name = "funit-techprod-a", change = 0.1 },
			{ type = "item", name = "funit-techprod-a", change = 0.9 },
		},
	})
	process(tech)

	local count = 0
	for _, effect in ipairs(tech.effects) do
		if effect.recipe == "funit-techprod-recipe-single" then
			count = count + 1
		end
	end
	assert(count == 1, "the same recipe must not be added twice (got " .. count .. ")")
	assert(
		effect_for(tech, "funit-techprod-recipe-single").change == 0.1,
		"the first matching effect's change should win"
	)
end)

check("TECH-10-noprod", function()
	local excluded = make_tech("funit-techprod-noprod-default", {}, {
		effects = { { type = "item", name = "funit-techprod-d", change = 0.1 } },
	})
	process(excluded)
	assert(
		not effect_for(excluded, "funit-techprod-recipe-noprod"),
		"recipes without allow_productivity must be skipped by default"
	)

	local included = make_tech("funit-techprod-noprod-allowed", {}, {
		allow_recipes_without_productivity = true,
		effects = { { type = "item", name = "funit-techprod-d", change = 0.1 } },
	})
	process(included)
	assert(
		effect_for(included, "funit-techprod-recipe-noprod"),
		"allow_recipes_without_productivity must include recipes with allow_productivity disabled"
	)
end)

check("TECH-10-category", function()
	local tech = make_tech("funit-techprod-category", {}, {
		effects = { { category = "funit-techprod-cat", change = 0.15 } },
	})
	process(tech)

	local effect = effect_for(tech, "funit-techprod-recipe-cat")
	assert(effect, "the category filter did not match the recipe")
	assert(effect.change == 0.15, "the category effect's change was not propagated")
end)

local vanilla_tech = data.raw.technology["steel-plate-productivity"]
if not vanilla_tech then
	-- Base Factorio has no steel-plate-productivity technology; this check is
	-- meaningful only with Space Age's productivity technologies.
	results.skip(
		SUITE,
		"TECH-10-vanilla",
		"the active prototype set has no steel-plate-productivity technology"
	)
else
	check("TECH-10-vanilla", function()
		local setting = settings.startup["PlanetsLib-update-vanilla-recipe-productivity-techs"]
		assert(setting, "the PlanetsLib-update-vanilla-recipe-productivity-techs setting is missing")
		assert(setting.value, "the vanilla productivity update setting must be enabled in the test scenario")

		local tech = data.raw.technology["steel-plate-productivity"]
		local config = tech.PlanetsLib_recipe_productivity_effects
		assert(
			config and config.effects and config.effects[1],
			"the vanilla override did not configure steel-plate-productivity"
		)

		local inherited = tech.effects and tech.effects[1] and tech.effects[1].change
		assert(inherited, "steel-plate-productivity has no inherited effect")
		assert(
			config.effects[1].change == inherited,
			"the vanilla productivity technology did not inherit its change value"
		)
	end)
end

return true
