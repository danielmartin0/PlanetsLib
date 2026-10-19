-- data-final-fixes fixture: set_special_properties must refuse to run this late.
local results = require("lib.results")

local ok, err = pcall(function()
	local attribute_ok, attribute_err = pcall(PlanetsLib.set_special_properties, "funit-sp-final", { a = 1 })
	assert(not attribute_ok, "set_special_properties must error during data-final-fixes")
	assert(
		tostring(attribute_err):find("before data-final-fixes", 1, true),
		"the error message should explain the data-final-fixes restriction"
	)
end)
results.record("special_properties_final", "SP-2", ok, err)

return true
