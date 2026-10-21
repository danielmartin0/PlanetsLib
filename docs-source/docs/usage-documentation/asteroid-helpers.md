---
sidebar_label: Asteroid Spawn Helpers
---

# Asteroid Spawn Helpers

PlanetsLib provides data-stage helpers for building `asteroid_spawn_definitions` on planets, space locations and space connections. They are designed for the common planet-mod setup:

- a **space connection** needs full `spawn_points` curves along the route;
- a **planet or space location** needs a single `probability` entry sampled at its position, conventionally `0.9`;
- custom asteroid types should not require copying Space Age's helper or deep-copying generated entries.

The helpers are additive: `PlanetsLib:extend`, `PlanetsLib:update` and hand-written `asteroid_spawn_definitions` tables continue to work unchanged. They have no hard Space Age dependency.

## Quick start

```lua
local route = PlanetsLib.asteroid_route {
	{
		position = 0.1,
		ratios = { metallic = 3, carbonic = 2, oxide = 1 },
		spawn = { chunk = 0.0125 },
	},
	{
		position = 0.9,
		ratios = { metallic = 4, carbonic = 3, oxide = 1 },
		spawn = { chunk = 0.0025, medium = 0.0025 },
	},
}

PlanetsLib.set_asteroid_spawn_definitions("cerys", route, { influence = 1 })
PlanetsLib.set_asteroid_spawn_definitions("fulgora-cerys", route)
```

The setter writes:

- `planet.asteroid_spawn_definitions = route:planet(0.9)` for planets and space locations;
- `space_connection.asteroid_spawn_definitions = route:connection()` for space connections.

If you prefer assigning the fields yourself:

```lua
data.raw.planet.cerys.asteroid_spawn_definitions = route:planet(0.9)
data.raw["space-connection"]["fulgora-cerys"].asteroid_spawn_definitions = route:connection()
```

## Building a route

A route specification is an array of keyframes. Each frame has a `position` in the range `0..1`, and may define `ratios`, `spawn`, or both.

```lua
local route = PlanetsLib.asteroid_route {
	{
		position = 0.1,
		ratios = { metallic = 3, carbonic = 2, oxide = 1 },
		spawn = { chunk = 0.0125 },
	},
	{
		position = 0.5,
		spawn = { medium = 0.0075 },
	},
	{
		position = 0.9,
		ratios = { metallic = 4, carbonic = 3, oxide = 1 },
		spawn = { chunk = 0.0025, medium = 0.0025 },
	},
}
```

| Field | Meaning |
| --- | --- |
| `position` | Position along the route, from `0` to `1`. Frames are sorted automatically; duplicate positions are an error. |
| `ratios` | A dictionary of `family = weight`. Weights are interpolated linearly between ratio frames. |
| `spawn` | A dictionary of `size = probability`, or `size = { probability = ..., angle_when_stopped = ... }`. Each asteroid size is an independent curve. |

The five asteroid sizes are built in: `chunk`, `small`, `medium`, `big` and `huge`. A size that never appears in any `spawn` frame is not emitted.

Frames may contain only `ratios` or only `spawn`. This matters for routes such as Space Age's `gleba_aquilo`, where medium and big probabilities change at different positions from the asteroid ratios.

### Optional route settings

```lua
local route = PlanetsLib.asteroid_route {
	-- Complete prototype-name map for a custom family. Sizes not listed are
	-- deliberately not emitted.
	names = {
		anorthite = { chunk = "anorthite-chunk" },
	},
	-- Defaults match Space Age.
	angles = { chunk = 1, small = 0.7, medium = 0.6, big = 0.5, huge = 0.4 },
	-- Defaults to 1 * meter / second.
	speed = 1 / 60,

	{
		position = 0.1,
		ratios = { metallic = 3, anorthite = 3 },
		spawn = { chunk = 0.0125 },
	},
	{
		position = 0.9,
		ratios = { metallic = 1, anorthite = 1 },
		spawn = { chunk = 0.025 },
	},
}
```

- `names[family]` is a **complete** map of `size = prototype name` for that family. Supplying it replaces the default name convention for that family, so omit sizes you do not want to emit. Families without a `names` entry use the default convention.
- `angles` supplies default `angle_when_stopped` values per size. Individual spawn points may override the angle with `{ probability = ..., angle_when_stopped = ... }`.
- `speed` is the asteroid speed written to every generated entry.

### Default prototype names

For a family named `metallic`:

| Size | Prototype name | Extra field |
| --- | --- | --- |
| `chunk` | `metallic-asteroid-chunk` | `type = "asteroid-chunk"` |
| `small` | `small-metallic-asteroid` | |
| `medium` | `medium-metallic-asteroid` | |
| `big` | `big-metallic-asteroid` | |
| `huge` | `huge-metallic-asteroid` | |

The same convention applies to custom families. For example, `ratios = { auric = 1 }` produces `auric-asteroid-chunk`, `small-auric-asteroid`, and so on.

## Generated definitions

### Space connections

```lua
local definitions = route:connection()
```

returns an array in the shape expected by [[SpaceConnectionPrototype]]:

```lua
{
	asteroid = "metallic-asteroid-chunk",
	type = "asteroid-chunk",
	spawn_points = {
		{ distance = 0.1, probability = 0.0125, speed = 1 / 60, angle_when_stopped = 1 },
		{ distance = 0.9, probability = 0.0025, speed = 1 / 60, angle_when_stopped = 1 },
	},
}
```

