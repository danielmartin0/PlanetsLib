-- data-final-fixes fixture: orbit conversion and native `origin` handling.
--
-- Runs after PlanetsLib's own final-fixes (so all locations already have orbits
-- and, under Space Age, native origins). It creates a fresh prototype and drives
-- lib/orbits directly, which can only be done in the data stage.
local results = require("lib.results")

package.loaded["util"] = require("__core__.lualib.util")
package.loaded["lib.lib"] = require("__PlanetsLib__.lib.lib")
local orbits = require("__PlanetsLib__.lib.orbits")

local EPSILON = 1e-6

local function approx(a, b)
	return math.abs(a - b) <= EPSILON
end

local function rect(distance, orientation)
	return distance * math.sin(orientation * 2 * math.pi), -distance * math.cos(orientation * 2 * math.pi)
end

local function polar(x, y)
	return math.sqrt(x * x + y * y), (0.25 + math.atan2(y, x) / (2 * math.pi)) % 1
end

local function create_planet(name)
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = name
	planet.surface_properties = {}
	planet.orbit = nil
	-- A planet prototype always needs native distance/orientation, even when
	-- the test is asserting that a location without an orbit gains no origin.
	planet.distance = 0
	planet.orientation = 0
	planet.origin = nil
	data:extend({ planet })
	return data.raw.planet[name]
end

-- ORB-5: a star parent is a pass-through.
local star_ok, star_err = pcall(function()
	local distance, orientation = orbits.get_absolute_polar_position_from_orbit({
		parent = { type = "space-location", name = "star" },
		distance = 7,
		orientation = 0.3,
	})
	assert(distance == 7 and orientation == 0.3, "a star parent should pass distance/orientation through")
end)
results.record("orbit_native", "ORB-5", star_ok, star_err)

-- ORB-6: composition through a real, non-star parent matches rectangular addition.
local compose_ok, compose_err = pcall(function()
	local parent = data.raw.planet["funit-parent-str"]
	assert(parent, "funit-parent-str is missing")
	assert(parent.distance and parent.orientation, "the parent has no absolute position")

	local child_orbit = {
		parent = { type = "planet", name = "funit-parent-str" },
		distance = 5,
		orientation = 0.2,
	}
	local distance, orientation = orbits.get_absolute_polar_position_from_orbit(child_orbit)

	local px, py = rect(parent.distance, parent.orientation)
	local ox, oy = rect(child_orbit.distance, child_orbit.orientation)
	local expected_distance, expected_orientation = polar(px + ox, py + oy)

	assert(approx(distance, expected_distance), string.format("absolute distance disagrees with the rectangular convention: got %.9f, expected %.9f", distance, expected_distance))
	assert(approx(orientation, expected_orientation), string.format("absolute orientation disagrees with the rectangular convention: got %.9f, expected %.9f", orientation, expected_orientation))
end)
results.record("orbit_native", "ORB-6", compose_ok, compose_err)

-- ORB-7: missing parents use placeholders when asked, and error otherwise.
local missing_ok, missing_err = pcall(function()
	local orbit = {
		parent = { type = "planet", name = "funit-missing-parent" },
		distance = 1,
		orientation = 0.5,
	}

	local distance, orientation = orbits.get_absolute_polar_position_from_orbit(orbit, true)
	assert(
		distance == orbits.SPECIAL_PLACEHOLDERS_FOR_MISSING_PARENT.distance
			and orientation == orbits.SPECIAL_PLACEHOLDERS_FOR_MISSING_PARENT.orientation,
		"missing parents should return the special placeholder values"
	)
	assert(not pcall(orbits.get_absolute_polar_position_from_orbit, orbit),
		"a missing parent should error when placeholders are not requested")
end)
results.record("orbit_native", "ORB-7", missing_ok, missing_err)

-- ORB-8: unsupported parent types are rejected.
local type_ok, type_err = pcall(function()
	assert(
		not pcall(orbits.get_absolute_polar_position_from_orbit, {
			parent = { type = "item", name = "iron-plate" },
			distance = 1,
			orientation = 0,
		}),
		"an unsupported parent type should error"
	)
end)
results.record("orbit_native", "ORB-8", type_ok, type_err)

-- ORB-9: locations_ordered_by_orbits yields parents before children.
local order_ok, order_err = pcall(function()
	local child = data.raw.planet["funit-child-nostr"]
	local parent = data.raw.planet["funit-parent-nostr"]
	assert(child and parent, "the parent/child test planets are missing")

	local ordered = orbits.locations_ordered_by_orbits({ child, parent })
	local index = {}
	for i, location in ipairs(ordered) do
		index[location.name] = i
	end
	assert(index["funit-parent-nostr"] and index["funit-child-nostr"], "the ordered list dropped a location")
	assert(index["funit-parent-nostr"] < index["funit-child-nostr"], "the parent must come before the child")
end)
results.record("orbit_native", "ORB-9", order_ok, order_err)

