# JRS Core

The framework resource of **JRS Core** - the free RedM roleplay framework by the **JRS TEAM**.

| | |
|---|---|
| Resource | `jrs_core` |
| Game | RedM (rdr3) |
| Author | JRS TEAM |
| Needs | `oxmysql` (started before `jrs_core`) |

It handles connections, characters, money / gold / dirty money, jobs and multi-jobs, groups,
XP and levels, the compact HUD and its editor, notifications, menus, inputs, callbacks,
the input wheel, waypoints, map discoveries, wildlife and traffic density.

---

## Configuration

Everything is in **4 files** inside `config/`:

| File | What it controls |
|---|---|
| `config.lua` | Core: language, whitelist, Discord / Steam checks, admin groups, spawn, server management, performance, award pop-ups, character service (max jobs, job switch cooldown) |
| `gameplay.lua` | Gameplay switches, gamepad, wildlife density, input wheel, 3D waypoint |
| `economy.lua` | Starting money, rewards, taxes, daily challenges |
| `levels.lua` | XP needed per level (up to 100), level perks, job perks |

Each file is split into titled sections. Change a value, then `restart jrs_core` (or restart the server).

---

## Using JRS Core in your scripts

Load one API object on the side where your code runs:

```lua
-- server
local JRS = exports.jrs_core:getCoreApi()
local character = JRS.GetCharacter(source)
JRS.AddMoney(source, 25)
JRS.AddXP(source, 10, 'mission_reward')
JRS.NotifyRightTip(source, 'Reward received', 3000)
```

```lua
-- client
local JRS = exports.jrs_core:getCoreApi()
JRS.NotifyRightTip('Ready', 3000)
JRS.SetCustomDestination(vector3(0.0, 0.0, 0.0), 'Destination')
JRS.Rpc('jrs:getPlayerData', function(playerData)
    print(json.encode(playerData))
end, {})
```

Menus and inputs are part of the core:

```lua
local MenuData = exports.jrs_core:GetMenuData()
local text = exports.jrs_core:advancedInput({ type = 'enableinput', inputType = 'input', button = 'OK',
    placeholder = 'Name', style = 'block', attributes = { inputHeader = 'Title', type = 'text' } })
```

Jobs: `exports.jrs_core:SetJob(src, job, grade)`, `GetJobs`, `AddJob`, `RemoveJob`, `SwitchJob`.

---

## Load order

```
ensure oxmysql
ensure jrs_core
ensure jrs_inventory
...
```

`server.cfg` in the pack already has the right order.
