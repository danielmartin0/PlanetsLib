[![foundrygg.com](https://img.shields.io/badge/foundrygg-4a1402?style=for-the-badge&logo=vercel&logoColor=white)](https://foundrygg.com)[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/nFVqaPEk97)[![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/danielmartin0/PlanetsLib)

# PlanetsLib

Code and graphics to help modders creating planets, moons and other systems. This library is a community project. Anyone is welcome to open a [pull request](https://github.com/danielmartin0/PlanetsLib/pulls) on Github. For feature requests, please open an [issue](https://github.com/danielmartin0/PlanetsLib/issues). For general discussion, use [Discord](https://discord.gg/nFVqaPEk97).

Since other mods make use of the 'orbit structure' this mod provides to the solar system, it is recommended to add PlanetsLib compatibility to your planet mod either by defining your planet prototype using PlanetsLib (as in the first image in the [mod portal gallery](https://mods.factorio.com/mod/PlanetsLib)), or by calling `PlanetsLib:update` in data-updates.lua (second image in the gallery). Besides improving compatibility with PlanetsLib consumers, this means if another mod updates the position of your planet's orbital parent without moving your planet, your planet will be moved too.

We aim to *never make any breaking API changes* such that the library is safe to use. We sometimes deprecate APIs by removing them from the documentation, but they stay functional.

# Player-facing features

The primary intent of PlanetsLib is to be a library which provides opt-in functionality for other mods. However, a small number of game-affecting or player-interface-affecting features have been added over time. These are listed below, player feedback on them is most welcome in [Discord](https://discord.gg/nFVqaPEk97).

* Unlinking hidden prerequisites
    * If PlanetsLib detects that technologies have hidden prerequisites such that they would be unresearchable, it warns players about this fact.
        * This is done because the Factorio client gives no explanation or reason for why these technologies cannot be researched.
        * There are PlanetsLib mod settings to repair the user's game by unlinking all such prerequisites, or to disable the warning.
* Fixed rocket weights of vanilla items
    * If an item prototype does not have an explicitly specified rocket weight, the behavior of the Factorio engine is to assign it a weight based on the recipes that produce it. Unfortunately, this means that the rocket weight of vanilla items is liable to change when additional mods are installed. PlanetsLib therefore sets an explicit weight on vanilla items equal to their weight in Space Age. This occurs in `data-final-fixes` and only if the item does not have a weight by that point.
* Extra informational tooltips
    * On recipes:
        * Freshness resets on craft completion
            * This tracks `result_is_always_fresh` and only appears if `true`.
        * Freshness resets on craft beginning
            * This tracks `reset_freshness_on_craft` and only appears if `true`.
        * Products preserved in machine output
            * This tracks `preserve_products_in_machine_output` and only appears if `true`.
    * All such tooltips are added in `data-final-fixes`.
* Biolab inputs
    * Because modders often forget about the Biolab when adding a new science pack, PlanetsLib mirrors all science packs from the vanilla lab to the Biolab in `data-final-fixes`.
* Centrifuge entity improvements
    * This entity is given an input and an output fluidbox (or two of each if the mod setting `PlanetsLib-enable-additional-centrifuge-fluidboxes` is enabled).
    * Also, the graphics of the working glow are improved so that it naturally glows different colors depending on the recipe.
* Space tile without the ability to cover it
    * A space tile that can be used around limited surfaces floating in space, as it can not be covered in space platform tiles. Modders, enable it with the `PlanetsLib-enable-blocking-empty-space-tile` setting. The name of the tile is `planetslib-empty-space`, all localization is set to match the regular `empty-space` tile from space age.
# Notes for contributors

* In your pull requests, please list your changes in changelog.txt to be included in the next release. Please also update `README.md` to add sections for your new functionality (even with only 'Documentation pending') and add yourself to the contributors list.
* Contributions MUST be tested before a PR is made, ideally with multiple planets installed.
* Feel free to use the file `todo.md`.

# API documentation

## Defining planets

PlanetsLib provides an API to define planets and space locations. It is a simple wrapper for data:extend.

The reasons one may choose to use it over a plain `data:extend` are some additional features: you can specify positions with respect to a parent body; if the parent body is moved by another mod your planet will move with it; a sprite depicting the orbit can be supplied; and various other mods are sensitive to the orbit tree.

* `PlanetsLib:extend(configs)` — Throws an error if passed `distance` or `orientation`. (as these will be generated automatically on the prototype.) Instead, it takes the following fields:
    * `orbit` — Object containing orbital parameters:
        * `parent` — Object containing `name` and `type` fields, corresponding to a parent at `data.raw[type][name]`. Planets in the original solar system should have an orbit with `type = "space-location"` and `name = "star"`.
        * `distance` — Number — orbital distance from parent
        * `orientation` — Number — orbital angle from parent (0-1). Note that orientation is absolute, not relative to the parent's orientation.
        * `sprite` — Object (optional) — Sprite for the planet’s orbit. This will be centered on the parent's location. If the parent is a planet that becomes hidden, the orbit sprite will not be drawn.
    * `type` — `"planet"` or `"space-location"`
    * `special_properties` — Table (optional). The value of this field is passed to `data.raw["mod-data"]["Planetslib"].data.planet_properties[planet.name]`.
    * `sprite_only` — Boolean (optional) — If true, this prototype will be removed in `data-final-fixes` and replaced by its sprites on the starmap (unless it has no sprites, in which case nothing will show).
        * This is useful for constructing stars and other locations that should not have a space platform 'docking ring'.
    * `is_satellite` — Boolean (optional) — Has no effect in PlanetsLib, but other mods such as [Redrawn Space Connections](https://mods.factorio.com/mod/Redrawn-Space-Connections) are sensitive to this field. (Conventionally, such mods also treat `subgroup = "satellites"` planets as satellites, this is the legacy marker.)
    * Any other valid `planet` or `space-location` prototype fields.
    * See [here](https://github.com/danielmartin0/Cerys-Moon-of-Fulgora/blob/main/prototypes/planet/planet.lua) or [here](https://github.com/danielmartin0/PlanetsLib/issues/12#issuecomment-2585484116) for usage examples.
* `PlanetsLib:update(configs)` — Updates the position of a pre-existing space location, as identified by the passed `type` and `name` fields. Any other fields passed will be updated on the prototype, and if the `orbit` field is passed the `distance` and `orientation` fields on the prototype will also be updated, along with the `distance` and `orientation` of its children and grandchildren. Any fields not passed will be left unchanged. Fields of `special_properties` will be merged with pre-existing fields of `special_properties`, replacing overlapping fields.

PlanetsLib has some extra compatibility code in `data-final-fixes` in which if a planet has noticed to have a `position` and `orientation` different from that implied by its orbit fields, those values will be treated as authoritative, its `orbit` field will be updated, and a simulated `PlanetsLib:update` call will be made to update the `position` and `orientation` of its children. However, using `PlanetsLib:update` to update planetary positions is generally recommended.

Please note that the orbit structure does not yet dictate layering of the sprites on the spacemap – this is a desired feature from future contributors, it has not been built yet.

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
    * It's possible to add items to cargo drop whitelists using the following APIs ('entity type' refers to the type of the entity with the same name as the item):
        * `PlanetsLib.add_item_name_to_planet_cargo_drops_whitelist(planet_name, item_name)`
        * `PlanetsLib.add_entity_type_to_planet_cargo_drops_whitelist(planet_name, entity_type)`
        * `PlanetsLib.add_item_name_to_global_cargo_drops_whitelist(item_name)`
        * `PlanetsLib.add_entity_type_to_global_cargo_drops_whitelist(entity_type)`
* Note that players can use [this mod](https://mods.factorio.com/mod/disable-cargo-drops-techs) to disable the effect of this restriction.

## Rocket part recipes

You can use the library to assign unique rocket part recipes to rocket silos placed on a specified planet to increase or decrease the difficulty of launching rockets on the planet. Rocket silos with their recipe fixed to the vanilla `rocket-part` recipe are targeted by PlanetsLib. To implement:

* Use the helper function `PlanetsLib.assign_rocket_part_recipe(planet,recipe,lock_silo(default = true))` to assign a recipe to a planet, and optionally determine if the rocket silo has its recipe locked on that planet.
    * PlanetsLib stores rocket part recipe assignments in a mod-data prototype named `Planetslib-planet-rocket-part-recipe`. Planets with their own system for assigning rocket part recipes are exempted with the assigned recipe name `_other`. Muluna and Maraxsis are currently exempted in this manner to maintain backwards compatibility with those mods.
    * PlanetsLib stores silo recipe lock data in a mod-data prototype named `Planetslib-planet-lock-rocket-silos`. For planets with undefined lock behavior, PlanetsLib will check if a planet has multiple valid rocket silo recipes before unlocking the silo. If only one valid recipe exists, PlanetsLib will lock the silo on placement.
    * Planets without an assigned recipe default to the vanilla `rocket-part` recipe.

## Planet-Exclusive Entity Variants

PlanetsLib allows you to quickly generate planet-exclusive variants of entities. On placing an entity on a planet with a planet-exclusive variant, PlanetsLib will replace the original entity with your variant. The difference between entity variants and the original entity are invisible to the user, and variants can not be seen in the Factoriopedia. Every variant must be associated with a boolean startup setting that can be disabled to ease in uninstallation. Once an entity variant has been created, any attempt to create a variant for the same entity for the same planet will throw an error. This is a limitation of the current system that may change in the future. Currently, entity variants that are the same type as their origin entity are well-tested, but changing entity types is untested.

Known issues: Variant entities will be the same fast_replaceable_group as the entity they're based on. This makes it possible to place over the variant entity with the entity's item. This is an engine limitation.

* `PlanetsLib.create_planet_entity_variant(planet_names(table of strings or string),entity(table),new_properties(table),bound_setting(startup setting name),item_name(defaults to entity name))` – Creates and adds to data.raw a variant of `entity` with a unique name, the same localized name/description, and new properties taken from new_properties. When `entity` is placed on planet during gameplay, PlanetsLib will replace entity with new_entity. `bound_setting` is a boolean startup setting. This entity variant is only placed when this startup setting is enabled. When disabling this startup setting on an existing save, variant entities are migrated back to their original entities when appropriate. When enabling this startup setting on an existing save, variant entities are migrated from their original entities when appropriate. To aid in mod uninstallation, expose this setting to users.
* `PlanetsLib.assign_entity_replacement(planet,entity,new_entity,bound_setting)` – When `entity` is placed on planet during gameplay, PlanetsLib will replace entity with new_entity. Due to current system limitations, assigning an entity replacement of the same entity onto the same planet will throw an error. Not recommended for regular use due to the lack of safety checks compared to PlanetsLib.create_planet_entity_variant().

## Entity variant migrations

On adding new entity replacement rules to an existing save or disabling old replacement rules, PlanetsLib will perform a runtime migration on all entities in violation of the current ruleset to comply with the new ruleset. This process includes copying the settings, wire connections, inventories, fluidbox contents, health, crafting progress, and a myriad of other settings associated with entities. This process is not perfect, so reports of incomplete migrations are welcome. 

## Safely disabling an entity replacement rule

Each entity replacement rule must be associated with a startup setting, defined with `bound_setting`. When this setting is enabled, entity replacements are active. When this setting is disabled, variant entities are generated in data, allowing saves with obsolete rules to load without deleting any entities. However, on loading a save, all variant entities that should not exist under the current ruleset are replaced with their original entity, reverting all replacements performed under that rule.

To safely remove an entity replacement from the game, disable the associated startup setting, load the save to allow the migration to occur, then remove the mod. When updating a mod to revert an entity replacement rule, apply a conventional migration to all affected entities, or if not possible, hide and force disable the associated setting, rather than deleting code adding the replacement rule. After you are ready to make old saves break their migration, you can delete the associated code.

### Making your entity compatible with PlanetsLib's entity replacement script

If you have a script-augmented entity and a PlanetsLib entity replacement targets your entity, `PlanetsLib.constants.entity_variants_list` contains a list of entity variants for each entity. For scripted entity `"scripted_entity"`, A list of variant entities will be found in `PlanetsLib.constants.entity_variants_list["scripted_entity"]` if any exist. To make your script-augmented entity compatible, add entities from this list to any entity name checks in your control stage. If PlanetsLib replaces an entity tracked in your mod's storage, `remote.call("planetslib_entity_replacement","get_replacement",entity_unit_number)` will return the LuaEntity that replaced your entity. Use this function to repair stale references.

* Custom event: `PlanetsLib.events.on_entity_replaced(event)`
* Runs when PlanetsLib replaces an entity. Use this event to change variables associated with script-augmented entities to refer to the new entity.
* `event` fields:
    * `entity(LuaEntity)`: The entity about to be deleted.
    * `new_entity(LuaEntity)`: The entity that has had `entity`'s settings and inventory transferred to. 

## Planet Special Properties
PlanetsLib allows the addition of "special properties", values which can be displayed as surface properties, but are not intended to be used as surface properties. These properties are used during data-final-fixes and in control scripts to execute certain behavior.

* `PlanetsLib.set_special_properties(planet(table or string),properties(table)) -> table` — Sets the special properties of a planet. Can not be called during data-final-fixes.
* `PlanetsLib.get_special_property(planet(table or string),property(string)) -> object` — Returns the value of a single special property.
* `PlanetsLib.get_special_properties(planet(table or string)) -> table` — Returns the entire `special_properties` table of a planet.

### Hardcoded Special Properties
PlanetsLib reserves two special property values for runtime scripts set up during data-final-fixes. They are displayed as surface properties in game. If no mods define these properties, they are not displayed.
* `rocket_lift_multiplier(float)` — Multiplies the lift of every rocket silo placed on the planet. Achieved via runtime entity replacements generated during data-final-fixes(See Planet-Exclusive Entity Variants).
* `rocket_part_multiplier(float)` — Multiplies the rocket parts required of every rocket silo placed on the planet. Achieved via runtime entity replacements generated during data-final-fixes(See Planet-Exclusive Entity Variants).

## Surface conditions

#### New surface properties

PlanetsLib includes a variety of surface properties, all of which are either hidden or disabled by default. To enable a surface property, modders must add the following line to settings-updates.lua (using 'oxygen' as an example):

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

PlanetsLib adds a new field named `PlanetsLib_recipe_productivity_effects` to technologies, used by recipe productivity technologies. During `data-final-fixes`, technologies with this field will have their effects list appended or replaced with recipes matching either an output name or recipe category. Recipes will be excluded if they have the field `PlanetsLib_blacklist_technology_updates` set to true `true`.

Recipe products are ignored if they are not "productivity-capable"—if `ignored_by_productivity` is greater than or equal to `amount` (or `amount_max`)—because changing a recipe's productivity has no effect on such products. If a recipe has no productivity-capable products, it is fully ineligible; and if a recipe has multiple products, but only one product is productivity-capable (e.g. Kovarex enrichment), it is eligible _even if `allow_multiple_results` = false_.

#### [`TechnologyPrototype`](https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html) field: `PlanetsLib_recipe_productivity_effects` Properties:
*   `effects`: `array[ChangeResultProductivityModifier]`
*   `category_blacklist` - `array[`[`RecipeCategoryID`](https://lua-api.factorio.com/latest/types/RecipeCategoryID.html)`]`
*   `purge_other_effects`- `boolean`. Default: false. Before adding effects added by `PlanetsLib_recipe_productivity_effects`, remove all 
effects not flagged with `PlanetsLib_force_include`.
*   `allow_recipes_without_productivity` - `boolean`. Default: false. Captures recipes even if they have `allow_productivity` set to false.

#### `ChangeResultProductivityModifier` Properties:
*   `name` (optional) - [`ItemID`](https://lua-api.factorio.com/latest/types/ItemID.html) Required if not using `category`. Incompatible with `category`.
*   `type` (optional) - [`ProductPrototype`](https://lua-api.factorio.com/latest/types/ProductPrototype.html) Required if using `name`.
*   `category` (optional) - [`RecipeCategoryID`](https://lua-api.factorio.com/latest/types/RecipeCategoryID.html)  Required if not using `name`. Incompatible with `name` and `category_blacklist`.
*   `allow_multiple_results`: `boolean`. Default: false. When false, only recipes with one (productivity-capable) result are added to the technology's effect list. If multiple results have the same name, they are counted as a single result rather than being counted individually.
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

#### Example
```
{
   type = "technology",
   name = "thruster-fuel-productivity",
   --Other required fields here
   PlanetsLib_recipe_productivity_effects = {
               purge_other_effects = true,
               effects = {
                   {
                       type = "fluid",
                       name = "thruster-fuel",
                       change = 0.1
                   },
                   {
                       type = "fluid",
                       name = "thruster-oxidizer",
                       change = 0.1
                   },
               }
           }
}
```

#### Tech tree adjustments

* `PlanetsLib.excise_tech_from_tech_tree(tech_name)` — Seamlessly removes a technology from the tech tree by making all its dependencies depend instead on the technology's prerequisites. In addition, `hidden = true` is set on the technology.
* `PlanetsLib.excise_recipe_from_tech_tree(recipe_name)` — Removes this recipe from all technologies, and if this would cause any technology to have zero effects, the technology is excised using `PlanetsLib.excise_tech_from_tech_tree`.
* `PlanetsLib.excise_effect_from_tech_tree(effect)` — Similar to `excise_recipe_from_tech_tree`, but any effect can be passed.
    * Example: `PlanetsLib.excise_effect_from_tech_tree({ type = "unlock-quality", quality = "uncommon" })`
* `PlanetsLib.add_science_packs_from_vanilla_lab_to_technology(technology)` — Adds all science packs that the vanilla lab have slots for to the unit of the given technology. Can be useful when defining endgame technologies.

## Achievements

Planetslib includes functions to generate certain kinds of achievements.

* `PlanetsLib.visit_planet_achievement(planet: SpaceLocationPrototype, icon: string, (optional) icon_size: integer)` — Returns an achievement for visiting the provided planet. The icon can be generated with the `helper_scripts/generate_visit_planet_achievement.py` helper script (we recommend using `uv run` to execute it).

## Assorted helpers

* `PlanetsLib.technology_icon_moon(tech_icon: string, icon_size: integer, (optional) shadow_scale: number)` — Creates a moon discovery technology icon by adding a little moon icon on your technology icon, like in vanilla, but for moon type planets. If `shadow_scale` is defined, a shadow layer will be added to the icon, making it unnecessary to manually add one in an image editor.
* `PlanetsLib.technology_icon_planet(tech_icon: string, icon_size: integer, (optional) shadow_scale: number)` — Creates a planet discovery technology icon by adding a little planet icon on your technology icon, like in vanilla. If `shadow_scale` is defined, a shadow layer will be added to the icon, making it unnecessary to manually add one in an image editor.
* `PlanetsLib.set_default_import_location(item_name, planet_name)` — Sets the default import location for an item on a planet.
* `PlanetsLib.borrow_music(source_planet, target_planet, (optional) options{track_types,modifier_function})` — Clones music tracks from `source_planet` prototype to `target_planet` prototype. Does not overwrite existing music for `target_planet`. To clone music from or to space platforms, set the respective parameter to "space-platform." Otherwise, use the relevant planet object.
* `PlanetsLib.crushing_recipe_icons(icon_dir,icon_size)` — Returns an asteroid crushing icon resembling a basic asteroid crushing icon from vanilla Space Age, using a copper-colored crushing icon. Used by "Muluna, Moon of Nauvis" and "Crushing Industry." 
* `PlanetsLib.asteroid_crushing_recipe_icons(icon_dir,icon_size)` — Returns an asteroid crushing icon resembling a basic asteroid crushing icon from vanilla Space Age. Uses a yellow crushing icon. 
* `PlanetsLib.advanced_crushing_recipe_icons(asteroid_icon,product_1,product_2,variant)` — Returns an asteroid crushing icon resembling an advanced asteroid crushing icon from vanilla Space Age.
#### Assorted graphics

* `__PlanetsLib__/graphics/icons/research-progress-product.png` — an iconographic science pack icon intended for items used exclusively as ResearchProgressProducts, since mods using a common icon might help players understand the mechanic.

# Contributors

[thesixthroc](https://mods.factorio.com/user/thesixthroc), [MeteorSwarm](https://mods.factorio.com/user/MeteorSwarm), [Midnighttigger](https://mods.factorio.com/user/Midnighttigger), [Tserup](https://mods.factorio.com/user/Tserup), [notnotmelon](https://mods.factorio.com/user/notnotmelon), [Frontrider](https://mods.factorio.com/user/Frontrider), Zwvei, [allisonlastname](https://mods.factorio.com/user/allisonlastname), Hoochie63, [SirPuck](https://mods.factorio.com/user/SirPuck), [Osmo](https://mods.factorio.com/user/O5MO), [Thremtopod](https://mods.factorio.com/user/thremtopod).


[![Discord](https://img.shields.io/discord/1309620686347702372?style=for-the-badge&logoColor=bf6434&label=The%20Foundry&labelColor=222222&color=bf6434)](https://foundrygg.com)

## Appendix

#### `PlanetsLib.create_planet_entity_variant` steps

`PlanetsLib.create_planet_entity_variant(planet_names,entity,new_properties,bound_setting,item_name)`

This section describes the steps taken by `create_planet_entity_variant` to help explain possible incompatibilities.

On calling function in data stage:
1. Generate a deepcopy of `entity`. This will be named `new_entity`.
2. Append `"-PlanetsLib-{first_planet}"` to `new_entity`'s name, giving it a unique name. If `planet_names` is a table, `first_planet` is `planet_names`. If it's a table, `first_planet` is `planet_names[1]`.
3. Set the fields of `new_entity` such that the external appearance of `new_entity` is the same as `entity`. This includes copying `entity`'s localised_name and localised_description, redirecting Factoriopedia requests to `entity`, hiding `new_entity` from Factoriopedia, adding entity flags hiding the entity from "made-in" and from the bonus gui, and overriding `placeable_by` to be `item_name`. If item_name is undefined and `data.raw["item"][entity.name]` exists, `item_name` will use this item.
4. While it's possible to almost fully hide the existence of variant entities, they will still appear in upgrade planners. To make variant entity icons visually distinct from their original, the sprite of the planet this variant entity is intended for will be added to the top right corner of the variant entity's icon.
5. To allow additional customization, `new_entity` and `new_properties` will be merged into one table, with each top-level key in `new_properties` overriding the value of the same top-level key.
6. Using `PlanetsLib.create_planet_entity_variant`, `new_entity` is registered as a replacement for `entity` on each planet in `planet_names` if it's a list, or on `planet_names` if it is not a list. This tells PlanetsLib's control script "If `entity` placed on this planet, delete it and replace it with `new_entity`." If `bound_setting` is currently enabled by the user, continue to register the rule, but set its `enabled` field to `false`.
7. `new_entity` is added to `data.raw`.

In control stage:

On configuration changed:
1. If any entity replacement rules have changed since last save. Perform a migration.
2. During a migration, each entity replacement rule is evaluated, and entities on each surface not matching the rule are replaced. If the rule is not enabled by the user, reverse replacements made by the rule. If the rule is enabled, perform replacements that should have been made by the rule.

On placing `entity`:
1. On placing an `entity` on `planet`, if PlanetsLib.constants. on_entity_placed_on_planet_replacements[planet][entity] exists, this tells PlanetsLib that `entity` is intended to be replaced on `planet`.
2. If `enabled` == true, execute the rule, replacing `entity` with `new_entity`. 
3. Transfer settings, inventory, and other information from the old entity to the new entity.
