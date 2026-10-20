-- Ground diggers: runtime build conversion, recipe assignment and surface
-- conditions.
--
-- The data-stage fixture and suite cover configuration/generation. These tests
-- use real surfaces and the `planetslib_funit` remote interface. The headless
-- FUnit CI scenario has no player, so the player-driven parts of GD-8/GD-9 are
-- skipped with a log message; the no-player guard itself is still tested.

local MARKER = "PlanetsLib-has-ground-diggers"
local DIGGER = "electric-mining-drill-ground-digger"
local DRILL_ITEM = "electric-mining-drill"

local function run_with_cleanup(cleanup, fn)
	local ok, err = xpcall(fn, function(error_value)
		return error_value
	end)
	pcall(cleanup)
	if not ok then
		error(err, 0)
	end
end

local function make_surface(runner, planet_name, created)
	local planet = game.planets[planet_name]
	runner.assert(planet, "test planet '" .. planet_name .. "' is missing")

	local surface = planet.surface
	if surface and not surface.valid then
		surface = nil
	end
	if not surface then
		local ok, result = pcall(function()
			return planet.create_surface()
		end)
		runner.assert(ok, "could not create the surface for '" .. planet_name .. "': " .. tostring(result))
		surface = result
	end
	runner.assert(surface and surface.valid, "the surface for '" .. planet_name .. "' is invalid")
	created[#created + 1] = surface
	return surface
end

local function prepare_surface(runner, planet_name, created, expected_marker)
	local surface = make_surface(runner, planet_name, created)

	-- Remove map-generation leftovers and lay a flat landfill area around the
	-- origin so placements are deterministic.
	surface.clear(true)
	surface.request_to_generate_chunks({ 0, 0 }, 1)
	surface.force_generate_chunk_requests()

	local tiles = {}
	for x = -32, 32 do
		for y = -32, 32 do
			tiles[#tiles + 1] = { name = "landfill", position = { x, y } }
		end
	end
	surface.set_tiles(tiles, true, true, true)
	-- clear(false) removes entities but keeps the landfill tiles laid above.
	surface.clear(false)
	surface.clear_hidden_tiles()

	if expected_marker ~= nil then
		local actual = surface.get_property(MARKER)
		runner.assert(
			actual == expected_marker,
			"the surface property '"
				.. MARKER
				.. "' for '"
				.. planet_name
				.. "' is "
				.. tostring(actual)
				.. ", expected "
				.. tostring(expected_marker)
		)
	end
	return surface
end

local function cleanup_surfaces(created)
	for index = #created, 1, -1 do
		local surface = created[index]
		if surface and surface.valid then
			pcall(function()
				surface.clear(true)
			end)
			pcall(function()
				game.delete_surface(surface)
			end)
		end
	end
end

local function find_entity(surface, name, position, radius)
	local entities = surface.find_entities_filtered({
		name = name,
		position = position,
		radius = radius or 2,
	})
	return entities[1]
end

local function find_ghost(surface, inner_name, position, radius)
	local ghosts = surface.find_entities_filtered({
		name = "entity-ghost",
		ghost_name = inner_name,
		position = position,
		radius = radius or 2,
	})
	return ghosts[1]
end

local function save_player_state(player)
	return {
		surface = player.surface,
		position = player.position,
		controller_type = player.controller_type,
		created_character = false,
	}
end

local function ensure_character(runner, player, state)
	if not player.character then
		local created = player.create_character()
		runner.assert(created, "could not create a character for the player")
		state.created_character = true
	end
	player.set_controller({
		type = defines.controllers.character,
		character = player.character,
	})
end

local function restore_player(player, state)
	if not (player and player.valid) then
		return
	end
	pcall(function()
		player.clear_cursor()
	end)
	if state.surface and state.surface.valid and player.character then
		pcall(function()
			player.teleport(state.position, state.surface)
		end)
	end
	if state.controller_type == defines.controllers.character and player.character then
		pcall(function()
			player.set_controller({
				type = defines.controllers.character,
				character = player.character,
			})
		end)
	elseif state.controller_type == defines.controllers.remote and state.surface and state.surface.valid then
		pcall(function()
			player.set_controller({
				type = defines.controllers.remote,
				surface = state.surface,
				position = state.position,
			})
		end)
	end
	if state.created_character and player.character and player.character.valid then
		pcall(function()
			player.character.destroy()
		end)
	end
end

return function(runner)
	if not script.active_mods["space-age"] then
		return
	end

	runner.test("GD-6 built digger gets and locks the planet recipe", function()
		local created = {}
		run_with_cleanup(function()
			cleanup_surfaces(created)
		end, function()
			local surface_a = prepare_surface(runner, "funit-gd-planet", created, 1)
			local digger_a = surface_a.create_entity({
				name = DIGGER,
				position = { 0, 0 },
				force = game.forces.player,
				raise_built = true,
			})
			runner.assert(digger_a, "could not create a digger on a participating planet")
			local recipe = digger_a.get_recipe()
			runner.assert(recipe, "the built digger has no recipe")
			runner.assert(
				recipe.name == "funit-gd-recipe-a",
				"the digger got the wrong planet recipe: " .. tostring(recipe.name)
			)
			runner.assert(digger_a.recipe_locked == true, "the digger's recipe is not locked")

			-- A second participating planet gets its own recipe from the same
			-- shared prototype.
			local surface_b = prepare_surface(runner, "funit-gd-planet-b", created, 1)
			local digger_b = surface_b.create_entity({
				name = DIGGER,
				position = { 0, 0 },
				force = game.forces.player,
				raise_built = true,
			})
			runner.assert(digger_b, "could not create a digger on the second participating planet")
			local recipe_b = digger_b.get_recipe()
			runner.assert(recipe_b, "the second planet's digger has no recipe")
			runner.assert(
				recipe_b.name == "funit-gd-recipe-b",
				"the second planet's digger got the wrong recipe: " .. tostring(recipe_b.name)
			)
			runner.assert(digger_b.recipe_locked == true, "the second planet's digger recipe is not locked")

			-- The idle planet has no ground-digger config. Enable the prototype's
			-- marker condition so the digger can exist, and verify that the build
			-- handler still leaves it without a recipe.
			local surface_idle = prepare_surface(runner, "funit-gd-idle", created, 0)
			surface_idle.set_property(MARKER, 1)
			local digger_idle = surface_idle.create_entity({
				name = DIGGER,
				position = { 0, 0 },
				force = game.forces.player,
				raise_built = true,
			})
			runner.assert(digger_idle, "could not create a digger on the idle planet after setting the marker")
			runner.assert(
				digger_idle.get_recipe() == nil,
				"a digger on a non-participating planet received a recipe"
			)
			runner.assert(
				digger_idle.recipe_locked == false,
				"a digger on a non-participating planet was locked"
			)
		end)
	end)

	runner.test("GD-7 surface conditions gate digger placement", function()
		local created = {}
		run_with_cleanup(function()
			cleanup_surfaces(created)
		end, function()
			-- The shared digger requires the participating-planet marker. A
			-- previous test may have set it on this planet's primary surface,
			-- which cannot be deleted by cleanup_surfaces, so reset it here.
			local idle_planet = game.planets["funit-gd-idle"]
			local existing_idle_surface = idle_planet and idle_planet.surface
			if existing_idle_surface and existing_idle_surface.valid then
				existing_idle_surface.set_property(MARKER, 0)
			end
			local idle = prepare_surface(runner, "funit-gd-idle", created, 0)
			-- Script-created entities bypass surface conditions, so test the
			-- placement check that a player build would use.
			local placement = idle.find_non_colliding_position(DRILL_ITEM, { x = 0, y = 0 }, 32, 0.5)
				or { x = 0, y = 0 }
			local blocked = idle.can_place_entity({
				name = DIGGER,
				position = placement,
				force = game.forces.player,
			})
			runner.assert(
				not blocked,
				"a digger could be placed on a planet without the ground-digger marker"
			)

			-- Setting the marker allows the prototype to exist, but the idle
			-- planet still has no recipe to assign.
			idle.set_property(MARKER, 1)
			local can_place = idle.can_place_entity({
				name = DIGGER,
				position = placement,
				force = game.forces.player,
			})
			runner.assert(can_place, "setting the marker did not allow the shared digger prototype")
			local enabled = idle.create_entity({
				name = DIGGER,
				position = placement,
				force = game.forces.player,
				raise_built = true,
			})
			runner.assert(enabled, "the shared digger prototype could not be created")
			runner.assert(enabled.get_recipe() == nil, "the idle planet's digger unexpectedly got a recipe")

			-- The drill's own surface conditions are inherited by its digger.
			local participating = prepare_surface(runner, "funit-gd-planet", created, 1)
			local participating_position = participating.find_non_colliding_position(
				DIGGER,
				{ x = 0, y = 0 },
				32,
				0.5
			) or { x = 0, y = 0 }
			local conditioned_placeable = participating.can_place_entity({
				name = "funit-gd-conditioned-drill-ground-digger",
				position = participating_position,
				force = game.forces.player,
			})
			runner.assert(
				not conditioned_placeable,
				"a digger could be placed even though the drill's surface conditions were not met"
			)

			local control = participating.create_entity({
				name = DIGGER,
				position = participating_position,
				force = game.forces.player,
				raise_built = true,
			})
			runner.assert(control, "the control digger could not be created on a participating planet")
		end)
	end)

	runner.test("GD-8 construct_ground_digger conversion rules", function()
		-- The missing-player guard is testable without a player.
		local guard_ok, guard_err = pcall(remote.call, "planetslib_funit", "construct_ground_digger", {
			player_index = 9999,
			cursor_position = { 0, 0 },
			cursor_direction = defines.direction.north,
			input_name = "PlanetsLib-build",
		})
		runner.assert(
			guard_ok,
			"construct_ground_digger errored for a missing player: " .. tostring(guard_err)
		)

		local player = game.players[1]
		if not player then
			runner.log("GD-8 skipped: the headless scenario has no player (missing-player guard was tested)")
			return
		end

		local created = {}
		local state = save_player_state(player)
		run_with_cleanup(function()
			restore_player(player, state)
			cleanup_surfaces(created)
		end, function()
			ensure_character(runner, player, state)
			local surface = prepare_surface(runner, "funit-gd-planet", created, 1)
			player.teleport({ 0, 0 }, surface)

			local function stack_count()
				return player.cursor_stack.valid_for_read and player.cursor_stack.count or 0
			end

			local function set_cursor(count, quality)
				player.cursor_stack.set_stack({
					name = DRILL_ITEM,
					count = count,
					quality = quality,
				})
			end

			local function construct(position, input_name)
				remote.call("planetslib_funit", "construct_ground_digger", {
					player_index = player.index,
					cursor_position = position,
					cursor_direction = defines.direction.north,
					input_name = input_name or "PlanetsLib-build",
				})
			end

			local function assert_digger(position, message)
				local digger = find_entity(surface, DIGGER, position)
				runner.assert(digger, message)
				return digger
			end

			local function assert_no_digger(position, message)
				runner.assert(find_entity(surface, DIGGER, position) == nil, message)
			end

			-- No resources: convert and consume one cursor item, updating the
			-- force's build statistics.
			set_cursor(5)
			local before_count = stack_count()
			local stats = player.force.get_entity_build_count_statistics(surface)
			local before_builds = stats.get_input_count(DRILL_ITEM)
			construct({ 4, 0 })
			local digger = assert_digger(
				{ 4, 0 },
				"a drill placed without nearby resources was not converted into a digger"
			)
			runner.assert(stack_count() == before_count - 1, "a real build did not consume one cursor item")
			runner.assert(
				stats.get_input_count(DRILL_ITEM) == before_builds + 1,
				"the entity build statistics were not incremented"
			)
			local recipe = digger.get_recipe()
			runner.assert(recipe and recipe.name == "funit-gd-recipe-a", "the converted digger has the wrong recipe")
			digger.destroy()

			-- Resources nearby: leave the normal drill alone.
			set_cursor(5)
			local resource = surface.create_entity({
				name = "iron-ore",
				position = { 6, 0 },
			})
			runner.assert(resource, "could not create the resource used by the no-conversion check")
			local resource_count = stack_count()
			construct({ 4, 0 })
			assert_no_digger({ 4, 0 }, "a drill with nearby resources was converted into a digger")
			runner.assert(stack_count() == resource_count, "a rejected conversion consumed a cursor item")
			resource.destroy()

			-- Collision: do not replace a solid entity.
			set_cursor(5)
			local chest = surface.create_entity({
				name = "iron-chest",
				position = { 4, 0 },
				force = player.force,
			})
			runner.assert(chest, "could not create the colliding entity")
			construct({ 4, 0 })
			assert_no_digger({ 4, 0 }, "a digger was created on top of a colliding entity")
			chest.destroy()

			-- Hidden tile: do not build over a tile with a hidden tile.
			set_cursor(5)
			surface.set_hidden_tile({ x = 4, y = 0 }, "landfill")
			construct({ 4, 0 })
			assert_no_digger({ 4, 0 }, "a digger was created on a tile with a hidden tile")
			surface.set_hidden_tile({ x = 4, y = 0 }, nil)

			-- Out of reach: do not build outside the character's build distance.
			set_cursor(5)
			local build_distance = player.character.build_distance or 10
			local far = { x = build_distance + 10, y = 0 }
			construct(far)
			assert_no_digger(far, "a digger was created outside the character's build distance")

			-- Quality is inherited from the cursor stack when Quality is active.
			if prototypes.quality and prototypes.quality["uncommon"] then
				set_cursor(5, "uncommon")
				construct({ 4, 0 })
				local uncommon = assert_digger({ 4, 0 }, "the quality build did not create a digger")
				runner.assert(
					uncommon.quality and uncommon.quality.name == "uncommon",
					"the digger did not inherit the cursor stack's quality"
				)
				uncommon.destroy()
			end
		end)
	end)

	runner.test("GD-9 remote-view ghost without reach", function()
		local player = game.players[1]
		if not player then
			runner.log("GD-9 skipped: the headless scenario has no player")
			return
		end

		local created = {}
		local state = save_player_state(player)
		run_with_cleanup(function()
			restore_player(player, state)
			cleanup_surfaces(created)
		end, function()
			ensure_character(runner, player, state)
			local surface = prepare_surface(runner, "funit-gd-planet", created, 1)
			player.teleport({ 0, 0 }, surface)

			player.cursor_stack.set_stack({
				name = DRILL_ITEM,
				count = 5,
			})
			local before_count = player.cursor_stack.count

			local build_distance = player.character.build_distance or 10
			local far = { x = build_distance + 10, y = 0 }

			player.set_controller({
				type = defines.controllers.remote,
				surface = surface,
				position = { 0, 0 },
			})

			remote.call("planetslib_funit", "construct_ground_digger", {
				player_index = player.index,
				cursor_position = far,
				cursor_direction = defines.direction.north,
				input_name = "PlanetsLib-build",
			})

			local ghost = find_ghost(surface, DIGGER, far)
			runner.assert(ghost, "a remote-view build did not create a digger ghost")
			runner.assert(ghost.ghost_name == DIGGER, "the ghost has the wrong inner prototype")
			runner.assert(
				player.cursor_stack.count == before_count,
				"a ghost build consumed the cursor item"
			)
			runner.assert(
				find_entity(surface, DIGGER, far) == nil,
				"a remote-view build created a real digger instead of a ghost"
			)
		end)
	end)
end
