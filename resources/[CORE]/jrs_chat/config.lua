-- ===================================================================
-- JRS CHAT | Configuration
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

Config = {}

-- Distance settings (in meters) for proximity chat
Config.Proximity = {
    Local = 15.0,    -- Standard local speech
    Shout = 35.0,    -- /s or /shout
    Whisper = 3.0,   -- /w or /whisper
    Me = 15.0,       -- /me roleplay actions
    Do = 15.0,       -- /do roleplay descriptions
}

-- Spam protection
Config.MessageCooldown = 750   -- Minimum milliseconds between messages
Config.MaxMessageLength = 250  -- Maximum character length per message

-- Auto-fadeout for inactive chat window (in milliseconds)
Config.FadeTimeout = 7000

-- Language fallback ('ar' or 'en')
Config.DefaultLanguage = 'ar'
