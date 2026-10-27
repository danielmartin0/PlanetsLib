---
sidebar_label: Entity Removal Floors
---
# Entity Removal Floors

PlanetsLib can place a temporary floor underneath configured **simple entities, plants, trees, and containers** while they are deconstructed. This prevents construction robots from destroying the entity's mining results when the entity stands on a tile whose prototype has `destroys_dropped_items` set.

The mechanic is ported from the lunar-rock removal feature in [Muluna, Moon of Nauvis](https://mods.factorio.com/mod/planet-muluna). Instead of hard-coding a planet and an entity, PlanetsLib stores one rule per planet and entity in mod-data.

## Usage

```lua
-- data.lua, data-updates.lua, or data-final-fixes.lua
PlanetsLib.assign_entity_removal_floor("muluna", { "lunar-rock", "lunar-huge-rock" }, "muluna-gravel", {
    default_tile_item = "stone-crushed",
})
```

`PlanetsLib.assign_entity_removal_floor(planet, entities, default_tile, options)` configures the mechanic:

* `planet` — Planet name or planet prototype. Only surfaces whose `LuaSurface.planet` matches this planet use the rule.
* `entities` — One entity name, an array of names, or a dictionary of name to `true`. The entities must exist and have a supported prototype type: `simple-entity`, `plant`, `tree`, or `container`.
* `default_tile` — Preferred tile prototype placed under the entity. It must not have `destroys_dropped_items` set, or the floor would destroy the same drops it is meant to protect. PlanetsLib verifies that the tile can actually be built on each unsafe footprint tile; if the default cannot be built there, another buildable safe tile is chosen.
* `options` (optional):
    * `default_tile_item` — Item used to place `default_tile`. If omitted, PlanetsLib finds an item whose `place_as_tile` result is `default_tile`. When no such item exists, players cannot fall back to another tile.
    * `waiting_message` — Localised string shown when a queued entity is marked for deconstruction again. Defaults to a PlanetsLib message.

Calling the function again for the same planet/entity pair replaces the older rule. `PlanetsLib.add_entity_removal_floor_rule()` is an alias.

## Behaviour

When one of the configured entities is marked for deconstruction:

1. PlanetsLib checks every tile in the entity's whole-tile footprint.
2. If every tile is safe, the deconstruction order is left alone.
3. Otherwise, PlanetsLib cancels the order, queues the entity, and places tile ghosts of the replacement tile under the unsafe tiles.
4. When the floor has been built, the deconstruction order is reissued. Construction robots can then deconstruct the entity without destroying its drops.
5. If construction robots built the temporary floor, it is ordered for deconstruction after the entity is gone and its dropped items have been picked up. Floors built by a player are left in place.

Character players who are outside a stationary roboport network and do not carry enough of the rule's `default_tile_item` may use another tile item from their inventory, provided it places a safe tile that is buildable on the footprint tile. The rule's `default_tile` is used when no suitable fallback exists.

Undoing the deconstruction order removes the queued entry and any tile ghosts that PlanetsLib created for it.

## Mod-data format

The API writes into the `Planetslib` mod-data prototype's `entity_removal_floors` table. Mods may also write the table directly:

```lua
data.raw["mod-data"].Planetslib.data.entity_removal_floors["muluna"] = {
    ["lunar-rock"] = {
        default_tile = "muluna-gravel",
        default_tile_item = "stone-crushed",
    },
    ["lunar-huge-rock"] = {
        default_tile = "muluna-gravel",
        default_tile_item = "stone-crushed",
    },
}
```

The runtime also accepts a grouped form, where a rule has its own `entities` list:

```lua
data.raw["mod-data"].Planetslib.data.entity_removal_floors["muluna"] = {
    {
        entities = { "lunar-rock", "lunar-huge-rock" },
        default_tile = "muluna-gravel",
        default_tile_item = "stone-crushed",
    },
}
```

Because both the data-stage API and the runtime read the same mod-data table, rules added during `data-final-fixes` are available when the game starts.

## Known limitations

* The mechanic only applies to entities whose prototype type is `simple-entity`, `plant`, `tree`, or `container`. Corpses and other entity types are ignored.
* Tile ghosts are placed in the entity's whole-tile footprint, using the entity's `bounding_box` rather than its placement grid. Entities with unusual collision shapes can therefore receive a larger floor than their visual footprint.
* The temporary floor is not transferred if a mod or script replaces the queued entity with a different entity before deconstruction; the queue keeps tracking the original entity.
