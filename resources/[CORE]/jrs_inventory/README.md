# jrs_inventory

## v1.6.30 - Storage transfer slots + centered inventory navigation
- Centered Inventory search directly below the title.
- Category filter and action tabs are separated into clear rows.
- Storage uses five real columns with visible slot numbers.
- Drag player Inventory -> Storage and Storage -> player Inventory with source-aware drop targets.
- Dropping onto an empty Storage slot persists that Storage slot; dropping Storage content onto a free player slot requests that exact player slot.
- Empty Storage slot drops persist the selected Storage slot in the storage JSON.
- Added clear PLAYER INVENTORY / STORAGE transfer labels and lightweight drop feedback.
- Keeps wallet, gold, dirty money, clothing, ground and hotbar hidden in Storage mode.
- JRS Core only.

# v1.6.9 - Quick slots + three inventory sounds
- JRS Core only.
- Uses exactly three local MP3 assets inside the normal Inventory: open, close, and click.
- Removed the old hover sound and the generated weight-warning beep. Storage/robbery/other NUI surfaces remain silent.
- Fixed the open sound order so it plays after the inventory becomes visible; close sound plays before the normal inventory hides.
- Rebuilt Quick Slots 1-5: drag inventory items/weapons to assign, drag filled quick slots to swap, and right-click a quick slot to clear it.
- Quick-slot drag/drop is rebound after every inventory render, fixing slots that stopped accepting drops after a refresh.
- Hotbar state is validated client-side and server-side, deduplicated, repaired after legitimate stack-ID changes, and authoritatively synced back to the client.
- Active 1-5 input is checked every frame only while at least one quick slot is assigned; an empty hotbar keeps the long idle sleep.

## v1.6.8 - Compact connected / instant-open inventory
- JRS Core only.
- Restores the older compact panel dimensions while keeping Clothing, Inventory, Ground, Wallet and slots 1-5 connected.
- Opens immediately from the synchronized client cache; authoritative inventory/ground data refreshes in the background.
- The inventory sound set is local and scoped to the normal Inventory view only.
- Drag/drop uses shorter, low-cost feedback settings for smoother slot movement.


## v1.6.7 - Connected responsive inventory UI
- Matched the supplied wide reference layout: Clothing + Inventory + Ground in one aligned three-column composition.
- Wallet is attached below Clothing; Quick Slots are attached below Inventory.
- Hotbar keys are 1 through 5.
- Added a dedicated local menu-open sound (`html/sounds/ui_open.mp3`).
- Removed the visible NUI loading overlay; panels appear only when authoritative inventory data is ready.
- Kept all assets local and preserved JRS Core-only integration and server-authoritative transfer/security logic.
- Responsive single-scale layout keeps the complete UI visible on common 16:9, 16:10, ultrawide, 2K and 4K screens.
# jrs_inventory v1.6.5 - RedM Native Instant Open

This build removes `RegisterKeyMapping` from the inventory open flow and uses the RedM control hash (`Config.openinv`) directly. A dedicated one-control-per-frame watcher catches quick taps immediately, while the heavier inventory, ground, weapon, robbery, and social loops keep their low-frequency idle timers. `/inv` remains available as a fallback.

## Ultra-Low Idle Pass (v1.6.3)

This build targets the case where Resource Monitor showed more client time while the inventory was closed than while NUI was open. The remaining idle work was mostly control/hotbar/player/ground scanners and periodic ammo sampling.

- Empty hotbar: no hotbar control natives are called; the loop sleeps for 500ms.
- Active hotbar: polling reduced from 10ms to 25ms and only assigned slots are checked.
- Hotbar polling no longer allocates temporary Lua tables every cycle.
- Inventory/holster/lantern polling reduced to 50ms while closed and 250ms while NUI owns focus.
- Holster and lantern actions are edge-triggered so holding a key does not repeat expensive weapon natives.
- Ground scanner sleeps for 2 seconds when no drops exist, and reads player coordinates only once per scan when drops do exist.
- Ground scanning now uses distance tiers (far / near / prompt) instead of one aggressive idle rate.
- Robbery scanner sleeps longer when no other player is streamed and uses distance-tiered polling.
- Social/hostage scanner sleeps when no other player is streamed.
- Ammo save scans are skipped completely while no inventory weapon is equipped; active weapons keep the normal periodic save behavior.
- Character-not-ready states put all major client loops into long sleeps.

All timing values are configurable under `Config.Performance`.

## Lightweight Performance Pass (v1.6.2)

This build keeps the integrated robbery and on-screen Give player selector while reducing idle client/server/NUI work:

- Slow idle polling with fast polling only while a prompt/target is actually active.
- Player interaction prompts are cached instead of deleted/recreated continuously.
- Closest-player checks use squared distance and no longer run at hotbar frequency.
- Ground drop world props are diff/reused instead of all being destroyed/recreated after every drop change.
- Static item/weapon definition tables are sent once per player instead of on every inventory update.
- Inventory slot saves are debounced; only changed weapon slot rows are written.
- Dirty inventory background autosave defaults to 30 seconds; immediate safety saves remain in critical paths.
- Weapon serial maintenance defaults to 5 minutes instead of every minute.
- Item PNGs are optimized for CEF/NUI and dynamic item images use lazy async decoding.
- Runtime polling values are grouped under `Config.Performance`.


