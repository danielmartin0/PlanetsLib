
The primary intent of PlanetsLib is to be a library which provides opt-in functionality for other mods. However, a small number of game-affecting or player-interface-affecting features have been added over time. These are listed below, player feedback on them is most welcome in [Discord](https://discord.gg/nFVqaPEk97).

* Unlinking hidden prerequisites
    * If PlanetsLib detects that technologies have hidden prerequisites such that they would be unresearchable, it warns players about this fact.
        * This is done because the Factorio client gives no explanation or reason for why these technologies cannot be researched.
        * There are PlanetsLib mod settings to repair the user's game by unlinking all such prerequisites, or to disable the warning.
* Fixed rocket weights of vanilla items
    * If an item prototype does not have an explicitly specified rocket weight, the behavior of the Factorio engine is to assign it a weight based on the recipes that produce it. Unfortunately, this means that the rocket weight of vanilla items is liable to change when additional mods are installed. PlanetsLib therefore sets an explicit weight on vanilla items equal to their weight in Space Age. This occurs in `data-final-fixes` and only if the item does not have a weight by that point.
* Extra informational tooltips
    * On recipes:
        * Freshness resets on craft completion
            * This tracks `result_is_always_fresh` and only appears if `true`.
        * Freshness resets on craft beginning
            * This tracks `reset_freshness_on_craft` and only appears if `true`.
        * Products preserved in machine output
            * This tracks `preserve_products_in_machine_output` and only appears if `true`.
    * All such tooltips are added in `data-final-fixes`.
* Biolab inputs
    * Because modders often forget about the Biolab when adding a new science pack, PlanetsLib mirrors all science packs from the vanilla lab to the Biolab in `data-final-fixes`.
* Centrifuge entity improvements
    * This entity is given an input and an output fluidbox (or two of each if the mod setting `PlanetsLib-enable-additional-centrifuge-fluidboxes` is enabled).
    * Also, the graphics of the working glow are improved so that it naturally glows different colors depending on the recipe.
* Space platform hub improvements
    * The list of cargo pods that can be accepted by the vanilla space platform hub can be modifying by modifying `PlanetsLib.constants.space_platform_hub_receiving_cargo_units`. The global functions `platform_upper_hatch` and `platform_lower_hatch` added by base Space Age are overridden and modified by PlanetsLib to reference mod-data tables from PlanetsLib.
* Space tile without the ability to cover it
    * A space tile that can be used around limited surfaces floating in space, as it can not be covered in space platform tiles. Modders, enable it with the `PlanetsLib-enable-blocking-empty-space-tile` setting. The name of the tile is `planetslib-empty-space`, all localization is set to match the regular `empty-space` tile from space age.