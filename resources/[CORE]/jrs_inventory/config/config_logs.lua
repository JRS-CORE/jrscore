-- ============================================================================
-- JRS Inventory - Discord Logs (SERVER ONLY)
-- This file is kept inside the config folder for easier management.
-- It is loaded only as a server script and is not downloaded by players.
-- ============================================================================

DiscordLogConfig = {
    Enabled = false,
    Debug = false,

    BotName = "JRS Inventory Logs",
    AvatarUrl = "",

    -- A category uses its own webhook when filled. Otherwise it falls back to
    -- Default. You can use one webhook for everything or split categories.
    Webhooks = {
        Default = "",
        Items = "",
        Weapons = "",
        Ground = "",
        Storage = "",
        Currency = "",
        Usage = "",
        Layout = "",
        Security = "",
    },

    -- Discord embed colours (decimal format).
    Colors = {
        Items = 3447003,
        Weapons = 10181046,
        Ground = 15844367,
        Storage = 5763719,
        Currency = 16766720,
        Usage = 9807270,
        Layout = 8359053,
        Security = 15158332,
        Default = 5793266,
    },

    IncludePlayerIdentifiers = true,
    IncludeMetadata = true,
    MaxMetadataLength = 900,

    -- Layout saves can happen frequently while players rearrange slots.
    -- Enable only when you specifically need hotbar/slot audit logs.
    LogLayoutChanges = false,
    LogWeaponStateChanges = true,
    LogStorageOpenClose = false,

    -- Optional Discord role mention for blocked anti-dupe/security events.
    MentionRoleOnSecurity = false,
    SecurityRoleId = "",

    -- Sends queued embeds gradually to reduce Discord rate-limit errors.
    QueueIntervalMs = 500,
    MaxQueuedLogs = 500,
}
