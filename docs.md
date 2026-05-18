# VORP Inventory Enhanced Documentation

This document covers installation notes, export usage, integration patterns, and the practical API surface exposed by this resource.

## Installation Summary

### Required startup order

```cfg
ensure oxmysql
ensure vorp_core
ensure vorp_progressbar
ensure vorp_inventory
```

### Notes

- `vorp_progressbar` is only needed if you use the repair flow
- The UI is already built in `ui/`
- The source UI lives in `web/`
- Slot and durability columns are auto-migrated on startup
- Craft stations can now be configured as plain points or NPC ped stations

## Resource Structure

- `client/exports.lua`
  Main documented client export wrappers
- `client/services/NUIService.lua`
  Inventory open/close/use behavior and additional client exports
- `server/services/inventoryApiService.lua`
  Main server export surface
- `server/vorpInventoryApi.lua`
  Deprecated compatibility wrapper export
- `shared/services/UtilityService.lua`
  Shared utility functions and exports
- `shared/services/Regex.js`
  Shared regex export

## Export Overview

### Client exports

Use these from another client resource with:

```lua
exports.vorp_inventory:exportName(...)
```

### Server exports

Use these from another server resource with:

```lua
exports.vorp_inventory:exportName(...)
```

### Shared exports

These are utility helpers available as resource exports and are intended for lightweight shared logic.

## Client Exports

### Inventory control

#### `openInventory()`

Opens the player's main inventory UI.

```lua
exports.vorp_inventory:openInventory()
```

#### `closeInventory()`

Closes the inventory UI.

```lua
exports.vorp_inventory:closeInventory()
```

#### `toggleInventory()`

Opens the inventory if closed, or closes it if already open.

```lua
exports.vorp_inventory:toggleInventory()
```

#### `isInventoryOpen()`

Returns `true` when the inventory is currently open on the client.

```lua
local isOpen = exports.vorp_inventory:isInventoryOpen()
```

#### `setInventoryDisabled(state)`

Disables or re-enables inventory opening on the client.

```lua
exports.vorp_inventory:setInventoryDisabled(true)
exports.vorp_inventory:setInventoryDisabled(false)
```

### Client item / weapon use

#### `useItem(data)`

Triggers the standard item-use flow.

Expected `data` shape:

```lua
{
    item = "consumable_raspberrywater",
    type = "item_standard",
}
```

Example:

```lua
exports.vorp_inventory:useItem({
    id = itemId,
    item = "consumable_raspberrywater",
    type = "item_standard"
})
```

#### `useWeapon(data)`

Triggers the weapon-equip/use flow for an inventory weapon entry.

Expected `data` shape:

```lua
{
    id = 123,
    type = "item_weapon"
}
```

Example:

```lua
exports.vorp_inventory:useWeapon({
    id = 123,
    type = "item_weapon"
})
```

### Client lookup helpers

#### `getWeaponDefaultWeight(hash)`

Returns the configured default weapon weight.

#### `getWeaponDefaultDesc(hash)`

Returns the configured default weapon description.

#### `getWeaponDefaultLabel(hash)`

Returns the configured default weapon label.

#### `getWeaponName(hash)`

Returns the configured weapon name from a hash.

#### `getWeaponsDefaultData(request)`

Returns default weapon data based on the request expected by the utility layer.

#### `getWeaponAmmoTypes(group)`

Returns ammo types for a weapon group.

#### `getAmmoLabel(ammo)`

Returns the label for an ammo type.

#### `getInventoryItem(name)`

Returns a client-side inventory item definition by name.

#### `getInventoryItems()`

Returns the client-side item definition table.

#### `getServerItem(data)`

Returns server item information resolved through the client utility bridge.

Example:

```lua
local item = exports.vorp_inventory:getInventoryItem("water")
if item then
    print(item.label)
end
```

## Server Exports

Many server exports can be used as direct-return helpers, but any export backed by async database queries should be treated as callback-friendly first. If an export accepts a callback in the signature, use the callback form when you are unsure.

## Deprecated compatibility export

### `vorp_inventoryApi()`

Returns the legacy compatibility API table from `server/vorpInventoryApi.lua`.

Example:

```lua
local Inventory = exports.vorp_inventory:vorp_inventoryApi()
Inventory.addItem(source, "water", 1)
```

Use direct exports when possible. The wrapper exists mainly for backward compatibility.

## Server Exports Reference

### Carry checks

#### `canCarryItems(source, amount)`

Checks whether the player can carry additional total item weight/count.

#### `canCarryItem(source, itemName, amount)`

Checks whether the player can carry a specific item amount.

Example:

```lua
if exports.vorp_inventory:canCarryItem(source, "water", 5) then
    exports.vorp_inventory:addItem(source, "water", 5)
end
```

#### `canCarryWeapons(source, amount, cb, weaponName)`

