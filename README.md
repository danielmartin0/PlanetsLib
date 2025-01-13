[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/VuVhYUBbWE)

# PlanetsLib

Code, graphics and conventions to help modders creating planets, moons and other systems. This library is a community project and will grow over time. Feel free to contribute via pull requests on [Github](https://github.com/danielmartin0/PlanetsLib).

We try to avoid breaking changes. In the unlikely event breaking changes occur, the major version of Planetslib will be bumped (unless the feature is unused.)

## Credits

Contributors:

* [thesixthroc](https://mods.factorio.com/user/thesixthroc)
* [Tserup](https://mods.factorio.com/user/Tserup) (art)
* [MidnightTigger](https://mods.factorio.com/user/Midnighttigger)
* [notnotmelon](https://mods.factorio.com/user/notnotmelon)
* [MeteorSwarm](https://mods.factorio.com/user/MeteorSwarm)

## API Reference

### Planet definitions

Planet prototypes and space location prototypes can be defined using the following API. The 'distance' and 'orientation' of the prototypes will be calculated automatically from the orbit hierarchy, as will the layering of the sprites on the starmap.

* `PlanetsLib:extend(config)` — A wrapper/replacement for `data:extend`. Throws an error if passed `distance` or `orientation`. It instead takes the fields listed below.
    * `type` — `"planet"` or `"space-location"`
    * `orbit` — Object containing orbital parameters:
        * `parent` — Object containing `name` and `type` fields, corresponding to a parent at `data.raw[type][name]`. Planets in the original solar system should have an orbit with `type = "space-location"` and `name = "star"`.
        * `distance` — Number: orbital distance from parent
        * `orientation` — Number: orbital angle from parent (0-1). Note that orientation is absolute, not relative to the parent's orientation.
        * `sprite` — Object: Sprite for the orbit, centered on its parent
    * `sprite_only` — Boolean (optional): If true, this prototype will be removed in `data-final-fixes` and replaced by its sprites on the starmap (unless neither `starmap_icon`, `starmap_icons` nor an orbit sprite are defined, in which case nothing will show).
        * This is useful for constructing stars and other locations that should not have a space platform 'docking ring'.
    * Other valid `planet` or `space-location` prototype fields
    * Further notes on `PlanetsLib:extend`:
        * Should not be called in `data-final-fixes`.
        * See [here](https://github.com/danielmartin0/Cerys-Moon-of-Fulgora/blob/main/prototypes/planet/planet.lua) or [here](https://github.com/danielmartin0/PlanetsLib/issues/12#issuecomment-2585484116) for usage examples.
* `PlanetsLib:update(config)` — The same as `PlanetsLib:extend`, except it updates a pre-existing planet or space location (identified by the passed `type` and `name` fields) using the parameters passed. If the `orbit` field is passed, the `distance` and `orientation` fields on the prototype will be updated appropriately. Should not be called in `data-final-fixes`.

### Other planet helpers

* `PlanetsLib:borrow_music(source_planet, target_planet)` - Clones music tracks from an existing planet to a new one.
* `PlanetsLib:set_default_import_location(item_name, planet)` - Sets the default import location for an item on a planet.

### Planet Cargo Drops technology

The library provides automatic functionality to restrict cargo drops on your planet until a technology is researched. To implement:

* Define a technology with name pattern: `[planet-name]-cargo-drops`
    * Use the provided helper functions:
    * `PlanetsLib.technology_icons_planet_cargo_drops`
    * `PlanetsLib.technology_effect_cargo_drops`

Players will be unable to drop cargo (excluding players and construction robots) to planets with that name before researching the technology.

## Support for moons

* `PlanetsLib.technology_icons_moon` — Standardized icon for moon discovery technology.
* `subgroup=satellites` — A new Factoriopedia row for satellites (below the planets row).

### Description templates

PlanetsLib provides a set of localisation templates for moons and planets to provide standardization between mods on how the relationships between planets and moons are described.

```
[planetslib-templates] 
moon-description=__1__\nOrbiting __2__.
planet-description-one-moon=__1__\nOrbited by __2__.
planet-description-two-moons=__1__\nOrbited by __2__ and __3__.
planet-description-three-moons=__1__\nOrbited by __2__, __3__, and __4__.
```

### Description examples
```
data.raw["planet"]["muluna"].localised_description={"planetslib-templates.moon-description",{"space-location-description.muluna"},"[planet=nauvis]"}
data.raw["planet"]["nauvis"].localised_description={"planetslib-templates.planet-description-one-moon",{"space-location-description.nauvis"},"[planet=muluna]"}
data.raw["planet"]["nauvis"].localised_description={"planetslib-templates.planet-description-two-moons",{"space-location-description.nauvis"},"[planet=muluna]","[planet=lignumis]"}
```

## Surface conditions

### Surface condition helpers

* `PlanetsLib.restrict_to_surface(planet)` : Returns surface condition restricting an entity to the provided planet(See `planet-str`).
* `PlanetsLib.exact_value(property,value)` : Returns surface condition that requires the planet's `property` equal `value`.

#### Example
```
local muluna = data.raw["planet"]["muluna"]
anorthite_crushing.surface_conditions ={
    -- Add more surface conditions here
    PlanetsLib.exact_value("oxygen",0), -- Requires exactly 0% oxygen.
    PlanetsLib.restrict_to_surface(muluna), -- Explicitly locks recipe to Muluna. This condition is hidden in-game.
}
```
### New conditions

PlanetsLib includes a wide variety of surface conditions, all of which are either hidden or disabled by default. To enable a surface condition, modders must add the following line to settings-updates.lua:

`data.raw["bool-setting"]["PlanetsLib-enable-[PROPERTY]"].forced_value = true`

Example: `data.raw["bool-setting"]["PlanetsLib-enable-oxygen"].forced_value = true`

### New conditions with quantity format
* `temperature`: __n__ K
* Atmospheric Gases
  * `oxygen`: __n__%
  * `nitrogen`: __n__%
  * `carbon-dioxide`: __n__%
  * `argon`: __n__%

### Hidden conditions

The following conditions are hidden but always enabled. 

* `planet-str` - A string (<=8 characters) encoded as a double and stored in a planet's surface properties. Setting this from a string can be inconvenient, so the following functions are included to help modders encode strings into a planet's properties, then decode the resulting double back into a string. Every planet should have a unique planet-str to have the intended effect. Restricting a recipe to a particular planet-str makes it possible to explicitly restrict recipes and buildings to a single planet. In most situations, mods other than PlanetsLib will not need to use these functions.
  * `PlanetsLib.planet_str.set_planet_str(planet)` : Sets the planet string of a planet. This is done automatically for all planets, but these default strings can be overidden. If two planets share the first 8 character names, they will have the same planet string, so one of them should be manually changed to a different string if the modder doesn't want conditions to apply to both planets.
  * `PlanetsLib.planet_str.get_planet_str(planet) -> str` : Returns the planet string of a planet, decoded from double to string. Not used very often in practice.
  * `PlanetsLib.planet_str.get_planet_str_double(planet)` : Returns the planet string of a planet as a double. If the planet string has not been set yet, it will return the planet string that the planet will have by the end of data-final-fixes.lua. This function is used internally when setting the surface conditions of a recipe or entity.
* `parent-body` - A planet-str referencing the planet's parent planet. Used by moons to indicate their parent body. Automatically defined when a body's parent is defined as a planet.

## Further notes for contributors

* Please TEST YOUR CHANGES. thesixthroc would like to release versions with minimal testing of new features on their part. You might break a lot of games if you don't do this.
* We're currently publishing releases of this mod manually. In your pull requests, please list your changes in changelog.txt to be included in the next release. Please also update README.md to add sections for your new functionality (even with only 'Documentation pending.') and add yourself to the contributors list.
* Feel free to use the file `todo.md`.