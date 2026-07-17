local rro = require("lib.remove-replace-object")
PlanetsLib = {}
PlanetsLib.events = require("scripts.custom-events")
PlanetsLib.constants = prototypes.mod_data.Planetslib.data
PlanetsLib.objects = require("lib.remove-replace-object")
local rocket_parts = require("scripts.rocket-parts")
local unreachable_techs = require("scripts.unreachable-techs")
local entity_replacement = require("scripts.entity-replacement")
PlanetsLib.replace_entity=entity_replacement.replace_entity
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

	
end

if settings.startup["PlanetsLib-warn-on-hidden-prerequisites"].value then
	script.on_event(defines.events.on_player_joined_game, function()
		if game.tick == 0 then
			unreachable_techs.warn_unreachable_techs()
		end
	end)
end

script.on_init(function()
	if cargo_pods then
		cargo_pods.init_storage()
	end
		storage.old_replacement_rules = PlanetsLib.constants.on_entity_placed_on_planet_replacements
end)

local function replace_entity(surface,old_entity,new_entity)
	if surface then
		
		local entities = surface.find_entities_filtered{name = old_entity}
		local entity_ghosts = surface.find_entities_filtered{name = "entity-ghost",ghost_name = old_entity}
			
		for _,entities in pairs({entities,entity_ghosts}) do
			if not rro.deep_equals(entities,{}) then
				game.print({"planetslib.planetslib-entity-migration",old_entity,new_entity})
			end
			for _,entity in pairs(entities) do
				entity_replacement.replace_entity(entity,new_entity,false)
			end
		end
		
	end
	

end

local function migrate_surface(planet_name,surface,planet_rules,replacement_rules)
	if not storage.old_replacement_rules[planet_name] then storage.old_replacement_rules[planet_name] = {} end
		for entity_name,entity_table in pairs(planet_rules) do
			local new_rule = PlanetsLib.constants.on_entity_placed_on_planet_replacements[planet_name][entity_name]
			if storage.old_replacement_rules[planet_name][entity_name] then 
				local old_rule = storage.old_replacement_rules[planet_name][entity_name]
				

				if new_rule.enabled ~= old_rule.enabled or new_rule.entity ~= old_rule.entity then
					game.print({"planetslib.planetslib-entity-replacement-rule-changed"})
					if new_rule.enabled == false then
						--Revert changes previously made. Search for old_rule.entity and new_rule.entity and replace both with new_rule.old_entity
						--game.print("[PlanetsLib]: Entity replacement rule change detected:\n Migrating __1__ to __3__\nMigrating __2__ to __3__")
						replace_entity(surface,old_rule.entity,new_rule.old_entity)
						replace_entity(surface,new_rule.entity,new_rule.old_entity)
						storage.old_replacement_rules[planet_name][entity_name] = new_rule
					elseif new_rule.enabled == true then
						--Make overdue changes. Search for new_rule.old_entity, old_rule.old_entity, and old_rule.entity and replace them with new_rule.entity 
						replace_entity(surface,old_rule.old_entity,new_rule.entity)
						replace_entity(surface,new_rule.old_entity,new_rule.entity)
						replace_entity(surface,old_rule.entity,new_rule.entity)
						storage.old_replacement_rules[planet_name][entity_name] = new_rule
					end

				end
			else
				storage.old_replacement_rules[planet_name][entity_name] = replacement_rules[planet_name][entity_name]
				if new_rule.enabled == true then
					--Make overdue changes. Search for new_rule.old_entity and replace them with new_rule.entity 
					replace_entity(surface,new_rule.old_entity,new_rule.entity)
				end
				
				
			end
		end

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

	local replacement_rules = PlanetsLib.constants.on_entity_placed_on_planet_replacements
	if not storage.old_replacement_rules then storage.old_replacement_rules = {} end
	
	if replacement_rules then
		--Search for changes to entity replacement rules, and replace existing entities if the entity rules changed since last load
		for planet_name,planet_rules in pairs(replacement_rules) do
			local is_space_platform = planet_name == "space-platform"
			
			if is_space_platform then --Migrate each space platform using space platform rules
				for _,surface in pairs(game.surfaces) do
					if surface.platform then
						migrate_surface(planet_name,surface,planet_rules,replacement_rules)
					end
				end
			else
				local surface --Migrate the one planet these rules apply to.
				if game.planets[planet_name] then surface = game.planets[planet_name].surface end
				migrate_surface(planet_name,surface,planet_rules,replacement_rules)
			end
			
		end
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
	for entity,replacement_table in pairs(replacements) do
		local replacement = replacement_table.entity
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
	script.on_event(defines.events.script_raised_built,on_built_entity_combined,on_built_filters_and_silos) 
	script.on_event(defines.events.script_raised_revive,on_built_entity_combined,on_built_filters_and_silos)
	script.on_event(defines.events.on_space_platform_built_entity,on_built_entity_combined,on_built_filters_and_silos)
	--script.on_event(defines.events.on_biter_base_built,entity_replacement.on_built_entity)

	--script.on_event(defines.events.on_player_setup_blueprint,entity_replacement.blueprint_standardize)
end


if script.active_mods["gvv"] then require("__gvv__.gvv")() end --gvv enables debugging of storage values with a GUI
