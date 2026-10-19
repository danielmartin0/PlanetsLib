-- Data-stage fixture: PlanetsLib_recipe_effects data preparation.
--
-- PlanetsLib's own data-final-fixes module
-- (prototypes/override-final/recipe-effects.lua) consumes
-- recipe.PlanetsLib_recipe_effects and derives the fields the runtime handler in
-- scripts/recipe-effects.lua needs. This fixture does two things:
--
--   1. Creates the persistent funit-recipefx-* recipes in data.raw.recipe so
--      that PlanetsLib's data-final-fixes processes them normally. The runtime
--      suite (tests/suites/recipe_effects.lua) asserts the derived fields on the
--      resulting prototypes and mod-data.
--   2. Runs the module against throwaway probe recipes to exercise its error
--      paths and derived fields without aborting the real prototype load. The
--      module is required fresh each time and always cleared from package.loaded
--      afterwards, so PlanetsLib's data-final-fixes still runs it on the real
--      recipes.
local results = require("lib.results")

local MODULE = "__PlanetsLib__.prototypes.override-final.recipe-effects"

-- Run the data-final-fixes module against `recipes` (a name -> recipe table),
-- then restore the real registry and force the module to be re-run later.
local function run_module(recipes, probe_names)
	local real_recipes = data.raw.recipe
	-- Factorio normalises module names to a slash-separated path when caching
	-- them in package.loaded, so the dotted MODULE string does not match the
	-- cache key. Clear every entry for this file so require actually re-runs it.
	for key in pairs(package.loaded) do
		if string.find(key, "recipe-effects", 1, true) then
			package.loaded[key] = nil
		end
	end
	data.raw.recipe = recipes
	local ok, err = pcall(require, MODULE)
	data.raw.recipe = real_recipes
	for key in pairs(package.loaded) do
		if string.find(key, "recipe-effects", 1, true) then
			package.loaded[key] = nil
		end
	end
	if PlanetsLib.constants.recipe_effects then
		for _, probe_name in ipairs(probe_names) do
			PlanetsLib.constants.recipe_effects[probe_name] = nil
		end
	end
	return ok, err
end

local function persistent_recipe(name, ingredient_name, ingredient_amount, returned_ingredient)
	return {
		type = "recipe",
		name = name,
		categories = { "crafting" },
		ingredients = { { type = "item", name = ingredient_name, amount = ingredient_amount } },
		results = { { type = "item", name = "iron-gear-wheel", amount = 1 } },
		energy_required = 0.5,
		hidden = true,
		PlanetsLib_recipe_effects = { returned_ingredients = { returned_ingredient } },
	}
end

-- Persistent recipes. A returned ingredient may carry no probability at all;
-- the data-prep module sets no_probability for the runtime handler (REC-1d).
local RECIPES = {
	persistent_recipe("funit-recipefx-shared", "iron-ore", 3, {
		type = "item",
		name = "iron-ore",
		amount = 2,
		shared_probability = { min = 0.25, max = 0.75 },
		ignored_by_productivity = 1,
		ignored_by_stats = 1,
	}),
	persistent_recipe("funit-recipefx-independent", "copper-ore", 4, {
		type = "item",
		name = "copper-ore",
		amount = 1,
		independent_probability = 0.5,
		ignored_by_stats = 4,
	}),
	persistent_recipe("funit-recipefx-batch", "iron-plate", 2, {
		type = "item",
		name = "iron-plate",
		amount = 2,
		batch_count = 4,
		shared_probability = { min = 0, max = 1 },
	}),
	-- No probability is supplied: the data-prep module must set no_probability,
	-- and the tooltip must fall back to the amount-only form.
	persistent_recipe("funit-recipefx-always", "copper-plate", 1, {
		type = "item",
		name = "copper-plate",
		amount = 3,
	}),
}

local function record(id, ok, err)
	results.record("recipe_effects_setup", id, ok, err)
end

