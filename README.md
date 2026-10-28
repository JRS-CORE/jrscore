<div align="center">

<img src=".github/assets/banner.png" alt="JRS Core" width="100%">

# JRS Core

**A free, open-source roleplay framework for RedM.**
One framework, one visual style, ready to run.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: RedM](https://img.shields.io/badge/Platform-RedM-a4161a.svg)](https://redm.net)
[![Language: Lua 5.4](https://img.shields.io/badge/Lua-5.4-2c2d72.svg)](https://www.lua.org)
[![Docs](https://img.shields.io/badge/Docs-docs.jrs--core.com-success.svg)](https://docs.jrs-core.com)
[![Discord](https://img.shields.io/badge/Discord-Join-5865F2.svg?logo=discord&logoColor=white)](https://discord.gg/jrscore)

[Documentation](https://docs.jrs-core.com) · [Discord](https://discord.gg/jrscore) · [Report a bug](../../issues/new/choose) · [العربية](README.ar.md)

</div>

---

## What is JRS Core?

JRS Core is a complete RedM server pack built around one core. Every script shares the same API, the same
interface style and the same database, so a new server works from the first start instead of after weeks of
gluing resources together.

- **74 JRS resources** that are made to work together
- **One-click install** with a txAdmin recipe, database included
- **English and Arabic** in every interface
- **Free forever**, released under the GNU GPL v3

## Features

| Area | What you get |
|---|---|
| **Core** | Users and characters, money and gold, jobs and multi-job, XP and levels, HUD, notifications, menus, inputs, callbacks, permissions |
| **Inventory** | Items, weapons and ammo, weight and slots, ground drops, storages, backpacks, player trade |
| **Characters** | Selector and full creator, clothing, barber, walk styles, animations, metabolism, passports |
| **Economy** | Banking, stores, billing, paychecks, mailbox, saloons, weapons, trader |
| **Jobs** | Police and MDT, medic, boss menu, crafting, mining, smelting, gold panning, lumberjack, fishing, hunting, herbs, railroad |
| **Properties** | Housing, wild horses, door locks, trapdoors |
| **Crime** | Outlaws, robberies, NPC looting, lockpicking, searching |
| **World** | Towns and zones, Guarma, canoes, hot air balloon, NPCs, teleports, zombie outbreaks |
| **Admin** | Admin menu, death logs, IMAP view tool |

## What is in the pack

| Folder | Resources |
|---|---|
| `[CORE]` | `jrs_core` `jrs_inventory` `jrs_loadingscreen` `jrs_chat` `jrs_updater` |
| `[WORLD]` | `jrs_city` |

Also included: `[CFX]` (default CFX resources and screenshot-basic) and `[DEPENDENCIES]`
(oxmysql, uiprompt, pma-voice, PolyZone, httpmanager, objectloader, weathersync, moonshine_interiors).

## Requirements

- A RedM server with the latest recommended artifacts, and txAdmin
- MariaDB or MySQL
- A server key from the [Cfx.re portal](https://portal.cfx.re)
- OneSync enabled

## Installation

### Option 1: txAdmin recipe (recommended)

1. In txAdmin choose **Remote URL Template**.
2. Paste this URL:
   ```
   https://raw.githubusercontent.com/JRS-CORE/jrscore/main/recipe/jrscore.yaml
   ```
3. txAdmin downloads every resource, creates and imports the database, and writes `server.cfg`.
4. Start the server.

### Option 2: offline installer

Run `INSTALL.bat` and answer the questions (server folder, MySQL login, licence key).
It copies the resources, imports `sql/jrscore.sql` and writes `server.cfg`.

### Option 3: manual

1. Copy the `resources` folder into your server folder.
2. Import `sql/jrscore.sql` into an empty database.
3. Copy `server.cfg` and fill in the `{{...}}` values.

### After installing

- Keep `sv_enforceGameBuild 1491` in `server.cfg`.
- `oxmysql` and `jrs_core` must start before everything else.
- To become owner, add your Steam hex to `Config.CoreOwners` in
  `resources/[CORE]/jrs_core/config/config.lua`, or set `group` to `owner` in the `jrs_users` table, then rejoin.

## Configuration

| File | What it controls |
|---|---|
| `jrs_core/config/config.lua` | Default language, whitelist, starting money and items, admins, commands |
| `jrs_core/config/levels.lua` | Levels and XP |
| `jrs_inventory/config/config.lua` | Weight, slots, items |
| `jrs_character/config/config.lua` | Spawn points, character slots, creator |
| `jrs_loadingscreen/web/config_main.js` | Server name, links, video, music |
| `jrs_loadingscreen/web/config_staff.js` | Staff, rules, news |

## Developer API

```lua
local JRS = exports.jrs_core:getCoreApi()

local character = JRS.getCharacter(source)
JRS.addMoney(source, 0, 100)            -- 0 = money, 1 = gold
JRS.setJob(source, 'police', 0)
JRS.NotifyRightTip(source, 'Hello', 4000)

exports.jrs_inventory:addItem(source, 'water', 1)
local count = exports.jrs_inventory:getItemCount(source, 'water')
```

The full API reference, guides and one page per script are on **[docs.jrs-core.com](https://docs.jrs-core.com)**.
More examples: `resources/[CORE]/jrs_core/api_usage_examples.lua`.

## Stores

- **JRS SOTR:** [jrs-sotr.tebex.io](https://jrs-sotr.tebex.io/)
- **Gum Scripts:** [gum-scripts.tebex.io](https://gum-scripts.tebex.io/)
## Support
- **Documentation:** [docs.jrs-core.com](https://docs.jrs-core.com)
- **Community and support:** [discord.gg/jrscore](https://discord.gg/jrscore)
- **Bugs and ideas:** [open an issue](../../issues/new/choose)

Please read the FAQ and search existing issues before you open a new one, and never post licence keys,
server keys or passwords.

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. For security problems follow
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## Team

| | Role |
|---|---|
| **ALFIE** | Founder and Lead Developer |
| **JRS** | Founder and Lead Developer |
| **GM** | Project Manager |

JRS Core is made by the **JRS TEAM**. Full credits, including the open-source projects this pack builds on,
are in [CREDITS.md](CREDITS.md).

## Contributors

| | Contribution |
|---|---|
| [**NQ3Z**](https://github.com/NQ3Z) (Jehad Abdulwahab) | Contributor |
| [**jrsmatrex**](https://github.com/jrsmatrex) | Contributor: `jrs_zombies`, `jrs_zombies_notify`, `bee_house` |
| [**gummyantifi**](https://github.com/gummyantifi) (Gummik) | Contributor |
| [**JRS-CORE**](https://github.com/JRS-CORE) | All JRS Core repositories, one per script |

## License

JRS Core is free software under the [GNU General Public License v3.0](LICENSE).
You may use, change and share it. Anything you build from it must stay under the same license, with the source available and the credits kept.
