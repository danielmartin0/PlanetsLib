local Public = {}
local entity_replacements = PlanetsLib.constants.on_entity_placed_on_planet_replacements
local entity_replacements_inverted = {}

for _,planet in pairs(entity_replacements) do
    --entity_replacements_inverted[planet] = {}
    for key,value in pairs(planet) do
        entity_replacements_inverted[value] = key
    end
end

function Public.replace_entity(entity,new_entity,raise_built)
    local is_ghost = entity.name == "entity-ghost"
    local player = entity.last_user
    local new_entity_properties = {
        name = is_ghost and "entity-ghost" or new_entity,
        inner_name = is_ghost and new_entity or nil,
        tags = is_ghost and entity.tags or nil,
        position = entity.position,
        direction = entity.direction,
        force = entity.force_index,
        quality = entity.quality,
        health = entity.health,
        raise_built = false,
        player = player,
        mirror = entity.mirroring
    }
    --if not surface.can_place_entity{new_entity_properties} then return end
    local new_entity = entity.surface.create_entity(new_entity_properties)
    
    if not new_entity or not new_entity.valid then return end
    --new_entity.mirroring = entity.mirroring
    new_entity.copy_settings(entity)

    if not is_ghost and entity.get_module_inventory() then
        local modules = entity.get_module_inventory().get_contents()
        for _, item in pairs(modules) do
            local inserted_count = new_entity.insert(item)
            if inserted_count < item.count then
                item.count = item.count - inserted_count
                entity.surface.spill_item_stack {
                    position = entity.position,
                    stack = item,
                    enable_looted = true,
                    force = entity.force_index,
                    allow_belts = false
                }
            end
        end
    end
    new_entity.last_user = entity.last_user
    entity.destroy()
    if raise_built then
        script.raise_script_built{entity=new_entity}
    end


end

function Public.on_built_entity(event,swap_target,dont_raise_built) -- Based on Maraxsis function. Fulfills rule "If entity X placed on planet Y, replace entity with entity Z"
    local entity = event.entity
    local surface = entity.surface
    local planet_object = surface.planet
    local planet 
    if planet_object then
        planet = planet_object.name
    else
        planet = "space-platform"
    end
    
    --if not entity_replacements[planet] then return end
    
    if not ((entity_replacements_inverted[entity.name]) or (entity_replacements[planet] and entity_replacements[planet][entity.name]))  then return end

    if not entity.valid then return end 

   

    
    local surface = entity.surface
    
    local name = is_ghost and entity.ghost_name or entity.name

    local is_space = not not surface.platform

    local swap_target = swap_target or nil
    --game.print(serpent.block(entity_replacements_inverted))
    if swap_target == nil then
        if entity_replacements_inverted[name] then
            swap_target = entity_replacements[planet][entity_replacements_inverted[name].entity]
        else
            swap_target = entity_replacements[planet][name].entity
        end
    end
        
    if entity_replacements[planet][entity.name].enabled == false then return end 
        
    
    Public.replace_entity(entity,swap_target,true)
    

    
    
    



end

function Public.migrate_entity_replacements()
    if not storage.entity_replacement_migrations then storage.entity_replacement_migrations = {} end --Table to track changes in entity replacement migrations
    local replacement_queue = {} --List of migrations to perform
    for _,planet in pairs(entity_replacements) do
        for entity,new_entity_table in pairs(entity_replacements) do
            local new_entry = {}
            if not PlanetsLib.rro.deep_equals(storage.entity_replacement_migrations[planet][entity],new_entity_table) then --Checks if new settings are different from old settings.
                storage.entity_replacement_migrations[planet][entity] = new_entity
                local old_entity = new_entity.old_entity
                
                table.insert(replacement_queue,new_entity)

                

            end
        end
    end

    for _,replacement in pairs(replacement_queue) do
        local entity_to_find --Entity to search for in surfaces.
        local entity_to_replace --Entity to to replace found instances of entity_to_find with.
        for _,surface in pairs(game.surfaces) do
            
        end
    end
    

    
        

end

--Function called to replace PlanetsLib planet-exclusive entity replacements with original versions. Keeping blueprints in a stable state feels like a safer choice than allowing people to 



-- function Public.blueprint_standardize(event)
--     local record = event.record

--     for _,entity in pairs(record.get_blueprint_entities()) do
--         if entity_replacements_inverted[entity.name] then 
--             entity.name = entity_replacements_inverted[entity.name] 
--         end
--     end

-- end


return Public