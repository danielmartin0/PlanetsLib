local rro = require("lib.objects")
local Public = {}

-- Creates "If entity placed on planet, replace entity with new_entity" rule.
-- Mass-assignment is possible by making entity a dictionary table and new_entity nil.
function Public.assign_entity_replacement(planet,entity,new_entity,bound_setting)
    
    local planet_name = (type(planet) == "table" and planet.name) or planet
    if not bound_setting then --Since entity replacements can potentially break saves, every entity replacement must be bound to a startup setting that can be disabled to aid in safe uninstallation.
        bound_setting = "PlanetsLib-enable-entity-replacements"
    end
    if not PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet_name] then PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet_name] = {} end
    if type(entity) == "table" and new_entity == nil then
        for key,value in pairs(entity) do
            Public.assign_entity_replacement(planet_name,key,value.entity,value.bound_setting)
        end
        return
    end
    if PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet][entity] then
        error("PlanetsLib.assign_entity_replacement(planet,entity,new_entity,bound_setting) - Assigning an entity variant of the same entity on the same planet more than once is currently not possible.")
    end
    PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet][entity] = {old_entity=entity,entity=new_entity,enabled=settings.startup[bound_setting].value}

end

-- 1. Generates a deepcopy of entity, 
-- 2. Gives the deepcopy a unique name, 
-- 3. Gives the deepcopy the same localized name/description as entity.
-- 4. Merges deepcopy with new_properties, enabling the user to override steps 2/3 if desired.
-- 5. Makes the deepcopy replace entity when on each "planet".
-- 6. Adds new_entity to data.raw.
-- 7. Returns new_entity to make it easier to reference the generated entity in subsequent code.
function Public.create_planet_entity_variant(planet_names,entity,new_properties,bound_setting,item_name)
    assert(settings.startup[bound_setting],
    "PlanetsLib.assign_entity_replacement(planet_names,entity,new_properties,bound_setting,item_name) - bound_setting must refer to a valid boolean startup setting.")
    if item_name == nil and data.raw["item"][entity.name] then
        item_name = entity.name
    end
    local first_planet_name = (type(planet) == "table" and planet_names[1]) or planet_names
    if not entity.fast_replaceable_group then
        entity.fast_replaceable_group = entity.name .. "-PlanetsLib-group"
    end
    local new_entity = table.deepcopy(entity)
    if not entity.factoriopedia_alternative then
        new_entity.factoriopedia_alternative = entity.name
    end
    if not new_entity.placeable_by and item_name then
        new_entity.placeable_by = {{item = item_name, count =1}}
    end
    new_entity.hidden_in_factoriopedia = true
    new_entity.name = entity.name .. "-PlanetsLib-" .. first_planet_name 
    
    if not new_entity.localised_name then
        new_entity.localised_name = {"entity-name." .. entity.name}
    end
    if not new_entity.localised_description then
        new_entity.localised_description = {"entity-description." .. entity.name}
    end
    
    if not new_entity.icons then
        new_entity.icons = {
            new_entity.icon and {
                icon = new_entity.icon,
                icon_size = new_entity.icon_size
            } or nil
        }
    end
    

    new_entity.flags = new_entity.flags or {}
    rro.soft_insert(new_entity.flags,"not-in-made-in")
    rro.soft_insert(new_entity.flags, "not-in-bonus-gui")
    new_entity = rro.merge(new_entity,new_properties) 
    
    if type(planet_names) == "table" then
        for _,planet in pairs(planet_names) do
            Public.assign_entity_replacement(planet,entity.name,new_entity.name,bound_setting)
        end
    else
    if new_entity.icon or new_entity.icons then
        if data.raw["planet"][planet_names].icon then
            table.insert(new_entity.icons , {
                icon = data.raw["planet"][planet_names].icon,
                icon_size = data.raw["planet"][planet_names].icon_size,
                scale = 64 / (data.raw["planet"][planet_names].icon_size or 64)* 0.25,
                shift = {10,-10},
                draw_background = true,
        })
        else
            for _,icon_entry in pairs(data.raw["planet"][planet_names].icons) do
                table.insert(new_entity.icons , {
                icon = icon_entry.icon,
                icon_size = icon_entry.icon_size,
                scale = 64 / (icon_entry.icon_size or 64)* 0.25,
                shift = {10,-10},
                draw_background = true,
            })
            end
        end
    end
        
        new_entity.order = (new_entity.order or "") .. "z" .. data.raw["planet"][planet_names].order
        Public.assign_entity_replacement(planet_names,entity.name,new_entity.name,bound_setting)
    end
    
    data:extend{new_entity}
    return new_entity
end


return Public