--- PlanetsLib ground diggers
--- Allows a planet to convert mining drills placed without nearby resources
--- into "ground digger" machines that craft a recipe over time.
--- Ported from "Muluna, Moon of Nauvis" (which was itself forked from Maraxsis).
---
--- All planets share a single ground digger prototype per mining drill, using the
--- naming scheme "<drill>-ground-digger". This matches the prototypes used by Muluna,
--- so saves that placed those entities keep working. The recipe is assigned at runtime,
--- since a shared prototype cannot hard-code a per-planet recipe.
-- @module lib.ground-diggers

local util = require("util")
local rro = require("lib.objects")
local lib = require("lib.lib")

local Public = {}

-- Hidden surface property marking every planet that enabled ground diggers. Each shared
-- digger prototype gets a surface condition on it, so diggers can only exist on
-- participating planets even though the prototypes themselves are shared.
local SURFACE_PROPERTY_NAME = "PlanetsLib-has-ground-diggers"

--== Helpers ==--

---Normalizes a list/array of names into a dictionary keyed by name.
-- Accepts both {"a","b"} and {a = true, b = true} forms.
-- @param list table
-- @return table|nil
local function normalize_name_set(list)
	if not list then
		return nil
	end
	local normalized = {}
	for key, value in pairs(list) do
		if type(key) == "number" then
			if value then
				normalized[value] = true
			end
		elseif value then
			normalized[key] = true
		end
	end
	return normalized
end

local function is_square(entity)
	if not entity.selection_box then
		return false
	end
	local width = entity.selection_box[2][1] - entity.selection_box[1][1]
	local height = entity.selection_box[2][2] - entity.selection_box[1][2]
	return math.ceil(width) == math.ceil(height)
end

-- Some mods create per-quality or per-resource copies of a drill with the quality/resource
-- name baked into the entity name. Those are variants of a drill, not distinct machines.
local function contains_quality_or_resource_name(name)
	for quality_name in pairs(data.raw["quality"] or {}) do
		if string.find(name, quality_name, 1, true) then
			return true
		end
	end
	for resource_name in pairs(data.raw["resource"] or {}) do
		if string.find(name, resource_name, 1, true) then
			return true
		end
	end
	return false
end

-- Drills that cannot mine ordinary solid resources can only be placed on specific
-- resource sites (pumpjacks on oil, anomaly collectors on warp anomalies, ...).
-- Turning those into ground diggers would let players place them anywhere.
local function can_mine_solid_resources(drill)
	if not drill.resource_categories then
		return true
	end
	for _, category in pairs(drill.resource_categories) do
		if category == "basic-solid" then
			return true
		end
	end
	return false
end

---Whether a mining drill can be converted into a ground digger.
-- Diggers are assembling machines, so the drill must be square and placeable, must
-- not output fluids (pumpjacks are mining drills), and must be able to mine ordinary
-- solid resources rather than only specific resource sites. Any energy source is
-- allowed, so non-electric drills are eligible too.
-- @param drill table
-- @param item_lookup table Dictionary of entity name -> placing item name.
-- @return boolean
function Public.is_eligible_drill(drill, item_lookup)
	if not drill then
		return false
	end
	if drill.PlanetsLib_do_not_generate_variants then
		return false
	end
	if drill.output_fluid_box then
		return false
	end
	if not can_mine_solid_resources(drill) then
		return false
	end
	if not is_square(drill) then
		return false
	end
	if not item_lookup[drill.name] then
		return false
	end
	if contains_quality_or_resource_name(drill.name) then
		return false
	end
	return true
end

---The shared ground digger prototype name for a mining drill.
-- Deliberately matches Muluna's naming scheme for backwards compatibility.
-- @param drill_name string
-- @return string
function Public.ground_digger_name(drill_name)
	return drill_name .. "-ground-digger"
end

-- Factorio treats a missing condition bound as the lowest/highest double, so a
-- condition with no bounds (or only the full double range) does not restrict the
-- entity at all.
local LOWEST_DOUBLE = -1.7976931348623157e308
local HIGHEST_DOUBLE = 1.7976931348623157e308

