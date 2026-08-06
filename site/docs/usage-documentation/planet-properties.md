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
