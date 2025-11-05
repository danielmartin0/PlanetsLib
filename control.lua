local rocket_parts = require("scripts.rocket-parts")
local unreachable_techs = require("scripts.unreachable-techs")

if script.active_mods["space-age"] then
	require("scripts.cargo-pods")
end


script.on_event(defines.events.on_built_entity, function(event)
	if script.active_mods["space-age"] then
		rocket_parts.on_built_rocket_silo(event)
	end
	
end)

script.on_event(defines.events.on_player_joined_game, function()
	if settings.startup["PlanetsLib-warn-on-hidden-prerequisites"].value then
		if game.tick == 0 then
			unreachable_techs.warn_unreachable_techs()
		end
	end
end)

script.on_configuration_changed(function(data)
	local mod_changed = false

	for _, _ in pairs(data.mod_changes) do
		mod_changed = true
		break
	end

	if not mod_changed then
		return
	end

	if settings.startup["PlanetsLib-warn-on-hidden-prerequisites"].value then
		unreachable_techs.warn_unreachable_techs()
	end
end)
