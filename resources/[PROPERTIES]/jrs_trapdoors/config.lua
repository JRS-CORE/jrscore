-- ==========================================================================
--  JRS CORE  |  jrs_trapdoors  |  config.lua
--  trapdoors - synced trapdoors with an optional 4-digit passcode
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

Config.MoveDuration   = 2000  -- ms the open/close animation takes
Config.AutoCloseTime  = 30000 -- ms before an open trapdoor closes itself (0 = never)
Config.PlayerCooldown = 1000  -- ms between toggle requests per player
Config.StreamDistance = 100.0 -- distance at which clients look for / sync the prop

-- passcodes
Config.MaxCodeAttempts = 3     -- wrong guesses before a player is locked out of that door
Config.CodeLockoutTime = 60000 -- ms lockout after too many wrong guesses
Config.AdminResetCommand = 'resettrapdoorcode' -- /resettrapdoorcode <door id> (admins)

-- Each entry is one physical trapdoor. The key is its unique id.
-- rotations are pitch/roll/yaw in degrees (rotation order 2)
Config.Trapdoors = {
    rhodes_gunsmith = {
        label          = 'door_rhodes_gunsmith', -- locale key
        model          = 'p_gunsmithtrapdoor01x',
        closedPosition = vec3(1326.04, -1326.38, 76.92),
        openPosition   = vec3(1326.07, -1326.36, 76.98),
        closedRotation = vec3(0.0, 0.0, 165.0),
        openRotation   = vec3(-90.0, 0.0, 165.0),
        interactDistance = 3.0,
    },
    strawberry = {
        label          = 'door_strawberry',      -- locale key
        model          = 'p_trapdoor01x',
        closedPosition = vec3(-1790.744, -390.1504, 159.2894),
        openPosition   = vec3(-1790.744, -390.1504, 159.2894),
        closedRotation = vec3(0.0, 0.0, 145.0879),
        openRotation   = vec3(-90.0, 0.0, 145.0879),
        interactDistance = 3.0,
    },
    clothing_case = {
        label          = 'door_clothing_case',   -- locale key
        model          = 's_clothingcasedoor01x',
        closedPosition = vec3(2858.862793, -1194.916504, 47.991444),
        openPosition   = vec3(2858.862793, -1194.916504, 47.991444),
        closedRotation = vec3(0.0, 0.0, 94.999939),
        openRotation   = vec3(0.0, 0.0, 184.999939),
        interactDistance = 3.0,
    },
}
