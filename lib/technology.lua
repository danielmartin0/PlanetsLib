--- Technology-related functions.
--- Dependencies: util, lib.lib, lib.remove-replace-object
-- @module lib.technology.lua


local util = require("util")
local lib = require("lib.lib")
local rro = require("lib.objects")

local Public = {}

---Technology name goes in. Out comes an array of technology names that currently list that tech as a prerequisite. Throws an error if an invalid prototype name is passed.
---@param tech_name string
---@return string[] children
function Public.get_child_technologies(tech_name)
	assert(data.raw.technology[tech_name], "Invalid technology name: " .. tech_name)
	local children = {}
	for _, tech in pairs(data.raw.technology) do
		if tech.prerequisites then
			for _, prereq in ipairs(tech.prerequisites) do
				if prereq == tech_name then
					table.insert(children, tech.name)
					break
				end
			end
		end
	end
	return children
end

function Public.excise_tech_from_tech_tree(tech_name)
	log("PlanetsLib: Excising technology " .. tech_name .. " from tech tree")

	local tech = data.raw.technology[tech_name]
	if not tech then
		return
	end

	for _, other_tech in pairs(data.raw.technology) do
		if other_tech.prerequisites then
			local affected = false
			for i = #other_tech.prerequisites, 1, -1 do
				if other_tech.prerequisites[i] == tech_name then
					affected = true
					table.remove(other_tech.prerequisites, i)
				end
			end

			if affected then
				for _, prereq in pairs(tech.prerequisites or {}) do
					local already_present = false
					for _, existing in pairs(other_tech.prerequisites) do
						if existing == prereq then
							already_present = true
							break
						end
					end
					if not already_present then
						table.insert(other_tech.prerequisites, prereq)
					end
				end
			end
		end
	end

	data.raw.technology[tech_name].hidden = true
end

function Public.excise_recipe_from_tech_tree(name)
	log("PlanetsLib: Excising recipe " .. name .. " from tech tree")

	for _, tech in pairs(data.raw.technology) do
		if tech.effects and #tech.effects > 0 then
			local new_effects = {}
			for _, effect in ipairs(tech.effects) do
				if not (effect.type == "unlock-recipe" and effect.recipe == name) then
					table.insert(new_effects, effect)
				end
			end
			tech.effects = new_effects

			if #new_effects == 0 then
				Public.excise_tech_from_tech_tree(tech.name)
			end
		end
	end
end

function Public.excise_effect_from_tech_tree(effect)
	log("PlanetsLib: Excising effect " .. serpent.block(effect) .. " from tech tree")

	for _, tech in pairs(data.raw.technology) do
		if tech.effects and #tech.effects > 0 then
			local new_effects = {}
			for _, current_effect in ipairs(tech.effects) do
				local should_keep = true

				local effect_count, current_count = 0, 0
				for _ in pairs(effect) do
					effect_count = effect_count + 1
				end
				for _ in pairs(current_effect) do
					current_count = current_count + 1
				end

				if effect_count == current_count then
					should_keep = false
					for k, v in pairs(effect) do
						if not (current_effect[k] and current_effect[k] == v) then
							should_keep = true
							break
						end
					end
				else
					should_keep = true
				end

				if should_keep then
					table.insert(new_effects, current_effect)
				end
			end
			tech.effects = new_effects

			if #new_effects == 0 then
				Public.excise_tech_from_tech_tree(tech.name)
			end
		end
	end
end

function Public.cargo_drops_technology_base(planet, planet_technology_icon, planet_technology_icon_size)
	if not planet then
		error("PlanetsLib:cargo_drops_technology() - planet is required")
	end
	if not planet_technology_icon then
		error("PlanetsLib:cargo_drops_technology() - planet_technology_icon is required")
	end
	if not planet_technology_icon_size then
		error("PlanetsLib:cargo_drops_technology() - planet_technology_icon_size is required")
	end

	return {
		type = "technology",
		name = "planetslib-" .. planet .. "-cargo-drops",
		localised_name = { "", { "technology-name.cargo-drops", { "space-location-name." .. planet } } },
		localised_description = { "technology-description.cargo-drops", { "space-location-name." .. planet } },
		-- TODO: Switch to the iconized planet and show a constant symbol in front?
		effects = Public.technology_effect_cargo_drops(planet, {
			{
				icon = planet_technology_icon,
				icon_size = planet_technology_icon_size,
				scale = 0.65 * (256 / planet_technology_icon_size),
				draw_background = true,
			},
		}),
		icons = Public.technology_icons_planet_cargo_drops(planet_technology_icon, planet_technology_icon_size),
	}
end

