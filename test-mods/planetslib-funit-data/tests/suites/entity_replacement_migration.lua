-- Entity replacement: migration behavior (ENT-12..ENT-13).
--
-- ENT-12 drives the live rolling-stock upgrade path. ENT-13 exercises the
-- on_configuration_changed entry point and the silent (raise_built = false)
-- replacement path used by migrations. A real "rule added/disabled" migration
-- needs a data-stage change between two saves, so it is recorded as a
-- limitation rather than simulated by mutating PlanetsLib's storage from this
-- mod's Lua environment.

-- `require` is only allowed while the scenario's control.lua is parsed, not
-- from inside an on_tick test callback.
local mock = require("__funit__.mock")

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local FIXTURE_SUITE = "entity_replacement_data"
local SURFACE_NAME = "nauvis"
local AREA_STEP = 80
local AREA_RADIUS = 8
local next_area = 0

local function fixture_entries(runner)
	local bag = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(bag, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	local entries = bag.data[FIXTURE_SUITE]
	runner.assert(entries, "no data-stage results recorded for '" .. FIXTURE_SUITE .. "'")
	for _, id in ipairs({ "ENT-1g", "ENT-2e" }) do
		local entry = entries[id]
		runner.assert(entry, "missing data fixture entry " .. id)
		runner.assert(entry.ok, "data fixture " .. id .. " failed: " .. tostring(entry.err))
	end
	return entries
end

local function require_seam(runner, name)
	local interface = remote.interfaces["planetslib_funit"]
	runner.assert(interface and interface[name], "PlanetsLib did not expose planetslib_funit." .. name)
	return function(...)
		return remote.call("planetslib_funit", name, ...)
	end
end

local function area_box(center, radius)
	return {
		{ center.x - radius, center.y - radius },
		{ center.x + radius, center.y + radius },
	}
end

local function prepare_area(surface, center, radius)
	surface.request_to_generate_chunks(center, 1)
	surface.force_generate_chunk_requests()

	local tiles = {}
	for x = math.floor(center.x - radius), math.floor(center.x + radius) do
		for y = math.floor(center.y - radius), math.floor(center.y + radius) do
			tiles[#tiles + 1] = { name = "landfill", position = { x = x, y = y } }
		end
	end
	surface.set_tiles(tiles, true, true, true, false)
end

local function clear_area(surface, center, radius)
	for _, entity in pairs(surface.find_entities_filtered({ area = area_box(center, radius) })) do
		if entity.valid and entity.type ~= "character" then
			entity.destroy()
		end
	end
end

local function with_area(runner, body)
	fixture_entries(runner)
	local planet = game.planets[SURFACE_NAME]
	runner.assert(planet and planet.surface, "the nauvis surface is missing")
	local surface = planet.surface

	next_area = next_area + 1
	local center = { x = 8000 + next_area * AREA_STEP, y = 4000 }

	local ok, err = pcall(function()
		prepare_area(surface, center, AREA_RADIUS)
		body(surface, center)
	end)
	pcall(clear_area, surface, center, AREA_RADIUS + 6)
	if not ok then
		error(err, 0)
	end
end

local function create_at(surface, name, center)
	local position = surface.find_non_colliding_position(name, center, 6, 0.5)
	if not position then
		return nil, nil
	end
	return surface.create_entity({
		name = name,
		position = position,
		force = game.forces.player,
		create_build_effect_smoke = false,
	}), position
end

local function create_rail(surface, center)
	-- A locomotive is six tiles long, so a single 2-tile rail segment cannot
	-- hold one. Build a short north-south line and return the middle segment.
	-- Rail alignment depends on the rail grid; try a few centre conventions.
	local candidates = {
		{ x = center.x, y = center.y },
		{ x = center.x + 0.5, y = center.y + 0.5 },
		{ x = center.x - 0.5, y = center.y - 0.5 },
		{ x = center.x + 1, y = center.y },
		{ x = center.x, y = center.y + 1 },
	}
	for _, base in ipairs(candidates) do
		local rails = {}
		local complete = true
		for offset = -2, 2 do
			local ok, rail = pcall(function()
				return surface.create_entity({
					name = "straight-rail",
					position = { x = base.x, y = base.y + offset * 2 },
					direction = defines.direction.north,
					force = game.forces.player,
				})
			end)
			if not (ok and rail and rail.valid) then
				log("[funit] rail candidate " .. tostring(base.x) .. "," .. tostring(base.y)
					.. " offset " .. offset .. " failed: " .. tostring(ok and "nil/invalid" or rail))
				complete = false
				break
			end
			rails[#rails + 1] = rail
		end
		if complete then
			return rails[3]
		end
		for _, rail in ipairs(rails) do
			if rail.valid then
				rail.destroy()
			end
		end
	end
	return nil
end

local function find(surface, name, position, radius)
	local entities = surface.find_entities_filtered({
		name = name,
		position = position,
		radius = radius or 1.5,
	})
	return entities[1]
end

return function(runner)
	runner.test("ENT-12 rolling-stock replacement preserves the locomotive state", function()
		local replace_entity = require_seam(runner, "replace_entity")

		with_area(runner, function(surface, center)
			local rail = create_rail(surface, center)
			runner.assert(rail and rail.valid, "could not create a straight rail for the locomotive")

			local ok, locomotive = pcall(function()
				return surface.create_entity({
					name = "locomotive",
					position = rail.position,
					direction = rail.direction,
					force = game.forces.player,
				})
			end)
			runner.assert(ok and locomotive and locomotive.valid, "could not create a locomotive on the test rail")

			local position = locomotive.position
			local orientation = locomotive.orientation
			locomotive.insert({ name = "coal", count = 7 })
			runner.assert(
				locomotive.get_inventory(defines.inventory.fuel).get_item_count("coal") == 7,
				"could not fill the locomotive fuel inventory"
			)
			runner.assert(
				prototypes.entity["locomotive"].fast_replaceable_group
					== prototypes.entity["locomotive-PlanetsLib-nauvis"].fast_replaceable_group,
				"the locomotive variant has a different fast_replaceable_group"
			)
			replace_entity(locomotive, "locomotive-PlanetsLib-nauvis", false)

			local new = find(surface, "locomotive-PlanetsLib-nauvis", position, 2)
			runner.assert(new and new.valid, "the locomotive was not replaced by its nauvis variant")
			runner.assert(not locomotive.valid, "the old locomotive was not removed")
			runner.assert(
				math.abs(new.orientation - orientation) < 1e-3,
				"the replacement locomotive changed orientation"
			)
			runner.assert(new.train ~= nil, "the replacement locomotive is not on a train")
			runner.assert(
				new.get_inventory(defines.inventory.fuel).get_item_count("coal") == 7,
				"the locomotive fuel inventory was not transferred"
			)
		end)
	end)

	runner.test("ENT-13a on_configuration_changed runs without spurious replacements", function()
		local on_configuration_changed = require_seam(runner, "on_configuration_changed")

		with_area(runner, function(surface, center)
			local iron, iron_position = create_at(surface, "iron-chest", center)
			runner.assert(iron and iron.valid, "could not create the already-compliant iron chest")
			local wood, wood_position = create_at(
				surface,
				"wooden-chest",
				{ x = center.x + 4, y = center.y }
			)
			runner.assert(wood and wood.valid, "could not create the wooden chest")

			-- No replacement rule changed between saves, so this must be a no-op.
			local ok, err = pcall(on_configuration_changed, {
				mod_changes = {},
			})
			runner.assert(
				ok,
				"on_configuration_changed raised an error: "
					.. tostring(err)
					.. " (suspected non-string planet key from assign_entity_replacement's planet-table form; "
					.. "see lib/add-entity-replacement.lua:16-23)"
			)

			runner.assert(iron.valid, "the migration replaced an entity that already matched the rule")
			runner.assert(wood.valid, "the migration replaced an entity although no rule changed")
			local wood_again = find(surface, "wooden-chest", wood_position)
			local iron_again = find(surface, "iron-chest", iron_position)
			runner.assert(wood_again and wood_again.unit_number == wood.unit_number,
				"the wooden chest moved or was recreated")
			runner.assert(iron_again and iron_again.unit_number == iron.unit_number,
				"the iron chest moved or was recreated")
		end)
	end)

	runner.test("ENT-13b migration replacements are silent (raise_built = false)", function()
		local replace_entity = require_seam(runner, "replace_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "wooden-chest", center)
			runner.assert(old and old.valid, "could not create the source chest")

			local built_events = 0
			-- Do not clobber PlanetsLib's own script_raised_built handler: save it
			-- and restore it after the check.
			local previous_built_handler = script.get_event_handler(defines.events.script_raised_built)
			script.on_event(defines.events.script_raised_built, function()
				built_events = built_events + 1
			end)

			local ok, err = pcall(function()
				replace_entity(old, "iron-chest", false)
			end)

			script.on_event(defines.events.script_raised_built, previous_built_handler)

			runner.assert(ok, "the silent replacement raised: " .. tostring(err))
			local new = find(surface, "iron-chest", position)
			runner.assert(new and new.valid, "the chest was not replaced")
			runner.assert(not old.valid, "the old chest was not removed")
			runner.assert(
				built_events == 0,
				"replace_entity(..., false) raised script_raised_built " .. built_events .. " time(s)"
			)
		end)
	end)

	runner.test("ENT-13c added/disabled rule migration requires a second save", function()
		fixture_entries(runner)
		runner.log(
			"ENT-13c limitation: exercising a real added/disabled entity replacement rule requires two saves with "
				.. "different startup settings; this scenario only loads one. The rule-change comparison and the "
				.. "silent migration replacement path are covered by ENT-13a and ENT-13b."
		)
		runner.assert(true)
	end)
end
