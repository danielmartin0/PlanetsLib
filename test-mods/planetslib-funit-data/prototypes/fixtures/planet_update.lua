-- data-updates fixture: PlanetsLib:update during data/data-updates.
local results = require("lib.results")

local ok, err = pcall(function()
	local child = data.raw.planet["funit-child-str"]
	assert(child, "the data-stage fixture did not create funit-child-str")
	local before_distance, before_orientation = child.distance, child.orientation

	PlanetsLib:update({
		type = "planet",
		name = "funit-child-str",
		orbit = {
			parent = { type = "planet", name = "funit-parent-str" },
			distance = 12,
			orientation = 0.6,
		},
	})

	assert(child.orbit.distance == 12 and child.orbit.orientation == 0.6, "the orbit field was not replaced")
	assert(
		child.distance ~= before_distance or child.orientation ~= before_orientation,
		"the absolute position was not recalculated"
	)
	assert(child.distance > 0, "the recalculated distance should be positive")

	-- Re-parent to a different planet.
	PlanetsLib:update({
		type = "planet",
		name = "funit-child-str",
		orbit = {
			parent = { type = "planet", name = "funit-parent-nostr" },
			distance = 3,
			orientation = 0.9,
		},
	})
	assert(child.orbit.parent.name == "funit-parent-nostr", "re-parenting failed")
end)
results.record("planet_update", "PLAN-7", ok, err)

-- Error cases.
local error_checks = {
	{ id = "PLAN-8a", build = function(c)
		c.name = nil
	end },
	{ id = "PLAN-8b", build = function(c)
		c.type = "item"
	end },
	{ id = "PLAN-8c", build = function(c)
		c.distance = 5
	end },
	{ id = "PLAN-8d", build = function(c)
		c.orientation = 0.5
	end },
	{ id = "PLAN-8e", build = function(c)
		c.orbit = { parent = { type = "item", name = "iron-plate" }, distance = 1, orientation = 0 }
	end },
	{ id = "PLAN-8f", build = function(c)
		c.name = "funit-missing-planet"
	end },
	{ id = "PLAN-8g", build = function(c)
		c.special_properties = { a = 1 }
	end },
}
for _, check in ipairs(error_checks) do
	local config = {
		type = "planet",
		name = "funit-child-str",
		orbit = {
			parent = { type = "planet", name = "funit-parent-str" },
			distance = 5,
			orientation = 0.25,
		},
	}
	check.build(config)
	local check_ok, check_err = pcall(function() PlanetsLib:update(config) end)
	results.record(
		"planet_update",
		check.id,
		(not check_ok) and true or false,
		check_ok and ("expected PlanetsLib:update to reject config " .. check.id) or check_err
	)
end

-- PLAN-13: update accepts a batch of configs and applies non-orbit fields.
local batch_ok, batch_err = pcall(function()
	local color = { r = 0.125, g = 0.25, b = 0.5 }
	local child = data.raw.planet["funit-child-str"]
	local parent = data.raw.planet["funit-parent-nostr"]
	assert(child and parent, "the PLAN-13 test planets are missing")
	local child_parent = child.orbit and child.orbit.parent and child.orbit.parent.name

	PlanetsLib:update({
		{ type = "planet", name = "funit-child-str", map_color = color },
		{ type = "planet", name = "funit-parent-nostr", map_color = color },
	})

	assert(
		child.map_color
			and child.map_color.r == 0.125
			and child.map_color.g == 0.25
			and child.map_color.b == 0.5,
		"the first batch config did not apply map_color"
	)
	assert(parent.map_color and parent.map_color.b == 0.5, "the second batch config did not apply map_color")
	assert(
		child.orbit and child.orbit.parent and child.orbit.parent.name == child_parent,
		"a non-orbit update changed the child's orbit"
	)
end)
results.record("planet_update", "PLAN-13", batch_ok, batch_err)

return true
