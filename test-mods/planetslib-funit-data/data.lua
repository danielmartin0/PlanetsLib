-- Data-stage entry point for the PlanetsLib FUnit data fixtures.
--
-- Development-only companion to PlanetsLib, used by the headless FUnit scenario
-- in tests/scenario. It exercises PlanetsLib's data-stage API inside pcall and
-- records the results into a mod-data prototype that the runtime scenario
-- asserts on.

data:extend({
	{
		type = "mod-data",
		name = "PlanetsLib-funit-results",
		data = {
			-- [suite name][check id] = { ok = boolean, err = string|nil }
			suite = {},
		},
	},
})

local manifest = require("prototypes.fixtures.manifest")
for _, fixture in ipairs(manifest.data) do
	require("prototypes.fixtures." .. fixture)
end
