local orbits = require("lib.orbits")

local Public = {}

function Public.extend(config)
	Public.default_extend_fields(config)
	Public.verify_extend_fields(config)

	local planet = {}

	

	local distance, orientation = orbits.get_absolute_polar_position_from_orbit(config.orbit)

	planet.distance = distance
	planet.orientation = orientation

	for k, v in pairs(config) do -- This will not include distance, orientation due to validity checks.
		planet[k] = v
	end

	

	if planet.orbit.parent then --Adds encoded parent body to surface properties.
		if planet.orbit.parent.type == "planet" then
			if data.raw["planet"][config.orbit.parent.name] then
				planet["surface_properties"] = planet["surface_properties"] or {}
				planet["surface_properties"]["parent-planet-str"] =
					data.raw["planet"][config.orbit.parent.name]["surface_properties"]["planet-str"]
			end
		end
	end

	data:extend({ planet })
end

function Public.is_space_location(planet)
	if not planet then
		return false
	end
	return planet.type == "planet" or planet.type == "space-location"
end

function Public.default_extend_fields(config) --Adds default values when values are empty. This step does not seek to assert anything.
--Allows planet objects with orbits formatted according to vanilla structure to be passed to PlanetsLib without any modifications.
--Will not prevent planets with distance/orientation both defined in root and orbit from crashing.
	if (config.orbit == nil) then
		config.orbit = {}
	end
	if config.orbit then
		if config.orbit.distance == nil and config.distance then
			config.orbit.distance = config.distance
			config.distance = nil
		end
		if config.orbit.orientation == nil and config.orientation then
			config.orbit.orientation = config.orientation
			config.orientation = nil
		end
		if config.orbit.parent == nil then --Default planet orbit parent mirroring vanilla planets. Before this was added, the library would crash when parent was nil.
			config.orbit.parent = {
				type = "space-location",
				name ="star",
			}
		end
	end
	
end

-- TODO: Add checks to ensure the structure of orbit is correct.
function Public.verify_extend_fields(config)
	if not Public.is_space_location(config) then
		error(
			"Error with space-location \""..config.name.."\": PlanetsLib:extend() - extend only takes a planet or space-location prototype. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not config.orbit then
		error(
			"Error with space-location \""..config.name.."\": PlanetsLib:extend() - 'orbit' field is required. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not Public.is_space_location(config.orbit.parent) then
		error(
			"Error with space-location \""..config.name.."\": PlanetsLib:extend() - 'orbit.parent' must be a space location. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if config.distance or not config.orbit.distance then
		error(
			"Error with space-location \""..config.name.."\": PlanetsLib:extend() - 'distance' should be specified in the 'orbit' field. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if config.orientation or not config.orbit.distance then
		error(
			"Error with space-location \""..config.name.."\": PlanetsLib:extend() - 'orientation' should be specified in the 'orbit' field. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not config.orbit.parent then
		error(
			"Error with space-location \""..config.name.."\": PlanetsLib:extend() - 'orbit.parent' field is required with an object containing 'type' and 'name' fields. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
end

function Public.update(config)
	Public.verify_update_fields(config)

	for k, v in pairs(config) do
		data.raw[config.type][config.name][k] = v

		if k == "orbit" then
			local distance, orientation = orbits.get_absolute_polar_position_from_orbit(v)

			data.raw[config.type][config.name].distance = distance
			data.raw[config.type][config.name].orientation = orientation
		end
	end
end

-- TODO: Add checks to ensure the structure of orbit is correct.
function Public.verify_update_fields(config)
	if not config.name then
		error(
			"PlanetsLib:update() - 'name' field is required. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if (not config.type) or (not Public.is_space_location(config)) then
		error(
			"PlanetsLib:update() - type='planet' or type='space-location' is required. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if config.orbit and not Public.is_space_location(config.orbit.parent) then
		error(
			"PlanetsLib:update() - 'orbit.parent' must be a space location. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if config.distance then
		error(
			"PlanetsLib:update() - update 'orbit' instead of 'distance'. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if config.orientation then
		error(
			"PlanetsLib:update() - update 'orbit' instead of 'orientation'. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if not data.raw[config.type][config.name] then
		error("PlanetsLib:update() - " .. config.type .. " not found: " .. config.name)
	end
end

--- Clones music tracks from source_planet to target_planet.
--- Does not overwrite existing music for target_planet.
function Public.borrow_music(source_planet, target_planet)
	assert(
		Public.is_space_location(source_planet),
		"PlanetsLib.borrow_music() - Invalid parameter 'source_planet'. Field is required to be either `space-location` or `planet` prototype."
	)
	assert(
		Public.is_space_location(target_planet),
		"PlanetsLib.borrow_music() - Invalid parameter 'target_planet'. Field is required to be either `space-location` or `planet` prototype."
	)

	for _, music in pairs(util.table.deepcopy(data.raw["ambient-sound"])) do
		if music.planet == source_planet.name then
			music.name = music.name .. "-" .. target_planet.name
			music.planet = target_planet.name
			data:extend({ music })
		end
	end
end

--- This function sets `default_import_location` based on an item name and planet.
--- `default_import_location` is used by the space platform GUI to
--- define the default planet where an item will be imported from.
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
