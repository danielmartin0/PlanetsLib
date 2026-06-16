local order = 101
for _,planet in pairs(data.raw["planet"]) do
    if true or PlanetsLib.constants.planet_properties[planet.name] then
        local properties = PlanetsLib.constants.planet_properties[planet.name] or {}
        local lift_multiplier =  properties["rocket_lift_multiplier"]
        local part_multiplier =  properties["rocket_part_multiplier"]
        
        if lift_multiplier or part_multiplier then
            if not planet.custom_tooltip_fields then planet.custom_tooltip_fields = {} end

            if lift_multiplier then
                table.insert(planet.custom_tooltip_fields,{
                    name = {"surface-property-name.rocket-lift-multiplier"},
                    value = {"surface-property-unit.multiplier",string.format(lift_multiplier,"%.2f")},
                    order = order,
                }   )  
            end

            if part_multiplier then
                table.insert(planet.custom_tooltip_fields,{
                    name = {"surface-property-name.rocket-part-multiplier"},
                    value = {"surface-property-unit.multiplier",string.format(part_multiplier,"%.2f")},
                    order = order,
                }   )  
            end

            --for _,silo in pairs(data.raw["rocket-silo"]) do
                local silo = data.raw["rocket-silo"]["rocket-silo"]
                local silo_item_name = silo.name
                PlanetsLib.create_planet_entity_variant(
                    planet.name,
                    silo,
                    {
                        rocket_parts_required = silo.rocket_parts_required*(part_multiplier or 1),
                        --Add rocket_lift_multiplier here when 2.1 comes out
                    },
                    silo_item_name
                )
            --end
        end 
    end
   
end