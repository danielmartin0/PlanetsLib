local util = require("util")
local orbits = require("lib.orbits")
local lib = require("lib/lib")

local Public = {}

function Public.extend(config)
	Public.verify_extend_fields(config)

	local planet = {}

	local distance, orientation = orbits.get_absolute_polar_position_from_orbit(config.orbit, true)

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

	if planet.special_properties then
		error("special_properties is an invalid field.")
		-- local special_properties = planet.special_properties
		-- PlanetsLib.constants.planet_properties[planet.name] = special_properties
		-- planet.special_properties = nil
	end

	data:extend({ planet })
end

function Public.is_space_location(planet)
	if not planet then
		return false
	end
	return planet.type == "planet" or planet.type == "space-location"
end

function Public.is_space_location_or_space_platform(planet)
	if not planet then
		return false
	end
	return planet == "space-platform" or planet.type == "planet" or planet.type == "space-location"
end
-- TODO: Add checks to ensure the structure of orbit is correct.
function Public.verify_extend_fields(config)
	if PlanetsLib.current_stage == "data-final-fixes" then
        error("PlanetsLib:extend() - This function can only be run before data-final-fixes. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib.")
	end
	if not Public.is_space_location(config) then
		error(
			"PlanetsLib:extend() - extend only takes a planet or space-location prototype. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not config.orbit then
		error(
			"PlanetsLib:extend() - 'orbit' field is required. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not Public.is_space_location(config.orbit.parent) then
		error(
			"PlanetsLib:extend() - 'orbit.parent' must be a space location. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end

	if config.distance then
		error(
			"PlanetsLib:extend() - 'distance' should be specified in the 'orbit' field. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if config.orientation then
		error(
			"PlanetsLib:extend() - 'orientation' should be specified in the 'orbit' field. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if not config.orbit.parent then
		error(
			"PlanetsLib:extend() - 'orbit.parent' field is required with an object containing 'type' and 'name' fields. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
end

function Public.update(config)
	if PlanetsLib.current_stage == "data-final-fixes" then
		error("This function can only be run before data-final-fixes.")
	end
	Public.verify_update_fields(config)

	orbits.ensure_all_locations_have_orbits()

	for k, v in pairs(config) do
		if k == "orbit" then
			lib.detailed_log("--------------------------------")
			lib.detailed_log(
				"PlanetsLib:update called on "
				.. config.name
				.. ", changing orbit from "
				.. serpent.line(data.raw[config.type][config.name].orbit)
				.. " to "
				.. serpent.line(config.orbit)
				.. " and updating the positions of children appropriately:"
			)

			data.raw[config.type][config.name].orbit = v

			local current_x, current_y = orbits.get_rectangular_position_from_polar(
				data.raw[config.type][config.name].distance,
				data.raw[config.type][config.name].orientation
			)

			local parent_prototype = data.raw[v.parent.type][v.parent.name]

			if not parent_prototype then
				error("PlanetsLib.update: update called with invalid parent: " .. v.parent.name)
			end

			local parent_x, parent_y =
				orbits.get_rectangular_position_from_polar(parent_prototype.distance, parent_prototype.orientation)

			local orbit_x, orbit_y = orbits.get_rectangular_position_from_polar(v.distance, v.orientation)

			local new_x, new_y = parent_x + orbit_x, parent_y + orbit_y

			lib.detailed_log(
				"PlanetsLib: updating "
				.. config.name
				.. " from x="
				.. current_x
				.. ", y="
				.. current_y
				.. " to x="
				.. new_x
				.. ", y="
				.. new_y
			)

			local new_distance, new_orientation = orbits.get_polar_position_from_rectangular(new_x, new_y)

			data.raw[config.type][config.name].distance = new_distance
			data.raw[config.type][config.name].orientation = new_orientation

			orbits.update_positions_of_all_children_via_orbits(data.raw[config.type][config.name])

			lib.detailed_log("--------------------------------")
		elseif k == "special_properties" then
			error("PlanetsLib:update() - special_properties is an invalid field.")
			-- if not PlanetsLib.constants.planet_properties[config.name] then
			-- 		PlanetsLib.constants.planet_properties[config.name] = {}
			-- end
			-- for field,value in pairs(v) do

			-- 	PlanetsLib.constants.planet_properties[config.name][field] = value
			-- end
		else
			data.raw[config.type][config.name][k] = v
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
--- Options specified in `options`:
--- track_types(table): Allows the selection of only tracks matching one or more track types.
--- modifier_function(function): Function applied to each borrowed track: Expected form: modifier_function = function(track) {Apply changes to track table here} end
-- @param source_planet
-- @param target_planet
-- @param options table Table of options (track_types)
function Public.borrow_music(source_planet, target_planet, options)
	assert(
		Public.is_space_location_or_space_platform(source_planet),
		"PlanetsLib.borrow_music() - Invalid parameter 'source_planet'. Field is required to be either `space-platform` or a `space-location` or `planet` prototype."
	)
	assert(
		Public.is_space_location_or_space_platform(target_planet),
		"PlanetsLib.borrow_music() - Invalid parameter 'target_planet'. Field is required to be either `space-platform` or a `space-location` or `planet` prototype."
	)

	if not options then
		options = {}
	end

	if options.modifier_function then
		assert(
			debug.getinfo(options.modifier_function, "u").nparams == 1,
			"options.modifier_function can only have one parameter."
		)
	end

	local source_name = source_planet.name or source_planet

	local target_name = target_planet.name
	if source_name == "space-platform" then
		source_name = nil
	end

	if target_name == "space-platform" then
		target_name = nil
	end

	for _, music in pairs(util.table.deepcopy(data.raw["ambient-sound"])) do
		if
			PlanetsLib.rro.contains(music.planets,source_name)
			and (options.track_types == nil or PlanetsLib.rro.contains(options.track_types, music.track_type))
		then if not options.modifier_function then
			table.insert(music.planets,target_name) --New in Factorio 2.1: Ambient sounds can be played for multiple planets, making borrow_music()'s old approach of copying tracks mostly obsolete. We will avoid making new tracks unless a modifier function is provided.

			else
				music.name = music.name .. "-" .. target_name
				music.planet = target_name

				options.modifier_function(music) -- options.modifier gives the opportunity to apply changes to the track's parameters through a function.

				data:extend({ music })
		end end
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

--- PlanetsLib.set_special_properties(planet,properties)
--- Assigns special properties to a planet stored in a mod-data object.
--- Special properties are displayed as surface properties, but they are not intended to be used as surface properties.
--- Like vanilla's robot-energy-multiplier, these special properties influence the behavior of entities, either through data-final-fixes or through a runtime script.
--- Can be retrieved with PlanetsLib.get_special_property(planet,(string) property?)
--- Can not be called during data-final-fixes, to allow variables defined as special properties to be used by PlanetsLib for particular functions
--- List of special properties that PlanetsLib will use in the future::
--- rocket_part_multiplier: Multiplies the parts required by rocket silos by this value via entity replacements.
--- rocket_lift_multiplier: Multiplies the lift of rockets launched from rocket silos by this value via entity replacements.
function Public.set_special_properties(planet,properties)
	assert(PlanetsLib.current_stage ~= "data-final-fixes", "PlanetsLib.set_special_properties(planet,properties) - This function must be called before data-final-fixes.")
	local planet_name = type(planet) == "table" and planet.name or planet
	if not PlanetsLib.constants.planet_special_properties[planet_name] then
		PlanetsLib.constants.planet_special_properties[planet_name] = table.deepcopy(properties)
	else
		PlanetsLib.rro.merge(PlanetsLib.constants.planet_special_properties[planet_name],table.deepcopy(properties))
	end
	return PlanetsLib.constants.planet_special_properties[planet_name]
end

--- PlanetsLib.get_special_property(planet,property)
function Public.get_special_property(planet,property)
	local planet_name = type(planet) == "table" and planet.name or planet
	if property == nil then
		return PlanetsLib.constants.planet_special_properties[planet_name]
	end
	local planet_name = type(planet) == "table" and planet.name or planet
	if not PlanetsLib.constants.planet_special_properties[planet_name] then
		PlanetsLib.constants.planet_special_properties[planet_name] = table.deepcopy(properties)
	else
		PlanetsLib.rro.merge(PlanetsLib.constants.planet_special_properties[planet_name],table.deepcopy(properties))
	end
	return PlanetsLib.constants.planet_special_properties[planet_name]
end

--- PlanetsLib.get_special_properties(planet)
function Public.get_special_properties(planet)
	local planet_name = type(planet) == "table" and planet.name or planet
	return PlanetsLib.constants.planet_special_properties[planet_name]
end

local sprites = {
	[1.39] = {
			type = "sprite",
			filename = "__PlanetsLib__/graphics/orbits/moons/orbit-1.39.png",
			size = 379,
			scale = 0.25,
		},
	[1.5] =  {
			type = "sprite",
			filename = "__PlanetsLib__/graphics/orbits/moons/orbit-1.5.png",
			size = 412,
          	scale = 0.25
		},
	[1.8] = {
			type = "sprite",
			filename = "__PlanetsLib__/graphics/orbits/moons/orbit-1.8.png",
			size = 470,
			scale = 0.25,
		},
	[2.65] = {
			type = "sprite",
			filename = "__PlanetsLib__/graphics/orbits/moons/orbit-2.65.png",
			size = 685,
			scale = 0.25
		},
	[3.95] = {
			type = "sprite",
			filename = "__PlanetsLib__/graphics/orbits/moons/orbit-3.95.png",
			size = 1025,
			scale = 0.25
		}
}

Public.get_orbit_sprite = function(radius)
	local orbit_data = sprites[radius]
	if not orbit_data then
		local keys = {}
		for k in pairs(sprites) do
		keys[#keys+1] = tostring(k)
		end

		table.sort(keys)
		local available_orbits = table.concat(keys, ", ")

		error("No planetslib orbit asset is registered for radius "..tostring(radius)". Available radiuses are: "..available_orbits)
	end
	return table.deepcopy(orbit_data)
end


return Public
