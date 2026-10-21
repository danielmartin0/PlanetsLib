-- Data-stage fixture: PlanetsLib.set_asteroid_spawn_definitions.
--
-- The route builder itself is pure and covered by the runtime `asteroids`
-- suite. This fixture pins down the prototype-writing helper, including the
-- default 0.9 planet position and the connection/planet branch split.

local results = require("lib.results")

local ok, err = pcall(function()
	-- asteroid_spawn_definitions must reference real asteroid prototypes.
	-- Clone a vanilla chunk when Space Age is active; in a base-only game there
	-- is no asteroid-chunk prototype to clone, so create a minimal one.
	local custom_chunk_name = "funit-anorthite-chunk"
	local custom_chunk
	if data.raw["asteroid-chunk"] and data.raw["asteroid-chunk"]["metallic-asteroid-chunk"] then
		custom_chunk = table.deepcopy(data.raw["asteroid-chunk"]["metallic-asteroid-chunk"])
	else
		custom_chunk = {
			type = "asteroid-chunk",
			name = custom_chunk_name,
			icon = "__base__/graphics/icons/iron-plate.png",
			icon_size = 64,
			order = "z",
		}
	end
	custom_chunk.name = custom_chunk_name
	data:extend({ custom_chunk })

	local route = PlanetsLib.asteroid_route {
		names = {
			anorthite = { chunk = custom_chunk_name },
		},
		{
			position = 0.1,
			ratios = { anorthite = 3 },
			spawn = { chunk = 0.0125 },
		},
		{
			position = 0.9,
			ratios = { anorthite = 1 },
			spawn = { chunk = 0.025 },
		},
	}

	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = "funit-asteroid-planet"
	planet.type = "planet"
	data:extend({ planet })

	local returned = PlanetsLib.set_asteroid_spawn_definitions("funit-asteroid-planet", route, { influence = 0.25 })
	assert(
		returned == data.raw.planet["funit-asteroid-planet"],
		"set_asteroid_spawn_definitions should return the resolved prototype"
	)
	assert(planet.asteroid_spawn_influence == 0.25, "influence was not written to the planet")
	assert(planet.asteroid_spawn_definitions, "planet spawn definitions were not written")

	local expected = route:planet(0.9)
	assert(
		#planet.asteroid_spawn_definitions == #expected,
		"planet definitions should default to position 0.9"
	)
	assert(
		planet.asteroid_spawn_definitions[1].asteroid == expected[1].asteroid
			and planet.asteroid_spawn_definitions[1].probability == expected[1].probability,
		"planet definitions do not match route:planet(0.9)"
	)

	local anorthite = false
	for _, definition in ipairs(planet.asteroid_spawn_definitions) do
		if definition.asteroid == custom_chunk_name then
			anorthite = true
			assert(definition.type == "asteroid-chunk", "custom chunk type is wrong")
		end
	end
	assert(anorthite, "the custom anorthite chunk is missing from the planet definitions")

	-- Explicit position and prototype-table targets.
	PlanetsLib.set_asteroid_spawn_definitions(planet, route, { position = 0.5, influence = 1 })
	assert(planet.asteroid_spawn_influence == 1, "influence was not updated")
	assert(
		#planet.asteroid_spawn_definitions == #route:planet(0.5),
		"explicit planet position was not used"
	)

	local missing_target_ok = pcall(function()
		PlanetsLib.set_asteroid_spawn_definitions("funit-no-such-asteroid-target", route)
	end)
	assert(not missing_target_ok, "an unknown target should raise an error")

	local bad_position_ok = pcall(function()
		PlanetsLib.set_asteroid_spawn_definitions(planet, route, { position = 2 })
	end)
	assert(not bad_position_ok, "an out-of-range position should raise an error")

	if mods["space-age"] and data.raw["space-connection"]["nauvis-vulcanus"] then
		local connection = table.deepcopy(data.raw["space-connection"]["nauvis-vulcanus"])
		connection.name = "funit-asteroid-connection"
		connection.from = "nauvis"
		connection.to = "vulcanus"
		data:extend({ connection })

		local returned_connection = PlanetsLib.set_asteroid_spawn_definitions("funit-asteroid-connection", route)
		assert(returned_connection == connection, "connection target was not resolved")
		assert(connection.asteroid_spawn_definitions, "connection spawn definitions were not written")
		assert(#connection.asteroid_spawn_definitions > 0, "connection spawn definitions are empty")
		assert(
			connection.asteroid_spawn_definitions[1].spawn_points ~= nil,
			"connection definitions must contain spawn_points"
		)

		local position_ok = pcall(function()
			PlanetsLib.set_asteroid_spawn_definitions(connection, route, { position = 0.5 })
		end)
		assert(not position_ok, "a planet position option should be rejected for a space connection")

		local influence_ok = pcall(function()
			PlanetsLib.set_asteroid_spawn_definitions(connection, route, { influence = 1 })
		end)
		assert(not influence_ok, "influence should be rejected for a space connection")
	end
end)

results.record("asteroids", "AST-11", ok, err)
