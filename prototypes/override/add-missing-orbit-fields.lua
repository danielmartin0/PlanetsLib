for _, type in pairs({ "space-location", "planet" }) do
	for _, location in pairs(data.raw[type]) do
		if
			not (
				location.orbit
				and location.orbit.parent
				and location.orbit.distance
				and (location.orbit.orientation or location.orbit.distance == 0)
			)
		then
			-- This has no effect on PlanetsLib itself, as we use the position and orientation directly in data-final-fixes.
			location.orbit = {
				parent = {
					type = "space-location",
					name = "star",
				},
				distance = location.distance,
				orientation = location.orientation,
			}
		end
	end
end

-- Disabled as the vanilla orbits are sufficient:
-- data.raw["planet"]["vulcanus"].orbit.sprite = {
-- 	type = "sprite",
-- 	filename = "__PlanetsLib__/graphics/orbits/orbit_vulcanus.png",
-- 	size = 640,
-- }
-- data.raw["planet"]["nauvis"].orbit.sprite = {
-- 	type = "sprite",
-- 	filename = "__PlanetsLib__/graphics/orbits/orbit_nauvis.png",
-- 	size = 960,
-- }
-- data.raw["planet"]["gleba"].orbit.sprite = {
-- 	type = "sprite",
-- 	filename = "__PlanetsLib__/graphics/orbits/orbit_gleba.png",
-- 	size = 1280,
-- }
-- data.raw["planet"]["fulgora"].orbit.sprite = {
-- 	type = "sprite",
-- 	filename = "__PlanetsLib__/graphics/orbits/orbit_fulgora.png",
-- 	size = 1600,
-- }
-- data.raw["planet"]["aquilo"].orbit.sprite = {
-- 	type = "sprite",
-- 	filename = "__PlanetsLib__/graphics/orbits/orbit_aquilo.png",
-- 	size = 2240,
-- }
-- data.raw["space-location"]["solar-system-edge"].orbit.sprite = {
-- 	type = "sprite",
-- 	filename = "__PlanetsLib__/graphics/orbits/orbit_solar-system-edge.png",
-- 	size = 3200,
-- }
