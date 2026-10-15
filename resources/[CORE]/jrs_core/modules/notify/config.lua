-- ============================================================================
--  jrs_notify / config.lua
--  The single notification configuration for the whole JRS server.
--
--  jrs_notify is the ONLY resource that renders notifications. jrs_core,
--  jrs_ranch, jrs_farming, jrs_inventory, jrs_lib and every job script route
--  their messages here, so the values below decide the look, the branding, the
--  position and the sounds of every message a player ever sees.
-- ============================================================================

Config = Config or {}

Config.Notifications = {
    -- Master switch. When false, jrs_notify renders nothing and its exports
    -- return false, so callers fall back to their own native notification
    -- instead of silently losing the message.
    Enabled = true,

    -- Milliseconds a toast stays on screen when the caller gives no duration.
    DefaultDuration = 4500,

    -- Clamp, so a bad caller cannot pin a toast on screen forever or flash one
    -- for a single frame.
    MinimumDuration = 1200,
    MaximumDuration = 30000,

    -- Server brand. Every notification on the server is rendered by this NUI,
    -- so this one value decides the name shown on all of them. Set to '' to
    -- turn branding off entirely.
    Brand = 'JRS CORE',

    -- Append the calling resource to the brand, e.g. "JRS CORE | Mining".
    -- The source is taken from the export/event caller, not from the message.
    ShowSource = true,

    -- Where toasts dock. MenuOpenPosition is used while a script has told us a
    -- fullscreen menu is open (exports.jrs_core:SetMenuOpen(true)).
    ClosedPosition = 'top-right',
    MenuOpenPosition = 'top-right',

    -- Most toasts visible at once; the oldest is dropped past this.
    MaxVisible = 4,

    -- jrs_core also exposes a set of legacy helpers that used to draw the raw
    -- RDR2 notification feed: NotifyLeft, NotifyRightTip, NotifyTip, NotifyTop,
    -- NotifyObjective, NotifyCenter, NotifyBottomRight, NotifyAdvanced and the
    -- matching jrs_core:send*Notification net events. About two hundred call
    -- sites across the server still use them. With this true they render as the
    -- same unified toast as everything else, so the server has exactly one
    -- notification surface. Set it false to give those helpers their original
    -- Red Dead feed back - the toast API keeps working either way.
    RouteLegacyNativeFeed = true,

    Sound = {
        Enabled = true,
        Volume = 0.22,
        MinimumGapMs = 500,
        -- false = silent for that type.
        Files = {
            info    = false,
            success = 'sounds/collect_success.mp3',
            warning = 'sounds/collect_fail.mp3',
            error   = 'sounds/collect_fail.mp3',
            reward  = 'sounds/coins.mp3',
        }
    },

    -- Legacy DisplayLeftNotification(title, text, icon, duration) passes an
    -- item name as the icon. When this is set, jrs_notify tries that item's
    -- inventory artwork and quietly keeps the type glyph if it does not exist.
    ItemImagePath = 'nui://jrs_inventory/html/images/items/%s.png',
}

-- Words that decide the icon when a caller does not pass an explicit type.
-- Checked in order: error, then reward, then success; anything else is info.
Config.NotificationKeywords = {
    error = {
        'not enough', 'invalid', 'failed', 'denied', 'cannot', "can't", 'must ',
        'need ', 'cancel', 'not found', 'disabled', 'no space', 'no slots',
        'too far', 'wrong', 'error', 'missing', 'busy', 'already',
    },
    reward = {
        'sold', 'reward', 'withdrawn', 'deposited', 'earned', 'received',
        'payout', 'paid', 'bonus', 'you got',
    },
    success = {
        'success', 'placed', 'completed', 'complete', 'following', 'purchased',
        'bought', 'saved', 'added', 'done', 'unlocked', 'welcome',
    },
    warning = {
        'warning', 'careful', 'caution', 'about to', 'low ',
    },
}
