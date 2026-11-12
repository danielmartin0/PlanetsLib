local Public = {}
local rro = require("__PlanetsLib__.lib.remove-replace-object")

-- Forked from Maraxsis, which was ported from Muluna.
-- "PlanetsLib-build", "PlanetsLib-build-ghost" and "PlanetsLib-super-forced-build"
-- are custom inputs that are linked to the build/rotate game controls.
--
-- Ground diggers share one prototype per mining drill across all planets, so the
-- planet's recipe cannot be baked into the prototype. It is assigned when the digger
-- is built (see on_entity_built). Ghosts cannot store a script-set recipe, so they are
-- converted into recipe-bearing diggers when they are later built.
--
-- Builds from remote view always place digger ghosts, without a reach limit, so that
-- players can plan diggers remotely (e.g. from the map view).

-- Set of ground digger prototype names, used to recognise digger builds.
local digger_names = {}
local digger_batches = {}
for _, config in pairs(PlanetsLib.constants.ground_diggers) do
	for _, info in pairs(config.diggers or {}) do
		digger_names[info.digger] = true
		digger_batches[info.digger] = info.full_belt_stacks == true
	end
end

-- Only prototypes that still exist can be used in find_entities_filtered.
local digger_name_list = {}
for digger_name in pairs(digger_names) do
	if prototypes.entity[digger_name] then
		digger_name_list[#digger_name_list + 1] = digger_name
	end
end

local STORAGE_VERSION = 1

local function ensure_storage()
	if not storage.ground_diggers then
		storage.ground_diggers = {
			version = STORAGE_VERSION,
			rebuilt = false,
			by_unit = {},
			by_force = {},
		}
	else
		storage.ground_diggers.version = storage.ground_diggers.version or STORAGE_VERSION
		storage.ground_diggers.by_unit = storage.ground_diggers.by_unit or {}
		storage.ground_diggers.by_force = storage.ground_diggers.by_force or {}
	end
	return storage.ground_diggers
end

local function add_unit_to_force_bucket(entry)
	local bucket = storage.ground_diggers.by_force[entry.force_name]
	if not bucket then
		bucket = {}
		storage.ground_diggers.by_force[entry.force_name] = bucket
	end
	bucket[entry.unit_number] = true
end

local function remove_unit_from_force_bucket(entry)
	local bucket = storage.ground_diggers.by_force[entry.force_name]
	if bucket then
		bucket[entry.unit_number] = nil
		if next(bucket) == nil then
			storage.ground_diggers.by_force[entry.force_name] = nil
		end
	end
end

local function move_entry_to_force(entry, force_name)
	if entry.force_name == force_name then
		return
	end
	remove_unit_from_force_bucket(entry)
	entry.force_name = force_name
	add_unit_to_force_bucket(entry)
end

local function remove_entry(entry)
	if not entry then
		return
	end
	remove_unit_from_force_bucket(entry)
	storage.ground_diggers.by_unit[entry.unit_number] = nil
end

---Registers a ground digger in the per-force storage table.
local function register_entity(entity, base_recipe)
	if not (entity and entity.valid and entity.unit_number and digger_names[entity.name]) then
		return nil
	end
	ensure_storage()
	local existing = storage.ground_diggers.by_unit[entity.unit_number]
	if existing then
		existing.entity = entity
		if base_recipe ~= nil then
			existing.base_recipe = base_recipe
		end
		existing.planet_name = entity.surface.planet and entity.surface.planet.name or nil
		move_entry_to_force(existing, entity.force.name)
		return existing
	end
	local entry = {
		unit_number = entity.unit_number,
		entity = entity,
		base_recipe = base_recipe,
		force_name = entity.force.name,
		planet_name = entity.surface.planet and entity.surface.planet.name or nil,
	}
	storage.ground_diggers.by_unit[entity.unit_number] = entry
	add_unit_to_force_bucket(entry)
	return entry
end

local function unregister_entity(entity)
	if not (entity and entity.unit_number) then
		return
	end
	ensure_storage()
	local entry = storage.ground_diggers.by_unit[entity.unit_number]
	if entry then
		remove_entry(entry)
	end
end

local function is_allowed_on_planet(config, entity_name)
	for _, info in pairs(config.diggers or {}) do
		if info.digger == entity_name then
			return true
		end
	end
	return false
end

local function resolve_base_recipe(entry)
	local entity = entry.entity
	if not (entity and entity.valid) then
		return nil
	end
	local planet = entity.surface and entity.surface.planet
	local config = planet and PlanetsLib.constants.ground_diggers[planet.name]
	if config and config.recipe and is_allowed_on_planet(config, entity.name) then
		entry.planet_name = planet.name
		return config.recipe
	end
	if entry.base_recipe and prototypes.recipe[entry.base_recipe] then
		return entry.base_recipe
	end
	-- Fall back to the entity's current recipe, stripping a generated suffix.
	local current = entity.get_recipe()
	if current and prototypes.recipe[current.name] then
		local base = current.name:match("^(.*)%-PlanetsLib%-stack%-%d+$")
		if base and prototypes.recipe[base] then
			return base
		end
		if not current.name:find("%-PlanetsLib%-stack%-") then
			return current.name
		end
	end
	return nil
end

local function get_variant_metadata(base_recipe)
	return PlanetsLib.constants.ground_digger_recipe_variants
		and PlanetsLib.constants.ground_digger_recipe_variants[base_recipe]
end

local function variant_is_usable(force, name)
	return name and prototypes.recipe[name] and force.recipes[name] and force.recipes[name].enabled
end

---Returns the recipe a force should use for a base ground-digger recipe.
-- Variants are only used when the base recipe is unlocked, so research gating is preserved.
local function pick_variant_for(force_name, base_recipe)
	local force = game.forces[force_name]
	if not (force and prototypes.recipe[base_recipe]) then
		return base_recipe
	end
	local base = force.recipes[base_recipe]
	if not (base and base.enabled) then
		return base_recipe
	end
	local meta = get_variant_metadata(base_recipe)
	if not meta then
		return base_recipe
	end
	local stack = math.min((force.belt_stack_size_bonus or 0) + 1, meta.max_stack)
	if meta.item_stack_size then
		stack = math.min(stack, meta.item_stack_size)
	end
	stack = math.max(1, stack)
	local variant = meta.variants and meta.variants[stack]
	if variant_is_usable(force, variant) then
		return variant
	end
	for fallback = stack - 1, 1, -1 do
		local candidate = meta.variants and meta.variants[fallback]
		if variant_is_usable(force, candidate) then
			return candidate
		end
	end
	return base_recipe
end

local function pick_recipe_for_entity(entry)
	local entity = entry.entity
	if not (entity and entity.valid) then
		return nil
	end
	local base = resolve_base_recipe(entry)
	if not base then
		return nil
	end
	-- Only drills that drop full belt stacks batch their recipe.
	if not digger_batches[entity.name] then
		return base
	end
	return pick_variant_for(entity.force.name, base)
end

---Returns items removed by set_recipe to the machine instead of dropping them.
-- The output inventory is the requested destination; the input inventory and a
-- final spill are safety nets for the rare case where the output is full.
local function return_recipe_items_to_entity(entity, returned)
	if not returned then
		return
	end
	local output = entity.get_inventory(defines.inventory.crafter_output)
	local input = entity.get_inventory(defines.inventory.crafter_input)
	for _, item in pairs(returned) do
		if item and item.name and item.count and item.count > 0 then
			local remaining = item.count
			if output then
				local inserted = output.insert({
					name = item.name,
					count = remaining,
					quality = item.quality,
				})
				remaining = remaining - math.min(inserted, remaining)
			end
			if remaining > 0 and input then
				local inserted = input.insert({
					name = item.name,
					count = remaining,
					quality = item.quality,
				})
				remaining = remaining - math.min(inserted, remaining)
			end
			-- Last-resort safety net: never delete items silently.
			if remaining > 0 then
				entity.surface.spill_item_stack({
					position = entity.position,
					stack = {
						name = item.name,
						count = remaining,
						quality = item.quality,
					},
					enable_looted = true,
				})
			end
		end
	end
end

local function update_entry(entry)
	local entity = entry.entity
	if not (entity and entity.valid and entity.unit_number) then
		remove_entry(entry)
		return false
	end
	move_entry_to_force(entry, entity.force.name)
	local base = resolve_base_recipe(entry)
	if not base then
		return true
	end
	entry.base_recipe = base
	local target = pick_recipe_for_entity(entry)
	if not target then
		return true
	end
	local current = entity.get_recipe()
	if current and current.name == target then
		if entity.recipe_locked ~= true then
			entity.recipe_locked = true
		end
		return true
	end
	local returned = entity.set_recipe(target, "normal")
	return_recipe_items_to_entity(entity, returned)
	entity.recipe_locked = true
	return true
end

local function update_force(force_name)
	ensure_storage()
	local bucket = storage.ground_diggers.by_force[force_name]
	if not bucket then
		return
	end
	local units = {}
	for unit_number in pairs(bucket) do
		units[#units + 1] = unit_number
	end
	for _, unit_number in pairs(units) do
		local entry = storage.ground_diggers.by_unit[unit_number]
		if entry then
			update_entry(entry)
		end
	end
end

local function update_all()
	ensure_storage()
	for _, force in pairs(game.forces) do
		update_force(force.name)
	end
end

local function rebuild_storage()
	storage.ground_diggers = {
		version = STORAGE_VERSION,
		rebuilt = true,
		by_unit = {},
		by_force = {},
	}
	if #digger_name_list == 0 then
		return
	end
	for _, surface in pairs(game.surfaces) do
		if surface.valid then
			for _, entity in pairs(surface.find_entities_filtered({ name = digger_name_list })) do
				if entity.valid then
					register_entity(entity, nil)
				end
			end
		end
	end
	update_all()
end

local function get_storage_summary()
	ensure_storage()
	local summary = {}
	for force_name, bucket in pairs(storage.ground_diggers.by_force) do
		local force_summary = {}
		for unit_number in pairs(bucket) do
			local entry = storage.ground_diggers.by_unit[unit_number]
			if entry then
				local entity = entry.entity
				local recipe = entity and entity.valid and entity.get_recipe()
				force_summary[unit_number] = {
					entity_name = entity and entity.valid and entity.name or nil,
					base_recipe = entry.base_recipe,
					planet_name = entry.planet_name,
					recipe = recipe and recipe.name or nil,
				}
			end
		end
		summary[force_name] = force_summary
	end
	return summary
end

Public.register_entity = register_entity
Public.unregister_entity = unregister_entity
Public.update_force = update_force
Public.update_all = update_all
Public.reconcile = update_all
Public.rebuild_storage = rebuild_storage
Public.pick_variant_for = pick_variant_for
Public.get_storage_summary = get_storage_summary
Public.return_recipe_items_to_entity = return_recipe_items_to_entity

local function get_cursor_info(player)
	local cursor_stack = player.cursor_stack
	local cursor_stack_valid = cursor_stack and cursor_stack.valid_for_read and cursor_stack.count > 0

	if cursor_stack_valid then
		return cursor_stack.name, cursor_stack.quality, true
	end
	local cursor_ghost = player.cursor_ghost
	if not cursor_ghost then
		return nil
	end
	local name = cursor_ghost.name.name
	return name, cursor_ghost.quality, false
end

---Assigns a built ground digger the recipe of the planet it was built on.
---Registered for the entity build events, so that diggers built from ghosts or
---blueprints receive their recipe too.
function Public.on_entity_built(event)
	local entity = event.entity or event.created_entity
	if not (entity and entity.valid) then
		return
	end
	if not digger_names[entity.name] then
		return
	end
	local surface = entity.surface
	local planet = surface and surface.planet
	local config = planet and PlanetsLib.constants.ground_diggers[planet.name]
	local base_recipe
	if config and config.recipe and is_allowed_on_planet(config, entity.name) then
		base_recipe = config.recipe
	end
	local entry = register_entity(entity, base_recipe)
	if entry and base_recipe then
		update_entry(entry)
	end
end

---Whether a prototype's surface conditions are met on a surface.
-- Ground diggers inherit the drill's surface conditions when they are generated, but a mod
-- may change the drill's conditions later (for example, Muluna bans chemical burner
-- machines on its oxygen-less surface in data-final-fixes). The custom build input
-- bypasses the engine's normal build check, so check the drill itself before converting it.
-- @param surface LuaSurface
-- @param prototype LuaEntityPrototype
-- @return boolean
local function surface_conditions_met(surface, prototype)
	for _, condition in pairs(prototype.surface_conditions or {}) do
		local value = surface.get_property(condition.property)
		if (condition.min and value < condition.min) or (condition.max and value > condition.max) then
			return false
		end
	end
	return true
end

local mining_drill_prototypes = prototypes.get_entity_filtered{{filter="type",type="mining-drill"}}

---Returns a prototype's actual footprint size in tiles from its selection box.
-- LuaEntityPrototype::tile_width/tile_height describe the placement grid, not the
-- entity's collision footprint; most entities use a 1x1 placement grid even when
-- their selection box is larger.
-- @param prototype LuaEntityPrototype
-- @return number|nil width
-- @return number|nil height
local function get_selection_box_size(prototype)
	local selection_box = prototype and prototype.selection_box
	if not selection_box then
		return nil, nil
	end
	return math.abs(selection_box.right_bottom.x - selection_box.left_top.x),
		math.abs(selection_box.right_bottom.y - selection_box.left_top.y)
end

---Entities that block placing a ground digger at a position.
-- The checked area is the digger's square collision footprint around the build
-- position. Corpses and characters do not block construction, so they are removed
-- from the result.
-- @param surface LuaSurface
-- @param position MapPosition
-- @param digger_prototype LuaEntityPrototype|string A prototype or a prototype name.
-- @return table List of LuaEntity
function Public.find_build_collisions(surface, position, digger_prototype)
	if type(digger_prototype) == "string" then
		digger_prototype = prototypes.entity[digger_prototype]
	end
	if not (surface and surface.valid and position and digger_prototype) then
		return {}
	end

	-- If the digger is not square, this code can't cleanly handle the collision box.
	local selection_box = digger_prototype.selection_box
	local width, height = get_selection_box_size(digger_prototype)
	if not selection_box or not width or not height or width <= 0 or height <= 0 or width ~= height then
		return {}
	end

	local area = {
		{
			position.x + selection_box.left_top.x,
			position.y + selection_box.left_top.y,
		},
		{
			position.x + selection_box.right_bottom.x,
			position.y + selection_box.right_bottom.y,
		},
	}
	local collision_mask = digger_prototype.collision_mask
	local colliding_entities = surface.find_entities_filtered({
		area = area,
		to_be_deconstructed = false,
		-- Only count entities that share a collision layer with the digger. Some planets
		-- cover their surface with non-colliding visuals (e.g. Maraxsis' water shader),
		-- which would otherwise block every placement.
		collision_mask = collision_mask and collision_mask.layers,
	})

	-- Ghosts do not have a physical collision mask, so the filtered query above
	-- does not reliably return them. A ground digger must not overlap a ghost
	-- either, except for the ghost of the digger being placed: the caller revives
	-- that one instead of creating a second entity.
	local seen = {}
	for _, entity in pairs(colliding_entities) do
		if entity.unit_number then
			seen[entity.unit_number] = true
		end
	end
	for _, ghost in pairs(surface.find_entities_filtered({
		area = area,
		type = "entity-ghost",
		to_be_deconstructed = false,
	})) do
		if not ghost.unit_number or not seen[ghost.unit_number] then
			colliding_entities[#colliding_entities + 1] = ghost
		end
	end

	for i = #colliding_entities, 1, -1 do
		local entity = colliding_entities[i]
		-- Corpses and characters do not block construction: the engine allows
		-- building under the player, and the character itself is not an obstacle.
		-- Resources do not block construction either: on them the player is placing
		-- an ordinary mining drill, so they must not trigger a digger warning.
		if entity.type == "corpse" or entity.type == "character" or entity.type == "resource" then
			table.remove(colliding_entities, i)
		end
	end
	return colliding_entities
end

---Entities that show the custom entity-in-the-way warning for a ground digger.
-- This deliberately scans the visual footprint without a collision mask, so it warns
-- for objects that would visually overlap the digger. Corpses, characters, ghosts,
-- resources and map-hidden visuals do not produce the custom warning: resources mean
-- an ordinary mining drill is being placed, and ghosts keep the vanilla build overlay.
-- @param surface LuaSurface
-- @param position MapPosition
-- @param digger_prototype LuaEntityPrototype|string A prototype or a prototype name.
-- @return table List of LuaEntity
function Public.find_build_warning_entities(surface, position, digger_prototype)
	if type(digger_prototype) == "string" then
		digger_prototype = prototypes.entity[digger_prototype]
	end
	if not (surface and surface.valid and position and digger_prototype) then
		return {}
	end

	local selection_box = digger_prototype.selection_box
	local width, height = get_selection_box_size(digger_prototype)
	if not selection_box or not width or not height or width <= 0 or height <= 0 or width ~= height then
		return {}
	end

	local entities = surface.find_entities_filtered({
		area = {
			{
				position.x + selection_box.left_top.x,
				position.y + selection_box.left_top.y,
			},
			{
				position.x + selection_box.right_bottom.x,
				position.y + selection_box.right_bottom.y,
			},
		},
		to_be_deconstructed = false,
	})
	rro.remove(entities, function(entry)
		return entry.type == "corpse"
			or entry.type == "character"
			or entry.type == "entity-ghost"
			or entry.type == "resource"
			or entry.has_flag("not-on-map")
			or entry.name == "maraxsis-water-shader"
	end)
	return entities
end

---Selects the ground-digger ghost closest to the cursor.
-- Removes every matching candidate from `colliding_entities`; the caller may
-- revive the returned ghost. Non-matching entities stay in the list so they
-- continue to block placement.
-- @param colliding_entities table
-- @param digger_name string
-- @param position MapPosition
-- @return LuaEntity|nil
function Public.select_digger_ghost(colliding_entities, digger_name, position)
	local target_ghost
	local best_distance
	for i = #colliding_entities, 1, -1 do
		local entity = colliding_entities[i]
		if entity.type == "entity-ghost" and entity.ghost_name == digger_name then
			local dx = entity.position.x - position.x
			local dy = entity.position.y - position.y
			local distance = dx * dx + dy * dy
			if not target_ghost or distance < best_distance then
				target_ghost = entity
				best_distance = distance
			end
			table.remove(colliding_entities, i)
		end
	end
	return target_ghost
end

---Revives a ground-digger ghost and assigns its planet recipe.
-- Exposed through the FUnit seam so the headless suite can exercise the
-- item-over-ghost path without a connected player.
function Public.revive_ground_digger_ghost(ghost)
	if not (ghost and ghost.valid and ghost.type == "entity-ghost") then
		return nil
	end
	local _, revived = ghost.revive({ raise_revive = true })
	if not (revived and revived.valid) then
		return nil
	end
	Public.on_entity_built({ entity = revived })
	return revived
end

function Public.construct_ground_digger(event)
	
	local player = game.get_player(event.player_index)
	if not player or not player.valid then
		return
	end
	local surface = player.surface
	local planet = surface.planet
	if not planet then
		return
	end
	local config = PlanetsLib.constants.ground_diggers[planet.name]
	if not config or not config.diggers then
		return
	end

	local name, quality, cursor_stack_valid = get_cursor_info(player)
	
	if not name then
		return
	end
	local info = config.diggers[name]
	if not info then
		return
	end
	local drill_name = info.drill
	local digger_name = info.digger

	local position = event.cursor_position
	if not position then
		return
	end
	if surface.entity_prototype_collides(digger_name, position, false) then
		return
	end
	local drill_prototype = mining_drill_prototypes[drill_name]
	if not drill_prototype then
		return
	end

	-- Decide whether this is a digger placement before showing any placement feedback:
	-- a drill placed over resources is an ordinary mining drill, not a ground digger,
	-- so it must never show the digger's object-collision warning.
	local radius = drill_prototype.get_mining_drill_radius(quality)
	local neighboring_resources = surface.find_entities_filtered({
		-- Search for resources to see if a regular mining drill would be placed.
		area = {
			{ position.x - radius, position.y - radius },
			{ position.x + radius, position.y + radius },
		},
		type = { "resource" },
	})
	if #neighboring_resources ~= 0 then
		return -- If neighboring resources exist, then place a regular mining drill instead.
	end

	--If mining drill not square, this code can't cleanly handle it, so while mod-data should ideally not contain this drill,
	--this check allows them to exist in mod-data without crashing.
	local width, height = get_selection_box_size(drill_prototype)
	if not width or not height or width <= 0 or height <= 0 or width ~= height then
		return
	end

	local digger_prototype = prototypes.entity[digger_name]
	if not digger_prototype then
		return
	end

	-- Ghosts are handled by the later footprint check. Suppress the custom
	-- entity-in-the-way label for them so the vanilla build overlay remains
	-- visible instead of being replaced by a PlanetsLib warning.
	local warning_entities = Public.find_build_warning_entities(surface, position, digger_prototype)
	if #warning_entities ~= 0 then
		player.create_local_flying_text({
			text = { "cant-build-reason.entity-in-the-way", warning_entities[1] },
			surface = surface,
			create_at_cursor = true,
			speed = 0.01,
		})
		return
	end

	if surface.get_tile(position).hidden_tile then
		player.create_local_flying_text({
			text = { "cant-build-reason.cant-build-on-tile", surface.get_tile(position).prototype.localised_name },
			surface = surface,
			create_at_cursor = true,
			speed = 0.01,
		})
		return -- If tile is unnatural, like concrete, then don't place the digger.
	end



	-- In remote view the player always builds ghosts (even though the cursor stack is
	-- valid), and ghost placement has no reach limit. Treat remote builds as ghosts and
	-- skip the reachability check so diggers can be planned anywhere in remote view.
	local is_remote_view = player.controller_type == defines.controllers.remote

	local is_ghost = is_remote_view
		or (not cursor_stack_valid)
		or event.input_name == "PlanetsLib-build-ghost"
		or event.input_name == "PlanetsLib-super-forced-build"
	
	if not is_remote_view then
		local player_position = (player.character or player).position
		local distance = math.sqrt((position.x - player_position.x) ^ 2 + (position.y - player_position.y) ^ 2)
		if player.character and (distance >= player.character.build_distance) and not is_ghost then
			return -- If unreachable, then don't place.
		end
	end
	

	if not surface_conditions_met(surface, drill_prototype) then
		return
	end

	local colliding_entities = Public.find_build_collisions(surface, position, digger_prototype)
	local target_ghost
	if not is_ghost then
		-- Direct placement over matching ground-digger ghosts builds the one
		-- closest to the cursor, matching vanilla item-over-ghost behavior.
		-- Other ghosts and real entities remain blocking.
		target_ghost = Public.select_digger_ghost(colliding_entities, digger_name, position)
	end
	if #colliding_entities ~= 0 then
		return
	end

	local digger
	if target_ghost and target_ghost.valid then
		digger = Public.revive_ground_digger_ghost(target_ghost)
	else
		digger = surface.create_entity({
			name = is_ghost and "entity-ghost" or digger_name,
			inner_name = is_ghost and digger_name or nil,
			position = position,
			force = player.force,
			player = player,
			quality = quality,
			direction = event.cursor_direction,
			raise_built = true,
		})
	end
	if not digger or not digger.valid then
		return
	end

	if not is_ghost then
		player.cursor_stack.count = player.cursor_stack.count - 1
		player.force.get_entity_build_count_statistics(surface).on_flow(name, 1)
	end
end

---Removes a destroyed or mined ground digger from the storage table.
function Public.on_entity_removed(event)
	local entity = event.entity
	if entity and digger_names[entity.name] then
		unregister_entity(entity)
	end
end

---Registers and updates a cloned ground digger.
function Public.on_entity_cloned(event)
	local source = event.source
	local destination = event.destination
	if not (source and destination and digger_names[source.name]) then
		return
	end
	ensure_storage()
	local source_entry = storage.ground_diggers.by_unit[source.unit_number]
	local base_recipe = source_entry and source_entry.base_recipe or nil
	local entry = register_entity(destination, base_recipe)
	if entry then
		update_entry(entry)
	end
end

function Public.on_research_finished(event)
	local force = event.research and event.research.force
	if force then
		update_force(force.name)
	end
end

function Public.on_research_reversed(event)
	local force = event.research and event.research.force
	if force then
		update_force(force.name)
	end
end

function Public.on_technology_effects_reset(event)
	if event.force then
		update_force(event.force.name)
	end
end

function Public.on_force_reset(event)
	if event.force then
		update_force(event.force.name)
	end
end

---Moves the storage bucket of a merged force to the destination force.
local function merge_force_buckets(source_name, destination_name)
	if not (source_name and destination_name) then
		return
	end
	ensure_storage()
	local source_bucket = storage.ground_diggers.by_force[source_name]
	if source_bucket then
		local destination_bucket = storage.ground_diggers.by_force[destination_name]
		if not destination_bucket then
			destination_bucket = {}
			storage.ground_diggers.by_force[destination_name] = destination_bucket
		end
		for unit_number in pairs(source_bucket) do
			destination_bucket[unit_number] = true
			local entry = storage.ground_diggers.by_unit[unit_number]
			if entry then
				entry.force_name = destination_name
			end
		end
		storage.ground_diggers.by_force[source_name] = nil
	end
	update_force(destination_name)
end

function Public.on_forces_merged(event)
	if event.source_name and event.destination then
		merge_force_buckets(event.source_name, event.destination.name)
	end
end

Public.merge_force_buckets = merge_force_buckets

function Public.on_init()
	rebuild_storage()
end

function Public.on_configuration_changed()
	ensure_storage()
	if not storage.ground_diggers.rebuilt then
		rebuild_storage()
		return
	end
	update_all()
end

return Public
