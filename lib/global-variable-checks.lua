
local Public = {}


-- Claude
--- Combines duplicate science pack entries in an ingredients list,
--- summing their amounts.
--- @param ingredients table  Array of {name, amount} entries
--- @return table  New array with one entry per unique science pack
local function combine_science_packs(ingredients)
  local totals = {}      -- name -> summed amount
  local order = {}       -- preserves first-seen order of names

  for _, ingredient in ipairs(ingredients) do
    local name = ingredient[1] or ingredient.name
    local amount = ingredient[2] or ingredient.amount

    if not totals[name] then
      totals[name] = 0
      table.insert(order, name)
    end
    totals[name] = totals[name] + amount
  end

  local result = {}
  for _, name in ipairs(order) do
    table.insert(result, {name, totals[name]})
  end

  return result
end



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
            item.localised_description = {"",item.localised_description or "",{"tooltip.fuel-categories-corrected"}}
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
            local planet = data.raw.planet[sound.planet]
            if planet then
                planet.localised_description = {"",planet.localised_description or "",{"tooltip.space-location-ambient-sounds-corrected"}}
            end
            sound.planet = nil
            
            
        end
    end

    --Searches for techs containing duplicate research ingredients, and combines them together.
    for _,tech in pairs(data.raw["technology"]) do
        if tech.unit and tech.unit.ingredients then
            local ingredients = tech.unit.ingredients
            local new_ingredients = combine_science_packs(ingredients)
            if #ingredients ~= #new_ingredients then
                tech.unit.ingredients = new_ingredients
                tech.localised_description = {"",tech.localised_description or "",{"technology-description.technology-research-ingredients-corrected"}}
            end
            
        end
    end

    for _,container in pairs(data.raw["proxy-container"]) do
        if container.circuit_connector and type(container.circuit_connector[1]) ~= "table" then
            container.circuit_connector = {container.circuit_connector}
            container.localised_description = {"",container.localised_description or "",{"technology-description.circuit-connector-corrected"}}
        end
        
    end



end

return Public