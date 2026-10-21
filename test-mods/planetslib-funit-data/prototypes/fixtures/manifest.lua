-- Fixture manifest for the PlanetsLib FUnit data fixtures.
--
-- Each list holds fixture module names inside
-- test-mods/planetslib-funit-data/prototypes/fixtures/. They are required by
-- the matching stage entry point (data.lua / data-updates.lua /
-- data-final-fixes.lua). Every listed name must have a stub file, otherwise the
-- mod fails to load.

-- A base-only game has no star, space locations or surface conditions. The
-- fixtures below depend on those expansion features, so they are skipped when
-- Space Age is not active. The matching runtime suites make the same check.
local SPACE_AGE_ONLY = {
	planet_extend = true,
	planet_str_auto = true,
	planet_update = true,
	planet_update_final = true,
	orbit_native = true,
	ground_diggers_data = true,
	ground_diggers_late = true,
	rocket_parts_setup = true,
}

local function fixtures(list)
	local filtered = {}
	for _, name in ipairs(list) do
		if mods["space-age"] or not SPACE_AGE_ONLY[name] then
			filtered[#filtered + 1] = name
		end
	end
	return filtered
end

return {
	-- Required from data.lua.
	data = fixtures({
		"example",
		"planet_extend",
		"special_properties",
		"planet_str",
		"technology",
		"technology_productivity_setup",
		"surface_conditions",
		"mod_data",
		"achievements",
		"asteroids",
		"icons",
		"misc_global_checks",
		"misc_science_lab",
		"misc_visuals_setup",
		"entity_replacement_data",
		"ground_diggers_data",
		"rocket_parts_setup",
		"recipe_effects_setup",
	}),

	-- Required from data-updates.lua.
	data_updates = fixtures({ "example_updates", "planet_update" }),

	-- Required from data-final-fixes.lua.
	data_final_fixes = fixtures({
		"example_final_fixes",
		"planet_update_final",
		"special_properties_final",
		"planet_str_auto",
		"orbit_native",
		"ground_diggers_late",
		"misc_science_lab_final",
		"misc_visuals_final",
	}),
}
