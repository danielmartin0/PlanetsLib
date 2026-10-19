-- Fixture manifest for the PlanetsLib FUnit data fixtures.
--
-- Each list holds fixture module names inside
-- test-mods/planetslib-funit-data/prototypes/fixtures/. They are required by
-- the matching stage entry point (data.lua / data-updates.lua /
-- data-final-fixes.lua). Every listed name must have a stub file, otherwise the
-- mod fails to load.

return {
	-- Required from data.lua.
	data = {
		"example",
		"planet_extend",
		"special_properties",
		"planet_str",
		"technology",
		"technology_productivity_setup",
		"surface_conditions",
		"mod_data",
		"achievements",
		"icons",
		"misc_global_checks",
		"misc_science_lab",
		"misc_visuals_setup",
		"entity_replacement_data",
		"ground_diggers_data",
		"rocket_parts_setup",
		"recipe_effects_setup",
	},

	-- Required from data-updates.lua.
	data_updates = { "example_updates", "planet_update" },

	-- Required from data-final-fixes.lua.
	data_final_fixes = {
		"example_final_fixes",
		"planet_update_final",
		"special_properties_final",
		"planet_str_auto",
		"orbit_native",
		"ground_diggers_late",
		"misc_science_lab_final",
		"misc_visuals_final",
	},
}
