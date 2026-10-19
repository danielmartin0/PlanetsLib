-- Data-stage fixture: rocket-part recipe assignment and cargo-drop whitelists.
local results = require("lib.results")

local function create_planet(name)
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = name
	planet.surface_properties = {}
	data:extend({ planet })
	return data.raw.planet[name]
end

local function has_condition(recipe, property, value)
	for _, condition in ipairs(recipe.surface_conditions or {}) do
		if condition.property == property then
			return condition.min == value and condition.max == value
		end
	end
	return false
end

local ok, err = pcall(function()
	local p1 = create_planet("funit-md-1")
	local p2 = create_planet("funit-md-2")
	local p3 = create_planet("funit-md-3")
	local p4 = create_planet("funit-md-4")

	local recipe_map = data.raw["mod-data"]["Planetslib-planet-rocket-part-recipe"].data
	local lock_map = data.raw["mod-data"]["Planetslib-planet-lock-rocket-silos"].data
	local recipe_name = "iron-gear-wheel"
	local recipe = data.raw.recipe[recipe_name]

	-- First assignment: store the mapping, lock by default and restrict the recipe.
	PlanetsLib.assign_rocket_part_recipe("funit-md-1", recipe_name)
	assert(recipe_map["funit-md-1"] == recipe_name, "planet -> recipe mapping was not stored")
	assert(lock_map["funit-md-1"] == true, "lock_silo should default to true")
	assert(recipe.PlanetsLib_rocket_part_exclusive_to == "funit-md-1", "recipe was not marked exclusive")
	assert(has_condition(recipe, "PlanetsLib-is-funit-md-1", 1), "recipe was not restricted to the first planet")

	-- Second assignment: remove the restriction and never reapply it.
	PlanetsLib.assign_rocket_part_recipe("funit-md-2", recipe_name)
	assert(recipe_map["funit-md-2"] == recipe_name, "second planet mapping was not stored")
	assert(recipe.PlanetsLib_rocket_part_exclusive_to == nil, "the exclusivity marker was not cleared")
	assert(recipe.PlanetsLib_rocket_part_shared == true, "the shared marker was not set")
	assert(not has_condition(recipe, "PlanetsLib-is-funit-md-1", 1), "the single-planet restriction was not removed")
	assert(not has_condition(recipe, "PlanetsLib-is-funit-md-2", 1), "a restriction was added despite being shared")

	-- A third assignment stays unrestricted.
	PlanetsLib.assign_rocket_part_recipe("funit-md-3", recipe_name)
	assert(recipe_map["funit-md-3"] == recipe_name, "third planet mapping was not stored")
	assert(not has_condition(recipe, "PlanetsLib-is-funit-md-3", 1), "the shared recipe gained a restriction")

	-- Prototype-table arguments plus lock_silo = false.
	PlanetsLib.assign_rocket_part_recipe(p1, data.raw.recipe["copper-cable"], false)
	assert(recipe_map["funit-md-1"] == "copper-cable", "prototype-table arguments were not unwrapped")
	assert(lock_map["funit-md-1"] == false, "lock_silo = false must be preserved")

	-- "_other" stores the mapping but does not set lock behaviour. Use a fresh
	-- planet so an earlier default lock cannot mask the check.
	PlanetsLib.assign_rocket_part_recipe(p4, "_other")
	assert(recipe_map["funit-md-4"] == "_other", "'_other' mapping was not stored")
	assert(lock_map["funit-md-4"] == nil, "'_other' must not set a silo lock value")

	-- Cargo-drop whitelists, per planet and global.
	PlanetsLib.add_item_name_to_planet_cargo_drops_whitelist("funit-md-1", "iron-plate")
	PlanetsLib.add_entity_type_to_planet_cargo_drops_whitelist("funit-md-1", "container")
	local whitelist = data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists["funit-md-1"]
	assert(whitelist.item_names["iron-plate"], "planet item whitelist was not updated")
	assert(whitelist.entity_types["container"], "planet entity-type whitelist was not updated")

	PlanetsLib.add_item_name_to_global_cargo_drops_whitelist("copper-plate")
	PlanetsLib.add_entity_type_to_global_cargo_drops_whitelist("inserter")
	local global = data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists.all
	assert(global.item_names["copper-plate"], "global item whitelist was not updated")
	assert(global.entity_types["inserter"], "global entity-type whitelist was not updated")
end)
results.record("mod_data", "MD-1", ok, err)

return true
