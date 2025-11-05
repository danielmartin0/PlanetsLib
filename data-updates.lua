PlanetsLib.check_global_variables()
local orbits = require("lib.orbits")

if mods["space-age"] then
	require("prototypes.override.handle-previously-invalid-parents")
	orbits.ensure_all_locations_have_orbits()
	require("prototypes.override.rocket-silos")
end

require("prototypes.override.centrifuge")

-- module_visualisations[1] is vanilla art style:
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][1].pictures.filename =
"__PlanetsLib__/graphics/entity/beacon/beacon-module-slot-1.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][1].pictures.line_length = 5
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][1].pictures.variation_count = 5
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][2].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-mask-box-1.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][2].pictures.line_length = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][2].pictures.variation_count = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][3].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-mask-lights-1.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][3].pictures.height = 24
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][3].pictures.line_length = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][3].pictures.variation_count = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][4].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-lights-1.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][4].pictures.line_length = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[1][4].pictures.variation_count = 4

data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][1].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-slot-2.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][1].pictures.line_length = 5
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][1].pictures.variation_count = 5
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][2].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-mask-box-2.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][2].pictures.line_length = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][2].pictures.variation_count = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][3].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-mask-lights-2.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][3].pictures.line_length = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][3].pictures.variation_count = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][4].pictures.filename =
	"__PlanetsLib__/graphics/entity/beacon/beacon-module-lights-2.png"
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][4].pictures.line_length = 4
data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots[2][4].pictures.variation_count = 4

log(serpent.block(data.raw.beacon.beacon.graphics_set.module_visualisations[1].slots))
