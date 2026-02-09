local warn_color = { r = 255, g = 90, b = 54 }

-- 获取白名单物品列表
local function get_whitelist_items(planet_name)
	local whitelist = {}
	local storage_lib = storage.planets_lib
	local seen = {}

	-- 收集星球特定白名单
	if storage_lib.whitelisted_names and storage_lib.whitelisted_names[planet_name] then
		for item_name in pairs(storage_lib.whitelisted_names[planet_name]) do
			if not seen[item_name] then
				seen[item_name] = true
				table.insert(whitelist, item_name)
			end
		end
	end

	-- 收集全局白名单
	if storage_lib.whitelisted_names_all_planets then
		for item_name in pairs(storage_lib.whitelisted_names_all_planets) do
			if not seen[item_name] then
				seen[item_name] = true
				table.insert(whitelist, item_name)
			end
		end
	end

	return whitelist
end

-- 格式化白名单显示文本（不换行，用间隔符分隔）
local function format_whitelist_text(whitelist_items)
	if #whitelist_items == 0 then
		return nil
	end
	local formatted = {}
	for _, item_name in ipairs(whitelist_items) do
		table.insert(formatted, "[item=" .. item_name .. "]")
	end
	return table.concat(formatted, "、")
end

local function init_storage()
	storage.planets_lib = storage.planets_lib or {}
	storage.planets_lib.cargo_pods_seen_on_platforms = storage.planets_lib.cargo_pods_seen_on_platforms or {}
	storage.planets_lib.cargo_pod_canceled_whisper_ticks = storage.planets_lib.cargo_pod_canceled_whisper_ticks or {}
end

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

local cargo_drops_technology_names = {}
for _, planet in pairs(prototypes.space_location) do
	cargo_drops_technology_names[planet.name] = "planetslib-" .. planet.name .. "-cargo-drops"
end

local function pod_contents_is_allowed(pod_contents, planet_name)
	local whitelists = prototypes.mod_data.Planetslib.data.planet_cargo_drop_whitelists
	local old_names_all = storage.planets_lib.whitelisted_names_all_planets or {}
	local old_names = storage.planets_lib.whitelisted_names or {}
	local old_types_all = storage.planets_lib.whitelisted_types_all_planets or {}
	local old_types = storage.planets_lib.whitelisted_types or {}

	for _, item in pairs(pod_contents) do
		local entity = prototypes.entity[item.name]
		local whitelisted_by_item_name = whitelists.all.item_names[item.name]
			or (whitelists[planet_name] and whitelists[planet_name].item_names[item.name])
		local whitelisted_by_entity_type = entity
			and (whitelists.all.entity_types[entity.type]
			or (whitelists[planet_name] and whitelists[planet_name].entity_types[entity.type]))

		local old_condition = old_names_all[item.name]
			or (old_names[planet_name] and old_names[planet_name][item.name])
			or (entity and (old_types_all[entity.type] or (old_types[planet_name] and old_types[planet_name][entity.type])))

		if not whitelisted_by_item_name and not whitelisted_by_entity_type and not old_condition then
			return false
		end
	end
	return true
end

local function destroy_pod_on_platform(pod, platform, planet_name)
	local hub = platform.hub
	if hub and hub.valid then
		local pod_inventory = pod.get_inventory(defines.inventory.cargo_unit)
		local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
		if pod_inventory and hub_inventory then
			for _, item in pairs(pod_inventory.get_contents()) do
				hub_inventory.insert(item)
			end
		end
	end

	-- 获取白名单展示
	local whitelist_items = get_whitelist_items(planet_name)
	local formatted_whitelist = format_whitelist_text(whitelist_items)
	local tech_name = "planetslib-" .. planet_name .. "-cargo-drops"

	for _, player in pairs(game.connected_players) do
		if player.valid and player.surface and player.surface.valid and player.surface.index == platform.surface.index then
			local whisper_hash = platform.index .. "-" .. player.name
			local last_whisper_tick = storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash]
			if (not last_whisper_tick) or (game.tick - last_whisper_tick >= 60 * 10) then
				if formatted_whitelist then
					player.print({
						"beomyo-string.string2",
						"[space-platform=" .. platform.index .. "]",
						"[technology=" .. tech_name .. "]",
						formatted_whitelist
					}, { color = warn_color })
				else
					player.print({
						"beomyo-string.string3",
						"[space-platform=" .. platform.index .. "]",
						"[technology=" .. tech_name .. "]"
					}, { color = warn_color })
				end
				storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash] = game.tick
			end
		end
	end

	local pod_unit_number = pod.unit_number
	pod.destroy()
	storage.planets_lib.cargo_pods_seen_on_platforms[pod_unit_number] = nil
