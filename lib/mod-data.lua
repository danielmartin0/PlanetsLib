local Public = {}

function Public.assign_rocket_part_recipe(planet,recipe) 
    local planet_name
    local recipe_name
    if type(planet) == "list" then
        planet_name = planet.name
    else
        planet_name = planet
    end
    if type(recipe) == "list" then
        recipe_name = recipe.name
    else
        recipe_name = recipe
    end
    data.raw["mod-data"]["Planetslib-planet-rocket-part-recipe"].data[planet_name] = recipe_name

end



return Public