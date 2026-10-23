-- Data-updates fixture: excise_recipe_from_tech_tree with
-- include_productivity_effects during the data-updates stage.
--
-- This stage runs after PlanetsLib's own data-updates.lua, so
-- PlanetsLib.current_stage is "data-updates". The documented behavior is that
-- the recipe is blacklisted from later technology updates when the function is
-- called before data-final-fixes.
local results = require("lib.results")

local SUITE = "technology_excise_updates"
local RECIPE = "funit-tech-excise-updates-recipe"

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

local ok, err = pcall(function()
	assert(
		PlanetsLib.current_stage == "data-updates",
		"this check must run during data-updates, got " .. tostring(PlanetsLib.current_stage)
	)

	local recipe_source = data.raw.recipe["iron-gear-wheel"] and "iron-gear-wheel" or next(data.raw.recipe)
	assert(recipe_source, "no recipe prototype is available to clone")
	local tech_source = find_tech_source()
	assert(tech_source, "no researchable technology prototype is available to clone")

	local recipe = table.deepcopy(data.raw.recipe[recipe_source])
	recipe.name = RECIPE

	local function clone_tech(name, prerequisites, effects)
		local tech = table.deepcopy(data.raw.technology[tech_source])
		tech.name = name
		tech.prerequisites = prerequisites or {}
		tech.effects = effects or {}
		tech.hidden = nil
		tech.research_trigger = nil
		return tech
	end

	local root = clone_tech("funit-tech-excise-updates-root", {}, {})
	local target = clone_tech("funit-tech-excise-updates-tech", { root.name }, {
		{ type = "change-recipe-productivity", recipe = RECIPE, change = 0.1 },
	})
	local child = clone_tech("funit-tech-excise-updates-child", { target.name }, {})

	data:extend({ recipe, root, target, child })

	PlanetsLib.excise_recipe_from_tech_tree(RECIPE, true)

	assert(
		data.raw.recipe[RECIPE].PlanetsLib_blacklist_technology_updates == true,
		"the recipe must be blacklisted when excising before data-final-fixes"
	)
	assert(
		#data.raw.technology["funit-tech-excise-updates-tech"].effects == 0,
		"the recipe's productivity effect was not removed during data-updates"
	)
	assert(
		data.raw.technology["funit-tech-excise-updates-tech"].hidden == true,
		"the technology emptied during data-updates must be hidden"
	)

	local prerequisites = data.raw.technology["funit-tech-excise-updates-child"].prerequisites
	assert(
		#prerequisites == 1 and prerequisites[1] == "funit-tech-excise-updates-root",
		"prerequisites were not promoted when the technology was excised during data-updates"
	)
end)
results.record(SUITE, "TECH-16", ok, err)

return true
