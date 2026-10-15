-- ==========================================================================
--  JRS CORE  |  jrs_chat  |  config.lua
--  chat - character names, OOC, server announcements and spam protection
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

Config.MaxMessageLength = 256   -- characters; longer messages are cut off
Config.MessageCooldown  = 1000  -- ms between chat messages per player
-- SERVER PSA (chat:server:ServerPSA) from a client needs the JRS admin group
