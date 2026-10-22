-- Science-lab overrides applied by PlanetsLib's data-final-fixes.
--
-- prototypes/override-final/science.lua (hidden prerequisites, the legacy/modern
-- lab-pack technology fields, include_all_lab_science and the legacy/modern lab
-- sort fields) and prototypes/override-final/lab-updates.lua (>12-pack labs get
-- an icons_positioning entry) are exercised by the misc_science_lab (data) and
-- misc_science_lab_final (data-final-fixes) fixtures. This suite asserts the
-- recorded outcomes plus the resulting runtime prototypes.

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"
local support = require("__planetslib-funit-data__.tests.suites.support")

local function fixture(runner, suite)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	local entries = mod_data.data[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. suite .. "'")
	return entries
end

local function assert_namespace(runner, suite)
	local entries = fixture(runner, suite)
	for id, entry in pairs(entries) do
		if entry.note and entry.ok == nil then
			-- Informational note, not a check.
		else
			runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
		end
	end
	return entries
end

local function contains(list, value)
	for _, entry in ipairs(list or {}) do
		if entry == value then
			return true
		end
	end
	return false
end

local function same_strings(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function has_prereq(technology, name)
	return technology.prerequisites ~= nil and technology.prerequisites[name] ~= nil
end

local function has_pack(technology, pack_name)
	for _, ingredient in ipairs(technology.research_unit_ingredients or {}) do
		if (ingredient.name or ingredient[1]) == pack_name then
			return true
		end
	end
	return false
end

return function(runner)
	runner.test("MISC-2a data-stage setup and final-fixes fixture results", function()
		support.assert_all(runner, "misc_science_lab", {
			expected = { "MISC-2-setup", "MISC-3-setup" },
		})
		support.assert_all(runner, "misc_science_lab_final", {
			expected = { "MISC-2", "MISC-3" },
		})
		local final_entries = assert_namespace(runner, "misc_science_lab_final")
		runner.assert(
			type(final_entries["MISC-2-setting"].note) == "string",
			"the hidden-prerequisite setting note was not recorded"
		)
		runner.assert(
			type(final_entries["MISC-3-setting"].note) == "string",
			"the lab preview-size-change setting note was not recorded"
		)
	end)

	runner.test("MISC-2b hidden prerequisite unlinking and unlinked_prerequisites", function()
		assert_namespace(runner, "misc_science_lab_final")

		local successor = prototypes.technology["funit-lab-hidden-successor"]
		runner.assert(successor, "funit-lab-hidden-successor is missing")
		local unlinked = prototypes.mod_data["Planetslib"].data.unlinked_prerequisites
		runner.assert(unlinked, "Planetslib's unlinked_prerequisites is missing")

		local setting = settings.startup["PlanetsLib-unlink-hidden-prerequisites"].value
		if setting then
			runner.assert(
				not has_prereq(successor, "funit-lab-hidden-prereq"),
				"the hidden prerequisite was not unlinked"
			)
			runner.assert(
				contains(unlinked, "funit-lab-hidden-prereq"),
				"unlinked_prerequisites did not record the hidden prerequisite"
			)
		else
			runner.assert(
				has_prereq(successor, "funit-lab-hidden-prereq"),
				"the hidden prerequisite should remain while the setting is off"
			)
			runner.assert(
				not contains(unlinked, "funit-lab-hidden-prereq"),
				"unlinked_prerequisites should be untouched while the setting is off"
			)
		end
	end)

	runner.test("MISC-2c legacy and modern lab-pack technology fields", function()
		local vanilla_inputs = prototypes.entity["lab"].lab_inputs
		local cases = {
			{ name = "funit-lab-legacy-packs", unlocked = "logistic-science-pack", label = "legacy" },
			{ name = "funit-lab-modern-packs", unlocked = "utility-science-pack", label = "modern" },
		}

		for _, case in ipairs(cases) do
			local tech = prototypes.technology[case.name]
			runner.assert(tech, case.name .. " is missing")
			runner.assert(
				has_pack(tech, "automation-science-pack"),
				case.label .. " field: the original science pack was lost"
			)
			runner.assert(
				not has_pack(tech, case.unlocked),
				case.label .. " field: an unlocked science pack must not be required"
			)
			for _, pack in ipairs(vanilla_inputs) do
				if pack ~= case.unlocked then
					runner.assert(
						has_pack(tech, pack),
						case.label .. " field did not add vanilla lab pack " .. pack
					)
				end
			end
			runner.assert(
				#tech.research_unit_ingredients == #vanilla_inputs - 1,
				case.label .. " field produced an unexpected number of ingredients"
			)
		end
	end)

	runner.test("MISC-2d include_all_lab_science and lab sort fields", function()
		local vanilla_inputs = prototypes.entity["lab"].lab_inputs

		for _, name in ipairs({
			"funit-lab-legacy-sort",
			"funit-lab-modern-sort",
			"funit-lab-include-all",
		}) do
			local lab = prototypes.entity[name]
			runner.assert(lab, name .. " is missing")
			runner.assert(
				same_strings(lab.lab_inputs, vanilla_inputs),
				name .. " did not end up with the sorted vanilla science packs"
			)
		end
	end)

	runner.test("MISC-3 labs with more than 12 science packs get icons_positioning", function()
		assert_namespace(runner, "misc_science_lab")
		assert_namespace(runner, "misc_science_lab_final")

		local lab = prototypes.entity["funit-lab-many-packs"]
		runner.assert(lab, "funit-lab-many-packs is missing")
		runner.assert(#lab.lab_inputs > 12, "the many-packs lab should have more than 12 science packs")

		local setting = settings.startup["PlanetsLib-enable-lab-science-pack-preview-size-change"].value
		if not setting then
			for _, candidate in ipairs(lab.icons_positioning or {}) do
				runner.assert(
					candidate.inventory_index ~= defines.inventory.lab_input,
					"the preview-size-change setting is off, so no lab_input icons_positioning should be present"
				)
			end
			return
		end

		runner.assert(lab.icons_positioning, "PlanetsLib did not add icons_positioning")
		local lab_input_entries = 0
		local entry
		for _, candidate in ipairs(lab.icons_positioning) do
			if candidate.inventory_index == defines.inventory.lab_input then
				lab_input_entries = lab_input_entries + 1
				entry = entry or candidate
			end
		end
		runner.assert(lab_input_entries == 1,
			"exactly one lab_input icons_positioning entry should be added (got "
				.. lab_input_entries .. ", total entries " .. #lab.icons_positioning .. ")")

		runner.assert(
			entry.inventory_index == defines.inventory.lab_input,
			"the icons_positioning entry targets the wrong inventory"
		)
		runner.assert(entry.separation_multiplier == 1, "the separation_multiplier is wrong")

		local max_count = 12
		local pack_count = #lab.lab_inputs
		local icon_scaling = math.sqrt(max_count / pack_count)

		local selection_box = lab.selection_box
		local left_top = selection_box.left_top or selection_box[1]
		local right_bottom = selection_box.right_bottom or selection_box[2]
		local left_top_x = left_top.x or left_top[1]
		local right_bottom_x = right_bottom.x or right_bottom[1]
		local x = math.abs(left_top_x - right_bottom_x)
		local size_factor = math.sqrt(x / 3)

		local shift_x = entry.shift[1] or entry.shift.x
		local shift_y = entry.shift[2] or entry.shift.y
		runner.assert(shift_x == 0, "the icons_positioning horizontal shift should be 0")
		runner.assert(
			math.abs(shift_y - 0.75 * size_factor * (icon_scaling - 1)) < 1e-9,
			"the icons_positioning shift is wrong"
		)
		runner.assert(
			entry.max_icons_per_row == math.floor(6 / icon_scaling),
			"max_icons_per_row is wrong"
		)
		runner.assert(
			math.abs(entry.scale - 0.5 * size_factor * icon_scaling) < 1e-6,
			"the icons_positioning scale is wrong (got " .. tostring(entry.scale)
				.. ", expected " .. tostring(0.5 * size_factor * icon_scaling)
				.. ", icon_scaling " .. tostring(icon_scaling)
				.. ", size_factor " .. tostring(size_factor) .. ")"
		)
	end)
end
