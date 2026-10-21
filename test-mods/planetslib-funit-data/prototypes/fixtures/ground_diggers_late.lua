-- Data-final-fixes fixture: ground digger generation, late registration and
-- mining-productivity integration.
--
-- This runs after PlanetsLib's own data-final-fixes pass, so the prototypes for
-- the planets configured in `ground_diggers_data.lua` already exist. Everything
-- here exercises `generate_ground_diggers()` and the late
-- `enable_ground_diggers()` path.

local results = require("lib.results")
local ground_diggers = require("__PlanetsLib__.lib.ground-diggers")

local SUITE = "ground_diggers_late"
local MARKER = "PlanetsLib-has-ground-diggers"
local IDLE_PLANET = "funit-gd-idle"
local LATE_PLANET = "funit-gd-late"
local MISSING_PLANET = "funit-gd-missing-planet"

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

local function get_configs()
	return PlanetsLib.constants.ground_diggers
end

-- Remove any temporary configuration / surface-property side effects left by
-- the error-path tests. `generate_ground_diggers` marks a planet as
-- participating before it validates the recipe, so a failed generation can
-- leave the marker behind.
local function reset_idle_planet()
	local idle = data.raw.planet[IDLE_PLANET]
	if idle and idle.surface_properties then
		idle.surface_properties[MARKER] = nil
	end
	get_configs()[IDLE_PLANET] = nil
end

