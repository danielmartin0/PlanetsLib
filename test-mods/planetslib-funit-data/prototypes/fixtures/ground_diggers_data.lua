-- Data-stage fixture: PlanetsLib.enable_ground_diggers() configuration and the
-- pure helpers in lib/ground-diggers.lua.
--
-- The generation pass itself runs in PlanetsLib's own data-final-fixes, after
-- this fixture. ground_diggers_late.lua asserts the resulting prototypes; this
-- file only sets up the planets/recipes and records checks that can run before
-- then (validation, option normalisation, eligibility and create_ground_digger).

local results = require("lib.results")
local ground_diggers = require("__PlanetsLib__.lib.ground-diggers")

local SUITE = "ground_diggers_data"
local MARKER = "PlanetsLib-has-ground-diggers"

local function record(id, fn)
	local ok, err = pcall(fn)
	results.record(SUITE, id, ok, err)
end

local function list_contains(list, value)
	for _, entry in ipairs(list or {}) do
		if entry == value then
			return true
		end
	end
	return false
end

-- Shared setup. Kept in one pcall so a broken setup is reported instead of
-- crashing the whole data stage.
local setup_ok, setup_err = pcall(function()
	data:extend({
		{ type = "recipe-category", name = "funit-gd-category-a" },
		{ type = "recipe-category", name = "funit-gd-category-b" },
		{ type = "recipe-category", name = "funit-gd-late-category" },
	})

	local function add_recipe(name, categories, item)
		local recipe = {
			type = "recipe",
			name = name,
			energy_required = 1,
			ingredients = {},
			results = { { type = "item", name = item, amount = 1 } },
			enabled = true,
			main_product = item,
		}
		if categories then
			recipe.categories = categories
		end
		data:extend({ recipe })
	end

	add_recipe("funit-gd-recipe-a", { "funit-gd-category-a" }, "stone")
	add_recipe("funit-gd-recipe-b", { "funit-gd-category-b" }, "copper-ore")
	add_recipe("funit-gd-recipe-default", nil, "iron-ore")
	add_recipe("funit-gd-late-recipe", { "funit-gd-late-category" }, "coal")

	local function add_planet(name)
		local planet = table.deepcopy(data.raw.planet.nauvis)
		planet.name = name
		planet.surface_properties = {}
		data:extend({ planet })
		return data.raw.planet[name]
	end

	add_planet("funit-gd-planet")
	add_planet("funit-gd-planet-b")
	add_planet("funit-gd-planet-c")
	add_planet("funit-gd-idle")
	add_planet("funit-gd-late")

	-- A drill whose own surface condition can never be met on a normal surface.
	-- It is still eligible (square, has a placing item) and exercises both the
	-- inherited condition on the generated digger and the runtime build check.
	local conditioned = table.deepcopy(data.raw["mining-drill"]["electric-mining-drill"])
	conditioned.name = "funit-gd-conditioned-drill"
	conditioned.minable = { mining_time = 0.2, result = "funit-gd-conditioned-drill" }
	conditioned.surface_conditions = { { property = "pressure", min = 1e9, max = 2e9 } }
	conditioned.next_upgrade = nil
	conditioned.fast_replaceable_group = "funit-gd-conditioned"
	data:extend({ conditioned })

	local conditioned_item = table.deepcopy(data.raw.item["electric-mining-drill"])
	conditioned_item.name = "funit-gd-conditioned-drill"
	conditioned_item.place_result = "funit-gd-conditioned-drill"
	data:extend({ conditioned_item })

	-- A technology with a mining-drill-productivity-bonus effect. PlanetsLib's
	-- final-fixes should add change-recipe-productivity effects for every
	-- configured ground-digger recipe.
	data:extend({
		{
			type = "technology",
			name = "funit-gd-productivity-tech",
			icon = "__base__/graphics/technology/mining-productivity.png",
			icon_size = 256,
			prerequisites = {},
			effects = { { type = "mining-drill-productivity-bonus", modifier = 0.2 } },
			unit = { count = 1, time = 1, ingredients = { { "automation-science-pack", 1 } } },
			order = "funit-gd",
		},
	})

	-- Final configuration consumed by PlanetsLib's data-final-fixes.
	PlanetsLib.enable_ground_diggers("funit-gd-planet", "funit-gd-recipe-a", {
		drills = { "electric-mining-drill", "burner-mining-drill", "funit-gd-conditioned-drill" },
		blacklist = { "burner-mining-drill" },
	})
	PlanetsLib.enable_ground_diggers("funit-gd-planet-b", "funit-gd-recipe-b")
	PlanetsLib.enable_ground_diggers("funit-gd-planet-c", "funit-gd-recipe-default")
end)
results.record(SUITE, "GD-0-setup", setup_ok, setup_err)
if not setup_ok then
	return true
