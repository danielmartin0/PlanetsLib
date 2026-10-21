-- Runtime tests for PlanetsLib_recipe_effects.
--
-- The data-stage `recipe_effects_setup` fixture creates the persistent
-- funit-recipefx-* recipes and records the data-preparation probes; this suite
-- asserts both those results and the runtime handler in
-- scripts/recipe-effects.lua.
--
-- The handler lives in PlanetsLib's control stage and its cache lives in
-- PlanetsLib's storage, which this scenario cannot inspect. The suite therefore
-- requires scripts/recipe-effects.lua into this Lua state with a small
-- `PlanetsLib` shim and drives the registered handlers with test doubles for the
-- crafting machine and its production statistics. That keeps the tests
-- deterministic and avoids creating real entities.
--
-- Known limitation: the cache-clearing handler is defined inline in the root
-- control.lua (not in scripts/), so REC-3 can only exercise cache creation and
-- reuse directly. See the runner.log note in REC-3.
local support = require("__planetslib-funit-data__.tests.suites.support")

local SHARED = "funit-recipefx-shared"
local INDEPENDENT = "funit-recipefx-independent"
local BATCH = "funit-recipefx-batch"
local ALWAYS = "funit-recipefx-always"
local ALL_RECIPES = { SHARED, INDEPENDENT, BATCH, ALWAYS }

local QUALITY = "normal"

-- scripts/recipe-effects.lua reads the PlanetsLib global at require time and
-- storage/script/math at call time. Recreate the minimum shim this state needs.
local shim = _G.PlanetsLib or {}
_G.PlanetsLib = shim
shim.constants = shim.constants or {}
local runtime_effects = prototypes.mod_data["Planetslib"]
	and prototypes.mod_data["Planetslib"].data.recipe_effects
shim.constants.recipe_effects = runtime_effects or {}

local require_ok, require_err = pcall(require, "__PlanetsLib__.scripts.recipe-effects")

storage.entity_info = storage.entity_info or {}

local function item_key(name, quality)
	return tostring(name) .. "|" .. tostring(quality)
end