function Public.technology_icons_planet_cargo_drops(planet_icon, icon_size, mini)
	icon_size = icon_size or 256
	return {
		{
			icon = "__PlanetsLib__/graphics/icons/cargo-drop-tech-pod.png",
			icon_size = 256,
			scale = 1,
			shift = { 0, 0 },
			draw_background = true,
		},
		{
			icon = planet_icon,
			icon_size = icon_size,
			scale = 0.65 * (256 / icon_size),
			shift = mini and { 0, 0 } or { -17, 55 },
			draw_background = true,
		},
		{
			icon = "__PlanetsLib__/graphics/icons/cargo-drop-tech-shadow.png",
			icon_size = 256,
			scale = 1,
			shift = { 0, 0 },
			tint = { r = 0, g = 0, b = 0, a = 0.5 },
			draw_background = true,
		},
		{
			icon = "__PlanetsLib__/graphics/icons/cargo-drop-tech-pod.png",
			icon_size = 256,
			scale = 1,
			shift = { 0, 0 },
			draw_background = true,
		},
	}
end

function Public.technology_effect_cargo_drops(planet_name, icons)
	return {
		{
			type = "nothing",
			icons = icons,
			effect_description = { "planetslib.cargo-drops-tech-description", "[space-location=" .. planet_name .. "]" },
		},
	}
end

---Create a moon discovery technology icon by adding a little moon icon on your technology icon, like in vanilla, but for moon type planets.
---@param tech_icon string The technology icon to add the moon icon
---@param icon_size integer Your icon size
---@return data.IconData[]
function Public.technology_icon_moon(tech_icon, icon_size)
	icon_size = icon_size or 256
	local icons = util.technology_icon_constant_planet(tech_icon)
	icons[1].icon_size = icon_size
	icons[2].icon = "__PlanetsLib__/graphics/icons/moon-technology-symbol.png"
	-- End result is an icons object ressembling the following, as of 2.0.37. Future API changes might change this code,
	-- which is why this function is written to reference the base function instead of copying it by hand.
	-- local icons = {
	-- 	{
	-- 		icon = moon_icon,
	-- 		icon_size = icon_size,
	-- 	},
	-- 	{
	-- 		icon = "__PlanetsLib__/graphics/icons/moon-technology-symbol.png",
	-- 		icon_size = 128,
	-- 		scale = 0.5,
	-- 		shift = { 50, 50 },
	-- 		floating = true
	-- 	},
	-- }
	return icons
end

---Create a planet discovery technology icon by adding a little planet icon on your technology icon, like in vanilla.
---@param tech_icon string The technology icon to add the planet icon
---@param icon_size integer Your icon size
---@return data.IconData[]
function Public.technology_icon_planet(tech_icon, icon_size)
	icon_size = icon_size or 256
	local icons = util.technology_icon_constant_planet(tech_icon)
	icons[1].icon_size = icon_size
	-- End result is an icons object ressembling the following, as of 2.0.37. Future API changes might change this code,
	-- which is why this function is written to reference the base function instead of copying it by hand.
	-- local icons = {
	-- 	{
	-- 		icon = planet_icon,
	-- 		icon_size = icon_size,
	-- 	},
	-- 	{
	-- 		icon = "__core__/graphics/icons/technology/constants/constant-planet.png",
	-- 		icon_size = 128,
	-- 		scale = 0.5,
	-- 		shift = { 50, 50 },
	-- 		floating = true
	-- 	},
	-- }
	return icons
end

-- TODO: Apply use_icon_overlay_constant to the unlock if the planet is a moon

-- This function makes the technology use all sciences in the base lab.
-- Compatibility for technologies after prometheum science.
function Public.set_science_packs_from_lab(technology, lab)
	assert(technology, "PlanetsLib:add_science_packs_from_vanilla_lab_to_technology() - technology is required")
	assert(
		technology.unit,
		"PlanetsLib:add_science_packs_from_vanilla_lab_to_technology() - technology.unit is required"
	)
	assert(
		technology.unit.ingredients,
		"PlanetsLib:add_science_packs_from_vanilla_lab_to_technology() - technology.unit.ingredients is required"
	)
	assert(lab, "PlanetsLib:add_science_packs_from_vanilla_lab_to_technology() - lab is required")
	assert(lab.inputs, "PlanetsLib:add_science_packs_from_vanilla_lab_to_technology() - lab.inputs is required")

	technology.unit.ingredients = technology.unit.ingredients or {}

	local inputs = lab.inputs
	local existing_packs = {}

	for _, pack in pairs(technology.unit.ingredients) do
		existing_packs[pack[1]] = true
	end

	for _, value in pairs(inputs) do
		if not existing_packs[value] then
			local to_insert = true
			for _, effect in pairs(technology.effects) do --Check if this technology unlocks a science pack. If yes, don't make this technology require that pack.
				if effect.type == "unlock-recipe" and effect.recipe == value then
					to_insert = false
					break
				end
			end

			if to_insert then
				table.insert(technology.unit.ingredients, { value, 1 })
				existing_packs[value] = true
			end
		end
	end
