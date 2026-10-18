---
sidebar_label: Ground Diggers
---

# Ground Diggers

PlanetsLib can convert mining drills into **ground diggers**: machines that dig up a recipe's products anywhere on a planet, even where no resources exist. This is useful for planets where the surface itself is a resource (for example, regolith on a moon).

When a player tries to place a supported mining drill on a planet with ground diggers enabled, PlanetsLib checks whether any resources are within the drill's mining radius. If there are none, the drill is replaced by a ground digger that crafts the planet's configured recipe. If resources are present, an ordinary mining drill is placed as usual.

* `PlanetsLib.enable_ground_diggers(planet(string or table), recipe(string), options(table, optional))` — Enables ground diggers on `planet`. Whenever a supported mining drill is placed on `planet` without nearby resources, it is converted into a ground digger that crafts `recipe`. Each planet may have a single ground digger recipe.

`options` fields:

* `drills` (table) — Only generate diggers for these mining drill entity names. Accepts either an array of names or a dictionary of name to `true`. Defaults to every eligible mining drill.
* `blacklist` (table) — Never generate diggers for these mining drill entity names. Accepts the same formats as `drills`.

## Shared prototypes

Every planet that uses this feature shares the **same** ground digger prototypes. There is one prototype per eligible mining drill, named `<drill>-ground-digger` (for example, placing an `electric-mining-drill` produces an `electric-mining-drill-ground-digger`).

The naming scheme deliberately matches the prototypes used by [Muluna, Moon of Nauvis](https://mods.factorio.com/mod/planet-muluna), so saves that placed those entities keep working.

Because the prototypes are shared, the planet's `recipe` cannot be baked into the prototype. It is assigned at runtime when the digger is placed, and then locked. As a consequence, all ground diggers accept the crafting categories of every recipe registered with this feature, but each individual machine only ever crafts the recipe of the planet it was placed on.

Diggers are also restricted to planets that enabled the feature: PlanetsLib adds a hidden surface property to each participating planet, and every digger prototype requires it. A digger blueprint therefore cannot be built on a planet that hasn't called this function.

### Eligible mining drills

By default, every mining drill that meets all of the following criteria gets a ground digger variant:

* It has an `electric` energy source.
* It does not output fluids (pumpjacks are mining drills).
* It has a square selection box.
* It is placeable by an item.

Ground digger variants are assembling machines that share the drill's appearance, health, and other properties.

### Recipe requirements

The configured recipe must exist and should be unlockable by the player (for example, through a technology). PlanetsLib does not unlock it automatically. Ground diggers also benefit from mining drill productivity research, which is applied to the recipe automatically.

## Example

```lua
-- data.lua or data-updates.lua
PlanetsLib.enable_ground_diggers("muluna", "muluna-regolith-digging")
```

With the call above, every eligible mining drill placed on `muluna` without nearby resources becomes a ground digger that crafts `muluna-regolith-digging`. To limit diggers to specific drills, or to exclude some:

```lua
PlanetsLib.enable_ground_diggers("muluna", "muluna-regolith-digging", {
    drills = { "electric-mining-drill", "big-mining-drill" },
    blacklist = { "seafloor-drill" },
})
```
