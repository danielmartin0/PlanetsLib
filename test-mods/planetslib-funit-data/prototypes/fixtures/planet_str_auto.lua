-- data-final-fixes fixture: PlanetsLib auto-assigns planet-str to every planet
-- that has surface_properties but no explicit planet-str. This only runs when
-- Space Age is active (see data-final-fixes.lua in PlanetsLib).
local results = require("lib.results")

local ok, err = pcall(function()
	local planet = data.raw.planet["fauto"]
	assert(planet, "planet 'fauto' was not created by the data-stage fixture")

	if mods["space-age"] then
		assert(planet.surface_properties, "fauto has no surface_properties")
		assert(planet.surface_properties["planet-str"] ~= nil, "PlanetsLib did not auto-assign planet-str")
		assert(PlanetsLib.planet_str.get_planet_str(planet) == "fauto", "auto planet-str decoded incorrectly")
	end
end)
results.record("planet_str_auto", "PSTR-4", ok, err)

return true
