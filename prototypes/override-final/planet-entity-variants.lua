
for _,planet in pairs(PlanetsLib.constants.on_entity_placed_on_planet_replacements) do
    for old_entity_name,new_entity_table in pairs(planet) do
        local new_entity_name = new_entity_table.entity
        for _,item in pairs(data.raw["item"]) do
            if item.place_result == old_entity_name then
                local new_entity
                for _,prototype in pairs(data.raw) do
                    for name,entity in pairs(prototype) do
                        if name == new_entity_name then
                            new_entity = entity
                            break
                        end
                    end
                end
                new_entity.placeable_by = {item = item.place_result, count = 1}
            end
        end
    end
end