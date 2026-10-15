-- ==========================================================================
--  JRS CORE  |  jrs_track  |  shared/config.lua
--  horse race tracks - build checkpoint routes, save them and race
-- ==========================================================================

Config = {}


Config.Locale = 'en'                -- 'en' or 'ar'

-- ============================================================================
-- Discord Webhook Logging
-- ============================================================================
-- Posts race-lifecycle events (track create/delete, race start/finish,
-- admin setting changes, database errors) to Discord via embeds.
--
-- `url` is the fallback webhook used for any event that doesn't set its own
-- `url`. Leave an event's `url` as '' to use the fallback, or give it its
-- own webhook to split logs across channels (e.g. race results in one
-- channel, admin/error logs in another).
Config.Webhook = {
    enabled = false, -- master switch; everything below is inert until this is true
    url = '', -- e.g. 'https://discord.com/api/webhooks/XXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
    botName = 'JRS-Track',
    botAvatar = '', -- optional icon url shown as the webhook's avatar
    footer = 'JRS-Track Logs',
    -- Minimum time (ms) between two posts to the same webhook URL. Discord
    -- rate-limits webhooks; this keeps a burst of events (e.g. everyone
    -- finishing at once) from tripping it.
    minIntervalMs = 350,

    events = {
        --                     enabled   url (blank = use Config.Webhook.url)   colour (decimal)
        trackCreated    = { enabled = true,  url = '', color = 3066993  }, -- green
        trackDeleted    = { enabled = true,  url = '', color = 15158332 }, -- red
        raceStarted     = { enabled = true,  url = '', color = 3447003  }, -- blue
        raceFinished    = { enabled = true,  url = '', color = 15844367 }, -- gold
        raceReset       = { enabled = true,  url = '', color = 9807270  }, -- grey
        settingsChanged = { enabled = true,  url = '', color = 9936031  }, -- purple
        dbError         = { enabled = true,  url = '', color = 10038562 }, -- dark red
    }
}
