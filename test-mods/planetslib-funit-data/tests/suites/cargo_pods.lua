-- Cargo-drop technologies, the cargo-drop whitelist and the cargo-pod
-- examination logic (scripts/cargo-pods.lua + lib/technology.lua).
--
-- The data-stage `technology` fixture creates the cargo-drop technology
-- prototype `planetslib-funit-cargo-planet-cargo-drops` (recorded as TECH-8)
-- and the `mod_data` fixture installs the cargo-drop whitelists. This suite
-- asserts those prototypes and drives the runtime internals through the
-- `planetslib_funit` seam (`pod_contents_is_allowed`, `examine_cargo_pods`).
--
-- Cargo pods, space platforms and the deprecated `planetslib` remote interface
-- only exist with Space Age. In a base-only game the suite asserts that the
-- cargo seams are inert instead of pretending the Space-Age-only code ran; the
-- technology and mod-data checks still run. `remote.call` cannot carry a
-- function, so the warning tests call the module loaded into this Lua state
-- with a fake player table (see `cargo_runtime` below); the seam is still
-- exercised for the paths that reject before calling `player.print`.

-- `require` is only allowed while the scenario's control.lua is parsed, not
-- from inside an on_tick test callback.
local support = require("__planetslib-funit-data__.tests.suites.support")