# JRS Inventory

A server-authoritative inventory system for RedM built for `jrs_core`, `oxmysql`, and a custom NUI interface.

Current resource version:

```text
1.6.38
```

## Stash Integration (1.6.31)

- Adds a server-local `storagePermission` gate used by `jrs_stashes` for Deposit Only / Withdraw Only / Full Access.
- Adds a server-local `storageTransaction` hook after successful item, currency, and weapon storage transfers for stash logs.
- Keeps all 1.6.30 slot-position, UI, performance, robbery, and inventory changes unchanged.

## Main Features

### Inventory and UI

- Item and weapon inventory with saved manual slot positions.
- Four empty inventory slots are always kept available after the last occupied slot.
- Compact western-style interface with a shared dark background.
- Separate panels for:
  - Player inventory.
  - Clothing.
  - Ground items.
  - Storage/chests.
  - Hotbar.
  - Money, gold, and dirty money.
- Money, gold, and dirty money do not consume inventory slots.
- Search box inside the inventory panel.
- Filter carousel with left/right arrows.
- Gray textured toolbar and information-panel styling.
- Open, close, and click UI sounds only.
- Expanded item and weapon information opens with one left-click on a slot and closes when the pointer leaves that slot.
- Missing item images automatically use the configured fallback image.

### Inventory Filters

The filter carousel includes:

```text
ALL
WEAPONS
AMMO
FOOD
DRINKS
SEEDS
TOOLS
DAMAGED
PERSONAL
```

Item filters use the item name, label, description, and category. The damaged filter uses item durability or weapon condition. The personal filter uses `Config.PersonalItems`.

### Search

The inventory search checks:

- Internal item name.
- Display label.
- Description.
- Category.
- Weapon model name.
- Weapon display label.

Search and category filters can be used together.

### Sorting and Slot Layout

Temporary sort modes:

```text
NAME
TYPE
WEIGHT
COUNT
WEAPONS
```

Toolbar controls:

- `SORT`: previews the next temporary sort mode.
- `MANUAL`: restores the player's previously saved manual slot layout.
- `SAVE`: permanently saves the current temporary sort result.
- `PIN`: keeps a selected item or weapon in its manual slot during temporary sorting.

`PIN` only affects sorting. It does not block dropping, giving, storage transfers, or item use.

### Stack Management

- Right-click an item stack and choose `Split Stack` to create a separate stack.
- Drag one identical stack onto another to merge them.
- Stack merging requires:
  - Matching item names.
  - Matching metadata.
  - Matching durability data.
- Split and merge operations are validated by the server and protected from replay requests.

### Multi-Select

The `MULTI` mode allows selecting several visible inventory entries.

Available actions:

- Select every currently visible item with `ALL`.
- Move selected entries into an open storage with `STORAGE`.
- Give selected entries to a nearby player with `GIVE`.
- Clear the selection with `CLEAR`.

Personal items are excluded from restricted multi-actions.

### Quick Storage Transfer

While a storage is open:

- `Shift + Click`: transfer the full stack or selected weapon.
- `Ctrl + Click`: transfer one item from a stack.

This works in both directions between the player inventory and storage.

### Expanded Information

Hovering an inventory item shows information beside its slot.

Items can show:

- Count.
- Unit weight.
- Total weight.
- Category.
- Durability.
- Personal-item status.

Weapons can show:

- Permanent weapon serial number.
- Ammo count.
- Condition.
- Dirt level.
- Equipped status.

## Item Metadata System

Item metadata is now server-authoritative and belongs to the exact inventory entry identified by `itemId`. It is persisted inside the character's `characters.inventory` JSON and is preserved when the item is given to another player, dropped on the ground, picked up, moved into storage, or withdrawn from storage.

The `items.metadata` database column is treated as a **default metadata template**, not as the live metadata of every owned item. Legacy values such as `0`, an empty string, or `NULL` are treated as no defaults. A JSON object can be used for defaults. Example:

```sql
UPDATE items
SET metadata = '{"durability":100,"quality":100}'
WHERE item = 'pickaxe';
```

The same default can be configured without changing the database:

```lua
Config.Metadata.ItemDefaults = {
    pickaxe = { durability = 100, quality = 100 },
}
```

When both are present, `Config.Metadata.ItemDefaults` overrides matching values from `items.metadata`. Runtime metadata passed while creating the item overrides both defaults.

Example trusted server-side item creation:

```lua
exports['jrs_inventory']:addItem(source, 'pickaxe', 1, {
    durability = 87,
    quality = 95,
    craftedBy = 'Blackwater Smith',
})
```

Supported metadata values are sanitized before they are stored. Configurable limits protect against oversized or deeply nested metadata payloads. Unsupported Lua value types are discarded.

### Durability

`durability` is a metadata value, not a separate database field. The inventory UI reads:

```text
metaData.durability
```

Valid durability is clamped between `Config.Metadata.DurabilityMin` and `Config.Metadata.DurabilityMax`. Items containing durability metadata are treated as unique instances, so multiple tools do not share one durability value. Existing durability stacks are automatically separated into individual entries when the inventory loads.

