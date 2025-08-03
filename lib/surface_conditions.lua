local util = require("util")
local rro = require("lib.objects")
local Public = {}

-- Restricts the surface conditions of an existing recipe or entity. If the new condition is more restrictive in any way than the existing conditions, those restrictions will be applied.
function Public.restrict_surface_conditions(recipe_or_entity, condition)
	condition = util.table.deepcopy(condition)
	
	local surface_conditions = recipe_or_entity.surface_conditions
			and util.table.deepcopy(recipe_or_entity.surface_conditions)
		or {}
	
	-- If surface condition doesn't already exist, simply insert the condition into the recipe/entity and complete execution
	-- if not (rro.contains(surface_conditions,{property = condition.property, min = "_any", max = "_any"})) then
	-- 	rro.soft_insert(surface_conditions,condition)
	-- 	goto continue
	-- end
	for i = 1, #surface_conditions do
		local existing = surface_conditions[i]
		if existing.property == condition.property then
			if condition.min ~= nil then
				if existing.min ~= nil then
					existing.min = math.max(existing.min, condition.min)
				else
					existing.min = condition.min
				end
			end

			if condition.max ~= nil then
				if existing.max ~= nil then
					existing.max = math.min(existing.max, condition.max)
				else
					existing.max = condition.max
				end
			end
			goto continue
		end
	end

	-- No existing condition found, add new one
	table.insert(surface_conditions, {
		property = condition.property,
		min = condition.min,
		max = condition.max,
	})
	::continue::

	recipe_or_entity.surface_conditions = surface_conditions
end

-- Relaxes the surface conditions of an existing recipe or entity. If a condition with a 'min' field is passed, any existing min conditions on the same property will be relaxed to that min value. Similarly for 'max'. Note that failing to pass a max does not mean that any existing maxima for that property will be removed.
function Public.relax_surface_conditions(recipe_or_entity, condition)
	condition = util.table.deepcopy(condition)

	local surface_conditions = recipe_or_entity.surface_conditions
			and util.table.deepcopy(recipe_or_entity.surface_conditions)
		or {}

	for i = 1, #surface_conditions do
		local existing_condition = surface_conditions[i]
		if existing_condition.property == condition.property then
			if condition.min ~= nil and existing_condition.min ~= nil then
				existing_condition.min = math.min(existing_condition.min, condition.min)
			end

			if condition.max ~= nil and existing_condition.max ~= nil then
				existing_condition.max = math.max(existing_condition.max, condition.max)
			end
		end
	end

	recipe_or_entity.surface_conditions = surface_conditions
end

function Public.remove_surface_condition(recipe_or_entity, condition)
	if recipe_or_entity.surface_conditions then
		local conditions = util.table.deepcopy(recipe_or_entity.surface_conditions)
		local changed = false
		for i = #conditions, 1, -1 do
			local c = conditions[i]
			if type(condition) == "string" then
				if c.property == condition then
					table.remove(conditions, i)
					changed = true
				end
			elseif
				(c.property and condition.property and c.property == condition.property)
				and (not (condition.min or c.min) or (condition.min and c.min and c.min == condition.min))
				and (not (condition.max or c.max) or (condition.max and c.max and c.max == condition.max))
			then
				table.remove(conditions, i)
				changed = true
			end
		end

		if changed then
			recipe_or_entity.surface_conditions = conditions
		end
	end
end

function Public.restrict_to_planet(recipe_or_entity, planet)
	local surface_conditions = recipe_or_entity.surface_conditions
			and util.table.deepcopy(recipe_or_entity.surface_conditions)
		or {}

	local condition_value = PlanetsLib.planet_str.get_planet_str_double(planet)

	table.insert(surface_conditions, {
		property = "planet-str",
		min = condition_value,
		max = condition_value,
	})

	recipe_or_entity.surface_conditions = surface_conditions
end

--== Older APIs: ==--

local function exact_value(property, value) -- Returns a surface condition locking the acceptable range of values to exactly one.
	return {
		property = property,
		min = value,
		max = value,
	}
end

function Public.restrict_to_surface(planet) -- Returns a surface condition restricting prototype to the provided planet.
	return exact_value("planet-str", PlanetsLib.planet_str.get_planet_str_double(planet))
end

return Public
