local orbits = require("lib.orbits")

if mods["space-age"] then
	orbits.ensure_all_locations_have_orbits()
	require("prototypes.override.rocket-silos")
end

require("prototypes.override.centrifuge")