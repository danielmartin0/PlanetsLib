local delayed_functions = {}

---use this to execute a script after a delay
---example:
---Public.register_delayed_function('my_delayed_func', function(param1, param2, param3) ... end)
---Public.execute_later('my_delayed_func', 60, param1, param2, param3)
---The above code will execute my_delayed_func after waiting for 60 ticks
---@param function_key string
---@param ticks integer
---@param ... any
function PlanetsLib.execute_later(function_key, ticks, ...)
	local marked_for_death_render_object = rendering.draw_line {
		color = {0, 0, 0, 0},
		width = 0,
		filled = false,
		from = {0, 0},
		to = {0, 0},
		create_build_effect_smoke = false,
		surface = "nauvis",
		time_to_live = ticks
	}
	storage._delayed_functions = storage._delayed_functions or {}
	storage._delayed_functions[script.register_on_object_destroyed(marked_for_death_render_object)] = {function_key, {...}}
    return marked_for_death_render_object
end

script.on_event(defines.events.on_object_destroyed, function(event)
	if not storage._delayed_functions then return end
	local registration_number = event.registration_number
	local data = storage._delayed_functions[registration_number]
	if not data then return end
	storage._delayed_functions[registration_number] = nil

	local f = delayed_functions[data[1]]
	if not f then error("No function found for key: " .. function_key) end
	f(table.unpack(data[2]))
end)

function PlanetsLib.register_delayed_function(key, func)
	delayed_functions[key] = func
end


local target_daytime = 0.5 -- "Midnight" on this planet
local function iterate_day(surface)
        if not surface.valid then return end
        script.raise_event("PlanetsLib-on-planet-day-begins",{surface=surface})
        game.print("New day on " .. surface.name)
        game.print("Current daytime is" .. surface.daytime)
        local daytime = surface.daytime
        local daytime_adjust = 0
        if not surface.freeze_daytime then
            daytime_adjust = math.ceil((daytime-target_daytime) * surface.ticks_per_day - 0.5) --When this function is called when daytime not ~0, an adjustment is applied to make the next call more accurate.
        end
        game.print("adjusting day length by "..daytime_adjust)
        storage.surface_info[surface.name].tracker =  PlanetsLib.execute_later("iterate_day", surface.ticks_per_day-daytime_adjust, surface)
        storage.surface_info[surface.name].day_count = (storage.surface_info[surface.name].day_count or 0) + 1 
end

PlanetsLib.register_delayed_function("iterate_day", iterate_day)

function PlanetsLib.setup_surface_daynight_cycle(surface)
    storage.surface_info[surface.name]=storage.surface_info[surface.name] or {}
    local daytime = surface.daytime
    local daytime_adjust = 0
    if not surface.freeze_daytime then
        daytime_adjust = math.ceil((daytime-target_daytime) * surface.ticks_per_day - 0.5) --When this function is called when daytime not ~0, an adjustment is applied to make the next call more accurate.
    end
    storage.surface_info[surface.name].tracker =  PlanetsLib.execute_later("iterate_day", surface.ticks_per_day-daytime_adjust, surface)

end

script.on_event(
    defines.events.on_surface_created, function(event)
        game.print("Surface created")
        local surface = game.surfaces[event.surface_index]
        if PlanetsLib.constants.surface_fire_daynight_event[surface.name] then
            PlanetsLib.setup_surface_daynight_cycle(surface)
        end
        
    end
)

