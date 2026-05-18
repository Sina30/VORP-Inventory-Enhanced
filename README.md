# VORP Inventory Enhanced

Enhanced RedM inventory resource built on top of the original `vorp_inventory` for the VORP framework.

This repository keeps the VORP inventory foundation, extends it with new gameplay features, and ships with a modern UI, crafting support, stash support, weapon durability, hotbar behavior, item metadata support, and a much broader export surface for other resources.

## Credits

- Original framework: `VORP Framework`
- Original inventory base: `VORP Inventory`
- Original repository: <https://github.com/VORPCORE/vorp_inventory>
- Additional credit requested for `Outsider`
- Enhancement / integration work: this repository and its maintainers

This project is an enhancement of the VORP inventory ecosystem. It is not presented as a replacement for the original authorship.

## Preview and Docs
- Video: [YouTube](https://youtu.be/pvwEyYEfvvI)
- Docs: [Link](https://coderanch-redm-store.gitbook.io/coderanch-redm-store-docs/coderanch-vorp_inventory)

## What This Resource Includes

- Player inventory with items, weapons, money, gold, and ammo support
- Weapon-aware inventory entries with labels, descriptions, serials, components, ammo totals, and durability
- Custom inventories that can be registered and opened from other resources
- Built-in config-based stashes with prompt locations and job access restriction
- Drop inventories with world props, pickup syncing, lock handling, and optional auto-cleanup
- Crafting system with persistent craft slots saved to `craft_inventories.json`
- Craft stations can be plain interaction points or NPC ped stations
- Weapon durability and repair flow with configurable repair stations
- Hotbar toggle and hotbar quick-use keys
- Player-to-player giving
- Player stealing flow with its own second-inventory view
- Metadata-aware items and metadata-aware inventory queries
- Export API for client, server, and shared utility usage
- Vue/Vite source for the UI plus prebuilt `ui/` assets ready to run

## Main Features

### Inventory Core

- Supports normal items, weapon items, money, gold, and ammo entries
- Uses slot-based inventory behavior
- Tracks total carried weight
- Supports item metadata, custom labels, custom descriptions, and degradation-aware items
- Supports default inventory opening from keybind and server-side open calls

### Custom Inventories

- Register inventories dynamically from other resources
- Shared or character-bound inventory behavior
- Slot-based or weight-based storage
- Optional weapon acceptance
- Item and weapon per-inventory limits
- Job permission and charid permission helpers
- Inventory open/close state protection

### Stashes

- Config-driven stash definitions in `config/config.lua`
- Prompt-based interaction at world coordinates
- Shared or personal stash behavior
- Job-restricted access support

### Crafting

- Recipe definitions in `config/craft.lua`
- Prompt-driven craft station locations with optional NPC ped support
- Per-character crafting workspace persisted in `craft_inventories.json`
- Craft slot moving, splitting, merging, and removal
- Timed crafting completion with notifications

### Weapons

- Weapon registration, ownership, ammo tracking, and custom metadata fields
- Weapon serial number support
- Weapon durability support
- Repair station flow with progress bar integration
- Weapon component retrieval
- Dual wield handling
- Lantern belt behavior

### UI / UX

- Modern NUI inventory
- Hotbar quick-use
- Sound toggles
- Optional open animation
- Nearby-player give flow
- Context actions and secondary inventory support

## Requirements

### Required

- `RedM`
- `VORP Core`
- `oxmysql`

### Recommended / Optional

- `vorp_progressbar`
  Required if you keep weapon repair enabled in config
- Any resources that integrate with the included second-inventory hooks:
  - `vorp_stables`
  - `vorp_bank`
  - `vorp_housing`
  - `syn_store`
  - `syn_clan`
  - `syn_Container`
  - `syn_underground`
  - `syn_weapons`

If you do not use those optional integrations, the inventory still works. Those hooks simply exist so other systems can open or move into linked inventories.

## Installation

### 1. Place the Resource

Put the folder inside your RedM resources directory, for example:

```txt
resources/[vorp]/vorp_inventory
```

### 2. Ensure Dependencies

Make sure these resources are started before this inventory:

```cfg
ensure oxmysql
ensure vorp_core
ensure vorp_progressbar
ensure vorp_inventory
```

If you do not want repair progress bars, disable weapon durability repair usage in config or remove that gameplay flow before omitting `vorp_progressbar`.

### 3. Database

This resource expects the normal VORP inventory data model and item database to exist.

At startup, this version automatically checks and adds these columns if needed:

- `character_inventories.slot`
- `loadout.slot`
- `loadout.ammo_total`
- `loadout.durability`

That means you usually do not need to do those migrations manually.

### 4. Items / Images

- Item definitions are loaded from your database `items` table
- Item icons are served from the `items/` folder
- Weapon data is loaded from config/shared data

Make sure your database item names and image names match your intended setup.

### 5. Restart and Test

After installing:

1. Restart the resource
2. Join with a character
3. Open inventory with the configured key
4. Test item loading, weapons, drops, stashes, and crafting

## Frontend Development

The repo already includes built `ui/` files, so a frontend build is not required for normal installation.

Only rebuild the UI if you edit the source inside `web/`:

```bash
cd web
npm install
npm run build
```

The Vite config outputs directly into the `ui/` folder.

## Important Config Files

- `config/config.lua`
  Main inventory behavior, keybinds, drops, stashes, durability, death handling, hotbar-related behavior, and more
- `config/craft.lua`
  Recipes, craft slots, and craft station locations, including optional NPC ped crafting stations
- `config/weapons.lua`
  Weapon defaults and inventory weapon data
- `config/ammo.lua`
  Ammo mappings and ammo-related shared data
- `config/groups.lua`
  Group/classification data used by the inventory
- `config/logs.lua`
  Logging and webhook-related settings

## Included Gameplay Systems

### Stashes

Config-based stash entries are auto-registered on startup through the server API. Each stash can be:

- Shared or personal
- Slot-based or weight-based
- Restricted to one or more jobs

### Crafting

Players can move items into a craft workspace, match configured recipes, and complete crafting over time. Craft slot contents persist in `craft_inventories.json`.

Craft stations can be configured in two ways:

- Plain craft point with no ped
- NPC craft station with a configurable ped model, heading, and scenario

Example craft config:

```lua
Config.CraftLocations = {
    {
        coord = vector3(-369.51, 796.07, 116.2),
        label = "Craft Station",
        interactDistance = 2.0,
    },
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

### Drops

Dropped items can create world pickup inventories with lock protection so multiple players do not fight over the same drop at once.

### Stealing

The included `/steal` command opens the nearest player's inventory if conditions are met. You can require a weapon before stealing by config.

### Weapon Repairs

Repair locations are defined in config. A damaged equipped weapon can be repaired through a timed process and restored to full durability.

## Notes for Server Owners

- `Config.DevMode` should stay `false` on live servers
- `Config.Debug` should stay `false` unless actively troubleshooting
- The inventory depends heavily on your item database quality
- If you rename or remove items in the database, old inventory entries may no longer resolve correctly
- Optional integrations can trigger inventory views for horse, cart, bank, house, clan, hideout, and store flows

## Exports and Integration

This resource exposes:

- Client exports
- Server exports
- Shared utility exports

Full usage examples and reference documentation are in [docs.md](./docs.md).

## File Overview

- `client/`
  Client inventory behavior, NUI handling, hotbar logic, pickups, and client exports
- `server/`
  Inventory services, inventory API, persistence logic, crafting, stashes, repair flow, and server exports
- `shared/`
  Shared models and utility helpers
- `ui/`
  Built production NUI files
- `web/`
  Vue/Vite source for UI development
- `items/`
  Inventory item icons

## Support / Customization

This version is designed to be extended by other VORP resources. The main integration path should be through exports rather than editing core logic every time you want to add a new system.

Recommended customization areas:

- Config-driven stash registration
- Recipe definitions
- New usable item registration
- Custom inventory registration for jobs, businesses, wagons, houses, and world objects
- Metadata-driven item systems
- Weapon custom labels, serials, and descriptions

## Final Credit Statement

All base framework credit belongs to the VORP team and the original `vorp_inventory` project. This repository enhances and extends that work, and also includes the requested credit mention for `Outsider`.
