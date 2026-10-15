-- ---------------------------------------------------------------------------
-- JRS shared translation runtime
--
-- This file is the single translation engine for every resource on the server.
-- It is NOT meant to be copied around: a resource pulls it in from jrs_core
-- with
--
--     shared_script '@jrs_core/shared/jrs_lang.lua'
--     shared_scripts { 'locales/*.lua' }
--
-- Because every Cfx resource runs its own Lua state, each resource that loads
-- this file gets its own private `Locales` table, its own cache and its own
-- state-bag handler. Nothing is shared between resources except the player's
-- chosen language, which jrs_core publishes on the player state bag.
--
-- What a resource gets:
--
--   Locales['en'] = { key = "text" }    -- filled by locales/en.lua
--   Locales['ar'] = { key = "نص" }      -- filled by locales/ar.lua
--
--   _U(key, ...)        client: the local player's language
--                       server: the server default language (console / logs)
--   _Up(src, key, ...)  server: the language of player `src`
--                       client: same as _U (src ignored)
--   _UE(key, ...)       Legacy prompt helper: follows the local player's
--                       language on clients; English for pre-login server text.
--   _UL(lang, key, ...) an explicit language, for building NUI payloads.
--
-- Every lookup falls back: requested language -> English -> the key itself.
-- A missing key therefore shows the key, never a "Translation does not exist"
-- banner in the middle of the UI.
-- ---------------------------------------------------------------------------

Locales = Locales or {}

JrsLang = JrsLang or {}

-- The languages the server ships. Adding one is: add the code here, drop a
-- locales/<code>.lua into every resource, and add the button in the character
-- screen language picker.
JrsLang.Supported = {
    { code = 'en', label = 'English',  native = 'English', rtl = false },
    { code = 'ar', label = 'Arabic',   native = 'العربية', rtl = true  },
}

JrsLang.Default  = 'ar'
JrsLang.Fallback = 'en'

-- The player state-bag key jrs_core writes the chosen language to. Replicated,
-- so the client reads it off LocalPlayer.state and any server script reads it
-- off Player(src).state with no event round trip.
JrsLang.StateKey = 'jrsLanguage'

local supportedSet = {}
local rtlSet = {}
for _, entry in ipairs(JrsLang.Supported) do
    supportedSet[entry.code] = true
    if entry.rtl then rtlSet[entry.code] = true end
end

--- Coerce anything into a supported language code, or nil when it is not one.
function JrsLang.Normalize(value)
    if type(value) ~= 'string' then return nil end
    local code = value:lower():gsub('%s', '')
    -- Tolerate the historic file-name style codes ("en_lang", "pt-br", "en-US").
    code = code:gsub('_lang$', '')
    code = code:gsub('[-_].*$', '')
    if supportedSet[code] then return code end
    return nil
end

function JrsLang.IsSupported(value)
    return JrsLang.Normalize(value) ~= nil
end

function JrsLang.IsRTL(value)
    return rtlSet[JrsLang.Normalize(value) or JrsLang.Default] == true
end

--- The list the character screen renders. Plain data, safe to hand to NUI.
function JrsLang.List()
    local out = {}
    for _, entry in ipairs(JrsLang.Supported) do
        out[#out + 1] = {
            code   = entry.code,
            label  = entry.label,
            native = entry.native,
            rtl    = entry.rtl == true,
        }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Current language
-- ---------------------------------------------------------------------------

if IsDuplicityVersion() then
    -- Server: read the state bag jrs_core wrote. The state bag itself is a
    -- cheap local lookup, but the framework's Player(src) call in front of it
    -- is not - a caller that resolves this once per item (an inventory of a
    -- few hundred items, say) pays that cost that many times over. Cache per
    -- source and drop the entry the moment that player's language actually
    -- changes, so this never reads stale.
    local ofCache = {}

    function JrsLang.Of(source)
        local src = tonumber(source)
        if not src or src <= 0 then return JrsLang.Default end
        local cached = ofCache[src]
        if cached then return cached end
        local ok, player = pcall(Player, src)
        if not ok or not player or not player.state then return JrsLang.Default end
        local lang = JrsLang.Normalize(player.state[JrsLang.StateKey]) or JrsLang.Default
        ofCache[src] = lang
        return lang
    end

    AddStateBagChangeHandler(JrsLang.StateKey, nil, function(bagName, _, _)
        local src = tonumber(bagName:match('^player:(%d+)$'))
        if src then ofCache[src] = nil end
    end)

    AddEventHandler('playerDropped', function()
        ofCache[tonumber(source)] = nil
    end)

    function JrsLang.Current()
        return JrsLang.Default
    end