---Whether a surface condition allows every surface.
-- Such conditions are redundant on a generated digger and are not inherited, so the
-- digger only lists the participating-planet condition.
-- @param condition table
-- @return boolean
local function condition_allows_all_surfaces(condition)
	if type(condition) ~= "table" then
		return false
	end
	local min = condition.min
	local max = condition.max
	if min == nil and max == nil then
		return true
	end
	return (min == nil or min <= LOWEST_DOUBLE) and (max == nil or max >= HIGHEST_DOUBLE)
end

---Whether every planet has a ground-digger configuration.
-- When every planet participates, the hidden participating-planet condition no longer
-- restricts the digger and only produces an empty-looking surface conditions tooltip,
-- so it is omitted.
-- @return boolean
local function all_planets_have_ground_diggers()
	local has_planet = false
	for planet_name in pairs(data.raw["planet"] or {}) do
		has_planet = true
		local config = PlanetsLib.constants.ground_diggers[planet_name]
		if not (config and config.recipe) then
			return false
		end
	end
	return has_planet
end

---Builds the surface conditions for a generated ground digger.
-- Inherited conditions that allow every surface are deleted. The participating-planet
-- condition is also omitted when every planet participates, because then it restricts
-- nothing. Returns nil when no conditions remain so the prototype has no empty table.
-- @param drill table The mining drill prototype.
-- @param include_participating_condition boolean
-- @return table|nil
local function get_ground_digger_surface_conditions(drill, include_participating_condition)
	local conditions = {}
	for _, condition in ipairs(drill.surface_conditions or {}) do
		if not condition_allows_all_surfaces(condition) then
			conditions[#conditions + 1] = util.table.deepcopy(condition)
		end
	end
	if include_participating_condition then
		conditions[#conditions + 1] = {
			property = SURFACE_PROPERTY_NAME,
			min = 1,
			max = 1,
		}
	end
	if #conditions == 0 then
		return nil
	end
	return conditions
end

---Creates the hidden shared surface property used to restrict diggers to participating planets.
local function ensure_ground_digger_surface_property()
	if data.raw["surface-property"][SURFACE_PROPERTY_NAME] then
		return
	end
	data:extend({
		{
			name = SURFACE_PROPERTY_NAME,
			type = "surface-property",
			hidden = true,
			hidden_in_factoriopedia = true,
			default_value = 0,
			order = "zzz",
			localised_name = { "surface-property-name.planet-str" },
			localised_unit_key = "surface-property-name.planet-str",
		},
	})
end

--== Public API ==--

--- PlanetsLib.enable_ground_diggers(planet, recipe, options)
--- Enables ground diggers on a planet. Whenever a supported mining drill is placed on the
--- planet where no resources are nearby, it is converted into a ground digger that crafts
--- `recipe`. Each planet may have a single ground digger recipe.
--- @param planet string|table Planet name or planet prototype.
--- @param recipe string Name of the recipe the ground diggers will craft.
--- @param options table|nil Optional fields:
---   `drills` (table): Only generate diggers for these mining drill entity names.
---   `blacklist` (table): Never generate diggers for these mining drill entity names.
function Public.enable_ground_diggers(planet, recipe, options)
	local planet_name = type(planet) == "table" and planet.name or planet
	if type(planet_name) ~= "string" then
		error(
			"PlanetsLib.enable_ground_diggers(planet,recipe,options) - 'planet' must be a planet name or prototype. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	if type(recipe) ~= "string" then
		error(
			"PlanetsLib.enable_ground_diggers(planet,recipe,options) - 'recipe' must be a recipe name. See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
	end
	options = options or {}

	local config = PlanetsLib.constants.ground_diggers[planet_name]
	if not config then
		config = {}
		PlanetsLib.constants.ground_diggers[planet_name] = config
	end
	config.recipe = recipe
	config.drills = normalize_name_set(options.drills)
	config.blacklist = normalize_name_set(options.blacklist)
	config.diggers = nil

	-- If the automatic final-fixes pass has already run, generate the new planet immediately.
	if PlanetsLib.current_stage == "data-final-fixes" then
		Public.generate_ground_diggers()
	end
end

---Builds the shared ground digger entity for a single drill.
-- @param drill table The mining drill prototype to copy.
-- @param digger_name string Name of the generated prototype.
-- @param item_name string The item that places the drill (and so the digger).
-- @param categories table The crafting categories the digger accepts.
-- @return table The generated assembling-machine prototype (not yet extended).
function Public.create_ground_digger(drill, digger_name, item_name, categories)
	local digger = util.table.deepcopy(drill)
	local original_localised_name = digger.localised_name or { "entity-name." .. drill.name }

	digger.name = digger_name
	digger.type = "assembling-machine"
	digger.crafting_categories = util.table.deepcopy(categories)
	digger.crafting_speed = digger.mining_speed or digger.crafting_speed or 1
	digger.placeable_by = { item = item_name, count = 1 }
	digger.fast_replaceable_group = (drill.fast_replaceable_group or drill.name) .. "-ground-digger"
	digger.next_upgrade = nil
	digger.allowed_effects = { "productivity", "consumption", "speed", "pollution", "quality" }
	digger.localised_name = { "entity-name.PlanetsLib-ground-digger", original_localised_name }
	digger.localised_description = { "entity-description.PlanetsLib-ground-digger" }
	digger.hidden_in_factoriopedia = false

	-- Keep the drill's own restrictive surface conditions, then additionally restrict
	-- the digger to planets that enabled ground diggers. Conditions that allow every
	-- surface are redundant, so they are deleted instead of copied. The participating
	-- condition is also omitted when every planet participates.
	digger.surface_conditions = get_ground_digger_surface_conditions(drill, not all_planets_have_ground_diggers())

	-- Fields that only make sense on mining drills.
	digger.mining_speed = nil
	digger.resource_categories = nil
	digger.resource_drain_rate_percent = nil
	digger.resource_searching_radius = nil

	-- Replicates the default drain of mining drills. Assembling machines automatically apply some drain to machines with undefined drain levels.
	if digger.energy_source.type == "electric" and not digger.energy_source.drain then
		digger.energy_source.drain = "0MW"
	end
	digger.flags = digger.flags or {}
	rro.soft_insert(digger.flags, "not-in-made-in")
	rro.soft_insert(digger.flags, "not-in-bonus-gui")

	return digger
end

-- Resolves which drills a planet can convert, populating config.diggers as a map of
-- placing item name -> {drill = entity name, digger = shared digger entity name}.
local function resolve_planet_diggers(planet_name, item_lookup)
	local config = PlanetsLib.constants.ground_diggers[planet_name]
	if not config then
		return
	end

	local drill_names = {}
	if config.drills then
		-- Accept both array/list and dictionary forms, including configs injected
		-- directly into PlanetsLib.constants.ground_diggers.
		for drill_name in pairs(normalize_name_set(config.drills) or {}) do
			drill_names[drill_name] = true
		end
	else
		for drill_name, drill in pairs(data.raw["mining-drill"] or {}) do
			if Public.is_eligible_drill(drill, item_lookup) then
				drill_names[drill_name] = true
			end
		end
	end
	if config.blacklist then
		for drill_name in pairs(normalize_name_set(config.blacklist) or {}) do
			drill_names[drill_name] = nil
		end
	end

	config.diggers = {}
	for drill_name in pairs(drill_names) do
		local drill = data.raw["mining-drill"][drill_name]
		if not drill then
			error(
				"PlanetsLib.enable_ground_diggers() - Mining drill not found: "
					.. drill_name
					.. " (configured for planet "
					.. planet_name
					.. ")."
			)
		end
		if Public.is_eligible_drill(drill, item_lookup) then
			local item_name = item_lookup[drill_name]
			config.diggers[item_name] = {
				drill = drill_name,
				digger = Public.ground_digger_name(drill_name),
				full_belt_stacks = drill.drops_full_belt_stacks == true,
			}
		end
	end
end

---Applies mining drill productivity technologies to the given ground digger recipes,
-- so that ground diggers benefit from mining productivity research.
local function apply_mining_productivity(recipes)
	for _, technology in pairs(data.raw["technology"] or {}) do
		if technology.effects then
			for _, effect in pairs(technology.effects) do
				if effect.type == "mining-drill-productivity-bonus" and effect.modifier then
					for recipe_name in pairs(recipes) do
						rro.soft_insert(technology.effects, {
							type = "change-recipe-productivity",
							recipe = recipe_name,
							change = effect.modifier,
							hidden = true,
						})
					end
				end
			end
		end
	end
end

-- Tracks drills that already received the Factoriopedia note, so repeated
-- generate_ground_diggers() calls do not duplicate it.
local described_drills = {}

---Adds a Factoriopedia note to a mining drill pointing at its ground digger variant.
local function add_factoriopedia_description(drill, digger_name)
	if described_drills[drill.name] then
		return
	end
	described_drills[drill.name] = true
	local description = drill.factoriopedia_description or { "entity-description." .. drill.name }
	drill.factoriopedia_description = {
		"",
		{"?",{"",description,"\n"},""},
		{ "factoriopedia-description.PlanetsLib-ground-digger", digger_name },
	}
end

--== Belt-stack recipe variants ==--

local function get_utility_max_belt_stack_size()
	local constants = data.raw["utility-constants"] and data.raw["utility-constants"]["default"]
	return (constants and constants.max_belt_stack_size) or 1
end

local function infer_entry_type(entry)
	if entry.type == "item" or entry.type == "fluid" then
		return entry.type
	end
	if entry.name then
		if data.raw.item and data.raw.item[entry.name] then
			return "item"
		end
		if data.raw.fluid and data.raw.fluid[entry.name] then
			return "fluid"
		end
	end
	return nil
end

---Normalizes a recipe ingredient or product entry into a full prototype table.
-- Supports full tables, entries without a type, and the legacy {name, amount} form.
local function normalize_entry(entry, fallback_type)
	if type(entry) == "string" then
		return { type = fallback_type or "item", name = entry, amount = 1 }
	end
	if type(entry) ~= "table" then
		return nil
	end
	if type(entry[1]) == "string" and type(entry[2]) == "number" then
		return {
			type = infer_entry_type(entry)
				or (data.raw.item and data.raw.item[entry[1]] and "item")
				or (data.raw.fluid and data.raw.fluid[entry[1]] and "fluid")
				or fallback_type
				or "item",
			name = entry[1],
			amount = entry[2],
		}
	end
	if type(entry.name) ~= "string" then
		return nil
	end
	local entry_type = infer_entry_type(entry) or fallback_type
	if not entry_type then
		return nil
	end
	local normalized = util.table.deepcopy(entry)
	normalized.type = entry_type
	return normalized
end

---Normalizes an ingredient/product list (array or dictionary form) into an array.
local function normalize_entries(list, fallback_type)
	if type(list) ~= "table" then
		return nil
	end
	local normalized = {}
	if list[1] ~= nil then
		-- Preserve the original result/ingredient order for array forms.
		for _, value in ipairs(list) do
			local entry = normalize_entry(value, fallback_type)
			if not entry then
				return nil
			end
			normalized[#normalized + 1] = entry
		end
	else
		for key, value in pairs(list) do
			local entry
			if type(key) == "number" then
				entry = normalize_entry(value, fallback_type)
			elseif type(key) == "string" then
				entry = normalize_entry({ name = key, amount = value }, fallback_type)
			end
			if not entry then
				return nil
			end
			normalized[#normalized + 1] = entry
		end
	end
	return normalized
end

local function scale_number(value, multiplier)
	if type(value) ~= "number" then
		return value
	end
	return value * multiplier
end

local function item_amount_too_large(entry, multiplier)
	if entry.type ~= "item" then
		return false
	end
	for _, amount in pairs({ entry.amount, entry.amount_min, entry.amount_max }) do
		if type(amount) == "number" and amount * multiplier > 65535 then
			return true
		end
	end
	return false
end

local function entries_have_valid_item_amounts(entries)
	for _, entry in pairs(entries) do
		if entry.type == "item" then
			for _, amount in pairs({ entry.amount, entry.amount_min, entry.amount_max }) do
				if type(amount) == "number" and amount > 65535 then
					return false
				end
			end
		end
	end
	return true
end

---Scales every amount on an ingredient/product list by an integer multiplier.
-- Probabilities and custom fields (including Rigor fields) are left untouched.
local function scale_entries(entries, multiplier, fallback_type)
	local normalized = normalize_entries(entries, fallback_type)
	if not normalized then
		return nil
	end
	for _, entry in pairs(normalized) do
		if item_amount_too_large(entry, multiplier) then
			return nil
		end
		if entry.amount ~= nil then
			entry.amount = scale_number(entry.amount, multiplier)
		end
		if entry.amount_min ~= nil then
			entry.amount_min = scale_number(entry.amount_min, multiplier)
		end
		if entry.amount_max ~= nil then
			entry.amount_max = scale_number(entry.amount_max, multiplier)
		end
		if entry.ignored_by_stats ~= nil then
			entry.ignored_by_stats = scale_number(entry.ignored_by_stats, multiplier)
		end
		if entry.ignored_by_productivity ~= nil then
			entry.ignored_by_productivity = scale_number(entry.ignored_by_productivity, multiplier)
		end
		if entry.extra_count_fraction ~= nil then
			local extra = entry.extra_count_fraction * multiplier
			local whole = math.floor(extra)
			if whole > 0 then
				if entry.amount ~= nil then
					entry.amount = entry.amount + whole
				elseif entry.amount_min ~= nil and entry.amount_max ~= nil then
					entry.amount_min = entry.amount_min + whole
					entry.amount_max = entry.amount_max + whole
				end
			end
			entry.extra_count_fraction = extra - whole
			if entry.extra_count_fraction == 0 then
				entry.extra_count_fraction = nil
			end
		end
	end
	if not entries_have_valid_item_amounts(normalized) then
		return nil
	end
	return normalized
end

---Returns the item product that determines the ground digger's belt stack size.
-- Prefers recipe.main_product, then the first item product.
local function get_main_item_product(recipe)
	local products = normalize_entries(recipe.results, "item")
	if not products then
		return nil
	end
	local main_name = recipe.main_product
	if type(main_name) == "string" and main_name ~= "" then
		for _, product in pairs(products) do
			if product.type == "item" and product.name == main_name then
				return product
			end
		end
	end
	for _, product in pairs(products) do
		if product.type == "item" then
			return product
		end
	end
	return nil
end

local function get_product_amount(product)
	if type(product.amount) == "number" then
		return product.amount
	end
	if type(product.amount_max) == "number" then
		return product.amount_max
	end
	return 0
end

---Creates one batched copy of a ground-digger recipe.
-- @param base table The original recipe prototype.
-- @param name string The variant prototype name.
-- @param multiplier integer The number of base crafts represented by one variant craft.
-- @return table|nil
local function create_recipe_variant(base, name, multiplier)
	local variant = util.table.deepcopy(base)
	variant.name = name
	variant.hidden = true
	variant.enabled = true
	variant.auto_recycle = false
	variant.localised_name = variant.localised_name or { "recipe-name." .. base.name }
	variant.energy_required = (base.energy_required or 0.5) * multiplier
	variant.PlanetsLib_ground_digger_stack_variant = true
	variant.PlanetsLib_ground_digger_base_recipe = base.name
	variant.PlanetsLib_ground_digger_batch = multiplier

	local ingredients = scale_entries(base.ingredients, multiplier, "item")
	if base.ingredients ~= nil and not ingredients then
		return nil
	end
	variant.ingredients = ingredients or {}

	local results = scale_entries(base.results, multiplier, "item")
	if base.results ~= nil and not results then
		return nil
	end
	variant.results = results or {}

	return variant
end

---Removes variants generated by an earlier generate_ground_diggers() call.
-- This keeps late data-final-fixes registrations idempotent.
local function cleanup_generated_variants()
	local previous = PlanetsLib.constants.ground_digger_generated_variants or {}
	for variant_name in pairs(previous) do
		local recipe = data.raw["recipe"][variant_name]
		if recipe and recipe.PlanetsLib_ground_digger_stack_variant then
			data.raw["recipe"][variant_name] = nil
		end
		for _, technology in pairs(data.raw["technology"] or {}) do
			if technology.effects then
				for index = #technology.effects, 1, -1 do
					local effect = technology.effects[index]
					if effect.type == "change-recipe-productivity" and effect.recipe == variant_name then
						table.remove(technology.effects, index)
					end
				end
			end
		end
	end
	PlanetsLib.constants.ground_digger_generated_variants = {}
end

---Generates hidden batched recipe variants up to utility-constants.max_belt_stack_size.
-- Every recipe gets one variant per distinct integer batch multiplier. For a recipe
-- whose main product is crafted one at a time, that is one variant per stack size.
local function generate_recipe_variants(recipes)
	local utility_max = math.max(1, get_utility_max_belt_stack_size())
	local metadata = {}
	local generated = {}

	for base_name in pairs(recipes) do
		local base = data.raw["recipe"][base_name]
		if base then
			local main_product = get_main_item_product(base)
			if main_product then
				local item_prototype = data.raw.item and data.raw.item[main_product.name]
				local item_stack_size = item_prototype and item_prototype.stack_size or 1
				local base_amount = get_product_amount(main_product)
				local variants = { [1] = base_name }
				local variant_by_batch = {}

				if base_amount > 0 and utility_max >= 2 then
					for target = 2, utility_max do
						local batch = math.max(1, math.ceil(target / base_amount))
						local variant_name
						if batch <= 1 then
							variant_name = base_name
						else
							local cached = variant_by_batch[batch]
							if cached == nil then
								local actual_output = batch * base_amount
								local candidate_name = base_name
									.. "-PlanetsLib-stack-"
									.. actual_output
								local existing = data.raw["recipe"][candidate_name]
								if existing and not existing.PlanetsLib_ground_digger_stack_variant then
									log(
										"[PlanetsLib] Cannot generate ground-digger stack recipe '"
											.. candidate_name
											.. "': the name is already used by another recipe."
									)
									variant_by_batch[batch] = false
								else
									local variant = create_recipe_variant(base, candidate_name, batch)
									if variant then
										data.raw["recipe"][candidate_name] = nil
										data:extend({ variant })
										variant_by_batch[batch] = candidate_name
										generated[candidate_name] = true
									else
										log(
											"[PlanetsLib] Cannot batch ground-digger recipe '"
												.. base_name
												.. "' by "
												.. batch
												.. ": ingredient or product amounts exceed the prototype limit."
										)
										variant_by_batch[batch] = false
									end
								end
								cached = variant_by_batch[batch]
							end
							variant_name = cached or nil
						end

						if variant_name then
							variants[target] = variant_name
						else
							for fallback_target = target - 1, 1, -1 do
								if variants[fallback_target] then
									variants[target] = variants[fallback_target]
									break
								end
							end
							variants[target] = variants[target] or base_name
						end
					end
				end

				metadata[base_name] = {
					max_stack = utility_max,
					item_stack_size = item_stack_size,
					main_product = main_product.name,
					variants = variants,
				}
			end
		end
	end

	PlanetsLib.constants.ground_digger_recipe_variants = metadata
	PlanetsLib.constants.ground_digger_generated_variants = generated
	return generated
end

---Generates all ground digger variants configured by mods.
---Called automatically during data-final-fixes. May also be called by a mod during
---data-final-fixes after defining a recipe late.
function Public.generate_ground_diggers()
	local planets = PlanetsLib.constants.ground_diggers

	local item_lookup = {}
	for item_name, item in pairs(data.raw["item"] or {}) do
		if item.place_result then
			item_lookup[item.place_result] = item_name
		end
	end

	-- Pass 1: validate each planet, resolve its eligible drills, and collect recipes.
	local recipes = {}
	for planet_name, config in pairs(planets) do
		local planet = data.raw["planet"][planet_name]
		assert(
			planet,
			"PlanetsLib.enable_ground_diggers() - Planet not found: "
				.. tostring(planet_name)
				.. ". See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)

		-- Mark the planet as participating so the shared digger prototypes can be built here.
		ensure_ground_digger_surface_property()
		planet.surface_properties = planet.surface_properties or {}
		planet.surface_properties[SURFACE_PROPERTY_NAME] = 1

		local recipe_name = config.recipe
		assert(
			recipe_name,
			"PlanetsLib.enable_ground_diggers() - No recipe assigned to planet '" .. planet_name .. "'."
		)
		assert(
			data.raw["recipe"][recipe_name],
			"PlanetsLib.enable_ground_diggers() - Recipe not found: "
				.. recipe_name
				.. ". See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
		)
		recipes[recipe_name] = true

		resolve_planet_diggers(planet_name, item_lookup)
	end

	-- All ground diggers share one prototype per drill, so they must accept every
	-- configured recipe's category. Recipes are assigned per planet at runtime.
	local categories = {}
	for recipe_name in pairs(recipes) do
		local recipe = data.raw["recipe"][recipe_name]
		for _, category in pairs(recipe.categories or { "crafting" }) do
			categories[category] = true
		end
	end
	local categories_list = {}
	for category in pairs(categories) do
		table.insert(categories_list, category)
	end

	-- Pass 2: generate hidden batched recipe variants for belt stacking.
	cleanup_generated_variants()
	local generated_variants = generate_recipe_variants(recipes)

	-- Pass 3: create (or refresh) the shared prototype for each drill.
	local include_participating_condition = not all_planets_have_ground_diggers()
	local processed = {}
	for _, config in pairs(planets) do
		for item_name, info in pairs(config.diggers or {}) do
			if not processed[info.digger] then
				processed[info.digger] = true
				local drill = data.raw["mining-drill"][info.drill]
				local existing = data.raw["assembling-machine"][info.digger]
				if existing then
					existing.crafting_categories = util.table.deepcopy(categories_list)
					-- Refresh only our participating-planet condition; leave any other
					-- conditions a mod may have added to the shared prototype alone.
					if include_participating_condition then
						local has_condition = false
						for _, condition in ipairs(existing.surface_conditions or {}) do
							if condition.property == SURFACE_PROPERTY_NAME then
								has_condition = true
								break
							end
						end
						if not has_condition then
							existing.surface_conditions = existing.surface_conditions or {}
							table.insert(existing.surface_conditions, {
								property = SURFACE_PROPERTY_NAME,
								min = 1,
								max = 1,
							})
						end
					elseif existing.surface_conditions then
						local conditions = {}
						for _, condition in ipairs(existing.surface_conditions) do
							if condition.property ~= SURFACE_PROPERTY_NAME then
								conditions[#conditions + 1] = condition
							end
						end
						existing.surface_conditions = #conditions > 0 and conditions or nil
					end
				else
					data:extend({
						Public.create_ground_digger(drill, info.digger, item_name, categories_list),
					})
				end
				add_factoriopedia_description(drill, info.digger)
				lib.detailed_log(
					"[PlanetsLib] Generated ground digger " .. info.digger .. " for " .. info.drill
				)
			end
		end
	end

	local productivity_recipes = {}
	for recipe_name in pairs(recipes) do
		productivity_recipes[recipe_name] = true
	end
	for variant_name in pairs(generated_variants) do
		productivity_recipes[variant_name] = true
	end
	apply_mining_productivity(productivity_recipes)
end

return Public
