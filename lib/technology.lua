local Public = {}

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
		effects = Public.technology_effect_cargo_drops(planet),
		icons = Public.technology_icons_planet_cargo_drops(planet_technology_icon, planet_technology_icon_size),
	}
end

function Public.technology_icons_planet_cargo_drops(planet_icon, icon_size)
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
			shift = { -17, 55 },
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

function Public.technology_effect_cargo_drops(planet_name)
	return {
		{
			type = "nothing",
			effect_description = { "planetslib.cargo-drops-tech-description", "[space-location=" .. planet_name .. "]" },
		},
	}
end

function Public.technology_icon_moon(moon_icon, icon_size)
	icon_size = icon_size or 256

	local icons = {
		{
			icon = moon_icon,
			icon_size = icon_size,
		},
		{
			icon = "__PlanetsLib__/graphics/icons/moon-technology-symbol.png",
			icon_size = 128,
			scale = 0.5,
			shift = { 50, 50 },
		},
	}
	return icons
end

-- The same as util.technology_icon_constant_planet from the vanilla library, but allows any icon size.
function Public.technology_icon_planet(planet_icon, icon_size)
	icon_size = icon_size or 256

	local icons = {
		{
			icon = planet_icon,
			icon_size = icon_size,
		},
		{
			icon = "__core__/graphics/icons/technology/constants/constant-planet.png",
			icon_size = 128,
			scale = 0.5,
			shift = { 50, 50 },
		},
	}
	return icons
end

-- TODO: Apply use_icon_overlay_constant to the unlock if the planet is a moon

-- This function makes the technology use all sciences in the base lab.
-- Compatibility for technologies after prometheum science.
function Public.set_science_packs_from_lab(technology, lab)
	if not (technology and technology.unit and lab and lab.inputs) then
		return
	end

	technology.unit.ingredients = technology.unit.ingredients or {}

	local inputs = lab.inputs
	local existing_packs = {}

	for _, pack in pairs(technology.unit.ingredients) do
		existing_packs[pack[1]] = true
	end

	for _, value in pairs(inputs) do --For input in lab inputs
		local to_insert = true
		for _, effect in pairs(technology.effects) do --Check if this technology unlocks a science pack. If yes, don't make this technology require that pack.
			if effect.type == "unlock-recipe" and effect.recipe == value then
				to_insert = false
				break
			end
		end
		for key, pack in pairs(existing_packs) do
			if key == value then
				to_insert = false
				break
			end
		end
		if to_insert then
			table.insert(technology.unit.ingredients, { value, 1 }) --Inserts science pack.
		end
	end
end

return Public
