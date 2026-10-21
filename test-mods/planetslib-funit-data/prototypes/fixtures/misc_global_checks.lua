-- Data-stage fixture: PlanetsLib.check_global_variables().
--
-- The fixture creates prototypes using the corrected (obsolete) fields and then
-- calls check_global_variables() itself, so it does not have to wait for
-- PlanetsLib's next data-cycle pass. Legacy fields that the current engine
-- refuses to accept are skipped rather than failed.
local results = require("lib.results")

local function contains(list, value)
	for _, entry in ipairs(list or {}) do
		if entry == value then
			return true
		end
	end
	return false
end

local ok, err = pcall(function()
	local _, template = next(data.raw.technology)
	assert(template, "no technology prototype available to copy")

	-- Array-form duplicate science packs are combined, preserving first-seen order.
	local tech = table.deepcopy(template)
	tech.name = "funit-dup-research-array"
	tech.unit = {
		count = 1,
		time = 1,
		ingredients = {
			{ "automation-science-pack", 1 },
			{ "logistic-science-pack", 1 },
			{ "automation-science-pack", 2 },
		},
	}
	tech.localised_description = nil
	data:extend({ tech })

	PlanetsLib.check_global_variables()

	local corrected = data.raw.technology["funit-dup-research-array"]
	assert(#corrected.unit.ingredients == 2, "duplicate array ingredients were not combined")
	assert(
		corrected.unit.ingredients[1][1] == "automation-science-pack"
			and corrected.unit.ingredients[1][2] == 3,
		"duplicate amounts were not summed"
	)
	assert(corrected.unit.ingredients[2][1] == "logistic-science-pack", "first-seen order was not preserved")
	assert(corrected.localised_description, "a correction tooltip was not added")

	-- Dictionary-form ingredients are handled too.
	local tech2 = table.deepcopy(template)
	tech2.name = "funit-dup-research-dict"
	tech2.unit = {
		count = 1,
		time = 1,
		ingredients = {
			{ name = "automation-science-pack", amount = 1 },
			{ name = "automation-science-pack", amount = 4 },
		},
	}
	data:extend({ tech2 })

	PlanetsLib.check_global_variables()

	local corrected2 = data.raw.technology["funit-dup-research-dict"]
	assert(#corrected2.unit.ingredients == 1, "dictionary-form duplicates were not combined")
	assert(corrected2.unit.ingredients[1][2] == 5, "dictionary-form amounts were not summed")

	-- The correction is idempotent.
	PlanetsLib.check_global_variables()
	assert(#corrected2.unit.ingredients == 1, "a second pass changed the ingredient list")

	-- An overridden `helpers` global is detected. The engine's `helpers` methods
	-- are read-only, so replace the whole global rather than clearing a method.
	local saved_helpers = helpers
	_G.helpers = {}
	local helper_ok, helper_err = pcall(PlanetsLib.check_global_variables)
	_G.helpers = saved_helpers

	assert(not helper_ok, "an overridden helpers global should raise an error")
	assert(tostring(helper_err):find("helpers", 1, true), "the error message should mention 'helpers'")
end)
results.record("misc_global_checks", "MISC-1", ok, err)

-- Legacy ItemPrototype::fuel_category and AmbientSound::planet corrections.
-- Skipped (not failed) when the running engine rejects those fields outright.
local legacy_ok, legacy_err = pcall(function()
	local item = table.deepcopy(data.raw.item["iron-plate"])
	-- PlanetsLib attaches a fuel_category guard metatable to item prototypes.
	-- deepcopy copies it, which would make the assignment below take the late-write
	-- path instead of creating a prototype that check_global_variables() corrects.
	setmetatable(item, nil)
	item.name = "funit-fuel-category"
	item.fuel_category = "chemical"
	local item_created = pcall(data.extend, data, { item })

	if item_created then
		PlanetsLib.check_global_variables()
		local corrected = data.raw.item["funit-fuel-category"]
		assert(corrected.fuel_category == nil, "ItemPrototype::fuel_category was not removed")
		assert(contains(corrected.fuel_categories, "chemical"), "fuel_categories was not populated")
		assert(
			contains(PlanetsLib.constants.items_corrected_fuel_category, "funit-fuel-category"),
			"the corrected item was not recorded"
		)
	end

	local sound_template
	for _, sound in pairs(data.raw["ambient-sound"]) do
		sound_template = sound
		break
	end
	assert(sound_template, "no ambient-sound prototype is available for the legacy-field check")
	local sound = table.deepcopy(sound_template)
	sound.name = "funit-legacy-planet-sound"
	sound.planet = "nauvis"
	sound.planets = nil
	local sound_created, sound_err = pcall(data.extend, data, { sound })
	assert(sound_created, "could not create the legacy ambient-sound fixture: " .. tostring(sound_err))
	PlanetsLib.check_global_variables()
	local corrected_sound = data.raw["ambient-sound"]["funit-legacy-planet-sound"]
	assert(corrected_sound.planet == nil, "AmbientSound::planet was not removed")
	assert(contains(corrected_sound.planets, "nauvis"), "AmbientSound::planets was not populated")
end)
results.record("misc_global_checks", "MISC-2", legacy_ok, legacy_err)

return true