-- 1. Create the persistent recipes.
local setup_ok, setup_err = pcall(function()
	local to_extend = {}
	for _, recipe in ipairs(RECIPES) do
		to_extend[#to_extend + 1] = recipe
	end
	data:extend(to_extend)
	for _, recipe in ipairs(RECIPES) do
		assert(data.raw.recipe[recipe.name], "recipe '" .. recipe.name .. "' was not created")
	end
end)
record("REC-1", setup_ok, setup_err)

-- 2. REC-1a: a returned fluid must raise the documented error.
do
	local probe = {
		type = "recipe",
		name = "funit-recipefx-probe-fluid",
		ingredients = { { type = "item", name = "iron-ore", amount = 1 } },
		results = {},
		PlanetsLib_recipe_effects = {
			returned_ingredients = { { type = "fluid", name = "water", amount = 1 } },
		},
	}
	local ok, err = run_module({ [probe.name] = probe }, { probe.name })
	local matched = (not ok)
		and tostring(err):find("Returning fluids are not currently supported", 1, true) ~= nil
	record(
		"REC-1a",
		matched,
		ok and "the fluid probe loaded instead of raising the documented error"
			or ("unexpected error: " .. tostring(err))
	)
end

-- 3. REC-1b: shared probability and derived fields plus the success tooltip.
do
	local probe = {
		type = "recipe",
		name = "funit-recipefx-probe-shared",
		ingredients = { { type = "item", name = "iron-ore", amount = 5, ignored_by_stats = 2 } },
		results = {},
		PlanetsLib_recipe_effects = {
			returned_ingredients = {
				{
					type = "item",
					name = "iron-ore",
					amount = 3,
					shared_probability = { min = 0.25, max = 0.75 },
					ignored_by_productivity = 1,
					batch_count = 4,
				},
			},
		},
	}
	local ok, err = run_module({ [probe.name] = probe }, { probe.name })
	local returned = probe.PlanetsLib_recipe_effects.returned_ingredients[1]
	local problems = {}
	if not ok then
		problems[#problems + 1] = "module raised: " .. tostring(err)
	end
	if probe.raise_on_crafted ~= true then
		problems[#problems + 1] = "raise_on_crafted was not set to true"
	end
	if probe.ingredients[1].ignored_by_stats ~= 5 then
		problems[#problems + 1] = "the ingredient's ignored_by_stats was not set to its amount"
	end
	if returned.add_to_stats ~= 3 then
		problems[#problems + 1] = "add_to_stats was not amount - ignored_by_stats (got "
			.. tostring(returned.add_to_stats)
			.. ")"
	end
	if returned.amount_minus_ignored_by_productivity ~= 2 then
		problems[#problems + 1] = "amount_minus_ignored_by_productivity was not derived (got "
			.. tostring(returned.amount_minus_ignored_by_productivity)
			.. ")"
	end
	if returned.inverse_batch_count ~= 0.25 then
		problems[#problems + 1] = "inverse_batch_count was not derived (got "
			.. tostring(returned.inverse_batch_count)
			.. ")"
	end
	if returned.no_probability then
		problems[#problems + 1] = "no_probability was set despite shared_probability being present"
	end

	local tooltip = probe.custom_tooltip_fields and probe.custom_tooltip_fields[1]
	if not tooltip then
		problems[#problems + 1] = "custom_tooltip_fields was not added"
	else
		if type(tooltip.name) ~= "table" or tooltip.name[1] ~= "tooltip.returned-ingredients" then
			problems[#problems + 1] = "the tooltip name is wrong"
		end
		if type(tooltip.value) ~= "table"
			or tooltip.value[1] ~= "tooltip-value.returned-ingredients-probability" then
			problems[#problems + 1] = "the tooltip value did not use the probability localisation key"
		elseif tostring(tooltip.value[2]) ~= "50" or tostring(tooltip.value[3]) ~= "3" then
			problems[#problems + 1] = "the shared-probability tooltip was not (max-min)*100 and amount (got "
				.. tostring(tooltip.value[2])
				.. ", "
				.. tostring(tooltip.value[3])
				.. ")"
		end
	end

	record("REC-1b", #problems == 0, table.concat(problems, "; "))
end

-- 4. REC-1c: independent_probability and its tooltip.
--
-- Note: the shared branch formats the tooltip probability as a percentage
-- ((max-min)*100) while the independent branch uses the raw 0..1 value. This is
-- recorded as-is (characterisation); see the suite's runner.log note.
do
	local probe = {
		type = "recipe",
		name = "funit-recipefx-probe-independent",
		ingredients = { { type = "item", name = "copper-ore", amount = 4 } },
		results = {},
		PlanetsLib_recipe_effects = {
			returned_ingredients = {
				{ type = "item", name = "copper-ore", amount = 1, independent_probability = 0.5 },
			},
		},
	}
	local ok, err = run_module({ [probe.name] = probe }, { probe.name })
	local returned = probe.PlanetsLib_recipe_effects.returned_ingredients[1]
	local problems = {}
	if not ok then
		problems[#problems + 1] = "module raised: " .. tostring(err)
	end
	if returned.add_to_stats ~= 4 then
		problems[#problems + 1] = "add_to_stats was not the ingredient amount (got "
			.. tostring(returned.add_to_stats)
			.. ")"
	end
	if returned.amount_minus_ignored_by_productivity ~= 1 then
		problems[#problems + 1] = "amount_minus_ignored_by_productivity was not derived (got "
			.. tostring(returned.amount_minus_ignored_by_productivity)
			.. ")"
	end
	if returned.no_probability then
		problems[#problems + 1] = "no_probability was set despite independent_probability being present"
	end
	local tooltip = probe.custom_tooltip_fields and probe.custom_tooltip_fields[1]
	if not tooltip then
		problems[#problems + 1] = "custom_tooltip_fields was not added"
	elseif type(tooltip.value) ~= "table"
		or tooltip.value[1] ~= "tooltip-value.returned-ingredients-probability" then
		problems[#problems + 1] = "the tooltip value did not use the probability localisation key"
	elseif tostring(tooltip.value[2]) ~= "0.5" or tostring(tooltip.value[3]) ~= "1" then
		problems[#problems + 1] = "the independent-probability tooltip was not the raw value and amount (got "
			.. tostring(tooltip.value[2])
			.. ", "
			.. tostring(tooltip.value[3])
			.. ")"
	end
	record("REC-1c", #problems == 0, table.concat(problems, "; "))
end

-- 5. REC-1d/REC-1e: a returned ingredient with no probability.
--
-- The runtime handler supports no_probability (scripts/recipe-effects.lua:22),
-- and the data-final-fixes tooltip must fall back to the amount-only form. REC-1d
-- records the documented expectation; REC-1e records the derived fields.
do
	local probe = {
		type = "recipe",
		name = "funit-recipefx-probe-noprobability",
		ingredients = { { type = "item", name = "iron-ore", amount = 5 } },
		results = {},
		PlanetsLib_recipe_effects = {
			returned_ingredients = {
				{ type = "item", name = "iron-ore", amount = 2, ignored_by_productivity = 1 },
			},
		},
	}
	local ok, err = run_module({ [probe.name] = probe }, { probe.name })
	record(
		"REC-1d",
		ok,
		"a returned ingredient with no probability (no_probability) must load, but "
			.. "prototypes/override-final/recipe-effects.lua:35-36 raised: "
			.. tostring(err)
	)

	local returned = probe.PlanetsLib_recipe_effects.returned_ingredients[1]
	local fields_ok = returned.no_probability == true
		and returned.add_to_stats == 5
		and returned.amount_minus_ignored_by_productivity == 1
	record(
		"REC-1e",
		fields_ok,
		"expected no_probability=true, add_to_stats=5 and amount_minus_ignored_by_productivity=1 (got "
			.. tostring(returned.no_probability)
			.. ", "
			.. tostring(returned.add_to_stats)
			.. ", "
			.. tostring(returned.amount_minus_ignored_by_productivity)
			.. ")"
	)
end

-- 6. REC-1f: the module must not be left cached, otherwise PlanetsLib's
-- data-final-fixes would skip the persistent recipes.
record(
	"REC-1f",
	package.loaded[MODULE] == nil,
	"the recipe-effects module was left cached; PlanetsLib's data-final-fixes would not process the real recipes"
)

return true
