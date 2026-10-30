-- Ground diggers: runtime build conversion, recipe assignment, collision
-- detection and surface conditions.
--
-- The data-stage fixture and suite cover configuration/generation. These tests
-- use real surfaces and the `planetslib_funit` remote interface.

local support = require("__planetslib-funit-data__.tests.suites.support")

local MARKER = "PlanetsLib-has-ground-diggers"
local DIGGER = "electric-mining-drill-ground-digger"
local BURNER_DIGGER = "burner-mining-drill-ground-digger"
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
	-- Wait for the surfaces to be deleted.
	test_runner.on_event_do(defines.events.on_surface_deleted, function() end, nil, 60)
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
	if player.controller_type == defines.controllers.cutscene then
		player.exit_cutscene()
	end
	if not player.character then
		local created = player.create_character()
		runner.assert(created, "could not create a character for the player")
		state.created_character = true
	end
	if player.controller_type ~= defines.controllers.character then
		player.set_controller({
			type = defines.controllers.character,
			character = player.character,
		})
	end
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
		local player = game.players[1]
		runner.assert(player, "the test scenario has no player")

		local created = {}
		local state = save_player_state(player)
		local cleanup_queued = false
		run_with_cleanup(function()
			if not cleanup_queued then
				restore_player(player, state)
				cleanup_surfaces(created)
			end
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
			construct({ x = 4, y = 0 })
			local digger = assert_digger(
				{ x = 4, y = 0 },
				"a drill placed without nearby resources was not converted into a digger"
			)
			runner.assert(stack_count() == before_count - 1, "a real build did not consume one cursor item")

			runner.after_n_ticks_do(1, function()
				runner.assert(
					stats.get_input_count(DRILL_ITEM) > before_builds,
					"the entity build statistics were not incremented"
				)
				restore_player(player, state)
				cleanup_surfaces(created)
			end)
			cleanup_queued = true
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
			construct({ x = 4, y = 0 })
			assert_no_digger({ 4, 0 }, "a drill with nearby resources was converted into a digger")
			runner.assert(stack_count() == resource_count, "a rejected conversion consumed a cursor item")
			resource.destroy()

			-- Collision: do not replace a solid entity.
			set_cursor(5)
			local chest = surface.create_entity({
				name = "iron-chest",
				position = { x = 4, y = 0 },
				force = player.force,
			})
			runner.assert(chest, "could not create the colliding entity")
			construct({ x = 4, y = 0 })
			assert_no_digger({ 4, 0 }, "a digger was created on top of a colliding entity")
			chest.destroy()

			-- Hidden tile: do not build over a tile with a hidden tile.
			set_cursor(5)
			surface.set_hidden_tile({ x = 4, y = 0 }, "landfill")
			construct({ x = 4, y = 0 })
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
				construct({ x = 4, y = 0 })
				local uncommon = assert_digger({ x = 4, y = 0 }, "the quality build did not create a digger")
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
		runner.assert(player, "the test scenario has no player")

		local created = {}
		local state = save_player_state(player)
		run_with_cleanup(function()
			restore_player(player, state)
			cleanup_surfaces(created)
		end, function()
			ensure_character(runner, player, state)
			local surface = prepare_surface(runner, "funit-gd-planet", created, 1)
			player.teleport({ 0, 0 }, surface)

			local build_distance = player.character.build_distance or 10
			local far = { x = build_distance + 10, y = 0 }

			player.set_controller({
				type = defines.controllers.remote,
				surface = surface,
				position = { 0, 0 },
			})

			player.cursor_stack.set_stack({
				name = DRILL_ITEM,
				count = 5,
			})
			local before_count = player.cursor_stack.count

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

	runner.test("GD-10 collision helper covers the whole digger footprint", function()
		local created = {}
		run_with_cleanup(function()
			cleanup_surfaces(created)
		end, function()
			support.assert_entry(runner, "ground_diggers_late", "GD-4a")

			local surface = prepare_surface(runner, "funit-gd-planet", created, 1)
			-- The shared test planet may still hold a digger from an earlier
			-- suite if a previous cleanup was interrupted. This test is about
			-- the collision footprint, not surface setup, so start from an
			-- explicitly empty 3x3 area.
			for _, entity in pairs(surface.find_entities_filtered({ area = { { 0, 0 }, { 3, 3 } } })) do
				entity.destroy()
			end
			local interface = remote.interfaces["planetslib_funit"]
			runner.assert(
				interface and interface["ground_digger_collisions"],
				"PlanetsLib did not expose planetslib_funit.ground_digger_collisions"
			)
			local function collisions_at(position)
				local collisions = remote.call(
					"planetslib_funit",
					"ground_digger_collisions",
					surface,
					position,
					DIGGER
				)
				runner.assert(
					type(collisions) == "table",
					"the ground_digger_collisions seam did not return a table"
				)
				return collisions
			end

			-- A 3x3 drill centred on this tile spans tiles 0..2 in both axes.
			local position = { x = 1.5, y = 1.5 }
			local collisions = collisions_at(position)
			runner.assert(
				#collisions == 0,
				"the collision helper reported "
					.. #collisions
					.. " entities in an empty 3x3 digger area"
			)

			-- An entity just outside the footprint must not block placement. The
			-- old implementation used tile_width/tile_height (the placement grid)
			-- instead of the selection box, which can make the checked area too
			-- small or otherwise incorrect for a given prototype.
			local adjacent = surface.create_entity({
				name = "iron-chest",
				position = { x = position.x + 3, y = position.y },
				force = game.forces.player,
			})
			runner.assert(adjacent, "could not create the adjacent chest")
			collisions = collisions_at(position)
			runner.assert(
				#collisions == 0,
				"an entity adjacent to, but outside, the digger footprint blocked placement"
			)
			adjacent.destroy()

			-- One tile from the centre: inside the 3x3 footprint, but outside the
			-- degenerate point that the old 1.5 margin produced for this build
			-- position. A regression to a zero-size area would miss this chest.
			local chest = surface.create_entity({
				name = "iron-chest",
				position = { x = position.x, y = position.y - 1 },
				force = game.forces.player,
			})
			runner.assert(chest, "could not create the chest used by the collision check")

			collisions = collisions_at(position)
			local found = false
			for _, entity in ipairs(collisions) do
				if entity.unit_number == chest.unit_number then
					found = true
					break
				end
			end
			runner.assert(
				found,
				"the collision helper missed a chest one tile from the digger centre; "
					.. "the collision area must cover the full footprint, not a zero-size point"
			)
			runner.assert(
				#collisions == 1,
				"the collision helper returned "
					.. #collisions
					.. " entities, expected only the test chest"
			)
			chest.destroy()

			-- Ghosts have no physical collision mask, but placing a digger over
			-- one must still be rejected.
			local ghost = surface.create_entity({
				name = "entity-ghost",
				inner_name = "iron-chest",
				position = { x = position.x, y = position.y - 1 },
				force = game.forces.player,
			})
			runner.assert(ghost and ghost.valid, "could not create the collision-test ghost")
			collisions = collisions_at(position)
			local found_ghost = false
			for _, entity in ipairs(collisions) do
				if entity.unit_number == ghost.unit_number then
					found_ghost = true
					break
				end
			end
			runner.assert(found_ghost, "the collision helper missed an entity ghost inside the footprint")
			runner.assert(
				#collisions == 1,
				"the collision helper returned "
					.. #collisions
					.. " entities, expected only the test ghost"
			)
			ghost.destroy()

			-- Directly placing a digger over its own ghost should revive the
			-- ghost. The seam exercises the same revival helper used by the
			-- player build path without requiring a connected player.
			local revive = remote.interfaces["planetslib_funit"]
				and remote.interfaces["planetslib_funit"]["revive_ground_digger_ghost"]
			runner.assert(revive, "PlanetsLib did not expose revive_ground_digger_ghost")
			local digger_ghost = surface.create_entity({
				name = "entity-ghost",
				inner_name = DIGGER,
				position = { x = position.x, y = position.y - 1 },
				force = game.forces.player,
			})
			runner.assert(digger_ghost and digger_ghost.valid, "could not create the ground-digger ghost")
			local revived = remote.call("planetslib_funit", "revive_ground_digger_ghost", digger_ghost)
			runner.assert(revived and revived.valid, "the ground-digger ghost was not revived")
			runner.assert(revived.name == DIGGER, "the revived entity has the wrong prototype")
			runner.assert(not digger_ghost.valid, "the ground-digger ghost still exists after revival")
			local revived_recipe = revived.get_recipe()
			runner.assert(
				revived_recipe and revived_recipe.name == "funit-gd-recipe-a",
				"the revived digger did not receive its planet recipe"
			)
			revived.destroy()
		end)
	end)

	runner.test("GD-12 only the ground-digger ghost nearest the cursor is selected", function()
		local interface = remote.interfaces["planetslib_funit"]
		runner.assert(
			interface and interface["select_digger_ghost"],
			"PlanetsLib did not expose planetslib_funit.select_digger_ghost"
		)

		local far = {
			type = "entity-ghost",
			ghost_name = DIGGER,
			name = "funit-far-ghost",
			position = { x = 2.5, y = 0.5 },
		}
		local near = {
			type = "entity-ghost",
			ghost_name = DIGGER,
			name = "funit-near-ghost",
			position = { x = 1.5, y = 1.0 },
		}
		local other = {
			type = "entity-ghost",
			ghost_name = "iron-chest",
			name = "funit-other-ghost",
			position = { x = 1.5, y = 1.5 },
		}

		local selected = remote.call(
			"planetslib_funit",
			"select_digger_ghost",
			{ far, near, other },
			DIGGER,
			{ x = 1.5, y = 1.5 }
		)
		runner.assert(selected ~= nil, "no ground-digger ghost was selected")
		runner.assert(
			selected.name == "funit-near-ghost",
			"the selected ground-digger ghost was not the one closest to the cursor"
		)
	end)

	runner.test("GD-11 on_entity_built respects the per-planet drill blacklist", function()
		local created = {}
		run_with_cleanup(function()
			cleanup_surfaces(created)
		end, function()
			-- GD-4b records that funit-gd-planet blacklists the burner drill while
			-- funit-gd-planet-b allows it.
			support.assert_entry(runner, "ground_diggers_late", "GD-4b")

			local surface_a = prepare_surface(runner, "funit-gd-planet", created, 1)
			local burner = surface_a.create_entity({
				name = BURNER_DIGGER,
				position = { 0, 0 },
				force = game.forces.player,
				raise_built = false,
			})
			runner.assert(burner, "could not create a burner digger on the blacklisting planet")
			remote.call("planetslib_funit", "on_entity_built", { entity = burner })
			runner.assert(
				burner.get_recipe() == nil,
				"a drill blacklisted on this planet received a ground-digger recipe"
			)
			runner.assert(
				burner.recipe_locked == false,
				"a drill blacklisted on this planet had its recipe locked"
			)

			local electric = surface_a.create_entity({
				name = DIGGER,
				position = { 5, 0 },
				force = game.forces.player,
				raise_built = false,
			})
			runner.assert(electric, "could not create an electric digger on the configured planet")
			remote.call("planetslib_funit", "on_entity_built", { entity = electric })
			local recipe = electric.get_recipe()
			runner.assert(recipe, "the allowed electric digger did not receive a recipe")
			runner.assert(
				recipe.name == "funit-gd-recipe-a",
				"the electric digger got the wrong planet recipe: " .. tostring(recipe.name)
			)
			runner.assert(electric.recipe_locked == true, "the allowed electric digger was not locked")

			-- The same shared prototype must still be converted on the planet that
			-- allows the burner drill.
			local surface_b = prepare_surface(runner, "funit-gd-planet-b", created, 1)
			local burner_b = surface_b.create_entity({
				name = BURNER_DIGGER,
				position = { 0, 0 },
				force = game.forces.player,
				raise_built = false,
			})
			runner.assert(burner_b, "could not create a burner digger on the allowing planet")
			remote.call("planetslib_funit", "on_entity_built", { entity = burner_b })
			local recipe_b = burner_b.get_recipe()
			runner.assert(recipe_b, "the burner digger did not receive a recipe on the allowing planet")
			runner.assert(
				recipe_b.name == "funit-gd-recipe-b",
				"the burner digger got the wrong planet recipe: " .. tostring(recipe_b.name)
			)
			runner.assert(burner_b.recipe_locked == true, "the burner digger was not locked on the allowing planet")
		end)
	end)
end
