-- Technology helpers (lib/technology.lua).
--
-- The data-stage fixture "technology" exercises everything that reads or
-- mutates data.raw (get_child_technologies, excise_*, sort_science_pack_names,
-- the vanilla-lab helper and the icon/cargo-drop helpers). This suite asserts
-- those recorded results and the real prototypes they produced, then re-checks
-- the pure helpers directly at runtime.

local support = require("__planetslib-funit-data__.tests.suites.support")

-- Every id the technology fixture records. Explicit so a missing entry fails
-- instead of silently dropping out of a pairs() loop.
local TECHNOLOGY_IDS = {
	"TECH-0",
	"TECH-0b",
	"TECH-1",
	"TECH-2",
	"TECH-3",
	"TECH-4",
	"TECH-5",
	"TECH-6",
	"TECH-7",
	"TECH-8",
	"TECH-11",
	"TECH-12",
	"TECH-13",
	"TECH-14",
	"TECH-15",
}

local function contains(list, value)
	for _, entry in ipairs(list or {}) do
		if entry == value then
			return true
		end
	end
	return false
end

local function ingredient_name(ingredient)
	-- Data-stage ingredients use either { "name", amount } or
	-- { name = "name", amount = amount }; runtime ResearchIngredient always
	-- exposes `.name`.
	return ingredient.name or ingredient[1]
end

local function contains_ingredient(ingredients, name)
	for _, ingredient in ipairs(ingredients or {}) do
		if ingredient_name(ingredient) == name then
			return true
		end
	end
	return false
end

-- At runtime LuaTechnologyPrototype::prerequisites is a dictionary keyed by
-- technology name (the data-stage prototype uses an array of names).
local function has_prereq(tech, name)
	return tech.prerequisites ~= nil and tech.prerequisites[name] ~= nil
end