Checks whether the player can carry more weapons.

`weaponName` can be a weapon name or hash.

### Item registration / usable items

#### `registerUsableItem(name, callback)`

Registers an item use callback.

Callback receives:

```lua
{
    source = source,
    item = {
        id = itemId,
        item = "item_name",
        name = "item_name",
        label = "Item Label",
        metadata = {},
        count = 1,
        percentage = 100,
        isDegradable = false
    }
}
```

Example:

```lua
exports.vorp_inventory:registerUsableItem("bandage", function(data)
    local src = data.source
    local itemId = data.item.id
    TriggerClientEvent("my_resource:useBandage", src, itemId)
end)
```

#### `unRegisterUsableItem(name)`

Removes a previously registered usable item callback.

### Player item queries

#### `getUserInventoryItems(source)`

Returns the player's normal inventory items.

#### `getItemCount(source, cb, itemName, metadata, percentage)`

Returns item count.

Notes:

- `metadata` narrows to matching metadata
- `percentage` is relevant for degradable items

#### `getItemDB(itemName)`

Returns the base item definition from the database-backed item cache.

#### `getItemByName(source, itemName)`

Returns an item instance by name.

#### `getItemContainingMetadata(source, itemName, metadata)`

Returns the first item containing the provided metadata subset.

#### `getItemMatchingMetadata(source, itemName, metadata)`

Returns the first item matching merged metadata exactly in the inventory search flow.

#### `getItemByMainId(source, itemId)`

Returns a single inventory item entry by its main inventory id.

#### `getItem(source, itemName, metadata)`

General item lookup helper. Use this for metadata-aware item retrieval.

Example:

```lua
local lockpick = exports.vorp_inventory:getItem(source, "lockpick")
if lockpick then
    print(lockpick.name, lockpick.count)
end
```

### Player item mutations

#### `addItem(source, name, amount, metadata, cb, allow, degradation, percentage)`

Adds an item to the player's default inventory.

Common use:

```lua
exports.vorp_inventory:addItem(source, "water", 2)
exports.vorp_inventory:addItem(source, "document", 1, {
    label = "Signed Contract",
    description = "Property transfer papers"
})
```

#### `subItem(source, name, amount, metadata, cb, allow, percentage)`

Removes item amount from the player's default inventory.

#### `subItemID(source, itemId, cb, allow, amount)`

Removes an item by its exact item id.

Alias also available:

#### `subItemById(source, itemId, cb, allow, amount)`

#### `setItemMetadata(source, itemId, metadata, amount, cb)`

Updates item metadata. This is especially useful for unique items, notes, licenses, recipes, or custom descriptions.

Example:

```lua
local item = exports.vorp_inventory:getItemByMainId(source, itemId)
if item then
    exports.vorp_inventory:setItemMetadata(source, itemId, {
        label = "Deputy Badge",
        description = "Issued by the Valentine sheriff office",
        badgeNumber = "VAL-014"
    })
end
```

### Weapon queries

#### `getUserWeapon(source, weaponId)`

Returns one weapon entry.

#### `getUserInventoryWeapons(source)`

Returns all player weapons.

#### `getWeaponBullets(source, weaponId)`

Returns stored ammo data for a weapon.

#### `getWeaponComponents(source, weaponId)`

Returns saved weapon components.

### Weapon mutations

#### `createWeapon(source, weaponName, ammos, components, comps, cb, wepId, customSerial, customLabel, customDesc)`

Creates/registers a weapon for the player.

Minimal example:

```lua
local weaponId = exports.vorp_inventory:createWeapon(
    source,
    "WEAPON_REVOLVER_CATTLEMAN",
    {},
    {},
    {},
    nil,
    nil,
    "SERIAL-1001",
    "Marshal Revolver",
    "Custom issue sidearm"
)
```

#### `giveWeapon(source, weaponId, target)`

Transfers a weapon from one player to another.

#### `subWeapon(source, weaponId)`

Removes/subtracts a weapon from the player.

#### `deleteWeapon(source, weaponId)`

Deletes a weapon record.

#### `setWeaponCustomLabel(weaponId, label)`

Sets a weapon custom label.

#### `setWeaponSerialNumber(weaponId, serial)`

Sets a weapon serial number.

#### `setWeaponCustomDesc(weaponId, desc)`

Sets a weapon custom description.

### Ammo exports

#### `getUserAmmo(source)`

Returns the player's saved ammo table.

#### `addBullets(source, bulletType, amount)`

Adds ammo to the player.

#### `subBullets(weaponId, bulletType, amount)`

Subtracts ammo from a weapon flow.

#### `removeAllUserAmmo(source)`

Clears all user ammo.

Example:

```lua
exports.vorp_inventory:addBullets(source, "ammorevolvernormal", 24)
```

### Custom inventory registration and control

#### `registerInventory(data)`

