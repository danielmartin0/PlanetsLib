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

for _,prototype in pairs(item_categories) do
    for _,item in pairs(data.raw[prototype]) do
        if item.spoil_ticks and item.spoil_result then
            if not item.PlanetsLib_spoil_category then
                item.PlanetsLib_spoil_category = "spoil"
            end
            if item.PlanetsLib_spoil_category then
                assert(type(item.PlanetsLib_spoil_category) == "string","PlanetsLib: ItemPrototype::PlanetsLib_spoil_category must be a string.")
                PlanetsLib.item_spoil_category[item] = item.PlanetsLib_spoil_category
                local spoil_category_info = PlanetsLib.constants.spoil_categories[item.PlanetsLib_spoil_category]
                assert(spoil_category_info,"Invalid spoil category ".. item.PlanetsLib_spoil_category .. "assigned to item" .. item.name .. ".")
                if not item.custom_tooltip_fields then item.custom_tooltip_fields = {} end
                table.insert(item.custom_tooltip_fields,{
                    name = spoil_category_info.localised_spoil_result,
                    value = "",
                })
            end
        end
    end
end
