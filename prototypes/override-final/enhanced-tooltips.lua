local rro = PlanetsLib.rro

--- Check that the recipe result references an item prototype that has spoilage.
--- A recipe result is defined as {name="foo", amount=...}.
--- Items and their subtypes (capsule, ammo, etc.) are stored in data.raw under their respective type tables.
--- This function iterates through all "item" prototype types to verify the result's item exists and has a non nil spoil_ticks.
---@param result table A recipe result with a 'name' field
---@return boolean True if the result references an item with spoil_ticks defined
local function assert_recipe_result_is_eligible(result)
    for type_, _ in pairs(defines.prototypes.item) do
        if data.raw[type_] and data.raw[type_][result.name] and data.raw[type_][result.name].spoil_ticks ~= nil then
            return true
        end
    end
    return false
end

if settings.startup["PlanetsLib-enhanced-tooltips"].value == true then
    for _,recipe in pairs(data.raw["recipe"]) do
        if recipe.results and rro.count(
            recipe.results,
            function(result) return assert_recipe_result_is_eligible(result) end
            ) > 0 then
            local i = 200
            for _,tooltip_name in pairs({"result_is_always_fresh","reset_freshness_on_craft"}) do
                i = i + 1
                local value = "gui.no"
                print(recipe.name)
                if recipe[tooltip_name] == true then
                    
                    value = "gui.yes"

                end
                --Recipes don't seem to support custom tooltip fields.
                -- recipe.localised_description = {"",recipe.localised_description or {"recipe-description." .. recipe.name}, {"tooltip.result-is-always-fresh"},{value}}
                -- local item = data.raw["item"][recipe.main_product]
                -- if recipe.main_product and data.raw["item"][recipe.main_product] then
                --     data.raw["item"][recipe.main_product].localised_description = {"",data.raw["item"][recipe.main_product].localised_description or {"item-description." .. recipe.name}, {"tooltip.result-is-always-fresh"},{value}}
                -- end
                
                local tooltip = {
                            name = {"tooltip." .. string.gsub(tooltip_name,"_","-")},
                            --quality_header = "quality-tooltip.decreases",
                            value = {value},
                            order = i,
                            --order = 2,
                            --quality_values = {}
                        }  
                if not recipe.custom_tooltip_fields then recipe.custom_tooltip_fields = {} end
                rro.soft_insert(recipe.custom_tooltip_fields, 
                        tooltip
                    )
                if data.raw["item"][recipe.name] then
                    local item = data.raw["item"][recipe.name]
                    if not item.custom_tooltip_fields then item.custom_tooltip_fields = {} end
                    rro.soft_insert(item.custom_tooltip_fields, 
                        tooltip
                    )
                    --data.raw["item"][recipe.main_product].localised_description = {"",data.raw["item"][recipe.main_product].localised_description or {"item-description." .. recipe.name}, {"tooltip.result-is-always-fresh"},{value}}
                end
                --local item = 
            end
        end
    end


    local function parse_energy_string(s) --ChatGPT
        -- Match: number part, optional prefix, and unit
        -- %d+ matches digits, %.? allows decimal point, 
        -- ([%a]?) captures single optional letter (prefix),
        -- ([%a]+) captures remaining letters (unit).
        local number, prefix, unit = string.match(s,"^(%d+%.?%d*)([%a]?)([%a])$")

        if not number then
            error("Invalid format: " .. s)
        end

        return number, prefix, unit
    end

    -- Converts an energy string into a localised string.
    local function localise_energy(energy)
        local symbols = {
            k="si-prefix-symbol-kilo",
            M="si-prefix-symbol-mega",
            G="si-prefix-symbol-giga",
            T="si-prefix-symbol-tera",
            P="si-prefix-symbol-peta",
            E="si-prefix-symbol-exa",
            Z="si-prefix-symbol-zetta",
            Y="si-prefix-symbol-yotta",
            R="si-prefix-symbol-ronna",
            Q="si-prefix-symbol-quetta",
            W="si-unit-symbol-watt",
            J="si-unit-symbol-joule",
            N="si-unit-symbol-newton",
        }

        if type(energy) == "string" then
            --local j_index = string.find(energy,"J")
            --local prefix_index = j_index - 1
            local number, prefix, unit = parse_energy_string(energy)
            return {"",tostring(number)," ",{symbols[prefix] or ""},{symbols[unit]}}
        else
            return "?"
        end
    
        

    end

    for _,prototype_type in pairs(data.raw) do
        for _,prototype in pairs(prototype_type) do
              if prototype.heating_energy then
                if not prototype.custom_tooltip_fields then prototype.custom_tooltip_fields = {} end
                -- if prototype.name == "steam-recycler" then
                --     error(serpent.block(localise_energy(prototype.heating_energy)))
                -- end
                rro.soft_insert(prototype.custom_tooltip_fields, 
                    {
                        name = {"tooltip.heating-energy"},
                        --quality_header = "quality-tooltip.decreases",
                        value =  localise_energy(prototype.heating_energy),
                        order = 200,
                        --quality_values = {}
                    } 
                )
              end  
        end
    end 
end