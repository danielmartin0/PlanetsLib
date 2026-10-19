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
for _, config in pairs(PlanetsLib.constants.ground_diggers) do
	for _, info in pairs(config.diggers or {}) do
		digger_names[info.digger] = true
	end
end

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
	if not planet then
		return
	end
	local config = PlanetsLib.constants.ground_diggers[planet.name]
	if not config or not config.recipe then
		return
	end
	entity.set_recipe(config.recipe, "normal")
	entity.recipe_locked = true
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
	--If mining drill not square, this code can't cleanly handle it, so while mod-data should ideally not contain this drill,
    --this check allows them to exist in mod-data without crashing.
	local selection_box = drill_prototype.selection_box
	--game.print(serpent.block(selection_box))
    local offset_width = math.abs(selection_box.left_top.x - selection_box.right_bottom.x)
    local offset_height = math.abs(selection_box.left_top.y - selection_box.right_bottom.y)
	--game.print(offset_width)
    local margin = 0
    local rounded_position = {
        x = math.ceil(position.x) - 0.5,
        y = math.ceil(position.y) - 0.5
    }
	--game.print(serpent.block(rounded_position))
	
	
    if offset_width ~= offset_height then return end 

    local colliding_entities = surface.find_entities_filtered{
            area= {{rounded_position.x-offset_width/2+margin,rounded_position.y-offset_height/2+margin},{rounded_position.x+offset_width/2-margin,rounded_position.y+offset_height/2-margin}},
            to_be_deconstructed = false,
        }
    rro.remove(colliding_entities,function(entry) return entry.type == "corpse" end)
	rro.remove(colliding_entities,function(entry) return entry.has_flag("not-on-map") end)
	rro.remove(colliding_entities,function(entry) return entry.name == "maraxsis-water-shader" end)
    if #colliding_entities ~= 0 then 
		player.create_local_flying_text({
			text = { "cant-build-reason.entity-in-the-way", colliding_entities[1] },
			surface = surface,
			create_at_cursor = true,
			speed = 0.01,
		})
	return end

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
	

	local drill_prototype = prototypes.entity[drill_name]
	if not drill_prototype then
		return
	end
	if not surface_conditions_met(surface, drill_prototype) then
		return
	end
	local digger_prototype = prototypes.entity[digger_name]
	if not digger_prototype then
		return
	end

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

	-- If the mining drill is not square, this code can't cleanly handle the collision box.
	local width = drill_prototype.tile_width
	local height = drill_prototype.tile_height
	if width ~= height then
		return
	end

	local margin = 1.5
	local rounded_position = {
		x = math.ceil(position.x + 0.5),
		y = math.ceil(position.y + 0.5),
	}
	local colliding_entities = surface.find_entities_filtered({
		area = {
			{
				rounded_position.x - width / 2 + margin,
				rounded_position.y - height / 2 + margin,
			},
			{
				rounded_position.x + width / 2 - margin,
				rounded_position.y + height / 2 - margin,
			},
		},
		to_be_deconstructed = false,
		-- Only count entities that share a collision layer with the digger. Some planets
		-- cover their surface with non-colliding visuals (e.g. Maraxsis' water shader),
		-- which would otherwise block every placement.
		collision_mask = digger_prototype.collision_mask.layers,
	})
	for i = #colliding_entities, 1, -1 do
		if colliding_entities[i].type == "corpse" then
			table.remove(colliding_entities, i)
		end
	end
	if #colliding_entities ~= 0 then
		return
	end

	local digger = surface.create_entity({
		name = is_ghost and "entity-ghost" or digger_name,
		inner_name = is_ghost and digger_name or nil,
		position = position,
		force = player.force,
		player = player,
		quality = quality,
		direction = event.cursor_direction,
		raise_built = true,
	})
	if not digger then
		return
	end

	if not is_ghost then
		player.cursor_stack.count = player.cursor_stack.count - 1
		player.force.get_entity_build_count_statistics(surface).on_flow(name, 1)
	end
end

return Public
