local orbits = require("lib.orbits")

PlanetsLib = {}

require("api")
PlanetsLib.check_global_variables()
require("prototypes.vanilla-override.recipe-productivity-technology")

require("prototypes.mod-data")

if mods["space-age"] then
	require("prototypes.surface-property")
	require("prototypes.categories")
	require("prototypes.star")

	orbits.ensure_all_locations_have_orbits() -- We also call this in data-updates, but it's good to call it here as well so that if the vanilla planets are moved in data.lua (or before this code runs in data-updates.lua), we correctly recognize that their orbital children should be moved as well.
end

data:extend({
	{
		type = "mod-data",
		name = "Planetslib",
		data = {
			unlinked_prerequisites = {},
			planet_cargo_drop_whitelists = {
				all = {
					entity_types = {},
					item_names = {},
				},
			},
		},
	},
})
