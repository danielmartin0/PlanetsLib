local orbits = require("lib.orbits")

local Public = {}
local starmap_layers = {}

-- Orbits help us construct the system. In data-final-fixes, it's now better to rely on the game variables (distance and orientation) for the position of each space location, for compatibility with other mods.

function Public.update_starmap_layers(planet)
	if planet.sprite_only and (planet.starmap_icon or planet.starmap_icons) then
		local magnitude = planet.magnitude or 1

		local x, y = orbits.get_rectangular_position(planet.distance * 32, planet.orientation)

		if planet.starmap_icons then
			for _, sprite in pairs(planet.starmap_icons) do
				local scaled_sprite = util.table.deepcopy(sprite)
				scaled_sprite.scale = scaled_sprite.scale * (magnitude * 32)

				Public.add_sprite_to_starmap(sprite, { x = x, y = y })
			end
		elseif planet.starmap_icon then
			local icon_size = planet.starmap_icon_size or 64

			Public.add_sprite_to_starmap({
				filename = planet.starmap_icon,
				size = icon_size,
				scale = (magnitude * 32) / icon_size,
			}, { x = x, y = y })
		end
	end

	if planet.orbit and planet.orbit.sprite then
		Public.draw_orbit_of_planet(planet)

		return { should_disable_default_orbit_sprite = true }
	end

	return { should_disable_default_orbit_sprite = false }
end

function Public.draw_orbit_of_planet(planet)
	local orbit = planet.orbit
	local parent = orbit.parent

	assert(
		parent.type == "planet" or parent.type == "space-location",
		"Parent types other than planet or space-location are not yet supported"
	)

	local distance_from_orbit = orbits.get_absolute_polar_position_from_orbit(orbit)

	if distance_from_orbit ~= planet.distance then
		-- Another mod has intercepted, so let's not risk drawing any orbit sprite.

		return { should_disable_default_orbit_sprite = true }
	end

	local parent_data = data.raw[parent.type][parent.name]

	local parent_x, parent_y = orbits.get_rectangular_position(parent_data.distance * 32, parent_data.orientation)

	if orbit.sprite.layers then
		for _, layer in pairs(orbit.sprite.layers) do
			Public.add_sprite_to_starmap(layer, { x = parent_x, y = parent_y })
		end
	else
		Public.add_sprite_to_starmap(orbit.sprite, { x = parent_x, y = parent_y })
	end
end

function Public.add_sprite_to_starmap(sprite, extra_displacement)
	local sprite_copy = util.table.deepcopy(sprite)

	local shift_x = 0
	local shift_y = 0

	if sprite_copy.shift then
		if sprite_copy.shift.x then
			shift_x = shift_x + sprite_copy.shift.x
			shift_y = shift_y + sprite_copy.shift.y
		else
			shift_x = shift_x + sprite_copy.shift[1]
			shift_y = shift_y + sprite_copy.shift[2]
		end
	end

	if extra_displacement then
		if extra_displacement.x and extra_displacement.y then
			shift_x = shift_x + extra_displacement.x
			shift_y = shift_y + extra_displacement.y
		else
			shift_x = shift_x + extra_displacement[1]
			shift_y = shift_y + extra_displacement[2]
		end
	end

	sprite_copy.shift = {
		shift_x,
		shift_y,
	}

	table.insert(starmap_layers, sprite_copy)
end

-- Now begins the algorithm:

local locations = {}

for _, type in pairs({ "space-location", "planet" }) do
	for _, location in pairs(data.raw[type]) do
		locations[#locations + 1] = location
	end
end

local ordered_locations = {}

local visited = {}
local temporary_marks = {}

local function visit(location, ordered)
	if temporary_marks[location.name] then
		if not (location.orbit and location.orbit.parent and location.orbit.parent.name == location.name) then -- Self-parents are acceptable. Presumably this is only the case for data.raw["space-location"]["star"].
			error("Circular orbit dependency detected at " .. location.name)
		end
	end
	if not visited[location.name] then
		temporary_marks[location.name] = true

		if location.orbit and location.orbit.parent then
			local parent_type = location.orbit.parent.type
			local parent_name = location.orbit.parent.name

			if parent_name ~= location.name then
				local parent = data.raw[parent_type][parent_name]
				if parent then
					visit(parent, ordered)
				end
			end
		end

		temporary_marks[location.name] = false
		visited[location.name] = true
		table.insert(ordered, location)
	end
end

for _, location in pairs(locations) do
	if not visited[location.name] then
		visit(location, ordered_locations)
	end
end

for _, location in pairs(ordered_locations) do
	local result = Public.update_starmap_layers(location)
	if result.should_disable_default_orbit_sprite then
		location.draw_orbit = false
	end
end

if #starmap_layers > 0 then
	data.raw["utility-sprites"]["default"].starmap_star = { layers = starmap_layers }
end

return Public
