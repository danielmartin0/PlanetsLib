if feature_flags.spoiling then
    local items = {
        ["yumako"] = {
            type = "rot",
            integrity=1
        },
        ["jellynut"] = {
            type = "rot",
            integrity=1
        },
        ["fish"] = {
            type = "rot",
            integrity=1
        },
        ["agricultural-science-pack"] = {
            type = "rot",
            integrity=.7
        },
        ["bioflux"] = {
            type = "rot",
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
            type = "rot",
            integrity=.4
        },
        ["jelly"] = {
            type = "rot",
            integrity=.4
        },
        ["nutrients"] = {
            type = "rot",
            integrity=.1
        },
        ["iron-bacteria"] = {
            type = "rot",
            integrity=.1
        },
        ["copper-bacteria"] = {
            type = "rot",
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