end

-- GD-1a: argument validation and prototype-table input.
record("GD-1a", function()
	local configs = PlanetsLib.constants.ground_diggers

	assert(
		not pcall(PlanetsLib.enable_ground_diggers, 123, "funit-gd-recipe-a"),
		"a numeric planet argument must be rejected"
	)
	assert(
		not pcall(PlanetsLib.enable_ground_diggers, { name = 123 }, "funit-gd-recipe-a"),
		"a numeric planet prototype name must be rejected"
	)
	assert(
		not pcall(PlanetsLib.enable_ground_diggers, "funit-gd-planet", 123),
		"a numeric recipe argument must be rejected"
	)
	assert(
		not pcall(PlanetsLib.enable_ground_diggers, nil, "funit-gd-recipe-a"),
		"a nil planet argument must be rejected"
	)
	assert(
		not pcall(PlanetsLib.enable_ground_diggers, "funit-gd-planet", nil),
		"a nil recipe argument must be rejected"
	)

	-- A planet prototype table is unwrapped to its name.
	PlanetsLib.enable_ground_diggers(data.raw.planet["funit-gd-planet"], "funit-gd-recipe-a")
	assert(
		configs["funit-gd-planet"] and configs["funit-gd-planet"].recipe == "funit-gd-recipe-a",
		"a planet prototype argument did not select the planet name"
	)
end)

-- GD-1b: option normalisation (arrays and dictionaries).
record("GD-1b", function()
	local configs = PlanetsLib.constants.ground_diggers

	PlanetsLib.enable_ground_diggers("funit-gd-planet", "funit-gd-recipe-a", {
		drills = { "electric-mining-drill", "burner-mining-drill" },
		blacklist = { ["burner-mining-drill"] = true, ["pumpjack"] = false },
	})
	local config = configs["funit-gd-planet"]
	assert(config.drills["electric-mining-drill"] == true, "array drills were not normalised")
	assert(config.drills["burner-mining-drill"] == true, "array drills were not normalised")
	assert(config.drills[1] == nil, "normalised drills kept numeric keys")
	assert(config.blacklist["burner-mining-drill"] == true, "dictionary blacklist entries were dropped")
	assert(config.blacklist["pumpjack"] == nil, "false dictionary entries must be ignored")
	assert(config.diggers == nil, "changing the config must reset the resolved diggers")

	-- The dictionary form for drills, with a false entry.
	PlanetsLib.enable_ground_diggers("funit-gd-planet", "funit-gd-recipe-a", {
		drills = { ["electric-mining-drill"] = true, ["burner-mining-drill"] = false },
	})
	config = configs["funit-gd-planet"]
	assert(config.drills["electric-mining-drill"] == true, "dictionary drills were not normalised")
	assert(config.drills["burner-mining-drill"] == nil, "false dictionary entries must be ignored")
	assert(config.blacklist == nil, "an omitted blacklist should be nil")

	-- Restore the configuration used by the generation assertions.
	PlanetsLib.enable_ground_diggers("funit-gd-planet", "funit-gd-recipe-a", {
		drills = { "electric-mining-drill", "burner-mining-drill", "funit-gd-conditioned-drill" },
		blacklist = { "burner-mining-drill" },
	})
end)

