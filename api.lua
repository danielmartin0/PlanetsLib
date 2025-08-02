local util = require("util")
local lib = require("lib.lib")
local technology = require("lib.technology")
local planet = require("lib.planet")
local planet_str = require("lib.planet-str")
local surface_conditions = require("lib.surface_conditions")
local mod_data = require("lib.mod-data")


--== APIs ==--
-- API documentation lives in README.md (or on the mod portal.)

PlanetsLib.add_science_packs_from_vanilla_lab_to_technology =
	technology.add_science_packs_from_vanilla_lab_to_technology
PlanetsLib.sort_science_pack_names = technology.sort_science_pack_names
PlanetsLib.get_child_technologies = technology.get_child_technologies
PlanetsLib.excise_tech_from_tech_tree = technology.excise_tech_from_tech_tree
PlanetsLib.excise_recipe_from_tech_tree = technology.excise_recipe_from_tech_tree
PlanetsLib.excise_effect_from_tech_tree = technology.excise_effect_from_tech_tree
PlanetsLib.technology_icon_moon = technology.technology_icon_moon
PlanetsLib.technology_icon_planet = technology.technology_icon_planet
PlanetsLib.cargo_drops_technology_base = technology.cargo_drops_technology_base


PlanetsLib.assign_rocket_part_recipe = mod_data.assign_rocket_part_recipe

PlanetsLib.restrict_surface_conditions = surface_conditions.restrict_surface_conditions
PlanetsLib.relax_surface_conditions = surface_conditions.relax_surface_conditions
PlanetsLib.remove_surface_condition = surface_conditions.remove_surface_condition

PlanetsLib.set_default_import_location = planet.set_default_import_location
PlanetsLib.borrow_music = planet.borrow_music

function PlanetsLib:extend(configOrConfigs)
	local configs = lib.wrap_single_config(util.table.deepcopy(configOrConfigs))

	for _, config in ipairs(configs) do
		planet.extend(config)
	end
end
function PlanetsLib:update(config)
	if #config == 1 then
		planet.update(config[1])
	else
		planet.update(config)
	end
end

--== Undocumented APIs ==--
-- Though these APIs are undocumented we should still support them, as mods may be using them.

PlanetsLib.process_technology_recipe_productivity_effects = technology.process_technology_recipe_productivity_effects
PlanetsLib.technology_icons_moon = technology.technology_icon_moon
PlanetsLib.technology_icon_constant_planet = technology.technology_icon_planet
PlanetsLib.technology_icons_planet_cargo_drops = technology.technology_icons_planet_cargo_drops
PlanetsLib.technology_effect_cargo_drops = technology.technology_effect_cargo_drops
PlanetsLib.surface_conditions = surface_conditions
PlanetsLib.restrict_to_planet = surface_conditions.restrict_to_planet
PlanetsLib.planet_str = planet_str


PlanetsLib.objects = require("lib.objects") --Table manipulation library 
PlanetsLib.rro = PlanetsLib.objects --Alias for PlanetsLib.objects


-- For backwards compatibility (mod-data was not always a thing). NOTE: These functions return numbers, other mods may change the tier prototypes after you call this.
PlanetsLib.get_planet_tier = function(planet_name)
	return data.raw["mod-data"]["PlanetsLib-tierlist"].data.planet[planet_name]
		or data.raw["mod-data"]["PlanetsLib-tierlist"].data.default
end

PlanetsLib.get_space_location_tier = function(space_location_name)
	return data.raw["mod-data"]["PlanetsLib-tierlist"].data["space-location"][space_location_name]
		or data.raw["mod-data"]["PlanetsLib-tierlist"].data.default
end
