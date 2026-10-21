local Public = {}

local DOCS = "See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."

local SIZES = { "chunk", "small", "medium", "big", "huge" }
local SIZE_LOOKUP = {}
for _, size in ipairs(SIZES) do
	SIZE_LOOKUP[size] = true
end

local DEFAULT_ANGLES = {
	chunk = 1,
	small = 0.7,
	medium = 0.6,
	big = 0.5,
	huge = 0.4,
}

-- 1 * meter / second. Prototype speeds are in tiles per tick, and the data
-- stage defines meter = 1 and second = 60. Keeping the number here means the
-- module can also be required from runtime tests.
local DEFAULT_SPEED = 1 / 60

local function fail(message)
	error("PlanetsLib.asteroid_route() - " .. message .. " " .. DOCS)
end

local function fail_setter(message)
	error("PlanetsLib.set_asteroid_spawn_definitions() - " .. message .. " " .. DOCS)
end

local function is_finite_number(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sorted_keys(map)
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		if type(a) == "number" and type(b) == "number" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function default_asteroid_name(family, size)
	if size == "chunk" then
		return family .. "-asteroid-chunk"
	end
	return size .. "-" .. family .. "-asteroid"
end

local function validate_size(size, context)
	if not SIZE_LOOKUP[size] then
		fail(
			string.format(
				'%s uses unknown asteroid size "%s". Valid sizes are chunk, small, medium, big and huge.',
				context,
				tostring(size)
			)
		)
	end
end

local function validate_probability(value, context)
	if not is_finite_number(value) or value < 0 or value > 1 then
		fail(string.format("%s must be a number between 0 and 1, got %s.", context, tostring(value)))
	end
end

local function validate_weight(value, context)
	if not is_finite_number(value) or value < 0 then
		fail(string.format("%s must be a non-negative number, got %s.", context, tostring(value)))
	end
end

local function validate_angle(value, context)
	if not is_finite_number(value) or value < 0 then
		fail(string.format("%s must be a non-negative number, got %s.", context, tostring(value)))
	end
end

local function parse_spawn_value(value, size, frame_index)
	if is_finite_number(value) then
		validate_probability(value, string.format("frame %d spawn.%s", frame_index, size))
		return { probability = value }
	end

	if type(value) ~= "table" then
		fail(string.format("frame %d spawn.%s must be a probability or a table.", frame_index, size))
	end

	for key in pairs(value) do
		if key ~= "probability" and key ~= "angle_when_stopped" then
			fail(string.format("frame %d spawn.%s has unknown field \"%s\".", frame_index, size, tostring(key)))
		end
	end

	local probability = value.probability
	validate_probability(probability, string.format("frame %d spawn.%s.probability", frame_index, size))

	local point = { probability = probability }
	if value.angle_when_stopped ~= nil then
		validate_angle(value.angle_when_stopped, string.format("frame %d spawn.%s.angle_when_stopped", frame_index, size))
		point.angle_when_stopped = value.angle_when_stopped
	end
	return point
end

local function evaluate_ratio_curve(points, family, position)
	if position <= points[1].position then
		return points[1].ratios[family]
	end
	if position >= points[#points].position then
		return points[#points].ratios[family]
	end

	for i = 1, #points - 1 do
		local lower = points[i]
		local upper = points[i + 1]
		if position >= lower.position and position <= upper.position then
			local range = upper.position - lower.position
			if range == 0 then
				return lower.ratios[family]
			end
			local t = (position - lower.position) / range
			return lower.ratios[family] + (upper.ratios[family] - lower.ratios[family]) * t
		end
	end

	return points[#points].ratios[family]
end

local function evaluate_spawn_curve(points, position)
	if position <= points[1].position then
		return points[1].probability, points[1].angle
	end
	if position >= points[#points].position then
		return points[#points].probability, points[#points].angle
	end

	for i = 1, #points - 1 do
		local lower = points[i]
		local upper = points[i + 1]
		if position >= lower.position and position <= upper.position then
			local range = upper.position - lower.position
			if range == 0 then
				return lower.probability, lower.angle
			end
			local t = (position - lower.position) / range
			return lower.probability + (upper.probability - lower.probability) * t,
				lower.angle + (upper.angle - lower.angle) * t
		end
	end

	return points[#points].probability, points[#points].angle
end

local function ratios_at(route, position)
	local result = {}
	for _, family in ipairs(route.families) do
		result[family] = evaluate_ratio_curve(route.ratio_curves[family], family, position)
	end
	return result
end

local function spawn_positions(route, size)
	local positions = {}
	for position in pairs(route.ratio_positions) do
		positions[position] = true
	end
	for _, point in ipairs(route.spawn_curves[size]) do
		positions[point.position] = true
	end
	return sorted_keys(positions)
end

local function planet_definition(name, size, probability, speed, angle)
	local definition = {
		asteroid = name,
		probability = probability,
		speed = speed,
		angle_when_stopped = angle,
	}
	if size == "chunk" then
		definition.type = "asteroid-chunk"
	end
	return definition
end

local function connection_definition(name, size)
	local definition = { asteroid = name }
	if size == "chunk" then
		definition.type = "asteroid-chunk"
	end
	return definition
end

local function build_connection(route)
	local definitions = {}

	for _, size in ipairs(SIZES) do
		local curve = route.spawn_curves[size]
		if curve then
			local positions = spawn_positions(route, size)
			local ratio_map = {}
			for _, position in ipairs(positions) do
				ratio_map[position] = ratios_at(route, position)
			end

			for _, family in ipairs(route.families) do
				local name = route.names[family] and route.names[family][size]
				if name then
					local spawn_points = {}
					local has_nonzero_probability = false
					for _, position in ipairs(positions) do
						local probability, angle = evaluate_spawn_curve(curve, position)
						local final_probability = probability * ratio_map[position][family]
						if final_probability > 0 then
							has_nonzero_probability = true
						end
						spawn_points[#spawn_points + 1] = {
							distance = position,
							probability = final_probability,
							speed = route.speed,
							angle_when_stopped = angle,
						}
					end

					if has_nonzero_probability then
						local definition = connection_definition(name, size)
						definition.spawn_points = spawn_points
						definitions[#definitions + 1] = definition
					end
				end
			end
		end
	end

	return definitions
end

local function build_planet(route, position)
	local definitions = {}
	local ratios = ratios_at(route, position)

	for _, size in ipairs(SIZES) do
		local curve = route.spawn_curves[size]
		if curve then
			local probability, angle = evaluate_spawn_curve(curve, position)
			for _, family in ipairs(route.families) do
				local name = route.names[family] and route.names[family][size]
				if name then
					local final_probability = probability * ratios[family]
					if final_probability > 0 then
						definitions[#definitions + 1] =
							planet_definition(name, size, final_probability, route.speed, angle)
					end
				end
			end
		end
	end

	return definitions
end

local Route = {}
Route.__index = Route

function Route:connection()
	return build_connection(self)
end

function Route:planet(position)
	position = position == nil and 0.9 or position
	if not is_finite_number(position) or position < 0 or position > 1 then
		fail("planet position must be a number between 0 and 1, got " .. tostring(position) .. ".")
	end
	return build_planet(self, position)
end

local function is_route(value)
	return type(value) == "table" and getmetatable(value) == Route
end

local function is_vanilla_table(spec)
	if type(spec) ~= "table" then
		return false
	end
	if spec.type_ratios ~= nil then
		return true
	end
	for key in pairs(spec) do
		if type(key) == "string" and key:match("^probability_on_range_") then
			return true
		end
	end
	return false
end

local function validate_options(options)
	if options == nil then
		return {}
	end
	if type(options) ~= "table" then
		fail("options must be a table.")
	end
	for key in pairs(options) do
		if key ~= "families" and key ~= "names" and key ~= "speed" and key ~= "angles" then
			fail('unknown option "' .. tostring(key) .. '".')
		end
	end
	return options
end

local function convert_vanilla_table(spec, options)
	options = validate_options(options)

	local families = options.families
	if families == nil then
		families = { "metallic", "carbonic", "oxide" }
		if spec.has_promethium_asteroids == true then
			families[#families + 1] = "promethium"
		end
	end
	if type(families) ~= "table" or #families == 0 then
		fail("the families option must be a non-empty array of asteroid family names.")
	end
	local family_lookup = {}
	for i, family in ipairs(families) do
		if type(family) ~= "string" or family == "" then
			fail(string.format("families[%d] must be a non-empty string.", i))
		end
		if family_lookup[family] then
			fail(string.format('families[%d] duplicates asteroid family "%s".', i, family))
		end
		family_lookup[family] = true
	end

	local frames_by_position = {}
	local function frame_at(position, context)
		if not is_finite_number(position) or position < 0 or position > 1 then
			fail(context .. " position must be a number between 0 and 1, got " .. tostring(position) .. ".")
		end
		local frame = frames_by_position[position]
		if not frame then
			frame = { position = position, ratios = nil, spawn = {} }
			frames_by_position[position] = frame
		end
		return frame
	end

	local ratio_points = spec.type_ratios
	if type(ratio_points) ~= "table" or #ratio_points == 0 then
		fail("a Space Age style route needs a non-empty type_ratios array.")
	end

	for index, point in ipairs(ratio_points) do
		if type(point) ~= "table" then
			fail(string.format("type_ratios[%d] must be a table.", index))
		end
		local frame = frame_at(point.position, string.format("type_ratios[%d]", index))
		if frame.ratios ~= nil then
			fail(string.format("type_ratios has more than one point at position %s.", tostring(point.position)))
		end
		if type(point.ratios) ~= "table" then
			fail(string.format("type_ratios[%d].ratios must be an array.", index))
		end

		local ratios = {}
		for i, family in ipairs(families) do
			local weight = point.ratios[i]
			if weight == nil then
				weight = 0
			end
			validate_weight(weight, string.format("type_ratios[%d].ratios[%d] (%s)", index, i, family))
			ratios[family] = weight
		end
		for i = #families + 1, #point.ratios do
			if point.ratios[i] ~= 0 then
				fail(
					string.format(
						"type_ratios[%d] has a non-zero ratio at index %d, but only %d families were supplied. Pass the families option to map custom asteroid types.",
						index,
						i,
						#families
					)
				)
			end
		end
		frame.ratios = ratios
	end

	for _, size in ipairs(SIZES) do
		local points = spec["probability_on_range_" .. size]
		if points ~= nil then
			if type(points) ~= "table" then
				fail("probability_on_range_" .. size .. " must be an array.")
			end
			for index, point in ipairs(points) do
				if type(point) ~= "table" then
					fail(string.format("probability_on_range_%s[%d] must be a table.", size, index))
				end
				local frame = frame_at(point.position, string.format("probability_on_range_%s[%d]", size, index))
				validate_probability(point.probability, string.format("probability_on_range_%s[%d].probability", size, index))
				if frame.spawn[size] ~= nil then
					fail(
						string.format(
							"probability_on_range_%s has more than one point at position %s.",
							size,
							tostring(point.position)
						)
					)
				end
				frame.spawn[size] = {
					probability = point.probability,
					angle_when_stopped = point.angle_when_stopped,
				}
			end
		end
	end

	local frames = {}
	for _, position in ipairs(sorted_keys(frames_by_position)) do
		local frame = frames_by_position[position]
		if next(frame.spawn) == nil then
			frame.spawn = nil
		end
		frames[#frames + 1] = frame
	end

	local converted = {
		names = options.names,
		speed = options.speed,
		angles = options.angles,
	}
	for i, frame in ipairs(frames) do
		converted[i] = frame
	end
	return converted
end

local function build_names(spec, families)
	local names = {}
	local generated_names = {}

	for _, family in ipairs(families) do
		local explicit = spec.names and spec.names[family]
		local family_names = {}
		if explicit ~= nil then
			if type(explicit) ~= "table" then
				fail('names["' .. family .. '"] must be a table of size = prototype name.')
			end
			for size, name in pairs(explicit) do
				validate_size(size, 'names["' .. family .. '"]')
				if type(name) ~= "string" or name == "" then
					fail(
						string.format('names["%s"].%s must be a non-empty prototype name string.', family, size)
					)
				end
				if generated_names[name] then
					fail(string.format('prototype name "%s" is generated more than once.', name))
				end
				generated_names[name] = true
				family_names[size] = name
			end
		else
			for _, size in ipairs(SIZES) do
				local name = default_asteroid_name(family, size)
				if generated_names[name] then
					fail(string.format('prototype name "%s" is generated more than once.', name))
				end
				generated_names[name] = true
				family_names[size] = name
			end
		end
		names[family] = family_names
	end

	if spec.names ~= nil then
		for family in pairs(spec.names) do
			if not names[family] then
				fail('names contains family "' .. tostring(family) .. '", but no ratio frame defines it.')
			end
		end
	end

	return names
end

local function build_route(spec)
	if type(spec) ~= "table" then
		fail("route specification must be a table.")
	end

	local frames = {}
	local angles = {}
	for _, size in ipairs(SIZES) do
		angles[size] = DEFAULT_ANGLES[size]
	end

	local speed = DEFAULT_SPEED
	for key, value in pairs(spec) do
		if type(key) == "number" then
			if key ~= math.floor(key) then
				fail("frame keys must be integers, got " .. tostring(key) .. ".")
			end
			if type(value) ~= "table" then
				fail("frame " .. tostring(key) .. " must be a table.")
			end
			frames[#frames + 1] = { index = key, frame = value }
		elseif key == "names" then
			if type(value) ~= "table" then
				fail("names must be a table.")
			end
		elseif key == "angles" then
			if type(value) ~= "table" then
				fail("angles must be a table.")
			end
			for size, angle in pairs(value) do
				validate_size(size, "angles")
				validate_angle(angle, "angles." .. size)
				angles[size] = angle
			end
		elseif key == "speed" then
			if not is_finite_number(value) or value <= 0 then
				fail("speed must be a positive number, got " .. tostring(value) .. ".")
			end
			speed = value
		else
			fail('unknown field "' .. tostring(key) .. '".')
		end
	end

	if #frames == 0 then
		fail("at least one frame is required.")
	end

	table.sort(frames, function(a, b)
		local position_a = a.frame.position
		local position_b = b.frame.position
		if type(position_a) ~= "number" then
			position_a = math.huge
		end
		if type(position_b) ~= "number" then
			position_b = math.huge
		end
		if position_a == position_b then
			return a.index < b.index
		end
		return position_a < position_b
	end)

	local parsed_frames = {}
	local families
	local family_lookup = {}
	local ratio_positions = {}

	for frame_index, wrapper in ipairs(frames) do
		local frame = wrapper.frame
		local position = frame.position
		if not is_finite_number(position) or position < 0 or position > 1 then
			fail(string.format("frame %d position must be a number between 0 and 1, got %s.", frame_index, tostring(position)))
		end
		if parsed_frames[#parsed_frames] and parsed_frames[#parsed_frames].position == position then
			fail(string.format("frame %d has duplicate position %s.", frame_index, tostring(position)))
		end
		for key in pairs(frame) do
			if key ~= "position" and key ~= "ratios" and key ~= "spawn" then
				fail(string.format("frame %d has unknown field \"%s\".", frame_index, tostring(key)))
			end
		end

		local parsed = { position = position }

		if frame.ratios ~= nil then
			if type(frame.ratios) ~= "table" then
				fail(string.format("frame %d ratios must be a table.", frame_index))
			end
			local ratios = {}
			local frame_families = {}
			for family, weight in pairs(frame.ratios) do
				if type(family) ~= "string" or family == "" then
					fail(string.format("frame %d ratio family names must be non-empty strings.", frame_index))
				end
				validate_weight(weight, string.format('frame %d ratios["%s"]', frame_index, family))
				ratios[family] = weight
				frame_families[#frame_families + 1] = family
			end
			if #frame_families == 0 then
				fail(string.format("frame %d ratios must not be empty.", frame_index))
			end
			table.sort(frame_families)

			if families == nil then
				families = frame_families
				for _, family in ipairs(families) do
					family_lookup[family] = true
				end
			else
				for _, family in ipairs(families) do
					if ratios[family] == nil then
						fail(string.format('frame %d is missing ratio family "%s".', frame_index, family))
					end
				end
				for _, family in ipairs(frame_families) do
					if not family_lookup[family] then
						fail(string.format('frame %d has unknown ratio family "%s".', frame_index, family))
					end
				end
			end

			parsed.ratios = ratios
			ratio_positions[position] = true
		end

		if frame.spawn ~= nil then
			if type(frame.spawn) ~= "table" then
				fail(string.format("frame %d spawn must be a table.", frame_index))
			end
			local spawn = {}
			for size, value in pairs(frame.spawn) do
				validate_size(size, string.format("frame %d spawn", frame_index))
				spawn[size] = parse_spawn_value(value, size, frame_index)
			end
			if next(spawn) ~= nil then
				parsed.spawn = spawn
			end
		end

		if parsed.ratios == nil and parsed.spawn == nil then
			fail(string.format("frame %d must define ratios, spawn, or both.", frame_index))
		end

		parsed_frames[#parsed_frames + 1] = parsed
	end

	if families == nil then
		fail("at least one frame with ratios is required.")
	end
	if next(ratio_positions) == nil then
		fail("at least one frame with ratios is required.")
	end

	local ratio_curves = {}
	for _, family in ipairs(families) do
		ratio_curves[family] = {}
	end
	local spawn_curves = {}

	for _, frame in ipairs(parsed_frames) do
		if frame.ratios then
			-- Normalise each ratio keyframe before interpolating, matching Space
			-- Age's helper. Normalising after interpolation would boost regions
			-- where different families dominate at each end of the segment.
			local maximum = 0
			for _, family in ipairs(families) do
				if frame.ratios[family] > maximum then
					maximum = frame.ratios[family]
				end
			end
			local normalised = {}
			for _, family in ipairs(families) do
				normalised[family] = maximum > 0 and frame.ratios[family] / maximum or 0
			end
			for _, family in ipairs(families) do
				local curve = ratio_curves[family]
				curve[#curve + 1] = { position = frame.position, ratios = normalised }
			end
		end
		if frame.spawn then
			for size, point in pairs(frame.spawn) do
				local curve = spawn_curves[size]
				if not curve then
					curve = {}
					spawn_curves[size] = curve
				end
				curve[#curve + 1] = {
					position = frame.position,
					probability = point.probability,
					angle = point.angle_when_stopped or angles[size],
				}
			end
		end
	end

	if next(spawn_curves) == nil then
		fail("at least one frame with spawn probabilities is required.")
	end

	-- Sort each size's control points. Frames are already sorted, but a size may
	-- only appear in some frames.
	for _, size in ipairs(SIZES) do
		local curve = spawn_curves[size]
		if curve then
			table.sort(curve, function(a, b)
				return a.position < b.position
			end)
		end
	end

	local names = build_names(spec, families)

	local route = {
		families = families,
		names = names,
		ratio_curves = ratio_curves,
		ratio_positions = ratio_positions,
		spawn_curves = spawn_curves,
		speed = speed,
	}
	return setmetatable(route, Route)
end

--- Builds an asteroid route from a table of keyframes, or converts a Space Age
--- style asteroid table (`type_ratios` + `probability_on_range_*`).
--- @param spec table
--- @param options table|nil Only used when converting a Space Age style table.
--- @return table AsteroidRoute
function Public.asteroid_route(spec, options)
	if is_vanilla_table(spec) then
		return build_route(convert_vanilla_table(spec, options))
	end
	if options ~= nil then
		fail("options are only supported when converting a Space Age style asteroid table.")
	end
	return build_route(spec)
end

--- Generates asteroid spawn definitions. With no position, returns the
--- `spawn_points` form used by space connections. With a position (0..1),
--- returns the `probability` form used by planets and space locations.
--- @param route_or_spec table AsteroidRoute or route specification.
--- @param position number|nil
--- @return table
function Public.asteroid_spawn_definitions(route_or_spec, position)
	local route = is_route(route_or_spec) and route_or_spec or Public.asteroid_route(route_or_spec)
	if position == nil then
		return route:connection()
	end
	if not is_finite_number(position) then
		fail("planet position must be a number between 0 and 1, got " .. tostring(position) .. ".")
	end
	return route:planet(position)
end

local function resolve_target(target)
	if type(target) == "string" then
		if not data then
			fail_setter("the data stage is required to resolve prototype name " .. target .. ".")
		end
		local prototype = (data.raw.planet and data.raw.planet[target])
			or (data.raw["space-location"] and data.raw["space-location"][target])
			or (data.raw["space-connection"] and data.raw["space-connection"][target])
		if not prototype then
			fail_setter('could not find a planet, space-location or space-connection named "' .. target .. '".')
		end
		return prototype
	end

	if type(target) ~= "table" then
		fail_setter("target must be a prototype table or a prototype name.")
	end

	if target.type == "planet" or target.type == "space-location" or target.type == "space-connection" then
		return target
	end

	if target.name then
		if not data then
			fail_setter("the data stage is required to resolve prototype " .. target.name .. ".")
		end
		local prototype = (data.raw.planet and data.raw.planet[target.name])
			or (data.raw["space-location"] and data.raw["space-location"][target.name])
			or (data.raw["space-connection"] and data.raw["space-connection"][target.name])
		if prototype then
			return prototype
		end
	end

	fail_setter("target must be a planet, space-location or space-connection prototype.")
end

--- Applies a route to a planet, space-location or space-connection prototype.
--- For planets and space locations, the definitions are sampled at `position`
--- (default 0.9) and `influence` is written when supplied.
--- @param target table|string
--- @param route_or_spec table
--- @param options table|nil
--- @return table The resolved prototype.
function Public.set_asteroid_spawn_definitions(target, route_or_spec, options)
	options = options or {}
	if type(options) ~= "table" then
		fail_setter("options must be a table.")
	end
	for key in pairs(options) do
		if key ~= "position" and key ~= "influence" then
			fail_setter('unknown option "' .. tostring(key) .. '".')
		end
	end

	local route = is_route(route_or_spec) and route_or_spec or Public.asteroid_route(route_or_spec)
	local prototype = resolve_target(target)

	if prototype.type == "space-connection" then
		if options.position ~= nil then
			fail_setter("a space-connection does not use a planet position.")
		end
		if options.influence ~= nil then
			fail_setter("asteroid_spawn_influence only applies to planets and space locations.")
		end
		prototype.asteroid_spawn_definitions = route:connection()
		return prototype
	end

	if prototype.type ~= "planet" and prototype.type ~= "space-location" then
		fail_setter("target must be a planet, space-location or space-connection prototype.")
	end

	local position = options.position == nil and 0.9 or options.position
	if not is_finite_number(position) or position < 0 or position > 1 then
		fail_setter("position must be a number between 0 and 1, got " .. tostring(position) .. ".")
	end
	prototype.asteroid_spawn_definitions = route:planet(position)

	if options.influence ~= nil then
		if not is_finite_number(options.influence) then
			fail_setter("influence must be a number, got " .. tostring(options.influence) .. ".")
		end
		prototype.asteroid_spawn_influence = options.influence
	end

	return prototype
end

return Public