local function make_inventory()
	local inventory = { inserts = {}, counts = {} }
	-- LuaInventory.insert(stack) is called with a dot, so this must not be a
	-- colon method.
	inventory.insert = function(stack)
		inventory.inserts[#inventory.inserts + 1] = stack
		local key = item_key(stack.name, stack.quality)
		inventory.counts[key] = (inventory.counts[key] or 0) + stack.count
		return true
	end
	function inventory:total(name, quality)
		return self.counts[item_key(name, quality)] or 0
	end
	function inventory:reset()
		self.inserts = {}
		self.counts = {}
	end
	return inventory
end

local function make_statistics()
	local samples = {}
	local statistics = {}
	-- LuaFlowStatistics calls are also dotted, not colon methods.
	statistics.get_current_output_sample = function(id)
		return samples[item_key(id.name, id.quality)] or 0
	end
	statistics.set_current_output_sample = function(id, count)
		samples[item_key(id.name, id.quality)] = count
	end
	return statistics
end

local next_unit_number = 900100

local function make_entity()
	next_unit_number = next_unit_number + 1
	local entity = {
		unit_number = next_unit_number,
		surface = { name = "funit-recipefx-surface" },
		inventories = {},
		statistics = make_statistics(),
	}
	entity.inventories[defines.inventory.crafter_input] = make_inventory()
	entity.inventories[defines.inventory.crafter_output] = make_inventory()
	entity.inventories[defines.inventory.crafter_trash] = make_inventory()
	function entity.get_inventory(kind)
		return entity.inventories[kind]
	end
	entity.force = {
		get_item_production_statistics = function()
			return entity.statistics
		end,
	}
	return entity
end

local function input_of(entity)
	return entity.inventories[defines.inventory.crafter_input]
end

local function output_sample(entity, name)
	return entity.statistics.get_current_output_sample({ name = name, quality = QUALITY })
end

local function set_output_sample(entity, name, count)
	entity.statistics.set_current_output_sample({ name = name, quality = QUALITY }, count)
end

local function clear_entity(entity)
	if entity and entity.unit_number then
		storage.entity_info[entity.unit_number] = nil
	end
end

-- Queue the values returned by successive math.random() calls, then restore the
-- real function. Used to make the probability and batch branches deterministic.
local function with_math_random(values, callback)
	local saved = math.random
	local index = 0
	math.random = function()
		index = index + 1
		local value = values[index]
		if value == nil then
			value = 0
		end
		return value
	end
	local ok, err = pcall(callback)
	math.random = saved
	if not ok then
		error(err, 0)
	end
end

local function find_ingredient(recipe, name)
	for _, ingredient in pairs(recipe.ingredients or {}) do
		if ingredient.name == name then
			return ingredient
		end
	end
	return nil
end

local function tooltip_for(recipe, name)
	for _, field in pairs(recipe.custom_tooltip_fields or {}) do
		if type(field.name) == "table" and field.name[1] == name then
			return field
		end
	end
	return nil
end

-- Every id the recipe_effects_setup fixture records. REC-1d is asserted by its
-- own dedicated test below so a failure there does not mask the others.
local RECIPE_EFFECTS_IDS = {
	"REC-1",
	"REC-1a",
	"REC-1b",
	"REC-1c",
	"REC-1e",
	"REC-1f",
}

local function handler_for(runner, recipe_name)
	runner.assert(require_ok, "scripts/recipe-effects.lua failed to load: " .. tostring(require_err))
	local recipe = prototypes.recipe[recipe_name]
	runner.assert(recipe, "recipe prototype '" .. recipe_name .. "' is missing")
	runner.assert(recipe.on_crafted_event ~= nil,
		"recipe '" .. recipe_name .. "' has no on_crafted_event; raise_on_crafted was not set")
	local handler = script.get_event_handler(recipe.on_crafted_event)
	runner.assert(handler ~= nil, "no handler was registered for recipe '" .. recipe_name .. "'")
	return handler
end

local function fire(handler, recipe_name, entity, options)
	options = options or {}
	handler({
		name = recipe_name,
		recipe = recipe_name,
		entity = entity,
		recipe_quality = options.quality or QUALITY,
		product_quality = options.quality or QUALITY,
		bonus = options.bonus or false,
		shared_roll = options.shared_roll or 0,
		tick = options.tick or 0,
	})
end

return function(runner)
	runner.test("REC-1 data preparation and derived prototype fields", function()
		-- REC-1d is asserted separately so a failure there does not mask the
		-- other checks.
		support.assert_all(runner, "recipe_effects_setup", { expected = RECIPE_EFFECTS_IDS })

		runner.assert(require_ok,
			"scripts/recipe-effects.lua failed to load: " .. tostring(require_err))
		runner.assert(runtime_effects, "Planetslib mod-data has no recipe_effects table")

		for _, name in ipairs(ALL_RECIPES) do
			local recipe = prototypes.recipe[name]
			runner.assert(recipe, "recipe prototype '" .. name .. "' is missing")
			runner.assert(runtime_effects[name], "'" .. name .. "' is missing from PlanetsLib.constants.recipe_effects")
			-- raise_on_crafted is a prototype-stage field and is not exposed at
			-- runtime; on_crafted_event is the runtime proof that it was set.
			runner.assert(recipe.on_crafted_event ~= nil,
				"'" .. name .. "' has no on_crafted_event")
		end

		-- shared: derived fields, the ingredient's ignored_by_stats and the tooltip.
		local shared = runtime_effects[SHARED].returned_ingredients[1]
		runner.assert(shared.ignored_by_productivity == 1, "shared ignored_by_productivity was lost")
		runner.assert(shared.add_to_stats == 3,
			"shared add_to_stats should be the ingredient amount - its ignored_by_stats (got " .. tostring(shared.add_to_stats) .. ")")
		runner.assert(shared.amount_minus_ignored_by_productivity == 1,
			"shared amount_minus_ignored_by_productivity is wrong (got "
				.. tostring(shared.amount_minus_ignored_by_productivity) .. ")")

		local shared_ingredient = find_ingredient(prototypes.recipe[SHARED], "iron-ore")
		runner.assert(shared_ingredient, "the shared recipe lost its iron-ore ingredient")
		runner.assert(shared_ingredient.ignored_by_stats == 3,
			"the shared ingredient's ignored_by_stats was not set to its amount (got "
				.. tostring(shared_ingredient.ignored_by_stats) .. ")")

		local shared_tooltip = tooltip_for(prototypes.recipe[SHARED], "tooltip.returned-ingredients")
		runner.assert(shared_tooltip, "the shared recipe has no returned-ingredients tooltip")
		runner.assert(shared_tooltip.value[1] == "tooltip-value.returned-ingredients-probability",
			"the shared tooltip did not use the probability localisation key")
		runner.assert(tostring(shared_tooltip.value[2]) == "50",
			"the shared tooltip probability should be (max-min)*100 (got " .. tostring(shared_tooltip.value[2]) .. ")")
		runner.assert(tostring(shared_tooltip.value[3]) == "2",
			"the shared tooltip amount is wrong (got " .. tostring(shared_tooltip.value[3]) .. ")")

		-- independent: fields and tooltip.
		local independent = runtime_effects[INDEPENDENT].returned_ingredients[1]
		runner.assert(independent.independent_probability == 0.5, "independent probability was lost")
		runner.assert(independent.add_to_stats == 4,
			"independent add_to_stats should be the ingredient amount (got " .. tostring(independent.add_to_stats) .. ")")
		runner.assert(independent.amount_minus_ignored_by_productivity == 1,
			"independent amount_minus_ignored_by_productivity is wrong")
		local independent_ingredient = find_ingredient(prototypes.recipe[INDEPENDENT], "copper-ore")
		runner.assert(independent_ingredient and independent_ingredient.ignored_by_stats == 4,
			"the independent ingredient's ignored_by_stats was not set")

		local independent_tooltip = tooltip_for(prototypes.recipe[INDEPENDENT], "tooltip.returned-ingredients")
		runner.assert(independent_tooltip, "the independent recipe has no returned-ingredients tooltip")
		runner.assert(independent_tooltip.value[1] == "tooltip-value.returned-ingredients-probability",
			"the independent tooltip did not use the probability localisation key")
		runner.log("REC-1 note: scripts/.../recipe-effects.lua formats shared probabilities as percent "
			.. "((max-min)*100) but independent_probability as the raw 0..1 value (tooltip value[2]="
			.. tostring(independent_tooltip.value[2]) .. "). Characterised here, not asserted as a requirement.")

		-- batch: inverse_batch_count.
		local batch = runtime_effects[BATCH].returned_ingredients[1]
		runner.assert(batch.batch_count == 4, "batch_count was lost")
		runner.assert(batch.inverse_batch_count == 0.25,
			"inverse_batch_count should be 1/batch_count (got " .. tostring(batch.inverse_batch_count) .. ")")
		runner.log("REC-1 note: docs-source/docs/usage-documentation/recipe-events.md calls the batching "
			.. "field `batch_size`, while the implementation and this fixture use `batch_count`.")

		-- always: no_probability and its derived fields.
		local always = runtime_effects[ALWAYS].returned_ingredients[1]
		runner.assert(always.no_probability == true, "no_probability was lost")
		runner.assert(always.amount_minus_ignored_by_productivity == 3,
			"always amount_minus_ignored_by_productivity is wrong")
	end)

	runner.test("REC-1d a returned ingredient without a probability (no_probability) can be defined", function()
		-- no_probability is set by the data-prep module for the runtime handler,
		-- and the returned ingredient must not crash the tooltip arithmetic.
		support.assert_entry(runner, "recipe_effects_setup", "REC-1d")
	end)

	runner.test("REC-2a shared_probability hit/miss, bonus and production stats", function()
		local handler = handler_for(runner, SHARED)
		local entity = make_entity()
		local input = input_of(entity)

		local function reset()
			input:reset()
			set_output_sample(entity, "iron-ore", 0)
		end

		local function fire_roll(roll, bonus)
			reset()
			fire(handler, SHARED, entity, { shared_roll = roll, bonus = bonus })
		end

		fire_roll(0.5, false)
		runner.assert(input:total("iron-ore", QUALITY) == 2,
			"a shared hit without bonus should return the full amount (got " .. input:total("iron-ore", QUALITY) .. ")")
		runner.assert(output_sample(entity, "iron-ore") == 0, "a hit must not touch production stats")

		fire_roll(0.5, true)
		runner.assert(input:total("iron-ore", QUALITY) == 1,
			"a shared hit with bonus should return amount - ignored_by_productivity")
		runner.assert(output_sample(entity, "iron-ore") == 0, "a bonus hit must not touch production stats")

		fire_roll(0.2, false)
		runner.assert(input:total("iron-ore", QUALITY) == 0, "a roll below min must miss")
		runner.assert(output_sample(entity, "iron-ore") == 2,
			"a shared miss should add the amount to production stats (got " .. output_sample(entity, "iron-ore") .. ")")

		fire_roll(0.8, true)
		runner.assert(input:total("iron-ore", QUALITY) == 0, "a roll above max must miss")
		runner.assert(output_sample(entity, "iron-ore") == 1,
			"a bonus miss should add amount - ignored_by_productivity to stats")

		fire_roll(0.25, false)
		runner.assert(input:total("iron-ore", QUALITY) == 2, "the shared lower bound must be inclusive")

		fire_roll(0.75, false)
		runner.assert(input:total("iron-ore", QUALITY) == 2, "the shared upper bound must be inclusive")

		clear_entity(entity)
	end)

	runner.test("REC-2b independent_probability hit/miss", function()
		local handler = handler_for(runner, INDEPENDENT)
		local entity = make_entity()
		local input = input_of(entity)

		local function reset()
			input:reset()
			set_output_sample(entity, "copper-ore", 0)
		end

		with_math_random({ 0.4 }, function()
			reset()
			fire(handler, INDEPENDENT, entity, { shared_roll = 0.99 })
		end)
		runner.assert(input:total("copper-ore", QUALITY) == 1,
			"independent_probability below the roll should return the item")
		runner.assert(output_sample(entity, "copper-ore") == 0, "an independent hit must not touch stats")

		with_math_random({ 0.6 }, function()
			reset()
			fire(handler, INDEPENDENT, entity, { shared_roll = 0.99 })
		end)
		runner.assert(input:total("copper-ore", QUALITY) == 0,
			"independent_probability above the roll should miss")
		runner.assert(output_sample(entity, "copper-ore") == 1,
			"an independent miss should add the amount to stats")

		-- The comparison is <=, so an exact match hits.
		with_math_random({ 0.5 }, function()
			reset()
			fire(handler, INDEPENDENT, entity, { shared_roll = 0.99 })
		end)
		runner.assert(input:total("copper-ore", QUALITY) == 1,
			"an independent roll equal to independent_probability should hit")

		clear_entity(entity)
	end)

	runner.test("REC-2c batch_count batches insertions and keeps the stats invariant", function()
		local handler = handler_for(runner, BATCH)
		local entity = make_entity()
		local input = input_of(entity)

		local function reset()
			input:reset()
			set_output_sample(entity, "iron-plate", 0)
		end

		-- A batch roll below inverse_batch_count inserts amount * batch_count.
		with_math_random({ 0.2 }, function()
			reset()
			fire(handler, BATCH, entity, { shared_roll = 0.5 })
		end)
		runner.assert(input:total("iron-plate", QUALITY) == 8,
			"a batch insertion should insert amount * batch_count (got " .. input:total("iron-plate", QUALITY) .. ")")
		runner.assert(#input.inserts == 1, "a batch insertion should be a single insert call")
		runner.assert(input.inserts[1].quality == QUALITY, "the inserted stack should carry the recipe quality")
		runner.assert(output_sample(entity, "iron-plate") == 0, "a batch hit must not touch stats")

		-- A batch roll at/above inverse_batch_count skips the insertion entirely.
		-- Batching keeps the average return rate by inserting larger stacks less
		-- often; a skipped batch intentionally does not touch production stats.
		with_math_random({ 0.3 }, function()
			reset()
			fire(handler, BATCH, entity, { shared_roll = 0.5 })
		end)
		runner.assert(input:total("iron-plate", QUALITY) == 0, "a skipped batch must not insert")
		runner.assert(output_sample(entity, "iron-plate") == 0,
			"a skipped batch must not add to production stats (it is deferred, not missed)")

		-- Over many crafts every insertion is still a whole batch.
		local batch_rolls = {}
		for index = 1, 200 do
			batch_rolls[index] = (index % 4 == 0) and 0.3 or 0.1
		end
		reset()
		with_math_random(batch_rolls, function()
			for _ = 1, 200 do
				fire(handler, BATCH, entity, { shared_roll = 0.5 })
			end
		end)
		runner.assert(input:total("iron-plate", QUALITY) == 150 * 8,
			"150 successful batch rolls should insert 150 batches of 8 (got "
				.. input:total("iron-plate", QUALITY) .. ")")
		runner.assert(#input.inserts == 150, "one insert call should be made per successful batch")
		runner.assert(output_sample(entity, "iron-plate") == 0,
			"batch batching must not send skipped batches to production stats")

		clear_entity(entity)
	end)

	runner.test("REC-2d no_probability always returns regardless of the roll", function()
		local handler = handler_for(runner, ALWAYS)
		local entity = make_entity()
		local input = input_of(entity)

		local function reset()
			input:reset()
			set_output_sample(entity, "copper-plate", 0)
		end

		-- The recipe's shared range is {0.9, 0.95}; both of these rolls miss it,
		-- but no_probability must force the return.
		for _, roll in ipairs({ 0.0, 0.99 }) do
			reset()
			fire(handler, ALWAYS, entity, { shared_roll = roll })
			runner.assert(input:total("copper-plate", QUALITY) == 3,
				"no_probability roll " .. roll .. " should still return the full amount")
			runner.assert(output_sample(entity, "copper-plate") == 0,
				"a no_probability return must not touch stats")
		end

		clear_entity(entity)
	end)

	runner.test("REC-2e on_crafted_event is registered for every recipe with effects", function()
		runner.assert(require_ok,
			"scripts/recipe-effects.lua failed to load: " .. tostring(require_err))
		for _, name in ipairs(ALL_RECIPES) do
			local recipe = prototypes.recipe[name]
			runner.assert(recipe.on_crafted_event ~= nil, "'" .. name .. "' has no on_crafted_event")
			runner.assert(script.get_event_id(recipe.on_crafted_event) ~= nil,
				"'" .. name .. "' has an invalid on_crafted_event")
			runner.assert(script.get_event_handler(recipe.on_crafted_event) ~= nil,
				"no handler is registered for '" .. name .. "'")
		end
	end)

	runner.test("REC-2f inserted + production-stats equals the number of crafts", function()
		-- Shared: five deterministic rolls, three hits of 2 and two misses of 2.
		local handler = handler_for(runner, SHARED)
		local entity = make_entity()
		local input = input_of(entity)
		set_output_sample(entity, "iron-ore", 0)

		local rolls = { 0.5, 0.2, 0.8, 0.25, 0.75 }
		local inserted = 0
		for _, roll in ipairs(rolls) do
			local before = input:total("iron-ore", QUALITY)
			fire(handler, SHARED, entity, { shared_roll = roll })
			inserted = inserted + (input:total("iron-ore", QUALITY) - before)
		end
		runner.assert(inserted + output_sample(entity, "iron-ore") == #rolls * 2,
			"each shared craft should account for 2 items (inserted="
				.. inserted
				.. ", stats="
				.. output_sample(entity, "iron-ore")
				.. ")")
		clear_entity(entity)

		-- Independent: 200 crafts with alternating rolls.
		local independent_handler = handler_for(runner, INDEPENDENT)
		local independent_entity = make_entity()
		local independent_input = input_of(independent_entity)
		set_output_sample(independent_entity, "copper-ore", 0)

		local values = {}
		for index = 1, 200 do
			values[index] = (index % 2 == 0) and 0.6 or 0.4
		end
		local independent_inserted = 0
		with_math_random(values, function()
			for _ = 1, 200 do
				local before = independent_input:total("copper-ore", QUALITY)
				fire(independent_handler, INDEPENDENT, independent_entity, {})
				independent_inserted = independent_inserted
					+ (independent_input:total("copper-ore", QUALITY) - before)
			end
		end)
		local independent_stats = output_sample(independent_entity, "copper-ore")
		runner.assert(independent_inserted + independent_stats == 200,
			"inserted + stats must equal the craft count (inserted="
				.. independent_inserted
				.. ", stats="
				.. independent_stats
				.. ")")
		runner.assert(independent_inserted == 100 and independent_stats == 100,
			"alternating independent rolls should split 100/100 (inserted="
				.. independent_inserted
				.. ", stats="
				.. independent_stats
				.. ")")
		clear_entity(independent_entity)
	end)

	runner.test("REC-3 storage.entity_info cache creation and reuse", function()
		local handler = handler_for(runner, SHARED)
		local entity = make_entity()
		local input = input_of(entity)
		storage.entity_info[entity.unit_number] = nil

		fire(handler, SHARED, entity, { shared_roll = 0.5 })
		local cached = storage.entity_info[entity.unit_number]
		runner.assert(cached, "the recipe-effects cache entry was not created")
		runner.assert(cached.inventories and cached.inventories.crafter_input == input,
			"the cache did not store the crafter input inventory")
		runner.assert(cached.inventories.crafter_output == entity.inventories[defines.inventory.crafter_output],
			"the cache did not store the crafter output inventory")
		runner.assert(cached.inventories.crafter_trash == entity.inventories[defines.inventory.crafter_trash],
			"the cache did not store the crafter trash inventory")
		runner.assert(cached.item_production_statistics == entity.statistics,
			"the cache did not store the production statistics object")

		-- Swap the entity's inventory handle: reuse means the cached (old) handle
		-- keeps receiving items and the replacement stays empty.
		local replacement = make_inventory()
		entity.inventories[defines.inventory.crafter_input] = replacement
		local before = input:total("iron-ore", QUALITY)
		set_output_sample(entity, "iron-ore", 0)
		fire(handler, SHARED, entity, { shared_roll = 0.5 })

		runner.assert(storage.entity_info[entity.unit_number] == cached,
			"the cache entry was recreated instead of reused")
		runner.assert(input:total("iron-ore", QUALITY) > before,
			"the cached crafter input did not receive the returned items")
		runner.assert(replacement:total("iron-ore", QUALITY) == 0,
			"the replacement inventory received items, so the cache was not reused")

		runner.log("REC-3 limitation: the cache-clearing destroy handler is defined inline in "
			.. "PlanetsLib's control.lua (not in scripts/recipe-effects.lua) and cannot be invoked "
			.. "from this scenario state, so creation and reuse are tested directly while clearing "
			.. "is documented as untestable here.")

		clear_entity(entity)
	end)
end
