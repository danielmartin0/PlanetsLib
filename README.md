[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/VuVhYUBbWE)[![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/danielmartin0/PlanetsLib)

# PlanetsLib

Code, graphics and conventions to help modders creating planets, moons and other systems. This library is a community project and will grow over time. Anyone is welcome to open a [pull request](https://github.com/danielmartin0/PlanetsLib/pulls) on Github. For feature requests, please open an [issue](https://github.com/danielmartin0/PlanetsLib/issues).

## Contributors

* [thesixthroc](https://mods.factorio.com/user/thesixthroc)
* [Tserup](https://mods.factorio.com/user/Tserup) (art)
* [MidnightTigger](https://mods.factorio.com/user/Midnighttigger)
* [notnotmelon](https://mods.factorio.com/user/notnotmelon)
* [MeteorSwarm](https://mods.factorio.com/user/MeteorSwarm)
* [Frontrider](https://mods.factorio.com/user/Frontrider)

#### Notes for contributors

* In your pull requests, please list your changes in changelog.txt to be included in the next release. Please also update README.md to add sections for your new functionality (even with only 'Documentation pending') and add yourself to the contributors list.
* Contributions MUST be tested before a PR is made, ideally with multiple planets installed.
* We aim to avoid any breaking changes.
* Feel free to use the file `todo.md`.

## Planet definitions

PlanetsLib provides an API to define planet prototypes in orbit around another location.

Its additional features over the vanilla API are that relative positions are easier to specify, its sprites are on a higher layer than the parent's sprites, and that if the parent body is moved by another mod your planet will move with it.

* `PlanetsLib:extend(config)` — A wrapper/replacement for `data:extend`. Should not be called in `data-final-fixes`. Throws an error if passed `distance` or `orientation`. It instead takes the fields listed below.
    * `type` — `"planet"` or `"space-location"`
    * `orbit` — Object containing orbital parameters:
        * `parent` — Object containing `name` and `type` fields, corresponding to a parent at `data.raw[type][name]`. Planets in the original solar system should have an orbit with `type = "space-location"` and `name = "star"`.
        * `distance` — Number — orbital distance from parent
        * `orientation` — Number — orbital angle from parent (0-1). Note that orientation is absolute, not relative to the parent's orientation.
        * `sprite` — Object (optional) — Sprite for the planet’s orbit. This will be centered on, and underneath, the parent's sprite.
    * `sprite_only` — Boolean (optional) — If true, this prototype will be removed in `data-final-fixes` and replaced by its sprites on the starmap (unless it has no sprites, in which case nothing will show).
        * This is useful for constructing stars and other locations that should not have a space platform 'docking ring'.
    * Other valid `planet` or `space-location` prototype fields.
* `PlanetsLib:update(config)` — The same as `PlanetsLib:extend`, except it updates a pre-existing planet or space location (identified by the passed `type` and `name` fields) using the parameters passed. If the `orbit` field is passed, the `distance` and `orientation` fields on the prototype will be updated appropriately. Should not be called in `data-final-fixes`.

See [here](https://github.com/danielmartin0/Cerys-Moon-of-Fulgora/blob/main/prototypes/planet/planet.lua) or [here](https://github.com/danielmartin0/PlanetsLib/issues/12#issuecomment-2585484116) for usage examples of `PlanetsLib:extend`. The aforementioned feature for 'detecting the parent has moved' works by noticing discrepancies between the parent's `distance` and `orientation` and the parent's `orbit`.

## Planet Cargo Drops technology

The library provides automatic functionality to restrict cargo drops on your planet until a technology is researched. To implement:

* Use the helper function `PlanetsLib.cargo_drops_technology_base(planet, planet_technology_icon, planet_technology_icon_size)` to create a base technology prototype.
    * This will create a technology with name pattern: `planetslib-[planet-name]-cargo-drops`
    * PlanetsLib detects this technology by name. Players will be unable to drop cargo (excluding players and construction robots) to planets with that name before researching the technology.
    * Only the fields `type`, `name`, `localised_name`, `localised_description`, `effects`, `icons` will be defined, so you will need to add `unit` (or `research_trigger`) and prerequisites.
    * A locale entry for this technology is automatically generated, but you are free to override it.

## Surface conditions

#### New surface conditions

PlanetsLib includes a variety of surface conditions, all of which are either hidden or disabled by default. To enable a surface condition, modders must add the following line to settings-updates.lua (using 'oxygen' as an example):

`data.raw["bool-setting"]["PlanetsLib-enable-oxygen"].forced_value = true`

#### Restricting and relaxing conditions

Typically, when planet mods want to add a surface condition, what they are trying to do is restrict or relax the range of values for which that recipe or entity is allowed.

For example, Space Age recyclers have a maximum magnetic field of 99. If mod A wants to allow recyclers to be built up to 120, whilst mod B wants to allow them up to 150, compatibility issues can arise if mod A acts last and overrides mod B's change (which it ought to have been perfectly happy with). Instead mod A should modify existing surface conditions only if necessary.

Hence `relax_surface_conditions` and `restrict_surface_conditions` are provided, used like so:

* `relax_surface_conditions(data.raw.recipe["recycler"], {property = "magnetic-field", max = 120})`
* `restrict_surface_conditions(data.raw.recipe["boiler"], {property = "pressure", min = 10})`

NOTE: Calling `relax_surface_conditions` without a `min` field will not remove any existing `min` conditions for that property (and similarly for `max`).

#### Per-planet restrictions

* `PlanetsLib.restrict_to_planet(entity_or_recipe, planet)` — Restricts the entity or recipe prototype to a given planet by adding a special surface condition unique to that planet. This surface condition is almost invisible in the UI, with the exception of messages like "X can't be crafted on this surface. The  is too low". The planet can be passed as a name or object.

## Science adjustments

#### Labs

Unlike in Factoriopedia, science packs in labs aren't ordered by the `order` field. PlanetsLib orders the science packs in the vanilla labs in `data-final-fixes` for tidiness. Modded labs can set `sort_sciences` to `true` on their prototype to have PlanetsLib sort them too.

You can also have PlanetsLib add all sciences from the vanilla lab to your own modded lab in `data-final-fixes` by setting the field `include_all_base_lab_science` to `true` on your lab's prototype.

#### Technologies

Setting `ensure_all_packs_from_vanilla_lab` on any technology to true will ensure the technology contains all science packs present in the base lab. This is useful for defining new endgame technologies.

By default, PlanetsLib sets this field to `true` on the promethium science pack technology.

## Subgroups

Subgroups are rows in Factoriopedia. It is anticipated that dependencies of PlanetsLib may treat space locations differently based on their subgroup, so we are careful about adding more.

* `satellites` — A new Factoriopedia row for satellites (below the planets row). Affects [Redrawn Space Connections](https://mods.factorio.com/mod/Redrawn-Space-Connections).

## Description templates

Documentation pending.

## Other

#### Assorted functions

* `PlanetsLib.set_default_import_location(item_name, planet)` — Sets the default import location for an item on a planet.
* `PlanetsLib.borrow_music(source_planet, target_planet)` — Clones music tracks from `source_planet` to `target_planet`. Does not overwrite existing music for `target_planet`.
* `PlanetsLib.technology_icon_moon` — Creates a moon discovery technology icon.
* `PlanetsLib.technology_icon_planet` — Creates a planet discovery technology icon.

#### Python helper scripts

* `lib/orbit_graphic_generator.py` — contains a Python script that generates orbit sprites. `generate_orbit(distance, output_file, mod_name)`, `distance` being the same as your orbital distance. After generating your sprite, the script will print a block of lua code that imports your sprite with proper scaling. Orbit sprites should be scaled at 0.25 to ensure that no pixels are visible, even on 4K displays.