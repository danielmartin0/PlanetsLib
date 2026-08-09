PlanetsLib includes one event that recipes can hook into using `RecipePrototype::PlanetsLib_recipe_effects`. This event adds items to the machine's ingredient inventory on craft. Additional events may be added in the future.

#### `RecipePrototype` field: PlanetsLib_recipe_effects [`table`]
* `returned_ingredients` [`table(ItemProduct)`]
    * When this field is defined, ingredients are returned to the crafting machine's input. Must be defined prior to data-final-fixes.
    * Only supports the fields `name`,`type`, `amount`, `independent_probability`, and `shared_probability`.
    * Additional field: `batch_size(float)`: Reduces the frequency of item insertions to improve performance without reducing overall return rate.

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
    },```
```