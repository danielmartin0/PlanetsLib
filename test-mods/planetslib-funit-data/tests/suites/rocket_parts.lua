-- Rocket-part recipe assignment on built rocket silos (scripts/rocket-parts.lua)
-- and the fits_surface_conditions helper it depends on.
--
-- There is no `planetslib_funit` seam for `on_built_rocket_silo`, and FUnit's
-- event mocker cannot reach it in a base-only game (the combined on_built_entity
-- handler only calls it when Space Age / cargo pods are active). The suite
-- therefore requires the module directly and drives it with small test doubles
-- for the entity and its surface, while `fits_surface_conditions` and
-- `multiple_rocket_parts_can_be_crafted_in_vanilla_silo` run against the real
-- runtime prototypes. No real entities are created, so there is nothing to clean
-- up. The data-stage `rocket_parts_setup` fixture installs the mod-data.

local support = require("__planetslib-funit-data__.tests.suites.support")

-- Surface property created by the fixture's PlanetsLib.assign_rocket_part_recipe
-- call (see rocket_parts_setup.lua). Its default_value is 0.
local MARKER = "PlanetsLib-is-funit-rocket-planet"

return function(runner)
	if not script.active_mods["space-age"] then
		return
	end

	-- lib.surface-property-lib reads the PlanetsLib global (set in PlanetsLib's
	-- own control stage, which is a separate Lua state). Recreate the runtime
	-- marker in this state.
	_G.PlanetsLib = _G.PlanetsLib or {}
	_G.PlanetsLib.stage = "runtime"

	package.loaded["lib.predicates"] = require("__PlanetsLib__.lib.predicates")
	package.loaded["lib.remove-replace-object"] = require("__PlanetsLib__.lib.remove-replace-object")
	local surface_properties_lib = require("__PlanetsLib__.lib.surface-property-lib")
	package.loaded["lib.surface-property-lib"] = surface_properties_lib
	local rocket_parts = require("__PlanetsLib__.scripts.rocket-parts")

	-- A stand-in for a surface that only supports get_property (all the handler
	-- and fits_surface_conditions touch).
	local function make_surface(name, properties)
		properties = properties or {}
		return {
			name = name,
			get_property = function(property)
				return properties[property] or 0
			end,
		}
	end

	-- A stand-in for a rocket silo / rocket-silo ghost.
	local function make_silo(surface, overrides)
		local entity = {
			valid = true,
			type = "rocket-silo",
			name = "rocket-silo",
			surface = surface,
			prototype = { crafting_categories = { ["rocket-building"] = true } },
			recipe_locked = false,
			recipes = {},
		}
		entity.set_recipe = function(recipe)
			entity.recipes[#entity.recipes + 1] = recipe
			entity.recipe = recipe
		end
		for key, value in pairs(overrides or {}) do
			entity[key] = value
		end
		return entity
	end

	-- The rocket-building recipes that fit a surface, computed independently of
	-- the auto-lock helper. This is only used to assert the precondition of the
	-- RP-3 heuristic; the expected lock value itself is written literally.
	local function fitting_rocket_recipes(surface)
		local names = {}
		for _, recipe in pairs(prototypes.get_recipe_filtered({ { filter = "category", category = "rocket-building" } })) do
			if recipe.surface_conditions == nil or surface_properties_lib.fits_surface_conditions(recipe, surface) then
				names[#names + 1] = recipe.name
			end
		end
		table.sort(names)
		return names
	end

	local function contains_name(names, name)
		for _, value in ipairs(names) do
			if value == name then
				return true
			end
		end
		return false
	end

	runner.test("RP-1 recipe assignment, default and '_other'", function()
		support.assert_entry(runner, "rocket_parts_setup", "RP-FIXTURE-1")

		-- A planet with an assigned recipe.
		local assigned = make_silo(make_surface("funit-rocket-planet"))
		rocket_parts.on_built_rocket_silo({ entity = assigned })
		runner.assert(assigned.recipe == "funit-rocket-recipe-a",
			"the assigned recipe was not set (got " .. tostring(assigned.recipe) .. ")")

		-- A surface with no assignment falls back to the "default" entry.
		local defaulted = make_silo(make_surface("funit-rocket-default-surface"))
		rocket_parts.on_built_rocket_silo({ entity = defaulted })
		runner.assert(defaulted.recipe == "rocket-part",
			"an unassigned surface did not fall back to the default recipe (got " .. tostring(defaulted.recipe) .. ")")

		-- "_other" means the surface opts out; the handler must do nothing.
		local other = make_silo(make_surface("funit-rocket-other"))
		rocket_parts.on_built_rocket_silo({ entity = other })
		runner.assert(#other.recipes == 0, "'_other' must not assign a recipe")
		runner.assert(other.recipe_locked == false, "'_other' must not change the silo lock")
	end)

	runner.test("RP-2 lock behaviour", function()
		-- Explicit lock = true.
		local locked = make_silo(make_surface("funit-rocket-planet"))
		rocket_parts.on_built_rocket_silo({ entity = locked })
		runner.assert(locked.recipe_locked == true, "an explicitly locked silo was not locked")

		-- Explicit lock = false.
		local unlocked = make_silo(make_surface("funit-rocket-unlocked"))
		rocket_parts.on_built_rocket_silo({ entity = unlocked })
		runner.assert(unlocked.recipe_locked == false, "an explicitly unlocked silo was locked")

		-- A silo that is already locked keeps its lock: the handler only assigns
		-- the lock when recipe_locked == false.
		local prelocked = make_silo(make_surface("funit-rocket-unlocked"), { recipe_locked = true })
		rocket_parts.on_built_rocket_silo({ entity = prelocked })
		runner.assert(prelocked.recipe_locked == true, "an already-locked silo lost its lock")
	end)

	runner.test("RP-3 auto-lock heuristic and ghost silos", function()
		-- Precondition for the multi-recipe case: more than one rocket-building
		-- recipe fits the surface, including the fixture's own recipes. This is
		-- counted independently of multiple_rocket_parts_can_be_crafted_in_-
		-- vanilla_silo(), whose result the assertions below must not reuse.
		local multi = make_surface("funit-rocket-autolock-multi", { [MARKER] = 1 })
		local multi_recipes = fitting_rocket_recipes(multi)
		runner.assert(#multi_recipes >= 2,
			"fixture error: expected more than one rocket-building recipe to fit the 'multi' surface, got "
				.. #multi_recipes .. ": " .. table.concat(multi_recipes, ", "))
		runner.assert(
			contains_name(multi_recipes, "funit-rocket-recipe-a")
				and contains_name(multi_recipes, "funit-rocket-recipe-fit-1")
				and contains_name(multi_recipes, "funit-rocket-recipe-fit-2"),
			"fixture error: the fixture's rocket recipes do not fit the 'multi' surface: "
				.. table.concat(multi_recipes, ", ")
		)

		local multi_silo = make_silo(multi)
		rocket_parts.on_built_rocket_silo({ entity = multi_silo })
		runner.assert(multi_silo.recipe == "funit-rocket-recipe-a",
			"the auto-lock surface did not receive its recipe")
		-- Literal expectation: with more than one fitting recipe, locking is
		-- disabled. Do not derive this from the heuristic under test.
		runner.assert(multi_silo.recipe_locked == false,
			"the silo must not be locked when multiple rocket-part recipes fit")

		-- Precondition for the single-recipe case: exactly one rocket-building
		-- recipe fits (the vanilla rocket-part). The fixture's recipes are
		-- restricted to the marker=1 planet, and the 'single' surface's marker
		-- defaults to 0.
		local single = make_surface("funit-rocket-autolock-single")
		local single_recipes = fitting_rocket_recipes(single)
		runner.assert(#single_recipes == 1,
			"fixture error: expected exactly one rocket-building recipe to fit the 'single' surface, got "
				.. #single_recipes .. ": " .. table.concat(single_recipes, ", "))
		runner.assert(single_recipes[1] == "rocket-part",
			"fixture error: expected 'rocket-part' to be the only recipe fitting the 'single' surface, got "
				.. tostring(single_recipes[1]))

		-- The heuristic itself must report the literal answers the two surfaces
		-- were built to produce; this is not used to derive the lock values.
		runner.assert(
			surface_properties_lib.multiple_rocket_parts_can_be_crafted_in_vanilla_silo(multi) == true,
			"the heuristic should report multiple rocket-part recipes for the 'multi' surface"
		)
		runner.assert(
			surface_properties_lib.multiple_rocket_parts_can_be_crafted_in_vanilla_silo(single) == false,
			"the heuristic should report a single rocket-part recipe for the 'single' surface"
		)

		local single_silo = make_silo(single)
		rocket_parts.on_built_rocket_silo({ entity = single_silo })
		runner.assert(single_silo.recipe == "funit-rocket-recipe-a",
			"the single-recipe surface did not receive its recipe")
		-- Literal expectation: with exactly one fitting recipe, the silo locks.
		runner.assert(single_silo.recipe_locked == true,
			"the silo must be locked when only one rocket-part recipe fits")

		-- Ghost silos use ghost_prototype and still receive the recipe. The double
		-- models the handler's Lua branch only; whether the engine lets a real
		-- entity-ghost expose set_recipe/recipe_locked is unverified (see the
		-- suspected-bug note in the suite report for this file).
		local ghost = make_silo(multi, {
			type = "entity-ghost",
			name = "entity-ghost",
			ghost_type = "rocket-silo",
			ghost_prototype = { crafting_categories = { ["rocket-building"] = true } },
		})
		ghost.prototype = nil
		rocket_parts.on_built_rocket_silo({ entity = ghost })
		runner.assert(ghost.recipe == "funit-rocket-recipe-a", "a ghost silo did not receive the recipe")
	end)

	runner.test("RP-4 non-rocket entities are ignored and fits_surface_conditions", function()
		-- Not a rocket silo (and not a rocket-silo ghost): ignored before any lookup.
		local machine = make_silo(make_surface("funit-rocket-planet"),
			{ type = "assembling-machine", name = "assembling-machine-3" })
		rocket_parts.on_built_rocket_silo({ entity = machine })
		runner.assert(#machine.recipes == 0, "a non-rocket-silo entity must be ignored")

		-- Invalid entities are ignored.
		rocket_parts.on_built_rocket_silo({ entity = { valid = false } })

		-- A rocket silo without the rocket-building category is ignored.
		local no_category = make_silo(make_surface("funit-rocket-planet"),
			{ prototype = { crafting_categories = {} } })
		rocket_parts.on_built_rocket_silo({ entity = no_category })
		runner.assert(#no_category.recipes == 0,
			"a silo without the rocket-building category must be ignored")

		-- fits_surface_conditions: a missing surface_conditions field is an error.
		local ok, err = pcall(surface_properties_lib.fits_surface_conditions, {}, make_surface("funit-rocket-planet"))
		runner.assert(not ok, "fits_surface_conditions must assert when the entity has no surface_conditions")
		runner.assert(tostring(err):find("surface_conditions", 1, true),
			"the assertion message should mention surface_conditions")

		-- In-range values fit, out-of-range values do not. Conditions here always
		-- provide both min and max (the runtime branch compares against both).
		local marker = prototypes.surface_property[MARKER]
		runner.assert(marker, "the fixture's '" .. MARKER .. "' surface property is missing at runtime")
		local default = marker.default_value
		runner.assert(default == 0, "the fixture surface property should default to 0")

		local entity = { surface_conditions = { { property = MARKER, min = default, max = default } } }
		runner.assert(
			surface_properties_lib.fits_surface_conditions(entity, { get_property = function() return default end }),
			"a value equal to the min/max should fit"
		)
		runner.assert(
			not surface_properties_lib.fits_surface_conditions(entity,
				{ get_property = function() return default + 10 end }),
			"a value above max should not fit"
		)
		runner.assert(
			not surface_properties_lib.fits_surface_conditions(entity,
				{ get_property = function() return default - 10 end }),
			"a value below min should not fit"
		)

		-- Without surface.get_property the prototype default_value is used.
		runner.assert(
			surface_properties_lib.fits_surface_conditions(entity, {}),
			"fits_surface_conditions should fall back to the prototype default value"
		)
	end)
end