When `Config.Metadata.PreventUseWhenBroken = true`, any item whose metadata contains `durability = 0` is considered broken. Broken items remain in the inventory and may still be moved, dropped, stored, repaired, or inspected, but the server blocks their usable callback. This protection is server-authoritative, so calling the use event directly cannot bypass it. Items without a durability metadata key are unaffected.

Items without durability metadata correctly display `DURABILITY -`.

### Metadata Exports

These exports are server-side and operate on the exact `itemId` owned by the player:

```lua
local metadata = exports['jrs_inventory']:getMetadata(source, itemId)

exports['jrs_inventory']:setMetadata(source, itemId, { quality = 90 })
exports['jrs_inventory']:setMetadata(source, itemId, { quality = 90 }, true) -- replace table

exports['jrs_inventory']:setMetadataValue(source, itemId, 'craftedBy', 'Valentine Smith')
exports['jrs_inventory']:removeMetadataValue(source, itemId, 'craftedBy')

exports['jrs_inventory']:setDurability(source, itemId, 75)

local success, durability, broken = exports['jrs_inventory']:damageItem(source, itemId, 5)
local success, durability = exports['jrs_inventory']:repairItem(source, itemId, 10)
```

The older `getMetaTypeById` export remains available for compatibility.

### Metadata Safety and Stacking

- The client is never trusted to decide the authoritative metadata of an owned inventory entry.
- Storage deposits use the server copy of the item's metadata.
- Ground drops use the server copy of the item's metadata.
- Player-to-player transfers use the server copy of the giver's metadata.
- Normal stackable items merge only when their metadata is exactly equal.
- Metadata containing `durability`, `serial_number`, `instance_id`, or `instanceId` creates a unique item instance by default.
- `stackable = false` or `unique = true` can also force a unique instance.
- Metadata changes are saved immediately and the inventory UI is refreshed from server state.

### Weight System

The inventory status area displays:

- Current weight and maximum weight.
- Current owned-weapon count and maximum weapon count.
- A category weight breakdown when the weight row is clicked.

Weight alert levels are configurable:

- Warning state at the configured warning percentage.
- Critical state at the configured critical percentage.
- Optional warning sound when a threshold is crossed.

### Weapons

- Configurable default owned-weapon limit.
- Optional weapon limits by job or group.
- Weapon names are normalized to uppercase for database consistency.
- Case-insensitive weapon lookup prevents valid uppercase database weapons from being hidden.
- Duplicate weapons of the same model remain separate records by weapon ID.
- Every weapon has a permanent unique `serial_number` stored in `weaponloadout`.
- The same serial follows the weapon through player transfers, ground drops, and storage transfers.
- Existing weapons are automatically assigned serials during resource startup.
- A unique database index prevents two weapon rows from sharing the same serial.
- Serial mismatches or missing serials block protected weapon transfers and are written to security logs.
- Unknown/orphan database weapon names can optionally be ignored when calculating capacity.
- Weapon use, equip state, ammo, condition, dirt, components, and serial remain supported.
- Optional weapon-wheel cleanup on spawn/respawn returns inventory weapons to the bag state.

### Hotbar

- Five hotbar slots.
- Saved item and weapon assignments.
- Configurable control hashes.
- Use cooldown to prevent one key press from triggering repeatedly.
- Drag inventory entries to the hotbar.
- Click a hotbar slot inside the inventory UI to clear it.

### Storage

- Storage inventory uses fixed item-style slots.
- Storage search box at the top.
- Storage replaces/hides the ground panel while open.
- Item, weapon, money, and gold transfers are supported when allowed by configuration.
- Money and gold deposits/withdrawals use server-side balance, amount, storage-open, and capacity validation.
- Failed currency persistence is rolled back so the same transfer cannot silently duplicate currency.
- Capacity is validated by the server.
- Player and storage operation locks prevent concurrent conflicting transfers.
- Stored weapon entries keep the permanent weapon serial and are checked against the database row during withdrawal.

### Ground Drops

- Drop and pick up items, weapons, money, and gold.
- Configurable ground visibility and prompt distances.
- Configurable money and gold drop permissions.
- Optional persistent database ground drops.
- In-memory drops can be cleared periodically when persistence is disabled.

### Separate Currency Panel

Money and gold appear as two separate slots beside each other below the inventory.

Supported operations:

- Give currency to another player.
- Drop currency on the ground when enabled.
- Deposit currency into storage when enabled.
- Withdraw currency already stored in storage.

## Requirements

- RedM / Cfx.re server.
- `jrs_core`.
- `oxmysql`.
- `uiprompt`.
- `jrs_notify` when using the default configured notification resource.

Recommended start order:

```cfg
ensure oxmysql
ensure uiprompt
ensure jrs_core
ensure jrs_core  # notifications/input/menu are integrated here
ensure jrs_inventory
```

## Installation

1. Copy the `jrs_inventory` folder into the server resources directory.
2. Import the inventory database tables required by your server build.
3. Confirm resource names in `config/config.lua`.
4. Keep `Config.WeaponSerials.AutoMigrate = true` for automatic weapon-serial database migration.
5. Configure limits, permissions, UI thresholds, and personal items.
6. Configure Discord webhooks in `config/config_logs.lua`.
7. Add `ensure jrs_inventory` to `server.cfg`.
8. Restart the resource or the server.

