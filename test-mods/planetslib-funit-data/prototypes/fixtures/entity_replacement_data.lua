-- Data-stage fixture: entity replacement rules, generated planet variants and
-- rocket multiplier variants.
--
-- The runtime suites (entity_replacement_runtime / entity_replacement_migration)
-- assert these results and the real prototypes recorded here. Every rule is
-- bound to a startup boolean, as required by PlanetsLib's API contract.

local results = require("lib.results")

local SUITE = "entity_replacement_data"
local SETTING = "planetslib-funit-data-enable-entity-replacement-fixture"
local DISABLED_SETTING = "PlanetsLib-disable-all-entity-replacements"

local function record(id, fn)
	local ok, err = pcall(fn)
	results.record(SUITE, id, ok, err)
	return ok
end

local function contains(list, value)
	if not list then
		return false
	end
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end
	return false
end

-- The global kill switch overrides every rule's own bound setting, so the
-- expected `enabled` flag is the bound setting only when the switch is off.
local function expected_enabled(bound_setting)
	local disable_all = settings.startup[DISABLED_SETTING]
	if disable_all and disable_all.value then
		return false
	end
	return settings.startup[bound_setting].value
end

local function create_planet(name)
	local planet = table.deepcopy(data.raw.planet.nauvis)
	planet.name = name
	planet.surface_properties = {}
	data:extend({ planet })
	return data.raw.planet[name]
end

-- Test planets are created before PlanetsLib's data-final-fixes runs, so the
-- rocket-multiplier override can see the special properties below.
local planet_a = create_planet("funit-ent-planet-a")
local planet_b = create_planet("funit-ent-planet-b")
local rocket_planet = create_planet("funit-ent-rocket")

-- ENT-1a: rule storage, including the default bound setting.
record("ENT-1a", function()
	assert(planet_a, "the test planet was not created")
	PlanetsLib.assign_entity_replacement("funit-ent-planet-a", "funit-ent-old-a", "funit-ent-new-a", SETTING)
	local rules = PlanetsLib.constants.on_entity_placed_on_planet_replacements["funit-ent-planet-a"]
	local rule = rules["funit-ent-old-a"]
	assert(rule, "the rule was not stored")
	assert(rule.old_entity == "funit-ent-old-a", "old_entity was not stored")
	assert(rule.entity == "funit-ent-new-a", "entity was not stored")
	assert(
		rule.enabled == expected_enabled(SETTING),
		"the rule was not bound to the supplied setting (or ignored the global kill switch)"
	)

	-- With no bound_setting the documented default setting is used.
	PlanetsLib.assign_entity_replacement("funit-ent-planet-a", "funit-ent-old-b", "funit-ent-new-b")
	local default_rule = rules["funit-ent-old-b"]
	assert(default_rule, "the default-bound rule was not stored")
	assert(
		default_rule.enabled == expected_enabled("PlanetsLib-enable-entity-replacements"),
		"the default bound setting was not used (or ignored the global kill switch)"
	)
end)

-- ENT-1b: duplicate assignment on the same planet errors.
record("ENT-1b", function()
	PlanetsLib.assign_entity_replacement("funit-ent-planet-b", "funit-ent-dup-old", "funit-ent-dup-new", SETTING)
	local ok, err = pcall(
		PlanetsLib.assign_entity_replacement,
		"funit-ent-planet-b",
		"funit-ent-dup-old",
		"funit-ent-dup-new-2",
		SETTING
	)
	assert(not ok, "assigning the same entity twice on the same planet should error")
	assert(tostring(err):find("more than once", 1, true), "the duplicate error should explain the limitation")
end)

-- ENT-1c: recursive rules are rejected.
record("ENT-1c", function()
	PlanetsLib.assign_entity_replacement("funit-ent-planet-b", "funit-ent-rec-a", "funit-ent-rec-b", SETTING)
	local ok, err = pcall(
		PlanetsLib.assign_entity_replacement,
		"funit-ent-planet-b",
		"funit-ent-rec-b",
		"funit-ent-rec-a",
		SETTING
	)
	assert(not ok, "a recursive rule set should error")
	assert(tostring(err):find("Recursive", 1, true), "the recursion error should mention recursion")
end)

