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

return true
