return function(LuaEntity)

    local is_ghost = LuaEntity.name == "entity-ghost"
    local name = is_ghost and LuaEntity.ghost_name or LuaEntity.name

    return name




end
