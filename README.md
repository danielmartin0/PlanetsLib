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

### Support for moons

* `PlanetsLib.technology_icons_moon` — Standardized icon for moon discovery technology.
* `subgroup=satellites` — A new Factoriopedia row for satellites (below the planets row).

### Surface conditions

Documentation pending.

## Further notes for contributors

* Please TEST YOUR CHANGES. I would like to make releases with minimal testing of new features. You will break a lot of games if you don't do this.
* I'm currently publishing releases of this mod manually. In your pull requests, I ask you list your changes in changelog.txt to be included in the next release. Please also update README.md adding sections for your new functionality (even with only 'Documentation pending.') and adding yourself to the contributors list above.
* Feel free to make use of the file `todo.md`.