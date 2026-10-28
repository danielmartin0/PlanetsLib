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

## Melting recipe icons

`PlanetsLib.melting_icon(metal, ore, catalyst)` builds an icon in the style of the vanilla Space Age recipes that melt an ore together with calcite into a molten metal: the catalyst and the ore are shown small at the top, with the molten product drawn large across the front. It is useful for mods that add their own melting recipes.

* `metal` — `string` — prototype name of the molten product; drawn largest.
* `ore` — `string` — prototype name of the ore being melted.
* `catalyst` — `string` — optional prototype name of the catalyst. Defaults to `"calcite"`.

Like `PlanetsLib.dual_icon`, each argument is a prototype **name** (not a table or an icon path). The prototype type is detected automatically and the icon is taken from the prototype's `icon`/`icons` field; if a name cannot be resolved, a placeholder is substituted and a message is logged.

```lua
-- calcite + alumina -> molten aluminum:
data.raw.recipe["aluminum-ore-melting"].icons =
    PlanetsLib.melting_icon("molten-aluminum", "alumina")
```

## Asteroid crushing recipe icons

These helpers build `icons` arrays in the style of the vanilla Space Age asteroid-crushing recipes. Unlike `PlanetsLib.dual_icon` and `PlanetsLib.melting_icon`, their arguments are **sprite paths** (strings), not prototype names.

### `PlanetsLib.crushing_recipe_icons(icon_dir, icon_size)`

Returns an array of [[IconData]] resembling a basic asteroid-crushing recipe, using PlanetsLib's copper-colored crushing symbol. The supplied icon is drawn small over the crushing symbol.

* `icon_dir` — `string` — sprite path of the icon to crush (the ore or asteroid chunk).
* `icon_size` — `integer` — optional size of `icon_dir` in pixels. Defaults to `64`. The icon is drawn at the same apparent size regardless of the value, so a 128-pixel or 256-pixel source looks identical to a 64-pixel one.

The first entry uses `icon_dir` (shifted up slightly) and the second uses `__PlanetsLib__/graphics/icons/generic-crushing.png`.

### `PlanetsLib.asteroid_crushing_recipe_icons(icon_dir, icon_size)`

Identical to `PlanetsLib.crushing_recipe_icons`, but uses the yellow `__PlanetsLib__/graphics/icons/asteroid-crushing.png` symbol. It takes the same arguments.

```lua
-- A basic crushing recipe for a custom ore:
data.raw.recipe["my-ore-crushing"].icons =
    PlanetsLib.crushing_recipe_icons("__my-mod__/graphics/icons/my-ore.png", 64)

-- The same layout with the asteroid-crushing symbol:
data.raw.recipe["my-asteroid-crushing"].icons =
    PlanetsLib.asteroid_crushing_recipe_icons("__my-mod__/graphics/icons/my-asteroid-chunk.png")
```

### `PlanetsLib.advanced_crushing_recipe_icons(asteroid_icon, product_1, product_2, variant)`

Returns an array of five [[IconData]] entries resembling an advanced asteroid-crushing recipe: four product icons are placed in quadrants at scale `0.25`, with the asteroid icon drawn over them at scale `0.4`.

* `asteroid_icon` — `string` — sprite path of the asteroid shown on top.
* `product_1` — `string` — sprite path of the first product.
* `product_2` — `string` — sprite path of the second product.
* `variant` — `string` — optional arrangement of the four product icons. Defaults to `"checkerboard"`:
  * `"checkerboard"` — the products alternate diagonally (`product_1` bottom-left and top-right, `product_2` top-left and bottom-right).
  * `"horizontal"` — `product_1` fills the top row and `product_2` the bottom row.
  * `"vertical"` — `product_1` fills the left column and `product_2` the right column.

Any other value raises an error naming the valid variants.

```lua
data.raw.recipe["my-advanced-crushing"].icons =
    PlanetsLib.advanced_crushing_recipe_icons(
        "__my-mod__/graphics/icons/my-asteroid-chunk.png",
        "__my-mod__/graphics/icons/product-a.png",
        "__my-mod__/graphics/icons/product-b.png",
        "vertical"
    )
```

## Planet and moon technology icons

These helpers build technology `icons` arrays in the style of vanilla planet- and moon-discovery technologies. They accept a sprite path for your technology icon.

### `PlanetsLib.technology_icon_planet(tech_icon, icon_size, shadow_scale)`

Returns an array of [[IconData]]: your technology icon with the vanilla constant-planet overlay in the corner. The base layout comes from `util.technology_icon_constant_planet`.

