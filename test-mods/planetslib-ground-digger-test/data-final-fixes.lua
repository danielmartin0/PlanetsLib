-- Defined in final-fixes to exercise the late-registration path: PlanetsLib's own
-- data-final-fixes has already run by the time this file executes.

data:extend({
	{
		type = "recipe-category",
		name = "late-digging",
	},
	{
		type = "recipe",
		name = "late-digger-recipe",
		categories = { "late-digging" },
		energy_required = 1,
		ingredients = {},
		results = { { type = "item", name = "copper-ore", amount = 1 } },
		enabled = true,
		main_product = "copper-ore",
	},
})

-- Vulcanus only exists when Space Age is enabled.
if mods["space-age"] then
	PlanetsLib.enable_ground_diggers("vulcanus", "late-digger-recipe", {
		blacklist = { "electric-mining-drill" },
	})
end
