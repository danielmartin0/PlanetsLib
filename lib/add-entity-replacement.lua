local rro = require("lib.objects")
local Public = {}

-- Creates "If entity placed on planet, replace entity with new_entity" rule.
-- Mass-assignment is possible by making entity a dictionary table and new_entity nil.
function Public.assign_entity_replacement(planet,entity,new_entity)
    local planet_name = (type(planet) == "table" and planet.name) or planet
    if not PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet_name] then PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet_name] = {} end
    if type(entity) == "table" and new_entity == nil then
        for key,value in pairs(entity) do
            Public.add_entity_replacement(planet_name,key,value)
        end
        return
    end
    PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet][entity] = new_entity

end

-- 1. Generates a deepcopy of entity, 
-- 2. Gives the deepcopy a unique name, 
-- 3. Gives the deepcopy the same localized name/description as entity.
-- 4. Merges deepcopy with new_properties, enabling the user to override steps 2/3 if desired.
-- 5. Makes the deepcopy replace entity when on each "planet".
-- 6. Adds new_entity to data.raw.
-- 7. Returns new_entity to make it easier to reference the generated entity in subsequent code.
function Public.create_planet_entity_variant(planet_names,entity,new_properties)
    if PlanetsLib.current_stage == "data-final-fixes" then
        error("This function can only be run before data-final-fixes.")
    end
    local first_planet_name = (type(planet) == "table" and planet_names[1]) or planet_names
    if not entity.fast_replaceable_group then
        entity.fast_replaceable_group = entity.name
    end
    local new_entity = table.deepcopy(entity)
    if not entity.factoriopedia_alternative then
        new_entity.factoriopedia_alternative = entity.name
    end
    -- if not new_entity.placeable_by and data.raw["item"][entity.name] then
    --     new_entity.placeable_by = {{item = entity.name, count =1}}
    -- end
    new_entity.name = entity.name .. "-PlanetsLib-" .. first_planet_name 
    
    if not new_entity.localised_name then
        new_entity.localised_name = {"entity-name." .. entity.name}
    end
    if not new_entity.localised_description then
        new_entity.localised_description = {"entity-description." .. entity.name}
    end
    new_entity = rro.merge(new_entity,new_properties) 
    
    if type(planet_names) == "table" then
        for _,planet in pairs(planet_names) do
            Public.assign_entity_replacement(planet,entity.name,new_entity.name)
        end
    else
        Public.assign_entity_replacement(planet_names,entity.name,new_entity.name)
    end
    
    data:extend{new_entity}
    return new_entity
end


return Public