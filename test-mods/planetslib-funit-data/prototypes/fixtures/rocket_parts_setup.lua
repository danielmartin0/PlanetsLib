-- Data-stage fixture: rocket-part recipe/lock mod-data for the rocket_parts suite.
--
-- The runtime `scripts/rocket-parts.on_built_rocket_silo` handler looks up
--   prototypes.mod_data["Planetslib-planet-rocket-part-recipe"].data[surface.name]
-- and the matching lock map, so this fixture installs deterministic entries for
-- the surface names used by the suite. It also registers extra rocket-building
-- recipes whose surface conditions let the suite drive the auto-lock heuristic
-- (`multiple_rocket_parts_can_be_crafted_in_vanilla_silo`) in both directions.
local results = require("lib.results")

local ok, err = pcall(function()
	local recipe_map = data.raw["mod-data"]["Planetslib-planet-rocket-part-recipe"].data
	local lock_map = data.raw["mod-data"]["Planetslib-planet-lock-rocket-silos"].data

	-- A real planet so the public API exercises its documented single-planet
	-- restriction path (the runtime suite only needs the mod-data mapping).
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = "funit-rocket-planet"
	planet.surface_properties = {}
	data:extend({ planet })

	local base = data.raw.recipe["rocket-part"]
	assert(base, "the vanilla 'rocket-part' recipe is missing")

	local function add_rocket_building_recipe(name, surface_conditions)
		local recipe = table.deepcopy(base)
		recipe.name = name
		recipe.categories = { "rocket-building" }
		recipe.surface_conditions = surface_conditions
		data:extend({ recipe })
		return data.raw.recipe[name]
	end

	-- Assigned through the public API below. This also applies the single-planet
	-- restriction, which creates the hidden "PlanetsLib-is-funit-rocket-planet"
	-- surface property (default_value = 0) and sets it to 1 on the planet.
	local assigned = add_rocket_building_recipe("funit-rocket-recipe-a", nil)
	assert(
		assigned.categories and assigned.categories[1] == "rocket-building",
		"the test recipe must be in the rocket-building category"
	)

	PlanetsLib.assign_rocket_part_recipe("funit-rocket-planet", "funit-rocket-recipe-a", true)
	assert(recipe_map["funit-rocket-planet"] == "funit-rocket-recipe-a", "the assigned recipe was not stored")
	assert(lock_map["funit-rocket-planet"] == true, "the lock value was not stored")

	local marker = "PlanetsLib-is-funit-rocket-planet"
	assert(
		data.raw["planet"]["funit-rocket-planet"].surface_properties[marker] == 1,
		"the single-planet surface restriction was not applied"
	)

	-- Extra rocket-building recipes that fit any surface whose marker is 1. They
	-- reuse the fixture's own surface property instead of inventing properties the
	-- game would have to validate. Together with the assigned recipe they guarantee
	-- that >= 2 recipes fit the "multi" fake surface (see the suite).
	local function marker_condition()
		return { { property = marker, min = 1, max = 1 } }
	end
	add_rocket_building_recipe("funit-rocket-recipe-fit-1", marker_condition())
	add_rocket_building_recipe("funit-rocket-recipe-fit-2", marker_condition())

	-- Explicit lock = false.
	PlanetsLib.assign_rocket_part_recipe("funit-rocket-unlocked", "funit-rocket-recipe-a", false)
	assert(recipe_map["funit-rocket-unlocked"] == "funit-rocket-recipe-a", "the unlocked recipe was not stored")
	assert(lock_map["funit-rocket-unlocked"] == false, "lock_silo = false was not preserved")

	-- "_other" stores the mapping but must not create a lock entry.
	PlanetsLib.assign_rocket_part_recipe("funit-rocket-other", "_other")
	assert(recipe_map["funit-rocket-other"] == "_other", "the '_other' mapping was not stored")
	assert(lock_map["funit-rocket-other"] == nil, "'_other' must not set a lock value")

	-- Surfaces with a recipe but no lock entry exercise the auto-lock heuristic.
	-- The API always writes a lock value, so write these entries directly.
	recipe_map["funit-rocket-autolock-multi"] = "funit-rocket-recipe-a"
	recipe_map["funit-rocket-autolock-single"] = "funit-rocket-recipe-a"
	assert(lock_map["funit-rocket-autolock-multi"] == nil, "the auto-lock surface must not have a lock entry")
	assert(lock_map["funit-rocket-autolock-single"] == nil, "the auto-lock surface must not have a lock entry")
end)
results.record("rocket_parts_setup", "RP-FIXTURE-1", ok, err)

return true
