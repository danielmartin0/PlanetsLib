local Public = {}

-- PlanetsLib tiers are a simple way for modded planets to define where they typically fit in a Space Age playthrough. It has no meaning by itself, but other mods can be sensitive to them.

Public.fallback_tier = 3.33333 -- Vertically south of the star in Organized Solar System

--== Tier meanings guide ==--
-- Tier 0:  Pre-Nauvis
-- Tier 1:  Nauvis & friends
-- Tier 2:  First steps from Nauvis
-- Tier 3:  Intermediate planets that may reward preparation
-- Tier 4:  More involved planets that may depend on earlier progress
-- Tier 5:  Aquilo and the vanilla endgame
-- Tier 6:  Post-endgame planets and other oddities
-- Tier -1: Indicates the planet sits outside of this system in some way.

Public.vanilla_tiers = {
	planet = {
		nauvis = 1,
		vulcanus = 1.8,
		fulgora = 2.4,
		gleba = 3.5,
		aquilo = 5,
	},
	["space-location"] = {
		["shattered-planet"] = 5,
		["solar-system-edge"] = 5,
	},
}

Public.modded_tiers = {
	planet = {
		akularis = 0.5,
		gerkizia = 0.5,
		quadromire = 0.5,
		mickora = 1,
		vicrox = 1.4,
		froodara = 1.8,
		tchekor = 2,
		jahtra = 2.2,
		nekohaven = 2.5,
		zzhora = 2.5,
		janus = 3,
		ithurice = 3.3,
		corrundum = 3.3,
		castra = 4,
		tapatrion = 4,
		tenebris = 4,
		moshine = 4.1,
		cubium = 4.1,
		rubia = 4.5,
		paracelsin = 4.8,
		hexalith = 5.1,
		maraxsis = 5.3,
		frozeta = 5.5,
		naufulglebunusilo = 6,
		arrakis = 6,
	},
	["space-location"] = {
		["slp-solar-system-sun"] = 0.2,
		["slp-solar-system-sun2"] = 0.2,
		["oratl-approach"] = 5.4
		oratl = 5.5
		secretas = 5.65,
	},
}

Public.get_planet_tier = function(planet_name)
	local tier = Public.vanilla_tiers.planet[planet_name]
		or Public.modded_tiers.planet[planet_name]
		or Public.fallback_tier

	return tier
end

Public.get_space_location_tier = function(space_location_name)
	local tier = Public.vanilla_tiers["space-location"][space_location_name]
		or Public.modded_tiers["space-location"][space_location_name]
		or Public.fallback_tier

	return tier
end

return Public