-- Factorio's `remote.call` copies its arguments and rejects functions, so the
-- `warn_cargo_pod_canceled` seam cannot receive a fake player with a `print`
-- method. Load scripts/cargo-pods.lua into this Lua state instead, with
-- `remote` shadowed so its deprecated interface registration is a no-op. The
-- module (and the storage it shares with PlanetsLib's own VM) is then callable
-- directly, which makes the localised message and the throttle observable.
local cargo_runtime
if script.active_mods["space-age"] then
	local real_remote = _G.remote
	_G.remote = { add_interface = function() end }
	local loaded, module = pcall(require, "__PlanetsLib__.scripts.cargo-pods")
	_G.remote = real_remote
	if loaded then
		cargo_runtime = module
	end
end

local function has_space_age()
	return script.active_mods["space-age"] ~= nil
end

-- The cargo-pod entity type and the platform hub only exist with Space Age.
local function has_cargo_prototypes()
	return prototypes.entity["cargo-pod"] ~= nil and prototypes.entity["space-platform-hub"] ~= nil
end

local function seam(name)
	local iface = remote.interfaces["planetslib_funit"]
	return iface ~= nil and iface[name] ~= nil
end

local function seam_call(name, ...)
	return remote.call("planetslib_funit", name, ...)
end

-- The deprecated cargo-drop whitelist interface (registered by
-- scripts/cargo-pods.lua as "planetslib", only loaded with Space Age).
local function legacy_interface()
	return remote.interfaces["planetslib"]
end

-- Assert that the cargo-pod seams are registered but inert. This is the real
-- base-game expectation: control.lua registers the interface unconditionally,
-- while scripts/cargo-pods.lua (and therefore every implementation behind it)
-- is only required with Space Age.
local function assert_cargo_seams_inert(runner, label)
	runner.assert(seam("pod_contents_is_allowed"), "PlanetsLib did not expose the pod_contents_is_allowed test seam")
	runner.assert(seam("examine_cargo_pods"), "PlanetsLib did not expose the examine_cargo_pods test seam")
	runner.assert(seam("warn_cargo_pod_canceled"), "PlanetsLib did not expose the warn_cargo_pod_canceled test seam")
	runner.assert(
		seam_call("pod_contents_is_allowed", {}, "nauvis") == nil,
		label .. ": without Space Age pod_contents_is_allowed must be inert (return nil)"
	)
	runner.assert(
		seam_call("examine_cargo_pods", nil, "nauvis") == nil,
		label .. ": without Space Age examine_cargo_pods must be inert (return nil)"
	)
	runner.assert(
		seam_call("warn_cargo_pod_canceled", nil, nil, "nauvis") == nil,
		label .. ": without Space Age warn_cargo_pod_canceled must be inert (return nil)"
	)
end

-- Guard for tests that need the cargo-pod runtime. Returns false (after
-- asserting the real base-game expectation) when Space Age is absent.
local function cargo_runtime_available(runner, label)
	if not has_space_age() then
		assert_cargo_seams_inert(runner, label)
		runner.log(label .. " limitation: cargo pods and space platforms require Space Age; asserted the seams are inert")
		return false
	end
	runner.assert(
		has_cargo_prototypes(),
		"Space Age is active but the cargo-pod/space-platform-hub prototypes are missing"
	)
	runner.assert(seam("examine_cargo_pods"), "PlanetsLib did not expose the examine_cargo_pods test seam")
	return true
end

-- A fake player accepted by warn_player_of_canceled_pod. The helper only reads
-- `valid`, `name`, `surface.valid`, `surface.index` and calls `print`. Factorio
-- binds LuaObject methods, and the implementation calls `player.print(message,
-- options)` with a dot, so the fake table uses that two-argument signature.
local function make_fake_cargo_player(name, surface_index, prints)
	return {
		valid = true,
		name = name,
		surface = { valid = true, index = surface_index },
		print = function(message, options)
			prints[#prints + 1] = { message = message, options = options }
		end,
	}
end

local function pod_contents(item_name, count)
	return { { name = item_name, count = count or 1 } }
end

local function whitelists()
	return prototypes.mod_data.Planetslib.data.planet_cargo_drop_whitelists
end

-- == Platform / cargo-pod helpers (Space Age only) == -- --

local platform_counter = 0

-- Create a throwaway space platform (with a hub) orbiting nauvis. Returns nil
-- if the platform could not be created (Space Age absent, no starter pack, ...).
local function create_test_platform()
	if not (has_space_age() and has_cargo_prototypes()) then
		return nil
	end

	local force = game.forces.player
	if not force then
		return nil
	end

	platform_counter = platform_counter + 1
	-- Factorio LuaObject methods are bound (called with a dot), so wrap them in
	-- closures instead of passing the object as a pcall argument.
	local ok, platform = pcall(function()
		return force.create_space_platform({
			name = "funit-cargo-platform-" .. tostring(platform_counter),
			planet = "nauvis",
			starter_pack = "space-platform-starter-pack",
		})
	end)
	if not ok or not platform or not platform.valid then
		return nil
	end

	if not platform.hub then
		pcall(function()
			platform.apply_starter_pack(true)
		end)
	end

	if not (platform.surface and platform.surface.valid and platform.hub and platform.hub.valid) then
		pcall(function()
			platform.destroy()
		end)
		return nil
	end

	return platform
end

local function destroy_surface_cargo_pods(surface)
	if not (surface and surface.valid) then
		return
	end
	local ok, pods = pcall(function()
		return surface.find_entities_filtered({ type = "cargo-pod" })
	end)
	if not ok then
		return
	end
	for _, pod in pairs(pods) do
		if pod and pod.valid then
			pcall(function()
				pod.destroy()
			end)
		end
	end
end

-- Clean up a platform and everything created on it, even on failure.
local function destroy_test_platform(platform)
	if not (platform and platform.valid) then
		return
	end
	destroy_surface_cargo_pods(platform.surface)
	pcall(function()
		platform.destroy()
	end)
end

-- Create a platform for a test and record a clear limitation if the headless
-- environment refuses to create one. Returns nil in that case (the test must
-- then return after this helper's capability assertion).
local function test_platform_or_limitation(runner, label)
	local platform = create_test_platform()
	if not platform then
		runner.log(label .. " limitation: could not create a space platform in this environment")
		runner.assert(
			has_cargo_prototypes() and seam("examine_cargo_pods"),
			label .. ": the cargo-pod/space-platform capabilities are missing"
		)
	end
	return platform
end

-- Setting the destination makes the pod launch towards nauvis; the pod is
-- still on the platform surface during the ascent animation, which is when
-- examine_cargo_pods inspects it.
local function set_pod_destination_towards_nauvis(pod)
	local surface = game.surfaces["nauvis"]
	if not surface then
		return false
	end
	local ok = pcall(function()
		pod.cargo_pod_destination = { type = defines.cargo_destination.surface, surface = surface }
	end)
	return ok
end

local function add_cargo(pod, item_name, count)
	local ok, inventory = pcall(function()
		return pod.get_inventory(defines.inventory.cargo_unit)
	end)
	if not ok or not inventory then
		return false
	end
	inventory.insert({ name = item_name, count = count })
	return true
end

local function hubs_near(surface, position)
	return surface.find_entities_filtered({
		name = { "space-platform-hub", "cargo-bay" },
		position = position,
		radius = 4,
	})
end

return function(runner)
	runner.test("CARGO-1 cargo-drop technology per space location with a nothing effect", function()
		support.assert_entry(runner, "technology", "TECH-8")

		local name = "planetslib-funit-cargo-planet-cargo-drops"
		local prototype = prototypes.technology[name]
		runner.assert(prototype, "the cargo-drop technology prototype '" .. name .. "' is missing")

		-- The runtime looks the technology up as "planetslib-<space-location>-cargo-drops"
		-- (scripts/cargo-pods.lua builds that map from prototypes.space_location).
		runner.assert(
			prototype.name == "planetslib-" .. "funit-cargo-planet" .. "-cargo-drops",
			"the cargo-drop technology name does not follow the per-space-location convention"
		)

		runner.assert(#prototype.effects == 1, "the cargo-drop technology must have exactly one effect")
		runner.assert(prototype.effects[1].type == "nothing", "the cargo-drop effect must be a `nothing` effect")
		runner.assert(
			prototype.effects[1].effect_description[2] == "[space-location=funit-cargo-planet]",
			"the cargo-drop effect must reference the space location"
		)

		-- The 4-icon layout is data-stage only; the technology fixture TECH-8
		-- asserts it. Runtime LuaTechnologyPrototype doesn't expose `icons`.
	end)

	runner.test("CARGO-2a examine_cargo_pods is a no-op when there are no pods", function()
		if not cargo_runtime_available(runner, "CARGO-2a") then
			return
		end

		local platform = test_platform_or_limitation(runner, "CARGO-2a")
		if not platform then
			return
		end

		local ok, err = pcall(function()
			local surface = platform.surface
			destroy_surface_cargo_pods(surface)
			runner.assert(
				#surface.find_entities_filtered({ type = "cargo-pod" }) == 0,
				"fixture error: the platform surface still has cargo pods"
			)
			-- Must simply return without error.
			seam_call("examine_cargo_pods", platform, "nauvis")
		end)
		destroy_test_platform(platform)
		if not ok then
			error(err, 0)
		end
	end)

	runner.test("CARGO-2 disallowed cargo pod is destroyed and its cargo goes to the hub", function()
		if not cargo_runtime_available(runner, "CARGO-2") then
			return
		end

		local platform = test_platform_or_limitation(runner, "CARGO-2")
		if not platform then
			return
		end

		local ok, err = pcall(function()
			local hub = platform.hub
			local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
			runner.assert(hub_inventory, "the platform hub has no hub_main inventory")

			local pod = hub.create_cargo_pod()
			runner.assert(pod and pod.valid, "could not create a cargo pod from the hub")
			runner.assert(set_pod_destination_towards_nauvis(pod), "could not set the cargo pod destination")

			-- iron-plate is only whitelisted for funit-md-1, not globally.
			runner.assert(add_cargo(pod, "iron-plate", 5), "could not insert cargo into the pod")

			local before = hub_inventory.get_item_count("iron-plate")
			seam_call("examine_cargo_pods", platform, "nauvis")

			runner.assert(not pod.valid, "a disallowed cargo pod must be destroyed")
			runner.assert(
				hub_inventory.get_item_count("iron-plate") == before + 5,
				"the destroyed pod's cargo must be transferred to the hub"
			)
		end)
		destroy_test_platform(platform)
		if not ok then
			error(err, 0)
		end
	end)

	runner.test("CARGO-2b allowed cargo pod is not destroyed", function()
		if not cargo_runtime_available(runner, "CARGO-2b") then
			return
		end

		local platform = test_platform_or_limitation(runner, "CARGO-2b")
		if not platform then
			return
		end

		local ok, err = pcall(function()
			local hub = platform.hub
			local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
			runner.assert(hub_inventory, "the platform hub has no hub_main inventory")

			local pod = hub.create_cargo_pod()
			runner.assert(pod and pod.valid, "could not create a cargo pod from the hub")
			runner.assert(set_pod_destination_towards_nauvis(pod), "could not set the cargo pod destination")

			-- copper-plate is whitelisted globally by the mod_data fixture.
			runner.assert(add_cargo(pod, "copper-plate", 5), "could not insert cargo into the pod")

			local before = hub_inventory.get_item_count("copper-plate")
			seam_call("examine_cargo_pods", platform, "nauvis")

			runner.assert(pod.valid, "an allowed cargo pod must not be destroyed")
			runner.assert(
				hub_inventory.get_item_count("copper-plate") == before,
				"cargo must not be transferred for an allowed pod"
			)
		end)
		destroy_test_platform(platform)
		if not ok then
			error(err, 0)
		end
	end)

	runner.test("CARGO-2c canceled-pod warning is printed once and throttled", function()
		if not has_space_age() then
			runner.assert(cargo_runtime == nil, "scripts/cargo-pods.lua must not be loaded without Space Age")
			assert_cargo_seams_inert(runner, "CARGO-2c")
			runner.log("CARGO-2c limitation: cargo-pod warnings require Space Age; asserted the seams are inert")
			return
		end

		runner.assert(seam("warn_cargo_pod_canceled"), "PlanetsLib did not expose the warn_cargo_pod_canceled test seam")
		runner.assert(
			cargo_runtime and type(cargo_runtime.warn_player_of_canceled_pod) == "function",
			"scripts/cargo-pods.lua did not expose warn_player_of_canceled_pod for this test"
		)

		-- warn_player_of_canceled_pod only compares surface indices and calls
		-- player.print, so any valid surface works. A fake platform keeps the
		-- whisper hash unique without creating a platform just for this test.
		local surface = game.surfaces["nauvis"]
		runner.assert(surface and surface.valid, "the nauvis surface is missing")
		local platform = { index = 987654321, surface = surface }
		runner.assert(
			game.tick < 60 * 10,
			"CARGO-2c must run within the first 10 minutes so the throttle window is meaningful"
		)

		local prints = {}
		local player = make_fake_cargo_player("funit-cargo-player", surface.index, prints)
		local whisper_hash = platform.index .. "-" .. player.name

		-- Make the test independent of earlier tests / real join events.
		cargo_runtime.init_storage()
		storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash] = nil

		local first = cargo_runtime.warn_player_of_canceled_pod(player, platform, "nauvis")
		runner.assert(first == true, "the first canceled-pod warning must be printed")
		runner.assert(#prints == 1, "expected exactly one player.print, got " .. #prints)

		local message = prints[1].message
		runner.assert(type(message) == "table", "the warning must be a localised string table")
		runner.assert(
			message[1] == "planetslib.cargo-pod-canceled",
			"the warning did not use the planetslib.cargo-pod-canceled key"
		)
		runner.assert(
			message[2] == "[space-platform=" .. platform.index .. "]",
			"the warning is missing the platform parameter"
		)
		runner.assert(
			message[3] == "[technology=planetslib-nauvis-cargo-drops]",
			"the warning is missing the cargo-drop technology parameter"
		)
		runner.assert(
			type(prints[1].options) == "table" and prints[1].options.color ~= nil,
			"the warning must be printed with the warn colour"
		)
		runner.assert(
			storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash] == game.tick,
			"the warning must record the current tick for the throttle"
		)

		local second = cargo_runtime.warn_player_of_canceled_pod(player, platform, "nauvis")
		runner.assert(second == false, "a second warning within 10 minutes must be throttled")
		runner.assert(#prints == 1, "the throttled call must not print again")

		-- The throttle is per player, not global.
		local other_prints = {}
		local other_player = make_fake_cargo_player("funit-cargo-player-2", surface.index, other_prints)
		local other = cargo_runtime.warn_player_of_canceled_pod(other_player, platform, "nauvis")
		runner.assert(other == true, "a different player on the same platform must still be warned")
		runner.assert(#other_prints == 1, "the different player's warning was not printed")

		-- After the 10-minute window the same player is warned again.
		storage.planets_lib.cargo_pod_canceled_whisper_ticks[whisper_hash] = game.tick - 60 * 10
		local rewarn = cargo_runtime.warn_player_of_canceled_pod(player, platform, "nauvis")
		runner.assert(rewarn == true, "a warning after the 10-minute throttle window must be printed again")
		runner.assert(#prints == 2, "the re-warn should add exactly one print, got " .. #prints)

		-- A player on another surface must not be warned (and must not print).
		-- This path is also exercised through the seam: the fake player has no
		-- `print` method, so reaching player.print would raise.
		local off_prints = {}
		local off_player = make_fake_cargo_player("funit-cargo-player-off", surface.index + 10000, off_prints)
		local off = cargo_runtime.warn_player_of_canceled_pod(off_player, platform, "nauvis")
		runner.assert(off == false, "a player on a different surface must not be warned")
		runner.assert(#off_prints == 0, "the off-platform player must not receive a warning")

		local seam_off = seam_call("warn_cargo_pod_canceled", {
			valid = true,
			name = "funit-seam-off",
			surface = { valid = true, index = surface.index + 10000 },
		}, platform, "nauvis")
		runner.assert(seam_off == false, "the seam must reach the real implementation and reject an off-surface player")

		-- An invalid player is rejected before any print is attempted.
		local seam_invalid = seam_call("warn_cargo_pod_canceled", { valid = false }, platform, "nauvis")
		runner.assert(seam_invalid == false, "the seam must reject an invalid player (false, not nil/inert)")
	end)

	runner.test("CARGO-3 whitelist variants", function()
		if not has_space_age() then
			-- Without Space Age, scripts/cargo-pods.lua is not loaded and the
			-- seam returns nil. The mod-data whitelist helpers still ran at the
			-- data stage, so assert those and the inert seam.
			support.assert_entry(runner, "mod_data", "MD-1")
			local maps = whitelists()
			runner.assert(maps, "the cargo-drop whitelist mod-data is missing")
			runner.assert(maps.all.item_names["copper-plate"], "the global item whitelist is missing")
			runner.assert(maps.all.entity_types["inserter"], "the global entity-type whitelist is missing")
			runner.assert(
				maps["funit-md-1"] and maps["funit-md-1"].item_names["iron-plate"],
				"the per-planet item whitelist is missing"
			)
			runner.assert(
				maps["funit-md-1"] and maps["funit-md-1"].entity_types["container"],
				"the per-planet entity-type whitelist is missing"
			)
			runner.assert(
				seam_call("pod_contents_is_allowed", {}, "nauvis") == nil,
				"without Space Age pod_contents_is_allowed must be inert (return nil)"
			)
			runner.log(
				"CARGO-3 limitation: pod_contents_is_allowed requires Space Age; asserted the mod-data whitelist instead"
			)
			return
		end
		runner.assert(seam("pod_contents_is_allowed"), "PlanetsLib did not expose the pod_contents_is_allowed test seam")

		local function allowed(contents, planet_name)
			return seam_call("pod_contents_is_allowed", contents, planet_name) == true
		end

		-- Global item name and global entity type (mod_data fixture).
		runner.assert(allowed(pod_contents("copper-plate"), "nauvis"), "a globally whitelisted item must be allowed")
		runner.assert(allowed(pod_contents("inserter"), "nauvis"), "a globally whitelisted entity type must be allowed")

		-- Per-planet item name and entity type (mod_data fixture).
		runner.assert(allowed(pod_contents("iron-plate"), "funit-md-1"), "a per-planet whitelisted item must be allowed")
		runner.assert(allowed(pod_contents("iron-chest"), "funit-md-1"), "a per-planet whitelisted entity type must be allowed")

		-- A planet without a matching whitelist must reject them.
		runner.assert(
			not allowed(pod_contents("iron-plate"), "nauvis"),
			"an item only whitelisted for another planet must not be allowed"
		)
		runner.assert(
			not allowed(pod_contents("iron-chest"), "nauvis"),
			"an entity type only whitelisted for another planet must not be allowed"
		)

		-- Mixed contents fail the whole pod; all-allowed and empty contents pass.
		runner.assert(
			not allowed({ { name = "copper-plate", count = 1 }, { name = "iron-plate", count = 1 } }, "nauvis"),
			"a pod with any disallowed entry must be rejected"
		)
		runner.assert(
			allowed({ { name = "copper-plate", count = 1 }, { name = "inserter", count = 1 } }, "nauvis"),
			"a pod with only allowed contents must be accepted"
		)
		runner.assert(allowed({}, "nauvis"), "an empty pod must be allowed")

		-- Legacy global item whitelist still works (see CARGO-5 for the type
		-- and per-planet legacy forms).
		local iface = legacy_interface()
		runner.assert(iface, "the deprecated `planetslib` interface is missing with Space Age")
		runner.assert(
			iface["add_to_cargo_drop_item_name_whitelist"],
			"the deprecated `planetslib` add-item interface is missing with Space Age"
		)
		local item = "copper-cable"
		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item)
		runner.assert(not allowed(pod_contents(item), "nauvis"), "the legacy whitelist entry leaked in")
		remote.call("planetslib", "add_to_cargo_drop_item_name_whitelist", item)
		runner.assert(allowed(pod_contents(item), "nauvis"), "the legacy global item whitelist must allow the item")
		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item)
		runner.assert(not allowed(pod_contents(item), "nauvis"), "the legacy global item whitelist removal must deny it")
	end)

	runner.test("CARGO-4 on-platform detection: a disallowed pod far from a hub is not destroyed", function()
		if not cargo_runtime_available(runner, "CARGO-4") then
			return
		end

		local platform = test_platform_or_limitation(runner, "CARGO-4")
		if not platform then
			return
		end

		local ok, err = pcall(function()
			local hub = platform.hub
			local surface = platform.surface
			local far_position = { x = hub.position.x + 60, y = hub.position.y + 60 }

			-- Prefer a direct create_entity far from the hub; fall back to
			-- teleporting a hub-created pod. If neither works, skip (the
			-- detection logic is still covered by CARGO-2/2b near the hub).
			local pod
			local created = pcall(function()
				pod = surface.create_entity({ name = "cargo-pod", position = far_position, force = game.forces.player })
			end)
			if not (created and pod and pod.valid) then
				pod = nil
				local ok_hub_pod, hub_pod = pcall(function()
					return hub.create_cargo_pod()
				end)
				if ok_hub_pod and hub_pod and hub_pod.valid then
					pcall(function()
						hub_pod.teleport(far_position)
					end)
					if hub_pod.valid and #hubs_near(surface, hub_pod.position) == 0 then
						pod = hub_pod
					end
				end
			end

			if not (pod and pod.valid) then
				runner.log("CARGO-4 limitation: could not place/position a cargo pod far from the platform hub")
				runner.assert(seam("examine_cargo_pods"), "PlanetsLib did not expose the examine_cargo_pods test seam")
				return
			end

			runner.assert(
				#hubs_near(surface, pod.position) == 0,
				"fixture error: a hub is still within the 4-tile detection radius of the far pod"
			)
			runner.assert(set_pod_destination_towards_nauvis(pod), "could not set the cargo pod destination")
			runner.assert(add_cargo(pod, "iron-plate", 5), "could not insert cargo into the pod")

			seam_call("examine_cargo_pods", platform, "nauvis")

			runner.assert(
				pod.valid,
				"a disallowed pod that was not launched from a platform must not be destroyed"
			)
			if pod.valid then
				pcall(function()
					pod.destroy()
				end)
			end
		end)
		destroy_test_platform(platform)
		if not ok then
			error(err, 0)
		end
	end)

	runner.test("CARGO-5a deprecated interface: global add/remove", function()
		if not has_space_age() then
			-- Without Space Age there is no deprecated interface; assert that,
			-- and the supported mod-data path instead.
			runner.assert(
				legacy_interface() == nil,
				"the deprecated `planetslib` interface must not exist without Space Age"
			)
			local maps = whitelists()
			runner.assert(maps, "the cargo-drop whitelist mod-data is missing")
			runner.assert(maps.all.item_names["copper-plate"], "the global mod-data item whitelist is missing")
			runner.assert(
				maps["funit-md-1"] and maps["funit-md-1"].item_names["iron-plate"],
				"the per-planet mod-data item whitelist is missing"
			)
			runner.assert(
				seam_call("pod_contents_is_allowed", {}, "nauvis") == nil,
				"without Space Age pod_contents_is_allowed must be inert (return nil)"
			)
			runner.log(
				"CARGO-5a limitation: the deprecated `planetslib` interface requires Space Age; asserted the mod-data path"
			)
			return
		end

		local iface = legacy_interface()
		runner.assert(iface, "the deprecated `planetslib` interface is missing with Space Age")
		runner.assert(seam("pod_contents_is_allowed"), "PlanetsLib did not expose the pod_contents_is_allowed test seam")

		runner.assert(iface["add_to_cargo_drop_item_name_whitelist"], "the add-item interface is missing")
		runner.assert(iface["remove_from_cargo_drop_item_name_whitelist"], "the remove-item interface is missing")
		runner.assert(iface["add_to_cargo_drop_item_type_whitelist"], "the add-type interface is missing")
		runner.assert(iface["remove_from_cargo_drop_item_type_whitelist"], "the remove-type interface is missing")

		local function allowed(contents, planet_name)
			return seam_call("pod_contents_is_allowed", contents, planet_name) == true
		end

		local item = "iron-gear-wheel"
		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item)
		runner.assert(not allowed(pod_contents(item), "nauvis"), "the item must start unwhitelisted")
		remote.call("planetslib", "add_to_cargo_drop_item_name_whitelist", item)
		runner.assert(allowed(pod_contents(item), "nauvis"), "add must allow the item")
		remote.call("planetslib", "add_to_cargo_drop_item_name_whitelist", item)
		runner.assert(allowed(pod_contents(item), "nauvis"), "adding twice must be idempotent")
		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item)
		runner.assert(not allowed(pod_contents(item), "nauvis"), "remove must deny the item")

		-- Type names must be strings.
		runner.assert(
			not pcall(remote.call, "planetslib", "add_to_cargo_drop_item_name_whitelist", 5),
			"a non-string item name must raise"
		)
		runner.assert(
			not pcall(remote.call, "planetslib", "add_to_cargo_drop_item_type_whitelist", 5),
			"a non-string type name must raise"
		)
	end)

	runner.test("CARGO-5b deprecated interface: per-planet item add/remove", function()
		if not has_space_age() then
			runner.assert(
				legacy_interface() == nil,
				"the deprecated `planetslib` interface must not exist without Space Age"
			)
			runner.assert(
				seam_call("pod_contents_is_allowed", {}, "nauvis") == nil,
				"without Space Age pod_contents_is_allowed must be inert (return nil)"
			)
			runner.log("CARGO-5b limitation: the deprecated `planetslib` interface requires Space Age")
			return
		end
		local iface = legacy_interface()
		runner.assert(iface, "the deprecated `planetslib` interface is missing with Space Age")
		runner.assert(seam("pod_contents_is_allowed"), "PlanetsLib did not expose the pod_contents_is_allowed test seam")

		local function allowed(contents, planet_name)
			return seam_call("pod_contents_is_allowed", contents, planet_name) == true
		end

		local item = "iron-gear-wheel"
		local planet = "funit-md-1"
		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item, planet)
		remote.call("planetslib", "add_to_cargo_drop_item_name_whitelist", item, planet)
		local was_allowed = allowed(pod_contents(item), planet)
		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item, planet)
		runner.assert(not allowed(pod_contents(item), planet), "removing a per-planet entry must deny it")

		-- A per-planet add must allow the item for that planet.
		runner.assert(
			was_allowed,
			"a per-planet legacy item whitelist entry must allow the item (scripts/cargo-pods.lua)"
		)
	end)

	runner.test("CARGO-5c deprecated interface: per-planet entity-type add/remove", function()
		if not has_space_age() then
			runner.assert(
				legacy_interface() == nil,
				"the deprecated `planetslib` interface must not exist without Space Age"
			)
			runner.assert(
				seam_call("pod_contents_is_allowed", {}, "nauvis") == nil,
				"without Space Age pod_contents_is_allowed must be inert (return nil)"
			)
			runner.log("CARGO-5c limitation: the deprecated `planetslib` interface requires Space Age")
			return
		end
		local iface = legacy_interface()
		runner.assert(iface, "the deprecated `planetslib` interface is missing with Space Age")
		runner.assert(seam("pod_contents_is_allowed"), "PlanetsLib did not expose the pod_contents_is_allowed test seam")

		local function allowed(contents, planet_name)
			return seam_call("pod_contents_is_allowed", contents, planet_name) == true
		end

		local entity_type = "furnace"
		local planet = "funit-md-1"
		remote.call("planetslib", "remove_from_cargo_drop_item_type_whitelist", entity_type, planet)
		remote.call("planetslib", "add_to_cargo_drop_item_type_whitelist", entity_type, planet)
		local was_allowed = allowed(pod_contents("stone-furnace"), planet)
		remote.call("planetslib", "remove_from_cargo_drop_item_type_whitelist", entity_type, planet)
		runner.assert(not allowed(pod_contents("stone-furnace"), planet), "removing a per-planet type must deny it")

		-- A per-planet type add must allow entities of that type on that planet.
		runner.assert(
			was_allowed,
			"a per-planet legacy entity-type whitelist entry must allow the entity (scripts/cargo-pods.lua)"
		)
	end)

	runner.test("CARGO-6 init_storage is idempotent across configuration changes", function()
		runner.assert(seam("on_configuration_changed"), "PlanetsLib did not expose the on_configuration_changed test seam")

		if not has_space_age() then
			-- Without Space Age there is no cargo-pod storage seam, but the
			-- control-stage on_configuration_changed seam still exists. Reach
			-- init_storage through it twice and assert the mod-data whitelist is
			-- untouched.
			runner.assert(
				legacy_interface() == nil,
				"the deprecated `planetslib` interface must not exist without Space Age"
			)
			local ok, err = pcall(function()
				seam_call("on_configuration_changed", { mod_changes = {} })
				seam_call("on_configuration_changed", { mod_changes = {} })
			end)
			runner.assert(ok, "calling on_configuration_changed failed: " .. tostring(err))
			local maps = whitelists()
			runner.assert(maps and maps.all.item_names["copper-plate"], "the mod-data whitelist is missing")
			runner.assert(
				seam_call("pod_contents_is_allowed", {}, "nauvis") == nil,
				"without Space Age the cargo-pod storage seam must be inert (return nil)"
			)
			runner.log(
				"CARGO-6 limitation: no cargo-pod storage exists without Space Age; init_storage ran twice via on_configuration_changed"
			)
			return
		end

		runner.assert(seam("pod_contents_is_allowed"), "PlanetsLib did not expose the pod_contents_is_allowed test seam")
		local iface = legacy_interface()
		runner.assert(iface, "the deprecated `planetslib` interface is missing with Space Age")
		runner.assert(iface["add_to_cargo_drop_item_name_whitelist"], "the add-item interface is missing")

		local item = "copper-cable"
		local function allowed()
			return seam_call("pod_contents_is_allowed", pod_contents(item), "nauvis") == true
		end

		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item)
		runner.assert(not allowed(), "the item must start unwhitelisted")
		remote.call("planetslib", "add_to_cargo_drop_item_name_whitelist", item)
		runner.assert(allowed(), "the item was not whitelisted")

		local ok, err = pcall(function()
			-- control.lua's on_configuration_changed calls
			-- cargo_pods.init_storage(). Running it twice must not clear or
			-- duplicate existing storage (init_storage uses `or {}`).
			seam_call("on_configuration_changed", { mod_changes = {} })
			seam_call("on_configuration_changed", { mod_changes = {} })
			runner.assert(allowed(), "init_storage cleared the legacy whitelist on the first configuration change")
			runner.assert(allowed(), "init_storage is not idempotent across two configuration changes")
			runner.assert(
				seam_call("pod_contents_is_allowed", pod_contents("iron-gear-wheel"), "nauvis") == false,
				"init_storage must not whitelist unrelated items"
			)
		end)

		remote.call("planetslib", "remove_from_cargo_drop_item_name_whitelist", item)
		if not ok then
			error(err, 0)
		end
		runner.assert(not allowed(), "removing the legacy whitelist entry must deny the item")
	end)
end
