data:extend{
    {
        type = "custom-event",
        name = "PlanetsLib-on-entity-replaced"
        --Called when PlanetsLib replaces one entity with another.
    },
}
if settings.startup["PlanetsLib-enable-on-rocket-part-crafted-event"].value then 
    data:extend{{
        type = "custom-event",
        name = "PlanetsLib-on-rocket-part-crafted"
        --Called when a rocket part is crafted.
    }}
end