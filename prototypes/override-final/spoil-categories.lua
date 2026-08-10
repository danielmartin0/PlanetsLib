local item_categories = {
    "ammo",
    "capsule",
    "gun",
    "item-with-entity-data",
    "item-with-label",
    "item-with-inventory",
    "blueprint-book",
    "item-with-tags",
    "selection-tool",
    "blueprint",
    "copy-paste-tool",
    "deconstruction-item",
    "spidertron-remote",
    "upgrade-item",
    "module",
    "rail-planner",
    "space-platform-starter-pack",
    "tool",
    "armor",
    "repair-tool",
    "item",
}

local function spoil_time(ticks)
    return (ticks / 60^3 >= 1 and (tostring(math.floor(ticks / 60^3)) .. "h") or "") .. 
                                (ticks / 60^2 >= 1 and tostring(math.floor(ticks % 60^3 / 60^2)) .. "m" or "") .. 
                                tostring(ticks % 60^2 / 60) .. "s"

end

for _,prototype in pairs(item_categories) do
    if data.raw[prototype] then
        for _,item in pairs(data.raw[prototype]) do
            if item.spoil_ticks and item.spoil_result then
                if not item.PlanetsLib_spoil_category then
                    item.PlanetsLib_spoil_category = "spoilable"
                end
                if item.PlanetsLib_spoil_category then
                    assert(type(item.PlanetsLib_spoil_category) == "string","PlanetsLib: ItemPrototype::PlanetsLib_spoil_category must be a string.")
                    PlanetsLib.constants.item_spoil_category[item.name] = item.PlanetsLib_spoil_category
                    local spoil_category_info = PlanetsLib.constants.spoil_categories[item.PlanetsLib_spoil_category]
                    assert(spoil_category_info,"Invalid spoil category ".. item.PlanetsLib_spoil_category .. " assigned to item" .. item.name .. ".")
                    
                    if item.PlanetsLib_spoil_category ~= "spoilable" then
                        if not item.custom_tooltip_fields then item.custom_tooltip_fields = {} end
                        table.insert(item.custom_tooltip_fields,{
                            name = {"tooltip.spoil-category"},
                            value = spoil_category_info.localised_name,
                        })

                        
                        local spoil_time_field = {
                            name = spoil_category_info.localised_spoil_time,
                            value = spoil_time(item.spoil_ticks),
                            quality_values = {},
                            quality_header = spoil_category_info.quality_header
                        }
                        for _,quality in pairs(data.raw.quality) do
                            spoil_time_field.quality_values[quality.name] = spoil_time(item.spoil_ticks * (quality.spoil_ticks_multiplier or (1 + 0.3 * quality.level)))
                        end
                        table.insert(item.custom_tooltip_fields,spoil_time_field)
                        if item.spoil_result then
                            table.insert(item.custom_tooltip_fields,{
                            name = spoil_category_info.localised_spoil_result,
                            value = data.raw.item[item.spoil_result] and data.raw.item[item.spoil_result].localised_name or {"item-name."..item.spoil_result},
                        })
                        end
                    end
                    
                end
            end
        end
    end
    
end
