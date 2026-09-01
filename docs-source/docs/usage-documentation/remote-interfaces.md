---
sidebar_label: Remote Interfaces
---

# Remote Interfaces


## Storage extraction and transfer

If a mod author has abandoned their mod, and another developer decides to fork their mod without the original author's involvement, the following remote interfaces can be used to transfer storage from saves containing the old mod to the new fork. These interfaces are intended to be used by players with /c to manually transfer storage from a mod to PlanetsLib's storage, then load the fork and transfer the cached storage from PlanetsLib's storage to the fork.

* `remote.call("PlanetsLib_transfer_storage","save",mod_name,storage_data)`: Saves the table `storage_data` to PlanetsLib's storage under the key `mod_name`.
* `remote.call("PlanetsLib_transfer_storage","get",mod_name)`: Returns the storage table stored in PlanetsLib's storage under the key `mod_name`.
* `remote.call("PlanetsLib_transfer_storage","purge",mod_name)`: Deletes the storage table stored in PlanetsLib's storage under the key `mod_name`.

These interfaces are used by the player. In your fork, add a variation of these instructions to explain to players how to transfer their data to the new mod.

1. Load save with the old mod loaded. Enter command `/c __old-mod__ remote.call("PlanetsLib_transfer_storage","save","old-mod",storage)`. Save the game.
2. Load save again with the old mod replaced with the new fork. Enter command `/c __new-mod__ storage = remote.call("PlanetsLib_transfer_storage","get","old-mod")`.
3. Delete cached storage with `/c __new-mod__ remote.call("PlanetsLib_transfer_storage","purge","old-mod")`.

If the structure of your fork's storage differs from the original mod, you may need to add an additional function for the player to run to correct the storage, as might be run in a migration.