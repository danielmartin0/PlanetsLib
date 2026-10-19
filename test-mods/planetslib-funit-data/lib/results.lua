-- Shared helper for recording data-stage fixture results.
--
-- Fixtures run in the data stage and cannot report failures back to the runtime
-- FUnit scenario directly, so they write into the "PlanetsLib-funit-results"
-- mod-data prototype (created in data.lua). The runtime scenario reads it via
-- prototypes.mod_data and asserts on it (see tests/suites/smoke.lua).

local results = {}

--- Record the outcome of one fixture check.
--- @param suite string Namespace to store the entry under (e.g. "suite").
--- @param id string Unique id of the check.
--- @param ok boolean Whether the check succeeded.
--- @param err any Error message/value when ok is false.
--- @return boolean ok
function results.record(suite, id, ok, err)
	local bag = data.raw["mod-data"]["PlanetsLib-funit-results"]
	assert(
		bag,
		"planetslib-funit-data: 'PlanetsLib-funit-results' mod-data prototype was not created before lib.results.record() was called."
	)

	bag.data[suite] = bag.data[suite] or {}
	bag.data[suite][id] = {
		ok = ok and true or false,
		err = err ~= nil and tostring(err) or nil,
	}
	if not ok then
		log("[funit] data fixture " .. suite .. " / " .. id .. " failed: " .. tostring(err))
	end

	return ok and true or false
end

return results
