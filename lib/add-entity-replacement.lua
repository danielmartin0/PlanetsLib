local Public = {}

function Public.add_entity_replacement(planet,entity,new_entity)
    if not PlanetsLib.constants[planet] then PlanetsLib.constants[planet] = {} end
    if type(entity) == "table" and type(new_entity)
    PlanetsLib.constants[planet][entity] = new_entity

end


return Public