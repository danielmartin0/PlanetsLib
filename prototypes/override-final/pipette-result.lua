for _,prototype in pairs(defines.prototypes.entity) do
    for _,entity in pairs(data.raw[prototype] or {}) do
        if entity.PlanetsLib_pipette_result then
            assert(type(entity.PlanetsLib_pipette_result) == "string", "EntityPrototype::PlanetsLib_pipette_result: Must be a string.")
            assert(not entity.placeable_by,"EntityPrototype::PlanetsLib_pipette_result: This field is mutually exclusive with EntityPrototype::placeable_by.")
            PlanetsLib.constants.pipette_result[entity.name] = entity.PlanetsLib_pipette_result
        end
    end
end