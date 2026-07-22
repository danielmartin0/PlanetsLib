local events = {
    on_entity_replaced = prototypes.custom_event["PlanetsLib-on-entity-replaced"]
    
}

if settings.startup["PlanetsLib-enable-on-rocket-part-crafted-event"].value then 

    events.on_rocket_part_crafted = prototypes.custom_event["PlanetsLib-on-rocket-part-crafted"]
end
return events