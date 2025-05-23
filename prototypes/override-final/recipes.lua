local lib = require("lib.lib")

-- keep track of what categories we had
local registerted_categories = {}

for _, recipe in pairs(data.raw["recipe"]) do
    if recipe["planetslib_recipe_category"] ~= nil then
        local assemblers = recipe["planetslib_recipe_category"]

        -- the category name is made of a prefix, and the names of the assemblers it is attached to.
        local category_name = "psl-recipe"
        for _, name in pairs(assemblers.assemblers) do
            category_name = category_name .. "-" .. name
        end
        for _, name in pairs(assemblers.furnaces) do
            category_name = category_name .. "-" .. name
        end
        recipe.category = category_name

        -- we only register the category if it was not registered already.
        if not lib.contains(registerted_categories, category_name) then
            data:extend {
                {
                    type = "recipe-category",
                    name = category_name
                }
            }
            -- attach the new category to all machines that can use it.
            -- checking if the category is already on the machine is technically redundant, but lets keep it here anyways for added security.
            for _, name in pairs(assemblers.assemblers) do
                local categories = data.raw["assembling-machine"][name].crafting_categories
                if not lib.contains(categories, categories) then
                    table.insert(categories, category_name)
                end
            end
            for _, name in pairs(assemblers.furnaces) do
                local categories = data.raw["furnaces"][name].crafting_categories
                if not lib.contains(categories, categories) then
                    table.insert(categories, category_name)
                end
            end

            table.insert(registerted_categories,category_name)
        end
    end
end
