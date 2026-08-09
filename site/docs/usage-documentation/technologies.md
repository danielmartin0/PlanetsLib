---
sidebar_label: Science & Technologies
---

# Science & Technologies

* `PlanetsLib.get_child_technologies(tech_name)` — Returns a list of the names of all technologies that have `tech_name` as a prerequisite.
* `PlanetsLib.sort_science_pack_names(science_pack_names_table)` — Sorts the given list of science pack names (strings expected) by the `order` fields of the corresponding prototypes, or by their names if an `order` field does not exist.
    * This is useful for defining the inputs of labs because (unlike in Factoriopedia) science packs displayed in labs aren't ordered by the `order` field.

### Recipe productivity technology helper field

PlanetsLib adds a new field named `PlanetsLib_recipe_productivity_effects` to [[TechnologyPrototype]], used by recipe productivity technologies. During `data-final-fixes`, technologies with this field will have their effects list appended or replaced with recipes matching either an output name or recipe category. Recipes will be excluded if they have the field `PlanetsLib_blacklist_technology_updates` set to true `true`.

Recipe products are ignored if they are not "productivity-capable"—if `ignored_by_productivity` is greater than or equal to `amount` (or `amount_max`)—because changing a recipe's productivity has no effect on such products. If a recipe has no productivity-capable products, it is fully ineligible; and if a recipe has multiple products, but only one product is productivity-capable (e.g. Kovarex enrichment), it is eligible _even if `allow_multiple_results` = false_.

#### [[TechnologyPrototype]] field: `PlanetsLib_recipe_productivity_effects` Properties:
*   `effects`: `array[ChangeResultProductivityModifier]`
*   `category_blacklist` - `array[`[`RecipeCategoryID`](https://lua-api.factorio.com/latest/types/RecipeCategoryID.html)`]`
*   `purge_other_effects`- `boolean`. Default: false. Before adding effects added by `PlanetsLib_recipe_productivity_effects`, remove all 
effects not flagged with `PlanetsLib_force_include`.
*   `allow_recipes_without_productivity` - `boolean`. Default: false. Captures recipes even if they have `allow_productivity` set to false.

#### `ChangeResultProductivityModifier` Properties:
*   `name` (optional) - [[ItemID]] Required if not using `category`. Incompatible with `category`.
*   `type` (optional) - [[ProductPrototype]] Required if using `name`.
*   `category` (optional) - [[RecipeCategoryID]]  Required if not using `name`. Incompatible with `name` and `category_blacklist`.
*   `allow_multiple_results`: `boolean`. Default: false. When false, only recipes with one (productivity-capable) result are added to the technology's effect list. If multiple results have the same name, they are counted as a single result rather than being counted individually.
##### Inherited from [[ChangeRecipeProductivityModifier]]
*   `change`
*   `icons` (optional)
*   `icon` (optional)
*   `icon_size` (optional)
*   `hidden` (optional)
*   `use_icon_overlay_constant` (optional)

#### New [[BaseModifier]] field: `PlanetsLib_force_include`
*  Makes this modifier immune to `purge_other_effects`.

#### New [[RecipePrototype]] field: `PlanetsLib_blacklist_technology_updates`
*  Stops PlanetsLib from targeting this recipe in technology updates.

#### Example
```lua
{
   type = "technology",
   name = "thruster-fuel-productivity",
   --Other required fields here
   PlanetsLib_recipe_productivity_effects = {
               purge_other_effects = true,
               effects = {
                   {
                       type = "fluid",
                       name = "thruster-fuel",
                       change = 0.1
                   },
                   {
                       type = "fluid",
                       name = "thruster-oxidizer",
                       change = 0.1
                   },
               }
           }
}
```

#### Tech tree adjustments

* `PlanetsLib.excise_tech_from_tech_tree(tech_name)` — Seamlessly removes a technology from the tech tree by making all its dependencies depend instead on the technology's prerequisites. In addition, `hidden = true` is set on the technology.
* `PlanetsLib.excise_recipe_from_tech_tree(recipe_name)` — Removes this recipe from all technologies, and if this would cause any technology to have zero effects, the technology is excised using `PlanetsLib.excise_tech_from_tech_tree`.
* `PlanetsLib.excise_effect_from_tech_tree(effect)` — Similar to `excise_recipe_from_tech_tree`, but any effect can be passed.
    * Example: `PlanetsLib.excise_effect_from_tech_tree({ type = "unlock-quality", quality = "uncommon" })`
* `PlanetsLib.add_science_packs_from_vanilla_lab_to_technology(technology)` — Adds all science packs that the vanilla lab have slots for to the unit of the given technology. Can be useful when defining endgame technologies.
