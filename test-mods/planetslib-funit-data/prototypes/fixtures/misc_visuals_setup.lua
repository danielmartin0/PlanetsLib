-- Data-stage fixture: prototypes that PlanetsLib's data-updates and
-- data-final-fixes override (enhanced tooltips, pipette results, centrifuge
-- fluid boxes, default weights, gas/is-freezing surface properties and the
-- star/native-orbit cleanup).
--
-- This fixture only creates the inputs (and records that creation succeeded).
-- The processed state is asserted by misc_visuals_final.lua, which runs in
-- data-final-fixes after PlanetsLib has finished.
local results = require("lib.results")

local SPACE_AGE = mods["space-age"]

local function clone_item(name, source)
	local prototype = table.deepcopy(data.raw.item[source])
	prototype.name = name
	return prototype
end

local ok, err = pcall(function()
	if SPACE_AGE then
		-- A spoilable item and a non-spoiling item for the enhanced-tooltip
		-- recipes. Icons and other fields are inherited from iron-plate.
		-- Spoiling is an expansion feature, so the whole MISC-4 fixture is
		-- skipped when Space Age is not active.
		local spoiler = clone_item("funit-visual-spoiler", "iron-plate")
		spoiler.spoil_ticks = 3600
		data:extend({ spoiler })

		local nospoil = clone_item("funit-visual-nospoil", "iron-plate")
		data:extend({ nospoil })

		-- MISC-4: enhanced tooltips.
		--
		-- `always_fresh` and `reset_freshness_on_craft` are per-product fields in
		-- Factorio 2.1 (the recipe-level fields were moved to ItemProductPrototype).
		data:extend({
			{
				type = "recipe",
				name = "funit-visual-tooltip-all",
				ingredients = { { type = "item", name = "funit-visual-spoiler", amount = 1 } },
				results = {
					{
						type = "item",
						name = "funit-visual-spoiler",
						amount = 1,
						always_fresh = true,
						reset_freshness_on_craft = true,
					},
				},
				preserve_products_in_machine_output = true,
				energy_required = 1,
			},
			{
				-- A non-spoiling result must not gain freshness tooltips.
				type = "recipe",
				name = "funit-visual-tooltip-nospoil",
				ingredients = { { type = "item", name = "funit-visual-nospoil", amount = 1 } },
				results = {
					{ type = "item", name = "funit-visual-nospoil", amount = 1, always_fresh = true },
				},
				energy_required = 1,
			},
			{
				-- The exact tooltip PlanetsLib would add is already present, so
				-- rro.soft_insert() must not duplicate it.
				type = "recipe",
				name = "funit-visual-tooltip-dedupe",
				ingredients = { { type = "item", name = "funit-visual-spoiler", amount = 1 } },
				results = {
					{ type = "item", name = "funit-visual-spoiler", amount = 1, always_fresh = true },
				},
				energy_required = 1,
				custom_tooltip_fields = {
					{
						name = { "tooltip.result-is-always-fresh" },
						value = { "", "[item=funit-visual-spoiler]" },
						order = 201,
					},
				},
			},
		})
	end

	-- MISC-5: PlanetsLib_pipette_result. The source must not define
	-- placeable_by, which is mutually exclusive with the custom field.
	local pipette_source = table.deepcopy(data.raw["container"]["iron-chest"])
	pipette_source.name = "funit-visual-pipette"
	pipette_source.placeable_by = nil
	pipette_source.PlanetsLib_pipette_result = "funit-visual-pipette-target"
	data:extend({ pipette_source })

	local pipette_target = table.deepcopy(data.raw["container"]["iron-chest"])
	pipette_target.name = "funit-visual-pipette-target"
	data:extend({ pipette_target })

	-- MISC-6: a modded centrifuging machine without fluid boxes, which
	-- PlanetsLib's data-updates override should give fluid boxes to.
	local centrifuge = table.deepcopy(data.raw["assembling-machine"]["centrifuge"])
	centrifuge.name = "funit-visual-centrifuge"
	centrifuge.crafting_categories = { "centrifuging" }
	centrifuge.fluid_boxes = nil
	centrifuge.fluid_boxes_off_when_no_fluid_recipe = nil
	data:extend({ centrifuge })

	if SPACE_AGE then
		-- MISC-8: planets used by the gas-percentage assertion and the
		-- is-freezing surface property. The gas surface-properties are hidden
		-- behind forced-off settings, so create them if PlanetsLib did not.
		for _, gas in ipairs({ "oxygen", "nitrogen" }) do
			if not data.raw["surface-property"][gas] then
				data:extend({
					{
						type = "surface-property",
						name = gas,
						default_value = 0,
					},
				})
			end
		end

		local gas_planet = table.deepcopy(data.raw.planet.nauvis)
		gas_planet.name = "funit-visual-gas"
		gas_planet.surface_properties = { oxygen = 40, nitrogen = 60 }
		data:extend({ gas_planet })

		local freezing_planet = table.deepcopy(data.raw.planet.nauvis)
		freezing_planet.name = "funit-visual-freezing"
		freezing_planet.entities_require_heating = true
		freezing_planet.surface_properties = {}
		data:extend({ freezing_planet })

		-- MISC-9: a sprite_only location that data-final-fixes must clean up,
		-- and a planet whose PlanetsLib orbit should become a native origin.
		local star = data.raw["space-location"]["star"]
		if star then
			local sprite_only = table.deepcopy(star)
			sprite_only.name = "funit-visual-sprite-only"
			sprite_only.sprite_only = true
			sprite_only.hidden = false
			data:extend({ sprite_only })
		end

		local orbit_planet = table.deepcopy(data.raw.planet.nauvis)
		orbit_planet.name = "funit-visual-orbit"
		orbit_planet.surface_properties = {}
		orbit_planet.origin = nil
		orbit_planet.distance = 12
		orbit_planet.orientation = 0.25
		orbit_planet.orbit = {
			parent = { type = "space-location", name = "star" },
			distance = 12,
			orientation = 0.25,
		}
		data:extend({ orbit_planet })
	end

	if SPACE_AGE then
		assert(data.raw.recipe["funit-visual-tooltip-all"], "the tooltip recipe was not created")
	end
	assert(data.raw["container"]["funit-visual-pipette"], "the pipette entity was not created")
	assert(data.raw["assembling-machine"]["funit-visual-centrifuge"], "the centrifuge clone was not created")
end)
results.record("misc_visuals_setup", "SETUP-1", ok, err)
results.note(
	"misc_visuals_setup",
	"SETUP-2",
	SPACE_AGE and "space-age active"
		or "space-age not active; star/is-freezing/weight/gas tests will be skipped"
)

return true
