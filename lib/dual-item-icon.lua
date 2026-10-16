local Public = {}

--== Composite "dual item" icon helpers ==--
-- Build an `icons` array (see [[IconData]]) out of the icons of up to three existing prototypes,
-- producing a composite icon similar to the way vanilla recipes display their ingredients.
-- Ported from "Muluna, Moon of Nauvis" (planet-muluna/lib/dual-item-icon.lua).

local PLACEHOLDER_ICON = "__core__/graphics/filter-blacklist.png"
local PLACEHOLDER_ICON_SIZE = 101

-- Returns the prototype type used to look up `name`, in the same precedence order as the original
-- planet-muluna implementation (later checks override earlier ones):
-- item (default) < planet < fluid < capsule < tool < surface.
local function detect_type(name)
	local prototype_type = "item"
	if not name then
		return prototype_type
	end
	for _, candidate in ipairs({ "planet", "fluid", "capsule", "tool", "surface" }) do
		if data.raw[candidate] and data.raw[candidate][name] then
			prototype_type = candidate
		end
	end
	return prototype_type
end

-- Returns the detected type and prototype of `name`, or ("item", nil) when nothing matches.
local function get_prototype(name)
	local prototype_type = detect_type(name)
	return prototype_type, data.raw[prototype_type] and data.raw[prototype_type][name]
end

-- Builds a single composite-icon entry from a prototype's icon fields.
-- `base_scale` is the entry's scale before the singular `icon` form's icon-size correction.
-- `shift` is applied to the singular `icon` form and to the placeholder fallback.
-- `plural_shift` is applied to the plural `icons` form; pass `false` to omit the shift (as the
-- original reversed helper does), or nil to reuse `shift`.
-- `copy_tint` carries over `icons[1].tint` for the plural form.
local function build_icon_entry(prototype, prototype_type, name, base_scale, shift, plural_shift, copy_tint)
	if plural_shift == nil then
		plural_shift = shift
	end

	if prototype and prototype.icon then
		local entry = {
			icon = prototype.icon,
			icon_size = prototype.icon_size,
			scale = base_scale,
			draw_background = true,
		}
		if prototype.icon_size then
			entry.scale = entry.scale * 64 / prototype.icon_size
		end
		if shift then
			entry.shift = { shift[1], shift[2] }
		end
		return entry
	elseif prototype and prototype.icons and prototype.icons[1] then
		local entry = {
			icon = prototype.icons[1].icon,
			icon_size = prototype.icons[1].icon_size,
			scale = base_scale,
			draw_background = true,
		}
		if plural_shift then
			entry.shift = { plural_shift[1], plural_shift[2] }
		end
		if copy_tint then
			entry.tint = prototype.icons[1].tint
		end
		return entry
	else
		log(prototype_type .. ' "' .. tostring(name) .. '" icon not found. Using a placeholder in composite icon instead.')
		local entry = {
			icon = PLACEHOLDER_ICON,
			icon_size = PLACEHOLDER_ICON_SIZE,
			scale = base_scale,
			draw_background = true,
		}
		if shift then
			entry.shift = { shift[1], shift[2] }
		end
		return entry
	end
end

--- Builds a composite icon from the icons of up to three prototypes.
--- Each argument is a prototype name (string). The prototype type is detected automatically;
--- see the PlanetsLib documentation for the type precedence.
--- The first icon is drawn at full size, with the second and third icons layered over it.
--- @param item_1 string Name of the primary (bottom) prototype.
--- @param item_2 string Name of the secondary prototype.
--- @param item_3 string|nil Optional name of the tertiary prototype.
--- @return table IconData array suitable for a prototype's `icons` field.
function Public.dual_icon(item_1, item_2, item_3)
	local type_1, proto_1 = get_prototype(item_1)
	local type_2, proto_2 = get_prototype(item_2)

	local primary = build_icon_entry(proto_1, type_1, item_1, 0.35, nil, nil, true)
	local secondary = build_icon_entry(proto_2, type_2, item_2, 0.30, { 10, -10 }, nil, true)

	local icons
	local type_3, proto_3 = get_prototype(item_3)
	if proto_3 then
		-- With three icons, the tertiary icon is placed first (top-left) and the original two
		-- icons shift right/down.
		local tertiary = build_icon_entry(proto_3, type_3, item_3, 0.30, { 0, -10 }, nil, true)
		icons = { tertiary, primary, secondary }
	else
		icons = { primary, secondary }
	end

	-- Nudge every entry up and to the left so the composition is centred.
	for _, entry in pairs(icons) do
		if not entry.shift then
			entry.shift = { 0, 0 }
		end
		entry.shift[1] = entry.shift[1] - 5
		entry.shift[2] = entry.shift[2] + 5
	end

	return icons
end

--- Builds a composite icon from the icons of two prototypes, using a layout mirrored relative
--- to `PlanetsLib.dual_icon`.
--- @param item_1 string Name of the primary prototype.
--- @param item_2 string Name of the secondary prototype.
--- @return table IconData array suitable for a prototype's `icons` field.
function Public.dual_icon_reversed(item_1, item_2)
	local type_1, proto_1 = get_prototype(item_1)
	local type_2, proto_2 = get_prototype(item_2)

	return {
		build_icon_entry(proto_1, type_1, item_1, 0.35, { 10, 0 }, false, false),
		build_icon_entry(proto_2, type_2, item_2, 0.30, { 0, -10 }, { 10, -10 }, false),
	}
end

return Public
