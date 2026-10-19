-- Data-stage fixture: technology helpers (lib/technology.lua).
--
-- get_child_technologies, the excise_* functions, sort_science_pack_names and
-- the vanilla-lab science-pack helper read or mutate data.raw, so they can only
-- run here. Every check is recorded in the results bag and asserted by
-- tests/suites/technology.lua, which also re-checks the pure helpers (icons,
-- cargo-drop tables and set_science_packs_from_lab) directly at runtime.
local results = require("lib.results")
local util = require("util")
local technology = require("__PlanetsLib__.lib.technology")

-- Pick a researchable technology (one with a `unit`) that also has an icon, so
-- cloned prototypes remain valid regardless of how the vanilla tree is laid out
-- (early technologies use `research_trigger` instead of `unit` in 2.x).
local function find_tech_source()
	for _, candidate in ipairs({ "automation", "steel-processing", "electronics", "logistic-science-pack" }) do
		local tech = data.raw.technology[candidate]
		if tech and tech.unit and tech.unit.ingredients and (tech.icon or tech.icons) then
			return candidate
		end
	end
	for name, tech in pairs(data.raw.technology) do
		if tech.unit and tech.unit.ingredients and (tech.icon or tech.icons) then
			return name
		end
	end
end

local TECH_SOURCE = find_tech_source()
assert(TECH_SOURCE, "no researchable technology prototype is available to clone")

local RECIPE_SOURCE = data.raw.recipe["iron-gear-wheel"] and "iron-gear-wheel" or next(data.raw.recipe)
local ITEM_SOURCE = data.raw.item["iron-plate"] and "iron-plate" or next(data.raw.item)

local TESTS_ICON = "__PlanetsLib__/graphics/icons/planet-technology.png"
local MOON_ICON = "__PlanetsLib__/graphics/icons/moon-technology-symbol.png"
local VANILLA_ICON = "__base__/graphics/icons/iron-plate.png"

-- Clone a real technology so the resulting prototype keeps a valid `unit` and
-- icon, then replace the fields under test.
local function clone_tech(name, prerequisites, effects)
	local tech = table.deepcopy(data.raw.technology[TECH_SOURCE])
	tech.name = name
	tech.prerequisites = prerequisites or {}
	tech.effects = effects or {}
	tech.hidden = nil
	-- The source is a `unit`-researched technology; drop any trigger form so the
	-- clone is not both unit- and trigger-researched.
	tech.research_trigger = nil
	return tech
end

local function clone_recipe(name)
	local recipe = table.deepcopy(data.raw.recipe[RECIPE_SOURCE])
	recipe.name = name
	return recipe
end

local function clone_item(name, order)
	local item = table.deepcopy(data.raw.item[ITEM_SOURCE])
	item.name = name
	item.order = order
	return item
end

local function contains(list, value)
	for _, entry in ipairs(list or {}) do
		if entry == value then
			return true
		end
	end
	return false
end

-- == Setup: recipes and items referenced by the test technologies == == --
local setup_ok, setup_err = pcall(function()
	data:extend({
		clone_recipe("funit-tech-recipe-1"),
		clone_recipe("funit-tech-recipe-2"),
		clone_recipe("funit-tech-recipe-3"),
		clone_recipe("funit-tech-recipe-4"),
		clone_recipe("funit-tech-recipe-5"),
		clone_recipe("funit-tech-recipe-6"),
	})

	-- Items used to exercise sort_science_pack_names. z1/z2 have no `order` and
	-- therefore fall back to their prototype name.
	data:extend({
		clone_item("funit-tech-pack-a", "a"),
		clone_item("funit-tech-pack-b", "b"),
		clone_item("funit-tech-pack-c", "c"),
		clone_item("funit-tech-pack-z1", nil),
		clone_item("funit-tech-pack-z2", nil),
	})
end)
results.record("technology", "TECH-0", setup_ok, setup_err)

