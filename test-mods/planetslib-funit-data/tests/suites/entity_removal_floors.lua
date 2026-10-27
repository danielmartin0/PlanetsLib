-- Entity removal floors: runtime queueing, tile ghosts, reissued deconstruction
-- and temporary-floor cleanup.

local support = require("__planetslib-funit-data__.tests.suites.support")

local PLANET = "funit-erf-planet"
local PLANET_B = "funit-erf-planet-b"
local ENTITY = "funit-erf-rock"
local ENTITY_B = "funit-erf-rock-b"
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

local function create_entity(runner, surface, position)
	local entity = surface.create_entity({
		name = ENTITY,
		position = position,
		force = game.forces.player,
	})
	runner.assert(entity and entity.valid, "could not create the test simple entity")
	return entity
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

			local entries = queued(surface)
			runner.assert(#entries == 1, "expected exactly one queued entity, got " .. #entries)
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

	runner.test("ERF-11 removes the test surface", function()
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
