-- Entity removal floors: runtime queueing, tile ghosts, reissued deconstruction
-- and temporary-floor cleanup.

local support = require("__planetslib-funit-data__.tests.suites.support")

local PLANET = "funit-erf-planet"
local PLANET_B = "funit-erf-planet-b"
local ENTITY = "funit-erf-rock"
local ENTITY_B = "funit-erf-rock-b"
local LARGE_ENTITY = "funit-erf-large-rock"
local DROP_ENTITY = "funit-erf-drop-rock"
local PLANT = "funit-erf-plant"
local CONTAINER = "funit-erf-container"
local SAFE_TILE = "funit-erf-safe"
local UNSAFE_TILE = "funit-erf-unsafe"
local SAFE_ITEM = "funit-erf-safe-item"
local OTHER_ITEM = "funit-erf-other-item"

local function run_with_cleanup(cleanup, fn)
	local ok, err = xpcall(fn, function(error_value)
		return error_value
	end)
	pcall(cleanup)
	if not ok then
		error(err, 0)
	end
end

local function make_surface(runner, planet_name)
	planet_name = planet_name or PLANET
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
	return surface
end

local prepared_surface

local function destroy_surface_entities(surface)
	for _, entity in pairs(surface.find_entities_filtered({})) do
		if entity.valid then
			entity.destroy()
		end
	end
end

