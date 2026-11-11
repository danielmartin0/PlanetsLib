-- Integration tests for PlanetsLib ground-digger belt stacking with the real
-- Muluna and Maraxsis ground-digger recipes. This is development-only and is
-- not shipped.
--
-- The suite needs FUnit's `planetslib_funit` seam to force a recipe update after
-- changing the force's belt stack bonus.

local MARKER = "PlanetsLib-has-ground-diggers"
local BIG_DIGGER = "big-mining-drill-ground-digger"
local ELECTRIC_DIGGER = "electric-mining-drill-ground-digger"

local function require_mod(runner, name)
	runner.assert(script.active_mods[name], "the integration scenario requires mod '" .. name .. "'")
end

local function get_surface(runner, planet_name)
	local planet = game.planets[planet_name]
	runner.assert(planet, "planet '" .. planet_name .. "' is missing")
	local surface = planet.surface
	if not surface or not surface.valid then
		local ok, created = pcall(function()
			return planet.create_surface()
		end)
		runner.assert(ok, "could not create the surface for '" .. planet_name .. "': " .. tostring(created))
		surface = created
	end
	runner.assert(surface and surface.valid, "the surface for '" .. planet_name .. "' is invalid")
	return surface
end

local function clear_surface(surface)
	surface.clear(true)
	surface.request_to_generate_chunks({ 0, 0 }, 1)
	surface.force_generate_chunk_requests()
	local tiles = {}
	for x = -32, 32 do
		for y = -32, 32 do
			tiles[#tiles + 1] = { name = "landfill", position = { x, y } }
		end
	end
	surface.set_tiles(tiles, true, true, true)
	surface.clear(false)
	surface.clear_hidden_tiles()
end

local function find_product(recipe, name)
	for _, product in ipairs(recipe.products or {}) do
		if product.name == name then
			return product
		end
	end
	return nil
end

local function count_stack_variants()
	local count = 0
	for name in pairs(prototypes.recipe) do
		if name:find("%-PlanetsLib%-stack%-%d+$") then
			count = count + 1
		end
	end
	return count
end

return function(runner)
	runner.test("GDI-1 real recipes get belt-stack variants", function()
		require_mod(runner, "planet-muluna")
		require_mod(runner, "maraxsis")

		local base = prototypes.recipe["muluna-regolith-digging"]
		runner.assert(base, "the Muluna ground-digger recipe is missing")
		for stack = 2, 4 do
			local name = "muluna-regolith-digging-PlanetsLib-stack-" .. stack
			local variant = prototypes.recipe[name]
			runner.assert(variant, "the Muluna stack-" .. stack .. " variant is missing")
			runner.assert(variant.hidden == true, "the Muluna stack-" .. stack .. " variant is not hidden")
			runner.assert(variant.enabled == true, "the Muluna stack-" .. stack .. " variant is not enabled")
			runner.assert(
				variant.energy == 2 * stack,
				"the Muluna stack-" .. stack .. " variant has the wrong energy requirement"
			)
			local regolith = find_product(variant, "muluna-lunar-regolith")
			local crushed = find_product(variant, "stone-crushed")
			runner.assert(regolith, "the Muluna stack-" .. stack .. " variant lost lunar regolith")
			runner.assert(crushed, "the Muluna stack-" .. stack .. " variant lost crushed stone")
			runner.assert(
				regolith.amount == stack,
				"the Muluna stack-" .. stack .. " variant has the wrong regolith amount"
			)
			runner.assert(
				crushed.amount == stack,
				"the Muluna stack-" .. stack .. " variant has the wrong crushed-stone amount"
			)
			runner.assert(
				regolith.shared_probability
					and regolith.shared_probability.min == 0
					and regolith.shared_probability.max == 0.2,
				"the Muluna regolith probability changed"
			)
			runner.assert(
				crushed.shared_probability
					and crushed.shared_probability.min == 0.2
					and crushed.shared_probability.max == 1,
				"the Muluna crushed-stone probability changed"
			)
		end

		local sand = prototypes.recipe["maraxsis-sand-extraction-PlanetsLib-stack-4"]
		runner.assert(sand, "the Maraxsis stack-4 variant is missing")
		runner.assert(sand.energy == 40, "the Maraxsis stack-4 variant has the wrong energy requirement")
		local sand_product = find_product(sand, "sand")
		runner.assert(sand_product, "the Maraxsis stack-4 variant lost sand")
		runner.assert(sand_product.amount == 4, "the Maraxsis stack-4 variant has the wrong sand amount")

		-- Two recipes times three stack sizes. This is the recipe-count budget:
		-- if it grows unexpectedly, Rigor will generate many more variants.
		runner.assert(
			count_stack_variants() == 6,
			"expected exactly six ground-digger stack variants, got " .. count_stack_variants()
		)
		runner.assert(
			prototypes.recipe["muluna-regolith-digging-PlanetsLib-stack-5"] == nil,
			"a variant beyond utility-constants.max_belt_stack_size was generated"
		)
	end)

	runner.test("GDI-2 Muluna and Maraxsis diggers select their stack variants", function()
		require_mod(runner, "planet-muluna")
		require_mod(runner, "maraxsis")

		local force = game.forces.player
		local old_bonus = force.belt_stack_size_bonus
		local created = {}
		local surfaces = {}
		local recipes = {}

		local function cleanup()
			force.belt_stack_size_bonus = old_bonus
			for _, recipe in ipairs(recipes) do
				if recipe.valid then
					pcall(function()
						recipe.enabled = recipe.prototype.enabled
					end)
				end
			end
			for _, entity in ipairs(created) do
				if entity.valid then
					pcall(function()
						entity.destroy()
					end)
				end
			end
			for _, surface in ipairs(surfaces) do
				if surface.valid then
					pcall(function()
						surface.clear(true)
					end)
				end
			end
			pcall(function()
				remote.call("planetslib_funit", "ground_digger_reconcile")
			end)
		end

		local ok, err = xpcall(function()
			runner.assert(prototypes.entity[BIG_DIGGER], "the big mining drill ground digger is missing")
			runner.assert(prototypes.entity[ELECTRIC_DIGGER], "the electric mining drill ground digger is missing")

			for _, case in ipairs({
				{ planet = "muluna", base = "muluna-regolith-digging" },
				{ planet = "maraxsis", base = "maraxsis-sand-extraction" },
			}) do
				local surface = get_surface(runner, case.planet)
				surfaces[#surfaces + 1] = surface
				clear_surface(surface)
				runner.assert(
					surface.get_property(MARKER) == 1,
					"'" .. case.planet .. "' does not have the ground-digger marker"
				)

				local force_recipe = force.recipes[case.base]
				runner.assert(force_recipe, "the force is missing recipe '" .. case.base .. "'")
				recipes[#recipes + 1] = force_recipe
				force_recipe.enabled = true
				force.belt_stack_size_bonus = 0

				local big = surface.create_entity({
					name = BIG_DIGGER,
					position = { 0, 0 },
					force = force,
					raise_built = true,
				})
				local electric = surface.create_entity({
					name = ELECTRIC_DIGGER,
					position = { 20, 0 },
					force = force,
					raise_built = true,
				})
				runner.assert(big, "could not create the batching digger on " .. case.planet)
				runner.assert(electric, "could not create the non-batching digger on " .. case.planet)
				created[#created + 1] = big
				created[#created + 1] = electric

				local function assert_recipe(entity, expected)
					remote.call("planetslib_funit", "ground_digger_update_force", force.name)
					local recipe = entity.get_recipe()
					runner.assert(recipe, "the " .. entity.name .. " has no recipe on " .. case.planet)
					runner.assert(
						recipe.name == expected,
						"expected recipe '" .. expected .. "', got '" .. tostring(recipe.name) .. "'"
					)
				end

				assert_recipe(big, case.base)
				assert_recipe(electric, case.base)
				for bonus = 1, 3 do
					force.belt_stack_size_bonus = bonus
					assert_recipe(big, case.base .. "-PlanetsLib-stack-" .. (bonus + 1))
					assert_recipe(electric, case.base)
				end

				-- Research gating: a locked base recipe must keep the base recipe.
				force.belt_stack_size_bonus = 3
				force_recipe.enabled = false
				assert_recipe(big, case.base)
				force_recipe.enabled = true
				assert_recipe(big, case.base .. "-PlanetsLib-stack-4")
				runner.assert(big.recipe_locked == true, "the batching digger's recipe is not locked")
			end
		end, function(error_value)
			return error_value
		end)

		cleanup()
		if not ok then
			error(err, 0)
		end
	end)
end