else
    local cached = nil

    -- Explicit sync can arrive before state-bag replication.
    AddEventHandler('jrs_core:language:changed', function(language)
        cached = JrsLang.Normalize(language)
    end)

    function JrsLang.Current()
        local ok, state = pcall(function() return LocalPlayer.state end)
        if ok and state and state[JrsLang.StateKey] then
            local live = JrsLang.Normalize(state[JrsLang.StateKey])
            if live then
                cached = live
                return live
            end
        end
        if cached then return cached end
        return JrsLang.Default
    end

    function JrsLang.Of(_)
        return JrsLang.Current()
    end

    -- Drop the cache the moment jrs_core republishes the language. This handler
    -- runs once inside every resource that loads this file, so it deliberately
    -- does NOT broadcast an event - jrs_core/client/language.lua fires the one
    -- global 'jrs_core:language:changed' that resources listen to, and a
    -- broadcast from here would multiply it by the number of resources.
    AddStateBagChangeHandler(JrsLang.StateKey, nil, function(bagName, _, value)
        if bagName ~= ('player:' .. GetPlayerServerId(PlayerId())) then return end
        cached = JrsLang.Normalize(value)
    end)
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

-- string.format only when the call site actually passed arguments: a lot of
-- strings legitimately contain a bare "%" (percentages, "100% cotton") and
-- formatting those with no arguments throws.
local function apply(text, ...)
    if select('#', ...) == 0 then return text end
    local ok, formatted = pcall(string.format, text, ...)
    if ok then return formatted end
    return text
end

local function lookup(lang, key)
    if type(key) ~= 'string' then return nil end
    local table1 = Locales[lang]
    if table1 ~= nil then
        local value = table1[key]
        if value ~= nil then return value end
    end
    if lang ~= JrsLang.Fallback then
        local table2 = Locales[JrsLang.Fallback]
        if table2 ~= nil then
            local value = table2[key]
            if value ~= nil then return value end
        end
    end
    return nil
end

--- Translate into an explicit language.
function _UL(lang, key, ...)
    local code = JrsLang.Normalize(lang) or JrsLang.Default
    local text = lookup(code, key)
    if text == nil then return tostring(key) end
    return apply(text, ...)
end

--- Translate for whoever is going to read it right here.
--- Client: the local player. Server: the server default (console, logs, chat
--- printed to no one in particular). Use _Up when a player is the audience.
function _U(key, ...)
    if type(key) == 'string' then
        local lowerKey = key:lower()
        if lowerKey:sub(1, 7) == 'prompt_' or lowerKey:sub(1, 5) == 'blip_' or lowerKey:sub(1, 5) == 'draw_' or lowerKey:sub(1, 3) == '3d_' or lowerKey:find('prompt') or lowerKey:find('group') or lowerKey:find('board') then
            return _UL('en', key, ...)
        end
    end
    return _UL(JrsLang.Current(), key, ...)
end

--- Translate for a specific player. Server-side counterpart of _U.
function _Up(source, key, ...)
    if type(key) == 'string' then
        local lowerKey = key:lower()
        if lowerKey:sub(1, 7) == 'prompt_' or lowerKey:sub(1, 5) == 'blip_' or lowerKey:sub(1, 5) == 'draw_' or lowerKey:sub(1, 3) == '3d_' or lowerKey:find('prompt') or lowerKey:find('group') or lowerKey:find('board') then
            return _UL('en', key, ...)
        end
    end
    return _UL(JrsLang.Of(source), key, ...)
end

--- Prompt & Blip helper: ALWAYS returns English to prevent RedM 3D text/prompt/blip boxes (مربعات).
function _UE(key, ...)
    return _UL('en', key, ...)
end

--- Bilingual helper for connection / deferral messages: returns English and Arabic together.
function _UBilingual(key, ...)
    local enText = _UL('en', key, ...)
    local arText = _UL('ar', key, ...)
    if type(enText) == 'string' and type(arText) == 'string' and arText ~= '' and arText ~= key and arText ~= enText then
        local cleanEn = enText:gsub('^\n+', ''):gsub('\n+$', '')
        local cleanAr = arText:gsub('^\n+', ''):gsub('\n+$', '')
        return cleanEn .. "\n(" .. cleanAr .. ")"
    end
    return tostring(enText or key)
