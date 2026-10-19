-- data-final-fixes fixture: assert the state PlanetsLib produced.
--
-- PlanetsLib's own data-final-fixes.lua has already run when this fixture is
-- required (see the stage ordering cheat-sheet in ../../AGENTS.md), so this is
-- the earliest point where the processed recipes/prototypes can be checked.
local results = require("lib.results")

local SPACE_AGE = mods["space-age"]

local function approx(a, b, epsilon)
	return math.abs(a - b) <= (epsilon or 1e-6)
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

-- MISC-4: enhanced tooltips.
local tooltip_ok, tooltip_err
if settings.startup["PlanetsLib-enhanced-tooltips"].value ~= true then
	tooltip_ok, tooltip_err = true, "PlanetsLib-enhanced-tooltips is disabled; skipped"
else
	tooltip_ok, tooltip_err = pcall(function()
		local all = data.raw.recipe["funit-visual-tooltip-all"]
		assert(all, "funit-visual-tooltip-all is missing")
		local fields = all.custom_tooltip_fields
		assert(fields, "the all-tooltips recipe gained no custom_tooltip_fields")

		local fresh = tooltip_by_name(fields, "tooltip.result-is-always-fresh")
		assert(fresh, "the always-fresh tooltip is missing")
		assert(fresh.order == 201, "the always-fresh tooltip has the wrong order")
		assert(
			fresh.value[1] == "" and fresh.value[2] == "[item=funit-visual-spoiler]",
			"the always-fresh tooltip does not name the spoilable product"
		)

		local reset = tooltip_by_name(fields, "tooltip.reset-freshness-on-craft")
		assert(reset, "the reset-freshness tooltip is missing")
		assert(reset.order == 202, "the reset-freshness tooltip has the wrong order")

		local preserve = tooltip_by_name(fields, "tooltip.preserve-products-in-machine-output")
		assert(preserve, "the preserve-products tooltip is missing")
		assert(preserve.order == 203, "the preserve-products tooltip has the wrong order")
		assert(preserve.value[1] == "gui.yes", "the preserve-products tooltip should say yes")

		-- Spoilage-only: a recipe whose results all lack spoil_ticks must not
		-- gain freshness tooltips.
		local nospoil = data.raw.recipe["funit-visual-tooltip-nospoil"]
		assert(nospoil, "funit-visual-tooltip-nospoil is missing")
		assert(
			nospoil.custom_tooltip_fields == nil,
			"a recipe with only non-spoiling results gained freshness tooltips"
		)

		-- rro.soft_insert() dedupe: the identical pre-existing field must not
		-- be added a second time.
		local dedupe = data.raw.recipe["funit-visual-tooltip-dedupe"]
		assert(dedupe, "funit-visual-tooltip-dedupe is missing")
		local dedupe_fields = dedupe.custom_tooltip_fields
		assert(dedupe_fields, "the dedupe recipe lost its pre-existing tooltip")
		assert(#dedupe_fields == 1, "soft_insert duplicated an identical tooltip field")
	end)
end
results.record("misc_visuals_final", "MISC-4", tooltip_ok, tooltip_err)

-- MISC-5: PlanetsLib_pipette_result.
local pipette_ok, pipette_err = pcall(function()
	local mapping = PlanetsLib.constants.pipette_result
	assert(mapping, "PlanetsLib.constants.pipette_result is missing")
	assert(
		mapping["funit-visual-pipette"] == "funit-visual-pipette-target",
		"the custom pipette result was not registered"
	)
	assert(mapping["funit-visual-pipette-target"] == nil, "only the source entity should be registered")
	local source = data.raw["container"]["funit-visual-pipette"]
	assert(source, "the pipette source entity is missing")
	assert(source.placeable_by == nil, "the pipette source must not define placeable_by (mutually exclusive)")
	assert(data.raw["container"]["funit-visual-pipette-target"], "the pipette target entity is missing")
end)
results.record("misc_visuals_final", "MISC-5", pipette_ok, pipette_err)
results.record(
	"misc_visuals_final",
	"MISC-5-note",
	true,
	"the both-fields assertion cannot be exercised from the data stage without aborting prototype loading"
)

-- MISC-6: centrifuge fluid boxes and tint.
local centrifuge_ok, centrifuge_err = pcall(function()
	local additional = settings.startup["PlanetsLib-enable-additional-centrifuge-fluidboxes"].value
	local expected = additional and 4 or 2
	for _, name in ipairs({ "centrifuge", "funit-visual-centrifuge" }) do
		local machine = data.raw["assembling-machine"][name]
		assert(machine, name .. " is missing")
		assert(machine.fluid_boxes, name .. " has no fluid_boxes")
		assert(#machine.fluid_boxes == expected, name .. " should have " .. expected .. " fluid boxes")
		assert(machine.fluid_boxes[1].production_type == "input", name .. " first fluid box should be an input")
		assert(machine.fluid_boxes[2].production_type == "output", name .. " second fluid box should be an output")
	end
	-- PlanetsLib only fills in modded centrifuges; vanilla keeps its own boxes.
	assert(
		data.raw["assembling-machine"]["funit-visual-centrifuge"].fluid_boxes_off_when_no_fluid_recipe == true,
		"the modded centrifuge should hide its fluid boxes when not needed"
	)
end)
results.record("misc_visuals_final", "MISC-6", centrifuge_ok, centrifuge_err)

local tint_ok, tint_err
local centrifuge = data.raw["assembling-machine"]["centrifuge"]
if
	centrifuge
	and centrifuge.graphics_set
	and centrifuge.graphics_set.working_visualisations
	and centrifuge.graphics_set.working_visualisations[1]
	and centrifuge.graphics_set.working_visualisations[2]
	and centrifuge.graphics_set.working_visualisations[2].animation
	and centrifuge.graphics_set.working_visualisations[2].animation.layers
then
	tint_ok, tint_err = pcall(function()
		local tint = centrifuge.graphics_set.default_recipe_tint
		assert(tint, "the centrifuge default_recipe_tint was not set")
		assert(
			tint.primary[1] == 0 and tint.primary[2] == 1 and tint.primary[3] == 0.2,
			"the centrifuge default tint is wrong"
		)
		assert(
			centrifuge.graphics_set.recipe_not_set_tint.primary[2] == 1,
			"the centrifuge recipe_not_set_tint was not set"
		)
		assert(
			centrifuge.graphics_set.working_visualisations[1].apply_recipe_tint == "primary",
			"working_visualisations[1] does not apply the recipe tint"
		)
		assert(
			centrifuge.graphics_set.working_visualisations[2].apply_recipe_tint == "primary",
			"working_visualisations[2] does not apply the recipe tint"
		)
	end)
else
	tint_ok, tint_err = true, "the centrifuge graphics shape did not match the tint guard; tint check skipped"
end
results.record("misc_visuals_final", "MISC-6-tint", tint_ok, tint_err)
results.record(
	"misc_visuals_final",
	"MISC-6-note",
	true,
	settings.startup["PlanetsLib-enable-additional-centrifuge-fluidboxes"].value
			and "additional centrifuge fluid boxes enabled"
		or "additional centrifuge fluid boxes disabled by setting; hidden extra boxes not exercised"
)

-- MISC-7: default item weights (Space Age only).
if SPACE_AGE then
	local weight_ok, weight_err = pcall(function()
		local lift = data.raw["utility-constants"]["default"].default_rocket_lift_weight
		assert(lift and lift > 0, "default_rocket_lift_weight is missing")
		local samples = {
			{ "iron-plate", 1000 },
			{ "copper-plate", 1000 },
			{ "iron-gear-wheel", 1000 },
			{ "copper-cable", 4000 },
			{ "electronic-circuit", 2000 },
		}
		for _, sample in ipairs(samples) do
			local item = data.raw.item[sample[1]]
			assert(item, sample[1] .. " is missing")
			assert(item.weight, sample[1] .. " has no explicit weight")
			assert(
				approx(item.weight * sample[2], lift),
				sample[1] .. " weight does not match default_rocket_lift_weight / items-per-rocket"
			)
		end
	end)
	results.record("misc_visuals_final", "MISC-7", weight_ok, weight_err)
else
	results.record(
		"misc_visuals_final",
		"MISC-7",
		true,
		"space-age not active; PlanetsLib does not set default weights"
	)
end

-- MISC-8: gas percentage and is-freezing (Space Age only).
if SPACE_AGE then
	local gas_ok, gas_err = pcall(function()
		local planet = data.raw.planet["funit-visual-gas"]
		assert(planet, "funit-visual-gas is missing")
		assert(planet.surface_properties.oxygen == 40, "the oxygen property is missing")
		assert(planet.surface_properties.nitrogen == 60, "the nitrogen property is missing")
	end)
	results.record("misc_visuals_final", "MISC-8-gas", gas_ok, gas_err)
	results.record(
		"misc_visuals_final",
		"MISC-8-gas-note",
		true,
		"a gas sum of exactly 100 passed the assertion; the >100 failure path cannot be exercised without aborting prototype loading"
	)

	local freeze_ok, freeze_err = pcall(function()
		local property = data.raw["surface-property"]["is-freezing"]
		assert(property, "the is-freezing surface-property is missing")
		assert(property.default_value == 0, "is-freezing should default to 0")
		assert(property.hidden == true, "is-freezing should be hidden")
		local planet = data.raw.planet["funit-visual-freezing"]
		assert(planet, "funit-visual-freezing is missing")
		assert(
			planet.surface_properties["is-freezing"] == 1,
			"entities_require_heating should add the is-freezing property"
		)
	end)
	results.record("misc_visuals_final", "MISC-8-freezing", freeze_ok, freeze_err)
else
	results.record(
		"misc_visuals_final",
		"MISC-8",
		true,
		"space-age not active; gas and is-freezing checks are skipped"
	)
end

-- MISC-9: star prototype and native starmap cleanup (Space Age only).
if SPACE_AGE then
	local star_ok, star_err = pcall(function()
		local star = data.raw["space-location"]["star"]
		assert(star, "the star space-location disappeared")
		assert(star.hidden == true, "the star should stay hidden")
		assert(star.sprite_only == nil, "the star should have survived sprite_only cleanup")
		assert(star.origin and star.origin.x == 0 and star.origin.y == 0, "the star should sit at the origin")
	end)
	results.record("misc_visuals_final", "MISC-9-star", star_ok, star_err)

	local cleanup_ok, cleanup_err = pcall(function()
		assert(
			data.raw["space-location"]["funit-visual-sprite-only"] == nil,
			"sprite_only locations should be removed in data-final-fixes"
		)
		local orbit = data.raw.planet["funit-visual-orbit"]
		assert(orbit, "funit-visual-orbit is missing")
		assert(orbit.origin, "the orbit planet did not gain a native origin")
		assert(
			approx(orbit.origin.x, 0) and approx(orbit.origin.y, 0),
			"the orbit planet origin should be the star at 0,0"
		)
		assert(
			approx(orbit.distance, 12) and approx(orbit.orientation, 0.25),
			"the orbit planet position should be rebased onto its origin"
		)
	end)
	results.record("misc_visuals_final", "MISC-9-cleanup", cleanup_ok, cleanup_err)
else
	results.record("misc_visuals_final", "MISC-9", true, "space-age not active; the star does not exist")
end

return true
