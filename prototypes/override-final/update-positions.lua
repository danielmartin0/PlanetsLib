local orbits = require("lib.orbits")

-- If the position/orientation of a location's parent prototype doesn't match its orbit, that implies the position has been moved by another mod. In this code we adjust the position of its children accordingly.

local locations = {}

for _, type in pairs({ "space-location", "planet" }) do
	for _, location in pairs(data.raw[type]) do
		locations[#locations + 1] = location
	end
end

local ordered_locations = orbits.location_ordered_by_orbit(locations)

for _, location in pairs(ordered_locations) do
	if location.orbit and location.orbit.distance and location.orbit.orientation and location.orbit.parent then
		local parent = location.orbit.parent
		local parent_data = data.raw[parent.type][parent.name]

		if
			parent_data
			and parent_data.name ~= "star"
			and parent_data.orbit
			and parent_data.orbit.distance
			and parent_data.orbit.orientation
		then
			local old_parent_distance, old_parent_orientation =
				orbits.get_absolute_polar_position_from_orbit(parent_data.orbit)

			local new_parent_distance = parent_data.distance
			local new_parent_orientation = parent_data.orientation

			if new_parent_distance ~= old_parent_distance or new_parent_orientation ~= old_parent_orientation then
				local old_location_x, old_location_y =
					orbits.get_rectangular_position(location.distance, location.orientation)

				local old_parent_x, old_parent_y =
					orbits.get_rectangular_position(old_parent_distance, old_parent_orientation)

				local new_parent_x, new_parent_y =
					orbits.get_rectangular_position(new_parent_distance, new_parent_orientation)

				local delta_x, delta_y =
					orbits.get_rectangular_position(location.orbit.distance, location.orbit.orientation)

				local new_position_x, new_position_y = new_parent_x + delta_x, new_parent_y + delta_y

				local new_distance = math.sqrt(new_position_x * new_position_x + new_position_y * new_position_y)
				local new_orientation = (0.25 + math.atan2(new_position_y, new_position_x) / (2 * math.pi)) % 1

				new_orientation = new_orientation % 1

				log(
					"PlanetsLib: "
						.. location.name
						.. "'s parent '"
						.. parent.name
						.. "' has moved from "
						.. old_parent_x
						.. ", "
						.. old_parent_y
						.. " to "
						.. new_parent_x
						.. ", "
						.. new_parent_y
						.. ". Moving '"
						.. location.name
						.. "' from "
						.. old_location_x
						.. ", "
						.. old_location_y
						.. " to "
						.. new_position_x
						.. ", "
						.. new_position_y
				)

				location.distance = new_distance
				location.orientation = new_orientation
			end
		end
	end
end
