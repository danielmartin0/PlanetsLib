PlanetsLib = {}

require("api")
require("prototypes.vanilla-override.recipe-productivity-technology")
if mods["space-age"] then
	require("prototypes.surface-property")
	require("prototypes.categories")
	require("prototypes.star")
	require("prototypes.mod-data")
end

data:extend({ {
	type = "mod-data",
	name = "Planetslib",
	data = {
		unlinked_prerequisites = {},
	},
} })
