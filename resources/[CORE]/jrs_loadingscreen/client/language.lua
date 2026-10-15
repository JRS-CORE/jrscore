-- ---------------------------------------------------------------------------
-- Language chosen on the loading screen
--
-- The loading screen is the first thing a player sees, so it is the first place
-- the language is offered. web/scripts/script_lang.js posts the choice here.
--
-- jrs_core owns the value (users.language, per account) and everything
-- downstream reads it from there - the character screen included, which means a
-- player who picks Arabic while the world streams in never sees an English
-- character screen.
--
-- Two things make this reliable during connect, which is the awkward part:
--
--   * the choice is queued rather than sent once. Until jrs_core's client side
--     is up and the server has acknowledged, it is retried.
--   * the character screen still asks when the account has no stored choice, so
--     a player whose queued write never landed is not silently defaulted.
-- ---------------------------------------------------------------------------

local SUPPORTED = { en = true, ar = true }

local pending = nil
local delivered = nil
local lastServerSend = 0

local function normalize(value)
    if type(value) ~= 'string' then return nil end
    local code = value:lower():gsub('%s', '')
    if SUPPORTED[code] then return code end
    return nil
end

local function deliver()
    if not pending or pending == delivered then return end

    if GetResourceState('jrs_core') == 'started' then
        local ok = pcall(function()
            exports.jrs_core:SetLanguage(pending)
        end)
        if ok then
            delivered = pending
            return
        end
    end

    -- jrs_core's client export is not there yet; the server event is registered
    -- from the moment the resource boots, so this covers the early window.
    -- 2.8.0: at most one server send every 5s (jrs_core throttles at 1s and
    -- each accepted send is a DB write); the server's sync marks it delivered.
    local now = GetGameTimer()
    if now - lastServerSend < 5000 then return end
    lastServerSend = now
    TriggerServerEvent('jrs_core:language:set', pending)
end

-- jrs_core answers every accepted write with a sync; once it echoes our
-- choice back as stored, the retry loop has nothing left to do.
RegisterNetEvent('jrs_core:language:sync')
AddEventHandler('jrs_core:language:sync', function(language, chosen)
    if pending and chosen == true and normalize(language) == pending then
        delivered = pending
    end
end)

RegisterNUICallback('setLanguage', function(data, cb)
    local wanted = normalize(type(data) == 'table' and data.language or nil)
    if wanted and wanted ~= pending then
        pending = wanted
        delivered = nil
        lastServerSend = 0
        deliver()
    elseif wanted then
        deliver()
    end
    cb({ ok = wanted ~= nil })
end)

CreateThread(function()
    -- Retry for the first minute of the session. After that the player is well
    -- past the loading screen and the character screen owns the choice.
    for _ = 1, 30 do
        Wait(2000)
        if pending and pending ~= delivered then
            deliver()
        end
    end
end)