-- == Setup: the technologies used by the tree-manipulation checks == == --
local techs_ok, techs_err = pcall(function()
	data:extend({
		-- TECH-1: child lookup.
		clone_tech("funit-tech-parent-1", {}, {}),
		clone_tech("funit-tech-child-1", { "funit-tech-parent-1" }, {}),
		clone_tech("funit-tech-child-2", { "funit-tech-parent-1" }, {}),

		-- TECH-2: excise a technology and promote its prerequisites.
		clone_tech("funit-tech-excise-root", {}, {}),
		clone_tech("funit-tech-excise-root2", {}, {}),
		clone_tech("funit-tech-excise-mid", { "funit-tech-excise-root", "funit-tech-excise-root2" }, {}),
		clone_tech("funit-tech-excise-child", { "funit-tech-excise-mid" }, {}),
		clone_tech("funit-tech-excise-other", { "funit-tech-excise-mid", "funit-tech-excise-root" }, {}),

		-- TECH-3: excise a recipe (including a technology emptied by it).
		clone_tech("funit-tech-recipe-base", {}, {}),
		clone_tech("funit-tech-recipe-multi", {}, {
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-1" },
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-2" },
		}),
		clone_tech("funit-tech-recipe-only", { "funit-tech-recipe-base" }, {
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-1" },
		}),
		clone_tech("funit-tech-recipe-only-child", { "funit-tech-recipe-only" }, {}),
		clone_tech("funit-tech-recipe-keep", {}, {
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-3" },
		}),

		-- TECH-4: excise an exact effect (including a technology emptied by it).
		clone_tech("funit-tech-effect-base", {}, {}),
		clone_tech("funit-tech-effect-a", {}, {
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-4" },
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-5" },
		}),
		clone_tech("funit-tech-effect-only", { "funit-tech-effect-base" }, {
			{ type = "unlock-recipe", recipe = "funit-tech-recipe-6" },
		}),
		clone_tech("funit-tech-effect-only-child", { "funit-tech-effect-only" }, {}),
		clone_tech("funit-tech-effect-count", {}, {
			{ type = "nothing", effect_description = "funit" },
		}),
	})
end)
results.record("technology", "TECH-0b", techs_ok, techs_err)

