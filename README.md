<div align="center">

<img src=".github/assets/banner.png" alt="JRS Core" width="100%">

# JRS Core

**A high-performance, modular roleplay framework for RedM.**
Built natively from the ground up with a unified architecture, clean code, and zero third-party framework dependencies.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: RedM](https://img.shields.io/badge/Platform-RedM-a4161a.svg)](https://redm.net)
[![Language: Lua 5.4](https://img.shields.io/badge/Lua-5.4-2c2d72.svg)](https://www.lua.org)
[![Docs](https://img.shields.io/badge/Docs-docs.jrs--core.com-success.svg)](https://docs.jrs-core.com)
[![Discord](https://img.shields.io/badge/Discord-Join-5865F2.svg?logo=discord&logoColor=white)](https://discord.gg/jrscore)

[Documentation](https://docs.jrs-core.com) · [Discord](https://discord.gg/jrscore) · [Report a Bug](../../issues/new/choose) · [العربية](README.ar.md)

</div>

---

## Overview

**JRS Core** is a complete, native RedM framework engineered for stability, ultra-low resource usage, and a seamless developer experience. Every script shares a unified object model, standardized events, and an optimized MySQL layer.

- **Unified Core Architecture**: Zero legacy framework emulation layers; 100% native JRS logic.
- **Bi-lingual Interface**: Native English and Arabic localization built into all systems.
- **Optimized Performance**: Tick-rate throttled idle loops and CEF UI isolation.
- **Free & Open Source**: Licensed under the GNU General Public License v3.0.

---

## Included Resources

| Directory | Resource | Description |
|---|---|---|
| `[CORE]` | `jrs_core` | Character management, economy (cash/gold/dirty money), jobs, permissions, HUD, RPC, and native player classes |
| `[CORE]` | `jrs_inventory` | Server-authoritative inventory, quick slots, custom storages, ground drops, weapon serials, and player robbery |
| `[CORE]` | `jrs_chat` | Native proximity chat (`/me`, `/do`, `/s`, `/w`, `/ann`, `/ooc`) with modern Western styling |
| `[CORE]` | `jrs_loadingscreen` | Responsive HD/2K/4K loading screen with video/slideshow, unified audio controls, and staff showcase |
| `[CORE]` | `jrs_updater` | Automated version checker and release validator |
| `[WORLD]` | `jrs_city` | RedM native zone discovery and location display |

*Bundled dependencies:* `oxmysql`, `pma-voice`, `PolyZone`, `uiprompt`, `weathersync`, `moonshine_interiors`, `httpmanager`.

---

## Requirements

- RedM Server (recommended build artifacts) with **OneSync** enabled.
- MySQL / MariaDB database server.
- Server license key from the [Cfx.re Keymaster](https://keymaster.fivem.net).

---

## Quick Installation

### Option 1: txAdmin Recipe (Recommended)

1. In txAdmin, select **Remote URL Template**.
2. Enter the recipe URL:
   ```text
   https://raw.githubusercontent.com/JRS-CORE/jrscore/main/recipe/jrscore.yaml
   ```
3. Follow the guided setup to automatically import the database and configure `server.cfg`.

### Option 2: Manual Setup

1. Place the `resources` directory in your server root.
2. Import `sql/jrscore.sql` into your database.
3. Add the following resource start order to your `server.cfg`:
   ```cfg
   ensure oxmysql
   ensure jrs_core
   ensure jrs_inventory
   ensure jrs_chat
   ensure jrs_loadingscreen
   ```
4. Configure `sv_enforceGameBuild 1491` in `server.cfg`.

---

## Developer API

Access the native core API anywhere in your scripts:

```lua
-- Server-side
local JRS = exports['jrs_core']:getCoreApi()
local character = JRS.GetCharacter(source)

if character then
    JRS.AddMoney(source, 50.0)
    JRS.NotifyRightTip(source, 'Payment received: $50.00', 3000)
end

-- Client-side
local JRS = exports['jrs_core']:getCoreApi()
JRS.NotifyRightTip('Welcome to the Frontier', 4000)
```

---

## Community & Support

- **Documentation**: [docs.jrs-core.com](https://docs.jrs-core.com)
- **Discord Community**: [discord.gg/jrscore](https://discord.gg/jrscore)
- **Bug Reports**: [Open an Issue](../../issues/new/choose)

---

## Development

Developed and maintained natively by the **JRS TEAM**.

---

## License

JRS Core is free software licensed under the **GNU General Public License v3.0**.
See [LICENSE](LICENSE) for full details.
