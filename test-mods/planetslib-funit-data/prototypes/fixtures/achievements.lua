-- Data-stage fixture: visit_planet_achievement prototype construction.
local results = require("lib.results")

local ok, err = pcall(function()
	local nauvis = data.raw.planet["nauvis"]
	assert(nauvis, "nauvis is missing")

	local achievement = PlanetsLib.visit_planet_achievement(nauvis, "funit/achievement.png")
	assert(achievement.type == "change-surface-achievement", "wrong achievement type")
	assert(achievement.name == "visit-nauvis", "wrong achievement name")
	assert(achievement.surface == "nauvis", "the achievement should target the planet's surface")
	assert(achievement.icon == "funit/achievement.png", "the icon was not copied")
	assert(achievement.icon_size == 128, "the default icon size should be 128")
	assert(achievement.order == "a[progress]-g[visit-planet]-e[nauvis]", "wrong achievement order")
	assert(achievement.localised_name[1] == "achievement-name.visit-planet", "wrong localised name key")
	assert(achievement.localised_description[1] == "achievement-description.visit-planet",
		"wrong localised description key")

	local custom = PlanetsLib.visit_planet_achievement(nauvis, "funit/achievement.png", 64)
	assert(custom.icon_size == 64, "a custom icon size was ignored")

	-- Invalid inputs raise errors.
	assert(not pcall(PlanetsLib.visit_planet_achievement, "nauvis", "funit/achievement.png"),
		"a planet name string should be rejected")
	assert(not pcall(PlanetsLib.visit_planet_achievement, nauvis, nil),
		"a nil icon should be rejected")
	assert(not pcall(PlanetsLib.visit_planet_achievement, nauvis, 123),
		"a non-string icon should be rejected")

	-- Space locations are accepted too.
	local star = data.raw["space-location"] and data.raw["space-location"]["star"]
	if star then
		local star_achievement = PlanetsLib.visit_planet_achievement(star, "funit/achievement.png")
		assert(star_achievement.name == "visit-star", "space-location achievements are named incorrectly")
	end
end)
results.record("achievements", "ACH-1", ok, err)

return true
