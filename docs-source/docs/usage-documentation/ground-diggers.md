---
sidebar_label: Ground Diggers
---

# Ground Diggers

PlanetsLib can convert mining drills into **ground diggers**: machines that dig up a recipe's products anywhere on a planet, even where no resources exist. This is useful for planets where the surface itself is a resource (for example, regolith on a moon).

When a player tries to place a supported mining drill on a planet with ground diggers enabled, PlanetsLib checks whether any resources are within the drill's mining radius. If there are none, the drill is replaced by a ground digger that crafts the planet's configured recipe. If resources are present, an ordinary mining drill is placed as usual.

* `PlanetsLib.enable_ground_diggers(planet(string or table), recipe(string), options(table, optional))` — Enables ground diggers on `planet`. Whenever a supported mining drill is placed on `planet` without nearby resources, it is converted into a ground digger that crafts `recipe`. Each planet may have a single ground digger recipe. The function may also be called during `data-final-fixes`; in that case the planet's diggers are generated immediately, so the planet and recipe must already exist.

`options` fields:

* `drills` (table) — Only generate diggers for these mining drill entity names and only convert these drills on this planet. Accepts either an array of names or a dictionary of name to `true`. Defaults to every eligible mining drill.
* `blacklist` (table) — Skip these mining drill entity names when generating diggers for this planet and when using the custom build path. Accepts the same formats as `drills`.

## Shared prototypes

Every planet that uses this feature shares the **same** ground digger prototypes. There is one prototype per eligible mining drill, named `<drill>-ground-digger` (for example, placing an `electric-mining-drill` produces an `electric-mining-drill-ground-digger`).

The naming scheme deliberately matches the prototypes used by [Muluna, Moon of Nauvis](https://mods.factorio.com/mod/planet-muluna), so saves that placed those entities keep working.

### Muluna compatibility

PlanetsLib requires `planet-muluna` newer than 2.7.40. Versions up to 2.7.40 include their own ground digger implementation that uses the same `<drill>-ground-digger` prototype names, so PlanetsLib refuses to load when one of those versions is active. Update `planet-muluna` to continue using this feature.

Because the prototypes are shared, the planet's `recipe` cannot be baked into the prototype. It is assigned at runtime when the digger is placed, and then locked. As a consequence, all ground diggers accept the crafting categories of every recipe registered with this feature, but each individual machine only ever crafts the recipe of the planet it was placed on.

Diggers are also restricted to planets that enabled the feature: PlanetsLib adds a hidden surface property to each participating planet, and every digger prototype requires it. A digger blueprint therefore cannot be built on a planet that hasn't called this function.

Placement also respects the mining drill's own surface conditions. If the drill cannot be placed on the planet (for example, a chemical burner drill on an oxygen-less planet), it will not be converted into a ground digger there. Builds in remote view are placed as ground-digger ghosts without the reach limit; the ghost becomes a recipe-bearing digger when it is built.

### Eligible mining drills

By default, every mining drill that meets all of the following criteria gets a ground digger variant:

* It does not output fluids (pumpjacks are mining drills).
* It can mine ordinary solid resources: its `resource_categories` includes `basic-solid`, or is unset. Drills that can only be placed on specific resource sites, such as pumpjacks or anomaly collectors, are skipped.
* It has a square selection box.
* It is placeable by an item.
* It does not set `PlanetsLib_do_not_generate_variants`.
* Its name does not contain a quality or resource name. This skips per-quality and per-resource copies of drills. The check is a substring match, so a drill whose name contains a quality or resource name for another reason is also skipped.

These criteria apply to every drill, including drills listed explicitly in `options.drills`; listing a drill cannot make a resource-site-only drill eligible.

Any energy source is allowed, so non-electric drills (for example, burner mining drills) are eligible by default. A digger keeps the energy source of the drill it is copied from; diggers with an electric energy source default to no drain (`0 MW`), matching mining drills.

Ground digger variants are assembling machines that share the drill's appearance, health, and other properties. Mining drills that can be used as ground diggers mention this in their Factoriopedia description, linking to the generated digger variant.

### Recipe requirements

The configured recipe must exist and should be unlockable by the player (for example, through a technology). PlanetsLib does not unlock it automatically. Ground diggers also benefit from mining drill productivity research, which is applied to the recipe automatically.

### Build warning

Because ground diggers can replace a mining drill placed without nearby resources, the vanilla warning shown in that situation is misleading. PlanetsLib blanks the `cant-build-reason.no-resource-for-drill` locale key so the warning is not shown.

### Known limitations

* `drills` and `blacklist` control which digger prototypes are generated and which drills the custom build path converts. Because the prototypes are shared, a digger generated for another planet can still be built on a planet that blacklists that drill (for example, from a blueprint or by script). The built digger still receives and locks the local recipe; filter such placements in your own scripts if this matters.
* Placement collision checks are best effort. PlanetsLib combines a prototype collision check with an area scan, but some collisions, especially for non-standard drill sizes, may not be detected. Script-created diggers should not rely on PlanetsLib to validate their placement.

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
