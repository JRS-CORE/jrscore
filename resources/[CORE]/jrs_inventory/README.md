# JRS Inventory

A modern, server-authoritative RedM inventory system built from the ground up for **JRS Core**.

---

## Overview

`jrs_inventory` provides a high-performance inventory with native NUI drag-and-drop, persistent slot indexing, multi-currency support, custom storages, and built-in player interaction systems.

## Key Features

- **Server-Authoritative**: All item transfers, splits, drops, and pickups are strictly validated server-side.
- **Persistent Grid & Quick Slots**: Custom manual slot arrangements with dedicated hotbar slots (1-5).
- **Multi-Currency System**: Full native support for Cash, Gold, and Dirty Money (`jrs_core` currencies).
- **Custom Storage API**: Integrated chest and stash system with deposit, withdraw, and access permissions.
- **Ground Drops**: 3D world props with distance tiers, operation locks, and persistence.
- **Weapons & Equipment**: Unique weapon serials, durability tracking, dynamic ammo synchronization.
- **Player Robbery & Search**: Integrated robbery interface for downed/hogtied players without external dependencies.
- **Lightweight NUI**: Optimized CEF rendering with local Western UI styling and lightweight audio feedback.

---

## Installation & Load Order

Ensure the resource in your `server.cfg` after `oxmysql` and `jrs_core`:

```cfg
ensure oxmysql
ensure jrs_core
ensure jrs_inventory
```

---

## Configuration

All runtime options are organized in the `config/` directory:

| File | Description |
|---|---|
| `config/config.lua` | Weight limits, default slots, ground drops, hotbar, and UI options |
| `config/robbery.lua` | Player robbery rules, police requirements, and protected zones |

---

## Developer API

### Server Exports

```lua
-- Add an item to a player
exports['jrs_inventory']:addItem(source, 'bread', 1, {})

-- Remove an item from a player
exports['jrs_inventory']:subItem(source, 'bread', 1)

-- Check item quantity
local count = exports['jrs_inventory']:getItemCount(source, 'bread')

-- Check if player can carry weight/slots
local canCarry = exports['jrs_inventory']:canCarryItem(source, 'iron_ore', 5)

-- Open custom storage
TriggerEvent('jrs_inventory:server:openStorage', source, storageId, storageData)
```

### Client Exports

```lua
-- Open inventory programmatically
exports['jrs_inventory']:OpenInventory()

-- Close inventory
exports['jrs_inventory']:CloseInventory()
```

---

## License

Part of the **JRS Core** framework. Distributed under the **GNU General Public License v3.0**.
