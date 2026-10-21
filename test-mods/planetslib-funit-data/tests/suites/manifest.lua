-- Ordered list of suite module names (relative to tests/suites/ in the
-- planetslib-funit-data mod). The scenario control.lua requires each one as
-- "__planetslib-funit-data__.tests.suites.<name>" in this order and calls the
-- returned function(runner) with the shared FUnit runner.
--
-- To add a suite: create suites/<name>.lua returning
--   return function(runner) runner.test("ID-1 ...", function() ... end) end
-- and append "<name>" below. A stub file must exist for every name listed here,
-- otherwise the whole scenario fails to load.

return {
	order = {
		-- Pure, runtime-stage suites (require __PlanetsLib__.lib.* directly).
		"orbits",
		"lib_helpers",
		"planet_str",
		"recipe",
		-- Data/control-stage suites (assert on prototypes and on the results
		-- bag produced by test-mods/planetslib-funit-data).
		"planet",
		"orbit_conversion",
		"special_properties",
		"technology",
		"technology_productivity",
		"api_coverage",
		"surface_conditions",
		"mod_data",
		"achievements",
		"misc_global_checks",
		"misc_science_lab",
		"misc_visuals",
		"entity_replacement_data",
		"ground_diggers_data",
		-- Stateful suites driven through the planetslib_funit remote interface.
		"entity_replacement_runtime",
		"entity_replacement_migration",
		"ground_diggers_runtime",
		"rocket_parts",
		"cargo_pods",
		"unreachable_techs",
		"recipe_effects",
		"remote_interfaces",
		-- Data-fixture smoke tests (see test-mods/planetslib-funit-data).
		"smoke",
	},
}
