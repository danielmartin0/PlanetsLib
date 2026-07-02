local Public = {}
local entity_replacements = PlanetsLib.constants.on_entity_placed_on_planet_replacements
local entity_replacements_inverted = {}

for planet,planet_table in pairs(entity_replacements) do
    entity_replacements_inverted[planet] = {}
    for key,value in pairs(planet_table) do
        entity_replacements_inverted[planet][value] = key
    end
end


local fields_to_transfer = {
    products_finished = 0,
    disabled_by_script = false,
    temperature = 0,
    --"power_switch_state",
    --"combinator_description",
    
}


--Transfers every single entity state, such that the new_entity is the same as the old entity.
function Public.transfer_entity_state(entity,new_entity)
    new_entity.copy_settings(entity)
    
    for field_to_transfer,default_value in pairs(fields_to_transfer) do
        --if entity[field_to_transfer] then
        new_entity[field_to_transfer] = entity[field_to_transfer] or default_value
        --end
    end

    for _,tooltip_field in pairs(entity.get_tooltip_fields()) do
        new_entity.set_tooltip_field(tooltip_field)
    end
end

function Public.replace_entity(entity,new_entity,raise_built)
    if not storage.replaced_entities then storage.replaced_entities = {} end
    if storage.replaced_entities[entity.unit_number] then return end --To stop infinite recursion
    local is_ghost = entity.name == "entity-ghost"
    local name = new_entity
    local player = entity.last_user
    local new_entity_properties = {
        name = is_ghost and "entity-ghost" or name,
        inner_name = is_ghost and name or nil,
        tags = is_ghost and entity.tags or nil,
        position = entity.position,
        direction = entity.direction,
        force = entity.force_index,
        quality = entity.quality,
        health = entity.health,
        raise_built = false, --raise_script_built is called later
        player = raise_built and player or nil,
        mirror = entity.mirroring,
        --fast_replace = true
    }
    --if not surface.can_place_entity{new_entity_properties} then return end
    local new_entity = entity.surface.create_entity(new_entity_properties)
    if not new_entity or not new_entity.valid then return end
    Public.transfer_entity_state(entity,new_entity)
    
    --if not entity or not entity.valid then return end
    --new_entity.mirroring = entity.mirroring
   

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
    storage.replaced_entities[new_entity.unit_number] = new_entity --Important for preventing infinite recursion
    entity.destroy()
    if raise_built == true then
        script.raise_script_built{entity=new_entity}
    end


end

function Public.on_built_entity(event,swap_target,dont_raise_built) -- Based on Maraxsis function. Fulfills rule "If entity X placed on planet Y, replace entity with entity Z"
    local entity = event.entity
    --if not entity.valid then return end 
    local surface = entity.surface
    local planet_object = surface.planet
    local planet 
    if planet_object then
        planet = planet_object.name
    else
        planet = "space-platform"
    end
    
    --if not entity_replacements[planet] then return end
    
    local is_ghost = entity.name == "entity-ghost"
    local name = is_ghost and entity.ghost_name or entity.name

    if not ((entity_replacements_inverted[planet] and entity_replacements_inverted[planet][name]) or (entity_replacements[planet] and entity_replacements[planet][name]))  then return end
    
    print(is_ghost)
    
    local is_space = not not surface.platform
    local swap_target = swap_target or nil
    --game.print(serpent.block(entity_replacements_inverted))
    if swap_target == nil then
        if entity_replacements_inverted[planet][name] then
            swap_target = entity_replacements[planet][entity_replacements_inverted[planet][name].entity]
        else
            swap_target = entity_replacements[planet][name].entity
        end
    end
    print(swap_target)
    print(name)
    if swap_target == name then return end
    if entity_replacements[planet][name].enabled == false then return end 
        
    print("Replacing entity " .. entity.name .. " with " .. swap_target)
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