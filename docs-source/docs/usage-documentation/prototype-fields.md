---
sidebar_label: Prototype Fields
---

# Prototype fields


## Spoilage metadata

Planetslib provides infrastructure to have additional information on items that spoil, beyond a timer. This lets modders decide what can be done to that item, so a freezer won't preserve a hot plate of metal.

It is done through the `planetslib_spoilage_meta` field on item prototypes.

> This is intended to be a common template for modders so you know where to look for the data you need, instead of having to implement several different compatibility apis for different mods.

### Fields

##### type
A string that identifies the process that is happening here. If you know that your process is the same as another mod, or the base game use the same string. 

For example, this lets you make sure that your freezer won't work on nuclear materials, or hot metals.

> The types registered for space age items are `rotting` and `hatching`. 

##### integrity

How "fragile" this item is, other mods can use it as a multiplier for recipes and othe processes that interact with spoilage timers.

> An item with very low fragility should not keep well, even if frozen. High integrity items should last for a long time under those conditions.

### Example
```lua
 item.planetslib_spoilage_meta = {
        type = "rotting",
        integrity = 1.0
    }
```

### Runtime

The data for every item is also available in the `Planetslib-spoilage-data` [[ModData]] prototype. (`prototypes['mod-data']['Planetslib-spoilage-data']`). It is indexed by the name of the item, and contains the full value of the `planetslib_spoilage_meta` field.

![spoilage data visible with the global variable viewer](/docs-images/spoilage-data-gvv.png)

### Supported prototypes

- [[ItemPrototype]]
- [[AmmoItemPrototype]]
- [[CapsulePrototype]]
- [[ToolPrototype]]
- [[GunPrototype]]
- [[ItemWithEntityDataPrototype]]
- [[ModulePrototype]]
- [[RailPlannerPrototype]]
- [[SpacePlatformStarterPackPrototype]]
- [[ArmorPrototype]]
- [[RepairToolPrototype]]
