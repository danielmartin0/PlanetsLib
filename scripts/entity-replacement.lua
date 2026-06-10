local Public = {}
local entity_replacements = PlanetsLib.constants.on_entity_placed_on_planet_replacements


function Public.on_built_entity(event) -- Based on Maraxsis function. Fulfills rule "If entity X placed on planet Y, replace entity with entity Z"
    local entity = event.entity
    local surface = entity.surface
    local planet_object = surface.planet
    local planet 
    if planet_object then
        planet = planet_object.name
    else
        planet = "space-platform"
    end
    
    if not entity_replacements[planet] then return end
    
    if not entity_replacements[planet][entity.name] then return end

    if not entity.valid then return end 

    

    
    local surface = entity.surface
    local is_ghost = entity.name == "entity-ghost"
    local name = is_ghost and entity.ghost_name or entity.name

    local is_space = not not surface.platform
    local swap_target = entity_replacements[planet][name]

    local player = event.player_index and game.get_player(event.player_index)

    local new_entity = surface.create_entity {
        name = is_ghost and "entity-ghost" or swap_target,
        inner_name = is_ghost and swap_target or nil,
        tags = is_ghost and entity.tags or nil,
        position = entity.position,
        direction = entity.direction,
        force = entity.force_index,
        quality = entity.quality,
        health = entity.health,
        raise_built = true,
        player = player,
    }
    
    if not new_entity or not new_entity.valid then return end
    new_entity.mirroring = entity.mirroring
    new_entity.copy_settings(entity)

    if not is_ghost then
        local modules = entity.get_module_inventory().get_contents()
        for _, item in pairs(modules) do
            local inserted_count = new_entity.insert(item)
            if inserted_count < item.count then
                item.count = item.count - inserted_count
                surface.spill_item_stack {
                    position = entity.position,
                    stack = item,
                    enable_looted = true,
                    force = entity.force_index,
                    allow_belts = false
                }
            end
        end
    end

    entity.destroy()
    



end

return Public