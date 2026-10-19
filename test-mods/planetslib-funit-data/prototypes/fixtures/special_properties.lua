-- Data-stage fixture: planetary special properties.
local results = require("lib.results")

local ok, err = pcall(function()
	local first = PlanetsLib.set_special_properties("funit-sp", {
		rocket_lift_multiplier = 2,
		custom = "a",
	})
	assert(first.rocket_lift_multiplier == 2, "the property was not stored")
	assert(first.custom == "a", "the custom property was not stored")
	assert(PlanetsLib.get_special_property("funit-sp") == first, "get_special_property should return the stored table")
	assert(
		PlanetsLib.get_special_property("funit-sp", "rocket_lift_multiplier") == 2,
		"get_special_property did not return a single property"
	)

	-- Merging: a second call with a prototype table adds fields and keeps old ones.
	local second = PlanetsLib.set_special_properties({ name = "funit-sp" }, { rocket_part_multiplier = 3 })
	assert(second.rocket_lift_multiplier == 2, "merging dropped an existing property")
	assert(second.rocket_part_multiplier == 3, "merging did not add the new property")
	assert(second.custom == "a", "merging dropped a custom property")

	-- The input table is deep-copied.
	local input = { nested = { value = 1 } }
	PlanetsLib.set_special_properties("funit-sp-deep", input)
	input.nested.value = 99
	assert(
		PlanetsLib.get_special_property("funit-sp-deep", "nested").value == 1,
		"the input table was not deep-copied"
	)

	-- Unknown planets and properties return nil.
	assert(PlanetsLib.get_special_property("funit-sp-unknown") == nil, "unknown planets should have no properties")
	assert(PlanetsLib.get_special_property("funit-sp-unknown", "x") == nil, "unknown planets should have no property")
	assert(PlanetsLib.get_special_property("funit-sp", "missing") == nil, "missing properties should be nil")
end)
results.record("special_properties", "SP-1", ok, err)

return true
