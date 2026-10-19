-- Data-stage fixture: science-lab / science-technology overrides that
-- PlanetsLib's data-final-fixes processes (prototypes/override-final/science.lua
-- and prototypes/override-final/lab-updates.lua).
--
-- Everything is created here, in the data stage, so PlanetsLib's final-fixes can
-- act on it. The post-processing assertions live in misc_science_lab_final.lua
-- (data-final-fixes), which runs after PlanetsLib finished. Both namespaces are
-- asserted by tests/suites/misc_science_lab.lua.
local results = require("lib.results")

local function find_technology_template()
	for _, tech in pairs(data.raw.technology) do
		if tech.unit and tech.unit.ingredients then
			return tech
		end
	end
	return nil
end

-- Clone an existing technology (so the prototype stays valid) and clear the
-- fields the test does not care about.
local function make_technology(name, mutate)
	local template = find_technology_template()
	assert(template, "no technology prototype available to clone")
	local tech = table.deepcopy(template)
	tech.name = name
	tech.effects = {}
	tech.prerequisites = nil
	tech.localised_name = nil
	tech.localised_description = nil
	if mutate then
		mutate(tech)
	end
	data:extend({ tech })
	return data.raw.technology[name]
end

local function make_science_pack(name)
	-- Science packs are ordinary item prototypes in Factorio 2.1 (the legacy
	-- `tool` prototype type was folded into `item`).
	local template = data.raw.item and data.raw.item["automation-science-pack"]
	assert(template, "no science pack (item) prototype available to clone")
	local pack = table.deepcopy(template)
	pack.name = name
	pack.localised_name = nil
	pack.localised_description = nil
	data:extend({ pack })
	return data.raw.item[name]
end

local function make_lab(name, mutate)
	local template = data.raw.lab["lab"]
	assert(template, "vanilla lab prototype is missing")
	local lab = table.deepcopy(template)
	lab.name = name
	lab.localised_name = nil
	if mutate then
		mutate(lab)
	end
	data:extend({ lab })
	return data.raw.lab[name]
end

local function reversed_inputs(inputs)
	local reversed = {}
	for i = #inputs, 1, -1 do
		reversed[#reversed + 1] = inputs[i]
	end
	return reversed
end

-- MISC-2: hidden prerequisite unlinking, the legacy/modern lab-pack fields and
-- the legacy/modern lab sort fields.
local ok, err = pcall(function()
	make_technology("funit-lab-hidden-prereq", function(tech)
		tech.hidden = true
	end)
	make_technology("funit-lab-hidden-successor", function(tech)
		tech.prerequisites = { "funit-lab-hidden-prereq" }
	end)

	-- Legacy technology field (unlock-recipe packs are not added as ingredients).
	make_technology("funit-lab-legacy-packs", function(tech)
		tech.unit.ingredients = { { "automation-science-pack", 1 } }
		tech.effects = { { type = "unlock-recipe", recipe = "logistic-science-pack" } }
		tech.ensure_all_packs_from_vanilla_lab = true -- legacy field
	end)
	-- Modern technology field.
	make_technology("funit-lab-modern-packs", function(tech)
		tech.unit.ingredients = { { "automation-science-pack", 1 } }
		tech.effects = { { type = "unlock-recipe", recipe = "utility-science-pack" } }
		tech.planetslib_ensure_all_packs_from_vanilla_lab = true
	end)

	-- Legacy lab sort field: inputs deliberately in reverse order.
	make_lab("funit-lab-legacy-sort", function(lab)
		lab.inputs = reversed_inputs(lab.inputs)
		lab.sort_sciences = true -- legacy field
	end)
	-- Modern lab sort field.
	make_lab("funit-lab-modern-sort", function(lab)
		lab.inputs = reversed_inputs(lab.inputs)
		lab.planetslib_sort_sciences = true
	end)
	-- include_all_lab_science: start from a single pack and let PlanetsLib add
	-- all of the vanilla lab's packs.
	make_lab("funit-lab-include-all", function(lab)
		lab.inputs = { "automation-science-pack" }
		lab.include_all_lab_science = true
	end)

	assert(data.raw.technology["funit-lab-hidden-prereq"], "the hidden prerequisite technology was not created")
	assert(data.raw.technology["funit-lab-hidden-successor"], "the successor technology was not created")
	assert(data.raw.technology["funit-lab-legacy-packs"], "the legacy-pack technology was not created")
	assert(data.raw.technology["funit-lab-modern-packs"], "the modern-pack technology was not created")
	assert(data.raw.lab["funit-lab-legacy-sort"], "the legacy-sort lab was not created")
	assert(data.raw.lab["funit-lab-modern-sort"], "the modern-sort lab was not created")
	assert(data.raw.lab["funit-lab-include-all"], "the include-all lab was not created")
end)
results.record("misc_science_lab", "MISC-2-setup", ok, err)

-- MISC-3: a lab with more than 12 science packs, so lab-updates.lua adds an
-- icons_positioning entry. The custom packs are cloned tools, so the lab stays
-- a valid prototype without Space Age.
local many_ok, many_err = pcall(function()
	local inputs = {}
	for i = 1, 13 do
		local name = "funit-lab-science-pack-" .. i
		make_science_pack(name)
		inputs[#inputs + 1] = name
	end
	assert(#inputs == 13, "the many-packs lab needs more than 12 science packs")

	make_lab("funit-lab-many-packs", function(lab)
		lab.inputs = inputs
		-- lab-updates.lua reads lab.selection_box unconditionally, so make sure
		-- the cloned lab has one even if the vanilla lab omitted it.
		if not lab.selection_box then
			lab.selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } }
		end
	end)

	local lab = data.raw.lab["funit-lab-many-packs"]
	assert(lab, "the many-packs lab was not created")
	assert(#lab.inputs == 13, "the many-packs lab lost science packs")
end)
results.record("misc_science_lab", "MISC-3-setup", many_ok, many_err)

return true
