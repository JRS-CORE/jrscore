# jrs_character 3.1.2

Clean JRS character lifecycle, selector, creator, clothing, barber, respawn, and playtime-aging resource.

This build contains the city spawn book and wake-up animation only; the experimental identity-card system is not included.

## Structure

```text
jrs_character/
├── client/client.lua       # all client runtime logic
├── server/server.lua       # all server runtime logic
├── config.lua              # all editable configuration
├── data/client.lua         # large client-only asset tables
├── data/shared.lua         # shared character appearance defaults
├── ui/                     # NUI outside the old creator directory
├── sql/install.sql         # database installation / upgrades
└── fxmanifest.lua
```

## Installation

1. Replace the previous `jrs_character` folder completely. Do not merge the old and new folders.
2. Import `sql/install.sql` once.
3. Ensure resources start in this order: `oxmysql`, `jrs_core`, `jrs_inventory`, `jrs_clothing`, `jrs_barber`, `jrs_character`.
4. Perform a full server restart.

## Compatibility

Event names and exports remain unchanged so existing JRS resources continue to call the same APIs.


## New-character spawn book

New characters choose their first city from an open-book UI after finishing appearance and clothing.

Configure pages in `Config.SpawnBook.Cities`. Every city has an independent `Enabled = true/false` toggle, image, description, details, preview camera and final spawn coordinates. Keep at least one city enabled.

Included pages: Valentine, Rhodes, Saint Denis, Blackwater, Armadillo and Strawberry.

## Spawn wake-up animation

Living characters play `wakeup_slow_charles` when they enter the game world. Configure or disable it under `Config.SpawnAnimation` in `config.lua`.


## Character Ready Gate (v3.1.4)

The character resource now owns a pre-character gate. While the selector, new-character creator, or final character spawn is still active:

- gameplay controls and the pause/ESC menu are blocked;
- HUD/radar are kept hidden;
- `LocalPlayer.state.jrsCharacterGate` is `true`;
- `LocalPlayer.state.jrsCharacterReady` is `false`.

Only after the selected/created character has finished model, body, clothing, barber, position and final spawn initialization does the resource publish:

- `LocalPlayer.state.jrsCharacterGate = false`
- `LocalPlayer.state.jrsCharacterReady = true`
- event: `jrs_character:gateChanged`
- export: `exports.jrs_character:IsCharacterReady()`
- export: `exports.jrs_character:IsCharacterGateActive()`

Other gameplay/UI resources should defer player-facing initialization until `jrsCharacterReady == true`. Required character dependencies still need to be started by the server so the creator can function; the gate prevents their gameplay controls/UI from being usable before character entry.
