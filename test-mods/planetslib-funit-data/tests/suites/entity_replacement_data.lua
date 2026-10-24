-- Entity replacement: data-stage API (ENT-1..ENT-4).
--
-- The `entity_replacement_data` fixture calls PlanetsLib's data-stage API and
-- records the outcome in the results bag. This suite asserts those recorded
-- results plus the final runtime prototypes.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local SUITE = "entity_replacement_data"

local function get_results(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	return mod_data.data
end

local function assert_entries(runner, ids)
	local bag = get_results(runner)[SUITE]
	runner.assert(bag, "no data-stage results recorded for '" .. SUITE .. "'")
	for _, id in ipairs(ids) do
		local entry = bag[id]
		runner.assert(entry, "missing data fixture entry " .. id)
		runner.assert(entry.ok, "data fixture " .. id .. " failed: " .. tostring(entry.err))
	end
end

local function contains(list, value)
	if not list then
		return false
	end
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end
	return false
end

return function(runner)
	runner.test("ENT-0 entity-replacement startup settings match the CI scenario", function()
		local settings_mod = script.active_mods["planetslib-funit-settings"] ~= nil
		local enable = settings.startup["PlanetsLib-enable-entity-replacements"].value
		local disable_all = settings.startup["PlanetsLib-disable-all-entity-replacements"].value
		runner.assert(
			enable == not settings_mod,
			"PlanetsLib-enable-entity-replacements is "
				.. tostring(enable)
				.. ", but the CI settings mod is "
				.. (settings_mod and "enabled" or "not loaded")
		)
		runner.assert(
			disable_all == settings_mod,
			"PlanetsLib-disable-all-entity-replacements is "
				.. tostring(disable_all)
				.. ", but the CI settings mod is "
				.. (settings_mod and "enabled" or "not loaded")
		)
	end)

	runner.test("ENT-1 assign_entity_replacement storage, errors and variant lists", function()
		assert_entries(runner, {
			"ENT-1a",
			"ENT-1b",
			"ENT-1c",
			"ENT-1d",
			"ENT-1e",
			"ENT-1f",
			"ENT-1g",
			"ENT-1h",
		})

		local replacements = prototypes.mod_data["Planetslib"].data.on_entity_placed_on_planet_replacements
		runner.assert(replacements, "the runtime replacement rules table is missing")

		-- ENT-1h: the planet-list form must not leak a non-string planet key into
		-- the runtime rules (see the ENT-1h check in the fixture).
		for key in pairs(replacements) do
			runner.assert(
				type(key) == "string",
				"a non-string planet key leaked into the runtime replacement rules"
			)
		end

		-- ENT-1a/1e: stored rule shape and planet-table/mass forms.
		local planet_a = replacements["funit-ent-planet-a"]
		runner.assert(planet_a, "funit-ent-planet-a has no rules")
		for _, name in ipairs({
			"funit-ent-old-a",
			"funit-ent-old-b",
			"funit-ent-mass-old-1",
			"funit-ent-mass-old-2",
			"funit-ent-pt-old",
			"funit-ent-suffix-old",
		}) do
			runner.assert(planet_a[name], "missing rule on funit-ent-planet-a: " .. name)
			runner.assert(planet_a[name].old_entity == name, "old_entity mismatch for " .. name)
		end
		runner.assert(planet_a["funit-ent-mass-old-1"].entity == "funit-ent-mass-new-1",
			"the mass-assignment rule was not stored")
		runner.assert(planet_a["funit-ent-pt-old"].entity == "funit-ent-pt-new",
			"the planet-table rule did not reach funit-ent-planet-a")
		runner.assert(replacements["funit-ent-planet-b"]["funit-ent-pt-old"].entity == "funit-ent-pt-new",
			"the planet-table rule did not reach funit-ent-planet-b")

		-- ENT-1a: the documented default bound setting is used when omitted.
		runner.assert(type(planet_a["funit-ent-old-b"].enabled) == "boolean",
			"the default bound setting did not produce a boolean enabled flag")

		-- ENT-1d: variant lists.
		runner.assert(contains(prototypes.mod_data["Planetslib"].data.entity_variants_list["funit-ent-old-a"],
			"funit-ent-new-a"), "entity_variants_list is missing the assigned variant")
		local inverse = prototypes.mod_data["Planetslib"].data.entity_variants_list_inverse["funit-ent-new-a"]
		runner.assert(inverse and #inverse == 1 and inverse[1].entity == "funit-ent-old-a",
			"entity_variants_list_inverse does not contain the base entity")
		local suffix_inverse =
			prototypes.mod_data["Planetslib"].data.entity_variants_list_inverse["funit-ent-suffix-new"]
		runner.assert(suffix_inverse and suffix_inverse[1].suffix == "funit-suffix",
			"the name suffix was not recorded in the inverse variant list")

		-- ENT-1g: the rules the runtime suite drives.
		local nauvis = replacements["nauvis"]
		runner.assert(nauvis, "nauvis has no replacement rules")
		runner.assert(nauvis["wooden-chest"] and nauvis["wooden-chest"].entity == "iron-chest",
			"the wooden-chest -> iron-chest rule is missing")
		runner.assert(nauvis["stone-furnace"] and nauvis["stone-furnace"].entity == "steel-furnace",
			"the stone-furnace -> steel-furnace rule is missing")
		runner.assert(nauvis["assembling-machine-3"] and nauvis["assembling-machine-3"].entity == "assembling-machine-2",
			"the assembling-machine-3 -> assembling-machine-2 rule is missing")
		runner.assert(nauvis["transport-belt"] and nauvis["transport-belt"].enabled == false,
			"the disabled transport-belt rule is missing or enabled")

		-- The global kill switch must override every rule, including rules bound
		-- to their own (default-on) startup setting. Without it, the per-rule
		-- settings must be respected.
		local disable_all = settings.startup["PlanetsLib-disable-all-entity-replacements"].value
		if disable_all then
			for planet_name, planet_rules in pairs(replacements) do
				for entity_name, rule in pairs(planet_rules) do
					runner.assert(
						rule.enabled == false,
						"rule '"
							.. tostring(entity_name)
							.. "' on '"
							.. tostring(planet_name)
							.. "' is enabled even though PlanetsLib-disable-all-entity-replacements is true"
					)
				end
			end
		else
			local default_enabled = settings.startup["PlanetsLib-enable-entity-replacements"].value
			local fixture_enabled =
				settings.startup["planetslib-funit-data-enable-entity-replacement-fixture"].value
			runner.assert(
				planet_a["funit-ent-old-b"].enabled == default_enabled,
				"the default-bound rule did not reflect PlanetsLib-enable-entity-replacements"
			)
			for _, name in ipairs({
				"funit-ent-old-a",
				"funit-ent-suffix-old",
				"funit-ent-mass-old-1",
				"funit-ent-mass-old-2",
				"funit-ent-pt-old",
				"wooden-chest",
				"stone-wall",
				"iron-chest",
				"gun-turret",
			}) do
				runner.assert(
					planet_a[name] and planet_a[name].enabled == fixture_enabled,
					"fixture-bound rule '" .. name .. "' did not reflect its own startup setting"
				)
			end
			for _, name in ipairs({ "wooden-chest", "stone-furnace", "assembling-machine-3" }) do
				runner.assert(
					nauvis[name] and nauvis[name].enabled == fixture_enabled,
					"nauvis fixture-bound rule '" .. name .. "' did not reflect its own startup setting"
				)
			end
		end
	end)

	runner.test("ENT-2 create_planet_entity_variant metadata and generated prototypes", function()
		assert_entries(runner, {
			"ENT-2a",
			"ENT-2b",
			"ENT-2c",
			"ENT-2d",
			"ENT-2e",
			"ENT-2f",
			"ENT-2g",
		})

		local variant = prototypes.entity["wooden-chest-PlanetsLib-funit-ent-planet-a"]
		runner.assert(variant, "the single-planet wooden-chest variant is missing")
		runner.assert(
			variant.get_inventory_size(defines.inventory.chest) == 99,
			"new_properties were not merged into the variant"
		)
		-- factoriopedia_alternative, hidden_in_factoriopedia, placeable_by,
		-- localised_name, icons, order and flags are prototype-stage fields that
		-- are not all exposed at runtime; ENT-2a asserts them in the data stage.

		local multi = prototypes.entity["stone-wall-PlanetsLib-funit-ent-planet-a"]
		runner.assert(multi, "the multi-planet stone-wall variant is missing")
		-- max_health is asserted by ENT-2b in the data stage.

		local inferred = prototypes.entity["iron-chest-PlanetsLib-funit-ent-planet-a"]
		runner.assert(inferred, "the inferred item variant is missing")
		local explicit = prototypes.entity["gun-turret-PlanetsLib-funit-ent-planet-a"]
		runner.assert(explicit, "the explicit item_name variant is missing")

		-- ENT-2e: runtime variants exist as prototypes and are registered.
		local replacements = prototypes.mod_data["Planetslib"].data.on_entity_placed_on_planet_replacements
		local nauvis = replacements["nauvis"]
		local runtime_variants = {
			{ "heat-pipe", "heat-pipe-PlanetsLib-nauvis" },
			{ "storage-tank", "storage-tank-PlanetsLib-nauvis" },
			{ "arithmetic-combinator", "arithmetic-combinator-PlanetsLib-nauvis" },
			{ "locomotive", "locomotive-PlanetsLib-nauvis" },
			{ "spidertron", "spidertron-PlanetsLib-nauvis" },
			{ "car", "car-PlanetsLib-nauvis" },
		}
		for _, info in ipairs(runtime_variants) do
			runner.assert(prototypes.entity[info[2]], "runtime variant prototype is missing: " .. info[1])
			runner.assert(nauvis[info[1]] and nauvis[info[1]].entity == info[2],
				"runtime variant rule is missing: " .. info[1])
		end

		-- ENT-2f/ENT-2g: no generated variant may be used as the base of
		-- another variant, regardless of whether the marker flag or the
		-- generated name prevents it.
		local recursion_variant = prototypes.entity["funit-ent-recursion-base-PlanetsLib-funit-ent-planet-a"]
		runner.assert(recursion_variant, "the recursion-guard fixture variant is missing")
		runner.assert(
			prototypes.entity["funit-ent-recursion-base-PlanetsLib-funit-ent-planet-a-PlanetsLib-funit-ent-planet-a"] == nil,
			"a variant of a generated variant exists (issue #136)"
		)
		runner.assert(
			prototypes.entity["funit-ent-recursion-override-base-PlanetsLib-funit-ent-planet-a-PlanetsLib-funit-ent-planet-a"] == nil,
			"overriding PlanetsLib_do_not_generate_variants allowed a variant of a generated variant"
		)
		local planet_a_rules = prototypes.mod_data["Planetslib"].data.on_entity_placed_on_planet_replacements["funit-ent-planet-a"]
		runner.assert(planet_a_rules["funit-ent-recursion-base-PlanetsLib-funit-ent-planet-a"] == nil,
			"the generated variant was registered as a base entity")
	end)

	runner.test("ENT-3 rocket lift/part multiplier variant fields", function()
		if not script.active_mods["space-age"] then
			return
		end

		assert_entries(runner, { "ENT-3" })

		local base = prototypes.entity["rocket-silo"]
		local variant = prototypes.entity["rocket-silo-PlanetsLib-funit-ent-planet-b"]
		runner.assert(base, "the vanilla rocket-silo prototype is missing")
		runner.assert(variant, "the rocket-silo multiplier variant is missing")

		local base_parts = base.rocket_parts_required or 20
		runner.assert(variant.rocket_parts_required == base_parts * 3,
			"rocket_parts_required was not multiplied by 3")

		if base.lift_weight then
			runner.assert(variant.lift_weight == base.lift_weight * 2,
				"lift_weight was not multiplied by 2")
		else
			runner.assert(variant.lift_weight == 1234567 * 2,
				"lift_weight did not use the fixture's fallback value")
		end

		if base.rocket_parts_storage_cap then
			runner.assert(variant.rocket_parts_storage_cap == base.rocket_parts_storage_cap * 3,
				"rocket_parts_storage_cap was not multiplied by 3")
		end
	end)

	runner.test("ENT-4 special properties and the final-fixes rocket override", function()
		assert_entries(runner, { "ENT-4" })

		local properties = prototypes.mod_data["Planetslib"].data.planet_special_properties["funit-ent-rocket"]
		runner.assert(properties, "funit-ent-rocket has no special properties")
		runner.assert(properties.rocket_lift_multiplier == 2, "rocket_lift_multiplier did not persist")
		runner.assert(properties.rocket_part_multiplier == 3, "rocket_part_multiplier did not persist")

		local base = prototypes.entity["rocket-silo"]
		local variant = prototypes.entity["rocket-silo-PlanetsLib-funit-ent-rocket"]
		local planet = prototypes.space_location["funit-ent-rocket"]

		if script.active_mods["space-age"] then
			runner.assert(variant, "Space Age is active but the rocket override did not generate a variant")
			runner.assert(
				variant.rocket_parts_required == (base.rocket_parts_required or 20) * 3,
				"the override did not apply rocket_part_multiplier"
			)
			runner.assert(planet.surface_properties["PlanetsLib-rocket-part-multiplier"] == 3,
				"the part multiplier surface property is missing")
			runner.assert(planet.surface_properties["PlanetsLib-lift-weight-multiplier"] == 2,
				"the lift multiplier surface property is missing")
			runner.assert(prototypes.surface_property["PlanetsLib-lift-weight-multiplier"],
				"the lift multiplier surface-property prototype is missing")
			if base.lift_weight then
				runner.assert(variant.lift_weight == base.lift_weight * 2,
					"the override did not apply rocket_lift_multiplier")
			else
				runner.assert(variant.lift_weight, "the override did not set lift_weight")
			end
		else
			runner.assert(not variant,
				"without Space Age the final-fixes rocket override should not run")
			runner.log("ENT-4: Space Age is inactive; the final-fixes rocket override is skipped by PlanetsLib.")
		end
	end)
end