```text
restart jrs_inventory
```

## Main Configuration

Configuration file:

```text
config/config.lua
```

### Inventory Limits

```lua
Config.Max_Items = 50
Config.Max_Weapons = 7
Config.CountUnknownWeaponsTowardLimit = false
```

`Config.Max_Items` is the maximum carried weight in kilograms.

`Config.CountUnknownWeaponsTowardLimit = false` prevents removed or unknown weapon rows from consuming the visible weapon capacity. Valid configured weapons still count normally.

### Weapon Limits by Job or Group

```lua
Config.WeaponLimitByJob = {
    default = 7,
    police = 10,
    sheriff = 10,
    admin = 10,
}
```

The script checks the player's job/group override and falls back to `Config.Max_Weapons` or `default`.

### Permanent Weapon Serial Numbers

```lua
Config.WeaponSerials = {
    Prefix = 'JRS',
    RandomLength = 8,
    AutoMigrate = true,
    MaintenanceIntervalMs = 60000,
}
```

- `Prefix`: prefix placed at the start of every generated serial.
- `RandomLength`: length of the random serial section.
- `AutoMigrate`: automatically adds and fills the `weaponloadout.serial_number` column.
- `MaintenanceIntervalMs`: checks for legacy weapons inserted by older external scripts without a serial.

On startup, the resource:

1. Adds `serial_number VARCHAR(64)` when missing.
2. Assigns a unique serial to existing weapons.
3. Repairs missing or duplicated legacy serials.
4. Adds the unique index `uniq_weapon_serial`.

New weapon creation is blocked when the serial migration fails, preventing untracked weapon records. The serial does not change when the weapon is given, dropped, stored, or withdrawn.

A manual fallback migration is included at:

```text
sql/weapon_serials.sql
```

Use the manual file only when automatic migration is disabled or your database account cannot alter tables.

### Personal Items

```lua
Config.PersonalItems = {
    "lockpick",
    -- "personal_radio",
}
```

Personal item names are case-insensitive.

Personal items can be used, arranged, pinned, and assigned to the hotbar, but cannot be:

- Dropped.
- Given to another player.
- Deposited into storage.

### UI Feature Settings

```lua
Config.InventoryUI = {
    DamagedThreshold = 30,
    WeightWarningPercent = 80,
    WeightCriticalPercent = 95,
    WeightWarningSound = true,
    MultiActionDelayMs = 500,
}
```

- `DamagedThreshold`: maximum condition percentage shown in the `DAMAGED` filter.
- `WeightWarningPercent`: warning threshold.
- `WeightCriticalPercent`: critical threshold.
- `WeightWarningSound`: enables or disables threshold sounds.
- `MultiActionDelayMs`: delay between secure multi-select actions.

### Currency Ground-Drop Permissions

```lua
Config.AllowMoneyGroundDrop = true
Config.AllowGoldGroundDrop = true
```

Set either option to `false` to block that currency from being dropped on the ground.

The restriction is validated by both client and server. Direct event calls are rejected by the server.

### Currency Storage-Deposit Permissions

```lua
Config.AllowMoneyToStorage = true
Config.AllowGoldToStorage = true
```

These options control deposits from the player into a storage.

When set to `false`:

- Depositing that currency is blocked.
- Direct event calls are rejected by the server.
- Currency already present inside storage can still be withdrawn.

### Distances

```lua
Config.PickupDistance = 7.0
Config.InteractionDistance = 2.0
Config.PlayerTransferDistance = 2.0
Config.GroundInteractionDistance = 1.0
Config.GroundPromptDistance = 0.7
```

- `PickupDistance`: search range for nearby ground drops/interactable entities.
- `InteractionDistance`: close-range interaction distance.
- `PlayerTransferDistance`: server-verified give distance.
- `GroundInteractionDistance`: ground-list visibility and pickup validation distance.
- `GroundPromptDistance`: distance at which the world pickup prompt appears.

### Inventory Command and Control

```lua
Config.openinv = 0xC1989F95
Config.OpenInventoryCommand = 'inv'
```

The inventory can be opened by the configured control or:

```text
/inv
```

### Hotbar Controls

```lua
Config.WeaponSlot1ControlHash = 0x1CE6D9EB
Config.WeaponSlot2ControlHash = 0x4F49CC4C
Config.WeaponSlot3ControlHash = 0x8F9F9E58
Config.WeaponSlot4ControlHash = 0xAB62E997
Config.WeaponSlot5ControlHash = 0xA1FDE2A6
Config.HotbarUseCooldownMs = 400
```

Additional weapon controls:

```lua
Config.WeaponHolsterControlHash = 0x52D29063
Config.LanternToggleControlHash = 0x53296B75
```

### Weight Movement Penalty

```lua
Config.WeightSpeedPenalty = {
    { threshold = 45, speed = 1.60 },
    { threshold = 42, speed = 1.70 },
    { threshold = 39, speed = 1.80 },
    { threshold = 35, speed = 1.90 },
    { threshold = 30, speed = 2.10 },
    { threshold = 27, speed = 2.20 },
}

Config.DefaultMoveSpeed = 0.0
Config.NormalMoveBlendRatio = 3.0
```

