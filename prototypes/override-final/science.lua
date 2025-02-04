local lib = require("lib.lib")
local tech = require("lib.technology")

local function science_sorted_by_order_or_name(table)
	table = util.table.deepcopy(table)

	lib.sort(table, function(left, right)
		if not (data.raw["tool"] and data.raw["tool"][left] and data.raw["tool"][right]) then
			return true
		end

		local left_order = data.raw["tool"][left].order
		local right_order = data.raw["tool"][right].order

		if left_order == nil then
			left_order = data.raw["tool"][left].name
		end
		if right_order == nil then
			right_order = data.raw["tool"][right].name
		end

		return left_order < right_order
	end)
	return table
end

if data.raw["lab"]["lab"] then
	local vanilla_lab = data.raw["lab"]["lab"]

	--== Ordering science packs in labs ==--

	local vanilla_lab_inputs = science_sorted_by_order_or_name(vanilla_lab.inputs)
	vanilla_lab.inputs = vanilla_lab_inputs

	if data.raw["lab"]["biolab"] then
		data.raw["lab"]["biolab"].include_all_lab_science = true
	end

	for _, new_lab in pairs(data.raw["lab"]) do
		if new_lab["include_all_lab_science"] == true then
			for _, input in pairs(vanilla_lab_inputs) do
				if not lib.contains(new_lab.inputs, input) then
					table.insert(new_lab.inputs, input)
				end
			end
			new_lab.inputs = science_sorted_by_order_or_name(new_lab.inputs)
		elseif new_lab["sort_sciences"] == true then
			local local_inputs = new_lab.inputs
			new_lab.inputs = science_sorted_by_order_or_name(local_inputs)
		end
	end

	--== Setting science packs in endgame technologies

	if data.raw["technology"]["promethium-science-pack"] then
		data.raw["technology"]["promethium-science-pack"]["give_all_packs_in_vanilla_lab"] = true
	end

	for _, value in pairs(data.raw["technology"]) do
		if value["give_all_packs_in_vanilla_lab"] == true then
			tech.set_science_packs_from_lab(value, vanilla_lab)
		end
	end
end
