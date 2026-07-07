require("prototypes.tiles")
require("prototypes.events")
local orbits = require("lib.orbits")
PlanetsLib = {}
PlanetsLib.current_stage = "data"
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
			on_entity_placed_on_planet_replacements = {
				--["planet-name"] = {
				-- ["entity-to-replace"] = "new-entity"
				--}
				 --Test data, replace with mod-data when script is confirmed to work.
					-- ["nauvis"] = { --If on planet (or "space-platform")
					-- 	["assembling-machine-1"] = "chemical-plant", --If chemical plant placed on Nauvis, replace with assembling-machine 2
					-- 	["assembling-machine-2"] = "chemical-plant",
					-- 	["assembling-machine-3"] = "chemical-plant", 
					-- 	["electric-furnace"] = "chemical-plant", 
					-- 	--["assembling-machine-1"] = "chemical-plant" --If chemical plant placed on Nauvis, replace with assembling-machine 2
					-- },
					-- ["space-platform"] = { --If on planet (or "space-platform")
					-- 	["chemical-plant"] = "assembling-machine-3" --If chemical plant placed on space platform, replace with assembling-machine 3
					-- },
				
			},
			planet_special_properties = { --Place to store arbitrary planet properties to avoid a proliferation of new mod-data objects.
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