-- GD-2: eligibility exclusions.
record("GD-2", function()
	local item_lookup = {
		["funit-eligible-drill"] = "funit-eligible-item",
		["funit-fluid-drill"] = "funit-fluid-item",
		["funit-nonsquare-drill"] = "funit-nonsquare-item",
		["funit-iron-ore-drill"] = "funit-iron-ore-item",
		["funit-normal-drill"] = "funit-normal-item",
		["funit-variant-drill"] = "funit-variant-item",
	}

	local function drill(name, overrides)
		local prototype = {
			name = name,
			type = "mining-drill",
			selection_box = { { -1, -1 }, { 1, 1 } },
			tile_width = 2,
			tile_height = 2,
		}
		for key, value in pairs(overrides or {}) do
			prototype[key] = value
		end
		return prototype
	end

	assert(
		ground_diggers.is_eligible_drill(drill("funit-eligible-drill"), item_lookup),
		"a plain square drill with a placing item should be eligible"
	)
	assert(
		not ground_diggers.is_eligible_drill(drill("funit-fluid-drill", { output_fluid_box = {} }), item_lookup),
		"fluid-output drills must be excluded"
	)
	assert(
		not ground_diggers.is_eligible_drill(
			drill("funit-nonsquare-drill", { selection_box = { { -1, -1 }, { 1, 0 } } }),
			item_lookup
		),
		"non-square drills must be excluded"
	)
	assert(
		not ground_diggers.is_eligible_drill(drill("funit-no-item-drill"), item_lookup),
		"drills without a placing item must be excluded"
	)
	assert(
		not ground_diggers.is_eligible_drill(drill("funit-iron-ore-drill"), item_lookup),
		"resource-named drill variants must be excluded"
	)
	if next(data.raw["quality"] or {}) then
		assert(
			not ground_diggers.is_eligible_drill(drill("funit-normal-drill"), item_lookup),
			"quality-named drill variants must be excluded"
		)
	end
	assert(
		not ground_diggers.is_eligible_drill(
			drill("funit-variant-drill", { PlanetsLib_do_not_generate_variants = true }),
			item_lookup
		),
		"PlanetsLib_do_not_generate_variants must exclude a drill"
	)
	assert(not ground_diggers.is_eligible_drill(nil, item_lookup), "nil must not be eligible")
	local no_selection_box = drill("funit-eligible-drill")
	no_selection_box.selection_box = nil
	assert(
		not ground_diggers.is_eligible_drill(no_selection_box, item_lookup),
		"drills without a selection box must be excluded"
	)
	assert(
		ground_diggers.ground_digger_name("funit-eligible-drill") == "funit-eligible-drill-ground-digger",
		"ground_digger_name did not use the <drill>-ground-digger scheme"
	)
end)

