-- Data-stage fixture: planet-string setting/getting.
--
-- Only strings up to 6 bytes are round-trip safe: the encoding packs bytes into
-- a double, and a double only has 53 bits of integer precision. 7-8 byte
-- strings lose their low-order bytes (recorded as a known limitation in
-- test-mods/planetslib-funit-data/AGENTS.md).
local results = require("lib.results")

-- The planet-str surface property only exists with Space Age; a base-only game
-- cannot assign surface properties at all.
if not mods["space-age"] then
	results.skip("planet_str", "PSTR-3", "space-age not active; planet-str fixtures are skipped")
	results.skip("planet_str_auto", "PSTR-4", "space-age not active; planet-str fixtures are skipped")
	return true
end

local ps = PlanetsLib.planet_str

local function create_planet(name)
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = name
	planet.surface_properties = nil
	planet.orbit = nil
	data:extend({ planet })
	return data.raw.planet[name]
end

local ok, err = pcall(function()
	local object_planet = create_planet("funit-a")

	ps.set_planet_str(object_planet, "abc123")
	assert(object_planet.surface_properties, "set_planet_str did not create surface_properties")
	assert(
		object_planet.surface_properties["planet-str"] == 56290669978209,
		"set_planet_str stored the wrong encoded value"
	)
	assert(ps.get_planet_str(object_planet) == "abc123", "object round-trip failed")

	-- Name-based overload overwrites the existing value.
	ps.set_planet_str("funit-a", "xyz12")
	assert(ps.get_planet_str("funit-a") == "xyz12", "name-based set/get failed")
	assert(
		ps.get_planet_str_double("funit-a") == 215578474872,
		"get_planet_str_double did not return the encoded value"
	)

	-- Planets without an explicit value fall back to the first 8 name chars.
	-- Keep this name within the 6-byte round-trip-safe range; 7-8 byte names
	-- are lossy (see the file header and the documented limitation).
	local fallback = create_planet("funit6")
	assert(ps.get_planet_str(fallback) == "funit6", "fallback should be the first 8 characters of the name")
	assert(type(ps.get_planet_str_double(fallback)) == "number", "fallback double should be a number")

	-- Long names must use the same truncation in both fallbacks. Before this
	-- regression test, get_planet_str_double() encoded the full name and threw
	-- the "longer than 8 characters" assertion. The 8-byte result itself is
	-- lossy, so assert agreement rather than a literal decoded string.
	local lib = require("__PlanetsLib__.lib.lib")
	local long_fallback = create_planet("funit-long-name")
	local expected_double = lib.encode_string_to_double("funit-lo")
	assert(
		ps.get_planet_str(long_fallback) == "funit-lo",
		"long-name fallback should be the first 8 characters"
	)
	assert(
		ps.get_planet_str_double(long_fallback) == expected_double,
		"get_planet_str_double long-name fallback does not encode the truncated name"
	)

	local ok_long = pcall(ps.set_planet_str, object_planet, "123456789")
	assert(not ok_long, "set_planet_str must reject strings longer than 8 characters")

	local ok_unknown_set = pcall(ps.set_planet_str, "funit-missing", "x")
	assert(not ok_unknown_set, "set_planet_str must reject an unknown planet name")

	local ok_unknown_get = pcall(ps.get_planet_str, "funit-missing")
	assert(not ok_unknown_get, "get_planet_str must reject an unknown planet name")

	-- Created for the data-final-fixes fixture: PlanetsLib auto-fills a
	-- planet-str when surface_properties exists but the property is missing.
	local auto = create_planet("fauto")
	auto.surface_properties = {}
end)
results.record("planet_str", "PSTR-3", ok, err)

return true