The highest matching threshold is selected. Positive `speed` values are RedM
maximum movement blend ratios; `0.0` means normal/unrestricted movement. The
active penalty is applied with `SET_PED_MAX_MOVE_BLEND_RATIO` and is restored to
`NormalMoveBlendRatio` as soon as carried weight falls below the first tier.

### Loading, Saving, and Respawn

```lua
Config.InventoryLoadTimeoutMs = 8000
Config.AutoSaveIntervalMs = 10000
Config.SaveThrottleMs = 100
Config.CharacterLoadDelayMs = 5000
Config.UnequipWeaponsOnSpawn = true
Config.RespawnWeaponCleanupDelayMs = 1500
```

### Ground-Drop Persistence

```lua
Config.SaveDrops = false
Config.DropCleanupIntervalMs = 300000
```

When `Config.SaveDrops` is `false`:

- Drops are kept in memory.
- Drops are cleared during the configured cleanup cycle.
- Drops are removed on resource/server restart.

When `Config.SaveDrops` is `true`, the script uses persistent database ground-drop storage supported by the resource.

### Resource Names

```lua
Config.NotificationResource = 'jrs_notify'
Config.CoreResource = 'jrs_core'
Config.MysqlResource = 'oxmysql'
```

Update these values if the resources are renamed.

### Dev Mode

```lua
Config.DevMode = false
Config.DevCommand = 'restartinventory'
Config.DevPermission = 'admin'
Config.DevReopenInventory = false
Config.Debug = false
```

Dev Mode allows an authorized group to reinitialize inventory state without restarting the full resource.

## UI Sound Configuration

File:

```text
html/config.js
```

```js
config.uiSounds = {
    enabled: true,
    clickEnabled: true,
    openEnabled: true,
    closeEnabled: true,
    clickVolume: 0.34,
    openVolume: 0.40,
    closeVolume: 0.38,
    clickCooldownMs: 45
}
```

The three sounds are scoped to the normal Inventory view only. Open and close use dedicated files; clicks apply to its controls and slots.

## Metadata Configuration

```lua
Config.Metadata = {
    Enabled = true,
    ApplyDatabaseDefaults = true,
    DefaultDurability = 100,
    DurabilityMin = 0,
    DurabilityMax = 100,
    PreventUseWhenBroken = true,
    MaxDepth = 5,
    MaxKeys = 32,
    MaxStringLength = 256,
    MaxEncodedLength = 2048,
    LogChanges = false,

    UniqueKeys = { 'durability', 'serial_number', 'instance_id', 'instanceId' },

    ItemDefaults = {
        -- pickaxe = { durability = 100 },
    },
}
```

Set `LogChanges = true` only when a Discord audit entry is needed for every metadata mutation; durability updates can otherwise generate a large number of logs.

## Anti-Duplication and Lag-Switch Protection

Configuration:

```lua
Config.AntiDupe = {
    Enabled = true,
    OperationReplayWindowMs = 120000,
    LockTimeoutMs = 30000,
    LegacyReplayWindowMs = 1500,
    LogBlockedActions = true,
    MaxViolationsBeforeDrop = 0,
}
```

Protected operations include:

- Item and weapon drops.
- Money and gold drops.
- Ground pickup.
- Player-to-player item transfers.
- Player-to-player weapon transfers.
- Player-to-player money and gold transfers.
- Deposits into storage.
- Withdrawals from storage.
- Quick storage transfers.
- Multi-select storage transfers.
- Stack splitting.
- Stack merging.

Security methods include:

- Server-authoritative ownership checks.
- Server-authoritative quantity checks.
- Item ID, weapon ID, and permanent weapon-serial validation.
- Metadata validation.
- Player-distance validation.
- Active-storage validation.
- Per-player operation locks.
- Per-storage operation locks.
- Unique client operation IDs.
- Replay-window rejection.
- Capacity checks.
- Two-sided database transactions where supported by the operation.
- Unique weapon-serial database constraint and serial matching across storage/ground references.
- Rollback/rejection when authoritative validation or persistence fails.
- Optional security violation tracking.

To remove a player automatically after repeated blocked operations:

```lua
Config.AntiDupe.MaxViolationsBeforeDrop = 5
```

A blocked operation does not always prove cheating. High latency, outdated client files, broken third-party scripts, or repeated clicks can also produce rejected requests. Review security logs before permanent punishment.

## Discord Logs

Configuration file:

```text
config/config_logs.lua
```

This file is loaded as a server script only. Keep webhook URLs out of shared scripts, client scripts, NUI JavaScript, and public repositories.

### Basic Configuration

```lua
DiscordLogConfig = {
    Enabled = true,
    Debug = false,

    BotName = "JRS Inventory Logs",
    AvatarUrl = "",

    Webhooks = {
        Default = "YOUR_DISCORD_WEBHOOK_URL",
        Items = "",
        Weapons = "",
        Ground = "",
        Storage = "",
        Currency = "",
        Usage = "",
        Layout = "",
        Security = "",
    },
}
```

A blank category webhook falls back to `Default`.

### Log Categories

