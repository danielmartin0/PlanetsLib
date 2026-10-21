-- Data-stage fixture: PlanetsLib:extend, borrow_music and set_default_import_location.
local results = require("lib.results")

-- Build a full, valid planet prototype from vanilla nauvis and strip the fields
-- PlanetsLib:extend() recomputes or validates.
local function base_config(name)
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = name
	planet.type = "planet"
	planet.surface_properties = {}
	planet.orbit = nil
	planet.distance = nil
	planet.orientation = nil
	planet.origin = nil
	return planet
end

local function with_star_orbit(config, distance, orientation)
	config.orbit = {
		parent = { type = "space-location", name = "star" },
		distance = distance,
		orientation = orientation,
	}
	return config
end

-- PLAN-1..4: valid configs and the parent planet-str copy.
local ok, err = pcall(function()
	local planet_a = with_star_orbit(base_config("funit-planet-a"), 10, 0.25)
	planet_a.orbit.draw_orbit = true
	PlanetsLib:extend(planet_a)

	local prototype_a = data.raw.planet["funit-planet-a"]
	assert(prototype_a, "PlanetsLib:extend did not create the planet")
	assert(prototype_a.draw_orbit == true, "draw_orbit was not copied from the orbit field")
	assert(prototype_a.distance == 10 and prototype_a.orientation == 0.25,
		"distance/orientation were not derived from the orbit")
	assert(prototype_a.orbit and prototype_a.orbit.parent.name == "star", "orbit field was not stored")

	-- A parent planet with an explicit planet-str is copied to its children.
	local parent_str = with_star_orbit(base_config("funit-parent-str"), 50, 0.1)
	PlanetsLib:extend(parent_str)
	PlanetsLib.planet_str.set_planet_str("funit-parent-str", "paren1")

	local child_str = base_config("funit-child-str")
	child_str.orbit = { parent = { type = "planet", name = "funit-parent-str" }, distance = 5, orientation = 0.2 }
	PlanetsLib:extend(child_str)
	local prototype_child = data.raw.planet["funit-child-str"]
	assert(prototype_child, "child planet was not created")
	assert(
		prototype_child.surface_properties["parent-planet-str"]
			== PlanetsLib.planet_str.get_planet_str_double("funit-parent-str"),
		"parent-planet-str was not copied from the parent"
	)

	-- A parent without an explicit planet-str must not crash.
	local parent_nostr = with_star_orbit(base_config("funit-parent-nostr"), 60, 0.3)
	PlanetsLib:extend(parent_nostr)
	local child_nostr = base_config("funit-child-nostr")
	child_nostr.orbit = { parent = { type = "planet", name = "funit-parent-nostr" }, distance = 5, orientation = 0.4 }
	PlanetsLib:extend(child_nostr)
	local prototype_nostr = data.raw.planet["funit-child-nostr"]
	assert(prototype_nostr, "child of a planet without planet-str was not created")
	assert(
		prototype_nostr.surface_properties == nil
			or prototype_nostr.surface_properties["parent-planet-str"] == nil,
		"parent-planet-str should not be set when the parent has no planet-str"
	)

	-- draw_orbit is not set when the orbit does not request it.
	assert(prototype_a.draw_orbit == true, "sanity check failed")
	local planet_b = with_star_orbit(base_config("funit-planet-b"), 11, 0.5)
	PlanetsLib:extend(planet_b)
	assert(data.raw.planet["funit-planet-b"].draw_orbit == nil, "draw_orbit should stay unset by default")
end)
results.record("planet_extend", "PLAN-1", ok, err)

-- PLAN-5: validation errors.
local error_checks = {
	{ id = "PLAN-5a", label = "missing orbit", build = function(c)
		c.orbit = nil
	end },
	{ id = "PLAN-5b", label = "missing orbit parent", build = function(c)
		c.orbit = {}
	end },
	{ id = "PLAN-5c", label = "non-space-location parent", build = function(c)
		c.orbit = { parent = { type = "item", name = "iron-plate" } }
	end },
	{ id = "PLAN-5d", label = "distance field", build = function(c)
		c.orbit = { parent = { type = "space-location", name = "star" }, distance = 1, orientation = 0 }
		c.distance = 1
	end },
	{ id = "PLAN-5e", label = "orientation field", build = function(c)
		c.orbit = { parent = { type = "space-location", name = "star" }, distance = 1, orientation = 0 }
		c.orientation = 0
	end },
	{ id = "PLAN-5f", label = "non-space-location prototype", build = function(c)
		c.type = "item"
		c.orbit = { parent = { type = "space-location", name = "star" }, distance = 1, orientation = 0 }
	end },
	{ id = "PLAN-5g", label = "special_properties field", build = function(c)
		c.orbit = { parent = { type = "space-location", name = "star" }, distance = 1, orientation = 0 }
		c.special_properties = { a = 1 }
	end },
}
for _, check in ipairs(error_checks) do
	local config = with_star_orbit(base_config("funit-extend-error"), 1, 0)
	check.build(config)
	local check_ok, check_err = pcall(function() PlanetsLib:extend(config) end)
	results.record(
		"planet_extend",
		check.id,
		(not check_ok) and true or false,
		check_ok and ("expected PlanetsLib:extend to reject " .. check.label) or check_err
	)