end

function Public.add_science_packs_from_vanilla_lab_to_technology(technology)
	assert(
		data.raw["lab"]["lab"],
		"PlanetsLib:add_science_packs_from_vanilla_lab_to_technology() - data.raw['lab']['lab'] is required"
	)
	Public.set_science_packs_from_lab(technology, data.raw["lab"]["lab"])
end

function Public.sort_science_pack_names(science_pack_names_table)
	science_pack_names_table = util.table.deepcopy(science_pack_names_table)

	lib.sort(science_pack_names_table, function(left, right)
		if not (data.raw["tool"] and data.raw["tool"][left] and data.raw["tool"][right]) then
			return true
		end

		local left_order = data.raw["tool"][left].order
		local right_order = data.raw["tool"][right].order

		if left_order == nil then
			left_order = data.raw["tool"][left].name
		end
		if right_order == nil then
			right_order = data.raw["tool"][right].name
		end

		return left_order < right_order
	end)
	return science_pack_names_table
end


--New technologyPrototype field: PlanetsLib_recipe_productivity_effects
--Properties:
--  effects: array[ChangeResultProductivityModifier]
--  purge_other_effects: boolean. Default: false. Before adding effects added by PlanetsLib_recipe_productivity_effects, remove all effects not flagged with PlanetsLib_force_include.

--ChangeResultProductivityModifier
--Properties:
--  allow_multiple_results: boolean. Default: false. When false, only recipes with one result are added to the technology's effect list.
--  category (optional) (Either (name and type) or category required) 
--Inherited from ChangeRecipeProductivityModifier https://lua-api.factorio.com/latest/types/ChangeRecipeProductivityModifier.html
--  type (optional)
--  name (optional)
--  change 
--  icons (optional)
--  icon (optional)
--  icon_size (optional)
--  hidden (optional)
--  use_icon_overlay_constant (optional)



--New Modifier field: PlanetsLib_force_include
-- Makes this modifier immune to purge_other_effects.

--New recipe field: PlanetsLib_blacklist_technology_updates
-- Stops PlanetsLib from targeting this recipe in technology updates.



local function xor(a,b)
    return (a or b) and (not(a and b))
end

---@param tech table (TechnologyPrototype)
---@author MeteorSwarm
function Public.process_technology_recipe_productivity_effects(tech) 
    if tech.PlanetsLib_recipe_productivity_effects then
        
        local new_effects = {}
        if tech.PlanetsLib_recipe_productivity_effects.purge_other_effects then
            for _,effect in pairs(tech.effects) do
                if effect.PlanetsLib_force_include then
                    table.insert(new_effects,effect)
                end
            end
        else
            new_effects = table.deepcopy(tech.effects)
        end
        if not tech.effects then tech.effects = {} end
        

        for _,effect in pairs(tech.PlanetsLib_recipe_productivity_effects.effects) do
            local type = effect.type
            local name = effect.name
            local change = effect.change
            local category = effect.category 
            assert(xor(name,category),"You may only filter by result name or by category.")
            if category then
                assert(tech.PlanetsLib_recipe_productivity_effects.category_blacklist == nil,"category_blacklist and category are incompatible.")
            end

            local category_blacklist = tech.PlanetsLib_recipe_productivity_effects.category_blacklist or {"recycling"} --Excluded recipe categories

            for _,recipe in pairs(data.raw["recipe"]) do
                if not (recipe.Planetslib_blacklist_technology_updates or rro.contains(category_blacklist,recipe.category) )
                and recipe.results and (#recipe.results == 1 or effect.allow_multiple_results) then
                    for _,result in pairs(recipe.results) do
                        if result.type == type and ((not name and recipe.category == category) or result.name == name) then
                            local new_effect = {
                                type = "change-recipe-productivity",
                                recipe = recipe.name,
                                change = change,
                                hidden = effect.hidden,
                                use_icon_overlay_constant = effect.use_icon_overlay_constant,
                                icons = effect.icons,
                                icon = effect.icon,
                                icon_size = effect.icon_size,
                            }
                            --Check if effect already exists 
                            local contains = false
                            for _,effect in pairs(new_effects) do
                                if effect.recipe == new_effect.recipe then
                                    contains = true
                                end
                            end
                            if not contains then
                                table.insert(new_effects,new_effect)
                            end
                            break --To stop the same recipe from being added multiple times per result item.
                        end
                    end
                end
            end
            tech.effects = new_effects

        end
        tech.PlanetsLib_recipe_producitivity_effects = nil
    end



end

return Public
