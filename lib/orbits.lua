local Public = {}

function Public.get_planets_with_orbits(planets)
    local planets_with_orbits = {}
    
    for _, planet in pairs(planets) do
        if planet.orbit then
            table.insert(planets_with_orbits, planet)
        end
    end
    
    return planets_with_orbits
end

function Public.get_absolute_polar_position_from_orbit(orbit)
	local parent = orbit.parent

	assert(
		parent.type == "planet" or parent.type == "space-location",
		"Parent types other than planet or space-location are not yet supported"
	)

	if parent.name == "star" then
		return orbit.distance, orbit.orientation
	end

	local parent_data = data.raw[parent.type][parent.name]

	local parent_distance = parent_data.distance
	local parent_orientation = parent_data.orientation

	if parent_data.orbit then -- Overwrite distance and orientation
		parent_distance, parent_orientation = Public.get_absolute_polar_position_from_orbit(parent_data.orbit)
	end

	local parent_angle = parent_orientation * 2 * math.pi
	local orbit_angle = orbit.orientation * 2 * math.pi -- Note that this isn't rotated by the parent's orientation.

	local px = parent_distance * math.cos(parent_angle)
	local py = parent_distance * math.sin(parent_angle)

	local ox = orbit.distance * math.cos(orbit_angle)
	local oy = orbit.distance * math.sin(orbit_angle)

	local x = px + ox
	local y = py + oy

	local distance = math.sqrt(x * x + y * y)
	local orientation = math.atan2(y, x) / (2 * math.pi)

	if orientation < 0 then
		orientation = orientation + 1
	end
	if orientation > 1 then
		orientation = orientation - 1
	end

	return distance, orientation
end

return Public