return function(runner)
	-- lib.technology is a data-stage module. Seed its relative requires so it
	-- can be loaded in the control stage (same pattern as suites/planet.lua).
	package.loaded["util"] = require("__core__.lualib.util")
	package.loaded["lib.lib"] = require("__PlanetsLib__.lib.lib")
	package.loaded["lib.objects"] = require("__PlanetsLib__.lib.objects")
	local technology = require("__PlanetsLib__.lib.technology")

	runner.test("TECH-0 technology fixture results", function()
		support.assert_all(runner, "technology", { expected = TECHNOLOGY_IDS })
	end)

	runner.test("TECH-1a get_child_technologies finds the children", function()
		local parent = prototypes.technology["funit-tech-parent-1"]
		runner.assert(parent, "funit-tech-parent-1 is missing")

		local children = {}
		for name, tech in pairs(prototypes.technology) do
			if has_prereq(tech, "funit-tech-parent-1") then
				children[#children + 1] = name
			end
		end
		table.sort(children)
		runner.assert(
			#children == 2 and children[1] == "funit-tech-child-1" and children[2] == "funit-tech-child-2",
			"unexpected children of funit-tech-parent-1: " .. table.concat(children, ", ")
		)

		-- The independent scan above proves the fixture data is what the test
		-- expects; TECH-1 proves get_child_technologies itself returns it.
		support.assert_entry(runner, "technology", "TECH-1")
	end)

	runner.test("TECH-2 excise_tech_from_tech_tree promotes prerequisites", function()
		local mid = prototypes.technology["funit-tech-excise-mid"]
		runner.assert(mid and mid.hidden, "the excised technology is not hidden")

		local child = prototypes.technology["funit-tech-excise-child"]
		runner.assert(child, "funit-tech-excise-child is missing")
		runner.assert(
			has_prereq(child, "funit-tech-excise-root") and has_prereq(child, "funit-tech-excise-root2"),
			"the child did not inherit the excised technology's prerequisites"
		)
		runner.assert(
			not has_prereq(child, "funit-tech-excise-mid"),
			"the child still requires the excised technology"
		)

		local other = prototypes.technology["funit-tech-excise-other"]
		runner.assert(other, "funit-tech-excise-other is missing")
		runner.assert(
			has_prereq(other, "funit-tech-excise-root") and has_prereq(other, "funit-tech-excise-root2"),
			"a promoted prerequisite was not added to the other child"
		)
		runner.assert(
			not has_prereq(other, "funit-tech-excise-mid"),
			"the other child still requires the excised technology"
		)
	end)

	runner.test("TECH-3 excise_recipe_from_tech_tree removes effects and empty techs", function()
		local multi = prototypes.technology["funit-tech-recipe-multi"]
		runner.assert(multi, "funit-tech-recipe-multi is missing")
		runner.assert(
			#multi.effects == 1 and multi.effects[1].recipe == "funit-tech-recipe-2",
			"the wrong effects remained on the multi-recipe technology"
		)
		runner.assert(not multi.hidden, "the multi-recipe technology should not be hidden")

		local only = prototypes.technology["funit-tech-recipe-only"]
		runner.assert(only and only.hidden, "the emptied technology should be hidden")
		runner.assert(#only.effects == 0, "the emptied technology should have no effects")

		local only_child = prototypes.technology["funit-tech-recipe-only-child"]
		runner.assert(only_child, "funit-tech-recipe-only-child is missing")
		runner.assert(
			has_prereq(only_child, "funit-tech-recipe-base"),
			"prerequisites were not promoted to the child"
		)
		runner.assert(
			not has_prereq(only_child, "funit-tech-recipe-only"),
			"the child still requires the excised technology"
		)

		local keep = prototypes.technology["funit-tech-recipe-keep"]
		runner.assert(keep, "funit-tech-recipe-keep is missing")
		runner.assert(
			#keep.effects == 1 and keep.effects[1].recipe == "funit-tech-recipe-3",
			"an unrelated technology was modified"
		)
	end)

	runner.test("TECH-4 excise_effect_from_tech_tree matches exact effects only", function()
		local a = prototypes.technology["funit-tech-effect-a"]
		runner.assert(a, "funit-tech-effect-a is missing")
		runner.assert(
			#a.effects == 1 and a.effects[1].recipe == "funit-tech-recipe-5",
			"effect-a kept the wrong effects"
		)
		runner.assert(not a.hidden, "effect-a should not be hidden")

		local only = prototypes.technology["funit-tech-effect-only"]
		runner.assert(only and only.hidden, "the emptied technology should be hidden")
		runner.assert(#only.effects == 0, "the emptied technology should have no effects")

		local only_child = prototypes.technology["funit-tech-effect-only-child"]
		runner.assert(only_child, "funit-tech-effect-only-child is missing")
		runner.assert(
			has_prereq(only_child, "funit-tech-effect-base"),
			"prerequisites were not promoted to the child"
		)
		runner.assert(
			not has_prereq(only_child, "funit-tech-effect-only"),
			"the child still requires the excised technology"
		)

		local effect_count = prototypes.technology["funit-tech-effect-count"]
		runner.assert(effect_count, "funit-tech-effect-count is missing")
		runner.assert(
			#effect_count.effects == 1 and effect_count.effects[1].effect_description == "funit",
			"an effect with a different key count must not be removed"
		)
		runner.assert(not effect_count.hidden, "the non-matching technology should not be hidden")
	end)

	runner.test("TECH-11 excise_recipe_from_tech_tree keeps productivity effects by default", function()
		local tech = prototypes.technology["funit-tech-excise-prod-default"]
		runner.assert(tech, "funit-tech-excise-prod-default is missing")
		runner.assert(#tech.effects == 1, "the default call must keep exactly the productivity effect")
		runner.assert(
			tech.effects[1].type == "change-recipe-productivity"
				and tech.effects[1].recipe == "funit-tech-excise-prod-recipe-c",
			"the default call removed or changed the productivity effect"
		)
		runner.assert(tech.hidden ~= true, "the technology still has an effect and must not be hidden")
		support.assert_entry(runner, "technology", "TECH-11")
	end)

	runner.test("TECH-12 include_productivity_effects removes only the target recipe", function()
		local tech = prototypes.technology["funit-tech-excise-prod-mixed"]
		runner.assert(tech, "funit-tech-excise-prod-mixed is missing")
		runner.assert(#tech.effects == 2, "the target recipe's effects were not both removed")
		runner.assert(
			tech.effects[1].type == "unlock-recipe"
				and tech.effects[1].recipe == "funit-tech-excise-prod-recipe-b",
			"the unrelated unlock effect was not preserved"
		)
		runner.assert(
			tech.effects[2].type == "change-recipe-productivity"
				and tech.effects[2].recipe == "funit-tech-excise-prod-recipe-b"
				and tech.effects[2].change == 0.2,
			"the unrelated productivity effect was not preserved"
		)

		local control = prototypes.technology["funit-tech-excise-prod-control"]
		runner.assert(control and #control.effects == 1, "an unrelated technology was modified")
		runner.assert(control.effects[1].change == 0.3, "the unrelated technology's effect changed")
		support.assert_entry(runner, "technology", "TECH-12")
	end)

	runner.test("TECH-13 include_productivity_effects excises an emptied technology", function()
		local tech = prototypes.technology["funit-tech-excise-prod-only"]
		runner.assert(tech and tech.hidden, "the technology emptied by productivity excision is not hidden")
		runner.assert(#tech.effects == 0, "the emptied technology still has effects")

		local child = prototypes.technology["funit-tech-excise-prod-only-child"]
		runner.assert(child, "funit-tech-excise-prod-only-child is missing")
		runner.assert(
			has_prereq(child, "funit-tech-excise-prod-root") and not has_prereq(child, "funit-tech-excise-prod-only"),
			"prerequisites were not promoted when productivity excision emptied the technology"
		)
		support.assert_entry(runner, "technology", "TECH-13")
	end)

	runner.test("TECH-14 include_productivity_effects blacklists the recipe in data", function()
		-- The blacklist marker is a data-stage-only custom field, so the fixture
		-- asserts it. The recorded result is the runtime contract.
		support.assert_entry(runner, "technology", "TECH-14")
	end)

	runner.test("TECH-15 include_productivity_effects tolerates an unknown recipe", function()
		support.assert_entry(runner, "technology", "TECH-15")
	end)

	runner.test("TECH-16 include_productivity_effects blacklists the recipe in data-updates", function()
		support.assert_entry(runner, "technology_excise_updates", "TECH-16")

		local tech = prototypes.technology["funit-tech-excise-updates-tech"]
		runner.assert(tech and tech.hidden, "the data-updates technology emptied by excision is not hidden")
		runner.assert(#tech.effects == 0, "the data-updates technology still has effects")

		local child = prototypes.technology["funit-tech-excise-updates-child"]
		runner.assert(child, "funit-tech-excise-updates-child is missing")
		runner.assert(
			has_prereq(child, "funit-tech-excise-updates-root")
				and not has_prereq(child, "funit-tech-excise-updates-tech"),
			"prerequisites were not promoted during the data-updates excision"
		)
	end)

	runner.test("TECH-17 include_productivity_effects does not blacklist in data-final-fixes", function()
		support.assert_entry(runner, "technology_final", "TECH-17")

		local tech = prototypes.technology["funit-tech-excise-final-tech"]
		runner.assert(tech, "funit-tech-excise-final-tech is missing")
		runner.assert(tech.hidden == true, "the data-final-fixes technology emptied by excision is not hidden")
		runner.assert(#tech.effects == 0, "the data-final-fixes technology still has effects")
	end)

	runner.test("TECH-5 sort_science_pack_names sorts by order without mutating", function()
		-- sort_science_pack_names reads data.raw, so the data-stage fixture is the
		-- only place it can run. This asserts its recorded result explicitly.
		support.assert_entry(runner, "technology", "TECH-5")
	end)

	runner.test("TECH-6 set_science_packs_from_lab adds inputs and skips unlocked packs", function()
		-- Pure behavior: a synthetic lab and technology can be used at runtime.
		local lab = { inputs = { "funit-pack-a", "funit-pack-b", "funit-pack-c" } }
		local tech = { unit = { ingredients = { { "funit-pack-a", 1 } } }, effects = {} }
		technology.set_science_packs_from_lab(tech, lab)
		runner.assert(#tech.unit.ingredients == 3, "expected 3 ingredients, got " .. #tech.unit.ingredients)
		for _, name in ipairs(lab.inputs) do
			runner.assert(contains_ingredient(tech.unit.ingredients, name), "missing lab input " .. name)
		end

		local skip = {
			unit = { ingredients = {} },
			effects = { { type = "unlock-recipe", recipe = "funit-pack-b" } },
		}
		technology.set_science_packs_from_lab(skip, lab)
		runner.assert(#skip.unit.ingredients == 2, "the unlocked pack was not skipped")
		runner.assert(
			not contains_ingredient(skip.unit.ingredients, "funit-pack-b"),
			"the unlocked pack was added anyway"
		)

		runner.assert(not pcall(technology.set_science_packs_from_lab, nil, lab), "a nil technology must error")
		runner.assert(not pcall(technology.set_science_packs_from_lab, {}, lab), "a missing unit must error")
		runner.assert(
			not pcall(technology.set_science_packs_from_lab, { unit = { ingredients = {} } }, nil),
			"a nil lab must error"
		)

		-- The fixture's real prototypes. At runtime a lab exposes `lab_inputs`
		-- and a technology exposes `research_unit_ingredients` (the `unit`
		-- table is data-stage only).
		local lab_prototype = prototypes.entity["lab"]
		runner.assert(lab_prototype and lab_prototype.lab_inputs, "the vanilla lab prototype is missing")

		local all = prototypes.technology["funit-tech-lab"]
		runner.assert(all and all.research_unit_ingredients, "funit-tech-lab is missing")
		for _, input in ipairs(lab_prototype.lab_inputs) do
			runner.assert(
				contains_ingredient(all.research_unit_ingredients, input),
				"funit-tech-lab is missing the lab input " .. input
			)
		end

		local skip_prototype = prototypes.technology["funit-tech-lab-skip"]
		runner.assert(skip_prototype, "funit-tech-lab-skip is missing")
		runner.assert(
			#skip_prototype.research_unit_ingredients == #lab_prototype.lab_inputs - 1,
			"the skipped-pack technology has the wrong ingredient count"
		)
	end)

	runner.test("TECH-7 technology_icon_planet / technology_icon_moon", function()
		-- Technology icons are data-stage fields and are not exposed by
		-- LuaTechnologyPrototype at runtime; the data-stage fixture TECH-7
		-- asserts the exact icon lists. This test only checks the prototypes
		-- survived and points at the recorded result.
		runner.assert(prototypes.technology["funit-tech-icon-planet"], "funit-tech-icon-planet is missing")
		runner.assert(prototypes.technology["funit-tech-icon-moon"], "funit-tech-icon-moon is missing")
		support.assert_entry(runner, "technology", "TECH-7")
	end)

	runner.test("TECH-8 cargo_drops_technology_base and its helpers", function()
		local prototype = prototypes.technology["planetslib-funit-cargo-planet-cargo-drops"]
		runner.assert(prototype, "the cargo-drop technology prototype is missing")
		runner.assert(
			#prototype.effects == 1 and prototype.effects[1].type == "nothing",
			"the cargo-drop technology should have a single `nothing` effect"
		)
		runner.assert(
			prototype.effects[1].effect_description[2] == "[space-location=funit-cargo-planet]",
			"the cargo-drop effect does not reference the planet"
		)
		-- The four-entry icon list is data-stage only (the TECH-8 fixture asserts
		-- it); runtime LuaTechnologyPrototype doesn't expose `icons`.

		local icon = "__base__/graphics/icons/iron-plate.png"
		local icons = technology.technology_icons_planet_cargo_drops(icon, 64)
		runner.assert(#icons == 4, "the cargo-drop icon helper should return 4 entries")
		runner.assert(icons[2].icon == icon, "the planet icon was not inserted at index 2")
		runner.assert(icons[2].scale == 0.65 * 256 / 64, "the planet icon scale is wrong")

		local mini = technology.technology_icons_planet_cargo_drops(icon, 64, true)
		runner.assert(
			mini[2].shift[1] == 0 and mini[2].shift[2] == 0,
			"the mini variant should not be shifted"
		)

		local effects = technology.technology_effect_cargo_drops("funit-cargo-planet", { { icon = icon } })
		runner.assert(
			#effects == 1 and effects[1].type == "nothing",
			"the cargo-drop effect helper is malformed"
		)

		runner.assert(
			not pcall(technology.cargo_drops_technology_base, nil, icon, 64),
			"a nil planet must raise an error"
		)
		runner.assert(
			not pcall(technology.cargo_drops_technology_base, "funit-cargo-planet", nil, 64),
			"a nil planet icon must raise an error"
		)
		runner.assert(
			not pcall(technology.cargo_drops_technology_base, "funit-cargo-planet", icon, nil),
			"a nil planet icon size must raise an error"
		)
	end)
end
