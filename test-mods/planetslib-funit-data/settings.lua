-- Startup settings for the PlanetsLib FUnit data fixtures.
--
-- All fixtures are gated behind a startup boolean so the save can be loaded
-- with them disabled, and entity-replacement fixtures are bound to their own
-- boolean (as required by PlanetsLib.assign_entity_replacement's contract).

data:extend({
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "planetslib-funit-data-enable-fixtures",
		default_value = true,
		order = "a",
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "planetslib-funit-data-enable-entity-replacement-fixture",
		default_value = true,
		order = "b",
	},
})
