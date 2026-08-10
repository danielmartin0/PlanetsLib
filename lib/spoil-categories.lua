PlanetsLib.constants.spoil_categories = {}
PlanetsLib.constants.item_spoil_category = {} --item-name -> PlanetsLibSpoilageCategoryPrototype

local Public = {}

function Public.create_spoil_category(prototype)
    assert(prototype.name,"PlanetsLib.create_spoil_category(): Spoil category must have a defined name.")
    PlanetsLib.constants.additional_spoil_categories_exist = true
    PlanetsLib.constants.spoil_categories[prototype.name] = {
        name = prototype.name,
        icon = prototype.icon,
        icons = prototype.icons,
        icon_size = prototype.icon_size,
        localised_name = prototype.localised_name or {"spoil-category.".. prototype.name},
        localised_spoil_result = prototype.localised_spoil_result or {"description.spoil-result"},
        localised_spoil_time = prototype.localised_spoil_time or {"description.spoil-time"},
        quality_header = prototype.quality_header or "quality-tooltip.spoils-slower",
    }

end

Public.create_spoil_category{
    name = "spoilable",
    localised_name = {"tooltip-category.spoilable"}
}







return Public