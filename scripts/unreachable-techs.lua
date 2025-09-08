local Public = {}

local WARN_COLOR = { r = 255, g = 90, b = 54 }

function Public.warn_unreachable_techs()
	if #prototypes.mod_data["Planetslib"].data.unlinked_prerequisites > 0 then
		return Public.warn_unlinked_prerequisites()
	end

	local hidden_prereq_successors = {}

	for _, tech in pairs(prototypes.technology) do
		if not tech.hidden then
			for _, prereq in pairs(tech.prerequisites) do
				if prereq.hidden then
					if not hidden_prereq_successors[prereq.name] then
						hidden_prereq_successors[prereq.name] = {}
					end
					table.insert(hidden_prereq_successors[prereq.name], tech.name)
				end
			end
		end
	end

	local warnings = {}
	for prereq_name, successors in pairs(hidden_prereq_successors) do
		local tech_links = {}
		for _, tech_name in pairs(successors) do
			table.insert(tech_links, "[technology=" .. tech_name .. "]")
		end
		local successor_list = table.concat(tech_links, ", ")
		table.insert(warnings, successor_list .. " due to hidden prerequisite '" .. prereq_name .. "'")
	end

	if #warnings > 0 then
		local all_warnings = table.concat(warnings, ", ")
		game.print({
			"",
			{ "planetslib.planetslib-print" },
			{ "planetslib.warn-unreachable-techs", all_warnings },
		}, { color = WARN_COLOR })
	end
end

function Public.warn_unlinked_prerequisites()
	local prerequisites = {}
	for _, prerequisite in pairs(prototypes.mod_data["Planetslib"].data.unlinked_prerequisites) do
		table.insert(prerequisites, prerequisite)
	end
	local all_warnings = table.concat(prerequisites, ", ")

	game.print({
		"",
		{ "planetslib.planetslib-print" },
		{ "planetslib.notify-unlinked-prerequisites", all_warnings },
	}, { color = WARN_COLOR })
end

return Public
