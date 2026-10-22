-- Shared helper for recording data-stage fixture results.
--
-- Fixtures run in the data stage and cannot report failures back to the runtime
-- FUnit scenario directly, so they write into the "PlanetsLib-funit-results"
-- mod-data prototype (created in data.lua). The runtime scenario reads it via
-- prototypes.mod_data and asserts on it (see tests/suites/smoke.lua).
--
-- There are three kinds of entry:
--
--   * a real check: results.record(suite, id, ok, err)
--   * an explicit skip: results.skip(suite, id, reason)
--   * an informational note: results.note(suite, id, text)
--
-- Skips are deliberately visible in the results bag. A skipped check must not
-- silently count as a pass: tests/suites/support.lua treats an unexpected skip
-- as a failure and only allows the skips that are expected for the active
-- scenario. Notes are not checks at all and are ignored by the result checker.

local results = {}

local function bag()
	local mod_data = data.raw["mod-data"]["PlanetsLib-funit-results"]
	assert(
		mod_data,
		"planetslib-funit-data: 'PlanetsLib-funit-results' mod-data prototype was not created before lib.results.record() was called."
	)
	return mod_data.data
end

local function store(suite, id, entry)
	local data_bag = bag()
	data_bag[suite] = data_bag[suite] or {}
	data_bag[suite][id] = entry
	return entry
end

--- Record the outcome of one fixture check.
--- @param suite string Namespace to store the entry under (e.g. "suite").
--- @param id string Unique id of the check.
--- @param ok boolean Whether the check succeeded.
--- @param err any Error message/value when ok is false.
--- @return boolean ok
function results.record(suite, id, ok, err)
	local entry = {
		ok = ok and true or false,
		err = err ~= nil and tostring(err) or nil,
	}
	store(suite, id, entry)
	if not ok then
		log("[funit] data fixture " .. suite .. " / " .. id .. " failed: " .. tostring(err))
	end
	return ok and true or false
end

--- Record a check that could not run in this scenario.
--
-- Use this instead of results.record(suite, id, true, "SKIP: ..."). The
-- runtime checker fails on unexpected skips, so a scenario that ought to
-- exercise the check cannot pass by skipping it.
--- @param suite string
--- @param id string
--- @param reason string
--- @return table entry
function results.skip(suite, id, reason)
	local entry = {
		ok = true,
		skipped = true,
		note = tostring(reason),
	}
	store(suite, id, entry)
	log("[funit] data fixture " .. suite .. " / " .. id .. " skipped: " .. tostring(reason))
	return entry
end

--- Record an informational note that is not a pass/fail check.
--- @param suite string
--- @param id string
--- @param text string
--- @return table entry
function results.note(suite, id, text)
	local entry = {
		note = tostring(text),
	}
	store(suite, id, entry)
	return entry
end

return results
