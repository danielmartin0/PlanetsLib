local Public = {}
local rro = require("lib.remove-replace-object")
--Returns true if an entity's surface_conditions fit the surface properties of a planet.
function Public.fits_surface_conditions(entity,luaSurface) 
    assert(entity.surface_conditions,"fits_surface_conditions(entity,planet) - Entity must have surface conditions.")
    --if not planet.surface_properties then return true end
        for _,condition in pairs(entity.surface_conditions) do
            local property = condition.property
            local value = luaSurface.get_property and luaSurface.get_property(property) or prototypes.surface_property[property].default_value
            if value > condition.max or value < condition.min then
                return false
            end
        end
    return true
end

--Returns true if on a given planet, more than one recipe producing rocket parts can be produced in a vanilla rocket silo.
function Public.multiple_rocket_parts_can_be_crafted_in_vanilla_silo(planet) 
    local count = 0
    for _,recipe in pairs(prototypes.get_recipe_filtered{{filter = "category",category = "rocket-building"}}) do
        --game.print(recipe.name)
        if  recipe.surface_conditions == nil or Public.fits_surface_conditions(recipe,planet) then
            count = count + 1
            --game.print(count)
            if count >= 2 then
                return true
            end
        end
    end
    return false
end

return Public