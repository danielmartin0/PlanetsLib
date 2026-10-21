-- Data-stage fixture: public APIs that had no direct tests.
--
-- This fixture focuses on the backwards-compatibility helpers in api.lua and
-- the undocumented-but-supported technology icon helpers. It records results
-- for tests/suites/api_coverage.lua.

local results = require("lib.results")
local technology = require("__PlanetsLib__.lib.technology")

local SUITE = "api_coverage"
local TIERLIST = "PlanetsLib-tierlist"

local function record(id, fn)
	local ok, err = pcall(fn)
	results.record(SUITE, id, ok, err)
end

-- The tier list normally lives in the separate "PlanetsLib: Tiers" mod. Do not
-- overwrite it if it is installed; otherwise install a small test table so the
-- backwards-compatibility helpers have something real to read.
local tierlist_created = false
if not data.raw["mod-data"][TIERLIST] then
	data:extend({
		{
			type = "mod-data",
			name = TIERLIST,
			data_type = "table",
			data = {
				default = 3.25,
				planet = {},
				["space-location"] = {},
			},
		},
	})
	tierlist_created = true
end

local tierlist = data.raw["mod-data"][TIERLIST]
tierlist.data.default = tierlist.data.default or 3.25
tierlist.data.planet = tierlist.data.planet or {}
tierlist.data["space-location"] = tierlist.data["space-location"] or {}
tierlist.data.planet["funit-api-planet"] = 2
tierlist.data.planet["funit-api-zero"] = 0
tierlist.data["space-location"]["funit-api-location"] = 4
tierlist.data["space-location"]["funit-api-location-zero"] = 0
local default_tier = tierlist.data.default

-- API-1: get_planet_tier() reads the documented mod-data table and falls back
-- to its `default` value for unknown planets.
record("API-1", function()
	assert(tierlist_created or data.raw["mod-data"][TIERLIST], "the tier-list mod-data is missing")
	assert(
		PlanetsLib.get_planet_tier("funit-api-planet") == 2,
		"get_planet_tier() did not read the planet entry"
	)
	assert(
		PlanetsLib.get_planet_tier("funit-api-unknown-planet") == default_tier,
		"get_planet_tier() did not use the default tier"
	)
	assert(
		PlanetsLib.get_planet_tier("funit-api-zero") == 0,
		"get_planet_tier() treated a tier of 0 as missing and used the default"
	)
end)

-- API-2: get_space_location_tier() uses the "space-location" table and the same
-- fallback.
record("API-2", function()
	assert(
		PlanetsLib.get_space_location_tier("funit-api-location") == 4,
		"get_space_location_tier() did not read the space-location entry"
	)
	assert(
		PlanetsLib.get_space_location_tier("funit-api-unknown-location") == default_tier,
		"get_space_location_tier() did not use the default tier"
	)
	assert(
		PlanetsLib.get_space_location_tier("funit-api-location-zero") == 0,
		"get_space_location_tier() treated a tier of 0 as missing and used the default"
	)
end)

-- API-3: the compatibility helpers must not error when PlanetsLib: Tiers is not
-- installed. Temporarily remove the test prototype and restore it immediately.
record("API-3", function()
	local tierlist = data.raw["mod-data"][TIERLIST]
	assert(tierlist, "the tier-list mod-data is missing")
	data.raw["mod-data"][TIERLIST] = nil
	local ok, planet_tier, location_tier = pcall(function()
		return PlanetsLib.get_planet_tier("funit-api-planet"),
			PlanetsLib.get_space_location_tier("funit-api-location")
	end)
	data.raw["mod-data"][TIERLIST] = tierlist
	assert(ok, "the tier helpers errored when PlanetsLib: Tiers was absent: " .. tostring(planet_tier))
	assert(planet_tier == nil, "get_planet_tier() should return nil without a tier list")
	assert(location_tier == nil, "get_space_location_tier() should return nil without a tier list")
end)

-- API-4: the obsolete get_orbit_sprite() helper must fail with an explanation
-- instead of silently returning something that no longer works.
record("API-4", function()
	local ok, err = pcall(PlanetsLib.get_orbit_sprite, 10)
	assert(not ok, "get_orbit_sprite() must raise the documented obsolete error")
	assert(
		tostring(err):find("obsolete", 1, true),
		"get_orbit_sprite() error should explain that the function is obsolete"
	)
end)

-- API-5: technology_icons_moon() and its public alias produce the documented
-- moon discovery icon layout.
record("API-5", function()
	local shadowed = PlanetsLib.technology_icons_moon(
		"__base__/graphics/technology/automation.png",
		256,
		0.5
	)
	assert(#shadowed == 3, "technology_icons_moon(shadow_scale) should return three icons")
	assert(
		shadowed[1].icon == "__PlanetsLib__/graphics/icons/planet-technology.png",
		"the planet discovery symbol is missing"
	)
	assert(
		shadowed[#shadowed].icon == "__PlanetsLib__/graphics/icons/moon-technology-symbol.png",
		"the moon symbol did not replace the constant icon"
	)

	local plain = technology.technology_icon_moon(
		"__base__/graphics/technology/automation.png",
		256,
		nil
	)
	assert(#plain == 2, "technology_icon_moon() without a shadow should return two icons")
	assert(
		plain[#plain].icon == "__PlanetsLib__/graphics/icons/moon-technology-symbol.png",
		"technology_icon_moon() did not set the moon symbol"
	)
	assert(plain[1].icon_size == 256, "technology_icon_moon() did not set the icon size")
end)

return true
