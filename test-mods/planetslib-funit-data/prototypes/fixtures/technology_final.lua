-- Data-final-fixes fixture: technology behavior that requires PlanetsLib's own
-- data-final-fixes pass to have run first.
--
-- Checks two things:
--   * excise_recipe_from_tech_tree(..., true) must not blacklist the recipe
--     when called during data-final-fixes (too late to affect technology
--     processing).
--   * PlanetsLib_recipe_productivity_effects technologies that produce no
--     effects are excised automatically, unless force_do_not_excise is set.
--
-- The technologies below are created by technology_productivity_setup.lua in
-- the data stage, so PlanetsLib's final-fixes pass has processed them by the
-- time this fixture runs.
local results = require("lib.results")

local SUITE = "technology_final"

local function find_tech_source()
	for _, candidate in ipairs({ "automation", "steel-processing", "electronics" }) do
		local tech = data.raw.technology[candidate]
		if tech and tech.unit and tech.unit.ingredients and (tech.icon or tech.icons) then
			return candidate
		end
	end
	for name, tech in pairs(data.raw.technology) do
		if tech.unit and tech.unit.ingredients and (tech.icon or tech.icons) then
			return name
		end
	end
end

local function effect_for(tech, recipe_name)
	for _, effect in ipairs(tech.effects or {}) do
		if effect.recipe == recipe_name then
			return effect
		end
	end
end

local ok, err = pcall(function()
	assert(
		PlanetsLib.current_stage == "data-final-fixes",
		"this check must run during data-final-fixes, got " .. tostring(PlanetsLib.current_stage)
	)

	local recipe_source = data.raw.recipe["iron-gear-wheel"] and "iron-gear-wheel" or next(data.raw.recipe)
	assert(recipe_source, "no recipe prototype is available to clone")
	local tech_source = find_tech_source()
	assert(tech_source, "no researchable technology prototype is available to clone")

	local function clone_tech(name, prerequisites, effects)
		local tech = table.deepcopy(data.raw.technology[tech_source])
		tech.name = name
		tech.prerequisites = prerequisites or {}
		tech.effects = effects or {}
		tech.hidden = nil
		tech.research_trigger = nil
		return tech
	end

	local recipe = table.deepcopy(data.raw.recipe[recipe_source])
	recipe.name = "funit-tech-excise-final-recipe"

	local target = clone_tech("funit-tech-excise-final-tech", {}, {
		{ type = "change-recipe-productivity", recipe = recipe.name, change = 0.1 },
	})

	data:extend({ recipe, target })

	PlanetsLib.excise_recipe_from_tech_tree(recipe.name, true)

	assert(#target.effects == 0, "the recipe's productivity effect was not removed during data-final-fixes")
	assert(target.hidden == true, "the technology emptied during data-final-fixes must be hidden")
	assert(
		recipe.PlanetsLib_blacklist_technology_updates == nil,
		"the recipe must not be blacklisted when excising during data-final-fixes"
	)
end)
results.record(SUITE, "TECH-17", ok, err)

-- TECH-22: the automatic final-fixes pass excises a no-op technology.
ok, err = pcall(function()
	local tech = data.raw.technology["funit-techprod-auto-excise"]
	assert(tech, "funit-techprod-auto-excise is missing")
	assert(tech.hidden == true, "a technology with no effects after processing must be hidden")
	assert(#tech.effects == 0, "the excised technology should have no effects")
	assert(
		tech.PlanetsLib_recipe_productivity_effects == nil,
		"the input field must be cleared even when the technology is excised"
	)

	local child = data.raw.technology["funit-techprod-auto-excise-child"]
	assert(child, "funit-techprod-auto-excise-child is missing")
	assert(
		#child.prerequisites == 1 and child.prerequisites[1] == "funit-techprod-auto-root",
		"prerequisites were not promoted when the automatic pass emptied the technology"
	)
end)
results.record(SUITE, "TECH-22", ok, err)

-- TECH-23: non-empty and unconfigured technologies are not excised.
ok, err = pcall(function()
	local keep = data.raw.technology["funit-techprod-auto-keep"]
	assert(keep, "funit-techprod-auto-keep is missing")
	assert(keep.hidden ~= true, "a technology that gained an effect must not be hidden")
	assert(
		effect_for(keep, "funit-techprod-recipe-single"),
		"the automatic pass did not add the configured productivity effect"
	)
	assert(
		keep.PlanetsLib_recipe_productivity_effects == nil,
		"the input field must be cleared after processing"
	)

	local root = data.raw.technology["funit-techprod-auto-root"]
	assert(root, "funit-techprod-auto-root is missing")
	assert(root.hidden ~= true, "a technology without PlanetsLib_recipe_productivity_effects must not be hidden")
end)
results.record(SUITE, "TECH-23", ok, err)

-- TECH-24: force_do_not_excise keeps an otherwise empty technology.
ok, err = pcall(function()
	local force = data.raw.technology["funit-techprod-auto-force"]
	assert(force, "funit-techprod-auto-force is missing")
	assert(force.hidden ~= true, "force_do_not_excise must prevent the automatic excision")
	assert(#force.effects == 0, "the force_do_not_excise technology should still have no effects")
	assert(
		force.PlanetsLib_recipe_productivity_effects == nil,
		"the input field must be cleared even when excision is suppressed"
	)
end)
results.record(SUITE, "TECH-24", ok, err)

return true
