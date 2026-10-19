-- Data-stage fixture: prototype-type detection and composite icons.
--
-- detect_type/get_prototype read data.raw, and dual_icon/melting_icon look up
-- real prototypes, so these can only run in the data stage.
local results = require("lib.results")

local icon_entry = require("__PlanetsLib__.lib.icon-entry")

-- Same name in several prototype namespaces, to exercise the documented
-- precedence (item < planet < fluid < capsule < tool < surface). Item subtypes
-- (item/capsule/tool) share one name registry, so only item+fluid can share a
-- name here; capsule/tool are checked against their real prototypes below.
local COLLISION = "funit-icon-collision"

local function clone_into(prototype_type, source_name)
	local prototype = table.deepcopy(data.raw[prototype_type][source_name])
	prototype.name = COLLISION
	data:extend({ prototype })
end

local ok, err = pcall(function()
	clone_into("item", "iron-plate")
	clone_into("fluid", "water")

	assert(icon_entry.detect_type("iron-plate") == "item", "plain items must be detected as items")
	if data.raw.tool and data.raw.tool["automation-science-pack"] then
		assert(icon_entry.detect_type("automation-science-pack") == "tool", "science packs must be detected as tools")
	end
	assert(icon_entry.detect_type("water") == "fluid", "fluids must be detected as fluids")
	assert(icon_entry.detect_type("nauvis") == "planet", "planets must be detected as planets")
	if data.raw.capsule and data.raw.capsule["grenade"] then
		assert(icon_entry.detect_type("grenade") == "capsule", "capsules must be detected as capsules")
	end

	-- Documented precedence: the highest-priority matching type wins, not `item`.
	assert(
		icon_entry.detect_type(COLLISION) == "fluid",
		"type precedence is wrong for a name shared by several prototype types"
	)
	assert(icon_entry.detect_type("funit-does-not-exist") == "item", "unknown names fall back to item")
end)
results.record("icons", "RCP-ICONS-1", ok, err)

local get_ok, get_err = pcall(function()
	local prototype_type, prototype = icon_entry.get_prototype("iron-plate")
	assert(prototype_type == "item", "get_prototype returned the wrong type")
	assert(prototype and prototype.name == "iron-plate", "get_prototype did not return the prototype")

	local missing_type, missing = icon_entry.get_prototype("funit-does-not-exist")
	assert(missing_type == "item", "missing prototypes should fall back to type 'item'")
	assert(missing == nil, "missing prototypes should return nil")
end)
results.record("icons", "RCP-ICONS-2", get_ok, get_err)

local dual_ok, dual_err = pcall(function()
	local icons = PlanetsLib.dual_icon("iron-plate", "copper-plate", "steel-plate")
	assert(#icons == 3, "dual_icon with a tertiary item should return 3 entries")
	assert(icons[2].scale == 0.35, "primary icon scale is wrong")
	assert(icons[3].scale == 0.30, "secondary icon scale is wrong")
	assert(icons[1].scale == 0.30, "tertiary icon scale is wrong")
	-- The centring nudge is applied to every entry.
	assert(icons[2].shift[1] == -5 and icons[2].shift[2] == 5, "primary centring shift is wrong")
	assert(icons[3].shift[1] == 5 and icons[3].shift[2] == -5, "secondary centring shift is wrong")
	assert(icons[1].shift[1] == -5 and icons[1].shift[2] == -5, "tertiary centring shift is wrong")

	local two = PlanetsLib.dual_icon("iron-plate", "copper-plate")
	assert(#two == 2, "dual_icon without a tertiary item should return 2 entries")
end)
results.record("icons", "RCP-ICONS-3", dual_ok, dual_err)

local reversed_ok, reversed_err = pcall(function()
	local icons = PlanetsLib.dual_icon_reversed("iron-plate", "copper-plate")
	assert(#icons == 2, "dual_icon_reversed should return 2 entries")
	assert(icons[1].scale == 0.35 and icons[2].scale == 0.30, "dual_icon_reversed scales are wrong")
	assert(icons[1].shift[1] == 10 and icons[1].shift[2] == 0, "dual_icon_reversed primary shift is wrong")
	-- Vanilla items use the singular `icon` form, so `shift` (not plural_shift) applies.
	assert(icons[2].shift[1] == 0 and icons[2].shift[2] == -10, "dual_icon_reversed secondary shift is wrong")
end)
results.record("icons", "RCP-ICONS-4", reversed_ok, reversed_err)

local melting_ok, melting_err = pcall(function()
	local icons = PlanetsLib.melting_icon("iron-plate", "iron-ore", "copper-plate")
	assert(#icons == 3, "melting_icon should return 3 entries")
	assert(icons[1].scale == 0.25, "catalyst scale is wrong")
	assert(icons[2].scale == 0.25, "ore scale is wrong")
	assert(icons[3].scale == 0.45, "metal scale is wrong")
	assert(icons[3].shift[1] == -2 and icons[3].shift[2] == 3, "metal shift is wrong")

	-- The catalyst defaults to calcite when available.
	if data.raw.item and data.raw.item["calcite"] then
		local defaulted = PlanetsLib.melting_icon("iron-plate", "iron-ore")
		assert(#defaulted == 3, "melting_icon default catalyst failed")
	end
end)
results.record("icons", "RCP-ICONS-5", melting_ok, melting_err)

return true
