-- Data-fixture smoke tests.
--
-- test-mods/planetslib-funit-data runs PlanetsLib's data-stage API inside pcall
-- and records the outcome into the "PlanetsLib-funit-results" mod-data
-- prototype. This suite reads it back at runtime and fails if any fixture
-- reported an error, which is how data-stage failures surface in the FUnit
-- report.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local support = require("__planetslib-funit-data__.tests.suites.support")

-- Namespaces that must exist in the results bag. This catches a fixture that
-- silently stops loading; a pairs() loop over whatever happens to be present
-- cannot.
local BASE_NAMESPACES = {
	"achievements",
	"api_coverage",
	"entity_replacement_data",
	"icons",
	"misc_global_checks",
	"misc_science_lab",
	"misc_science_lab_final",
	"misc_visuals_final",
	"misc_visuals_setup",
	"mod_data",
	"planet_str",
	"planet_str_auto",
	"recipe_effects_setup",
	"special_properties",
	"special_properties_final",
	"suite",
	"surface_conditions",
	"technology",
	"technology_productivity_setup",
}

local SPACE_AGE_NAMESPACES = {
	"ground_diggers_data",
	"ground_diggers_late",
	"orbit_native",
	"planet_extend",
	"planet_update",
	"planet_update_final",
	"rocket_parts_setup",
}

local function get_results(runner)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(
		mod_data,
		"mod-data prototype '" .. RESULTS_MOD_DATA .. "' not found. Is the planetslib-funit-data test mod enabled?"
	)
	return mod_data.data
end

local function allowed_skips()
	local allowed = {}
	if not support.has_space_age() then
		allowed["planet_str:PSTR-3"] = true
		allowed["planet_str_auto:PSTR-4"] = true
		allowed["surface_conditions:SFC-DATA-1"] = true
		allowed["misc_visuals_final:MISC-4"] = true
		allowed["misc_visuals_final:MISC-6-tint"] = true
		allowed["misc_visuals_final:MISC-7"] = true
		allowed["misc_visuals_final:MISC-8"] = true
		allowed["misc_visuals_final:MISC-9"] = true
		allowed["technology_productivity_setup:TECH-10-vanilla"] = true
	else
		if settings.startup["PlanetsLib-enhanced-tooltips"].value ~= true then
			allowed["misc_visuals_final:MISC-4"] = true
		end
		-- The tint check depends on the vanilla centrifuge graphics shape.
		allowed["misc_visuals_final:MISC-6-tint"] = true
	end
	return allowed
end

return function(runner)
	runner.test("SMOKE-1 results bag exists", function()
		local results = get_results(runner)
		-- Deliberately broken to exercise the FUnit failure PR comment.
		runner.assert(type(results) == "string",
			"deliberate failure: results bag should be a table")
	end)

	runner.test("SMOKE-2 example data-stage fixtures succeeded", function()
		support.assert_all(runner, "suite", {
			expected = { "example-assign-entity-replacement", "example-sort-science-packs" },
		})
	end)

	runner.test("SMOKE-3 every expected fixture namespace reported", function()
		local results = get_results(runner)
		local expected = {}
		for _, name in ipairs(BASE_NAMESPACES) do
			expected[#expected + 1] = name
		end
		if support.has_space_age() then
			for _, name in ipairs(SPACE_AGE_NAMESPACES) do
				expected[#expected + 1] = name
			end
		end
		for _, name in ipairs(expected) do
			runner.assert(results[name], "no data-stage results recorded for fixture namespace '" .. name .. "'")
			runner.assert(next(results[name]) ~= nil, "fixture namespace '" .. name .. "' is empty")
		end
	end)

	runner.test("SMOKE-4 no unexpected data-stage skips", function()
		local results = get_results(runner)
		local allowed = allowed_skips()
		for namespace, entries in pairs(results) do
			for id, entry in pairs(entries) do
				if entry.skipped then
					local key = namespace .. ":" .. id
					runner.assert(
						allowed[key],
						"data fixture '" .. key .. "' was skipped unexpectedly: " .. tostring(entry.note or entry.err)
					)
				elseif not (entry.note and entry.ok == nil) then
					runner.assert(
						entry.ok,
						"data fixture '" .. namespace .. ":" .. id .. "' failed: " .. tostring(entry.err)
					)
				end
			end
		end
	end)

	runner.test("SMOKE-5 expected PlanetsLib prototypes are present", function()
		if script.active_mods["space-age"] then
			runner.assert(prototypes.space_location["nauvis"], "space location prototype 'nauvis' not found")
		else
			runner.assert(prototypes.entity["iron-chest"], "base prototype 'iron-chest' not found")
		end
	end)
end
