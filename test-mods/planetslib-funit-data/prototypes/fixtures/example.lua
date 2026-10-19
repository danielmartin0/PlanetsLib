-- Worked example of a data-stage fixture.
--
-- Fixtures call PlanetsLib's data-stage API inside pcall and record the outcome
-- into the shared "PlanetsLib-funit-results" mod-data prototype. A data-stage
-- error would otherwise crash the whole prototype load, so wrapping in pcall is
-- what lets the runtime FUnit report show a failure instead.

local results = require("lib.results")

if not settings.startup["planetslib-funit-data-enable-fixtures"].value then
	results.record("suite", "example-disabled", true, "fixtures disabled by startup setting")
	return
end

-- Example 1: exercise PlanetsLib.assign_entity_replacement(). This registers an
-- "if placed on planet X, replace entity with Y" rule that the runtime
-- entity-replacement suite can drive through the planetslib_funit remote
-- interface. It must be bound to a startup boolean so the save stays loadable.
local ok, err = pcall(function()
	PlanetsLib.assign_entity_replacement(
		"nauvis",
		"iron-chest",
		"steel-chest",
		"planetslib-funit-data-enable-entity-replacement-fixture"
	)
end)
results.record("suite", "example-assign-entity-replacement", ok, err)

-- Example 2: a purely computational data API.
local sort_ok, sort_err = pcall(function()
	local sorted = PlanetsLib.sort_science_pack_names({
		"chemical-science-pack",
		"automation-science-pack",
		"logistic-science-pack",
	})
	assert(type(sorted) == "table", "sort_science_pack_names did not return a table")
	assert(#sorted == 3, "sort_science_pack_names changed the number of entries")
end)
results.record("suite", "example-sort-science-packs", sort_ok, sort_err)