-- ORB-10: is_parent walks the whole orbit chain.
local is_parent_ok, is_parent_err = pcall(function()
	local child = data.raw.planet["funit-child-nostr"]
	local direct = data.raw.planet["funit-parent-nostr"]
	local unrelated = data.raw.planet["funit-parent-str"]

	assert(orbits.is_parent(direct, child), "the direct parent was not detected")
	assert(not orbits.is_parent(unrelated, child), "an unrelated planet was reported as a parent")
	assert(not orbits.is_parent(child, child), "a location cannot be its own parent")

	local star = data.raw["space-location"] and data.raw["space-location"]["star"]
	if star then
		assert(orbits.is_parent(star, child), "the star is an ancestor of every location")
	end
end)
results.record("orbit_native", "ORB-10", is_parent_ok, is_parent_err)

-- ORB-11: ensure_all_locations_have_orbits gives every location a parent.
local ensure_ok, ensure_err = pcall(function()
	orbits.ensure_all_locations_have_orbits()
	for _, prototype_type in ipairs({ "space-location", "planet" }) do
		for _, location in pairs(data.raw[prototype_type]) do
			assert(location.orbit and location.orbit.parent, location.name .. " has no orbit parent")
		end
	end
end)
results.record("orbit_native", "ORB-11", ensure_ok, ensure_err)

-- ORB-12..15: apply_native_orbit.
local native_ok, native_err = pcall(function()
	local parent = data.raw.planet["funit-parent-str"]
	local parent_x, parent_y = orbits.get_absolute_position(parent)

	local native = create_planet("funit-native-a")
	native.orbit = {
		parent = { type = "planet", name = "funit-parent-str" },
		distance = 5,
		orientation = 0.25,
	}
	-- Place it at the absolute position that corresponds to its orbit.
	local offset_x, offset_y = rect(native.orbit.distance, native.orbit.orientation)
	native.distance, native.orientation = polar(parent_x + offset_x, parent_y + offset_y)

	orbits.apply_native_orbit(native)
	assert(native.origin, "apply_native_orbit did not set an origin")
	assert(approx(native.origin.x, parent_x) and approx(native.origin.y, parent_y),
		"the origin should be the parent's absolute position")
	assert(approx(native.distance, native.orbit.distance), string.format("distance was not rebased onto the origin: got %.9f, expected %.9f", native.distance, native.orbit.distance))
	assert(approx(native.orientation, native.orbit.orientation), string.format("orientation was not rebased onto the origin: got %.9f, expected %.9f", native.orientation, native.orbit.orientation))

	-- A pre-existing origin makes the call a no-op.
	native.origin = { x = 9, y = -9 }
	orbits.apply_native_orbit(native)
	assert(native.origin.x == 9 and native.origin.y == -9, "apply_native_orbit must not modify an existing origin")

	-- orbit.sprite forces the orbit to be drawn.
	local sprite_planet = create_planet("funit-native-sprite")
	sprite_planet.orbit = {
		parent = { type = "planet", name = "funit-parent-str" },
		distance = 6,
		orientation = 0.1,
		sprite = "funit/orbit.png",
	}
	sprite_planet.distance, sprite_planet.orientation = 6, 0.1
	orbits.apply_native_orbit(sprite_planet)
	assert(sprite_planet.draw_orbit == true, "orbit.sprite should enable draw_orbit")

	-- No orbit: nothing happens.
	local plain = create_planet("funit-native-plain")
	orbits.apply_native_orbit(plain)
	assert(plain.origin == nil, "a location without an orbit must not gain an origin")

	-- A missing parent raises an error.
	local broken = create_planet("funit-native-broken")
	broken.orbit = {
		parent = { type = "planet", name = "funit-missing-parent" },
		distance = 1,
		orientation = 0,
	}
	assert(not pcall(orbits.apply_native_orbit, broken),
		"apply_native_orbit should error when the parent is missing")
end)
results.record("orbit_native", "ORB-12", native_ok, native_err)

-- ORB-16: the star survives and stays hidden (Space Age only).
local star_survival_ok, star_survival_err = pcall(function()
	if mods["space-age"] then
		local star = data.raw["space-location"]["star"]
		assert(star, "the star space-location was removed")
		assert(star.hidden == true, "the star should stay hidden")
		-- data-final-fixes deliberately clears sprite_only so the star survives
		-- the sprite_only cleanup and remains a real (hidden) location.
		assert(star.sprite_only == nil, string.format("the star should no longer be sprite_only (got %s)", tostring(star.sprite_only)))
	end
end)
results.record("orbit_native", "ORB-16", star_survival_ok, star_survival_err)

return true
