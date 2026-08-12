if feature_flags.spoiling then
    local items = {
        ["yumako"] = {
            type = "rotting",
            integrity=1
        },
        ["jellynut"] = {
            type = "rotting",
            integrity=1
        },
        ["fish"] = {
            type = "rotting",
            integrity=1
        },
        ["agricultural-science-pack"] = {
            type = "rotting",
            integrity=.7
        },
        ["bioflux"] = {
            type = "rotting",
            integrity=2
        },
        ["pentapod-egg"] = {
            type = "hatching",
            integrity=.1
        },
        ["biter-egg"] = {
            type = "hatching",
            integrity=.1
        },
        ["yumako-mash"] = {
            type = "rotting",
            integrity=.4
        },
        ["jelly"] = {
            type = "rotting",
            integrity=.4
        },
        ["nutrients"] = {
            type = "rotting",
            integrity=.1
        },
        ["iron-bacteria"] = {
            type = "rotting",
            integrity=.1
        },
        ["copper-bacteria"] = {
            type = "rotting",
            integrity=.1
        },
    }

    for name, value in pairs(items) do
        local item = data.raw.item[name] or data.raw.capsule[name]
        if item then
            item.planetslib_spoilage_meta = {
                type = value.type,
                -- a float, how well this item should take to being procesed by other mods.
                -- eg, if it is bellow 1 then it should not take well to being preserved,
                -- if above 1 then it should last longer with such process.
                integrity = value.integrity
            }
        end
    end
end
