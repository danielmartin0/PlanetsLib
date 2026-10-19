-- data-final-fixes fixture: asserts what PlanetsLib's own data-final-fixes did
-- to the prototypes created by misc_science_lab.lua. This runs after PlanetsLib
-- finished, so the results are final.
--
-- Behaviours under test (prototypes/override-final/science.lua and
-- prototypes/override-final/lab-updates.lua):
--   * unlinking hidden prerequisites + the unlinked_prerequisites record
--   * the legacy/modern lab-pack technology fields
--   * include_all_lab_science / the legacy+modern lab sort fields
--   * >12-pack labs getting an icons_positioning entry
local results = require("lib.results")

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

local function ingredient_name(ingredient)
	return ingredient.name or ingredient[1]
end

local unlink_setting = settings.startup["PlanetsLib-unlink-hidden-prerequisites"].value
local preview_setting = settings.startup["PlanetsLib-enable-lab-science-pack-preview-size-change"].value

-- MISC-2: hidden prerequisites, lab-pack fields and sort/include fields.
local ok, err = pcall(function()
	local successor = data.raw.technology["funit-lab-hidden-successor"]
	assert(successor, "the successor technology is missing")
	local unlinked = data.raw["mod-data"]["Planetslib"].data.unlinked_prerequisites
	assert(unlinked, "Planetslib's unlinked_prerequisites is missing")

	if unlink_setting then
		assert(
			not contains(successor.prerequisites, "funit-lab-hidden-prereq"),
			"the hidden prerequisite was not unlinked"
		)
		assert(
			contains(unlinked, "funit-lab-hidden-prereq"),
			"the unlinked prerequisite was not recorded in unlinked_prerequisites"
		)
	else
		-- The scenario leaves the setting off (its default); assert the
		-- documented inert behavior instead of failing.
		assert(
			contains(successor.prerequisites, "funit-lab-hidden-prereq"),
			"the hidden prerequisite should remain while the setting is off"
		)
		assert(
			not contains(unlinked, "funit-lab-hidden-prereq"),
			"nothing should be recorded in unlinked_prerequisites while the setting is off"
		)
	end

	-- The vanilla lab's inputs have already been sorted by PlanetsLib; every
	-- custom lab below ends up with exactly the same set of packs, so its inputs
	-- must equal the vanilla lab's inputs.
	local vanilla_inputs = data.raw.lab["lab"].inputs

	-- Legacy technology field: ensure_all_packs_from_vanilla_lab.
	local legacy = data.raw.technology["funit-lab-legacy-packs"]
	assert(legacy, "the legacy-pack technology is missing")
	local legacy_packs = {}
	for _, ingredient in ipairs(legacy.unit.ingredients) do
		legacy_packs[ingredient_name(ingredient)] = true
	end
	assert(legacy_packs["automation-science-pack"], "the technology lost its original science pack")
	assert(not legacy_packs["logistic-science-pack"], "an unlocked science pack must not be required")
	for _, pack in ipairs(vanilla_inputs) do
		if pack ~= "logistic-science-pack" and pack ~= "automation-science-pack" then
			assert(legacy_packs[pack], "the legacy field did not add vanilla lab pack " .. pack)
		end
	end
	assert(#legacy.unit.ingredients == #vanilla_inputs - 1, "unexpected ingredient count for the legacy field")

	-- Modern technology field: planetslib_ensure_all_packs_from_vanilla_lab.
	local modern = data.raw.technology["funit-lab-modern-packs"]
	assert(modern, "the modern-pack technology is missing")
	local modern_packs = {}
	for _, ingredient in ipairs(modern.unit.ingredients) do
		modern_packs[ingredient_name(ingredient)] = true
	end
	assert(not modern_packs["utility-science-pack"], "an unlocked science pack must not be required")
	for _, pack in ipairs(vanilla_inputs) do
		if pack ~= "utility-science-pack" then
			assert(modern_packs[pack], "the modern field did not add vanilla lab pack " .. pack)
		end
	end
	assert(#modern.unit.ingredients == #vanilla_inputs - 1, "unexpected ingredient count for the modern field")

	-- Legacy + modern lab sort fields.
	local legacy_sort = data.raw.lab["funit-lab-legacy-sort"]
	local modern_sort = data.raw.lab["funit-lab-modern-sort"]
	assert(legacy_sort, "the legacy-sort lab is missing")
	assert(modern_sort, "the modern-sort lab is missing")
	assert(same_strings(legacy_sort.inputs, vanilla_inputs), "the legacy sort field did not sort the lab inputs")
	assert(same_strings(modern_sort.inputs, vanilla_inputs), "the modern sort field did not sort the lab inputs")

	-- include_all_lab_science.
	local include_all = data.raw.lab["funit-lab-include-all"]
	assert(include_all, "the include-all lab is missing")
	assert(
		same_strings(include_all.inputs, vanilla_inputs),
		"include_all_lab_science did not add every vanilla lab pack"
	)
	assert(contains(include_all.inputs, "automation-science-pack"), "the original science pack was lost")

	-- PlanetsLib flags the biolab with include_all_lab_science when it exists.
	local biolab = data.raw.lab["biolab"]
	if biolab then
		assert(
			biolab.include_all_lab_science == true,
			"PlanetsLib did not flag the biolab with include_all_lab_science"
		)
	end
end)
results.record("misc_science_lab_final", "MISC-2", ok, err)

-- MISC-3: >12-pack labs get an icons_positioning entry.
local ok3, err3 = pcall(function()
	local lab = data.raw.lab["funit-lab-many-packs"]
	assert(lab, "the many-packs lab is missing")
	assert(#lab.inputs > 12, "the many-packs lab should have more than 12 science packs")

	if not preview_setting then
		for _, entry in ipairs(lab.icons_positioning or {}) do
			assert(
				entry.inventory_index ~= defines.inventory.lab_input,
				"the preview-size-change setting is off, so no lab_input icons_positioning entry should be added"
			)
		end
		return
	end

	assert(lab.icons_positioning, "PlanetsLib did not add icons_positioning to the many-packs lab")
	local lab_input_entries = 0
	for _, entry in ipairs(lab.icons_positioning) do
		if entry.inventory_index == defines.inventory.lab_input then
			lab_input_entries = lab_input_entries + 1
		end
	end
	assert(lab_input_entries == 1, "exactly one lab_input icons_positioning entry should be added (got "
		.. lab_input_entries .. ", total entries " .. #lab.icons_positioning .. ")")

	local entry
	for _, candidate in ipairs(lab.icons_positioning) do
		if candidate.inventory_index == defines.inventory.lab_input then
			entry = candidate
			break
		end
	end
	assert(entry.inventory_index == defines.inventory.lab_input, "the entry targets the wrong inventory")
	assert(entry.separation_multiplier == 1,
		"the separation_multiplier is wrong (got " .. tostring(entry.separation_multiplier) .. ")")

	local max_count = 12
	local pack_count = #lab.inputs
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
	assert(shift_x == 0, "the icons_positioning horizontal shift should be 0")
	assert(
		math.abs(shift_y - 0.75 * size_factor * (icon_scaling - 1)) < 1e-9,
		"the icons_positioning shift is wrong"
	)
	assert(entry.max_icons_per_row == math.floor(6 / icon_scaling), "max_icons_per_row is wrong")
	assert(
		math.abs(entry.scale - 0.5 * size_factor * icon_scaling) < 1e-6,
		"the icons_positioning scale is wrong (got " .. tostring(entry.scale)
			.. ", expected " .. tostring(0.5 * size_factor * icon_scaling)
			.. ", icon_scaling " .. tostring(icon_scaling)
			.. ", size_factor " .. tostring(size_factor) .. ")"
	)
end)
results.record("misc_science_lab_final", "MISC-3", ok3, err3)

-- Record which branch of each startup-gated behavior the scenario exercised, so
-- the runtime report shows what was skipped rather than hiding it.
results.record(
	"misc_science_lab_final",
	"MISC-2-setting",
	true,
	unlink_setting
		and "PlanetsLib-unlink-hidden-prerequisites is ON; the unlink path was exercised"
		or "SKIP: PlanetsLib-unlink-hidden-prerequisites is OFF (default); the unlink path was not exercised"
)
results.record(
	"misc_science_lab_final",
	"MISC-3-setting",
	true,
	preview_setting
		and "PlanetsLib-enable-lab-science-pack-preview-size-change is ON; the OFF path was skipped"
		or "SKIP: PlanetsLib-enable-lab-science-pack-preview-size-change is OFF; the ON path was skipped"
)

return true
