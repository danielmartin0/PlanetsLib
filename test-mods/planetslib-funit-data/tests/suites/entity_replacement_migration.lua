-- Entity replacement: migration behavior (ENT-12..ENT-13).
--
-- ENT-12 drives the live rolling-stock upgrade path. ENT-13a/ENT-13b exercise
-- the on_configuration_changed entry point and the silent (raise_built = false)
-- replacement path used by migrations. ENT-13c..ENT-13e drive the real rule
-- migration through the `migrate_entity_replacement_rules` seam with a complete
-- old-rule snapshot, covering re-enabled, disabled and removed rules. ENT-13g
-- and ENT-13h cover stale rule snapshots whose entity prototypes no longer
-- exist after a mod update.

-- `require` is only allowed while the scenario's control.lua is parsed, not
-- from inside an on_tick test callback.
local mock = require("__funit__.mock")
local support = require("__planetslib-funit-data__.tests.suites.support")

local FIXTURE_SUITE = "entity_replacement_data"
local SURFACE_NAME = "nauvis"
local DISABLE_ALL_SETTING = "PlanetsLib-disable-all-entity-replacements"
local AREA_STEP = 80
local AREA_RADIUS = 8
local next_area = 0

local function fixture_entries(runner)
	support.assert_all(runner, FIXTURE_SUITE, { expected = { "ENT-1g", "ENT-2e" } })
	return support.entries(runner, FIXTURE_SUITE)
end

local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = deep_copy(entry)
	end
	return copy
end

local function copy_current_rules(runner)
	local planetslib = prototypes.mod_data["Planetslib"]
	runner.assert(planetslib and planetslib.data, "the PlanetsLib mod-data prototype is missing")
	local rules = planetslib.data.on_entity_placed_on_planet_replacements
	runner.assert(rules, "PlanetsLib has no on_entity_placed_on_planet_replacements table")
	return deep_copy(rules)
end

local function replacements_disabled()
	local setting = settings.startup[DISABLE_ALL_SETTING]
	return setting ~= nil and setting.value == true
end

local function require_seam(runner, name)
	local interface = remote.interfaces["planetslib_funit"]
	runner.assert(interface and interface[name], "PlanetsLib did not expose planetslib_funit." .. name)
	return function(...)
		return remote.call("planetslib_funit", name, ...)
	end
end

local function area_box(center, radius)
	return {
		{ center.x - radius, center.y - radius },
		{ center.x + radius, center.y + radius },
	}
end