Registers a custom inventory.

Common fields:

```lua
{
    id = "my_stash",
    name = "My Stash",
    limit = 50,
    acceptWeapons = true,
    shared = false,
    ignoreItemStackLimit = false,
    whitelistItems = false,
    UsePermissions = false,
    UseBlackList = false,
    whitelistWeapons = false,
    useWeight = false,
    weight = 0.0
}
```

Example:

```lua
exports.vorp_inventory:registerInventory({
    id = "smithy_storage",
    name = "Smithy Storage",
    limit = 80,
    acceptWeapons = true,
    shared = true,
    ignoreItemStackLimit = false,
    whitelistItems = false,
    UsePermissions = false,
    UseBlackList = false,
    whitelistWeapons = false
})
```

#### `removeInventory(id)`

Unregisters a custom inventory.

#### `openInventory(source, id)`

Opens:

- the main inventory if `id` is omitted
- the custom inventory if `id` is provided

Examples:

```lua
exports.vorp_inventory:openInventory(source)
exports.vorp_inventory:openInventory(source, "smithy_storage")
```

#### `closeInventory(source, id)`

Closes the inventory for the player. If `id` is passed, it closes the custom inventory flow.

#### `isCustomInventoryRegistered(id)`

Returns whether a custom inventory is already registered.

#### `getCustomInventoryData(id)`

Returns the registration/config data for a custom inventory.

#### `updateCustomInventoryData(id, data)`

Updates registration/config data for a custom inventory.

### Custom inventory permissions and limits

#### `AddPermissionMoveToCustom(id, jobName, grade)`

Allows a job/grade to move items into a custom inventory.

#### `AddPermissionTakeFromCustom(id, jobName, grade)`

Allows a job/grade to take items from a custom inventory.

#### `AddCharIdPermissionMoveToCustom(id, charId, state)`

Allows a specific character id to move items into a custom inventory.

`state` can be used to add, remove, or update temporary char-based permission handling.

#### `AddCharIdPermissionTakeFromCustom(id, charId, state)`

Allows a specific character id to take items from a custom inventory.

#### `BlackListCustomAny(id, itemName)`

Blacklists an item from a custom inventory.

#### `updateCustomInventorySlots(id, slots)`

Updates custom inventory slot capacity.

#### `getCustomInventorySlots(id)`

Returns custom inventory slot capacity.

#### `setCustomInventoryItemLimit(id, itemName, limit)`

Sets the max amount of one item name allowed inside that custom inventory.

#### `setCustomInventoryWeaponLimit(id, weaponName, limit)`

Sets the max amount of one weapon type allowed inside that custom inventory.

### Custom inventory contents

#### `addItemsToCustomInventory(id, items, charid, callback, identifier)`

Adds items directly into a custom inventory.

`items` format:

```lua
{
    { name = "water", amount = 10, metadata = {} },
    { name = "bread", amount = 5, metadata = {} }
}
```

Example:

```lua
exports.vorp_inventory:addItemsToCustomInventory("smithy_storage", {
    { name = "iron", amount = 20 },
    { name = "wood", amount = 10 }
}, charId)
```

#### `addWeaponsToCustomInventory(id, weapons, charid)`

Adds weapons to a custom inventory.

#### `getCustomInventoryItemCount(id, itemName, itemCraftedId, callback, metadata)`

Returns the amount of an item inside a custom inventory.

#### `getCustomInventoryWeaponCount(id, weaponName)`

Returns the amount of a weapon inside a custom inventory.

#### `removeItemFromCustomInventory(id, itemName, amount, itemCraftedId)`

Removes item quantity from a custom inventory.

#### `removeWeaponFromCustomInventory(id, weaponName)`

Removes a weapon by weapon name from a custom inventory.

#### `removeCustomInventoryWeaponById(id, weaponId)`

Removes a weapon by exact weapon id from a custom inventory.

#### `getCustomInventoryItems(id)`

Returns all normal items in a custom inventory.

#### `getCustomInventoryWeapons(id)`

Returns all weapons in a custom inventory.

#### `updateCustomInventoryItem(id, itemId, metadata, amount, callback, identifier)`

Updates a custom inventory item record.

#### `deleteCustomInventory(id)`

Clears cached and stored custom inventory contents.

## Open Player Inventory Export

### `openPlayerInventory(data, callback)`

Opens another player's inventory through the built-in player inventory flow.

Expected `data` shape:

```lua
{
    title = "Player Search",
    source = source,
    target = targetSource,
    blacklist = {},
    timeout = 30,
    itemsLimit = {
        items = {
            itemType = "item_standard",
            limit = 10
        },
        weapons = {
            itemType = "item_weapon",
            limit = 1
        }
    }
}
```

This is an advanced flow used by scripts that need controlled player-to-player inventory access.

## Shared Exports

