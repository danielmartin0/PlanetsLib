-- Entity replacement: migration behavior (ENT-12..ENT-13).
--
-- ENT-12 drives the live rolling-stock upgrade path. ENT-13a/ENT-13b exercise
-- the on_configuration_changed entry point and the silent (raise_built = false)
-- replacement path used by migrations. ENT-13c..ENT-13e drive the real rule
-- migration through the `migrate_entity_replacement_rules` seam with a complete
-- old-rule snapshot, covering re-enabled, disabled and removed rules. ENT-13g
-- and ENT-13h cover stale rule snapshots whose entity prototypes no longer
-- exist after a mod update. ENT-13i checks rolling-stock orientation survives
-- the migration replacement in all eight rail directions.

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

local function with_area(runner, body, radius)
	fixture_entries(runner)
	local planet = game.planets[SURFACE_NAME]
	runner.assert(planet and planet.surface, "the nauvis surface is missing")
	local surface = planet.surface
	radius = radius or AREA_RADIUS

	next_area = next_area + 1
	local center = { x = 8000 + next_area * AREA_STEP, y = 4000 }

	local ok, err = pcall(function()
		prepare_area(surface, center, radius)
		-- Map generation can leave trees, rocks or cliffs inside the landfill
		-- area; clear them before each test so entity placement is deterministic.
		clear_area(surface, center, radius)
		body(surface, center)
	end)
	pcall(clear_area, surface, center, radius + 6)
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

