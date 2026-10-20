---
sidebar_label: Rocket Part Recipes
---
# Rocket Part Recipes

You can use the library to assign unique rocket part recipes to rocket silos placed on a specified planet to increase or decrease the difficulty of launching rockets on the planet. Rocket silos with their recipe fixed to the vanilla `rocket-part` recipe are targeted by PlanetsLib. To implement:

* Use the helper function `PlanetsLib.assign_rocket_part_recipe(planet,recipe,lock_silo(default = true))` to assign a recipe to a planet, and optionally determine if the rocket silo has its recipe locked on that planet. `planet` and `recipe` may each be a name or a prototype.
    * The first planet assigned a recipe receives a hidden `PlanetsLib-is-<planet>` surface condition, restricting the recipe to that planet. If the same recipe is assigned to a second planet, PlanetsLib removes that condition and marks the recipe as shared. The restriction is not reapplied, even if the second planet is later assigned a different recipe.
    * `lock_silo` defaults to `true`. Passing `false` is preserved and leaves the silo unlocked.
    * PlanetsLib stores rocket part recipe assignments in a mod-data prototype named `Planetslib-planet-rocket-part-recipe`. Planets with their own system for assigning rocket part recipes are exempted with the assigned recipe name `_other`. Muluna and Maraxsis are currently exempted in this manner to maintain backwards compatibility with those mods.
    * PlanetsLib stores silo recipe lock data in a mod-data prototype named `Planetslib-planet-lock-rocket-silos`. For planets with undefined lock behavior, PlanetsLib will check if a planet has multiple valid rocket silo recipes before unlocking the silo. If only one valid recipe exists, PlanetsLib will lock the silo on placement.
    * Planets without an assigned recipe default to the vanilla `rocket-part` recipe.