```text
Items
Weapons
Ground
Storage
Currency
Usage
Layout
Security
Default
```

### Logged Operations

Depending on enabled options, logs can include:

- Trusted item add/remove operations.
- Item use.
- Item give operations.
- Weapon add/remove operations.
- Weapon give operations.
- Weapon equip, unequip, and cleaning.
- Item, weapon, money, and gold ground drops.
- Item, weapon, money, and gold ground pickups.
- Storage deposits and withdrawals.
- Currency transfers.
- Storage creation and size changes.
- Inventory clearing.
- Slot and hotbar layout changes.
- Replayed requests.
- Invalid ownership.
- Invalid quantities.
- Blocked personal-item actions.
- Blocked configuration-restricted currency actions.
- Other anti-duplication/security rejections.

Relevant logs can include:

- Server ID and player name.
- Character name and character ID.
- Job and group.
- Player identifiers when enabled.
- Item/weapon name, database ID, and permanent weapon serial.
- Quantity.
- Metadata.
- Target player.
- Storage ID.
- Drop ID and coordinates.
- Operation ID.
- Calling resource for trusted server exports/events.

### Optional High-Frequency Logs

```lua
DiscordLogConfig.LogLayoutChanges = false
DiscordLogConfig.LogWeaponStateChanges = true
DiscordLogConfig.LogStorageOpenClose = false
```

Slot and hotbar layout logs can be very frequent. Enable them only when needed.

### Security Role Mention

```lua
DiscordLogConfig.MentionRoleOnSecurity = true
DiscordLogConfig.SecurityRoleId = "DISCORD_ROLE_ID"
```

### Webhook Queue

```lua
DiscordLogConfig.QueueIntervalMs = 500
DiscordLogConfig.MaxQueuedLogs = 500
```

The queue sends embeds gradually to reduce Discord rate-limit errors.

### Logger Export

Other server resources can use the inventory logger:

```lua
exports["jrs_inventory"]:sendInventoryLog(
    "Items",
    "Custom Inventory Action",
    playerSource,
    {
        { name = "Item", value = "example_item", inline = true },
        { name = "Amount", value = "1", inline = true },
    },
    {
        description = "Optional description"
    }
)
```

## Player Usage

### Rearrange Slots

Drag an item or weapon to another slot. Manual slot changes are saved by the server.

### Use an Item or Weapon

- Double-click an item to use it.
- Double-click a weapon to equip/unequip it.
- The configured use key can also activate the hovered entry where supported.

### Search and Filter

- Type in the search box.
- Use the left/right arrows to cycle filters.
- Search results respect the currently selected filter.

### Temporary Sort

1. Press `SORT` to preview a mode.
2. Continue pressing `SORT` to cycle through sort modes.
3. Press `MANUAL` to restore the previous layout.
4. Press `SAVE` to persist the current temporary layout.

### Pin an Entry

1. Right-click an item or weapon.
2. Choose `Pin`.
3. The entry stays in its manual slot during temporary sorting.
4. Right-click and choose `Unpin` to remove the pin.

Pins are saved locally in the NUI browser storage for that client installation.

### Split a Stack

1. Right-click a stack containing more than one item.
2. Choose `Split Stack`.
3. Enter the amount to separate.
4. Confirm.

### Merge Stacks

Drag one item stack onto another identical stack. If the metadata and durability match, the server merges them.

### Multi-Select

1. Press `MULTI`.
2. Click inventory entries to select them.
3. Use `ALL`, `STORAGE`, `GIVE`, or `CLEAR`.

### Storage Quick Transfer

- `Shift + Click`: full transfer.
- `Ctrl + Click`: one item.

### Weight Details

Click the `WEIGHT` row to show or hide the category breakdown.

## Troubleshooting

### Inventory opens but icons are broken

- Confirm the image exists in:

```text
html/images/items/<item_name>.png
```

- Confirm filter images exist in:

```text
html/images/filter
```

- Confirm `fxmanifest.lua` includes the image directories.
- Restart `jrs_inventory` after adding images.

### Weapon count in the database is higher than the UI count

- Confirm weapon names are valid entries in `config/weapons.lua`.
- Weapon names are normalized to uppercase by the server.
- Check for orphan or removed weapon names.
- Check `Config.CountUnknownWeaponsTowardLimit`.
- Check the player's job/group override in `Config.WeaponLimitByJob`.

### The player cannot obtain another weapon

Check:

```lua
Config.Max_Weapons
Config.WeaponLimitByJob
Config.CountUnknownWeaponsTowardLimit
```

Also inspect `weaponloadout` for the correct `identifier`, `charidentifier`, and weapon rows.

### A weapon shows no serial or cannot be transferred

Check the server console for:

```text
[jrs_inventory] Weapon serial system ready.
```

Then verify the database:

```sql
SELECT id, name, serial_number
FROM weaponloadout
WHERE serial_number IS NULL OR serial_number = '';
```

Also verify that the unique index exists:

```sql
SHOW INDEX FROM weaponloadout WHERE Key_name = 'uniq_weapon_serial';
```

When automatic migration cannot alter the table, run `sql/weapon_serials.sql` once and restart `jrs_inventory`.

### Currency cannot be dropped

Check:

