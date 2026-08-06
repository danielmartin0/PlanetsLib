local library = require("lib")

local libraries = {}
local filters = {}

local setup_ran = false

local register_remote_interfaces = function()
    --Sometimes, in special cases, on_init and on_load can be run at the same time. Only register events once in this case.
    if setup_ran then return end
    setup_ran = true

    for lib_name, lib in pairs(libraries) do
        if lib.add_remote_interface then
            lib.add_remote_interface()
        end

        if lib.add_commands then
            lib.add_commands()
        end
    end
end

local function add_lib(lib)
    for k, current in ipairs(libraries) do
        if current == lib then
            error("Trying to register same lib twice")
        end
    end
    table.insert(libraries, lib)
end

local event_name = function(eventid)
    for name, id in pairs(defines.events) do
        if id == eventid then
            return name
        end
    end
    return tostring(eventid)
end

local check_handler = function(id, handler, oldhandler)
    if oldhandler then
        local oldinfo = debug.getinfo(oldhandler, "S")
        local newinfo = debug.getinfo(handler, "S")
        log(string.format(
            "duplicate handlers within module for event %s: first defined at %s:%d, replaced by redefinition at %s:%d",
            event_name(id), oldinfo.short_src, oldinfo.linedefined, newinfo.short_src, newinfo.linedefined))
    end
end

local register_events = function()
    local all_events = {}
    local on_nth_tick = {}

    local composite_libraries = {}
    -- handle composite event handlers.
    for lib_name, lib in pairs(libraries) do
        local composite_lib = {
            events = {}
        }
        local do_add = false

        if not lib.composite_events then
            goto continue
        end

        local composite_events = lib.composite_events

        if composite_events.on_built then
            for index, value in ipairs(library.build_events) do
                composite_lib.events[value] = composite_events.on_built
            end
            do_add = true
        end

        if composite_events.on_removed then
            for index, value in ipairs(library.destroy_events) do
                composite_lib.events[value] = composite_events.on_removed
            end
            do_add = true
        end
        if do_add then
            table.insert(composite_libraries, composite_lib)
        end
        ::continue::
    end

    for index, value in ipairs(composite_libraries) do
        table.insert(libraries, value)
    end

    for lib_name, lib in ipairs(libraries) do
        if lib.events then
            for k, handler in pairs(lib.events) do
                -- if different modules refer to the same event different ways
                -- (string, defines, CustomEvent/CustomInput protos), unify them to ids for registration...
                local id = script.get_event_id(k)
                all_events[id] = all_events[id] or {}

                -- if a *single* module refers to the same event different ways, error...
                local oldhandler = all_events[id][lib_name]
                check_handler(id, handler, oldhandler)
                all_events[id][lib_name] = handler
            end
        end

        if lib.on_nth_tick then
            for n, handler in pairs(lib.on_nth_tick) do
                on_nth_tick[n] = on_nth_tick[n] or {}
                on_nth_tick[n][lib_name] = handler
            end
        end
    end

    for event, handlers in pairs(all_events) do
        local action = function(event)
            for k, handler in pairs(handlers) do
                handler(event)
            end
        end
        local name = event_name(event)
        if filters[name] then
            script.on_event(event, action, filters[name])
        else
            script.on_event(event, action)
        end
    end

    for n, handlers in pairs(on_nth_tick) do
        local action = function(event)
            for k, handler in pairs(handlers) do
                handler(event)
            end
        end
        script.on_nth_tick(n, action)
    end
end

script.on_init(function()
    register_remote_interfaces()
    register_events()
    for k, lib in pairs(libraries) do
        if lib.on_init then
            lib.on_init()
        end
    end
end)

script.on_load(function()
    register_remote_interfaces()
    register_events()
    for k, lib in pairs(libraries) do
        if lib.on_load then
            lib.on_load()
        end
    end
end)

script.on_configuration_changed(function(data)
    for k, lib in pairs(libraries) do
        if lib.on_configuration_changed then
            lib.on_configuration_changed(data)
        end
    end
end)

local handler = {}

local function register_filter(event, filter)
    local name = event_name(event)
    local event_filters = filters[name]
    if not event_filters then
        event_filters = {}
        filters[name] = event_filters
    end

    -- prevent duplicate filters from being added.
    -- don't need to crash the process
    for index, value in ipairs(event_filters) do
        if value == filter then
            return
        end
    end
    table.insert(event_filters, filter)
end

handler.add_filter = function(event, filter)
    if event == "on_built" then
        for index, value in ipairs(library.build_events) do
            register_filter(value, filter)
        end
    else
        if event == "on_removed" then
            for index, value in ipairs(library.destroy_events) do
                register_filter(value, filter)
            end
        else
            register_filter(event.filter)
        end
    end
end

handler.add_lib = function(lib)
    add_lib(lib)
end

handler.add_libraries = function(libs)
    for k, lib in pairs(libs) do
        add_lib(lib)
    end
end

return handler
