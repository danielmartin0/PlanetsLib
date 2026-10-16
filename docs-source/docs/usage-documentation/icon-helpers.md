---
sidebar_label: Icon Helpers
---

# Icon Helpers

PlanetsLib provides helpers for composing and modifying prototype icons—the `icons` field, which is an array of [[IconData]] entries. These helpers are data-stage only, and are ported from ["Muluna, Moon of Nauvis"](https://mods.factorio.com/mod/planet-muluna).

## Composite "dual item" icons

`PlanetsLib.dual_icon` and `PlanetsLib.dual_icon_reversed` build a composite icon out of the icons of two or three existing prototypes. This is useful for recipes or technologies that are best recognised as a combination of existing items—for example, a recipe that turns one item into another.

* `PlanetsLib.dual_icon(item_1, item_2, item_3)` — Returns an array of [[IconData]]. Up to three icons are composed: `item_1` is drawn largest at the bottom, with `item_2` (and the optional `item_3`) layered over it at a smaller scale.
* `PlanetsLib.dual_icon_reversed(item_1, item_2)` — Returns an array of [[IconData]], composing two icons using a layout mirrored relative to `PlanetsLib.dual_icon`.

The arguments are prototype **names** (strings), not prototype tables. Each name is looked up automatically as a `surface`, `tool`, `capsule`, `fluid`, `planet`, or `item` prototype; when a name matches more than one type, the precedence is `surface` > `tool` > `capsule` > `fluid` > `planet` > `item`.

If a prototype has neither an `icon` nor an `icons` field—or if the name does not match any prototype—a placeholder icon is substituted and a message is logged.

```lua
-- A recipe that produces "water" from "my-item":
data.raw.recipe["my-recipe"].icons = PlanetsLib.dual_icon("my-item", "water")

-- Three icons (for example two inputs and one output):
data.raw.recipe["my-recipe"].icons = PlanetsLib.dual_icon("my-item", "water", "steam")

-- The mirrored two-icon layout:
data.raw.recipe["my-other-recipe"].icons = PlanetsLib.dual_icon_reversed("rocket-fuel", "aluminum-crushed")
```

## Blurring technology icons

* `PlanetsLib.blur_technology_icon(icons, blurriness)` — Returns an array of [[IconData]] that appears blurred, by layering many nearly-transparent, slightly offset duplicates of every entry using a `multiplicative-with-alpha` blend mode. The original icons are not modified.

This is useful for increasing the apparent resolution of icons without modifying the source image.

* `icons` — an array of [[IconData]] — the icons to blur.
* `blurriness` — `number` — how far the offset duplicates are displaced. Must be greater than `0`; larger values produce a wider blur.

```lua
data.raw.technology["my-hidden-technology"].icons =
    PlanetsLib.blur_technology_icon({ { icon = "__my-mod__/graphics/technology/thing.png", icon_size = 128 } }, 8)
```
