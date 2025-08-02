require("prototypes.override-final.science")
require("prototypes.override-final.technology-updates")
if mods["space-age"] then
	require("prototypes.override-final.check-unexpected-positions")
	require("prototypes.override-final.update-connections")
	local ps = require("lib.planet-str")

	local planets = data.raw.planet

	--Set planet string for every planet based on planet name.
	for _, planet in pairs(planets) do
		if planet["surface_properties"] and planet["surface_properties"]["planet-str"] == nil then --Other mods can override planet strings, this is a last-resort planet string generator.
			local truncated_name = string.sub(planet.name, 1, 8) --Planet strings can only be 8 characters or less.
			ps.set_planet_str(planet, truncated_name)
		end
	end

	require("prototypes.override-final.starmap")

	for _, type in pairs({ "space-location", "planet" }) do
		for _, location in pairs(data.raw[type]) do
			if location.sprite_only then
				data.raw[type][location.name] = nil
			end
		end
	end

	local gas_list = { "oxygen", "nitrogen", "carbon-dioxide", "argon" }
	local enforce_percentage = settings.startup["PlanetsLib-enforce-gas-percentage"].value --Whether code should assert that combined gas contents add up to less than 100%.

	for _, planet in pairs(planets) do
		if planet.surface_properties and enforce_percentage then
			local gas_content = 0
			for _, gas in pairs(gas_list) do
				if planet.surface_properties[gas] then
					gas_content = gas_content + planet.surface_properties[gas]
				end
			end
			assert(
				gas_content <= 100,
				"Combined gas contents of planet "
					.. planet.name
					.. ' exceed 100%. To override this assertion, add \'data.raw["bool-setting"]["PlanetsLib-enforce-gas-percentage"].forced_value = false\' to settings-updates.lua.'
			)
		end
	end
end