end

--- Connection & deferral helper: returns bilingual (English + Arabic) text.
function _UConn(key, ...)
    return _UBilingual(key, ...)
end


--- Helper to sanitize any native 3D/prompt/blip string so Arabic bytes don't cause boxes (مربعات) in RedM native rendering.
function JrsLang.SanitizeNativeText(text, fallback)
    if type(text) ~= 'string' or text == '' then
        return (type(fallback) == 'string' and fallback ~= '') and fallback or ''
    end
    -- Detect UTF-8 Arabic bytes (0xD8..0xDB => \216..\219)
    if text:find('[\216-\219]') then
        -- First try mapping known Arabic locale strings to English equivalents
        if Locales and Locales['ar'] and Locales['en'] then
            for k, v in pairs(Locales['ar']) do
                if type(v) == 'string' and v == text then
                    local enVal = Locales['en'][k]
                    if type(enVal) == 'string' and enVal ~= '' then
                        return enVal
                    end
                end
            end
        end
        local stripped = text:gsub('[\216-\219][\128-\191]', ''):gsub('^%s+', ''):gsub('%s+$', '')
        if not stripped:find('%w%w') then
            return (type(fallback) == 'string' and fallback ~= '') and fallback or 'Interact'
        end
        return stripped
    end
    return text
end

-- ---------------------------------------------------------------------------
-- Item names
-- ---------------------------------------------------------------------------
--
-- Item labels are not in a locale pack - there are over a thousand of them and
-- they are data the owner edits, so the translation lives in the `items` table
-- itself (items.label_ar, items.descriptions_ar) and jrs_inventory resolves it.
--
-- Every resource loads this file, so every resource gets the resolver for free:
--
--     _UItem(src, 'bear_pelt')          -- server: that player's language
--     _UItem(src, item, row.label)      -- with the English already in hand
--
-- On the client there is no item table to read, so the fallback (or the item
-- name) is returned unchanged - a client-side label should have come from the
-- server already resolved.

local function inventoryReady()
    return GetResourceState('jrs_inventory') == 'started'
end

--- The item's name as player `source` should read it.
---
--- `fallback` is the label the caller already had. When it is something other
--- than the item's own English label - a store owner's custom product name, a
--- reward's own wording - it is kept exactly as typed; only the stock English
--- name is swapped for its translation.
function _UItem(source, itemName, fallback)
    local name = tostring(itemName or '')
    if name == '' then return tostring(fallback or '') end
    if IsDuplicityVersion() and inventoryReady() then
        local given = (fallback ~= nil and fallback ~= '') and tostring(fallback) or nil
        if given then
            local okEn, english = pcall(function()
                return exports.jrs_inventory:GetItemLabelEnglish(name)
            end)
            if okEn and type(english) == 'string' and english ~= '' and english ~= given then
                return given
            end
        end
        local ok, label = pcall(function()
            return exports.jrs_inventory:GetItemLabel(source, name)
        end)
        if ok and type(label) == 'string' and label ~= '' then return label end
    end
    if fallback ~= nil and fallback ~= '' then return tostring(fallback) end
    return name
end

--- Same for the item's description.
function _UItemDesc(source, itemName, fallback)
    local name = tostring(itemName or '')
    if name == '' then return tostring(fallback or '') end
    if IsDuplicityVersion() and inventoryReady() then
        local ok, text = pcall(function()
            return exports.jrs_inventory:GetItemDescription(source, name)
        end)
        if ok and type(text) == 'string' and text ~= '' then return text end
    end
    if fallback ~= nil and fallback ~= '' then return tostring(fallback) end
    return name
end

--- Hand a whole language table to NUI in one go.
function JrsLang.Table(lang)
    local code = JrsLang.Normalize(lang) or JrsLang.Default
    local base = Locales[JrsLang.Fallback] or {}
    local wanted = Locales[code] or {}
    local out = {}
    for key, value in pairs(base) do out[key] = value end
    if code ~= JrsLang.Fallback then
        for key, value in pairs(wanted) do out[key] = value end
    end
    return out
