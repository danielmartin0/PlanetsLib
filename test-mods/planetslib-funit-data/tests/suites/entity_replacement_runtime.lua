-- Entity replacement: runtime behavior (ENT-5..ENT-14).
--
-- These tests build real entities on nauvis, drive PlanetsLib's control-stage
-- handler through the `planetslib_funit` seam, and assert the transfer of
-- state. Every test prepares its own landfill area and clears it afterwards.
-- In the CI no-replacements scenario the global kill switch is on, so the
-- tests that normally expect a replacement instead assert the entity was left
-- untouched (ENT-14 pins the kill switch itself).

-- `require` is only allowed while the scenario's control.lua is parsed, not
-- from inside an on_tick test callback.
local mock = require("__funit__.mock")
local support = require("__planetslib-funit-data__.tests.suites.support")

local FIXTURE_SUITE = "entity_replacement_data"
local SURFACE_NAME = "nauvis"
local DISABLE_ALL_SETTING = "PlanetsLib-disable-all-entity-replacements"
local AREA_STEP = 80
local AREA_RADIUS = 8
local next_area = 0

local function fixture_entries(runner)
	support.assert_all(runner, FIXTURE_SUITE, { expected = { "ENT-1g", "ENT-2e" } })
	return support.entries(runner, FIXTURE_SUITE)
end

local function seam(name)
	local interface = remote.interfaces["planetslib_funit"]
	if not interface or not interface[name] then
		return nil
	end
	return function(...)
		return remote.call("planetslib_funit", name, ...)
	end
end

local function require_seam(runner, name)
	local call = seam(name)
	runner.assert(call, "PlanetsLib did not expose planetslib_funit." .. name)
	return call
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
	-- Remove trees/cliffs/enemies so the test entities have a clear pad.
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
	local center = { x = 4000 + next_area * AREA_STEP, y = 4000 }

	local ok, err = pcall(function()
		prepare_area(surface, center, AREA_RADIUS)
		-- Map generation can leave trees, rocks or cliffs inside the landfill
		-- area; clear them before each test so entity placement is deterministic.
		clear_area(surface, center, AREA_RADIUS)
		body(surface, center)
	end)
	pcall(clear_area, surface, center, AREA_RADIUS + 4)
	if not ok then
		error(err, 0)
	end
end

local function create_at(surface, name, center, extra, search_name)
	local position = surface.find_non_colliding_position(search_name or name, center, 6, 0.5)
	if not position then
		return nil, nil
	end
	local params = {
		name = name,
		position = position,
		force = game.forces.player,
		create_build_effect_smoke = false,
	}
	for key, value in pairs(extra or {}) do
		params[key] = value
	end
	return surface.create_entity(params), position
end

local function find(surface, name, position, radius)
	local entities = surface.find_entities_filtered({
		name = name,
		position = position,
		radius = radius or 1.5,
	})
	return entities[1]
end

local function replacements_disabled()
	local setting = settings.startup[DISABLE_ALL_SETTING]
	return setting ~= nil and setting.value == true
end

local function count_ground_items(surface, position, radius, item_name)
	local total = 0
	for _, entity in pairs(surface.find_entities_filtered({
		name = "item-on-ground",
		position = position,
		radius = radius,
	})) do
		if entity.valid and entity.stack and entity.stack.name == item_name then
			total = total + entity.stack.count
		end
	end
	return total
end

local function connector_has(connector, owner, connector_id)
	local owner_unit_number = owner.unit_number
	for _, connection in pairs(connector.connections) do
		local target_owner = connection.target.owner
		if target_owner
			and target_owner.valid
			and target_owner.unit_number == owner_unit_number
			and connection.target.wire_connector_id == connector_id then
			return true
		end
	end
	return false
end

