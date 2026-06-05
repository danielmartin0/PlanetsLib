require("prototypes.tiles")

local orbits = require("lib.orbits")
PlanetsLib = {}

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
			rocket_silo_lift_multipliers = {
				--[number(str)] == table {base_silo = replacement_silo}
			},
			planet_data = { --Place to store arbitrary planet properties to avoid a proliferation of new mod-data objects.
				--[planet name] = table {incl. rocket_lift_multiplier}
			}
		},
	},
})

PlanetsLib.constants = data.raw["mod-data"].Planetslib.data



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

