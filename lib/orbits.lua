local Public = {}

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

	assert(parent_data, string.format("%s with name '%s' not found", parent.type, parent.name))

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

function Public.get_rectangular_position(distance, orientation)
	if distance == 0 then
		return 0, 0
	else
		return distance * math.sin(orientation * 2 * math.pi), -distance * math.cos(orientation * 2 * math.pi)
	end
end

function Public.location_ordered_by_orbit(locations)
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

	return ordered_locations
end

return Public
