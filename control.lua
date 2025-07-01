if script.active_mods["space-age"] then
	require("scripts.cargo-pods")
end

local rocket_parts = require("scripts.rocket-parts")

script.on_event(defines.events.on_built_entity, function(event)
    rocket_parts.on_built_rocket_silo(event)
end)