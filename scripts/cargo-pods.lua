local Public = {}

local warn_color = { r = 255, g = 90, b = 54 }

local function init_storage()
	storage.planets_lib = storage.planets_lib or {}

	storage.planets_lib.cargo_pods_seen_on_platforms = storage.planets_lib.cargo_pods_seen_on_platforms or {}
	storage.planets_lib.cargo_pod_canceled_whisper_ticks = storage.planets_lib.cargo_pod_canceled_whisper_ticks or {}

	storage.planets_lib.whitelisted_names_all_planets = storage.planets_lib.whitelisted_names_all_planets or {}
	storage.planets_lib.whitelisted_types_all_planets = storage.planets_lib.whitelisted_types_all_planets or {}

	storage.planets_lib.whitelisted_names = storage.planets_lib.whitelisted_names or {}
	storage.planets_lib.whitelisted_types = storage.planets_lib.whitelisted_types or {}
end

script.on_init(function()
	init_storage()
end)
script.on_configuration_changed(function()
	init_storage()
end)

local cargo_drops_techs = {}
for _,planet in pairs(prototypes.space_location) do
	cargo_drops_techs[planet.name] = "planetslib-" .. planet.name .. "-cargo-drops"
end
script.on_nth_tick(20, function()
	for _, force in pairs(game.forces) do
		for _, platform in pairs(force.platforms) do
			if platform and platform.valid and platform.surface and platform.surface.valid then
				local planet_name = nil
				if platform.space_location and platform.space_location.valid and platform.space_location.name then
					planet_name = platform.space_location.name
				end

				if planet_name then
					local cargo_drops_tech = force.technologies[cargo_drops_techs[planet_name]] --force.technologies["planetslib-" .. planet_name .. "-cargo-drops"]

					if cargo_drops_tech and not cargo_drops_tech.researched then
						local has_nothing_effect = false
						for _, effect in pairs(cargo_drops_tech.prototype.effects) do
							if effect.type == "nothing" then
								has_nothing_effect = true
								break
							end
						end

						if has_nothing_effect then
							local cargo_pods = platform.surface.find_entities_filtered({ type = "cargo-pod" })

							Public.examine_cargo_pods(platform, cargo_pods, planet_name)
						end
					end
				end
			end
		end
	end
end)

function Public.examine_cargo_pods(platform, cargo_pods, planet_name)
	local whitelisted_names_all_planets = storage.planets_lib.whitelisted_names_all_planets
	local whitelisted_names = storage.planets_lib.whitelisted_names
	local whitelisted_types_all_planets = storage.planets_lib.whitelisted_types_all_planets
	local whitelisted_types = storage.planets_lib.whitelisted_types

	for _, pod in pairs(cargo_pods) do
		if pod and pod.valid and not storage.planets_lib.cargo_pods_seen_on_platforms[pod.unit_number] then
			local pod_contents = pod.get_inventory(defines.inventory.cargo_unit).get_contents()

			local has_only_allowed_cargo = true

			for _, item in pairs(pod_contents) do
				if
					not whitelisted_names_all_planets[item.name]
					and not (whitelisted_names[planet_name] and whitelisted_names[planet_name][item.name])
					and not (
						prototypes.entity[item.name]
						and (
							whitelisted_types_all_planets[prototypes.entity[item.name].type]
							or (
								whitelisted_types[planet_name]
								and whitelisted_types[planet_name][prototypes.entity[item.name].type]
							)
						)
					)
				then
					has_only_allowed_cargo = false
					break
				end
			end

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
				Public.destroy_pod_on_platform(pod, platform, planet_name)
			end
		end
	end
end

function Public.destroy_pod_on_platform(pod, platform, planet_name)
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

	for _, player in pairs(game.connected_players) do
		if
			player.valid
			and player.surface
			and player.surface.valid
			and player.surface.index == platform.surface.index
		then
			local whisper_hash = platform.index .. "-" .. player.name

			local last_whisper_tick = storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash]

			if (not last_whisper_tick) or (game.tick - last_whisper_tick >= 60 * 10) then
				player.print({
					"planetslib.cargo-pod-canceled",
					"[space-platform=" .. platform.index .. "]",
					"[technology=" .. "planetslib-" .. planet_name .. "-cargo-drops" .. "]",
				}, { color = warn_color })

				storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash] = game.tick
			end
		end
	end

	local pod_unit_number = pod.unit_number

	pod.destroy()

	storage.planets_lib.cargo_pods_seen_on_platforms[pod_unit_number] = nil
end

remote.add_interface("planetslib", {
	add_to_cargo_drop_item_name_whitelist = function(name, planet_name)
		if type(name) ~= "string" then
			error("name must be a string")
		end

		if planet_name then
			if not storage.planets_lib.whitelisted_names[planet_name] then
				storage.planets_lib.whitelisted_names[planet_name] = {}
			end
			storage.planets_lib.whitelisted_names[planet_name][name] = true
		else
			storage.planets_lib.whitelisted_names_all_planets[name] = true
		end
	end,
	remove_from_cargo_drop_item_name_whitelist = function(name, planet_name)
		if type(name) ~= "string" then
			error("name must be a string")
		end
		if planet_name then
			if not storage.planets_lib.whitelisted_names[planet_name] then
				storage.planets_lib.whitelisted_names[planet_name] = {}
			end
			storage.planets_lib.whitelisted_names[planet_name][name] = nil
		else
			storage.planets_lib.whitelisted_names_all_planets[name] = nil
		end
	end,
	add_to_cargo_drop_item_type_whitelist = function(type_name, planet_name)
		if type(type_name) ~= "string" then
			error("type_name must be a string")
		end
		if planet_name then
			if not storage.planets_lib.whitelisted_types[planet_name] then
				storage.planets_lib.whitelisted_types[planet_name] = {}
			end
			storage.planets_lib.whitelisted_types[planet_name][type_name] = true
		else
			storage.planets_lib.whitelisted_types_all_planets[type_name] = true
		end
	end,
	remove_from_cargo_drop_item_type_whitelist = function(type_name, planet_name)
		if type(type_name) ~= "string" then
			error("type_name must be a string")
		end
		if planet_name then
			if not storage.planets_lib.whitelisted_types[planet_name] then
				storage.planets_lib.whitelisted_types[planet_name] = {}
			end
			storage.planets_lib.whitelisted_types[planet_name][type_name] = nil
		else
			storage.planets_lib.whitelisted_types_all_planets[type_name] = nil
		end
	end,
})

return Public