-- == TECH-1: get_child_technologies == == --
local ok, err = pcall(function()
	local children = PlanetsLib.get_child_technologies("funit-tech-parent-1")
	table.sort(children)
	assert(#children == 2, "expected 2 children, got " .. #children)
	assert(
		children[1] == "funit-tech-child-1" and children[2] == "funit-tech-child-2",
		"unexpected children: " .. table.concat(children, ", ")
	)
	assert(
		not pcall(PlanetsLib.get_child_technologies, "funit-tech-does-not-exist"),
		"an invalid technology name must raise an error"
	)
end)
results.record("technology", "TECH-1", ok, err)

-- == TECH-2: excise_tech_from_tech_tree == == --
ok, err = pcall(function()
	PlanetsLib.excise_tech_from_tech_tree("funit-tech-excise-mid")

	local mid = data.raw.technology["funit-tech-excise-mid"]
	assert(mid and mid.hidden == true, "the excised technology must be hidden")

	local child = data.raw.technology["funit-tech-excise-child"]
	table.sort(child.prerequisites)
	assert(#child.prerequisites == 2, "the child should inherit both prerequisites, got " .. #child.prerequisites)
	assert(
		child.prerequisites[1] == "funit-tech-excise-root"
			and child.prerequisites[2] == "funit-tech-excise-root2",
		"the excised technology's prerequisites were not promoted to the child"
	)

	-- The other child already required one of the promoted prerequisites: it
	-- must be deduplicated, and the excised name must be gone.
	local other = data.raw.technology["funit-tech-excise-other"]
	local counts = {}
	for _, prereq in ipairs(other.prerequisites) do
		counts[prereq] = (counts[prereq] or 0) + 1
	end
	assert(counts["funit-tech-excise-root"] == 1, "a promoted prerequisite appeared more than once")
	assert(counts["funit-tech-excise-root2"] == 1, "a promoted prerequisite was not added exactly once")
	assert(counts["funit-tech-excise-mid"] == nil, "the excised technology is still a prerequisite")

	-- Excising an unknown technology is a no-op.
	PlanetsLib.excise_tech_from_tech_tree("funit-tech-does-not-exist")
end)
results.record("technology", "TECH-2", ok, err)

-- == TECH-3: excise_recipe_from_tech_tree == == --
ok, err = pcall(function()
	PlanetsLib.excise_recipe_from_tech_tree("funit-tech-recipe-1")

	local multi = data.raw.technology["funit-tech-recipe-multi"]
	assert(#multi.effects == 1, "multi should keep one effect, got " .. #multi.effects)
	assert(multi.effects[1].recipe == "funit-tech-recipe-2", "the wrong effect was kept")
	assert(multi.hidden ~= true, "a technology with remaining effects must not be hidden")

	local only = data.raw.technology["funit-tech-recipe-only"]
	assert(only.hidden == true, "a technology emptied by the excision must be hidden")
	assert(#only.effects == 0, "the emptied technology should have no effects")

	local only_child = data.raw.technology["funit-tech-recipe-only-child"]
	assert(
		#only_child.prerequisites == 1 and only_child.prerequisites[1] == "funit-tech-recipe-base",
		"prerequisites were not promoted when the technology was excised"
	)

	local keep = data.raw.technology["funit-tech-recipe-keep"]
	assert(
		#keep.effects == 1 and keep.effects[1].recipe == "funit-tech-recipe-3",
		"unrelated technologies must be left alone"
	)

	-- Excising a recipe nobody unlocks is a no-op.
	PlanetsLib.excise_recipe_from_tech_tree("funit-tech-recipe-does-not-exist")
end)
results.record("technology", "TECH-3", ok, err)

-- == TECH-4: excise_effect_from_tech_tree == == --
ok, err = pcall(function()
	PlanetsLib.excise_effect_from_tech_tree({ type = "unlock-recipe", recipe = "funit-tech-recipe-4" })

	local a = data.raw.technology["funit-tech-effect-a"]
	assert(#a.effects == 1, "effect-a should keep one effect, got " .. #a.effects)
	assert(a.effects[1].recipe == "funit-tech-recipe-5", "effect-a kept the wrong effect")
	assert(a.hidden ~= true, "a technology with remaining effects must not be hidden")

	PlanetsLib.excise_effect_from_tech_tree({ type = "unlock-recipe", recipe = "funit-tech-recipe-6" })

	local only = data.raw.technology["funit-tech-effect-only"]
	assert(only.hidden == true, "a technology emptied by the excision must be hidden")
	assert(#only.effects == 0, "the emptied technology should have no effects")

	local only_child = data.raw.technology["funit-tech-effect-only-child"]
	assert(
		#only_child.prerequisites == 1 and only_child.prerequisites[1] == "funit-tech-effect-base",
		"prerequisites were not promoted when the technology was excised"
	)

	-- Only effects with an identical key set are removed: a one-key probe must
	-- not match the two-key `nothing` effect.
	PlanetsLib.excise_effect_from_tech_tree({ type = "unlock-recipe" })
	local count = data.raw.technology["funit-tech-effect-count"]
	assert(#count.effects == 1, "a one-key effect must not match a two-key effect")
	assert(count.effects[1].effect_description == "funit", "the two-key effect was removed")
	assert(count.hidden ~= true, "the technology must not be hidden by a non-matching effect")
end)
results.record("technology", "TECH-4", ok, err)

-- == TECH-5: sort_science_pack_names == == --
ok, err = pcall(function()
	local input = { "funit-tech-pack-c", "funit-tech-pack-a", "funit-tech-pack-b" }
	local sorted = PlanetsLib.sort_science_pack_names(input)
	assert(type(sorted) == "table", "sort_science_pack_names must return a table")
	assert(
		table.concat(sorted, ",") == "funit-tech-pack-a,funit-tech-pack-b,funit-tech-pack-c",
		"prototype `order` sorting is wrong: " .. table.concat(sorted, ",")
	)
	assert(
		table.concat(input, ",") == "funit-tech-pack-c,funit-tech-pack-a,funit-tech-pack-b",
		"sort_science_pack_names must not mutate its input"
	)

	-- Items without an `order` fall back to their name.
	local no_order = PlanetsLib.sort_science_pack_names({ "funit-tech-pack-z2", "funit-tech-pack-z1" })
	assert(
		table.concat(no_order, ",") == "funit-tech-pack-z1,funit-tech-pack-z2",
		"items without an order must sort by name: " .. table.concat(no_order, ",")
	)

	assert(#PlanetsLib.sort_science_pack_names({}) == 0, "an empty input must return an empty table")
end)
results.record("technology", "TECH-5", ok, err)

-- == TECH-6: set_science_packs_from_lab / vanilla-lab helper == == --
ok, err = pcall(function()
	local lab = data.raw["lab"]["lab"]
	assert(lab and lab.inputs, "the vanilla lab is required for this check")

	local all = clone_tech("funit-tech-lab", {}, {})
	all.unit.ingredients = {}
	PlanetsLib.add_science_packs_from_vanilla_lab_to_technology(all)
	assert(
		#all.unit.ingredients == #lab.inputs,
		"every lab input should be added: expected " .. #lab.inputs .. ", got " .. #all.unit.ingredients
	)
	for _, input in ipairs(lab.inputs) do
		local found = false
		for _, ingredient in ipairs(all.unit.ingredients) do
			if ingredient[1] == input then
				found = true
				break
			end
		end
		assert(found, "the technology is missing the lab input " .. input)
	end

	-- A pack whose recipe is unlocked by the technology is skipped.
	local pack = lab.inputs[1]
	if not data.raw.recipe[pack] then
		local recipe = table.deepcopy(data.raw.recipe[RECIPE_SOURCE])
		recipe.name = pack
		data:extend({ recipe })
	end

	local skip = clone_tech("funit-tech-lab-skip", {}, {
		{ type = "unlock-recipe", recipe = pack },
	})
	skip.unit.ingredients = {}
	PlanetsLib.add_science_packs_from_vanilla_lab_to_technology(skip)
	assert(
		#skip.unit.ingredients == #lab.inputs - 1,
		"the unlocked pack should be skipped: expected "
			.. (#lab.inputs - 1)
			.. ", got "
			.. #skip.unit.ingredients
	)
	for _, ingredient in ipairs(skip.unit.ingredients) do
		assert(ingredient[1] ~= pack, "the unlocked science pack must not be required")
	end

	-- Required-argument assertions (recorded, so they are visible if they regress).
	assert(not pcall(PlanetsLib.add_science_packs_from_vanilla_lab_to_technology, nil),
		"a nil technology must raise an error")
	assert(not pcall(technology.set_science_packs_from_lab, nil, lab), "a nil technology must raise an error")
	assert(not pcall(technology.set_science_packs_from_lab, {}, lab), "a missing unit must raise an error")
	assert(
		not pcall(technology.set_science_packs_from_lab, { unit = {} }, lab),
		"missing unit ingredients must raise an error"
	)
	assert(
		not pcall(technology.set_science_packs_from_lab, { unit = { ingredients = {} } }, nil),
		"a nil lab must raise an error"
	)
	assert(
		not pcall(technology.set_science_packs_from_lab, { unit = { ingredients = {} } }, {}),
		"a lab without inputs must raise an error"
	)

	data:extend({ all, skip })
end)
results.record("technology", "TECH-6", ok, err)

-- == TECH-7: technology_icon_planet / technology_icon_moon == == --
ok, err = pcall(function()
	local base_icons = util.technology_icon_constant_planet(TESTS_ICON)

	local planet_icons = PlanetsLib.technology_icon_planet(TESTS_ICON, 256)
	assert(type(planet_icons) == "table" and #planet_icons >= 2, "the planet icon list is too short")
	assert(#planet_icons == #base_icons, "the planet icon list should keep the base layout")
	assert(planet_icons[1].icon == TESTS_ICON, "the first icon is not the supplied technology icon")
	assert(planet_icons[1].icon_size == 256, "the requested icon size was not applied")
	assert(
		planet_icons[#planet_icons].icon == base_icons[#base_icons].icon,
		"the planet constant overlay was not preserved"
	)

	local moon_icons = PlanetsLib.technology_icon_moon(TESTS_ICON, 256)
	assert(#moon_icons == #base_icons, "the moon icon list should keep the base layout")
	assert(moon_icons[1].icon == TESTS_ICON, "the first moon icon is not the supplied technology icon")
	assert(moon_icons[#moon_icons].icon == MOON_ICON, "the moon symbol was not applied to the last icon")

	-- A shadow reorders the list: symbol, then the scaled technology icon.
	local planet_shadow = PlanetsLib.technology_icon_planet(TESTS_ICON, 256, 0.5)
	assert(planet_shadow[2] and planet_shadow[2].icon == TESTS_ICON, "the technology icon was not moved to index 2")
	assert(
		planet_shadow[2].scale == 0.5 * 128 / 256,
		"the shadow scale was not computed from shadow_scale"
	)
	assert(
		planet_shadow[2].shift[1] == 0 and planet_shadow[2].shift[2] == 10,
		"the shadow shift was not applied"
	)
	assert(
		planet_shadow[1].icon == "__PlanetsLib__/graphics/icons/planet-technology.png",
		"the planet symbol was not moved to index 1"
	)

	local moon_shadow = PlanetsLib.technology_icon_moon(TESTS_ICON, 256, 0.5)
	assert(moon_shadow[#moon_shadow].icon == MOON_ICON, "the moon symbol was not applied with a shadow")

	-- Default icon size is 256.
	local defaulted = PlanetsLib.technology_icon_planet(TESTS_ICON)
	assert(defaulted[1].icon_size == 256, "the default icon size should be 256")

	-- Extend the icons onto real prototypes so the runtime suite can inspect them.
	local planet_tech = clone_tech("funit-tech-icon-planet", {}, {})
	planet_tech.icons = planet_icons
	planet_tech.icon = nil
	planet_tech.icon_size = nil
	local moon_tech = clone_tech("funit-tech-icon-moon", {}, {})
	moon_tech.icons = moon_icons
	moon_tech.icon = nil
	moon_tech.icon_size = nil
	data:extend({ planet_tech, moon_tech })
end)
results.record("technology", "TECH-7", ok, err)

-- == TECH-8: cargo_drops_technology_base + effect/icon helpers == == --
ok, err = pcall(function()
	local planet = "funit-cargo-planet"

	local prototype = PlanetsLib.cargo_drops_technology_base(planet, VANILLA_ICON, 64)
	assert(prototype.type == "technology", "the helper must return a technology prototype")
	assert(
		prototype.name == "planetslib-funit-cargo-planet-cargo-drops",
		"the cargo-drop technology name is wrong: " .. tostring(prototype.name)
	)
	assert(
		type(prototype.localised_name) == "table"
			and prototype.localised_name[1] == ""
			and prototype.localised_name[2][1] == "technology-name.cargo-drops",
		"the localised name is malformed"
	)
	assert(
		prototype.localised_name[2][2][1] == "space-location-name.funit-cargo-planet",
		"the localised name does not reference the planet"
	)
	assert(
		prototype.localised_description[1] == "technology-description.cargo-drops",
		"the localised description is wrong"
	)
	assert(#prototype.effects == 1 and prototype.effects[1].type == "nothing",
		"the cargo-drop effect should be a single `nothing` effect")
	assert(
		prototype.effects[1].effect_description[2] == "[space-location=funit-cargo-planet]",
		"the effect description does not reference the planet"
	)
	assert(#prototype.icons == 4, "the cargo-drop technology should have 4 icons")
	assert(
		prototype.icons[1].icon == "__PlanetsLib__/graphics/icons/cargo-drop-tech-pod.png",
		"the first cargo-drop icon is wrong"
	)

	-- Required-argument errors.
	assert(not pcall(PlanetsLib.cargo_drops_technology_base, nil, VANILLA_ICON, 64),
		"a nil planet must raise an error")
	assert(not pcall(PlanetsLib.cargo_drops_technology_base, planet, nil, 64),
		"a nil planet icon must raise an error")
	assert(not pcall(PlanetsLib.cargo_drops_technology_base, planet, VANILLA_ICON, nil),
		"a nil planet icon size must raise an error")

	-- Icon helper.
	local icons = PlanetsLib.technology_icons_planet_cargo_drops(VANILLA_ICON, 64)
	assert(#icons == 4, "the cargo-drop icon helper should return 4 entries")
	assert(icons[2].icon == VANILLA_ICON, "the planet icon was not inserted at index 2")
	assert(icons[2].scale == 0.65 * 256 / 64, "the planet icon scale is wrong")
	assert(
		icons[2].shift[1] == -17 and icons[2].shift[2] == 55,
		"the planet icon shift is wrong"
	)
	local mini = PlanetsLib.technology_icons_planet_cargo_drops(VANILLA_ICON, 64, true)
	assert(mini[2].shift[1] == 0 and mini[2].shift[2] == 0, "the mini variant should not be shifted")
	local defaulted = PlanetsLib.technology_icons_planet_cargo_drops(VANILLA_ICON)
	assert(defaulted[2].icon_size == 256, "the default cargo-drop icon size should be 256")

	-- Effect helper.
	local effects = PlanetsLib.technology_effect_cargo_drops(planet, { { icon = VANILLA_ICON } })
	assert(#effects == 1 and effects[1].type == "nothing", "the cargo-drop effect helper is malformed")
	assert(
		effects[1].effect_description[2] == "[space-location=funit-cargo-planet]",
		"the effect helper does not reference the planet"
	)

	-- Extend a valid technology so the runtime suite can inspect the result.
	prototype.unit = { count = 1, time = 1, ingredients = { { "automation-science-pack", 1 } } }
	prototype.prerequisites = {}
	data:extend({ prototype })
end)
results.record("technology", "TECH-8", ok, err)

return true