local function prepare_area(surface, center, radius)
	surface.request_to_generate_chunks(center, 1)
	surface.force_generate_chunk_requests()

	local tiles = {}
	for x = math.floor(center.x - radius), math.floor(center.x + radius) do
		for y = math.floor(center.y - radius), math.floor(center.y + radius) do
			tiles[#tiles + 1] = { name = "landfill", position = { x = x, y = y } }
		end
	end
	surface.set_tiles(tiles, true, true, true, false)
end

local function clear_area(surface, center, radius)
	for _, entity in pairs(surface.find_entities_filtered({ area = area_box(center, radius) })) do
		if entity.valid and entity.type ~= "character" then
			entity.destroy()
		end
	end
end

local function with_area(runner, body)
	fixture_entries(runner)
	local planet = game.planets[SURFACE_NAME]
	runner.assert(planet and planet.surface, "the nauvis surface is missing")
	local surface = planet.surface

	next_area = next_area + 1
	local center = { x = 8000 + next_area * AREA_STEP, y = 4000 }

	local ok, err = pcall(function()
		prepare_area(surface, center, AREA_RADIUS)
		-- Map generation can leave trees, rocks or cliffs inside the landfill
		-- area; clear them before each test so entity placement is deterministic.
		clear_area(surface, center, AREA_RADIUS)
		body(surface, center)
	end)
	pcall(clear_area, surface, center, AREA_RADIUS + 6)
	if not ok then
		error(err, 0)
	end
end

local function with_migration_area(runner, migrate, body)
	with_area(runner, function(surface, center)
		local ok, err = pcall(body, surface, center)
		-- Restore PlanetsLib's migration baseline even when an assertion fails,
		-- so later suites never inherit this test's synthetic old snapshot.
		pcall(migrate, copy_current_rules(runner))
		if not ok then
			error(err, 0)
		end
	end)
end

local function create_at(surface, name, center)
	local position = surface.find_non_colliding_position(name, center, 6, 0.5)
	if not position then
		return nil, nil
	end
	return surface.create_entity({
		name = name,
		position = position,
		force = game.forces.player,
		create_build_effect_smoke = false,
	}), position
end

local function create_rail(surface, center)
	-- A locomotive is six tiles long, so a single 2-tile rail segment cannot
	-- hold one. Build a short north-south line and return the middle segment.
	-- Rail alignment depends on the rail grid; try a few centre conventions.
	local candidates = {
		{ x = center.x, y = center.y },
		{ x = center.x + 0.5, y = center.y + 0.5 },
		{ x = center.x - 0.5, y = center.y - 0.5 },
		{ x = center.x + 1, y = center.y },
		{ x = center.x, y = center.y + 1 },
	}
	for _, base in ipairs(candidates) do
		local rails = {}
		local complete = true
		for offset = -2, 2 do
			local ok, rail = pcall(function()
				return surface.create_entity({
					name = "straight-rail",
					position = { x = base.x, y = base.y + offset * 2 },
					direction = defines.direction.north,
					force = game.forces.player,
				})
			end)
			if not (ok and rail and rail.valid) then
				log("[funit] rail candidate " .. tostring(base.x) .. "," .. tostring(base.y)
					.. " offset " .. offset .. " failed: " .. tostring(ok and "nil/invalid" or rail))
				complete = false
				break
			end
			rails[#rails + 1] = rail
		end
		if complete then
			return rails[3]
		end
		for _, rail in ipairs(rails) do
			if rail.valid then
				rail.destroy()
			end
		end
	end
	return nil
end

local function find(surface, name, position, radius)
	local entities = surface.find_entities_filtered({
		name = name,
		position = position,
		radius = radius or 1.5,
	})
	return entities[1]
end

return function(runner)
	runner.test("ENT-12 rolling-stock replacement preserves the locomotive state", function()
		local replace_entity = require_seam(runner, "replace_entity")

		with_area(runner, function(surface, center)
			local rail = create_rail(surface, center)
			runner.assert(rail and rail.valid, "could not create a straight rail for the locomotive")

			local ok, locomotive = pcall(function()
				return surface.create_entity({
					name = "locomotive",
					position = rail.position,
					direction = rail.direction,
					force = game.forces.player,
				})
			end)
			runner.assert(ok and locomotive and locomotive.valid, "could not create a locomotive on the test rail")

			local position = locomotive.position
			local orientation = locomotive.orientation
			locomotive.insert({ name = "coal", count = 7 })
			runner.assert(
				locomotive.get_inventory(defines.inventory.fuel).get_item_count("coal") == 7,
				"could not fill the locomotive fuel inventory"
			)
			runner.assert(
				prototypes.entity["locomotive"].fast_replaceable_group
					== prototypes.entity["locomotive-PlanetsLib-nauvis"].fast_replaceable_group,
				"the locomotive variant has a different fast_replaceable_group"
			)
			replace_entity(locomotive, "locomotive-PlanetsLib-nauvis", false)

			local new = find(surface, "locomotive-PlanetsLib-nauvis", position, 2)
			runner.assert(new and new.valid, "the locomotive was not replaced by its nauvis variant")
			runner.assert(not locomotive.valid, "the old locomotive was not removed")
			runner.assert(
				math.abs(new.orientation - orientation) < 1e-3,
				"the replacement locomotive changed orientation"
			)
			runner.assert(new.train ~= nil, "the replacement locomotive is not on a train")
			runner.assert(
				new.get_inventory(defines.inventory.fuel).get_item_count("coal") == 7,
				"the locomotive fuel inventory was not transferred"
			)
		end)
	end)

	runner.test("ENT-13a on_configuration_changed runs without spurious replacements", function()
		local on_configuration_changed = require_seam(runner, "on_configuration_changed")

		with_area(runner, function(surface, center)
			local iron, iron_position = create_at(surface, "iron-chest", center)
			runner.assert(iron and iron.valid, "could not create the already-compliant iron chest")
			local wood, wood_position = create_at(
				surface,
				"wooden-chest",
				{ x = center.x + 4, y = center.y }
			)
			runner.assert(wood and wood.valid, "could not create the wooden chest")

			-- No replacement rule changed between saves, so this must be a no-op.
			local ok, err = pcall(on_configuration_changed, {
				mod_changes = {},
			})
			runner.assert(
				ok,
				"on_configuration_changed raised an error: "
					.. tostring(err)
					.. " (suspected non-string planet key from assign_entity_replacement's planet-table form; "
					.. "see lib/add-entity-replacement.lua:16-23)"
			)

			runner.assert(iron.valid, "the migration replaced an entity that already matched the rule")
			runner.assert(wood.valid, "the migration replaced an entity although no rule changed")
			local wood_again = find(surface, "wooden-chest", wood_position)
			local iron_again = find(surface, "iron-chest", iron_position)
			runner.assert(wood_again and wood_again.unit_number == wood.unit_number,
				"the wooden chest moved or was recreated")
			runner.assert(iron_again and iron_again.unit_number == iron.unit_number,
				"the iron chest moved or was recreated")
		end)
	end)

	runner.test("ENT-13b migration replacements are silent (raise_built = false)", function()
		local replace_entity = require_seam(runner, "replace_entity")

		with_area(runner, function(surface, center)
			local old, position = create_at(surface, "wooden-chest", center)
			runner.assert(old and old.valid, "could not create the source chest")

			local built_events = 0
			-- Do not clobber PlanetsLib's own script_raised_built handler: save it
			-- and restore it after the check.
			local previous_built_handler = script.get_event_handler(defines.events.script_raised_built)
			script.on_event(defines.events.script_raised_built, function()
				built_events = built_events + 1
			end)

			local ok, err = pcall(function()
				replace_entity(old, "iron-chest", false)
			end)

			script.on_event(defines.events.script_raised_built, previous_built_handler)

			runner.assert(ok, "the silent replacement raised: " .. tostring(err))
			local new = find(surface, "iron-chest", position)
			runner.assert(new and new.valid, "the chest was not replaced")
			runner.assert(not old.valid, "the old chest was not removed")
			runner.assert(
				built_events == 0,
				"replace_entity(..., false) raised script_raised_built " .. built_events .. " time(s)"
			)
		end)
	end)

	runner.test("ENT-13c re-enabling a disabled rule migrates existing entities", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")

		with_migration_area(runner, migrate, function(surface, center)
			local current = copy_current_rules(runner)
			local new_rule = current["nauvis"] and current["nauvis"]["wooden-chest"]
			runner.assert(new_rule, "the nauvis wooden-chest rule is missing")
			runner.assert(new_rule.entity == "iron-chest", "the nauvis wooden-chest rule has the wrong target")

			-- Start from a complete snapshot so every other rule is unchanged;
			-- only the target rule was disabled in the old save.
			local old_rules = copy_current_rules(runner)
			local old_rule = old_rules["nauvis"]["wooden-chest"]
			old_rule.enabled = false
			old_rule.entity = "wooden-chest"

			local chest, position = create_at(surface, "wooden-chest", center)
			runner.assert(chest and chest.valid, "could not create the source wooden chest")

			migrate(old_rules)

			if new_rule.enabled == true then
				runner.assert(not chest.valid, "the re-enabled rule did not migrate the wooden chest")
				local replacement = find(surface, "iron-chest", position)
				runner.assert(replacement and replacement.valid, "the wooden chest was not replaced by an iron chest")
			else
				runner.assert(chest.valid, "the global kill switch should leave the wooden chest in place")
				runner.assert(
					find(surface, "iron-chest", position) == nil,
					"the global kill switch still migrated the wooden chest"
				)
			end
		end)
	end)

	runner.test("ENT-13d disabling a rule reverts its replaced entities", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")

		with_migration_area(runner, migrate, function(surface, center)
			local current = copy_current_rules(runner)
			local new_rule = current["nauvis"] and current["nauvis"]["transport-belt"]
			runner.assert(new_rule, "the nauvis transport-belt rule is missing")
			runner.assert(new_rule.entity == "fast-transport-belt", "the transport-belt rule has the wrong target")
			runner.assert(new_rule.enabled == false, "the fixture transport-belt rule should be disabled")

			-- The old save had the same rule enabled.
			local old_rules = copy_current_rules(runner)
			local old_rule = old_rules["nauvis"]["transport-belt"]
			old_rule.enabled = true
			old_rule.entity = "fast-transport-belt"

			local belt, position = create_at(surface, "fast-transport-belt", center)
			runner.assert(belt and belt.valid, "could not create the fast transport belt")

			migrate(old_rules)

			if replacements_disabled() then
				runner.assert(
					belt.valid,
					"the global kill switch should leave the fast transport belt in place"
				)
				runner.assert(
					find(surface, "transport-belt", position) == nil,
					"the global kill switch still reverted the fast transport belt"
				)
			else
				runner.assert(not belt.valid, "the disabled rule did not revert the fast transport belt")
				local reverted = find(surface, "transport-belt", position)
				runner.assert(reverted and reverted.valid, "the fast transport belt was not reverted to a transport belt")
			end
		end)
	end)

	runner.test("ENT-13e removing a rule reverts its replaced entities", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")

		with_migration_area(runner, migrate, function(surface, center)
			local current = copy_current_rules(runner)
			runner.assert(current["nauvis"], "nauvis has no replacement rules")
			runner.assert(
				current["nauvis"]["funit-ent-removed-rule"] == nil,
				"the removal fixture key unexpectedly exists in the live rules"
			)

			-- A rule that was removed between saves exists only in the old
			-- snapshot. The live `prototypes` table is read-only, so the removal
			-- is modelled by an old-only rule rather than mutating the new table.
			local old_rules = copy_current_rules(runner)
			old_rules["nauvis"]["funit-ent-removed-rule"] = {
				old_entity = "fast-transport-belt",
				entity = "express-transport-belt",
				enabled = true,
			}

			local belt, position = create_at(surface, "express-transport-belt", center)
			runner.assert(belt and belt.valid, "could not create the removed rule's variant")

			migrate(old_rules)

			if replacements_disabled() then
				runner.assert(belt.valid, "the global kill switch should leave the express transport belt in place")
				runner.assert(
					find(surface, "fast-transport-belt", position) == nil,
					"the global kill switch still reverted the removed rule's variant"
				)
			else
				runner.assert(not belt.valid, "the removed rule did not revert its variant")
				local reverted = find(surface, "fast-transport-belt", position)
				runner.assert(
					reverted and reverted.valid,
					"the removed rule's variant was not reverted to fast-transport-belt"
				)
			end
		end)
	end)

	runner.test("ENT-13f a rule missing from the old snapshot is applied", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")

		with_migration_area(runner, migrate, function(surface, center)
			local current = copy_current_rules(runner)
			local new_rule = current["nauvis"] and current["nauvis"]["wooden-chest"]
			runner.assert(new_rule, "the nauvis wooden-chest rule is missing")

			-- The rule did not exist in the old save: delete it from the old
			-- snapshot to exercise the new-only migration branch.
			local old_rules = copy_current_rules(runner)
			old_rules["nauvis"]["wooden-chest"] = nil

			local chest, position = create_at(surface, "wooden-chest", center)
			runner.assert(chest and chest.valid, "could not create the source wooden chest")

			migrate(old_rules)

			if new_rule.enabled == true then
				runner.assert(not chest.valid, "the newly added rule did not migrate the wooden chest")
				local replacement = find(surface, "iron-chest", position)
				runner.assert(replacement and replacement.valid, "the wooden chest was not replaced by an iron chest")
			else
				runner.assert(chest.valid, "the global kill switch should leave the wooden chest in place")
				runner.assert(
					find(surface, "iron-chest", position) == nil,
					"the global kill switch still applied the newly added rule"
				)
			end
		end)
	end)

	runner.test("ENT-13g a removed rule with a missing variant prototype is skipped", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")
		local missing = "funit-ent-missing-variant"
		runner.assert(
			prototypes.entity[missing] == nil,
			missing .. " unexpectedly exists; this test needs a name that is not a prototype"
		)

		with_migration_area(runner, migrate, function(surface, center)
			-- A rule saved by an older mod version can name a generated variant
			-- (for example "foo-PlanetsLib-<planet>") that the current data
			-- stage no longer contains. Reverting that rule must not query the
			-- engine for the unknown name.
			local old_rules = copy_current_rules(runner)
			old_rules["nauvis"]["funit-ent-removed-missing-variant"] = {
				old_entity = "iron-chest",
				entity = missing,
				enabled = true,
			}

			local chest, position = create_at(surface, "iron-chest", center)
			runner.assert(chest and chest.valid, "could not create the control iron chest")

			local ok, err = pcall(migrate, old_rules)
			runner.assert(
				ok,
				"migrating a removed rule with a missing variant prototype raised: " .. tostring(err)
			)
			runner.assert(chest.valid, "the migration destroyed an unrelated entity")
			runner.assert(find(surface, "iron-chest", position) ~= nil, "the control iron chest moved")
		end)
	end)

	runner.test("ENT-13h a changed rule with a missing previous target is skipped", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")
		local missing = "funit-ent-missing-variant"
		runner.assert(
			prototypes.entity[missing] == nil,
			missing .. " unexpectedly exists; this test needs a name that is not a prototype"
		)

		with_migration_area(runner, migrate, function(surface, center)
			local current = copy_current_rules(runner)
			local new_rule = current["nauvis"] and current["nauvis"]["wooden-chest"]
			runner.assert(new_rule, "the nauvis wooden-chest rule is missing")
			runner.assert(new_rule.entity == "iron-chest", "the nauvis wooden-chest rule has the wrong target")

			-- The previous save recorded a target prototype that a mod update
			-- removed. Re-enabling (or disabling) the rule must still work.
			local old_rules = copy_current_rules(runner)
			local old_rule = old_rules["nauvis"]["wooden-chest"]
			old_rule.entity = missing
			old_rule.enabled = true

			local chest, position = create_at(surface, "wooden-chest", center)
			runner.assert(chest and chest.valid, "could not create the source wooden chest")

			local ok, err = pcall(migrate, old_rules)
			runner.assert(
				ok,
				"migrating a changed rule with a missing previous target raised: " .. tostring(err)
			)

			if new_rule.enabled == true then
				runner.assert(not chest.valid, "the changed rule did not migrate the wooden chest")
				local replacement = find(surface, "iron-chest", position)
				runner.assert(replacement and replacement.valid, "the wooden chest was not replaced by an iron chest")
			else
				runner.assert(chest.valid, "the global kill switch should leave the wooden chest in place")
				runner.assert(
					find(surface, "iron-chest", position) == nil,
					"the global kill switch still migrated the wooden chest"
				)
			end
		end)
	end)
end