```lua
Config.AllowMoneyGroundDrop
Config.AllowGoldGroundDrop
```

### Currency cannot be deposited into storage

Check:

```lua
Config.AllowMoneyToStorage
Config.AllowGoldToStorage
```

These options do not block withdrawing currency already stored.

### A storage transfer is busy or blocked

Possible reasons:

- Another operation is using the player lock.
- Another player is using the same storage lock.
- The request operation ID was already processed.
- The player no longer has the source item.
- Storage capacity was exceeded.
- The client is trying to use a storage that is not registered as open.
- The player double-clicked or repeated the same action too quickly.

Check the `Security` Discord webhook and server console.

### Discord logs do not appear

1. Set `DiscordLogConfig.Enabled = true`.
2. Add a valid `Default` or category webhook.
3. Confirm the webhook still exists.
4. Confirm `config/config_logs.lua` loads before `server/logger.lua`.
5. Restart `jrs_inventory`.
6. Temporarily enable:

```lua
DiscordLogConfig.Debug = true
```

### UI sounds are too loud or too frequent

Adjust values in:

```text
html/config.js
```

Especially:

```js
openVolume
closeVolume
clickVolume
clickCooldownMs
```

## Security Notes

- Never trust item names, amounts, metadata, storage IDs, player IDs, weapon IDs, or weapon serials sent by the client.
- Create items and weapons only through trusted server events/exports.
- Keep regular database backups.
- Keep Discord webhooks server-only.
- Rotate leaked webhooks immediately.
- Test rapid clicking, disconnects, high ping, simultaneous storage access, and repeated packets on a staging server.
- Discord logs are an audit trail, not a replacement for server-side validation.
- No script can guarantee protection against every exploit or external program.

## Version History

### 1.5.0

- Rebuilt item metadata as a server-authoritative per-`itemId` system.
- Added safe metadata normalization, size/depth limits, and default metadata templates.
- Added support for JSON defaults from `items.metadata` and per-item defaults from config.
- Added full metadata get/set/update/remove server exports.
- Added durability set, damage, and repair exports.
- Durability values are clamped to configured limits and shown by the existing inventory detail UI.
- Durability and other unique metadata keys prevent unsafe stacking.
- Existing durability stacks are split into individual item instances during inventory load.
- Preserved authoritative metadata through storage, ground, pickup, and player transfers.
- Kept the legacy `getMetaTypeById` API for compatibility.

### 1.4.4

- Centered the player inventory on the screen in normal inventory mode.
- Moved the clothing panel to the left and the ground/drop panel to the right.
- Matched the clothing and ground/drop panel height to the player inventory.
- Restored a dedicated drag-to-drop area inside the ground panel.
- Added a balanced storage layout with the player inventory on the left and storage on the right.
- Automatically hides clothing and ground/drop panels while a storage container is open.

### 1.4.3

- Removed all use of `navigator.clipboard` from the NUI.
- Fixed RedM Permissions Policy warnings when copying weapon serials.
- Added two synchronous CEF-compatible serial-copy fallbacks.

### 1.4.0

- Added permanent unique serial numbers for every weapon row.
- Added automatic serial-column migration, legacy backfill, duplicate repair, and a unique database index.
- Preserved weapon serials through player, ground, and storage transfers.
- Added serial validation to protected weapon ownership changes and anti-duplication logs.
- Displayed the real weapon serial in expanded inventory information and search.
- Fixed money and gold storage deposit/withdraw confirmation handling.
- Fixed storage UI locks after cancelled, blocked, or completed currency operations.
- Added server-authoritative currency balance, capacity, replay, and storage-open validation.
- Added rollback handling when a currency storage write or core currency operation fails.

### 1.3.0

- Merged the current UI branch with anti-duplication protection and Discord logs.
- Added inventory search and filter carousel.
- Added ammo, damaged, and personal filters.
- Added temporary sorting, manual restore, save, and pin support.
- Added four permanent empty slots after occupied inventory entries.
- Added split-stack and stack-merge support.
- Added storage quick transfer and multi-select actions.
- Added expanded item/weapon information.
- Added category weight breakdown and weight alerts.
- Added local inventory UI sounds (now open, close, and click only).
- Added separate money and gold slots below the inventory.
- Added configurable money/gold ground-drop permissions.
- Added configurable money/gold storage-deposit permissions.
- Added uppercase weapon-name normalization and corrected visible weapon counting.
- Added gray textured toolbar and detail-panel styling.

## Inventory UI Sounds

The normal Inventory uses exactly three local MP3 assets: `ui_open.mp3`, `ui_close.mp3`, and `ui_click.mp3`. Storage, robbery, and other NUI surfaces stay silent. Volumes can be adjusted in `html/config.js`.

## Weapon Serial Copy

- Weapon serial numbers appear in the expanded weapon tooltip.
- Right-click a weapon and choose `Copy Serial` to copy its permanent serial number.
- Clipboard copying avoids the blocked Clipboard API entirely and uses a synchronous RedM NUI/CEF selection fallback, so no Permissions Policy warning is printed.

## Ground stability fixes

