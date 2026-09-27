
local Public = {}

--Run at beginning of every data cycle. Checks if commonly used global variables set by engine still exist. Used to enforce a certain level of code quality among all mods.
function Public.check_global_variables()
    if not helpers.compare_versions then
        error("Another mod has overridden the 'helpers' global variable. More info: https://lua-api.factorio.com/latest/classes/LuaHelpers.html")
    end

    --Searches for prototypes using obsolete fields and replaces them with newer equivalents. Used to preserve the functionality of unmaintained mods on newer versions.
    for _,item in pairs(data.raw["item"]) do
        if item.fuel_category then
            item.fuel_categories = item.fuel_categories or {}
            table.insert(item.fuel_categories,item.fuel_category)
            item.fuel_category = nil
            table.insert(PlanetsLib.constants.items_corrected_fuel_category,item.name)
            log("Item " .. item.name .. " using unsupported field ItemPrototype::fuel_category has been corrected. This item should be manually fixed, as this field is no longer supported by Wube as of Factorio 2.1.20.")
        end
    end
    for _,sound in pairs(data.raw["ambient-sound"]) do
        if sound.planet then
            if not sound.planets then
                sound.planets = {}
            end
            PlanetsLib.rro.soft_insert(sound.planets,sound.planet)
            log("Ambient sound " .. sound.name .. " using unsupported field AmbientSound::planet has been corrected. This sound should be manually fixed, as this field is no longer supported by Wube as of Factorio 2.1.13.")
            sound.planet = nil
        end
    end



end

return Public