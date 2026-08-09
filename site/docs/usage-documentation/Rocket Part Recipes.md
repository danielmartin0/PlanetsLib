You can use the library to assign unique rocket part recipes to rocket silos placed on a specified planet to increase or decrease the difficulty of launching rockets on the planet. Rocket silos with their recipe fixed to the vanilla `rocket-part` recipe are targeted by PlanetsLib. To implement:

* Use the helper function `PlanetsLib.assign_rocket_part_recipe(planet,recipe,lock_silo(default = true))` to assign a recipe to a planet, and optionally determine if the rocket silo has its recipe locked on that planet.
    * PlanetsLib stores rocket part recipe assignments in a mod-data prototype named `Planetslib-planet-rocket-part-recipe`. Planets with their own system for assigning rocket part recipes are exempted with the assigned recipe name `_other`. Muluna and Maraxsis are currently exempted in this manner to maintain backwards compatibility with those mods.
    * PlanetsLib stores silo recipe lock data in a mod-data prototype named `Planetslib-planet-lock-rocket-silos`. For planets with undefined lock behavior, PlanetsLib will check if a planet has multiple valid rocket silo recipes before unlocking the silo. If only one valid recipe exists, PlanetsLib will lock the silo on placement.
    * Planets without an assigned recipe default to the vanilla `rocket-part` recipe.

