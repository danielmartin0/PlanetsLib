---
sidebar_label: Event Handler
---

# Event Handler

Planetslib provides an alternative to the event handler library found in factorio's core mod, the core of the code was taken from there then extended. It does work as a drop in replacement for that.

##### Filtering:

The `add_filter(event,filter)` method can add a filter to every registered event handler. The filters are added to all of your handlers, if you use a filter in one spot then use the same event elsewhere then you need to add the filters for that event as well. This is not done on the lua side, this interacts with the engine's [event filters](https://lua-api.factorio.com/latest/concepts/EntityPrototypeFilter.html). You still need to do a check in the function if you filter for multiple entities in your mod, and they don't have the same behavior.

```lua
    local handler = require("__PlanetsLib__.lib.event-handler.event-handler")

-- all built events will get this filter
handler.add_filter(defines.events.on_built_entity,{
  filter="name",
  name="orbital-cannon"
})
handler.add_lib(require("script.orbital-cannon"))
```

##### Composite events:
Some frequently used event combinations can be declared together. You have to write the handler in a way that supports [all included events](https://github.com/danielmartin0/PlanetsLib/blob/main/lib/lib.lua).
   * on_built: Every event that could fire when a new entity was built.
   * on_removed: Every event when the entity was mined or destroyed.

```lua
    local handler = require("__PlanetsLib__.lib.event-handler.event-handler")
    -- include the built in "on_built" and "on_removed" composite events
    handler.add_composite_events(require("__PlanetsLib__.lib.event-handler.composite-events"))


    -- using the name of a composite event is also valid for a filter, it will apply to every included event.
    handler.add_filter("on_built",{
        filter="name",
        name="orbital-cannon"
    })
   --in your handler code
   local lib = {
        composite_events = {
            on_built= function(event) end,
            on_removed= function(event) end
        }
    }
    return lib
```
##### Remote interface:

The `add_to_remote_interface` method lets you append to a single remote interface that is registered with your mod's name, instead of either collectiong all of you api functions from every relevant file, or registering multiple remote interfaces. 

```lua
local handler = require("__PlanetsLib__.lib.event-handler.event-handler")

local function api_function() end

local lib ={
    add_to_remote_interface = function(interface)
        interface["api_function"] = api_function
    end
}

handler.add_lib(lib)

```

Can be called as:
```lua

remote.call("your mod", "api_function")

```

