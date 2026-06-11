PlanetsLib = {}
PlanetsLib.constants = prototypes.mod_data.Planetslib.data
PlanetsLib.objects = require("lib.remove-replace-object")
local rocket_parts = require("scripts.rocket-parts")
local unreachable_techs = require("scripts.unreachable-techs")
local entity_replacement = require("scripts.entity-replacement")
-- By convention, please register event handlers in this file rather than the scripts directory, to help avoid collisions

local cargo_pods
if script.active_mods["space-age"] then
	cargo_pods = require("scripts.cargo-pods")
end
local is_cargo_pods = cargo_pods ~= nil
if cargo_pods then
	-- script.on_event(
	-- 	defines.events.on_built_entity,
	-- 	rocket_parts.on_built_rocket_silo,
	-- 	{ { filter = "type", type = "rocket-silo" }, { filter = "ghost_type", type = "rocket-silo" } }
	-- )

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

local entity_replacements = PlanetsLib.constants.on_entity_placed_on_planet_replacements
local is_entity_replacements = not PlanetsLib.objects.deep_equals(entity_replacements,{}) --If no mods add entity replacements, disable related event triggers.
--is_entity_replacements = true
local on_built_filters = {} --List of entity filters derived from entity_replacements to improve performance on entities not governed by replacement rules.
local on_built_filters_and_silos = {}
for planet_name,replacements in pairs(entity_replacements) do
	for entity,replacement in pairs(replacements) do
		table.insert(on_built_filters,{filter = "name", name = entity})
		table.insert(on_built_filters,{filter = "ghost_name", name = entity})
		table.insert(on_built_filters_and_silos,{filter = "name", name = entity}) --This lines are copy-pasted because to my shock, table.deepcopy is unavailable in control.
		table.insert(on_built_filters_and_silos,{filter = "ghost_name", name = entity})
		table.insert(on_built_filters,{filter = "name", name = replacement})
		table.insert(on_built_filters,{filter = "ghost_name", name = replacement})
		table.insert(on_built_filters_and_silos,{filter = "name", name = replacement}) --This lines are copy-pasted because to my shock, table.deepcopy is unavailable in control.
		table.insert(on_built_filters_and_silos,{filter = "ghost_name", name = replacement})
		
	end
end


table.insert(on_built_filters_and_silos,{filter = "type", type = "rocket-silo"})
table.insert(on_built_filters_and_silos,{filter = "ghost_type", type = "rocket-silo"})
print(serpent.block(on_built_filters))
local function on_built_entity_combined(event)
	if is_cargo_pods then
		rocket_parts.on_built_rocket_silo(event)
	end
	if is_entity_replacements then
		entity_replacement.on_built_entity(event)
	end
	
end

script.on_event(defines.events.on_built_entity,on_built_entity_combined,on_built_filters_and_silos)
if is_entity_replacements then
	script.on_event(defines.events.on_robot_built_entity,on_built_entity_combined,on_built_filters_and_silos)
	--script.on_event(defines.events.script_raised_built,on_built_entity_combined,on_built_filters_and_silos) 
	--script.on_event(defines.events.script_raised_revive,on_built_entity_combined,on_built_filters_and_silos)
	script.on_event(defines.events.on_space_platform_built_entity,on_built_entity_combined,on_built_filters_and_silos)
	--script.on_event(defines.events.on_biter_base_built,entity_replacement.on_built_entity)

	--script.on_event(defines.events.on_player_setup_blueprint,entity_replacement.blueprint_standardize)
end
