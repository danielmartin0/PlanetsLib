-- Data-stage fixture: PlanetsLib.assign_entity_removal_floor() and the
-- entity_removal_floors mod-data table.
--
-- The runtime suite creates a surface for funit-erf-planet and drives the
-- deconstruction/tile events through the planetslib_funit remote interface.
-- Everything here is Space Age only because the rule is tied to a planet.

local results = require("lib.results")

local SUITE = "entity_removal_floors_data"

local function record(id, fn)
	local ok, err = pcall(fn)
	results.record(SUITE, id, ok, err)
end

local function add_simple_entity(name, options)
	options = options or {}
	local entity = table.deepcopy(data.raw["simple-entity"]["big-rock"])
	entity.name = name
	entity.autoplace = nil
	entity.collision_box = options.collision_box or { { -0.45, -0.45 }, { 0.45, 0.45 } }
	entity.selection_box = options.selection_box or { { -0.5, -0.5 }, { 0.5, 0.5 } }
	entity.minable = options.minable or { mining_time = 0.2, result = "stone", count = 1 }
	entity.max_health = 100
	data:extend({ entity })
	return entity
end

local setup_ok, setup_err = pcall(function()
	local safe_tile = table.deepcopy(data.raw.tile["stone-path"])
	safe_tile.name = "funit-erf-safe"
	safe_tile.localised_name = { "tile-name.stone-path" }
	safe_tile.destroys_dropped_items = nil
	data:extend({ safe_tile })

	local unsafe_tile = table.deepcopy(data.raw.tile["dry-dirt"])
	unsafe_tile.name = "funit-erf-unsafe"
	unsafe_tile.localised_name = { "tile-name.dry-dirt" }
	unsafe_tile.destroys_dropped_items = true
	data:extend({ unsafe_tile })

	-- A water-like unsafe tile where paths cannot be built but foundations can.
	local foundation_only = table.deepcopy(data.raw.tile["water"])
	foundation_only.name = "funit-erf-foundation-only"
	foundation_only.autoplace = nil
	foundation_only.fluid = nil
	foundation_only.destroys_dropped_items = true
	data:extend({ foundation_only })
	local foundation_item = data.raw.item["foundation"]
	assert(foundation_item and foundation_item.place_as_tile and foundation_item.place_as_tile.tile_condition,
		"the foundation item is missing its tile_condition list")
	table.insert(foundation_item.place_as_tile.tile_condition, "funit-erf-foundation-only")

	local safe_item = table.deepcopy(data.raw.item["stone-brick"])
	safe_item.name = "funit-erf-safe-item"
	safe_item.place_as_tile.result = "funit-erf-safe"
	data:extend({ safe_item })

	-- An item that places a different tile, used for validation and fallback tests.
	local other_item = table.deepcopy(data.raw.item["landfill"])
	other_item.name = "funit-erf-other-item"
	other_item.place_as_tile.result = "landfill"
	data:extend({ other_item })

	add_simple_entity("funit-erf-rock")
	add_simple_entity("funit-erf-rock-b")
	add_simple_entity("funit-erf-rock-c")
	add_simple_entity("funit-erf-large-rock", {
		collision_box = { { -1.5, -1.1 }, { 1.5, 1.1 } },
		selection_box = { { -1.7, -1.3 }, { 1.7, 1.3 } },
	})
	add_simple_entity("funit-erf-drop-rock", {
		collision_box = { { -0.95, -0.95 }, { 0.95, 0.95 } },
		selection_box = { { -1, -1 }, { 1, 1 } },
		minable = {
			mining_time = 0.2,
			results = {
				{ type = "item", name = "stone", amount = 15 },
				{ type = "item", name = "sulfur", amount = 2 },
			},
		},
	})

	local tree = table.deepcopy(data.raw["tree"]["tree-01"])
	tree.name = "funit-erf-tree"
	tree.autoplace = nil
	tree.collision_box = { { -0.45, -0.45 }, { 0.45, 0.45 } }
	tree.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
	tree.minable = {
		mining_time = 0.2,
		results = { { type = "item", name = "wood", amount = 1 } },
	}
	data:extend({ tree })

	local container = table.deepcopy(data.raw["container"]["wooden-chest"])
	container.name = "funit-erf-container"
	container.autoplace = nil
	data:extend({ container })

	local plant = table.deepcopy(data.raw["plant"]["tree-plant"])
	plant.name = "funit-erf-plant"
	plant.autoplace = nil
	plant.collision_box = { { -0.45, -0.45 }, { 0.45, 0.45 } }
	plant.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
	plant.minable = {
		mining_time = 0.2,
		results = { { type = "item", name = "wood", amount = 1 } },
	}
	data:extend({ plant })

	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = "funit-erf-planet"
	planet.surface_properties = {}
	data:extend({ planet })

	local planet_b = table.deepcopy(data.raw.planet.nauvis)
	planet_b.name = "funit-erf-planet-b"
	planet_b.surface_properties = {}
	data:extend({ planet_b })

	PlanetsLib.assign_entity_removal_floor(
		"funit-erf-planet",
		"funit-erf-rock",
		"funit-erf-safe",
		{
			default_tile_item = "funit-erf-safe-item",
			waiting_message = { "funit-erf-waiting" },
		}
	)

	-- The alias writes the same table and normalises an array of entities.
	PlanetsLib.add_entity_removal_floor_rule(
		"funit-erf-planet",
		{ "funit-erf-rock-b" },
		"funit-erf-safe",
		{ default_tile_item = "funit-erf-safe-item" }
	)

	PlanetsLib.assign_entity_removal_floor(
		"funit-erf-planet",
		{ "funit-erf-large-rock", "funit-erf-drop-rock", "funit-erf-plant", "funit-erf-tree", "funit-erf-container" },
		"funit-erf-safe",
		{ default_tile_item = "funit-erf-safe-item" }
	)

	-- Omitting default_tile_item must infer the item that places the tile.
	PlanetsLib.assign_entity_removal_floor("funit-erf-planet-b", "funit-erf-rock-c", "funit-erf-safe")

	-- Direct mod-data grouped form for the runtime rule index.
	data.raw["mod-data"].Planetslib.data.entity_removal_floors["funit-erf-planet-b"]["funit-erf-group"] = {
		entities = { "funit-erf-rock-b" },
		default_tile = "funit-erf-safe",
	}
end)
results.record(SUITE, "ERF-0-setup", setup_ok, setup_err)
if not setup_ok then
	return true
