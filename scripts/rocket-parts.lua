--- rocket-parts.lua
-- @module scripts.rocket-parts.lua
-- @pragma nostrip
-- @author Nicholas Gower(MeteorSwarm)

local Public = {}

--- On building a rocket silo, if the silo is vanilla-like, its recipe is replaced if it was placed on a surface
--- that according to "Planetslib-planet-rocket-part-recipe"(mod-data), should be replaced.
--- Forked from NotNotMelon's [rocket silo code](https://github.com/notnotmelon/maraxsis/blob/main/scripts/project-seadragon.lua) for Maraxsis.
-- @param event table
function Public.on_built_rocket_silo(event)
    
    local entity = event.entity
    if not entity.valid then return end
    local prototype = entity.name == "entity-ghost" and entity.ghost_prototype or entity.prototype
    if prototype.type ~= "rocket-silo" then return end
    
    if not prototype.crafting_categories["rocket-building"] then return end
    local rocket_part_recipe_data = prototypes.mod_data["Planetslib-planet-rocket-part-recipe"].data
    local recipe
    if rocket_part_recipe_data[entity.surface.name] then
        recipe = rocket_part_recipe_data[entity.surface.name]
    else 
        recipe = rocket_part_recipe_data["default"]
    end
    

    if recipe == "_other" then return end --If planet excluded from planetlib script, do nothing, let other planet mod handle rocket part recipe assignment.

    entity.set_recipe(recipe)
    entity.recipe_locked = true

end


--Based on code from Maraxsis' project-seadragon, but altered to be more general using 2.0.58's mod-data prototype 

return Public

