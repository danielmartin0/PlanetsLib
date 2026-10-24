---
sidebar_label: Entity Fields
---

# Entity Fields

* [[EntityPrototype]]::`PlanetsLib_pipette_result`(string) — Defines the entity summoned when using the pipette tool on this entity. Is mutually exclusive with `EntityPrototype::placeable_by`. This field only affects pipette behavior, and does not make this entity placeable by the entity's pipette result. A wrapper for `PlanetsLib.constants.pipette_result`. In data-final-fixes, manipulate this mod-data table directly.
* [[EntityPrototype]]::`PlanetsLib_do_not_generate_variants`(boolean) — When `true`, PlanetsLib's built-in data-stage variant generators skip this prototype. This is honored by ground-digger generation, rocket-lift/rocket-part multiplier variants, and `PlanetsLib.create_planet_entity_variant`. `PlanetsLib.create_planet_entity_variant` sets it automatically on generated variants to prevent recursive variant generation; set it manually on prototypes that are already variants. `PlanetsLib.create_planet_entity_variant` also recognizes the generated `-PlanetsLib-` name suffix, so overriding the flag through `new_properties` cannot re-enable variant-of-variant generation.
