local orbits = require("lib.orbits")
-- Force-set the position of planets and moons, in case other mods moved them:
local planets_with_orbits = orbits.get_planets_with_orbits(data.raw.planet)
for _, p in pairs(planets_with_orbits) do
    local distance, orientation = orbits.get_absolute_polar_position_from_orbit(p.orbit)
    p.distance = distance
    p.orientation = orientation
end

local spaceLocs = orbits.get_planets_with_orbits(data.raw["space-location"])
for _, p in pairs(spaceLocs) do
    local distance, orientation = orbits.get_absolute_polar_position_from_orbit(p.orbit)
    p.distance = distance
    p.orientation = orientation
end

require("prototypes.override-final.starmap")

for _, p in pairs(planets_with_orbits) do
    if p.sprite_only then
        data.raw.planet[p.name] = nil
    end
end

for _, p in pairs(spaceLocs) do
    if p.sprite_only then
        data.raw["space-location"][p.name] = nil
    end
end