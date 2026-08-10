PlanetsLib.constants.spoil_categories = {}
PlanetsLib.constants.item_spoil_category = {} --item-name -> PlanetsLibSpoilageCategoryPrototype

local Public = {}

function Public.create_spoil_category(prototype)
    assert(prototype.name,"PlanetsLib.create_spoil_category(): Spoil category must have a defined name.")
    PlanetsLib.constants.spoil_categories[prototype.name] = {
        name = prototype.name,
        localised_spoil_result = prototype.localised_spoil_result or {"description.spoil-result"},
        localised_spoil_time = prototype.localised_spoil_time or {"description.spoil-time"},
        quality_tooltip = prototype.quality_tooltip or {"quality-tooltip.spoils-slower"},
    }

end

Public.create_spoil_category{
    name = "spoil",
}







return Public