-- ENT-1d: the documented variant lists are maintained.
record("ENT-1d", function()
	local variants = PlanetsLib.constants.entity_variants_list["funit-ent-old-a"]
	assert(contains(variants, "funit-ent-new-a"), "entity_variants_list did not record the variant")

	local inverse = PlanetsLib.constants.entity_variants_list_inverse["funit-ent-new-a"]
	assert(inverse and #inverse == 1, "entity_variants_list_inverse should have exactly one entry")
	assert(inverse[1].entity == "funit-ent-old-a", "the inverse entry has the wrong base entity")
	assert(inverse[1].suffix == nil, "the inverse entry should have no suffix for a plain assignment")

	PlanetsLib.assign_entity_replacement(
		"funit-ent-planet-a",
		"funit-ent-suffix-old",
		"funit-ent-suffix-new",
		SETTING,
		"funit-suffix"
	)
	local suffix_inverse = PlanetsLib.constants.entity_variants_list_inverse["funit-ent-suffix-new"]
	assert(
		suffix_inverse and #suffix_inverse == 1 and suffix_inverse[1].suffix == "funit-suffix",
		"the name suffix was not stored in the inverse list"
	)
end)

-- ENT-1e: mass assignment from a dictionary table.
record("ENT-1e", function()
	PlanetsLib.assign_entity_replacement("funit-ent-planet-a", {
		["funit-ent-mass-old-1"] = { entity = "funit-ent-mass-new-1" },
		["funit-ent-mass-old-2"] = { entity = "funit-ent-mass-new-2" },
	}, nil, SETTING)

	local rules = PlanetsLib.constants.on_entity_placed_on_planet_replacements["funit-ent-planet-a"]
	assert(rules["funit-ent-mass-old-1"].entity == "funit-ent-mass-new-1", "the first mass assignment was not stored")
	assert(rules["funit-ent-mass-old-2"].entity == "funit-ent-mass-new-2", "the second mass assignment was not stored")
	assert(
		rules["funit-ent-mass-old-1"].enabled == expected_enabled(SETTING),
		"the mass assignment ignored the bound setting (or the global kill switch)"
	)
end)

-- ENT-1f: a table (list) of planet names applies the rule to every planet.
record("ENT-1f", function()
	PlanetsLib.assign_entity_replacement({
		"funit-ent-planet-a",
		"funit-ent-planet-b",
	}, "funit-ent-pt-old", "funit-ent-pt-new", SETTING)

	local replacements = PlanetsLib.constants.on_entity_placed_on_planet_replacements
	assert(
		replacements["funit-ent-planet-a"]["funit-ent-pt-old"].entity == "funit-ent-pt-new",
		"planet A did not receive the rule"
	)
	assert(
		replacements["funit-ent-planet-b"]["funit-ent-pt-old"].entity == "funit-ent-pt-new",
		"planet B did not receive the rule"
	)
end)

-- ENT-1h: the planet-list form must not leak a non-string planet key into the
-- rule tables. assign_entity_replacement expands the list before deriving the
-- planet key, so on_entity_placed_on_planet_replacements and
-- inverted_entity_variants must only contain string keys after ENT-1f.
record("ENT-1h", function()
	local spurious_keys = 0
	for key in pairs(PlanetsLib.constants.on_entity_placed_on_planet_replacements) do
		if type(key) ~= "string" then
			spurious_keys = spurious_keys + 1
		end
	end
	for key in pairs(PlanetsLib.constants.inverted_entity_variants) do
		if type(key) ~= "string" then
			spurious_keys = spurious_keys + 1
		end
	end
	assert(
		spurious_keys == 0,
		"assign_entity_replacement(planet-list) stored "
			.. spurious_keys
			.. " non-string planet key(s)"
	)
end)

-- ENT-1g: rules used by the runtime suite (all on nauvis).
record("ENT-1g", function()
	local assignments = {
		{ "wooden-chest", "iron-chest" },
		{ "stone-furnace", "steel-furnace" },
		{ "assembling-machine-3", "assembling-machine-2" },
	}
	for _, pair in ipairs(assignments) do
		PlanetsLib.assign_entity_replacement("nauvis", pair[1], pair[2], SETTING)
	end

	-- Bound to a setting whose default is false: this is the disabled rule the
	-- runtime suite uses to prove disabled rules are inert.
	PlanetsLib.assign_entity_replacement("nauvis", "transport-belt", "fast-transport-belt", DISABLED_SETTING)

	local rules = PlanetsLib.constants.on_entity_placed_on_planet_replacements["nauvis"]
	for _, pair in ipairs(assignments) do
		assert(rules[pair[1]] and rules[pair[1]].entity == pair[2], "runtime rule was not stored: " .. pair[1])
	end
	local disabled = rules["transport-belt"]
	assert(disabled, "the disabled rule was not stored")
	assert(
		disabled.enabled == expected_enabled(DISABLED_SETTING),
		"the disabled rule used the wrong setting (or ignored the global kill switch)"
	)
	assert(disabled.enabled == false, "the disabled rule must be disabled with the default settings")
end)

-- ENT-2a: single-planet variant metadata and merging.
record("ENT-2a", function()
	local original = data.raw.container["wooden-chest"]
	assert(original, "the wooden-chest prototype is missing")
	local original_inventory_size = original.inventory_size

	PlanetsLib.create_planet_entity_variant(
		"funit-ent-planet-a",
		original,
		{ inventory_size = 99 },
		SETTING
	)

	local variant = data.raw.container["wooden-chest-PlanetsLib-funit-ent-planet-a"]
	assert(variant, "the variant prototype was not created")
	assert(variant.name == "wooden-chest-PlanetsLib-funit-ent-planet-a", "the name suffix is wrong")
	assert(
		original.name == "wooden-chest" and original.inventory_size == original_inventory_size,
		"the source prototype was mutated"
	)
	assert(variant.inventory_size == 99, "new_properties were not merged")
	assert(variant.PlanetsLib_do_not_generate_variants == true, "the variant is not marked do_not_generate_variants")

	assert(
		variant.localised_name and variant.localised_name[1] == "entity-name.wooden-chest",
		"localised_name was not set"
	)
	assert(
		variant.localised_description and variant.localised_description[1] == "entity-description.wooden-chest",
		"localised_description was not set"
	)
	assert(variant.flags and contains(variant.flags, "not-in-made-in"), "the not-in-made-in flag is missing")
	assert(variant.flags and contains(variant.flags, "not-in-bonus-gui"), "the not-in-bonus-gui flag is missing")
	assert(variant.factoriopedia_alternative == "wooden-chest", "the Factoriopedia redirect is missing")
	assert(variant.hidden_in_factoriopedia == true, "the variant is not hidden from the Factoriopedia")

	assert(variant.placeable_by and #variant.placeable_by == 1, "placeable_by was not set")
	assert(
		variant.placeable_by[1].item == "wooden-chest" and variant.placeable_by[1].count == 1,
		"placeable_by used the wrong item"
	)

	local expected_order_suffix = "z" .. data.raw.planet["funit-ent-planet-a"].order
	assert(
		string.sub(variant.order, -#expected_order_suffix) == expected_order_suffix,
		"the order suffix is missing"
	)

	local corner = variant.icons and variant.icons[#variant.icons]
	assert(corner and corner.shift and corner.shift[1] == 10 and corner.shift[2] == -10,
		"the planet icon corner is missing")
	assert(corner.draw_background == true, "the planet icon corner should draw a background")
	assert(corner.icon == data.raw.planet["funit-ent-planet-a"].icon,
		"the planet icon corner uses the wrong icon")
	assert(
		corner.scale == 64 / (data.raw.planet["funit-ent-planet-a"].icon_size or 64) * 0.25,
		"the planet icon corner scale is wrong"
	)

	local rule = PlanetsLib.constants.on_entity_placed_on_planet_replacements["funit-ent-planet-a"]["wooden-chest"]
	assert(rule and rule.entity == variant.name, "the generated variant was not registered as a replacement")
end)

-- ENT-2b: multi-planet variants use the first planet in the name and register
-- the rule on every planet.
record("ENT-2b", function()
	local original = data.raw.wall["stone-wall"]
	assert(original, "the stone-wall prototype is missing")
	PlanetsLib.create_planet_entity_variant(
		{ "funit-ent-planet-a", "funit-ent-planet-b" },
		original,
		{ max_health = 1234 },
		SETTING
	)

	local variant = data.raw.wall["stone-wall-PlanetsLib-funit-ent-planet-a"]
	assert(variant, "the multi-planet variant was not created")
	assert(
		variant.name == "stone-wall-PlanetsLib-funit-ent-planet-a",
		"the variant should use the first planet in its name"
	)
	assert(variant.max_health == 1234, "new_properties were not merged for the multi-planet variant")
	assert(variant.order == original.order, "the multi-planet form should not append a single-planet order suffix")

	local rules = PlanetsLib.constants.on_entity_placed_on_planet_replacements
	assert(
		rules["funit-ent-planet-a"]["stone-wall"].entity == variant.name,
		"the first planet did not receive the rule"
	)
	assert(
		rules["funit-ent-planet-b"]["stone-wall"].entity == variant.name,
		"the second planet did not receive the rule"
	)
	assert(
		contains(PlanetsLib.constants.entity_variants_list["stone-wall"], variant.name),
		"the variant list was not updated"
	)
end)

-- ENT-2c: an invalid bound setting is rejected.
record("ENT-2c", function()
	local ok = pcall(
		PlanetsLib.create_planet_entity_variant,
		"funit-ent-planet-b",
		data.raw.wall["stone-wall"],
		{},
		"funit-ent-not-a-real-setting"
	)
	assert(not ok, "an invalid bound_setting should error")
end)

-- ENT-2d: item inference and an explicit item_name.
record("ENT-2d", function()
	local iron_chest = data.raw.container["iron-chest"]
	assert(iron_chest and data.raw.item["iron-chest"], "the iron-chest entity/item is missing")
	PlanetsLib.create_planet_entity_variant("funit-ent-planet-a", iron_chest, {}, SETTING)
	local inferred = data.raw.container["iron-chest-PlanetsLib-funit-ent-planet-a"]
	assert(
		inferred and inferred.placeable_by and inferred.placeable_by[1].item == "iron-chest",
		"item inference did not set placeable_by"
	)

	local turret = data.raw["ammo-turret"] and data.raw["ammo-turret"]["gun-turret"]
	assert(turret, "the gun-turret prototype is missing")
	PlanetsLib.create_planet_entity_variant("funit-ent-planet-a", turret, {}, SETTING, "wooden-chest")
	local explicit = data.raw["ammo-turret"]["gun-turret-PlanetsLib-funit-ent-planet-a"]
	assert(
		explicit and explicit.placeable_by and explicit.placeable_by[1].item == "wooden-chest",
		"an explicit item_name did not override placeable_by"
	)
end)

-- ENT-2e: variants used by the runtime suite.
record("ENT-2e", function()
	local variants = {
		{ "heat-pipe", data.raw["heat-pipe"] and data.raw["heat-pipe"]["heat-pipe"], "heat-pipe-PlanetsLib-nauvis", nil },
		{
			"storage-tank",
			data.raw["storage-tank"] and data.raw["storage-tank"]["storage-tank"],
			"storage-tank-PlanetsLib-nauvis",
			nil,
		},
		{
			"arithmetic-combinator",
			data.raw["arithmetic-combinator"] and data.raw["arithmetic-combinator"]["arithmetic-combinator"],
			"arithmetic-combinator-PlanetsLib-nauvis",
			nil,
		},
		{
			"spidertron",
			data.raw["spider-vehicle"] and data.raw["spider-vehicle"]["spidertron"],
			"spidertron-PlanetsLib-nauvis",
			"spidertron",
		},
		{
			"locomotive",
			data.raw["locomotive"] and data.raw["locomotive"]["locomotive"],
			"locomotive-PlanetsLib-nauvis",
			nil,
		},
		{
			"car",
			data.raw["car"] and data.raw["car"]["car"],
			"car-PlanetsLib-nauvis",
			"car",
		},
	}

	for _, info in ipairs(variants) do
		local entity = info[2]
		assert(entity, "the runtime variant source prototype is missing: " .. info[1])
		PlanetsLib.create_planet_entity_variant("nauvis", entity, {}, SETTING, info[4])
		assert(data.raw[entity.type][info[3]], "runtime variant was not created: " .. info[1])
		local rule = PlanetsLib.constants.on_entity_placed_on_planet_replacements["nauvis"][info[1]]
		assert(rule and rule.entity == info[3], "runtime variant rule was not stored: " .. info[1])
	end
end)

-- ENT-2f: create_planet_entity_variant must not create a variant of a
-- generated variant. This is the guard that stops the issue #136 loop: callers
-- iterate data.raw and visit the variants they just created, so without the
-- guard every visit creates another variant until the game runs out of RAM.
record("ENT-2f", function()
	local base = table.deepcopy(data.raw.container["wooden-chest"])
	base.name = "funit-ent-recursion-base"
	data:extend({ base })

	PlanetsLib.create_planet_entity_variant("funit-ent-planet-a", base, {}, SETTING)
	local first_name = "funit-ent-recursion-base-PlanetsLib-funit-ent-planet-a"
	local first = data.raw.container[first_name]
	assert(first, "the first-level variant was not created")
	assert(first.PlanetsLib_do_not_generate_variants == true,
		"the generated variant is not marked PlanetsLib_do_not_generate_variants")

	PlanetsLib.create_planet_entity_variant("funit-ent-planet-a", first, {}, SETTING)

	local nested_name = first_name .. "-PlanetsLib-funit-ent-planet-a"
	assert(data.raw.container[nested_name] == nil,
		"a variant of a generated variant was created (issue #136)")
	assert(PlanetsLib.constants.entity_variants_list[first_name] == nil,
		"the generated variant was recorded as a base entity")
	assert(
		PlanetsLib.constants.on_entity_placed_on_planet_replacements["funit-ent-planet-a"][first_name] == nil,
		"a replacement rule was registered for the generated variant"
	)
end)

-- ENT-2g: the generated name is also a recursion guard, so overriding
-- PlanetsLib_do_not_generate_variants through new_properties cannot re-enable
-- variant-of-variant generation.
record("ENT-2g", function()
	local base = table.deepcopy(data.raw.container["wooden-chest"])
	base.name = "funit-ent-recursion-override-base"
	data:extend({ base })

	PlanetsLib.create_planet_entity_variant(
		"funit-ent-planet-a",
		base,
		{ PlanetsLib_do_not_generate_variants = false },
		SETTING
	)
	local first_name = "funit-ent-recursion-override-base-PlanetsLib-funit-ent-planet-a"
	local first = data.raw.container[first_name]
	assert(first, "the first-level variant was not created")
	assert(first.PlanetsLib_do_not_generate_variants == false,
		"new_properties did not override PlanetsLib_do_not_generate_variants")

	PlanetsLib.create_planet_entity_variant("funit-ent-planet-a", first, {}, SETTING)

	assert(data.raw.container[first_name .. "-PlanetsLib-funit-ent-planet-a"] == nil,
		"the generated name did not stop variant-of-variant generation")
end)

-- ENT-3: rocket lift/part multiplier variant fields.
record("ENT-3", function()
	local silo = data.raw["rocket-silo"]["rocket-silo"]
	assert(silo, "the vanilla rocket silo prototype is missing")
	local base_parts = silo.rocket_parts_required or 20
	local base_lift = silo.lift_weight or 1234567
	-- Pin the value so the runtime comparison is not affected by an engine
	-- default that differs from the data-stage fallback.
	silo.lift_weight = base_lift
	local properties = {
		rocket_parts_required = base_parts * 3,
		lift_weight = base_lift * 2,
	}
	if silo.rocket_parts_storage_cap then
		properties.rocket_parts_storage_cap = silo.rocket_parts_storage_cap * 3
	end

	PlanetsLib.create_planet_entity_variant("funit-ent-planet-b", silo, properties, SETTING)
	local variant = data.raw["rocket-silo"]["rocket-silo-PlanetsLib-funit-ent-planet-b"]
	assert(variant, "the rocket silo variant was not created")
	assert(variant.rocket_parts_required == base_parts * 3, "rocket_parts_required was not multiplied")
	assert(variant.lift_weight == base_lift * 2, "lift_weight was not multiplied")
	if silo.rocket_parts_storage_cap then
		assert(
			variant.rocket_parts_storage_cap == silo.rocket_parts_storage_cap * 3,
			"rocket_parts_storage_cap was not multiplied"
		)
	end
	assert(variant.PlanetsLib_do_not_generate_variants == true,
		"the rocket silo variant is not marked do_not_generate_variants")
end)

-- ENT-4: special properties consumed by PlanetsLib's data-final-fixes rocket
-- override (only when Space Age is active; asserted conditionally at runtime).
record("ENT-4", function()
	local properties = PlanetsLib.set_special_properties("funit-ent-rocket", {
		rocket_lift_multiplier = 2,
		rocket_part_multiplier = 3,
	})
	assert(properties.rocket_lift_multiplier == 2, "rocket_lift_multiplier was not stored")
	assert(properties.rocket_part_multiplier == 3, "rocket_part_multiplier was not stored")
	assert(rocket_planet and rocket_planet.surface_properties, "the rocket test planet has no surface_properties")
end)

return true
