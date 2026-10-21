-- Runtime helpers for asserting data-stage fixture results.
--
-- Every data fixture writes into the "PlanetsLib-funit-results" mod-data
-- prototype. This module turns those entries into real test assertions and
-- makes the difference between a pass, a failure, an explicit skip and an
-- informational note explicit.
--
-- Suites should pass an `expected` id list. That is what makes a missing
-- fixture id fail instead of silently disappearing from a pairs() loop.

local support = {}

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"

function support.has_space_age()
	return script.active_mods["space-age"] ~= nil
end

function support.results(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(
		mod_data,
		"mod-data prototype '"
			.. RESULTS_MOD_DATA
			.. "' not found. Is the planetslib-funit-data test mod enabled?"
	)
	return mod_data.data
end

function support.entries(runner, suite)
	local bag = support.results(runner)
	local entries = bag[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. tostring(suite) .. "'")
	return entries
end

---Assert one recorded fixture entry.
---@param runner table
---@param suite string
---@param id string
---@param opts table|nil { allow_skip = boolean }
---@return table entry
function support.assert_entry(runner, suite, id, opts)
	opts = opts or {}
	local entries = support.entries(runner, suite)
	local entry = entries[id]
	runner.assert(entry, "missing data fixture entry '" .. tostring(id) .. "' in '" .. tostring(suite) .. "'")

	if entry.note and entry.ok == nil then
		runner.assert(false, "data fixture '" .. id .. "' is an informational note, not a check")
	end
	if entry.skipped then
		runner.assert(
			opts.allow_skip,
			"data fixture '"
				.. id
				.. "' was skipped unexpectedly: "
				.. tostring(entry.note or entry.err)
		)
		return entry
	end

	runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
	return entry
end

---Assert every expected fixture entry in a suite.
--
-- `opts.expected` is a list of ids. Without it the helper can only check the
-- entries that happen to exist, which does not catch a fixture that silently
-- stopped recording an id. Prefer supplying the list.
--
-- `opts.allow_skips` maps ids to true for skips that are expected in this
-- scenario (for example Space-Age-only fixtures in a base game).
---@param runner table
---@param suite string
---@param opts table|nil { expected = table|nil, allow_skips = table|nil }
function support.assert_all(runner, suite, opts)
	opts = opts or {}
	local entries = support.entries(runner, suite)
	local allow_skips = opts.allow_skips or {}

	if opts.expected then
		for _, id in ipairs(opts.expected) do
			support.assert_entry(runner, suite, id, { allow_skip = allow_skips[id] == true })
		end
		return
	end

	for id, entry in pairs(entries) do
		if entry.note and entry.ok == nil then
			-- Informational note; not a check.
		else
			runner.assert(
				not entry.skipped or allow_skips[id],
				"data fixture '" .. id .. "' was skipped unexpectedly: " .. tostring(entry.note or entry.err)
			)
			runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
		end
	end
end

---Fail if a suite contains a skip that is not explicitly allowed.
function support.assert_no_unexpected_skips(runner, suite, allowed)
	allowed = allowed or {}
	for id, entry in pairs(support.entries(runner, suite)) do
		if entry.skipped and not allowed[id] then
			runner.assert(
				false,
				"data fixture '" .. id .. "' was skipped unexpectedly: " .. tostring(entry.note or entry.err)
			)
		end
	end
end

return support
