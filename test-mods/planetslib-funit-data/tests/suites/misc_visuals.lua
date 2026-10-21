-- Miscellaneous visual / prototype overrides (MISC-4..9):
-- enhanced tooltips, PlanetsLib_pipette_result, centrifuge fluid boxes and
-- tint, default item weights, gas/is-freezing surface properties, and the star
-- prototype + native-orbit cleanup.
--
-- The data stage is gone at runtime, so the misc_visuals_setup and
-- misc_visuals_final fixtures record the processed state and this suite asserts
-- both the recorded results and the surviving runtime prototypes.

local support = require("__planetslib-funit-data__.tests.suites.support")

local function assert_fixture_namespace(runner, suite)
	support.assert_all(runner, suite)
end

local function tooltip_by_name(fields, name)
	if not fields then
		return nil
	end
	for _, field in pairs(fields) do
		if type(field.name) == "table" and field.name[1] == name then
			return field
		end
	end
	return nil
end

return function(runner)
	runner.test("MISC-0 fixture result ids and expected skips", function()
		local space_age = support.has_space_age()
		local expected = { "MISC-4", "MISC-5", "MISC-6", "MISC-6-tint", "MISC-7" }
		local allow_skips = {}
		if not space_age then
			allow_skips["MISC-4"] = true
			allow_skips["MISC-6-tint"] = true
			allow_skips["MISC-7"] = true
			allow_skips["MISC-8"] = true
			allow_skips["MISC-9"] = true
			table.insert(expected, "MISC-8")
			table.insert(expected, "MISC-9")
		else
			table.insert(expected, "MISC-8-gas")
			table.insert(expected, "MISC-8-freezing")
			table.insert(expected, "MISC-9-star")
			table.insert(expected, "MISC-9-cleanup")
			if settings.startup["PlanetsLib-enhanced-tooltips"].value ~= true then
				allow_skips["MISC-4"] = true
			end
			allow_skips["MISC-6-tint"] = true
		end
		support.assert_all(runner, "misc_visuals_final", {
			expected = expected,
			allow_skips = allow_skips,
		})
	end)

	runner.test("MISC-4 enhanced tooltips (freshness/reset/preserve, spoilage-only, dedupe)", function()
		assert_fixture_namespace(runner, "misc_visuals_setup")

		if not script.active_mods["space-age"] then
			return
		end

		if settings.startup["PlanetsLib-enhanced-tooltips"].value ~= true then
			return
		end

		local all = prototypes.recipe["funit-visual-tooltip-all"]
		runner.assert(all, "funit-visual-tooltip-all is missing")
		local fields = all.custom_tooltip_fields
		runner.assert(fields, "custom_tooltip_fields did not persist to runtime")
		runner.assert(tooltip_by_name(fields, "tooltip.result-is-always-fresh"), "the always-fresh tooltip is missing")
		runner.assert(
			tooltip_by_name(fields, "tooltip.reset-freshness-on-craft"),
			"the reset-freshness tooltip is missing"
		)
		runner.assert(
			tooltip_by_name(fields, "tooltip.preserve-products-in-machine-output"),
			"the preserve-products tooltip is missing"
		)

		runner.assert(
			prototypes.recipe["funit-visual-tooltip-nospoil"].custom_tooltip_fields == nil,
			"a non-spoiling recipe gained freshness tooltips"
		)

		local dedupe = prototypes.recipe["funit-visual-tooltip-dedupe"]
		runner.assert(dedupe.custom_tooltip_fields, "the dedupe recipe lost its pre-existing tooltip")
		runner.assert(#dedupe.custom_tooltip_fields == 1, "soft_insert duplicated an identical tooltip")
	end)

	runner.test("MISC-5 PlanetsLib_pipette_result is registered and exclusive with placeable_by", function()
		local mapping = prototypes.mod_data["Planetslib"].data.pipette_result
		runner.assert(mapping, "PlanetsLib constants have no pipette_result table")
		runner.assert(
			mapping["funit-visual-pipette"] == "funit-visual-pipette-target",
			"the custom pipette result was not registered"
		)
		runner.assert(mapping["funit-visual-pipette-target"] == nil, "only the source entity should be registered")

		local source = prototypes.entity["funit-visual-pipette"]
		runner.assert(source, "the pipette source entity is missing")
		-- placeable_by is data-stage only; misc_visuals_final asserts that the
		-- source has no placeable_by and that the custom field is exclusive.
		runner.assert(prototypes.entity["funit-visual-pipette-target"], "the pipette target entity is missing")
	end)

	runner.test("MISC-6 centrifuge fluid boxes and tint", function()
		local additional = settings.startup["PlanetsLib-enable-additional-centrifuge-fluidboxes"].value
		local expected = additional and 4 or 2
		for _, name in ipairs({ "centrifuge", "funit-visual-centrifuge" }) do
			local machine = prototypes.entity[name]
			runner.assert(machine, name .. " is missing")
			runner.assert(
				machine.fluidbox_prototypes and #machine.fluidbox_prototypes == expected,
				name .. " should have " .. expected .. " fluid boxes"
			)
		end
		-- Only the modded centrifuge is filled in by PlanetsLib; vanilla keeps
		-- its own fluid boxes.
		runner.assert(
			prototypes.entity["funit-visual-centrifuge"].fluid_boxes_off_when_no_fluid_recipe == true,
			"the modded centrifuge should hide its fluid boxes when not needed"
		)
		-- The default recipe tint lives on graphics_set, which is not exposed by
		-- LuaEntityPrototype at runtime; misc_visuals_final asserts it instead.
	end)

	runner.test("MISC-7 default item weights", function()
		if not script.active_mods["space-age"] then
			return
		end
		local iron = prototypes.item["iron-plate"]
		local copper = prototypes.item["copper-plate"]
		local cable = prototypes.item["copper-cable"]
		runner.assert(iron.weight and copper.weight and cable.weight, "default weights were not set")
		runner.assert(
			math.abs(iron.weight - copper.weight) < 1e-9,
			"items with the same items-per-rocket should share a weight"
		)
		runner.assert(
			math.abs(iron.weight * 1000 - cable.weight * 4000) < 1e-6,
			"weights should scale with items-per-rocket"
		)
	end)

	runner.test("MISC-8 gas percentage and is-freezing", function()
		if not script.active_mods["space-age"] then
			return
		end
		local property = prototypes.surface_property["is-freezing"]
		runner.assert(property, "the is-freezing surface-property is missing")
		runner.assert(property.default_value == 0, "is-freezing should default to 0")
		runner.assert(property.hidden == true, "is-freezing should be hidden")

		local freezing = prototypes.space_location["funit-visual-freezing"]
		runner.assert(freezing, "funit-visual-freezing is missing")
		runner.assert(
			freezing.surface_properties["is-freezing"] == 1,
			"entities_require_heating did not add is-freezing"
		)

		local gas = prototypes.space_location["funit-visual-gas"]
		runner.assert(gas, "funit-visual-gas is missing")
		runner.assert(
			gas.surface_properties.oxygen == 40 and gas.surface_properties.nitrogen == 60,
			"the gas planet lost its surface properties"
		)
	end)

	runner.test("MISC-9 star prototype and native starmap cleanup", function()
		if not script.active_mods["space-age"] then
			return
		end
		local star = prototypes.space_location["star"]
		runner.assert(star, "the star space-location is missing")
		runner.assert(star.hidden == true, "the star should be hidden")
		-- `sprite_only` is a data-stage field and is not exposed at runtime; the
		-- data-stage fixture asserts the cleanup. The star's survival is what
		-- matters here.
		runner.assert(star.origin, "the star should have a native origin")

		runner.assert(
			prototypes.space_location["funit-visual-sprite-only"] == nil,
			"sprite_only locations should have been removed"
		)

		local orbit = prototypes.space_location["funit-visual-orbit"]
		runner.assert(orbit, "funit-visual-orbit is missing")
		runner.assert(orbit.origin, "the orbit planet has no native origin")
		runner.assert(
			math.abs(orbit.origin.x) < 1e-6 and math.abs(orbit.origin.y) < 1e-6,
			"the orbit planet origin should be the star at 0,0"
		)
	end)
end
