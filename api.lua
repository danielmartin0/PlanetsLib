local technology = require("lib.technology")
local planet = require("lib.planet")

function PlanetsLib:extend(configOrConfigs)
	local configs = util.table.deepcopy(configOrConfigs)

	if not configs[1] then
		configs = { configs }
	end

	for _, config in ipairs(configs) do
		planet.extend(config)
	end
end

function PlanetsLib:update(configOrConfigs)
	local configs = util.table.deepcopy(configOrConfigs)

	if not configs[1] then
		configs = { configs }
	end

	for _, config in ipairs(configs) do
		planet.update(config)
	end
end

PlanetsLib.technology_icons_planet_cargo_drops = technology.technology_icons_planet_cargo_drops
PlanetsLib.technology_effect_cargo_drops = technology.technology_effect_cargo_drops
PlanetsLib.technology_icons_moon = technology.technology_icons_moon

PlanetsLib.borrow_music = planet.borrow_music

PlanetsLib.planet_str=require("lib.planet-str")

function PlanetsLib.exact_value(property,value) -- Returns a surface condition locking the acceptable range of values to exactly one.
	return{
        property = property,
        min = value,
        max = value,
    }
end

function PlanetsLib.restrict_to_surface(planet) -- Returns a surface condition restricting prototype to the provided planet.
	return PlanetsLib.exact_value("planet-str",PlanetsLib.planet_str.get_planet_str_double(planet))
end



--- This function sets `default_import_location` based on an item name and planet.
--- `default_import_location` is used by the space platform GUI to
--- define the default planet where an item will be imported from.
PlanetsLib.set_default_import_location = planet.set_default_import_location
