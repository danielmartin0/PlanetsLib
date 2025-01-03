local orbits = require("lib.orbits")

local Public = {}

function Public.planet_extend(configs)
	if not configs[1] then
		configs = { configs }
	end

	local planets = {}
	for _, config in ipairs(configs) do
		Public.verify_config_fields(config)

		local distance, orientation = orbits.get_absolute_polar_position_from_orbit(config.orbit)

		local planet = {
			distance = distance,
			orientation = orientation,
		}

		for k, v in pairs(config) do -- This will not include distance, orientation due to validity checks.
			planet[k] = v
		end

		table.insert(planets, planet)
	end

	data:extend(planets)
	return planets
end

local function is_space_location(planet)
	if not planet then
		return false
	end
	return planet.type == "planet" or planet.type == "space-location"
end

function Public.verify_config_fields(config)
	if not is_space_location(config.orbit.parent) then
		error(
			"PlanetsLib:planet_extend() - 'orbit.parent' must be a space location. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if config.distance then
		error(
			"PlanetsLib:planet_extend() - 'distance' should be specified in the 'orbit' field. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if config.orientation then
		error(
			"PlanetsLib:planet_extend() - 'orientation' should be specified in the 'orbit' field. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not config.orbit then
		error(
			"PlanetsLib:planet_extend() - 'orbit' field is required. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not config.orbit.parent then
		error(
			"PlanetsLib:planet_extend() - 'orbit.parent' field is required with an object containing 'type' and 'name' fields. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
end

--- Clones music tracks from source_planet to target_planet.
--- Does not overwrite existing music for target_planet.
function Public.borrow_music(source_planet, target_planet)
	assert(
		is_space_location(source_planet),
		"PlanetsLib.borrow_music() - Invalid parameter 'source_planet'. Field is required to be either `space-location` or `planet` prototype."
	)
	assert(
		is_space_location(target_planet),
		"PlanetsLib.borrow_music() - Invalid parameter 'target_planet'. Field is required to be either `space-location` or `planet` prototype."
	)

	for _, music in pairs(data.raw["ambient-sound"]) do
		if
			music.planet == source_planet.name
			or (music.track_type == "hero-track" and music.name:find(source_planet.name))
		then
			local new_music = util.table.deepcopy(music)
			new_music.name = music.name .. "-" .. target_planet.name
			new_music.planet = target_planet.name
			data:extend({ new_music })
		end
	end
end

function Public.set_default_import_location(item_name, planet)
	for item_prototype in pairs(defines.prototypes.item) do
		local item = (data.raw[item_prototype] or {})[item_name]
		if item then
			item.default_import_location = planet
			return
		end
	end

	error("PlanetsLib.set_default_import_location() - Item not found: " .. item_name, 2)
end

return Public