end

---------------------------------------------------------------------------
-- Global NUI Focus Gate Hook (Client-side)
-- Intercepts SetNuiFocus and SetNuiFocusKeepInput across all resources loading
-- jrs_lang, automatically notifying jrs_hud:busy to hide the HUD, metabolism,
-- and minimap whenever any script UI opens, and restoring them when it closes.
---------------------------------------------------------------------------
if not IsDuplicityVersion() then
    local rawSetNuiFocus = SetNuiFocus
    local rawSetNuiFocusKeepInput = SetNuiFocusKeepInput

    SetNuiFocus = function(hasFocus, hasCursor)
        local caller = GetCurrentResourceName()
        if rawSetNuiFocus then
            rawSetNuiFocus(hasFocus == true, hasCursor == true)
        end

        -- Skip HUD editors so players can arrange their HUD without it hiding
        if caller == 'jrs_core' or caller == 'jrs_metabolism' then
            return
        end

        if hasFocus == true then
            TriggerEvent('jrs_hud:busy', caller, true)
            if LocalPlayer and LocalPlayer.state then
                LocalPlayer.state:set('uiOpen', true, false)
            end
        else
            TriggerEvent('jrs_hud:busy', caller, false)
            if LocalPlayer and LocalPlayer.state then
                LocalPlayer.state:set('uiOpen', false, false)
            end
        end
    end

    if rawSetNuiFocusKeepInput then
        SetNuiFocusKeepInput = function(keepInput)
            local caller = GetCurrentResourceName()
            rawSetNuiFocusKeepInput(keepInput == true)
            if caller ~= 'jrs_core' and caller ~= 'jrs_metabolism' then
                if keepInput == true then
                    TriggerEvent('jrs_hud:busy', caller, true)
                    if LocalPlayer and LocalPlayer.state then
                        LocalPlayer.state:set('uiOpen', true, false)
                    end
                end
            end
        end
    end

    AddEventHandler('onClientResourceStop', function(stoppedResource)
        if stoppedResource == GetCurrentResourceName() then
            if stoppedResource ~= 'jrs_core' and stoppedResource ~= 'jrs_metabolism' then
                TriggerEvent('jrs_hud:busy', stoppedResource, false)
            end
        end
    end)

    -- -----------------------------------------------------------------------
    -- JRS Global Blip Pool Protection (fwuiBlip Safeguard)
    -- Protects all 82+ resources importing jrs_lang from overflowing the 920-slot pool.
    -- -----------------------------------------------------------------------
    local _myResourceBlips = {}
    local _myResourceName = GetCurrentResourceName()

    local rawBlipAddForCoords = BlipAddForCoords
    local rawAddBlipForCoord = AddBlipForCoord
    local rawBlipAddForEntity = BlipAddForEntity
    local rawAddBlipForEntity = AddBlipForEntity
    local rawBlipAddForRadius = BlipAddForRadius
    local rawAddBlipForRadius = AddBlipForRadius
    local rawBlipAddForArea = BlipAddForArea
    local rawAddBlipForArea = AddBlipForArea
    local rawRemoveBlip = RemoveBlip

    local function _trackBlip(handle)
        if handle and handle ~= 0 then
            _myResourceBlips[handle] = true
            if GetResourceState('jrs_core') == 'started' then
                pcall(exports['jrs_core'].RegisterBlip, _myResourceName, handle)
            end
        end
        return handle
    end

    local function _canCreate()
        if GetResourceState('jrs_core') == 'started' then
            local ok, can = pcall(exports['jrs_core'].CanCreateBlip, _myResourceName)
            if ok and can == false then
                return false
            end
        end
        return true
    end

    if type(rawBlipAddForCoords) == 'function' then
        BlipAddForCoords = function(...)
            if not _canCreate() then return 0 end
            local h = rawBlipAddForCoords(...)
            return _trackBlip(h)
        end
    end

    if type(rawAddBlipForCoord) == 'function' then
        AddBlipForCoord = function(...)
            if not _canCreate() then return 0 end
            local h = rawAddBlipForCoord(...)
            return _trackBlip(h)
        end
    end

    if type(rawBlipAddForEntity) == 'function' then
        BlipAddForEntity = function(...)
            if not _canCreate() then return 0 end
            local h = rawBlipAddForEntity(...)
            return _trackBlip(h)
        end
    end

    if type(rawAddBlipForEntity) == 'function' then
        AddBlipForEntity = function(...)
            if not _canCreate() then return 0 end
            local h = rawAddBlipForEntity(...)
            return _trackBlip(h)
        end
    end

    if type(rawBlipAddForRadius) == 'function' then
        BlipAddForRadius = function(...)
            if not _canCreate() then return 0 end
            local h = rawBlipAddForRadius(...)
            return _trackBlip(h)
        end
    end

    if type(rawAddBlipForRadius) == 'function' then
        AddBlipForRadius = function(...)
            if not _canCreate() then return 0 end
            local h = rawAddBlipForRadius(...)
            return _trackBlip(h)
        end
    end

    if type(rawBlipAddForArea) == 'function' then
        BlipAddForArea = function(...)
            if not _canCreate() then return 0 end
            local h = rawBlipAddForArea(...)
            return _trackBlip(h)
        end
    end

    if type(rawAddBlipForArea) == 'function' then
        AddBlipForArea = function(...)
            if not _canCreate() then return 0 end
            local h = rawAddBlipForArea(...)
            return _trackBlip(h)
        end
    end

    if type(rawRemoveBlip) == 'function' then
        RemoveBlip = function(handle)
            if handle and handle ~= 0 then
                _myResourceBlips[handle] = nil
                if GetResourceState('jrs_core') == 'started' then
                    pcall(exports['jrs_core'].UnregisterBlip, handle)
                end
                return rawRemoveBlip(handle)
            end
        end
    end

    if type(N_0x554d9d53f696d002) == 'function' then
        local rawN_0x554d9d53f696d002 = N_0x554d9d53f696d002
        N_0x554d9d53f696d002 = function(...)
            if not _canCreate() then return 0 end
            local h = rawN_0x554d9d53f696d002(...)
            return _trackBlip(h)
        end
    end

    if type(N_0x23f74c2fda6e7c61) == 'function' then
        local rawN_0x23f74c2fda6e7c61 = N_0x23f74c2fda6e7c61
        N_0x23f74c2fda6e7c61 = function(...)
            if not _canCreate() then return 0 end
            local h = rawN_0x23f74c2fda6e7c61(...)
            return _trackBlip(h)
        end
    end

    if type(N_0x45f13b7e0a15c880) == 'function' then
        local rawN_0x45f13b7e0a15c880 = N_0x45f13b7e0a15c880
        N_0x45f13b7e0a15c880 = function(...)
            if not _canCreate() then return 0 end
            local h = rawN_0x45f13b7e0a15c880(...)
            return _trackBlip(h)
        end
    end

    if type(N_0x45f13b7e0a15c742) == 'function' then
        local rawN_0x45f13b7e0a15c742 = N_0x45f13b7e0a15c742
        N_0x45f13b7e0a15c742 = function(...)
            if not _canCreate() then return 0 end
            local h = rawN_0x45f13b7e0a15c742(...)
            return _trackBlip(h)
        end
    end

    if type(N_0x01a65c13d10e0100) == 'function' then
        local rawN_0x01a65c13d10e0100 = N_0x01a65c13d10e0100
        N_0x01a65c13d10e0100 = function(handle, ...)
            if handle and handle ~= 0 then
                _myResourceBlips[handle] = nil
                if GetResourceState('jrs_core') == 'started' then
                    pcall(exports['jrs_core'].UnregisterBlip, handle)
                end
            end
            return rawN_0x01a65c13d10e0100(handle, ...)
        end
    end

    local BLIP_CREATE_HASHES = {
        [0x554D9D53F696D002] = true,
        [0x23F74C2FDA6E7C61] = true,
        [0x45F13B7E0A15C880] = true,
        [0x45F13B7E0A15C742] = true,
        [0x5C9E84BD74780D61] = true,
        ["0x554d9d53f696d002"] = true,
        ["0x554D9D53F696D002"] = true,
        ["0x23f74c2fda6e7c61"] = true,
        ["0x23F74C2FDA6E7C61"] = true,
        ["0x45f13b7e0a15c880"] = true,
        ["0x45F13B7E0A15C880"] = true,
        ["0x45f13b7e0a15c742"] = true,
        ["0x45F13B7E0A15C742"] = true,
    }
    local BLIP_REMOVE_HASHES = {
        [0x01A65C13D10E0100] = true,
        ["0x01a65c13d10e0100"] = true,
        ["0x01A65C13D10E0100"] = true,
    }

    local function _isBlipCreateNative(h)
        if BLIP_CREATE_HASHES[h] then return true end
        if type(h) == 'string' then
            local n = tonumber(h)
            if n and BLIP_CREATE_HASHES[n] then return true end
        end
        return false
    end

    local function _isBlipRemoveNative(h)
        if BLIP_REMOVE_HASHES[h] then return true end
        if type(h) == 'string' then
            local n = tonumber(h)
            if n and BLIP_REMOVE_HASHES[n] then return true end
        end
        return false
    end

    -- -----------------------------------------------------------------------
    -- JRS Global Blip Native Font Protection (Anti-Tofu / مربعات Prevention)
    -- Intercepts blip naming so Arabic characters never cause □□□□ on the map.
    -- -----------------------------------------------------------------------
    local function _sanitizeBlipString(text, fallback)
        if type(text) ~= 'string' or text == '' then
            return text
        end
        if type(JrsLang) == 'table' and type(JrsLang.SanitizeNativeText) == 'function' then
            return JrsLang.SanitizeNativeText(text, fallback or 'Location')
        end
        if text:find('[\216-\219]') then
            local stripped = text:gsub('[\216-\219][\128-\191]', ''):gsub('^%s+', ''):gsub('%s+$', '')
            if stripped:find('%w') then return stripped end
            return fallback or 'Location'
        end
        return text
    end

    if type(SetBlipNameFromPlayerString) == 'function' then
        local rawSetBlipNameFromPlayerString = SetBlipNameFromPlayerString
        SetBlipNameFromPlayerString = function(blip, text)
            if not blip or blip == 0 then return end
            return rawSetBlipNameFromPlayerString(blip, _sanitizeBlipString(text))
        end
    end

    if type(SetBlipName) == 'function' then
        local rawSetBlipName = SetBlipName
        SetBlipName = function(blip, text)
            if not blip or blip == 0 then return end
            return rawSetBlipName(blip, _sanitizeBlipString(text))
        end
    end

    if type(N_0x9cb1a1623062f402) == 'function' then
        local rawN_0x9cb1a1623062f402 = N_0x9cb1a1623062f402
        N_0x9cb1a1623062f402 = function(blip, text)
            if not blip or blip == 0 then return end
            return rawN_0x9cb1a1623062f402(blip, _sanitizeBlipString(text))
        end
    end

    if type(CreateVarString) == 'function' then
        local rawCreateVarString = CreateVarString
        CreateVarString = function(p0, p1, p2, ...)
            if p0 == 10 and type(p2) == 'string' and p2:find('[\216-\219]') then
                p2 = _sanitizeBlipString(p2)
            end
            return rawCreateVarString(p0, p1, p2, ...)
        end
    end

    if type(Citizen) == 'table' and type(Citizen.InvokeNative) == 'function' then
        local rawInvokeNative = Citizen.InvokeNative
        Citizen.InvokeNative = function(hash, ...)
            if _isBlipCreateNative(hash) then
                if not _canCreate() then return 0 end
                local h = rawInvokeNative(hash, ...)
                return _trackBlip(h)
            elseif _isBlipRemoveNative(hash) then
                local handle = ...
                if handle and handle ~= 0 then
                    _myResourceBlips[handle] = nil
                    if GetResourceState('jrs_core') == 'started' then
                        pcall(exports['jrs_core'].UnregisterBlip, handle)
                    end
                end
                return rawInvokeNative(hash, ...)
            elseif hash == 0x9CB1A1623062F402 or hash == -715615614 then
                local blip, text = ...
                return rawInvokeNative(hash, blip, _sanitizeBlipString(text))
            end
            return rawInvokeNative(hash, ...)
        end
    end

    local function _cleanupMyResourceBlips(stoppedResource)
        if stoppedResource == _myResourceName then
            for handle in pairs(_myResourceBlips) do
                if DoesBlipExist(handle) then
                    pcall(rawRemoveBlip or RemoveBlip, handle)
                end
            end
            _myResourceBlips = {}
        end
    end

    AddEventHandler('onResourceStop', _cleanupMyResourceBlips)
    AddEventHandler('onClientResourceStop', _cleanupMyResourceBlips)
end

