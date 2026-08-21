data:extend{
    {
        type = "custom-event",
        name = "PlanetsLib-on-entity-replaced"
        --Called when PlanetsLib replaces one entity with another.
    },
    {
        type = "custom-event",
        name = "PlanetsLib-on-planet-day-begins"
        --Raised when a planet with a tracked day-night cycle hits midnight(daytime == 0.5)
    }
}