end

local function examine_cargo_pods(platform, planet_name)
	local cargo_pods = platform.surface.find_entities_filtered({ type = "cargo-pod" })
	if #cargo_pods == 0 then return end
	for _, pod in pairs(cargo_pods) do
		if pod
			and pod.valid
			and pod.cargo_pod_destination
			and pod.cargo_pod_destination.surface
			and pod.cargo_pod_destination.surface.planet
			and pod.cargo_pod_destination.surface.planet.name == planet_name
			and not storage.planets_lib.cargo_pods_seen_on_platforms[pod.unit_number] then
			local pod_contents = pod.get_inventory(defines.inventory.cargo_unit).get_contents()
			local has_only_allowed_cargo = pod_contents_is_allowed(pod_contents, planet_name)
			local nearby_hubs = platform.surface.find_entities_filtered({
				name = { "space-platform-hub", "cargo-bay" },
				position = pod.position,
				radius = 4,
			})
			local launched_from_platform = #nearby_hubs > 0
			storage.planets_lib.cargo_pods_seen_on_platforms[pod.unit_number] = {
				launched_from_platform = launched_from_platform,
				entity = pod,
				platform_index = platform.index,
			}
			if launched_from_platform and not has_only_allowed_cargo then
				destroy_pod_on_platform(pod, platform, planet_name)
			end
		end
	end
end

script.on_nth_tick(20, function()
	for _, force in pairs(game.forces) do
		for _, platform in pairs(force.platforms) do
			if platform and platform.valid and platform.surface and platform.surface.valid then
				local planet_name = platform.space_location and platform.space_location.valid and platform.space_location.name or nil
				if planet_name then
					local cargo_drops_tech = force.technologies[cargo_drops_technology_names[planet_name]]
					if cargo_drops_tech and not cargo_drops_tech.researched then
						local has_nothing_effect = false
						for _, effect in pairs(cargo_drops_tech.prototype.effects) do
							if effect.type == "nothing" then
								has_nothing_effect = true
								break
							end
						end
						if has_nothing_effect then
							examine_cargo_pods(platform, planet_name)
						end
					end
				end
			end
		end
	end
end)

-- 兼容旧版白名单接口
remote.add_interface("planetslib", {
	add_to_cargo_drop_item_name_whitelist = function(name, planet_name)
		if type(name) ~= "string" then error("name must be a string") end
		storage.planets_lib.whitelisted_names = storage.planets_lib.whitelisted_names or {}
		storage.planets_lib.whitelisted_names_all_planets = storage.planets_lib.whitelisted_names_all_planets or {}
		if planet_name then
			storage.planets_lib.whitelisted_names[planet_name] = storage.planets_lib.whitelisted_names[planet_name] or {}
			storage.planets_lib.whitelisted_names[planet_name][name] = true
		else
			storage.planets_lib.whitelisted_names_all_planets[name] = true
		end
	end,
	remove_from_cargo_drop_item_name_whitelist = function(name, planet_name)
		if type(name) ~= "string" then error("name must be a string") end
		if planet_name and storage.planets_lib.whitelisted_names and storage.planets_lib.whitelisted_names[planet_name] then
			storage.planets_lib.whitelisted_names[planet_name][name] = nil
		elseif storage.planets_lib.whitelisted_names_all_planets then
			storage.planets_lib.whitelisted_names_all_planets[name] = nil
		end
	end,
	add_to_cargo_drop_item_type_whitelist = function(type_name, planet_name)
		if type(type_name) ~= "string" then error("type_name must be a string") end
		storage.planets_lib.whitelisted_types = storage.planets_lib.whitelisted_types or {}
		storage.planets_lib.whitelisted_types_all_planets = storage.planets_lib.whitelisted_types_all_planets or {}
		if planet_name then
			storage.planets_lib.whitelisted_types[planet_name] = storage.planets_lib.whitelisted_types[planet_name] or {}
			storage.planets_lib.whitelisted_types[planet_name][type_name] = true
		else
			storage.planets_lib.whitelisted_types_all_planets[type_name] = true
		end
	end,
	remove_from_cargo_drop_item_type_whitelist = function(type_name, planet_name)
		if type(type_name) ~= "string" then error("type_name must be a string") end
		if planet_name and storage.planets_lib.whitelisted_types and storage.planets_lib.whitelisted_types[planet_name] then
			storage.planets_lib.whitelisted_types[planet_name][type_name] = nil
		elseif storage.planets_lib.whitelisted_types_all_planets then
			storage.planets_lib.whitelisted_types_all_planets[type_name] = nil
		end
	end,
})
