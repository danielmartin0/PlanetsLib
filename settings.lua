data:extend({
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-warn-on-hidden-prerequisites",
		default_value = true,
		order = "a",
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-update-vanilla-recipe-productivity-techs",
		default_value = true,
		order = "b",
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-unlink-hidden-prerequisites",
		default_value = false,
		order = "c",
	},
	
})

data:extend({
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-enable-temperature",
		forced_value = false,
		default_value = false,
		hidden = true,
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-enable-oxygen",
		forced_value = false,
		default_value = false,
		hidden = true,
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-enable-nitrogen",
		forced_value = false,
		default_value = false,
		hidden = true,
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-enable-carbon-dioxide",
		forced_value = false,
		default_value = false,
		hidden = true,
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-enable-argon",
		forced_value = false,
		default_value = false,
		hidden = true,
	},
	{
		type = "bool-setting",
		setting_type = "startup",
		name = "PlanetsLib-enforce-gas-percentage",
		forced_value = true,
		default_value = true,
		hidden = true,
	},
})