end

-- PLAN-6: borrow_music and set_default_import_location.
local music_ok, music_err = pcall(function()
	local template
	for _, music in pairs(data.raw["ambient-sound"]) do
		template = music
		break
	end
	assert(template, "no ambient-sound prototype available to copy")

	local track = table.deepcopy(template)
	track.name = "funit-music-track"
	track.planets = { "funit-parent-str" }
	track.surface_names = nil
	track.play_on_all_surfaces = nil
	data:extend({ track })

	local source = "funit-parent-str"
	local target = "funit-child-str"
	local track_prototype = data.raw["ambient-sound"]["funit-music-track"]
	local original_planet_count = #track_prototype.planets

	-- In Factorio 2.1 a multi-planet ambient sound is updated in place.
	PlanetsLib.borrow_music(source, target)
	assert(#track_prototype.planets == original_planet_count + 1,
		"borrow_music did not add the target planet to the existing track")
	assert(track_prototype.planets[#track_prototype.planets] == target, "the wrong planet was added")

	-- Same source and target is a no-op.
	PlanetsLib.borrow_music(source, source)

	-- A modifier function forces a copied track.
	PlanetsLib.borrow_music(source, "funit-planet-b", {
		modifier_function = function(copied)
			copied.planets = { "funit-planet-b", "nauvis" }
		end,
	})
	local copied = data.raw["ambient-sound"]["funit-music-track-funit-planet-b"]
	assert(copied, "borrow_music with a modifier did not copy the track")
	assert(#copied.planets == 2 and copied.planets[2] == "nauvis",
		"the modifier function was not applied")

	-- track_types filters the copied tracks.
	PlanetsLib.borrow_music(source, "funit-planet-a", {
		track_types = { "funit-nonexistent-track-type" },
		modifier_function = function(copied) end,
	})
	assert(data.raw["ambient-sound"]["funit-music-track-funit-planet-a"] == nil,
		"the track_types filter was ignored")

	-- Invalid arguments.
	assert(not pcall(PlanetsLib.borrow_music, "funit-not-a-planet", target), "a bad source should error")
	assert(
		not pcall(PlanetsLib.borrow_music, source, target, { modifier_function = function(a, b) return a end }),
		"a two-argument modifier_function should error"
	)

	-- set_default_import_location
	PlanetsLib.set_default_import_location("iron-plate", "funit-planet-a")
	assert(data.raw.item["iron-plate"].default_import_location == "funit-planet-a",
		"set_default_import_location did not set the field")
	assert(not pcall(PlanetsLib.set_default_import_location, "funit-missing-item", "funit-planet-a"),
		"set_default_import_location should error for missing items")
end)
results.record("planet_extend", "PLAN-6", music_ok, music_err)

-- PLAN-14: borrow_music accepts a prototype table as the source and copying to
-- the space platform produces a track without a planet/surface list.
local platform_ok, platform_err = pcall(function()
	local source = data.raw.planet["funit-parent-str"]
	assert(source, "funit-parent-str is missing")
	local source_track = data.raw["ambient-sound"]["funit-music-track"]
	assert(source_track, "the fixture music track is missing")
	local source_planet_count = #source_track.planets

	PlanetsLib.borrow_music(source, "space-platform")
	local copied = data.raw["ambient-sound"]["funit-music-track-space-platform"]
	assert(copied, "borrow_music did not copy the track to the space platform")
	assert(copied.planets == nil, "a space-platform track must not keep a planets list")
	assert(copied.surface_names == nil, "a space-platform track must not keep surface_names")
	assert(
		#source_track.planets == source_planet_count,
		"copying a track to the space platform mutated the source track"
	)
end)
results.record("planet_extend", "PLAN-14", platform_ok, platform_err)

return true
