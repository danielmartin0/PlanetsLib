PlanetsLib allows you to quickly generate planet-exclusive variants of entities. On placing an entity on a planet with a planet-exclusive variant, PlanetsLib will replace the original entity with your variant. The difference between entity variants and the original entity are invisible to the user, and variants can not be seen in the Factoriopedia. Every variant must be associated with a boolean startup setting that can be disabled to ease in uninstallation. Once an entity variant has been created, any attempt to create a variant for the same entity for the same planet will throw an error. This is a limitation of the current system that may change in the future. Currently, entity variants that are the same type as their origin entity are well-tested, but changing entity types is untested.

Known issues: Variant entities will be the same fast_replaceable_group as the entity they're based on. This makes it possible to place over the variant entity with the entity's item. This is an engine limitation.

* `PlanetsLib.create_planet_entity_variant(planet_names(table of strings or string),entity(table),new_properties(table),bound_setting(startup setting name),item_name(defaults to entity name))` – Creates and adds to data.raw a variant of `entity` with a unique name, the same localized name/description, and new properties taken from new_properties. When `entity` is placed on planet during gameplay, PlanetsLib will replace entity with new_entity. `bound_setting` is a boolean startup setting. This entity variant is only placed when this startup setting is enabled. When disabling this startup setting on an existing save, variant entities are migrated back to their original entities when appropriate. When enabling this startup setting on an existing save, variant entities are migrated from their original entities when appropriate. To aid in mod uninstallation, expose this setting to users.
* `PlanetsLib.assign_entity_replacement(planet,entity,new_entity,bound_setting)` – When `entity` is placed on planet during gameplay, PlanetsLib will replace entity with new_entity. Due to current system limitations, assigning an entity replacement of the same entity onto the same planet will throw an error. Not recommended for regular use due to the lack of safety checks compared to PlanetsLib.create_planet_entity_variant(). `planet = "space-platform"` causes this function to map a replacement to all space platforms.

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

