local Public = {}

function Public.assign_rocket_part_recipe(planet, recipe, lock_silo)
	local planet_name
	local recipe_name
	if type(planet) == "list" then
		planet_name = planet.name
	else
		planet_name = planet
	end
	if type(recipe) == "list" then
		recipe_name = recipe.name
	else
		recipe_name = recipe
	end
	data.raw["mod-data"]["Planetslib-planet-rocket-part-recipe"].data[planet_name] = recipe_name
	if recipe_name ~= "_other" then
		data.raw["mod-data"]["Planetslib-planet-lock-rocket-silos"].data[planet_name] = lock_silo or true
	end
	
end

local function initialize_planet_cargo_drops_whitelist(planet_name)
	data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists[planet_name] = data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists[planet_name]
		or {
			entity_types = {},
			item_names = {},
		}
end

function Public.add_item_name_to_planet_cargo_drops_whitelist(planet_name, item_name)
	initialize_planet_cargo_drops_whitelist(planet_name)

	data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists[planet_name].item_names[item_name] = true
end

function Public.add_entity_type_to_planet_cargo_drops_whitelist(planet_name, entity_type)
	initialize_planet_cargo_drops_whitelist(planet_name)

	data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists[planet_name].entity_types[entity_type] = true
end

function Public.add_item_name_to_global_cargo_drops_whitelist(item_name)
	data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists.all.item_names[item_name] = true
end

function Public.add_entity_type_to_global_cargo_drops_whitelist(entity_type)
	data.raw["mod-data"].Planetslib.data.planet_cargo_drop_whitelists.all.entity_types[entity_type] = true
end

return Public
