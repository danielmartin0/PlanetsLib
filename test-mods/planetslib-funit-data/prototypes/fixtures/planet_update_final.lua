-- data-final-fixes fixture: PlanetsLib:update in data-final-fixes (native origins)
-- and the PlanetsLib:extend data-final-fixes guard.
local results = require("lib.results")

local ok, err = pcall(function()
	local star = data.raw["space-location"] and data.raw["space-location"]["star"]
	local parent
	if star then
		parent = { type = "space-location", name = "star" }
	else
		parent = { type = "planet", name = "funit-parent-str" }
	end

	local target = data.raw.planet["funit-planet-a"]
	assert(target, "funit-planet-a is missing")

	PlanetsLib:update({
		type = "planet",
		name = "funit-planet-a",
		orbit = { parent = parent, distance = 20, orientation = 0.3 },
	})

	assert(target.orbit.distance == 20 and target.orbit.orientation == 0.3,
		"the final-fixes orbit update was not applied")
	assert(target.origin, "data-final-fixes update should set a native origin")
	assert(target.distance == 20 and target.orientation == 0.3,
		"data-final-fixes update should keep the orbit distance/orientation")

	-- An invalid parent is still rejected.
	local bad_ok = pcall(function()
		PlanetsLib:update({
			type = "planet",
			name = "funit-planet-a",
			orbit = { parent = { type = "planet", name = "funit-missing-parent" }, distance = 1, orientation = 0 },
		})
	end)
	assert(not bad_ok, "an invalid parent should error in data-final-fixes")
end)
results.record("planet_update_final", "PLAN-9", ok, err)

local extend_ok, extend_err = pcall(function()
	local config = table.deepcopy(data.raw.planet["funit-planet-a"])
	config.name = "funit-extend-too-late"
	config.orbit = { parent = { type = "space-location", name = "star" }, distance = 1, orientation = 0 }
	local called, call_err = pcall(function() PlanetsLib:extend(config) end)
	assert(not called, "PlanetsLib:extend must be rejected during data-final-fixes")
	assert(tostring(call_err):find("before data-final-fixes", 1, true),
		"the data-final-fixes error should be explicit")
end)
results.record("planet_update_final", "PLAN-10", extend_ok, extend_err)

return true
