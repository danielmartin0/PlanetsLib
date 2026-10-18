-- Test mod for PlanetsLib.enable_ground_diggers().
--
-- Registers a recipe in the data stage and enables ground diggers on Nauvis.
-- See data-final-fixes.lua for the late-registration path.

data:extend({
	{
		type = "recipe-category",
		name = "ground-digging-test",
	},
	{
		type = "recipe",
		name = "ground-digger-test-recipe",
		categories = { "ground-digging-test" },
		energy_required = 2,
		ingredients = {},
		results = { { type = "item", name = "stone", amount = 1 } },
		enabled = true,
		main_product = "stone",
	},
})

PlanetsLib.enable_ground_diggers("nauvis", "ground-digger-test-recipe")