Evaluation positions for a size are the union of all ratio-frame positions and that size's own spawn control points. Probabilities, ratio weights and per-point angles are interpolated linearly and clamped before the first / after the last control point. Each ratio keyframe is first normalised by its **largest weight**, then the normalised weights are interpolated, matching Space Age's helper. At a ratio keyframe the dominant family therefore has ratio `1`, and other families are scaled by `weight / max_weight`. The `spawn[size]` probability is the probability of the dominant family.

Entries with zero probability everywhere are omitted.

### Planets and space locations

```lua
local definitions = route:planet(0.9) -- position defaults to 0.9
```

returns an array in the shape expected by [[PlanetPrototype]]:

```lua
{
	asteroid = "metallic-asteroid-chunk",
	type = "asteroid-chunk",
	probability = 0.0025,
	speed = 1 / 60,
	angle_when_stopped = 1,
}
```

Only entries with `probability > 0` are emitted. Planet entries do not have `distance` or `spawn_points`.

## Custom asteroid types

Adding a family only requires adding it to the ratio keyframes. The default naming convention handles the five prototypes automatically:

```lua
-- Secretas-style auric asteroids:
ratios = { metallic = 2, carbonic = 4, oxide = 10, auric = 6 },
```

If a custom asteroid uses a different prototype name, supply a `names` map. This is useful for chunk-only asteroids such as Muluna's `anorthite-chunk`:

```lua
local route = PlanetsLib.asteroid_route {
	names = {
		anorthite = { chunk = "anorthite-chunk" },
	},
	{
		position = 0.1,
		ratios = { metallic = 3, carbonic = 2, oxide = 1, anorthite = 3 },
		spawn = { chunk = 0.0125 },
	},
	{
		position = 0.9,
		ratios = { metallic = 1, carbonic = 1, oxide = 1, anorthite = 1 },
		spawn = { chunk = 0.025 },
	},
}

data.raw.planet.muluna.asteroid_spawn_definitions = route:planet(0.9)
data.raw.planet.muluna.asteroid_spawn_influence = 0.1
```

Because `anorthite` has the same weight as `metallic` at every frame, its probability matches metallic's, reproducing the common "clone the metallic entry" pattern without manual deep-copying.

## Migrating from Space Age's helper

`PlanetsLib.asteroid_route` also accepts an existing Space Age-style table (`type_ratios` plus `probability_on_range_*`) and converts it without mutating the source:

```lua
local asteroid_util = require("__space-age__.prototypes.planet.asteroid-spawn-definitions")

local route = PlanetsLib.asteroid_route(asteroid_util.gleba_fulgora)

connection.asteroid_spawn_definitions = route:connection()
planet.asteroid_spawn_definitions = route:planet(0.9)
```

The ratio array is mapped to `metallic`, `carbonic`, `oxide`, plus `promethium` when the source sets `has_promethium_asteroids = true`. For vendored helpers with custom asteroid types, pass the family order explicitly:

```lua
local route = PlanetsLib.asteroid_route(secretas_asteroid_util.aquilo_secretas, {
	families = { "metallic", "carbonic", "oxide", "promethium", "auric" },
})
```

Options accepted by the converter are `families`, `names`, `angles` and `speed`.

## Applying a route

```lua
PlanetsLib.set_asteroid_spawn_definitions(target, route_or_spec, options)
```

- `target` is a prototype table or a prototype name.
- The target is resolved as a `planet`, then a `space-location`, then a `space-connection`.
- For planets and space locations, definitions are sampled at `options.position` (default `0.9`).
- `options.influence`, when supplied, is written to `asteroid_spawn_influence`. It is not derived from the route.
- For space connections, `position` and `influence` are rejected because they do not apply.
- Returns the resolved prototype.

The setter is a convenience wrapper; direct field assignment remains fully supported. It may be called in any data stage where the target prototype already exists.

## Direct API reference

- `PlanetsLib.asteroid_route(spec)` — Builds an `AsteroidRoute` from a keyframe table. Also accepts a Space Age-style table, with an optional `{ families = ..., names = ..., angles = ..., speed = ... }` conversion options table.
- `AsteroidRoute:connection()` — Returns definitions for `space-connection.asteroid_spawn_definitions`.
- `AsteroidRoute:planet(position)` — Returns definitions for `planet.asteroid_spawn_definitions`. `position` defaults to `0.9`.
- `PlanetsLib.asteroid_spawn_definitions(route_or_spec, position)` — Same second-argument convention as Space Age's helper: omit the position for connection definitions, or pass a number for planet definitions.
- `PlanetsLib.set_asteroid_spawn_definitions(target, route_or_spec, options)` — Resolves a prototype and writes the definitions for you.

## Differences from Space Age's helper

- Ratios are named dictionaries instead of positional arrays, so adding a custom asteroid does not shift every other ratio.
- Custom asteroid prototype names are supported through `names`.
- Zero-probability families and sizes are omitted instead of emitting empty entries.
- Values before the first / after the last control point are clamped instead of performing arithmetic on missing points.
- Invalid sizes, positions, probabilities, family sets and prototype-name collisions produce descriptive errors during the data stage.
- The helper has no Space Age dependency; vanilla-style tables are converted on request.
