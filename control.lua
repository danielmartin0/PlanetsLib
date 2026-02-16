local rocket_parts = require("scripts.rocket-parts")
local unreachable_techs = require("scripts.unreachable-techs")

-- By convention, please register event handlers in this file rather than the scripts directory, to help avoid collisions

local cargo_pods
if script.active_mods["space-age"] then
	cargo_pods = require("scripts.cargo-pods")
end

if cargo_pods then
	script.on_event(
		defines.events.on_built_entity,
		rocket_parts.on_built_rocket_silo,
		{ { filter = "type", type = "rocket-silo" }, { filter = "ghost_type", type = "rocket-silo" } }
	)

	script.on_event(defines.events.on_cargo_pod_started_ascending, cargo_pods.on_cargo_pod_started_ascending)

	script.on_init(function()
		cargo_pods.init_storage()
	end)
end

if settings.startup["PlanetsLib-warn-on-hidden-prerequisites"].value then
	script.on_event(defines.events.on_player_joined_game, function()
		if game.tick == 0 then
			unreachable_techs.warn_unreachable_techs()
		end
	end)
end

script.on_configuration_changed(function(data)
	if cargo_pods then
		cargo_pods.init_storage()
	end

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
