---
sidebar_label: Recipe Events
---

# Recipe Events

PlanetsLib includes one event that recipes can hook into using `RecipePrototype::PlanetsLib_recipe_effects`. This event adds items to the machine's ingredient inventory on craft. Additional events may be added in the future.

#### [[RecipePrototype]] field: `PlanetsLib_recipe_effects` [`table`]
* `returned_ingredients` [`table(ItemProduct)`]
    * When this field is defined, returned items are inserted into the crafting machine's input. The field must be defined before data-final-fixes. PlanetsLib sets `raise_on_crafted` on the recipe and adds a tooltip describing the return.
    * Only items are supported. Defining `type = "fluid"` raises an error during data-final-fixes.
    * Supported fields:
        * `name` ([[ItemID]]) — The item to return. It should match an ingredient of the recipe so PlanetsLib can track its production statistics.
        * `type` — Must be `"item"`.
        * `amount` (number) — The number of items returned per craft, or per batch when using `batch_count`.
        * `independent_probability` (number, 0–1) — Rolls separately for this returned ingredient on every craft.
        * `shared_probability` (`{min, max}`, 0–1) — Uses the craft's shared roll. The ingredient is returned when the roll is between `min` and `max`, inclusive. `min` defaults to `0` and `max` to `1`.
        * `ignored_by_productivity` (number) — On a productivity-bonus craft, PlanetsLib returns `amount - ignored_by_productivity` instead of `amount`. This returns the base amount on a normal craft without duplicating the ignored part on bonus crafts.
        * `batch_count` (positive number) — On a normal craft, instead of returning `amount` every craft, PlanetsLib inserts `amount * batch_count` items with probability `1 / batch_count`. This reduces the frequency of insertions without changing the expected return rate. (Earlier documentation called this field `batch_size`; the implementation uses `batch_count`.)
    * If neither probability field is set, the ingredient is returned on every craft.
    * PlanetsLib derives the internal fields `add_to_stats`, `amount_minus_ignored_by_productivity`, `inverse_batch_count`, and `no_probability` during data-final-fixes. Do not set these yourself.
    * When the returned item matches a recipe ingredient, PlanetsLib sets that ingredient's `ignored_by_stats` to its full amount. Do not rely on a custom `ignored_by_stats` value for that ingredient.

#### Known limitations
* The tooltip displays `shared_probability` as a percentage (`(max - min) * 100`), but `independent_probability` as the raw 0–1 value. This is a cosmetic inconsistency.
* When batching skips an insertion, the skipped return is not reflected in the machine's production statistics. Returned items are also not subtracted from consumption statistics.
* The derived `add_to_stats` value is currently unused by the runtime handler.

#### Example

```lua
    ingredients = {
      {type="item", name="cellulose", amount=15},
      {type="item", name="alumina-crushed", amount=1},
    },
    results = {
      {type="fluid", name="petroleum-gas", amount=20},
      {type="fluid", name="tar", amount=8},
    },
    PlanetsLib_recipe_effects = {
      returned_ingredients = {
        {type="item", name="alumina-crushed", amount=1,shared_probability = {min=0,max=0.9},ignored_by_productivity=1},
      },
    },
```

![Returned ingredients field](/docs-images/returned-ingredients.png)