local function effects_for(technology, recipe_name)
	local matches = {}
	for _, effect in ipairs(technology.effects or {}) do
		if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
			matches[#matches + 1] = effect
		end
	end
	return matches
end

local function assert_recipe_productivity(technology, recipe_name, change)
	local effects = effects_for(technology, recipe_name)
	assert(
		#effects == 1,
		"expected exactly one change-recipe-productivity effect for '"
			.. recipe_name
			.. "' in '"
			.. technology.name
			.. "', got "
			.. #effects
	)
	assert(
		effects[1].change == change,
		"the productivity change for '"
			.. recipe_name
			.. "' in '"
			.. technology.name
			.. "' is "
			.. tostring(effects[1].change)
			.. ", expected "
			.. tostring(change)
	)
	assert(effects[1].hidden == true, "the productivity effect for '" .. recipe_name .. "' should be hidden")
end

-- GD-1c: calling enable_ground_diggers() during data-final-fixes must record the
-- configuration and generate the prototypes immediately.
record("GD-1c", function()
	local configs = get_configs()
	assert(configs[LATE_PLANET] == nil, "the late planet was configured before the late-enable check")

	PlanetsLib.enable_ground_diggers(LATE_PLANET, "funit-gd-late-recipe")

	local config = configs[LATE_PLANET]
	assert(config, "the late enable_ground_diggers call did not record a configuration")
	assert(config.recipe == "funit-gd-late-recipe", "the late configuration has the wrong recipe")
	assert(config.diggers and next(config.diggers), "the late call did not resolve any diggers")

	local planet = data.raw.planet[LATE_PLANET]
	assert(planet, "the late planet prototype is missing")
	assert(
		planet.surface_properties[MARKER] == 1,
		"the late planet did not receive the ground-digger surface property"
	)

	local digger = data.raw["assembling-machine"]["electric-mining-drill-ground-digger"]
	assert(digger, "the late call did not create the shared electric-mining-drill digger")
	assert(
		list_contains(digger.crafting_categories, "funit-gd-late-category"),
		"the late recipe's crafting category was not added to the shared digger"
	)
end)

-- GD-4a: shared naming, category union, marker property, exclusion and inherited
-- surface conditions.
record("GD-4a", function()
	local digger = data.raw["assembling-machine"]["electric-mining-drill-ground-digger"]
	assert(digger, "the shared electric-mining-drill digger is missing")
	assert(digger.name == "electric-mining-drill-ground-digger", "the shared digger name is wrong")
	assert(digger.type == "assembling-machine", "the shared digger should be an assembling machine")
	assert(
		digger.placeable_by and digger.placeable_by.item == "electric-mining-drill",
		"the shared digger is not placeable by the electric mining drill"
	)

	-- Every configured planet's recipe category must be accepted by the shared
	-- prototype, because the recipe is only chosen at runtime.
	for _, category in ipairs({
		"funit-gd-category-a",
		"funit-gd-category-b",
		"funit-gd-late-category",
		"crafting",
	}) do
		assert(
			list_contains(digger.crafting_categories, category),
			"the shared digger is missing the '" .. category .. "' crafting category"
		)
	end

	local property = data.raw["surface-property"][MARKER]
	assert(property, "the ground-digger surface property was not created")
	assert(property.type == "surface-property", "the ground-digger marker has the wrong prototype type")
	assert(property.hidden == true, "the ground-digger marker should be hidden")
	assert(property.hidden_in_factoriopedia == true, "the ground-digger marker should be hidden in Factoriopedia")
	assert(property.default_value == 0, "the ground-digger marker should default to 0")

	for _, planet_name in ipairs({
		"funit-gd-planet",
		"funit-gd-planet-b",
		"funit-gd-planet-c",
		LATE_PLANET,
	}) do
		local planet = data.raw.planet[planet_name]
		assert(planet, "the configured planet '" .. planet_name .. "' is missing")
		assert(
			planet.surface_properties and planet.surface_properties[MARKER] == 1,
			"the configured planet '" .. planet_name .. "' was not marked as participating"
		)
	end

	-- Pumpjacks are mining drills with a fluid output and must never be converted.
	assert(
		data.raw["assembling-machine"]["pumpjack-ground-digger"] == nil,
		"a pumpjack ground digger was generated"
	)
	-- Drills restricted to specific resource sites must never be converted either.
	assert(
		data.raw["assembling-machine"]["funit-gd-restricted-drill-ground-digger"] == nil,
		"a ground digger was generated for a resource-site-only drill"
	)

	-- The drill's own surface conditions are inherited by the shared digger.
	local conditioned = data.raw["assembling-machine"]["funit-gd-conditioned-drill-ground-digger"]
	assert(conditioned, "the conditioned drill's shared digger was not generated")
	local inherited_pressure = false
	local marker_condition = false
	for _, condition in ipairs(conditioned.surface_conditions or {}) do
		if condition.property == "pressure" and condition.min == 1e9 and condition.max == 2e9 then
			inherited_pressure = true
		elseif condition.property == MARKER and condition.min == 1 and condition.max == 1 then
			marker_condition = true
		end
	end
	assert(inherited_pressure, "the drill's pressure surface condition was not inherited")
	assert(marker_condition, "the participating-planet surface condition was not added")
end)

-- GD-4b: `drills` restricts generation and `blacklist` removes entries, while a
-- planet without options gets every eligible drill.
record("GD-4b", function()
	local config = get_configs()["funit-gd-planet"]
	assert(config, "the configured planet has no ground-digger configuration")
	assert(config.drills["electric-mining-drill"], "the explicit drill list was not normalised")
	assert(config.drills["burner-mining-drill"], "the explicit drill list was not normalised")
	assert(config.blacklist["burner-mining-drill"], "the blacklist was not normalised")
	assert(
		config.diggers["electric-mining-drill"],
		"the electric mining drill is missing from the resolved diggers"
	)
	assert(
		config.diggers["electric-mining-drill"].drill == "electric-mining-drill",
		"the resolved digger has the wrong drill name"
	)
	assert(
		config.diggers["electric-mining-drill"].digger == "electric-mining-drill-ground-digger",
		"the resolved digger has the wrong shared digger name"
	)
	assert(
		config.diggers["burner-mining-drill"] == nil,
		"a blacklisted drill was resolved into a digger"
	)
	assert(
		config.diggers["funit-gd-conditioned-drill"],
		"an explicitly listed drill is missing from the resolved diggers"
	)
	assert(
		config.diggers["funit-gd-restricted-drill"] == nil,
		"an explicitly listed resource-site-only drill was resolved into a digger"
	)

	-- With an explicit `drills` list, an otherwise eligible drill that is not
	-- listed must not be resolved for this planet.
	if data.raw["mining-drill"]["big-mining-drill"] then
		assert(
			config.diggers["big-mining-drill"] == nil,
			"a drill outside the explicit list was resolved into a digger"
		)
	end

	-- A planet without options uses every eligible drill; the burner drill is
	-- eligible there (only planet A blacklists it).
	local default_config = get_configs()["funit-gd-planet-b"]
	assert(default_config, "the default-options planet has no configuration")
	assert(
		default_config.diggers["burner-mining-drill"],
		"the default drill selection did not include the burner mining drill"
	)
	assert(
		default_config.diggers["electric-mining-drill"],
		"the default drill selection did not include the electric mining drill"
	)
end)

-- GD-4c: a configuration for a planet that does not exist must fail loudly.
record("GD-4c", function()
	local configs = get_configs()
	configs[MISSING_PLANET] = { recipe = "funit-gd-recipe-a" }
	local ok, err = pcall(ground_diggers.generate_ground_diggers)
	configs[MISSING_PLANET] = nil

	assert(not ok, "configuring a nonexistent planet did not raise an error")
	assert(
		tostring(err):find("Planet not found", 1, true),
		"the missing-planet error does not mention 'Planet not found': " .. tostring(err)
	)
	assert(
		tostring(err):find(MISSING_PLANET, 1, true),
		"the missing-planet error does not name the planet: " .. tostring(err)
	)
end)

-- GD-4d: a missing recipe and an unknown drill both fail loudly.
record("GD-4d", function()
	local configs = get_configs()

	local function generate_with_idle_config(config)
		configs[IDLE_PLANET] = config
		local ok, err = pcall(ground_diggers.generate_ground_diggers)
		reset_idle_planet()
		return ok, err
	end

	local ok, err = generate_with_idle_config({ recipe = "funit-gd-missing-recipe" })
	assert(not ok, "configuring a nonexistent recipe did not raise an error")
	assert(
		tostring(err):find("Recipe not found", 1, true),
		"the missing-recipe error does not mention 'Recipe not found': " .. tostring(err)
	)
	assert(
		tostring(err):find("funit-gd-missing-recipe", 1, true),
		"the missing-recipe error does not name the recipe: " .. tostring(err)
	)

	ok, err = generate_with_idle_config({
		recipe = "funit-gd-recipe-a",
		drills = { "funit-gd-missing-drill" },
	})
	assert(not ok, "configuring a nonexistent drill did not raise an error")
	assert(
		tostring(err):find("Mining drill not found", 1, true),
		"the missing-drill error does not mention 'Mining drill not found': " .. tostring(err)
	)
	assert(
		tostring(err):find("funit-gd-missing-drill", 1, true),
		"the missing-drill error does not name the drill: " .. tostring(err)
	)
end)

-- GD-4e: a configuration without a recipe fails loudly.
record("GD-4e", function()
	local configs = get_configs()
	configs[IDLE_PLANET] = {}
	local ok, err = pcall(ground_diggers.generate_ground_diggers)
	reset_idle_planet()

	assert(not ok, "a configuration without a recipe did not raise an error")
	assert(
		tostring(err):find("No recipe assigned", 1, true),
		"the no-recipe error does not mention 'No recipe assigned': " .. tostring(err)
	)
	assert(
		tostring(err):find(IDLE_PLANET, 1, true),
		"the no-recipe error does not name the planet: " .. tostring(err)
	)
end)

-- GD-4f: the Factoriopedia note is added once, even across repeated generation.
record("GD-4f", function()
	local configs = get_configs()
	configs[MISSING_PLANET] = nil
	reset_idle_planet()

	local drill = data.raw["mining-drill"]["electric-mining-drill"]
	assert(drill, "the electric mining drill prototype is missing")
	local description = drill.factoriopedia_description
	assert(description, "the automatic generation did not add a Factoriopedia description")
	assert(
		description[3] and description[3][1] == "factoriopedia-description.PlanetsLib-ground-digger",
		"the Factoriopedia description does not use the shared ground-digger key"
	)
	assert(
		description[3][2] == "electric-mining-drill-ground-digger",
		"the Factoriopedia description does not link to the shared digger"
	)

	ground_diggers.generate_ground_diggers()
	assert(
		drill.factoriopedia_description == description,
		"a repeated generation replaced the existing Factoriopedia description"
	)

	ground_diggers.generate_ground_diggers()
	assert(
		drill.factoriopedia_description == description,
		"a repeated generation replaced the existing Factoriopedia description"
	)
end)

-- GD-5: mining-drill productivity technologies gain one hidden
-- change-recipe-productivity effect per configured recipe, without duplicates.
record("GD-5", function()
	local configs = get_configs()
	configs[MISSING_PLANET] = nil
	reset_idle_planet()

	-- Ensure the late recipe (added by GD-1c) and all other configured recipes
	-- have been processed, regardless of earlier error-path checks.
	ground_diggers.generate_ground_diggers()

	local recipes = {
		"funit-gd-recipe-a",
		"funit-gd-recipe-b",
		"funit-gd-recipe-default",
		"funit-gd-late-recipe",
	}

	local test_tech = data.raw["technology"]["funit-gd-productivity-tech"]
	assert(test_tech, "the test productivity technology is missing")
	for _, recipe_name in ipairs(recipes) do
		assert_recipe_productivity(test_tech, recipe_name, 0.2)
	end

	-- A second generation pass must not duplicate the effects.
	ground_diggers.generate_ground_diggers()
	for _, recipe_name in ipairs(recipes) do
		assert_recipe_productivity(test_tech, recipe_name, 0.2)
	end

	-- Vanilla mining-productivity technologies receive the same treatment.
	local vanilla = data.raw["technology"]["mining-productivity-1"]
	if vanilla then
		for _, recipe_name in ipairs(recipes) do
			assert_recipe_productivity(vanilla, recipe_name, 0.1)
		end
	end
end)

return true
