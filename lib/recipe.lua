
local icon_entry = require("lib.icon-entry")

local Public = {}

--- Returns an asteroid crushing icon resembling a basic asteroid crushing icon from vanilla Space Age, using a copper-colored crushing icon. Used by "Muluna, Moon of Nauvis" and "Crushing Industry." 
--- @param icon_dir string(sprite)
--- @param icon_size integer
--- @return table(IconData)
function Public.crushing_recipe_icons(icon_dir,icon_size)
return {
    {
        icon = icon_dir,
        icon_size=64,
        --scale=0.3,
        shift = {0,-3},
        scale=50/128,
        draw_background = true
    },
    {
        icon = "__PlanetsLib__/graphics/icons/generic-crushing.png",
        icon_size=64,
        scale=0.5,
        draw_background = true
    },
}

end

--- Returns an asteroid crushing icon resembling a basic asteroid crushing icon from vanilla Space Age. Uses a yellow crushing icon. 
--- @param icon_dir string(sprite)
--- @param icon_size integer
--- @return table(IconData)
function Public.asteroid_crushing_recipe_icons(icon_dir,icon_size)
return {
    {
        icon = icon_dir,
        icon_size=64,
        --scale=0.3,
        shift = {0,-3},
        scale=50/128,
        draw_background = true
    },
    {
        icon = "__PlanetsLib__/graphics/icons/asteroid-crushing.png",
        icon_size=64,
        scale=0.5,
        draw_background = true
    },
}
end


--- Returns an asteroid crushing icon resembling an advanced asteroid crushing icon from vanilla Space Age.
--- @param asteroid_icon string(sprite)
--- @param product_1 string(sprite)
--- @param product_2 string(sprite)
--- @param variant string(Union["checkerboard","horizontal","vertical"])
--- @return table(IconData)
function Public.advanced_crushing_recipe_icons(asteroid_icon,product_1,product_2,variant)
    if not variant then variant = "checkerboard" end
    local icons = {}
    if variant == "checkerboard" then
        icons = {product_1,product_1,product_2,product_2}
    elseif variant == "horizontal" then
        icons = {product_2,product_1,product_1,product_2}
    elseif variant == "vertical" then
        icons = {product_1,product_2,product_1,product_2}
    else
        error("Invalid asteroid crushing icon variant provided. Must be \"checkerboard\",  \"horizontal\", or  \"vertical\".")
    end
    return {
        {
            icon = icons[1],
            icon_size=64,
            scale = 0.25,
            shift = {-8,8},
            draw_background = true
        },
        {
            icon = icons[2],
            icon_size=64,
            scale = 0.25,
            shift = {8,-8},
            draw_background = true
        },
        {
            icon = icons[3],
            icon_size=64,
            scale = 0.25,
            shift = {-8,-8},
            draw_background = true
        },
        {
            icon = icons[4],
            icon_size=64,
            scale = 0.25,
            shift = {8,8},
            draw_background = true
        },
        {
            icon = asteroid_icon,
            icon_size=64,
            scale=0.4,
            draw_background = true
        },
    }
    

end


--- Returns a "melting" recipe icon, resembling the vanilla Space Age recipes that melt an ore
--- together with calcite into a molten metal: the catalyst and the ore are shown small at the
--- top, with the molten product drawn large across the front.
--- Each argument is a prototype name (string); the prototype type is detected automatically and a
--- single icon is taken from the prototype's `icon`/`icons` field (see `PlanetsLib.dual_icon`).
--- Used by "Muluna, Moon of Nauvis".
--- @param metal string Name of the molten product (drawn largest, in front).
--- @param ore string Name of the ore being melted.
--- @param catalyst string optional Name of the catalyst. Defaults to "calcite".
--- @return table(IconData)
function Public.melting_icon(metal,ore,catalyst)
    catalyst = catalyst or "calcite"
    local type_metal,proto_metal = icon_entry.get_prototype(metal)
    local type_ore,proto_ore = icon_entry.get_prototype(ore)
    local type_catalyst,proto_catalyst = icon_entry.get_prototype(catalyst)
return {
    icon_entry.build_icon_entry(proto_catalyst,type_catalyst,catalyst,0.25,{8,-8},nil,true),
    icon_entry.build_icon_entry(proto_ore,type_ore,ore,0.25,{-8,-8},nil,true),
    icon_entry.build_icon_entry(proto_metal,type_metal,metal,0.45,{-2,3},nil,true),
}

end


return Public