-- Data-stage fixture: restrict_to_planet / restrict_to_surface (these create
-- surface-property prototypes and write to data.raw), and the data-stage
-- default_value fallback in fits_surface_conditions.
local results = require("lib.results")

-- The planet omits the property, so fits_surface_conditions has to read the
-- surface-property prototype's default_value. A condition that excludes that
-- default does not fit; a condition that includes it does. This only needs a
-- surface-property prototype, which exists without Space Age.
local lookup_ok, lookup_err = pcall(function()
	assert(
		PlanetsLib.current_stage == "data",
		"this check must run during the data stage, got " .. tostring(PlanetsLib.current_stage)
	)
	assert(
		PlanetsLib.stage ~= "runtime",
		"fits_surface_conditions must take its data-stage branch, got stage " .. tostring(PlanetsLib.stage)
	)

	local property_name = "funit-unset-surface-property"
	local default_value = 7
	data:extend({
		{
			type = "surface-property",
			name = property_name,
			default_value = default_value,
		},
	})

	local property = data.raw["surface-property"][property_name]
	assert(property, "the test surface-property was not created")
	assert(property.default_value == default_value, "the test surface-property default_value changed")

	-- Other properties may be set. This one must not be, or the helper would
	-- read the planet value instead of the prototype default.
	local planet = {
		name = "funit-unset-surface-property-planet",
		surface_properties = {
			["funit-other-surface-property"] = 1,
		},
	}
	assert(planet.surface_properties[property_name] == nil, "the planet must not set the tested property")

	local surface_properties = require("__PlanetsLib__.lib.surface-property-lib")
	local excludes_default = {
		surface_conditions = {
			{ property = property_name, min = default_value + 1, max = default_value + 2 },
		},
	}
	assert(
		not surface_properties.fits_surface_conditions(excludes_default, planet),
		"a condition that excludes the default_value should not fit"
	)

	local includes_default = {
		surface_conditions = {
			{ property = property_name, min = default_value, max = default_value },
		},
	}
	assert(
		surface_properties.fits_surface_conditions(includes_default, planet),
		"a condition that includes the default_value should fit"
	)
end)
results.record("surface_conditions", "SFC-DATA-2", lookup_ok, lookup_err)

-- Surface conditions require the space-travel feature, so this fixture cannot
-- create a valid condition in a base-only game.
if not mods["space-age"] then
	results.skip("surface_conditions", "SFC-DATA-1", "space-age not active; surface-condition fixtures are skipped")
	return true
end

local ok, err = pcall(function()
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = "funit-sc"
	planet.surface_properties = {}
	data:extend({ planet })
	planet = data.raw.planet["funit-sc"]

	local recipe = {}
	PlanetsLib.restrict_to_planet(recipe, "funit-sc")

	local property_name = "PlanetsLib-is-funit-sc"
	local property = data.raw["surface-property"][property_name]
	assert(property, "restrict_to_planet did not create the hidden surface-property")
	assert(property.hidden_in_factoriopedia == true, "the surface-property should be hidden in Factoriopedia")
	assert(property.default_value == 0, "the surface-property default should be 0")
	assert(planet.surface_properties[property_name] == 1, "the planet should have the marker property set")

	assert(#recipe.surface_conditions == 1, "restrict_to_planet should add exactly one condition")
	local condition = recipe.surface_conditions[1]
	assert(condition.property == property_name, "the condition uses the wrong property")
	assert(condition.min == 1 and condition.max == 1, "the condition should require the planet marker")

	-- Idempotence: a second identical call must not append a duplicate.
	PlanetsLib.restrict_to_planet(recipe, "funit-sc")
	assert(#recipe.surface_conditions == 1, "repeated restrict_to_planet calls must be idempotent")

	-- invert overrides the existing value instead of adding a contradictory condition.
	PlanetsLib.restrict_to_planet(recipe, "funit-sc", true)
	assert(#recipe.surface_conditions == 1, "invert must reuse the existing condition")
	assert(recipe.surface_conditions[1].min == 0 and recipe.surface_conditions[1].max == 0,
		"invert should set the condition value to 0")

	-- Prototype-table input.
	local recipe_from_prototype = {}
	PlanetsLib.restrict_to_planet(recipe_from_prototype, planet)
	assert(#recipe_from_prototype.surface_conditions == 1, "prototype input failed")
	assert(recipe_from_prototype.surface_conditions[1].property == property_name,
		"prototype input selected the wrong property")

	-- Unknown planets are rejected.
	assert(not pcall(PlanetsLib.restrict_to_planet, {}, "funit-missing-planet"),
		"restrict_to_planet must reject an unknown planet")

	-- Legacy restrict_to_surface returns an exact planet-str condition.
	local legacy = PlanetsLib.restrict_to_surface("funit-sc")
	assert(legacy.property == "planet-str", "restrict_to_surface used the wrong property")
	assert(legacy.min == legacy.max, "restrict_to_surface should lock an exact value")
	assert(
		legacy.min == PlanetsLib.planet_str.get_planet_str_double("funit-sc"),
		"restrict_to_surface used the wrong planet-str value"
	)
end)
results.record("surface_conditions", "SFC-DATA-1", ok, err)

return true
