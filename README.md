[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/VuVhYUBbWE)[![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/danielmartin0/PlanetsLib)

# PlanetsLib

Code, graphics and conventions to help modders creating planets, moons and other systems. This library is a community project and will grow over time. Anyone is welcome to open a [pull request](https://github.com/danielmartin0/PlanetsLib/pulls) on Github. For feature requests, please open an [issue](https://github.com/danielmartin0/PlanetsLib/issues). For general discussion, use [Discord](https://discord.gg/VuVhYUBbWE).

## Contributors

* [Midnighttigger](https://mods.factorio.com/user/Midnighttigger)
* [thesixthroc](https://mods.factorio.com/user/thesixthroc)
* [Tserup](https://mods.factorio.com/user/Tserup)
* [notnotmelon](https://mods.factorio.com/user/notnotmelon)
* [MeteorSwarm](https://mods.factorio.com/user/MeteorSwarm)
* [Frontrider](https://mods.factorio.com/user/Frontrider)

#### Notes for contributors

* In your pull requests, please list your changes in changelog.txt to be included in the next release. Please also update `README.md` to add sections for your new functionality (even with only 'Documentation pending') and add yourself to the contributors list.
* Contributions MUST be tested before a PR is made, ideally with multiple planets installed.
* We aim to never make any breaking changes. Sometimes APIs are removed from the documentation, that does not mean they are no longer supported.
* Feel free to use the file `todo.md`.

# Documentation

## Defining planets

PlanetsLib provides an API to define planets and space locations. It is a simple wrapper for data:extend.

The reasons one may choose to use it over a plain `data:extend` are some additional features: you can specify positions with respect to a parent body; if the parent body is moved by another mod your planet will move with it; a sprite depicting the orbit can be supplied; and various other mods are sensitive to the orbit tree.

* `PlanetsLib:extend(configs)` — A wrapper/replacement for `data:extend`. Throws an error if passed `distance` or `orientation`. Each config instead takes the fields listed below.
    * `type` — `"planet"` or `"space-location"`
    * `orbit` — Object containing orbital parameters:
        * `parent` — Object containing `name` and `type` fields, corresponding to a parent at `data.raw[type][name]`. Planets in the original solar system should have an orbit with `type = "space-location"` and `name = "star"`.
        * `distance` — Number — orbital distance from parent
        * `orientation` — Number — orbital angle from parent (0-1). Note that orientation is absolute, not relative to the parent's orientation.
        * `sprite` — Object (optional) — Sprite for the planet’s orbit. This will be centered on the parent's location.
    * `sprite_only` — Boolean (optional) — If true, this prototype will be removed in `data-final-fixes` and replaced by its sprites on the starmap (unless it has no sprites, in which case nothing will show).
        * This is useful for constructing stars and other locations that should not have a space platform 'docking ring'.
    * Any other valid `planet` or `space-location` prototype fields.
    * The `distance` and `orientation` fields on the prototype will be generated automatically.
    * See [here](https://github.com/danielmartin0/Cerys-Moon-of-Fulgora/blob/main/prototypes/planet/planet.lua) or [here](https://github.com/danielmartin0/PlanetsLib/issues/12#issuecomment-2585484116) for usage examples.
* `PlanetsLib:update(config)` — Updates the position of a pre-existing space location, as identified by the passed `type` and `name` fields. Any other fields passed will be updated on the prototype, and if the `orbit` field is passed the `distance` and `orientation` fields on the prototype will also be updated, along with the `distance` and `orientation` of its children and grandchildren. Any fields not passed will be left unchanged.

PlanetsLib has some extra compatibility code in `data-final-fixes` in which if a planet has noticed to have a `position` and `orientation` different from that implied by its orbit fields, those values will be treated as authoritative, its `orbit` field will be updated, and a simulated `PlanetsLib:update` call will be made to update the `position` and `orientation` of its children. However, using `PlanetsLib:update` over this method is recommended for compatibility.

Neither `PlanetsLib:extend` nor `PlanetsLib:update` should be called in `data-final-fixes`.

## Planet tiers

The companion mod [PlanetsLib: Tiers](https://mods.factorio.com/mod/PlanetsLibTiers) defines 'tier values' for planets and space locations. Tiers have no functionality by themselves, but are a rough indicator where the planet fits in a vanilla-style game of Space Age for the purposes of other mods that wish to use this information.

With PlanetsLib: Tiers installed, tiers can be accessed with `local tier = data.raw["mod-data"]["PlanetsLib-tierlist"].data[type][name] or data.raw["mod-data"]["PlanetsLib-tierlist"].data.default`

The tier listing is [here on GitHub.](https://github.com/danielmartin0/factorio-PlanetsLib-Tiers/blob/main/data.lua). Players are encouraged to submit edits to keep it up-to-date.

## Planet Cargo Drops technology

You can use the library to restrict cargo drops on your planet until a certain technology is researched. To implement:

* Use the helper function `PlanetsLib.cargo_drops_technology_base(planet, planet_technology_icon, planet_technology_icon_size)` to create a base technology prototype.
    * This will create a technology with name pattern: `planetslib-[planet-name]-cargo-drops`
    * PlanetsLib detects this technology by name. Players will be unable to drop cargo (excluding players and construction robots) to planets with that name before researching the technology.
    * Only the fields `type`, `name`, `localised_name`, `localised_description`, `effects`, `icons` will be defined, so you will need to add `unit` (or `research_trigger`) and prerequisites.
    * A locale entry for this technology is automatically generated, but you are free to override it.
* Note that players can use [this mod](https://mods.factorio.com/mod/disable-cargo-drops-techs) to disable the effect of this restriction.

## Rocket part recipes

You can use the library to assign unique rocket part recipes to rocket silos placed on a specified planet to increase or decrease the difficulty of launching rockets on the planet. Rocket silos with their recipe fixed to the vanilla `rocket-part` recipe are targeted by PlanetsLib. To implement:

* Use the helper function `PlanetsLib.assign_rocket_part_recipe(planet,recipe)` to assign a recipe to a planet.
    * PlanetsLib stores rocket part recipe assignments in a mod-data prototype named `Planetslib-planet-rocket-part-recipe`. Planets with their own system for assigning rocket part recipes are exempted with the assigned recipe name `_other`. Muluna and Maraxsis are currently exempted in this manner to maintain backwards compatibility with those mods.
    * Planets without an assigned recipe default to the vanilla `rocket-part` recipe.

## Surface conditions

#### New surface conditions

PlanetsLib includes a variety of surface conditions, all of which are either hidden or disabled by default. To enable a surface condition, modders must add the following line to settings-updates.lua (using 'oxygen' as an example):

`data.raw["bool-setting"]["PlanetsLib-enable-oxygen"].forced_value = true`

#### Restricting and relaxing conditions

Typically, when planet mods want to modify a surface condition, what they are trying to do is restrict or relax the range of values for which that recipe or entity is allowed.

For example, Space Age recyclers have a maximum magnetic field of 99. If mod A wants to allow recyclers to be built up to 120, whilst mod B wants to allow them up to 150, compatibility issues can arise if mod A acts last and overrides mod B's change (which it ought to have been perfectly happy with). Instead mod A should modify existing surface conditions only if necessary.

Hence `relax_surface_conditions` and `restrict_surface_conditions` are provided, used like so:

* `PlanetsLib.relax_surface_conditions(data.raw.recipe["recycler"], {property = "magnetic-field", max = 120})`
* `PlanetsLib.restrict_surface_conditions(data.raw.recipe["boiler"], {property = "pressure", min = 10})`

NOTE: Calling `relax_surface_conditions` without a `min` field will not remove any existing `min` conditions for that property (and similarly for `max`).

#### Removing surface conditions

* `PlanetsLib.remove_surface_condition(recipe_or_entity, "magnetic-field")` — Removes all `magnetic-field` surface conditions.
* `PlanetsLib.remove_surface_condition(recipe_or_entity, {property = "magnetic-field", max = 120})` — Removes all surface conditions that exactly match the provided condition.

## Science & Technologies

* `PlanetsLib.get_child_technologies(tech_name)` — Returns a list of the names of all technologies that have `tech_name` as a prerequisite.
* `PlanetsLib.sort_science_pack_names(science_pack_names_table)` — Sorts the given list of science pack names (strings expected) by the `order` fields of the corresponding prototypes, or by their names if an `order` field does not exist.
    * This is useful for defining the inputs of labs because (unlike in Factoriopedia) science packs displayed in labs aren't ordered by the `order` field.

### Recipe productivity technology helper field

PlanetsLib adds a new field named `PlanetsLib_recipe_productivity_effects` to technologies, used by recipe productivity technologies. During `data-final-fixes,` technologies with this field will have their effects list appended or replaced with recipes matching either an output name or recipe category.

#### [`TechnologyPrototype`](https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html) field: `PlanetsLib_recipe_productivity_effects` Properties:
*   `effects`: `array[ChangeResultProductivityModifier]`
*   `category_blacklist` - `array[`[`RecipeCategoryID`](https://lua-api.factorio.com/latest/types/RecipeCategoryID.html)`]`
*   `purge_other_effects`- boolean. Default: false. Before adding effects added by `PlanetsLib_recipe_productivity_effects`, remove all effects not flagged with `PlanetsLib_force_include`.

#### `ChangeResultProductivityModifier` Properties:
*   `allow_multiple_results`: boolean. Default: false. When false, only recipes with one result are added to the technology's effect list.
*   `category` (optional) - [`RecipeCategoryID`](https://lua-api.factorio.com/latest/types/RecipeCategoryID.html)  Either `(name and type) or category` required. Forbidden when `category_blacklist ~= nil`.
*   `type` (optional) - [`ProductPrototype`](https://lua-api.factorio.com/latest/types/ProductPrototype.html)
*   `name` (optional) - [`ItemID`](https://lua-api.factorio.com/latest/types/ItemID.html)
##### Inherited from [`ChangeRecipeProductivityModifier`](https://lua-api.factorio.com/latest/types/ChangeRecipeProductivityModifier.html)
*   `change`
*   `icons` (optional)
*   `icon` (optional)
*   `icon_size` (optional)
*   `hidden` (optional)
*   `use_icon_overlay_constant` (optional)

#### New [`BaseModifier`](https://lua-api.factorio.com/latest/types/BaseModifier.html) field: `PlanetsLib_force_include`
*  Makes this modifier immune to `purge_other_effects`.

#### New ['RecipePrototype'](https://lua-api.factorio.com/latest/prototypes/RecipePrototype.html) field: `PlanetsLib_blacklist_technology_updates`
*  Stops PlanetsLib from targeting this recipe in technology updates.

#### Tech tree adjustments

* `PlanetsLib.excise_tech_from_tech_tree(tech_name)` — Seamlessly removes a technology from the tech tree by making all its dependencies depend instead on the technology's prerequisites. In addition, `hidden = true` is set on the technology.
* `PlanetsLib.excise_recipe_from_tech_tree(recipe_name)` — Removes this recipe from all technologies, and if this would cause any technology to have zero effects, the technology is excised using `PlanetsLib.excise_tech_from_tech_tree`.
* `PlanetsLib.excise_effect_from_tech_tree(effect)` — Similar to `excise_recipe_from_tech_tree`, but any effect can be passed.
    * Example: `PlanetsLib.excise_effect_from_tech_tree({ type = "unlock-quality", quality = "uncommon" })`
* `PlanetsLib.add_science_packs_from_vanilla_lab_to_technology(technology)` — Adds all science packs that the vanilla lab have slots for to the unit of the given technology. Can be useful when defining endgame technologies.

#### Biolab

Because modders often forget about the Biolab, PlanetsLib mirrors all science packs from the vanilla lab to the Biolab in `data-final-fixes`.

## Subgroups

Subgroups are rows in Factoriopedia.

* `satellites` — A new Factoriopedia row for satellites (below the planets row).
    * Note that being in this subgroup affects [Redrawn Space Connections](https://mods.factorio.com/mod/Redrawn-Space-Connections) and [Cosmic Social Distancing](https://mods.factorio.com/mod/Cosmic-Social-Distancing).

## Assorted helpers

* `PlanetsLib.technology_icon_moon(tech_icon: string, icon_size: integer)` — Creates a moon discovery technology icon by adding a little moon icon on your technology icon, like in vanilla, but for moon type planets.
* `PlanetsLib.technology_icon_planet(tech_icon: string, icon_size: integer)` — Creates a planet discovery technology icon by adding a little planet icon on your technology icon, like in vanilla.
* `PlanetsLib.set_default_import_location(item_name, planet_name)` — Sets the default import location for an item on a planet.
* `PlanetsLib.borrow_music(source_planet, target_planet)` — Clones music tracks from `source_planet` prototype to `target_planet` prototype. Does not overwrite existing music for `target_planet`. To clone music from or to space platforms, set the respective parameter to "space-platform." Otherwise, use the relevant planet object.

#### Assorted graphics

* `__PlanetsLib__/graphics/icons/research-progress-product.png` — an iconographic science pack icon intended for items used exclusively as ResearchProgressProducts, since mods using a common icon might help players understand the mechanic.

#### Python helper scripts

* `lib/orbit_graphic_generator.py` — contains a Python script that generates orbit sprites. `generate_orbit(distance, output_file, mod_name)`, `distance` being the same as your orbital distance. After generating your sprite, the script will print a block of lua code that imports your sprite with proper scaling. Orbit sprites should be scaled at 0.25 to ensure that no pixels are visible on 4K monitors.

---

[![Discord](https://img.shields.io/discord/1309620686347702372?style=for-the-badge&logo=discord&logoColor=bf6434&label=The%20Foundry&labelColor=222222&color=bf6434)](https://discord.gg/VuVhYUBbWE)