* `tech_icon` — `string` — sprite path of your technology icon.
* `icon_size` — `integer` — optional size of `tech_icon` in pixels. Defaults to `256`.
* `shadow_scale` — `number` — optional. When provided, a `__PlanetsLib__/graphics/icons/planet-technology.png` symbol is added first and the list is reordered to symbol, your icon (scaled by `shadow_scale * 128 / icon_size` and shifted `{0, 10}`), then the constant-planet overlay. When omitted, no shadow or planet symbol is drawn.

### `PlanetsLib.technology_icon_moon(tech_icon, icon_size, shadow_scale)`

Identical to `PlanetsLib.technology_icon_planet`, except that the final overlay is replaced with the moon symbol `__PlanetsLib__/graphics/icons/moon-technology-symbol.png`. It takes the same arguments.

```lua
local tech = data.raw.technology["my-planet-discovery"]
tech.icon = nil
tech.icon_size = nil
tech.icons = PlanetsLib.technology_icon_planet("__my-mod__/graphics/technology/planet.png", 256, 0.5)
```

### Choosing `shadow_scale`

The shadow sprite is vanilla's 256 px shadow layer: its visible ellipse is
183 px wide. Vanilla planet-discovery icons pair that ellipse with a planet disc
about 216 px wide, so the target ellipse-to-disc ratio is `183 / 216`.

Let `disc_px` be the width of the planet disc inside your icon. The scale that
reproduces vanilla's ratio is:

```latex
\text{shadow\_scale} = \frac{0.84375 \times \text{icon\_size}}{\text{disc\_px}}
```

For example, the Castra Prime icon is a 256 px tile with a 250 px planet disc:

```latex
\text{shadow\_scale} = \frac{0.84375 \times 256}{250} \approx 0.86
```

A vanilla-sized 256 px icon with a 216 px disc needs `shadow_scale = 1.0`.
Measure the planet body, not a ring or a glow. If the source icon already has a
baked-in shadow, do not add this layer as well.

The helper sets the planet layer's `scale` to `shadow_scale * 128 / icon_size`
and its `shift` to `{0, 10}`. If the original icon used a custom `scale` or
`shift`, the helper replaces them; pass the final values through after calling
it if you need to preserve a custom layout.

### `PlanetsLib.technology_icons_planet_cargo_drops(planet_icon, icon_size, mini)`

Returns an array of four [[IconData]] entries used for cargo-drop technologies: the cargo-pod icon, the planet icon, a semi-transparent black shadow, and the cargo-pod icon again.

* `planet_icon` — `string` — sprite path of the planet icon.
* `icon_size` — `integer` — optional size of `planet_icon` in pixels. Defaults to `256`. The planet is scaled by `0.65 * 256 / icon_size`.
* `mini` — `boolean` — optional. When `true`, the planet icon is centred instead of being shifted `{ -17, 55 }`.

This function is normally used indirectly through `PlanetsLib.cargo_drops_technology_base(planet, planet_technology_icon, planet_technology_icon_size)`.

### Related cargo-drop helpers

`PlanetsLib.cargo_drops_technology_base(planet, planet_technology_icon, planet_technology_icon_size)` returns a complete cargo-drop `technology` prototype named `planetslib-<planet>-cargo-drops`. Its `icons` field comes from `technology_icons_planet_cargo_drops`, and its effects come from `technology_effect_cargo_drops`. All three arguments are required; `planet` is a planet name.

`PlanetsLib.technology_effect_cargo_drops(planet_name, icons)` returns a single-element `technology.effects` array of type `"nothing"`. It displays `icons` (an array of [[IconData]]) and a translated cargo-drop description referring to `planet_name`.

## Backwards-compatible aliases

The following aliases are still exported for compatibility with existing mods. Prefer the canonical names in new code.

* `PlanetsLib.technology_icons_moon` — alias for `PlanetsLib.technology_icon_moon`.
* `PlanetsLib.technology_icon_constant_planet` — alias for `PlanetsLib.technology_icon_planet`.

## Blurring technology icons

* `PlanetsLib.blur_technology_icon(icons, blurriness)` — Returns an array of [[IconData]] that appears blurred, by layering many nearly-transparent, slightly offset duplicates of every entry using a `multiplicative-with-alpha` blend mode. The original icons are not modified.

This is useful for increasing the apparent resolution of icons without modifying the source image.

* `icons` — an array of [[IconData]] — the icons to blur.
* `blurriness` — `number` — how far the offset duplicates are displaced. Must be greater than `0`; larger values produce a wider blur.

```lua
data.raw.technology["my-hidden-technology"].icons =
    PlanetsLib.blur_technology_icon({ { icon = "__my-mod__/graphics/technology/thing.png", icon_size = 128 } }, 8)
```
