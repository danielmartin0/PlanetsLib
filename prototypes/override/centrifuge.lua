local pipe_picture = assembler3pipepictures()
pipe_picture.north = util.empty_sprite()
pipe_picture.south.filename = "__PlanetsLib__/graphics/entity/centrifuge/centrifuge-pipe-S.png"
pipe_picture.east.filename = "__PlanetsLib__/graphics/entity/centrifuge/centrifuge-pipe-E.png"
pipe_picture.west.filename = "__PlanetsLib__/graphics/entity/centrifuge/centrifuge-pipe-W.png"

local fluid_boxes = {
	{
		production_type = "input",
		pipe_picture = pipe_picture,
		pipe_covers = pipecoverspictures(),
		volume = 1000,
		pipe_connections = { { flow_direction = "input", direction = defines.direction.north, position = { 0, -1 } } },
	},
	{
		production_type = "input",
		pipe_picture = pipe_picture,
		pipe_covers = pipecoverspictures(),
		volume = 1000,
		pipe_connections = { { flow_direction = "input", direction = defines.direction.west, position = { -1, 0 } } },
	},
	{
		production_type = "output",
		pipe_picture = pipe_picture,
		pipe_covers = pipecoverspictures(),
		volume = 1000,
		pipe_connections = { { flow_direction = "output", direction = defines.direction.south, position = { 0, 1 } } },
	},
	{
		production_type = "output",
		pipe_picture = pipe_picture,
		pipe_covers = pipecoverspictures(),
		volume = 1000,
		pipe_connections = { { flow_direction = "output", direction = defines.direction.east, position = { 1, 0 } } },
	},
}

-- Ensure centrifuges can accept fluid recipes. It isn't ideal that we change modded centrifuges this way, as the fluid boxes may be in the wrong positions, but on the other hand they're only visible when fluid recipes are used.
for _, machine in pairs(data.raw["assembling-machine"]) do
	if machine.crafting_categories and not machine.fluid_boxes then
		for _, category in pairs(machine.crafting_categories) do
			if category == "centrifuging" then
				machine.fluid_boxes = util.table.deepcopy(fluid_boxes)
				machine.fluid_boxes_off_when_no_fluid_recipe = true
				break
			end
		end
	end
end

-- Add centrifuge tower tint.
local centrifuge = data.raw["assembling-machine"]["centrifuge"]
if
	centrifuge
	and centrifuge.graphics_set
	and centrifuge.graphics_set.working_visualisations
	and centrifuge.graphics_set.working_visualisations[1]
	and centrifuge.graphics_set.working_visualisations[2]
	and centrifuge.graphics_set.working_visualisations[2].animation
	and centrifuge.graphics_set.working_visualisations[2].animation.layers
then
	centrifuge.graphics_set.default_recipe_tint = { primary = { 0, 1, 0.2 } }
	centrifuge.graphics_set.recipe_not_set_tint = { primary = { 0, 1, 0.2 } }

	centrifuge.graphics_set.working_visualisations[1].apply_recipe_tint = "primary"
	centrifuge.graphics_set.working_visualisations[2].apply_recipe_tint = "primary"

	local layers = centrifuge.graphics_set.working_visualisations[2].animation.layers
	layers[1].filename = "__PlanetsLib__/graphics/entity/centrifuge/centrifuge-C-light.png"
	layers[2].filename = "__PlanetsLib__/graphics/entity/centrifuge/centrifuge-B-light.png"
	layers[3].filename = "__PlanetsLib__/graphics/entity/centrifuge/centrifuge-A-light.png"
end