-- GD-3: create_ground_digger field mapping, stripping, drain, conditions and flags.
record("GD-3", function()
	local base = table.deepcopy(data.raw["mining-drill"]["electric-mining-drill"])
	base.name = "funit-gd-create-drill"
	base.localised_name = nil
	base.surface_conditions = { { property = "pressure", min = 1000, max = 1000 } }
	base.mining_speed = 2.5
	base.resource_categories = { "basic-solid" }
	base.resource_drain_rate_percent = 50
	base.resource_searching_radius = 9
	base.next_upgrade = "electric-mining-drill"
	base.fast_replaceable_group = "funit-gd-create-group"
	base.flags = { "placeable-neutral" }
	base.energy_source = table.deepcopy(base.energy_source)
	base.energy_source.drain = nil

	local categories = { "funit-gd-category-a", "crafting" }
	local digger =
		ground_diggers.create_ground_digger(base, "funit-gd-create-digger", "electric-mining-drill", categories)

	assert(digger.name == "funit-gd-create-digger", "the digger's name was not set")
	assert(digger.type == "assembling-machine", "the digger should be an assembling machine")
	assert(digger.crafting_categories[1] == "funit-gd-category-a", "the first crafting category was lost")
	assert(digger.crafting_categories[2] == "crafting", "the second crafting category was lost")
	assert(digger.crafting_speed == 2.5, "crafting_speed should fall back to mining_speed")
	assert(digger.placeable_by.item == "electric-mining-drill", "placeable_by.item was not set")
	assert(digger.placeable_by.count == 1, "placeable_by.count was not set")
	assert(
		digger.fast_replaceable_group == "funit-gd-create-group-ground-digger",
		"fast_replaceable_group was not suffixed"
	)
	assert(digger.next_upgrade == nil, "next_upgrade should be stripped")
	assert(digger.hidden_in_factoriopedia == false, "the digger should be visible in Factoriopedia")
	assert(
		digger.localised_name[1] == "entity-name.PlanetsLib-ground-digger",
		"the digger's localised name is missing the shared key"
	)
	assert(
		digger.localised_name[2][1] == "entity-name.funit-gd-create-drill",
		"the digger's localised name lost the original name"
	)
	assert(
		digger.localised_description[1] == "entity-description.PlanetsLib-ground-digger",
		"the digger's localised description key is wrong"
	)

	local expected_effects = { "productivity", "consumption", "speed", "pollution", "quality" }
	assert(#digger.allowed_effects == #expected_effects, "allowed_effects has the wrong length")
	for index, effect in ipairs(expected_effects) do
		assert(digger.allowed_effects[index] == effect, "allowed_effects[" .. index .. "] is wrong")
	end

	assert(#digger.surface_conditions == 2, "the digger should inherit one condition and add the marker")
	assert(digger.surface_conditions[1].property == "pressure", "the drill's surface condition was lost")
	assert(digger.surface_conditions[1].min == 1000, "the drill's surface condition changed")
	assert(
		digger.surface_conditions[2].property == MARKER,
		"the participating-planet surface condition was not appended"
	)
	assert(
		digger.surface_conditions[2].min == 1 and digger.surface_conditions[2].max == 1,
		"the participating-planet surface condition should require exactly 1"
	)

	assert(digger.mining_speed == nil, "mining_speed should be stripped")
	assert(digger.resource_categories == nil, "resource_categories should be stripped")
	assert(digger.resource_drain_rate_percent == nil, "resource_drain_rate_percent should be stripped")
	assert(digger.resource_searching_radius == nil, "resource_searching_radius should be stripped")

	assert(digger.energy_source.type == "electric", "the energy source type changed")
	assert(digger.energy_source.drain == "0MW", "an electric digger with no drain should default to 0MW")
	assert(list_contains(digger.flags, "not-in-made-in"), "not-in-made-in was not added")
	assert(list_contains(digger.flags, "not-in-bonus-gui"), "not-in-bonus-gui was not added")
	assert(list_contains(digger.flags, "placeable-neutral"), "the drill's flags were lost")

	-- The source drill must not be mutated.
	assert(base.name == "funit-gd-create-drill", "the source drill was renamed")
	assert(#base.surface_conditions == 1, "the source drill's surface conditions were mutated")
	assert(base.energy_source.drain == nil, "the source drill's drain was mutated")
	assert(#base.flags == 1, "the source drill's flags were mutated")
	assert(base.mining_speed == 2.5, "the source drill's mining_speed was mutated")

	-- The categories argument is deep-copied, not aliased.
	digger.crafting_categories[1] = "mutated"
	assert(categories[1] == "funit-gd-category-a", "the categories argument was aliased")

	-- An existing drain is preserved.
	local with_drain = table.deepcopy(base)
	with_drain.name = "funit-gd-drain-drill"
	with_drain.energy_source.drain = "1kW"
	local drain_digger = ground_diggers.create_ground_digger(
		with_drain,
		"funit-gd-drain-digger",
		"electric-mining-drill",
		categories
	)
	assert(drain_digger.energy_source.drain == "1kW", "an existing electric drain was overwritten")

	-- Non-electric energy sources keep their type and get no drain default.
	local burner = table.deepcopy(data.raw["mining-drill"]["burner-mining-drill"])
	burner.name = "funit-gd-burner-create"
	local burner_digger = ground_diggers.create_ground_digger(
		burner,
		"funit-gd-burner-create-digger",
		"burner-mining-drill",
		categories
	)
	assert(burner_digger.energy_source.type == "burner", "a burner digger lost its energy source type")
	assert(burner_digger.energy_source.drain == nil, "a non-electric digger should not gain a drain")
end)

return true