- Multiple items and weapons can be dropped at the same location; every drop remains protected by its unique server ID and operation lock.
- Ground slots refresh from the authoritative server list after drops and pickups.
- Dropping a Ground entry onto any inventory slot uses the exact drop ID and no longer removes the UI slot before server confirmation.
- Weapon drop flags are normalized when loaded from memory or the database.


### Automatic metadata by category

Metadata defaults can be assigned to a whole item category from `config/config.lua`. The default configuration now gives every item whose database `category` is `equipment` a durability value of `100` automatically:

```lua
Config.Metadata.CategoryDefaults = {
    equipment = { durability = 100 },
}
```

This applies to newly added equipment and to older equipment entries when the inventory is normalized. Existing durability values are preserved and are not reset to 100 on every inventory open. Per-item defaults in `ItemDefaults` can override the category defaults.


## Lightweight NUI performance

Version 1.5.4 reduces RedM NUI/CEF overhead without removing inventory functionality:

- Removed unused Muuri, Hammer, Web Animations, duplicate jQuery and external Animate.css loads.
- Removed synchronous per-slot image HEAD requests; missing item images now fall back to `badItem.png` asynchronously.
- Inventory and Ground update bursts are batched to one DOM rebuild per browser animation frame.
- Removed duplicate draggable initialization after the inventory table renders.
- Currency drag behavior initializes once instead of being destroyed/rebuilt on every refresh.
- Ground drop-zone droppable behavior initializes once; only recreated Ground item nodes receive new draggable handlers.
- UI sounds reuse one audio element per sound instead of preloading a larger pool.
- Large-panel entrance animations and the permanent critical-weight pulse are disabled to reduce CEF repaints.
- CSS containment isolates panel/grid painting.
- Screen metrics are sent only when needed and when dimensions change.
- Client gameplay polling sleeps longer while inventory NUI has focus.

Storage, Ground, drag/drop, hotbar, metadata, durability, weapon serials and currency features remain enabled.


## Dirty Money / Illegal Money

This build supports the jrs_core currency type `3` (`characters.dirtymoney`) as a third player currency.

- UI slot: `DIRTY MONEY`
- Give to nearby players.
- Ground drop / pickup with server-side validation.
- Storage deposit / withdrawal.
- Currency changes are refreshed immediately in the inventory UI.
- Discord inventory logs identify Dirty Money operations separately.

Configuration:

```lua
Config.AllowDirtyMoneyGroundDrop = true
Config.AllowDirtyMoneyToStorage = true
```

Dirty Money remains stored by `jrs_core` in `characters.dirtymoney`. Storage chests keep deposited Dirty Money in their existing JSON as `item = "dirtymoney"`; no extra inventory database column is required.

## Integrated Player Robbery / Search (v1.6.0)

Player robbery is now part of `jrs_inventory`; do **not** run `jrs_player_robbery` as a separate resource.

- Searchable target: dead or hogtied player within configured distance.
- Left panel: robber's live inventory.
- Right panel: searched player's live inventory.
- One-way drag/drop: target -> robber only.
- Supports items, weapons, cash, gold, and dirty money.
- Stack/currency amount selection uses the inventory NUI.
- Every transfer is revalidated server-side for distance, target state, session, ownership, quantity and anti-duplicate operation id.
- Optional protected zones, police-online requirement, police alert and night-only rules live in `config/robbery.lua`.
- Closing the inventory, moving too far away, target recovery/disconnect or session expiry closes the robbery session.

### server.cfg

Only the inventory resource is required for this system:

```cfg
ensure jrs_inventory
```

Remove/disable any old `ensure jrs_player_robbery` line.


## Integrated Give Player Selector (v1.6.1)

- Giving items, weapons, money, gold, or dirty money now uses an on-screen nearby-player marker selector.
- The selector is integrated directly into `jrs_inventory`; `mega_nplayerselector` is not required as a separate resource.
- Player markers show the server ID and follow the nearby player on screen.
- Selection range uses `Config.PlayerTransferDistance`, while the existing server-side transfer distance and ownership checks remain authoritative.
- Multi-select Give uses the same marker selector.
- The previous raw cursor/raycast give selector was removed.

## Secure Trade launcher (v1.6.35)

The standard inventory includes a `TRADE` button that launches the separate `jrs_trade` resource.

```lua
Config.Trade = {
    Enabled = true,
    Resource = 'jrs_trade',
}
```

- `Enabled = false`: the TRADE button is always hidden.
- `Enabled = true`: the button is shown only while the configured trade resource is actually `started`.
- If `jrs_trade` is missing, stopped, or restarted, the button updates automatically and no trade path remains active in the inventory.
- The TRADE button is shown only in the normal player inventory layout, not Storage or robbery/search layouts.



## Trade button compact search row (v1.6.37)

- Moves the secure TRADE launcher beside the inventory Search field.
- Shrinks Search to make room while keeping the filter carousel aligned on the same row.
- TRADE visibility is still controlled by `Config.Trade.Enabled` and the live `jrs_trade` resource state.
- Storage mode still hides the TRADE launcher.


## Trade row alignment + filter restore (v1.6.38)

- Makes the Search + TRADE + Filter row exactly match the width of the action row below.
- Restores the filter carousel to 178px so its icon and label remain visible.
- Narrow-screen rules reduce Search/TRADE space only; the filter remains full size.