end

-- ERF-1: canonical per-entity rules, defaults and alias.
record("ERF-1", function()
	local rules = PlanetsLib.constants.entity_removal_floors["funit-erf-planet"]
	assert(rules, "no rules were stored for funit-erf-planet")
	assert(rules["funit-erf-rock"], "the named entity has no rule")
	assert(rules["funit-erf-rock"].default_tile == "funit-erf-safe", "default_tile is wrong")
	assert(rules["funit-erf-rock"].default_tile_item == "funit-erf-safe-item", "explicit tile item is wrong")
	assert(
		rules["funit-erf-rock"].waiting_message[1] == "funit-erf-waiting",
		"the custom waiting message was not stored"
	)
	assert(rules["funit-erf-rock-b"], "the alias did not store its entity rule")
	assert(rules["funit-erf-rock-b"].default_tile == "funit-erf-safe", "the alias rule has the wrong tile")
	assert(rules["funit-erf-large-rock"], "the multi-tile test entity has no rule")
	assert(rules["funit-erf-drop-rock"], "the drop test entity has no rule")
	assert(rules["funit-erf-plant"], "the plant test entity has no rule")
	assert(rules["funit-erf-tree"], "the tree test entity has no rule")
	assert(rules["funit-erf-container"], "the container test entity has no rule")

	local planet_b_rules = PlanetsLib.constants.entity_removal_floors["funit-erf-planet-b"]
	assert(planet_b_rules["funit-erf-rock-c"], "the inferred item rule is missing")
	assert(
		planet_b_rules["funit-erf-rock-c"].default_tile_item == "funit-erf-safe-item",
		"the tile item was not inferred from place_as_tile"
	)
	assert(
		planet_b_rules["funit-erf-rock-c"].waiting_message[1] == "planetslib.entity-removal-floor-waiting",
		"the default waiting message is wrong"
	)

	local grouped = planet_b_rules["funit-erf-group"]
	assert(grouped and grouped.entities and grouped.entities[1] == "funit-erf-rock-b", "the grouped rule was not preserved")
end)

-- ERF-2: validation and normalisation.
record("ERF-2", function()
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, nil, "funit-erf-rock", "funit-erf-safe"),
		"a nil planet must be rejected"
	)
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, "funit-missing-planet", "funit-erf-rock", "funit-erf-safe"),
		"an unknown planet must be rejected"
	)
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, "funit-erf-planet", {}, "funit-erf-safe"),
		"an empty entity list must be rejected"
	)
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, "funit-erf-planet", "missing-entity", "funit-erf-safe"),
		"an unknown entity must be rejected"
	)
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, "funit-erf-planet", "transport-belt", "funit-erf-safe"),
		"an unsupported entity type must be rejected"
	)
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, "funit-erf-planet", "funit-erf-rock", "missing-tile"),
		"an unknown tile must be rejected"
	)
	assert(
		not pcall(PlanetsLib.assign_entity_removal_floor, "funit-erf-planet", "funit-erf-rock", "funit-erf-unsafe"),
		"an unsafe default tile must be rejected"
	)
	assert(
		not pcall(
			PlanetsLib.assign_entity_removal_floor,
			"funit-erf-planet",
			"funit-erf-rock",
			"funit-erf-safe",
			{ default_tile_item = "missing-item" }
		),
		"an unknown tile item must be rejected"
	)
	assert(
		not pcall(
			PlanetsLib.assign_entity_removal_floor,
			"funit-erf-planet",
			"funit-erf-rock",
			"funit-erf-safe",
			{ default_tile_item = "funit-erf-other-item" }
		),
		"an item that places a different tile must be rejected"
	)

	-- Dictionary form, false entries ignored, and prototype input unwrapping.
	PlanetsLib.assign_entity_removal_floor(
		data.raw.planet["funit-erf-planet"],
		{ ["funit-erf-rock"] = true, ["funit-erf-rock-b"] = false },
		"funit-erf-safe"
	)
	local rules = PlanetsLib.constants.entity_removal_floors["funit-erf-planet"]
	assert(rules["funit-erf-rock"], "the dictionary form lost a true entry")
	assert(rules["funit-erf-rock"].default_tile_item == "funit-erf-safe-item", "the inferred item is wrong")
end)

return true