local function create_rail(surface, center, direction)
	-- A locomotive is six tiles long, so a single 2-tile rail segment cannot
	-- hold one. Build a short line and return the middle segment. `direction`
	-- is one of the eight rail directions a locomotive can face (0, 2, 4, 6,
	-- 8, 10, 12, 14); the engine normalises a rail to its axis, but the
	-- requested direction still decides which way a locomotive placed on it
	-- faces.
	-- Rail alignment depends on the rail grid; try a few centre conventions.
	local axis = direction % 8
	local step
	if axis == 0 then
		step = { x = 0, y = 2 }
	elseif axis == 2 then
		step = { x = -2, y = 2 }
	elseif axis == 4 then
		step = { x = 2, y = 0 }
	elseif axis == 6 then
		step = { x = 2, y = 2 }
	else
		return nil
	end

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
			local position = {
				x = base.x + step.x * offset,
				y = base.y + step.y * offset,
			}
			local ok, rail = pcall(function()
				return surface.create_entity({
					name = "straight-rail",
					position = position,
					direction = direction,
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

local function create_half_diagonal_rail(surface, center, direction)
	-- Half-diagonal rails connect at a (2, 4) or (4, 2) offset. Three pieces
	-- are long enough for a locomotive plus a wagon, and the resulting
	-- locomotive orientation is not a multiple of 1/8. That fractional
	-- orientation is what exposes the engine's floating-point rounding (issue
	-- #139). `direction` selects which way the stock faces, like create_rail.
	local axis = direction % 8
	local step
	if axis == 0 then
		step = { x = 2, y = 4 }
	elseif axis == 2 then
		step = { x = 2, y = -4 }
	elseif axis == 4 then
		step = { x = 4, y = -2 }
	elseif axis == 6 then
		step = { x = 4, y = 2 }
	else
		return nil
	end

	local candidates = {
		{ x = center.x, y = center.y },
		{ x = center.x + 0.5, y = center.y + 0.5 },
		{ x = center.x - 0.5, y = center.y - 0.5 },
	}
	for _, base in ipairs(candidates) do
		local rails = {}
		local complete = true
		for offset = -1, 1 do
			local position = {
				x = base.x + step.x * offset,
				y = base.y + step.y * offset,
			}
			local ok, rail = pcall(function()
				return surface.create_entity({
					name = "half-diagonal-rail",
					position = position,
					direction = direction,
					force = game.forces.player,
				})
			end)
			if not (ok and rail and rail.valid) then
				complete = false
				break
			end
			rails[#rails + 1] = rail
		end
		if complete then
			return rails
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
			local rail = create_rail(surface, center, defines.direction.north)
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

	runner.test("ENT-13i migration preserves locomotive orientation in every direction", function()
		local migrate = require_seam(runner, "migrate_entity_replacement_rules")

		-- Locomotive orientation is the direction the stock faces; `direction`
		-- itself is the rail direction (front/back) and is always north for a
		-- lone locomotive. A locomotive can face eight directions on straight
		-- rails: the four cardinals plus the four diagonals. Build one track
		-- per direction and assert the literal orientation the fixture is
		-- expected to produce, so a mis-placed fixture fails instead of
		-- silently testing the wrong pose.
		local cases = {
			{ direction = defines.direction.north, orientation = 0, label = "north" },
			{ direction = defines.direction.northeast, orientation = 0.125, label = "northeast" },
			{ direction = defines.direction.east, orientation = 0.25, label = "east" },
			{ direction = defines.direction.southeast, orientation = 0.375, label = "southeast" },
			{ direction = defines.direction.south, orientation = 0.5, label = "south" },
			{ direction = defines.direction.southwest, orientation = 0.625, label = "southwest" },
			{ direction = defines.direction.west, orientation = 0.75, label = "west" },
			{ direction = defines.direction.northwest, orientation = 0.875, label = "northwest" },
		}
		local tolerance = 1e-4

		with_migration_area(runner, migrate, function(surface, center)
			for _, case in ipairs(cases) do
				-- Keep one track at a time so locomotives cannot connect into a
				-- train and so a replacement from the previous case cannot be
				-- mistaken for this case's result.
				clear_area(surface, center, AREA_RADIUS)

				local rail = create_rail(surface, center, case.direction)
				runner.assert(
					rail and rail.valid,
					"could not create a " .. case.label .. " straight rail for the locomotive"
				)

				local ok, locomotive = pcall(function()
					return surface.create_entity({
						name = "locomotive",
						position = rail.position,
						direction = case.direction,
						force = game.forces.player,
					})
				end)
				runner.assert(
					ok and locomotive and locomotive.valid,
					"could not create a " .. case.label .. "-facing locomotive on the test rail: "
						.. tostring(locomotive)
				)
				runner.assert(
					math.abs(locomotive.orientation - case.orientation) < tolerance,
					"the " .. case.label .. " fixture locomotive did not face "
						.. case.label .. " (orientation " .. tostring(locomotive.orientation) .. ")"
				)

				local position = locomotive.position
				local old_orientation = locomotive.orientation
				local old_unit_number = locomotive.unit_number

				-- The previous save had the locomotive rule disabled. Changing it
				-- back to enabled makes the migration replace existing locomotives
				-- through the rolling-stock path.
				local current = copy_current_rules(runner)
				local new_rule = current["nauvis"] and current["nauvis"]["locomotive"]
				runner.assert(new_rule, "the nauvis locomotive rule is missing")
				runner.assert(
					new_rule.entity == "locomotive-PlanetsLib-nauvis",
					"the nauvis locomotive rule has the wrong target"
				)
				local old_rules = copy_current_rules(runner)
				old_rules["nauvis"]["locomotive"].enabled = false

				migrate(old_rules)

				if new_rule.enabled == true then
					runner.assert(not locomotive.valid, "the migration did not replace the " .. case.label .. " locomotive")
					local replacement = find(surface, "locomotive-PlanetsLib-nauvis", position, 2)
					runner.assert(
						replacement and replacement.valid,
						"the " .. case.label .. " locomotive was not replaced by its nauvis variant"
					)
					runner.assert(
						math.abs(replacement.orientation - old_orientation) < tolerance,
						"the " .. case.label .. " locomotive changed orientation during migration (was "
							.. tostring(old_orientation) .. ", now " .. tostring(replacement.orientation) .. ")"
					)
					runner.assert(replacement.train ~= nil, "the " .. case.label .. " replacement is not on a train")
					runner.assert(
						replacement.unit_number ~= old_unit_number,
						"the " .. case.label .. " replacement reused the old unit number"
					)
				else
					runner.assert(
						locomotive.valid,
						"the global kill switch should leave the " .. case.label .. " locomotive in place"
					)
					runner.assert(
						math.abs(locomotive.orientation - old_orientation) < tolerance,
						"the global kill switch changed the " .. case.label .. " locomotive's orientation"
					)
					runner.assert(
						find(surface, "locomotive-PlanetsLib-nauvis", position, 2) == nil,
						"the global kill switch still migrated the " .. case.label .. " locomotive"
					)
				end
			end
		end)
	end)

	runner.test("ENT-13j curved-track replacement does not report a false orientation mismatch (issue #139)", function()
		local replace_entity = require_seam(runner, "replace_entity")
		local orientations_differ = require_seam(runner, "orientations_differ")

		-- Exact values from the locomotive at (209.984, -487.828) in issue
		-- #139's save: the engine's in-place upgrade reports 0.63550692377612
		-- for a stored orientation of 0.635507. That tiny difference must not
		-- count as a mismatch.
		runner.assert(
			not orientations_differ(0.635507, 0.63550692377612),
			"the issue #139 rounding difference was treated as an orientation mismatch"
		)
		runner.assert(
			orientations_differ(0, 0.25),
			"a 90-degree orientation change was not treated as a mismatch"
		)
		runner.assert(
			not orientations_differ(0.99999, 0.00001),
			"orientations that wrap around 1.0 were treated as a mismatch"
		)

		with_area(runner, function(surface, center)
			-- A half-diagonal track gives a fractional orientation, like the
			-- curved track in the reported save. Three connected pieces are
			-- long enough for a locomotive.
			local rails = create_half_diagonal_rail(surface, center, defines.direction.north)
			runner.assert(rails and #rails == 3, "could not create the curved test track")

			local ok, locomotive = pcall(function()
				return surface.create_entity({
					name = "locomotive",
					position = rails[2].position,
					direction = defines.direction.north,
					force = game.forces.player,
				})
			end)
			runner.assert(ok and locomotive and locomotive.valid, "could not create the curved-track locomotive")

			local orientation = locomotive.orientation
			local eighths = orientation * 8
			runner.assert(
				math.abs(eighths - math.floor(eighths + 0.5)) > 0.01,
				"the curved-track fixture orientation is not fractional: " .. tostring(orientation)
			)
			runner.assert(
				math.abs(orientation - 0.4263) < 1e-3,
				"the curved-track fixture has an unexpected orientation: " .. tostring(orientation)
			)

			local new, orientation_mismatch = replace_entity(locomotive, "locomotive-PlanetsLib-nauvis", false)
			runner.assert(new and new.valid, "the curved-track locomotive was not replaced")
			runner.assert(
				orientation_mismatch == false,
				"the replacement reported a false orientation mismatch for " .. tostring(orientation)
			)
			runner.assert(
				math.abs(new.orientation - orientation) < 1e-4,
				"the curved-track locomotive changed orientation (was "
					.. tostring(orientation) .. ", now " .. tostring(new.orientation) .. ")"
			)
		end, 12)
	end)
end
