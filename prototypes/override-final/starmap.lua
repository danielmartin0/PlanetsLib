local orbits = require("lib.orbits")

local Public = {}
local starmap_layers = {}

function Public.update_starmap_layers(planet)
	local orbit = planet.orbit

	local x = orbit.distance * 32 * math.sin(orbit.orientation * 2 * math.pi)
	local y = -orbit.distance * 32 * math.cos(orbit.orientation * 2 * math.pi)

	local parent = planet.orbit.parent

	assert(
		parent.type == "planet" or parent.type == "space-location",
		"Parent types other than planet or space-location are not yet supported"
	)

	local parent_data = data.raw[parent.type][parent.name]
	local parent_orbit = parent_data.orbit

	assert(parent_orbit, "Parent " .. parent.name .. " has no orbit")

	local parent_distance, parent_orientation = orbits.get_absolute_polar_position_from_orbit(parent_orbit)

	local parent_x = parent_distance * 32 * math.sin(parent_orientation * 2 * math.pi)
	local parent_y = -parent_distance * 32 * math.cos(parent_orientation * 2 * math.pi)

	if orbit.sprite then
		if orbit.sprite.layers then
			for _, layer in pairs(orbit.sprite.layers) do
				Public.update_starmap_from_sprite(layer, parent_x, parent_y)
			end
		else
			Public.update_starmap_from_sprite(orbit.sprite, parent_x, parent_y)
		end
	end

	planet.draw_orbit = false

	if planet.sprite_only then
		table.insert(starmap_layers, {
			filename = planet.starmap_icon,
			size = planet.starmap_icon_size,
			scale = (planet.magnitude * 32) / planet.starmap_icon_size,
			shift = { parent_x + x, parent_y + y },
		})
	end
end

function Public.update_starmap_from_sprite(sprite, x, y)
	local sprite_copy = util.table.deepcopy(sprite)
	sprite_copy.shift = {
		(sprite_copy.shift and sprite_copy.shift[1] or 0) + x,
		(sprite_copy.shift and sprite_copy.shift[2] or 0) + y,
	}
	table.insert(starmap_layers, sprite_copy)
end

local planets = orbits.get_planets_with_orbits(data.raw["planet"])
for _, planet in pairs(planets) do
	Public.update_starmap_layers(planet)
end
local spaceLocs = orbits.get_planets_with_orbits(data.raw["space-location"])
for _, space_location in pairs(spaceLocs) do
	Public.update_starmap_layers(space_location)
end

data.raw["utility-sprites"]["default"].starmap_star = { layers = starmap_layers }

return Public