### `checkRegex(regex, str)`

Regex validation helper from `shared/services/Regex.js`.

Example:

```lua
local ok = exports.vorp_inventory:checkRegex("^[0-9]+$", "12345")
```

### `tableEquals(a, b, ignore_mt)`

Deep table equality helper.

### `tableContains(a, b)`

Returns `true` when table `a` contains the key/value structure of table `b`.

### `mergeTables(a, b)`

Merges two tables or JSON-like payloads into a Lua table.

Example:

```lua
local merged = exports.vorp_inventory:mergeTables(
    { label = "License" },
    { owner = "John Marston" }
)
```

### `isValueInArray(value, array)`

Simple array membership helper.

## Common Integration Recipes

## 1. Register a stash from another resource

```lua
exports.vorp_inventory:registerInventory({
    id = "doctor_storage",
    name = "Doctor Storage",
    limit = 100,
    acceptWeapons = false,
    shared = true,
    ignoreItemStackLimit = false,
    whitelistItems = false,
    UsePermissions = true,
    UseBlackList = false,
    whitelistWeapons = false
})

exports.vorp_inventory:AddPermissionMoveToCustom("doctor_storage", "doctor", 0)
exports.vorp_inventory:AddPermissionTakeFromCustom("doctor_storage", "doctor", 0)
```

## 2. Open that stash for a player

```lua
exports.vorp_inventory:openInventory(source, "doctor_storage")
```

## 3. Add a metadata-driven document

```lua
exports.vorp_inventory:addItem(source, "document", 1, {
    label = "Business Contract",
    description = "Signed by both parties",
    contractId = "CNT-204"
})
```

## 4. Check and remove a required ingredient

```lua
local count = exports.vorp_inventory:getItemCount(source, nil, "water")
if count >= 2 then
    exports.vorp_inventory:subItem(source, "water", 2)
end
```

## 5. Create a custom weapon reward

```lua
local created = exports.vorp_inventory:createWeapon(
    source,
    "WEAPON_REVOLVER_CATTLEMAN",
    {},
    {},
    {},
    nil,
    nil,
    "EVENT-001",
    "Prize Revolver",
    "Awarded to the tournament winner"
)
```

## Crafting Notes

- Recipes are stored in `config/craft.lua`
- Craft workspace contents are saved in `craft_inventories.json`
- Crafting stations are prompt-driven
- Each craft location can be a normal no-ped station or an NPC ped station
- The resource checks recipe completion against current craft slots before allowing crafting

### Craft station config format

Basic no-ped station:

```lua
Config.CraftLocations = {
    {
        coord = vector3(-369.51, 796.07, 116.2),
        label = "Craft Station",
        interactDistance = 2.0,
    }
}
```

NPC ped station:

```lua
Config.CraftLocations = {
    {
        coord = vector3(-365.12, 792.84, 116.18),
        label = "Camp Cook",
        interactDistance = 2.0,
        ped = {
            enabled = true,
            model = "U_M_M_NbxGeneralStoreOwner_01",
            heading = 180.0,
            scenario = "WORLD_HUMAN_SMOKE",
        }
    }
}
```

Supported craft location fields:

- `coord`
  Base interaction position for the craft station
- `label`
  Prompt group label shown to the player
- `interactDistance`
  Distance required to interact with the station
- `ped.enabled`
  Set `true` to spawn an NPC crafter at that location
- `ped.model`
  Ped model name or hash
- `ped.heading`
  Ped heading
- `ped.scenario`
  Optional idle scenario
- `ped.coords`
  Optional separate ped spawn position if you do not want the NPC exactly on the interaction point

## Stash Notes

- Config stashes are auto-registered on server start
- Job checks for config stashes are handled in `server/server.lua`
- You can also register additional inventories dynamically through exports

## Durability Notes

- Durability data is stored per weapon
- Weapon repair uses repair locations defined in `config/config.lua`
- Repair flow depends on `vorp_progressbar`

## Best Practice Notes

- Prefer exports over directly editing core inventory logic
- Use metadata for unique items instead of making many duplicate item names
- Use `registerUsableItem` for gameplay interactions
- Use custom inventories for businesses, jobs, wagons, housing, or mission containers
- Keep `DevMode` disabled on live servers

## Troubleshooting

### Inventory opens but items are missing

- Check your database `items` table
- Confirm item names match what other scripts are adding
- Confirm item images exist if the UI appears blank for those items

### Repair does not work

- Confirm `vorp_progressbar` is running
- Confirm durability is enabled in config
- Confirm repair locations are configured

### Custom inventory will not open

- Confirm it was registered first
- Confirm another player is not already using it
- Confirm permission settings are not blocking access

### Shared/client export call fails

- Confirm the resource name is exactly `vorp_inventory`
- Confirm your call is made from the correct side
- Confirm your script starts after this resource