local function prepare_surface(runner)
	local surface = prepared_surface
	if not (surface and surface.valid) then
		surface = make_surface(runner)
		prepared_surface = surface

		surface.request_to_generate_chunks({ 0, 0 }, 2)
		surface.force_generate_chunk_requests()
		surface.clear_hidden_tiles()
	end

	-- Destroy entities instead of clearing the surface: LuaSurface.clear()
	-- deletes chunks asynchronously, which invalidates cached LuaTile objects.
	destroy_surface_entities(surface)

	local tiles = {}
	for x = -24, 24 do
		for y = -24, 24 do
			tiles[#tiles + 1] = { name = UNSAFE_TILE, position = { x, y } }
		end
	end
	surface.set_tiles(tiles, true, true, true, false)
	return surface
end

local function cleanup_surface(surface)
	if not (surface and surface.valid) then
		return
	end
	pcall(function()
		remote.call("planetslib_funit", "entity_removal_floors_clear_surface_state", surface.index)
	end)
	pcall(function()
		destroy_surface_entities(surface)
	end)
end

local function create_named_entity(runner, surface, name, position)
	local entity = surface.create_entity({
		name = name,
		position = position,
		force = game.forces.player,
	})
	runner.assert(entity and entity.valid, "could not create the test entity " .. name)
	return entity
end

local function create_entity(runner, surface, position)
	return create_named_entity(runner, surface, ENTITY, position)
end

local function count_keys(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
end

local function tile_ghost_names(surface, position)
	local x = position.x or position[1]
	local y = position.y or position[2]
	local names = {}
	for _, ghost in pairs(surface.get_tile(x, y).get_tile_ghosts(game.forces.player)) do
		if ghost.valid then
			names[ghost.ghost_name] = true
		end
	end
	return names
end

local function count_tile_ghosts(surface, position, name)
	local x = position.x or position[1]
	local y = position.y or position[2]
	local count = 0
	for _, ghost in pairs(surface.get_tile(x, y).get_tile_ghosts(game.forces.player)) do
		if ghost.valid and ghost.ghost_name == name then
			count = count + 1
		end
	end
	return count
end

local function set_tile(surface, name, x, y)
	surface.set_tiles({ { name = name, position = { x, y } } }, true, false, true, false)
end

local function wait_until(runner, predicate, options)
	local timeout = math.max(1, options.timeout or 600)
	local interval = math.max(1, options.interval or 30)
	local deadline = game.tick + timeout

	local function check()
		local ok, err = pcall(function()
			if predicate() then
				if options.on_success then
					options.on_success()
				end
				return
			end
			if game.tick >= deadline then
				runner.assert(false, options.message or "condition was not met")
			end
			runner.after_n_ticks_do(interval, check)
		end)
		if not ok then
			if options.on_failure then
				pcall(options.on_failure)
			end
			error(err, 0)
		end
	end

	runner.after_n_ticks_do(1, check)
end

local function mark_queued(runner, entity)
	entity.order_deconstruction(game.forces.player)
	remote.call("planetslib_funit", "entity_removal_floors_on_marked_for_deconstruction", {
		entity = entity,
	})
end

local function find_tile_ghost(surface, position)
	local ghosts = surface.find_entities_filtered({
		name = "tile-ghost",
		position = position,
		radius = 1,
	})
	for _, ghost in pairs(ghosts) do
		if ghost.valid then
			return ghost
		end
	end
	return nil
end

local function queued(surface)
	return remote.call("planetslib_funit", "entity_removal_floors_get_queued", surface.index)
end

local function cleanup(surface)
	return remote.call("planetslib_funit", "entity_removal_floors_get_cleanup", surface.index)
end

return function(runner)
	if not support.has_space_age() then
		return
	end

	runner.test("ERF-1 data-stage rule configuration", function()
		local entries = support.entries(runner, "entity_removal_floors_data")
		for _, id in ipairs({ "ERF-0-setup", "ERF-1", "ERF-2" }) do
			local entry = entries[id]
			runner.assert(entry, "missing entity removal floor fixture entry '" .. id .. "'")
			runner.assert(entry.ok, "entity removal floor fixture '" .. id .. "' failed: " .. tostring(entry.err))
		end

		local rules = prototypes.mod_data["Planetslib"].data.entity_removal_floors
		runner.assert(rules and rules[PLANET], "the test planet has no entity removal floor rules")
		runner.assert(rules[PLANET][ENTITY], "the test entity has no rule")
		runner.assert(rules[PLANET][PLANT], "the plant test entity has no rule")
		runner.assert(rules[PLANET][CONTAINER], "the container test entity has no rule")
		runner.assert(rules[PLANET][ENTITY].default_tile == SAFE_TILE, "the configured default tile is wrong")
		runner.assert(
			rules[PLANET][ENTITY].default_tile_item == SAFE_ITEM,
			"the configured default tile item is wrong"
		)
		runner.assert(
			remote.call("planetslib_funit", "entity_removal_floors_is_enabled"),
			"the entity removal floor feature should be enabled"
		)
	end)

	runner.test("ERF-2 marks a queued entity and places floor ghosts", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 0.5, 0.5 })
			mark_queued(runner, entity)

			runner.assert(not entity.to_be_deconstructed(), "the deconstruction order was not cancelled")
			local ghost = find_tile_ghost(surface, { 0.5, 0.5 })
			runner.assert(ghost, "no tile ghost was created under the queued entity")
			runner.assert(ghost.ghost_name == SAFE_TILE, "the tile ghost has the wrong tile")

			local plant = create_named_entity(runner, surface, PLANT, { 1.5, 0.5 })
			mark_queued(runner, plant)
			runner.assert(not plant.to_be_deconstructed(), "the plant deconstruction order was not cancelled")
			local plant_ghost = find_tile_ghost(surface, { 1.5, 0.5 })
			runner.assert(plant_ghost, "no tile ghost was created under the queued plant")
			runner.assert(plant_ghost.ghost_name == SAFE_TILE, "the plant tile ghost has the wrong tile")

			local container = create_named_entity(runner, surface, CONTAINER, { 2.5, 0.5 })
			mark_queued(runner, container)
			runner.assert(not container.to_be_deconstructed(), "the container deconstruction order was not cancelled")
			local container_ghost = find_tile_ghost(surface, { 2.5, 0.5 })
			runner.assert(container_ghost, "no tile ghost was created under the queued container")
			runner.assert(container_ghost.ghost_name == SAFE_TILE, "the container tile ghost has the wrong tile")

			local entries = queued(surface)
			runner.assert(#entries == 3, "expected three queued entities, got " .. #entries)
			runner.assert(entries[1].replacement_tile == SAFE_TILE, "the queued replacement tile is wrong")
		end)
	end)

	runner.test("ERF-3 building the floor reissues deconstruction", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 2.5, 2.5 })
			mark_queued(runner, entity)

			surface.set_tiles({ { name = SAFE_TILE, position = { 2, 2 } } }, true, true, true, false)
			remote.call("planetslib_funit", "entity_removal_floors_on_tile_built", {
				surface_index = surface.index,
				tile = { name = SAFE_TILE },
				tiles = { { position = { x = 2, y = 2 } } },
			}, "robot")

			runner.assert(entity.valid and entity.to_be_deconstructed(), "deconstruction was not reissued")
			runner.assert(#queued(surface) == 0, "the queued entry was not removed after the floor was built")

			local pending = cleanup(surface)
			runner.assert(#pending == 1, "the robot-built floor was not queued for cleanup")
			runner.assert(pending[1].tile_name == SAFE_TILE, "the pending cleanup has the wrong tile")
		end)
	end)

	runner.test("ERF-4 undo removes the queue and created ghosts", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 4.5, 4.5 })
			mark_queued(runner, entity)
			runner.assert(#queued(surface) == 1, "the entity was not queued")
			runner.assert(find_tile_ghost(surface, { 4.5, 4.5 }), "the queue did not create a tile ghost")

			remote.call("planetslib_funit", "entity_removal_floors_on_undo_applied", {
				actions = {
					{
						type = "removed-entity",
						surface_index = surface.index,
						target = { name = ENTITY, position = { x = 4.5, y = 4.5 } },
					},
				},
			})

			runner.assert(#queued(surface) == 0, "undo did not remove the queued entry")
			runner.assert(not find_tile_ghost(surface, { 4.5, 4.5 }), "undo did not remove the created tile ghost")
		end)
	end)

	runner.test("ERF-5 tile selection rules", function()
		local function select(default_count, required, in_range, is_character, default_item)
			return remote.call(
				"planetslib_funit",
				"entity_removal_floors_select_replacement_tile",
				{
					{ name = OTHER_ITEM, count = 1 },
				},
				default_count,
				required,
				in_range,
				is_character,
				SAFE_TILE,
				default_item
			)
		end

		runner.assert(select(0, 1, false, true, SAFE_ITEM) == "landfill", "the fallback tile was not selected")
		runner.assert(select(0, 1, true, true, SAFE_ITEM) == SAFE_TILE, "roboport coverage should use the default tile")
		runner.assert(select(1, 1, false, true, SAFE_ITEM) == SAFE_TILE, "enough default items should use the default tile")
		runner.assert(select(0, 1, false, false, SAFE_ITEM) == SAFE_TILE, "non-character players should use the default tile")
		runner.assert(select(0, 1, false, true, nil) == SAFE_TILE, "a missing default tile item should disable fallback")
	end)

	runner.test("ERF-6 footprint bounds use whole tiles", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 6.5, 6.5 })
			local bounds = remote.call("planetslib_funit", "entity_removal_floors_floor_bounds", entity)
			runner.assert(bounds[1] == 6 and bounds[2] == 6, "the footprint left/right bounds are wrong")
			runner.assert(bounds[3] == 6 and bounds[4] == 6, "the footprint top/bottom bounds are wrong")
		end)
	end)

	runner.test("ERF-7 robot-built temporary floors are removed after drops are gone", function()
		local surface = prepare_surface(runner)
		local keep_surface = true

		local ok, err = xpcall(function()
			local entity = create_entity(runner, surface, { 8.5, 8.5 })
			mark_queued(runner, entity)
			runner.assert(#queued(surface) == 1, "the entity was not queued")

			surface.set_tiles({ { name = SAFE_TILE, position = { 8, 8 } } }, true, true, true, false)
			remote.call("planetslib_funit", "entity_removal_floors_on_tile_built", {
				surface_index = surface.index,
				tile = { name = SAFE_TILE },
				tiles = { { position = { x = 8, y = 8 } } },
			}, "robot")
			runner.assert(#queued(surface) == 0, "the queued entry was not removed after the floor was built")
			runner.assert(#cleanup(surface) == 1, "the robot-built floor was not queued for cleanup")

			entity.destroy({ raise_destroy = true })
			remote.call("planetslib_funit", "entity_removal_floors_process_pending_tile_cleanup")
			runner.after_n_ticks_do(31, function()
				local callback_ok, callback_err = pcall(function()
					remote.call("planetslib_funit", "entity_removal_floors_process_pending_tile_cleanup")

					local tile = surface.get_tile(8, 8)
					runner.assert(tile and tile.valid, "the temporary floor tile no longer exists")
					runner.assert(tile and tile.name == SAFE_TILE, "the temporary floor tile disappeared")
					runner.assert(
						tile.to_be_deconstructed(game.forces.player),
						"the robot-built temporary floor was not ordered for deconstruction"
					)
					runner.assert(#cleanup(surface) == 0, "the pending cleanup entry was not removed")
				end)

				pcall(cleanup_surface, surface)
				keep_surface = false
				if not callback_ok then
					error(callback_err, 0)
				end
			end)
		end, function(error_value)
			return error_value
		end)

		if not ok then
			if keep_surface then
				cleanup_surface(surface)
			end
			error(err, 0)
		end
	end)

	runner.test("ERF-8 player-built temporary floors are kept", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 10.5, 10.5 })
			mark_queued(runner, entity)

			surface.set_tiles({ { name = SAFE_TILE, position = { 10, 10 } } }, true, true, true, false)
			remote.call("planetslib_funit", "entity_removal_floors_on_tile_built", {
				surface_index = surface.index,
				tile = { name = SAFE_TILE },
				tiles = { { position = { x = 10, y = 10 } } },
			}, "player")

			entity.destroy({ raise_destroy = true })
			remote.call("planetslib_funit", "entity_removal_floors_process_pending_tile_cleanup")

			runner.assert(#cleanup(surface) == 0, "a player-built floor should not be queued for cleanup")
			local tile = surface.get_tile(10, 10)
			runner.assert(tile and tile.name == SAFE_TILE, "the player-built floor was removed")
			runner.assert(not tile.to_be_deconstructed(game.forces.player), "a player-built floor was marked for deconstruction")
		end)
	end)

	runner.test("ERF-9 direct grouped mod-data rules are usable", function()
		local surface = make_surface(runner, PLANET_B)
		surface.clear(true)
		surface.request_to_generate_chunks({ 0, 0 }, 2)
		surface.force_generate_chunk_requests()

		local tiles = {}
		for x = -8, 8 do
			for y = -8, 8 do
				tiles[#tiles + 1] = { name = UNSAFE_TILE, position = { x, y } }
			end
		end
		surface.set_tiles(tiles, true, true, true, false)

		run_with_cleanup(function()
			remote.call("planetslib_funit", "entity_removal_floors_clear_surface_state", surface.index)
			surface.clear(true)
			game.delete_surface(surface)
		end, function()
			local entity = surface.create_entity({
				name = ENTITY_B,
				position = { 0.5, 0.5 },
				force = game.forces.player,
			})
			runner.assert(entity and entity.valid, "could not create the grouped-rule test entity")
			mark_queued(runner, entity)

			runner.assert(not entity.to_be_deconstructed(), "the grouped-rule entity was not queued")
			local ghost = find_tile_ghost(surface, { 0.5, 0.5 })
			runner.assert(ghost, "the grouped rule did not create a tile ghost")
			runner.assert(ghost.ghost_name == SAFE_TILE, "the grouped rule used the wrong tile")
		end)
	end)

	runner.test("ERF-10 stationary roboport coverage is detected", function()
		local surface = prepare_surface(runner)
		local roboport = surface.create_entity({
			name = "roboport",
			position = { 0.5, 0.5 },
			force = game.forces.player,
		})
		runner.assert(roboport and roboport.valid, "could not create the test roboport")

		runner.after_n_ticks_do(1, function()
			local ok, err = pcall(function()
				runner.assert(
					remote.call(
						"planetslib_funit",
						"entity_removal_floors_has_stationary_roboport_coverage",
						surface,
						game.forces.player,
						{ x = 0.5, y = 0.5 }
					),
					"stationary roboport position was not reported as covered"
				)
				runner.assert(
					not remote.call(
						"planetslib_funit",
						"entity_removal_floors_has_stationary_roboport_coverage",
						surface,
						game.forces.player,
						{ x = 100.5, y = 100.5 }
					),
					"position outside the roboport construction area was reported as covered"
				)
			end)
			cleanup_surface(surface)
			if not ok then
				error(err, 0)
			end
		end)
	end)

	runner.test("ERF-11 multi-tile off-grid footprint has no extra edge tiles", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_named_entity(runner, surface, LARGE_ENTITY, { 6.4375, 6.1875 })
			local bounds = remote.call("planetslib_funit", "entity_removal_floors_floor_bounds", entity)
			runner.assert(bounds[1] == 5 and bounds[2] == 7, "the multi-tile x footprint is wrong")
			runner.assert(bounds[3] == 5 and bounds[4] == 7, "the multi-tile y footprint is wrong")

			mark_queued(runner, entity)
			runner.assert(not entity.to_be_deconstructed(), "the multi-tile entity was not queued")
			local entries = queued(surface)
			runner.assert(#entries == 1, "expected exactly one queued entity")
			runner.assert(count_keys(entries[1].remaining) == 9, "the multi-tile floor should have nine tiles")

			for x = 5, 7 do
				for y = 5, 7 do
					runner.assert(
						tile_ghost_names(surface, { x, y })[SAFE_TILE],
						"missing floor ghost at (" .. x .. ", " .. y .. ")"
					)
				end
			end
			runner.assert(
				not tile_ghost_names(surface, { 4, 5 })[SAFE_TILE],
				"an extra floor ghost was created outside the multi-tile footprint"
			)
		end)
	end)

	runner.test("ERF-12 unrelated tile ghost does not satisfy the floor", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 8.5, 8.5 })
			local unrelated = surface.create_entity({
				name = "tile-ghost",
				inner_name = "landfill",
				position = { 8.5, 8.5 },
				force = game.forces.player,
			})
			runner.assert(unrelated and unrelated.valid, "could not create the unrelated tile ghost")

			mark_queued(runner, entity)
			local names = tile_ghost_names(surface, { 8, 8 })
			runner.assert(names[SAFE_TILE], "the unrelated ghost prevented the configured floor ghost")
			runner.assert(names.landfill, "the unrelated ghost was removed")
		end)
	end)

	runner.test("ERF-13 safe floor leaves deconstruction alone", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			set_tile(surface, SAFE_TILE, 10, 10)
			local entity = create_entity(runner, surface, { 10.5, 10.5 })
			mark_queued(runner, entity)

			runner.assert(entity.to_be_deconstructed(), "a safe floor unexpectedly cancelled deconstruction")
			runner.assert(#queued(surface) == 0, "a safe floor was unexpectedly queued")
			runner.assert(not tile_ghost_names(surface, { 10, 10 })[SAFE_TILE], "a safe floor received a ghost")
		end)
	end)

	runner.test("ERF-14 premature re-mark does not duplicate the queue", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 12.5, 12.5 })
			mark_queued(runner, entity)
			local before = queued(surface)
			runner.assert(#before == 1, "the entity was not queued")
			local remaining = count_keys(before[1].remaining)

			mark_queued(runner, entity)
			runner.assert(not entity.to_be_deconstructed(), "the premature re-mark was not cancelled")
			local after = queued(surface)
			runner.assert(#after == 1, "the premature re-mark duplicated the queue")
			runner.assert(count_keys(after[1].remaining) == remaining, "the outstanding floor tiles changed")
			runner.assert(
				count_tile_ghosts(surface, { 12, 12 }, SAFE_TILE) == 1,
				"the premature re-mark duplicated the floor ghost"
			)
		end)
	end)

	runner.test("ERF-15 losing floor cancels a marked entity", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			set_tile(surface, SAFE_TILE, 14, 14)
			local entity = create_entity(runner, surface, { 14.5, 14.5 })
			mark_queued(runner, entity)
			runner.assert(entity.to_be_deconstructed(), "the entity was not marked on a safe floor")

			set_tile(surface, UNSAFE_TILE, 14, 14)
			remote.call("planetslib_funit", "entity_removal_floors_on_tile_mined", {
				surface_index = surface.index,
				tiles = { { position = { x = 14, y = 14 } } },
			})

			runner.assert(entity.valid, "the entity disappeared when its tile changed")
			runner.assert(not entity.to_be_deconstructed(), "losing the safe floor did not cancel deconstruction")
			runner.assert(#queued(surface) == 0, "losing the safe floor unexpectedly queued the entity")
		end)
	end)

	runner.test("ERF-16 unconfigured planets are ignored", function()
		local surface = game.surfaces["nauvis"]
		surface.request_to_generate_chunks({ 200, 200 }, 1)
		surface.force_generate_chunk_requests()
		local entity = create_named_entity(runner, surface, ENTITY, { 200.5, 200.5 })
		local ok, err = pcall(function()
			mark_queued(runner, entity)
			runner.assert(entity.to_be_deconstructed(), "an unconfigured planet cancelled deconstruction")
			runner.assert(#queued(surface) == 0, "an unconfigured planet was queued")
		end)
		pcall(function()
			entity.destroy({ raise_destroy = true })
		end)
		if not ok then
			error(err, 0)
		end
	end)

	runner.test("ERF-17 destroying a queued entity clears its queue", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 16.5, 16.5 })
			mark_queued(runner, entity)
			runner.assert(#queued(surface) == 1, "the entity was not queued")
			runner.assert(tile_ghost_names(surface, { 16, 16 })[SAFE_TILE], "the queue did not create a ghost")

			entity.destroy({ raise_destroy = true })
			remote.call("planetslib_funit", "entity_removal_floors_prune_invalid_entries")

			runner.assert(#queued(surface) == 0, "the destroyed queued entity was not pruned")
			runner.assert(
				not tile_ghost_names(surface, { 16, 16 })[SAFE_TILE],
				"pruning the destroyed entity left its floor ghost"
			)
		end)
	end)

	runner.test("ERF-18 queued floor uses the selected replacement tile", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local entity = create_entity(runner, surface, { 18.5, 18.5 })
			local index = remote.call(
				"planetslib_funit",
				"entity_removal_floors_queue_entity",
				entity,
				"player",
				nil,
				"landfill"
			)
			runner.assert(index, "could not queue the entity with a non-default tile")

			local entries = queued(surface)
			runner.assert(#entries == 1, "the non-default tile entity was not queued")
			runner.assert(entries[1].replacement_tile == "landfill", "the queued replacement tile is wrong")
			runner.assert(tile_ghost_names(surface, { 18, 18 }).landfill, "the non-default ghost was not created")
			runner.assert(not tile_ghost_names(surface, { 18, 18 })[SAFE_TILE], "the default ghost was created")

			set_tile(surface, "landfill", 18, 18)
			remote.call("planetslib_funit", "entity_removal_floors_on_tile_built", {
				surface_index = surface.index,
				tile = { name = "landfill" },
				tiles = { { position = { x = 18, y = 18 } } },
			}, "robot")

			runner.assert(#queued(surface) == 0, "the non-default floor queue was not completed")
			local pending = cleanup(surface)
			runner.assert(#pending == 1, "the robot-built non-default floor was not queued for cleanup")
			runner.assert(pending[1].tile_name == "landfill", "the pending cleanup has the wrong tile")
		end)
	end)

	runner.test("ERF-19 construction robots deliver drops and remove the temporary floor", function()
		local surface = prepare_surface(runner)
		local old_speed = game.speed
		game.speed = 10
		local cleanup_done = false
		local entity
		local storage_chest

		local function finish()
			if cleanup_done then
				return
			end
			cleanup_done = true
			game.speed = old_speed
			cleanup_surface(surface)
		end

		local setup_ok, setup_err = pcall(function()
			entity = create_named_entity(runner, surface, DROP_ENTITY, { 12.5, 12.5 })
			if not surface.has_global_electric_network then
				surface.create_global_electric_network()
			end

			local energy_interface = surface.create_entity({
				name = "electric-energy-interface",
				position = { 16.5, 12.5 },
				force = game.forces.player,
			})
			runner.assert(energy_interface and energy_interface.valid, "could not create the test power source")
			energy_interface.power_production = 100000000

			local roboport = surface.create_entity({
				name = "roboport",
				position = { 16.5, 14.5 },
				force = game.forces.player,
			})
			runner.assert(roboport and roboport.valid, "could not create the test roboport")
			local provider = surface.create_entity({
				name = "passive-provider-chest",
				position = { 18.5, 12.5 },
				force = game.forces.player,
			})
			runner.assert(provider and provider.valid, "could not create the test provider chest")
			storage_chest = surface.create_entity({
				name = "storage-chest",
				position = { 20.5, 12.5 },
				force = game.forces.player,
			})
			runner.assert(storage_chest and storage_chest.valid, "could not create the test storage chest")

			provider.insert({ name = SAFE_ITEM, count = 50 })
			-- The copied tile keeps its original landfill build item.
			provider.insert({ name = "landfill", count = 50 })
			local robot_inventory = roboport.get_inventory(defines.inventory.roboport_robot)
			runner.assert(robot_inventory, "the test roboport has no robot inventory")
			runner.assert(
				robot_inventory.insert({ name = "construction-robot", count = 20 }) == 20,
				"could not insert construction robots"
			)

			mark_queued(runner, entity)
			runner.assert(not entity.to_be_deconstructed(), "the robot test entity was not queued")
		end)

		if not setup_ok then
			finish()
			error(setup_err, 0)
		end

		wait_until(runner, function()
			local debug_inventory = storage_chest and storage_chest.valid and storage_chest.get_inventory(defines.inventory.chest)
			if entity.valid then
				return false
			end

			local inventory = storage_chest and storage_chest.valid
				and storage_chest.get_inventory(defines.inventory.chest)
			if not inventory then
				return false
			end
			if inventory.get_item_count("stone") < 15 or inventory.get_item_count("sulfur") < 2 then
				return false
			end

			local tile = surface.get_tile(12, 12)
			if not tile or not tile.valid or tile.name ~= UNSAFE_TILE then
				return false
			end
			return true
		end, {
			timeout = 9000,
			interval = 30,
			message = "construction robots did not deliver drops and remove the temporary floor",
			on_success = finish,
			on_failure = finish,
		})
	end)

	runner.test("ERF-21 selected floor tile is buildable on the unsafe tile", function()
		local surface = prepare_surface(runner)
		run_with_cleanup(function()
			cleanup_surface(surface)
		end, function()
			local x, y = 20, 20
			set_tile(surface, "funit-erf-foundation-only", x, y)

			local function can_build(tile_name)
				return surface.can_place_entity({
					name = "tile-ghost",
					inner_name = tile_name,
					position = { x + 0.5, y + 0.5 },
				})
			end

			runner.assert(not can_build(SAFE_TILE), "fixture error: the default tile should not be buildable here")
			runner.assert(can_build("foundation"), "fixture error: the foundation should be buildable here")

			local selected = remote.call(
				"planetslib_funit",
				"entity_removal_floors_select_replacement_tile_for_tile",
				{
					{ name = SAFE_ITEM, count = 1 },
					{ name = "foundation", count = 1 },
				},
				1,
				1,
				false,
				true,
				SAFE_TILE,
				SAFE_ITEM,
				surface.index,
				x,
				y
			)
			runner.assert(selected == "foundation", "expected the buildable foundation, got " .. tostring(selected))
			runner.assert(can_build(selected), "the selected replacement tile is not buildable on the unsafe tile")

			local entity = create_entity(runner, surface, { x + 0.5, y + 0.5 })
			local index = remote.call(
				"planetslib_funit",
				"entity_removal_floors_queue_entity",
				entity,
				"player",
				nil,
				selected
			)
			runner.assert(index, "could not queue the entity with the selected floor")
			runner.assert(
				tile_ghost_names(surface, { x, y }).foundation,
				"the queued floor did not use the buildable foundation"
			)
		end)
	end)

	runner.test("ERF-20 removes the test surface", function()
		local surface = prepared_surface
		prepared_surface = nil
		if surface and surface.valid then
			pcall(function()
				remote.call("planetslib_funit", "entity_removal_floors_clear_surface_state", surface.index)
			end)
			pcall(function()
				surface.clear(true)
			end)
			pcall(function()
				game.delete_surface(surface)
			end)
		end
	end)
end
