--- PlanetsLib ground diggers
--- Allows a planet to convert mining drills placed without nearby resources
--- into "ground digger" machines that craft a recipe over time.
--- Ported from "Muluna, Moon of Nauvis" (which was itself forked from Maraxsis).
-- @module lib.ground-diggers

local util = require("util")
local rro = require("lib.objects")
local lib = require("lib.lib")

local Public = {}

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

---Whether a mining drill can be converted into a ground digger.
-- Diggers are assembling machines, so the drill must be electric, square, placeable,
-- and must not output fluids (pumpjacks are mining drills).
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
	if not (drill.energy_source and drill.energy_source.type == "electric") then
		return false
	end
	if drill.output_fluid_box then
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
	config.diggers = {}
	config.generated = false

	-- If the automatic final-fixes pass has already run, generate the new planet immediately.
	if PlanetsLib.current_stage == "data-final-fixes" then
		Public.generate_ground_diggers()
	end
end

---Builds the ground digger entity for a single drill.
-- @return table The generated assembling-machine prototype (not yet extended).
function Public.create_ground_digger(drill, digger_name, item_name, planet_name, recipe_name, categories, product_name)
	local digger = util.table.deepcopy(drill)
	local original_localised_name = digger.localised_name or { "entity-name." .. drill.name }

	digger.name = digger_name
	digger.type = "assembling-machine"
	digger.crafting_categories = util.table.deepcopy(categories)
	digger.crafting_speed = digger.mining_speed or digger.crafting_speed or 1
	digger.fixed_recipe = recipe_name
	digger.placeable_by = { item = item_name, count = 1 }
	digger.fast_replaceable_group = (drill.fast_replaceable_group or drill.name) .. "-ground-digger"
	digger.next_upgrade = nil
	digger.allowed_effects = { "productivity", "consumption", "speed", "pollution", "quality" }
	digger.localised_name = { "entity-name.PlanetsLib-ground-digger", original_localised_name }
	digger.localised_description = { "entity-description.PlanetsLib-ground-digger" }
	digger.hidden_in_factoriopedia = false

	-- Fields that only make sense on mining drills.
	digger.mining_speed = nil
	digger.resource_categories = nil
	digger.resource_drain_rate_percent = nil
	digger.resource_searching_radius = nil
	digger.vector_to_place_result = nil

	digger.flags = digger.flags or {}
	rro.soft_insert(digger.flags, "not-in-made-in")
	rro.soft_insert(digger.flags, "not-in-bonus-gui")

	-- Overlay the digging result's icon so the digger is visually distinct in upgrade planners.
	local product = product_name and data.raw["item"][product_name]
	if product then
		local icon, icon_size
		if product.icons and product.icons[1] then
			icon = product.icons[1].icon
			icon_size = product.icons[1].icon_size
		elseif product.icon then
			icon = product.icon
			icon_size = product.icon_size
		end
		if icon then
			local overlay = {
				icon = icon,
				icon_size = icon_size,
				scale = 0.25,
				shift = { 10, -10 },
				draw_background = true,
			}
			if digger.icons then
				table.insert(digger.icons, overlay)
			elseif digger.icon then
				digger.icons = {
					{ icon = digger.icon, icon_size = digger.icon_size },
					overlay,
				}
			end
			digger.icon = nil
			digger.icon_size = nil
		end
	end

	if product_name then
		digger.custom_tooltip_fields = digger.custom_tooltip_fields or {}
		rro.soft_insert(digger.custom_tooltip_fields, {
			name = { "tooltip.PlanetsLib-ground-digger-result", "[planet=" .. planet_name .. "]" },
			value = "[item=" .. product_name .. "]",
		})
	end

	if not data.raw["planet"][planet_name].surface_properties then
		data.raw["planet"][planet_name].surface_properties = {}
	end
	PlanetsLib.restrict_to_planet(digger, planet_name)

	return digger
end

---Generates the ground digger variants configured for a single planet.
function Public.generate_for_planet(planet_name)
	local config = PlanetsLib.constants.ground_diggers[planet_name]
	if not config or config.generated then
		return
	end

	local planet = data.raw["planet"][planet_name]
	assert(
		planet,
		"PlanetsLib.enable_ground_diggers() - Planet not found: "
			.. tostring(planet_name)
			.. ". See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
	)

	local recipe_name = config.recipe
	assert(
		recipe_name,
		"PlanetsLib.enable_ground_diggers() - No recipe assigned to planet '" .. planet_name .. "'."
	)
	local recipe = data.raw["recipe"][recipe_name]
	assert(
		recipe,
		"PlanetsLib.enable_ground_diggers() - Recipe not found: "
			.. recipe_name
			.. ". See the PlanetsLib documentation at https://mods.factorio.com/mod/PlanetsLib."
	)
	local categories = recipe.categories and util.table.deepcopy(recipe.categories) or { "crafting" }

	local product_name = recipe.main_product
	if not product_name and recipe.results then
		for _, result in pairs(recipe.results) do
			if result.type == "item" or result.type == nil then
				product_name = result.name
				break
			end
		end
	end

	local item_lookup = {}
	for item_name, item in pairs(data.raw["item"] or {}) do
		if item.place_result then
			item_lookup[item.place_result] = item_name
		end
	end

	local drill_names = {}
	if config.drills then
		for drill_name in pairs(config.drills) do
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
		for drill_name in pairs(config.blacklist) do
			drill_names[drill_name] = nil
		end
	end

	config.diggers = config.diggers or {}

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
			local digger_name = drill_name .. "-ground-digger-" .. planet_name
			config.diggers[item_name] = { drill = drill_name, digger = digger_name }
			if not data.raw["assembling-machine"][digger_name] then
				data:extend({
					Public.create_ground_digger(
						drill,
						digger_name,
						item_name,
						planet_name,
						recipe_name,
						categories,
						product_name
					),
				})
			end
			lib.detailed_log(
				"[PlanetsLib] Generated ground digger "
					.. digger_name
					.. " for "
					.. drill_name
					.. " on "
					.. planet_name
			)
		end
	end

	config.generated = true
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

---Generates all ground digger variants configured by mods.
---Called automatically during data-final-fixes. May also be called by a mod during
---data-final-fixes after defining a recipe late.
function Public.generate_ground_diggers()
	local recipes = {}
	for planet_name in pairs(PlanetsLib.constants.ground_diggers) do
		Public.generate_for_planet(planet_name)
		local config = PlanetsLib.constants.ground_diggers[planet_name]
		if config.recipe then
			recipes[config.recipe] = true
		end
	end
	apply_mining_productivity(recipes)
end

return Public