return function(runner)
	runner.test("ENT-5a placing a ruled entity replaces it and transfers inventory", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "wooden-chest", center)
			runner.assert(old and old.valid, "could not create the source wooden chest")
			old.insert({ name = "iron-plate", count = 17 })

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the wooden chest in place")
				runner.assert(
					old.get_inventory(defines.inventory.chest).get_item_count("iron-plate") == 17,
					"the global kill switch should preserve the chest inventory"
				)
				runner.assert(
					find(surface, "iron-chest", position) == nil,
					"the global kill switch still replaced the wooden chest"
				)
				return
			end

			runner.assert(not old.valid, "the source wooden chest was not destroyed")
			local new = find(surface, "iron-chest", position)
			runner.assert(new and new.valid, "the wooden chest was not replaced by an iron chest")
			runner.assert(new.name == "iron-chest", "the replacement has the wrong name")
			runner.assert(
				new.get_inventory(defines.inventory.chest).get_item_count("iron-plate") == 17,
				"the chest inventory was not transferred"
			)
		end)
	end)

	runner.test("ENT-5b ghost replacement preserves ghost type and tags", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local ghost, position = create_at(
				surface,
				"entity-ghost",
				center,
				{ inner_name = "wooden-chest", tags = { funit = "ent-ghost" } },
				"wooden-chest"
			)
			runner.assert(ghost and ghost.valid, "could not create the wooden-chest ghost")
			runner.assert(ghost.ghost_name == "wooden-chest", "the test ghost has the wrong inner name")

			on_built_entity({ entity = ghost }, nil, false)

			if replacements_disabled() then
				runner.assert(ghost.valid, "the global kill switch should leave the wooden-chest ghost in place")
				runner.assert(
					ghost.ghost_name == "wooden-chest",
					"the global kill switch changed the ghost's inner name"
				)
				return
			end

			runner.assert(not ghost.valid, "the source ghost was not destroyed")
			local new = find(surface, "entity-ghost", position)
			runner.assert(new and new.valid, "the ghost was not replaced")
			runner.assert(new.name == "entity-ghost", "the replacement is not a ghost")
			runner.assert(new.ghost_name == "iron-chest", "the ghost did not switch to the replacement entity")
			runner.assert(
				new.tags and new.tags.funit == "ent-ghost",
				"the ghost's tags were not preserved"
			)
		end)
	end)

	runner.test("ENT-5c robot-built entities go through the same replacement path", function()
		runner.assert(
			remote.interfaces["__funit_mock_event__PlanetsLib"],
			"PlanetsLib is not registered with FUnit's event mocker"
		)

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "wooden-chest", center)
			runner.assert(old and old.valid, "could not create the robot-built source chest")

			local ok, err = pcall(mock.mock_event, {
				name = defines.events.on_robot_built_entity,
				entity = old,
			})
			runner.assert(ok, "mocking on_robot_built_entity raised: " .. tostring(err))

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the robot-built chest in place")
				runner.assert(
					find(surface, "iron-chest", position) == nil,
					"the global kill switch still replaced the robot-built chest"
				)
				return
			end

			runner.assert(not old.valid, "the robot-built chest was not replaced")
			local new = find(surface, "iron-chest", position)
			runner.assert(new and new.valid, "the robot-built chest was not replaced by an iron chest")
		end)
	end)

	runner.test("ENT-5d placing a vehicle ghost preserves its orientation", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			-- A vehicle ghost reports direction as north and ignores
			-- orientation writes, so the smooth orientation has to be supplied
			-- when the ghost is created.
			local orientation = 0.3
			local ghost, position = create_at(
				surface,
				"entity-ghost",
				center,
				{ inner_name = "car", orientation = orientation },
				"car"
			)
			runner.assert(ghost and ghost.valid, "could not create the car ghost")
			runner.assert(ghost.ghost_name == "car", "the test ghost has the wrong inner name")
			runner.assert(
				math.abs(ghost.orientation - orientation) < 1e-4,
				"the engine did not apply the requested orientation to the car ghost"
			)

			on_built_entity({ entity = ghost }, nil, false)

			if replacements_disabled() then
				runner.assert(ghost.valid, "the global kill switch should leave the car ghost in place")
				runner.assert(ghost.ghost_name == "car", "the global kill switch changed the car ghost's inner name")
				return
			end

			runner.assert(not ghost.valid, "the source car ghost was not destroyed")
			local new = find(surface, "entity-ghost", position)
			runner.assert(new and new.valid, "the car ghost was not replaced")
			runner.assert(
				new.ghost_name == "car-PlanetsLib-nauvis",
				"the car ghost did not switch to the replacement entity"
			)
			runner.assert(
				math.abs(new.orientation - orientation) < 1e-4,
				"the vehicle ghost's orientation was not preserved"
			)
		end)
	end)

	runner.test("ENT-6a recipe, crafting progress, products and health transfer", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			-- Use assembling machines: LuaEntity::set_recipe/get_recipe are
			-- assembly-machine APIs (furnaces reject set_recipe even though the
			-- method exists on LuaEntity).
			local old, position = create_at(surface, "assembling-machine-3", center)
			runner.assert(old and old.valid, "could not create the source assembling machine")
			old.set_recipe("iron-gear-wheel")
			old.crafting_progress = 0.42
			old.products_finished = 3
			old.health = 75

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the assembling machine in place")
				runner.assert(
					find(surface, "assembling-machine-2", position) == nil,
					"the global kill switch still replaced the assembling machine"
				)
				return
			end

			runner.assert(not old.valid, "the source assembling machine was not destroyed")
			local new = find(surface, "assembling-machine-2", position)
			runner.assert(new and new.valid, "the assembling machine was not replaced")
			local recipe = new.get_recipe()
			runner.assert(recipe and recipe.name == "iron-gear-wheel", "the assembling-machine recipe was not transferred")
			runner.assert(
				math.abs(new.crafting_progress - 0.42) < 1e-4,
				"the crafting progress was not transferred"
			)
			runner.assert(new.products_finished == 3, "the finished-product count was not transferred")
			runner.assert(math.abs(new.health - 75) < 1e-4, "the entity health was not transferred")
		end)
	end)

	runner.test("ENT-6b heat-pipe temperature transfers", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "heat-pipe", center)
			runner.assert(old and old.valid, "could not create the source heat pipe")
			old.temperature = 500

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the heat pipe in place")
				runner.assert(math.abs(old.temperature - 500) < 1e-4, "the kill switch changed the heat pipe temperature")
				runner.assert(
					find(surface, "heat-pipe-PlanetsLib-nauvis", position) == nil,
					"the global kill switch still replaced the heat pipe"
				)
				return
			end

			runner.assert(not old.valid, "the source heat pipe was not destroyed")
			local new = find(surface, "heat-pipe-PlanetsLib-nauvis", position)
			runner.assert(new and new.valid, "the heat pipe was not replaced by its nauvis variant")
			runner.assert(math.abs(new.temperature - 500) < 1e-4, "the heat pipe temperature was not transferred")
		end)
	end)

	runner.test("ENT-7 an existing replacement entity is not replaced again", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local chest, position = create_at(surface, "iron-chest", center)
			runner.assert(chest and chest.valid, "could not create the iron chest")
			local unit_number = chest.unit_number

			on_built_entity({ entity = chest }, nil, false)

			runner.assert(chest.valid, "the replacement entity was replaced again (recursion/normalisation bug)")
			runner.assert(chest.unit_number == unit_number, "the replacement entity was recreated")
			runner.assert(
				find(surface, "wooden-chest", position) == nil,
				"the inverse rule replaced the iron chest with a wooden chest"
			)
		end)
	end)

	runner.test("ENT-8a modules transfer and overflow spills instead of being lost", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "assembling-machine-3", center)
			runner.assert(old and old.valid, "could not create the source assembling machine")
			local modules = old.get_module_inventory()
			runner.assert(modules, "the assembling machine has no module inventory")
			runner.assert(
				modules.insert({ name = "speed-module", count = 3 }) == 3,
				"could not insert the test modules"
			)

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the assembling machine in place")
				runner.assert(
					old.get_module_inventory().get_item_count("speed-module") == 3,
					"the global kill switch should preserve the inserted modules"
				)
				runner.assert(
					find(surface, "assembling-machine-2", position) == nil,
					"the global kill switch still replaced the assembling machine"
				)
				return
			end

			runner.assert(not old.valid, "the source assembling machine was not destroyed")
			local new = find(surface, "assembling-machine-2", position)
			runner.assert(new and new.valid, "the assembling machine was not replaced")
			local new_modules = new.get_module_inventory()
			runner.assert(new_modules, "the replacement assembling machine has no module inventory")
			runner.assert(
				new_modules.get_item_count("speed-module") == 2,
				"the two module slots of the replacement were not filled"
			)

			local in_entity = new_modules.get_item_count("speed-module")
			local on_ground = count_ground_items(surface, position, 6, "speed-module")
			runner.assert(
				in_entity + on_ground == 3,
				"the third module was lost (in entity: " .. in_entity .. ", on ground: " .. on_ground .. ")"
			)
		end)
	end)

	runner.test("ENT-8b get_replacement maps the old unit number to the replacement", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "wooden-chest", center)
			runner.assert(old and old.valid, "could not create the source chest")
			local old_unit_number = old.unit_number

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the chest in place")
				runner.assert(find(surface, "iron-chest", position) == nil,
					"the global kill switch still replaced the chest")
				local replacement = remote.call("planetslib_entity_replacement", "get_replacement", old_unit_number)
				runner.assert(
					replacement == nil,
					"get_replacement returned an entity although the global kill switch prevented replacement"
				)
				return
			end

			local new = find(surface, "iron-chest", position)
			runner.assert(new and new.valid, "the chest was not replaced")
			local replacement = remote.call("planetslib_entity_replacement", "get_replacement", old_unit_number)
			runner.assert(
				replacement ~= nil
					and replacement.valid
					and replacement.unit_number == new.unit_number,
				"get_replacement(old_unit_number) must return the replacement entity "
					.. "(documented in docs-source/docs/usage-documentation/entity-replacement-system.md)"
			)
		end)
	end)

	runner.test("ENT-9 fluidbox contents transfer between storage tanks", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "storage-tank", center)
			runner.assert(old and old.valid, "could not create the source storage tank")
			old.insert_fluid({ name = "water", amount = 1234 })

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the storage tank in place")
				local fluid = old.get_fluid(1)
				runner.assert(fluid and fluid.name == "water", "the kill switch lost the stored fluid")
				runner.assert(
					find(surface, "storage-tank-PlanetsLib-nauvis", position) == nil,
					"the global kill switch still replaced the storage tank"
				)
				return
			end

			runner.assert(not old.valid, "the source storage tank was not destroyed")
			local new = find(surface, "storage-tank-PlanetsLib-nauvis", position)
			runner.assert(new and new.valid, "the storage tank was not replaced by its nauvis variant")
			local fluid = new.get_fluid(1)
			runner.assert(fluid and fluid.name == "water", "the stored fluid was not transferred")
			runner.assert(math.abs(fluid.amount - 1234) < 1e-3, "the transferred fluid amount is wrong")
		end)
	end)

	runner.test("ENT-10a wire connections, including self-references, are copied", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "arithmetic-combinator", center)
			runner.assert(old and old.valid, "could not create the source combinator")
			local other, other_position = create_at(
				surface,
				"arithmetic-combinator",
				{ x = center.x + 4, y = center.y }
			)
			runner.assert(other and other.valid, "could not create the target combinator")

			local output = old.get_wire_connector(defines.wire_connector_id.combinator_output_red, true)
			local input = old.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
			local other_input =
				other.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
			runner.assert(output and input and other_input, "the combinators are missing red wire connectors")
			runner.assert(output.connect_to(other_input, true), "could not connect the external red wire")
			runner.assert(output.connect_to(input, true), "could not connect the self-referential red wire")

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the combinator in place")
				runner.assert(other.valid, "the global kill switch destroyed the other combinator")
				runner.assert(
					connector_has(output, other, defines.wire_connector_id.combinator_input_red),
					"the kill switch lost the external red wire"
				)
				runner.assert(
					connector_has(output, old, defines.wire_connector_id.combinator_input_red),
					"the kill switch lost the self-referential red wire"
				)
				runner.assert(
					find(surface, "arithmetic-combinator-PlanetsLib-nauvis", position) == nil,
					"the global kill switch still replaced the combinator"
				)
				return
			end

			runner.assert(not old.valid, "the source combinator was not destroyed")
			local new = find(surface, "arithmetic-combinator-PlanetsLib-nauvis", position)
			runner.assert(new and new.valid, "the combinator was not replaced by its nauvis variant")
			local new_output =
				new.get_wire_connector(defines.wire_connector_id.combinator_output_red, true)
			local new_input = new.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
			runner.assert(new_output and new_input, "the replacement combinator is missing red wire connectors")
			runner.assert(
				connector_has(new_output, other, defines.wire_connector_id.combinator_input_red),
				"the external red wire was not copied"
			)
			runner.assert(
				connector_has(new_output, new, defines.wire_connector_id.combinator_input_red),
				"the self-referential red wire was not copied"
			)
		end)
	end)

	runner.test("ENT-10b equipment grid contents, including ghosts, transfer", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "spidertron", center)
			runner.assert(old and old.valid, "could not create the source spidertron")
			local solar = old.grid.put({
				name = "solar-panel-equipment",
				quality = "normal",
				position = { 0, 0 },
			})
			local ghost = old.grid.put({
				name = "solar-panel-equipment",
				quality = "normal",
				position = { 2, 0 },
				ghost = true,
			})
			runner.assert(solar, "could not insert the real solar panel equipment")
			runner.assert(ghost, "could not insert the ghost solar panel equipment")

			on_built_entity({ entity = old }, nil, false)

			if replacements_disabled() then
				runner.assert(old.valid, "the global kill switch should leave the spidertron in place")
				runner.assert(
					old.grid.count("solar-panel-equipment") >= 1,
					"the global kill switch lost the grid equipment"
				)
				runner.assert(
					find(surface, "spidertron-PlanetsLib-nauvis", position, 2) == nil,
					"the global kill switch still replaced the spidertron"
				)
				return
			end

			runner.assert(not old.valid, "the source spidertron was not destroyed")
			local new = find(surface, "spidertron-PlanetsLib-nauvis", position, 2)
			runner.assert(new and new.valid, "the spidertron was not replaced by its nauvis variant")
			runner.assert(
				new.grid.count("solar-panel-equipment") >= 1,
				"the real grid equipment was not transferred"
			)

			local found_ghost = false
			for _, equipment in pairs(new.grid.equipment) do
				if equipment.name == "equipment-ghost"
					and equipment.ghost_name == "solar-panel-equipment" then
					found_ghost = true
				end
			end
			runner.assert(found_ghost, "the ghost grid equipment was not transferred")
		end)
	end)

	runner.test("ENT-11a PlanetsLib-on-entity-replaced carries both entities", function()
		local on_built_entity = require_seam(runner, "on_built_entity")
		local event = prototypes.custom_event["PlanetsLib-on-entity-replaced"]
		runner.assert(event, "the PlanetsLib-on-entity-replaced custom event is missing")

		local captured
		script.on_event(event.event_id, function(data)
			captured = {
				old_name = data.entity and data.entity.name,
				old_unit_number = data.entity and data.entity.unit_number,
				new_name = data.new_entity and data.new_entity.name,
				new_unit_number = data.new_entity and data.new_entity.unit_number,
			}
		end)

		local ok, err = pcall(function()
			with_area(runner, function(surface, center)
				local old, position = create_at(surface, "wooden-chest", center)
				runner.assert(old and old.valid, "could not create the source chest")
				local old_unit_number = old.unit_number

				on_built_entity({ entity = old }, nil, false)

				if replacements_disabled() then
					runner.assert(old.valid, "the global kill switch should leave the chest in place")
					runner.assert(
						find(surface, "iron-chest", position) == nil,
						"the global kill switch still replaced the chest"
					)
					runner.assert(
						captured == nil,
						"PlanetsLib-on-entity-replaced fired although the global kill switch is on"
					)
					return
				end

				local new = find(surface, "iron-chest", position)
				runner.assert(new and new.valid, "the chest was not replaced")
				runner.assert(captured, "the PlanetsLib-on-entity-replaced event did not fire")
				runner.assert(captured.old_name == "wooden-chest", "the event's entity field is wrong")
				runner.assert(
					captured.old_unit_number == old_unit_number,
					"the event's entity is not the entity about to be deleted"
				)
				runner.assert(captured.new_name == "iron-chest", "the event's new_entity field is wrong")
				runner.assert(
					captured.new_unit_number == new.unit_number,
					"the event's new_entity is not the replacement entity"
				)
			end)
		end)

		pcall(script.on_event, event.event_id, nil)
		if not ok then
			error(err, 0)
		end
	end)

	runner.test("ENT-11b a disabled rule leaves the entity untouched", function()
		local on_built_entity = require_seam(runner, "on_built_entity")

		with_area(runner, function(surface, center)
			local belt, position = create_at(surface, "transport-belt", center)
			runner.assert(belt and belt.valid, "could not create the transport belt")
			local unit_number = belt.unit_number

			on_built_entity({ entity = belt }, nil, false)

			runner.assert(belt.valid, "a disabled rule replaced the transport belt")
			runner.assert(belt.unit_number == unit_number, "a disabled rule recreated the transport belt")
			runner.assert(
				find(surface, "fast-transport-belt", position) == nil,
				"the disabled rule still produced a fast transport belt"
			)
		end)
	end)

	runner.test("ENT-14 the global kill switch disables on_built_entity replacement", function()
		local on_built_entity = require_seam(runner, "on_built_entity")
		local disable_all = replacements_disabled()

		with_area(runner, function(surface, center)
			local chest, position = create_at(surface, "wooden-chest", center)
			runner.assert(chest and chest.valid, "could not create the source wooden chest")

			on_built_entity({ entity = chest })

			if disable_all then
				runner.assert(
					chest.valid and chest.name == "wooden-chest",
					"PlanetsLib-disable-all-entity-replacements did not stop the replacement"
				)
				runner.assert(
					find(surface, "iron-chest", position) == nil,
					"the global kill switch still produced an iron chest"
				)
			else
				runner.assert(not chest.valid, "the wooden chest was not replaced although replacements are enabled")
				local new = find(surface, "iron-chest", position)
				runner.assert(new and new.valid, "the wooden chest was not replaced by an iron chest")
			end
		end)
	end)
end
