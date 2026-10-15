CoreNotifications = {}

-- JRS unified notifications ---------------------------------------------------
-- Every JRS script funnels its notifications through CoreNotifications.* (via
-- exports.jrs_core:getCoreApi() and the jrs_core:send* net events). Routing the
-- plain toast/tip styles through the jrs_notify NUI here makes the whole server
-- share one notification look (the farm/ranch toast) from a single place. If
-- jrs_notify is not started (or declines because notifications are disabled) we
-- fall through to the native RDR2 notification, so nothing is ever lost.
-- Branding ---------------------------------------------------------------
-- Every notification carries the server name plus the script that raised it, so
-- a player always knows where a message came from. The source is stamped by the
-- API wrapper (client/api.lua) right before it delegates here; Lua on the client
-- is cooperatively scheduled and never yields between those two statements, so a
-- second script cannot overwrite it mid-call.
CoreNotifications.Brand = 'JRS CORE'
CoreNotifications.ActiveSource = nil

-- jrs_metal_detector -> "Metal Detector".  jrs-Radio -> "Radio".
local PRETTY_OVERRIDES = {
    jrs_core = 'Core',
    jrs_metabolism = 'Metabolism',
    jrs_npc_outfits = 'NPC Outfits',
    jrs_idcard = 'ID Card',
    jrs_mdt = 'MDT',
    ['jrs-Radio'] = 'Radio',
}

local function prettyName(resource)
    resource = tostring(resource or '')
    if resource == '' then return '' end
    local lang = (type(JrsLang) == 'table' and type(JrsLang.Current) == 'function' and JrsLang.Current()) or 'ar'
    local clean = resource:gsub('^[Jj][Rr][Ss][_%-]', ''):gsub('[_%-]+', ' '):lower()
    if lang == 'ar' then
        if clean == 'metabolism' then return 'الأيض' end
        if clean == 'core' then return 'النظام' end
        if clean == 'inventory' then return 'الحقيبة' end
        if clean == 'clothing' then return 'الملابس' end
        if clean == 'barber' then return 'الحلاق' end
        if clean == 'stable' then return 'الإسطبل' end
        if clean == 'bathing' then return 'الاستحمام' end
        if clean == 'idcard' then return 'بطاقة الهوية' end
        if clean == 'weapons' or clean == 'weapon' then return 'الأسلحة' end
        if clean == 'hunting' then return 'الصيد' end
        if clean == 'farming' then return 'الزراعة' end
        if clean == 'mining' then return 'التعدين' end
        if clean == 'lumberjack' then return 'الحطاب' end
        if clean == 'police' then return 'الشرطة' end
        if clean == 'medical' or clean == 'doctors' then return 'الطبابة' end
        if clean == 'bounty' or clean == 'bountyhunter' then return 'بونتي هنتر' end
    end
    local override = PRETTY_OVERRIDES[resource]
    if override then return override end
    local name = resource:gsub('^[Jj][Rr][Ss][_%-]', ''):gsub('[_%-]+', ' ')
    return (name:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

-- The title used when a caller did not supply one of its own.
function CoreNotifications.Label(explicitTitle)
    local brand = tostring(CoreNotifications.Brand or '')
    local name = prettyName(CoreNotifications.ActiveSource)

    if explicitTitle ~= nil and tostring(explicitTitle) ~= '' then
        local t = tostring(explicitTitle)
        -- Do not brand something twice if a caller already did it.
        if t:find(brand, 1, true) then return t end
        return brand .. ' | ' .. t
    end

    if name == '' then return brand end
    return brand .. ' | ' .. name
end

-- Called by the API wrapper; harmless if a script calls it directly.
function CoreNotifications.SetSource(resource)
    CoreNotifications.ActiveSource = resource
end

-- The single seam every CoreNotifications.Notify* wrapper below passes through.
--
-- It used to return false unconditionally, which left jrs_core owning TWO
-- notification surfaces at once: the unified JRSToast NUI reached through
-- Core.Toast / Core.ShowNotification, and the raw RDR2 native feed reached
-- through NotifyRightTip / NotifyLeft / NotifyTop / NotifyObjective and the
-- jrs_core:send*Notification net events. Roughly two hundred call sites across
-- the server use the second group, so the same server showed two different
-- notification styles in two different screen positions depending only on which
-- helper a script happened to call - and no central setting could change that.
--
-- Routing here makes the unified toast the one renderer for both groups. Set
-- Config.Notifications.RouteLegacyNativeFeed = false to hand the legacy helpers
-- back to the RDR2 native feed.
local function notifyRoute(text, notifyType, duration, title)
    local settings = Config and Config.Notifications or nil
    if type(settings) ~= 'table' then return false end
    if settings.RouteLegacyNativeFeed == false then return false end
    if settings.Enabled == false then return false end
    if text == nil or tostring(text) == '' then return false end
    if type(JRSNotifyRender) ~= 'function' then return false end

    local ok, rendered = pcall(JRSNotifyRender, {
        text = text,
        notifyType = notifyType,
        duration = duration,
        title = title,
        source = CoreNotifications.ActiveSource,
    })
    return ok and rendered == true
end

CoreNotifications.NotifyLeft = function(title, subtitle, dict, icon, duration, color)
    title = CoreNotifications.Label(title)
    local hasSub = subtitle ~= nil and tostring(subtitle) ~= ''
    if notifyRoute(hasSub and subtitle or title, nil, duration, hasSub and title or nil) then return end
    CoreFunctions.LoadTexture(dict)
  
    local structConfig = DataView.ArrayBuffer(20 * 8)
    structConfig:SetInt32(0 * 8, tonumber(duration or 5000))
  
    local structDisplay = DataView.ArrayBuffer(10 * 8)
    structDisplay:SetInt32(0 * 8, 1)
    structDisplay:SetInt64(1 * 8, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", title or "")))
    structDisplay:SetInt64(2 * 8, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", subtitle or "")))
    structDisplay:SetInt64(3 * 8, 0)
    structDisplay:SetInt32(4 * 8, GetHashKey(dict or "hud_toasts"))
    structDisplay:SetInt32(5 * 8, GetHashKey(icon or "toast_catalogue"))
    structDisplay:SetInt32(6 * 8, GetHashKey(color or "COLOR_WHITE"))
    structDisplay:SetInt32(7 * 8, 1)
  
    Citizen.InvokeNative(0x26E87218390E6729, structConfig:Buffer(), structDisplay:Buffer(), 1, 1)
    Citizen.InvokeNative(0x4ACA10A91F66F1E2, dict)
end
  
CoreNotifications.NotifyTip = function(tipMessage, duration, title, notifyType)
    if notifyRoute(tipMessage, notifyType, duration, title) then return end
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
    structConfig:SetInt32(8 * 1, 0)
    structConfig:SetInt32(8 * 2, 0)
    structConfig:SetInt32(8 * 3, 0)
  
    local structData = DataView.ArrayBuffer(8 * 3)
    structData:SetUint64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", tipMessage)))
  
    Citizen.InvokeNative(0x049D5C615BD38BAD, structConfig:Buffer(), structData:Buffer(), 1)
end
  
CoreNotifications.NotifyTop = function(message, location, duration)
    if notifyRoute(message, nil, duration, location) then return end
    -- The "location" line doubles as the header here, so it carries the branding.
    location = CoreNotifications.Label(location)
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 5)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", location)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", message)))
  
    Citizen.InvokeNative(0xD05590C1AB38F068, structConfig:Buffer(), structData:Buffer(), 0, 1)
end
  
CoreNotifications.NotifyRightTip = function(tipMessage, duration, title, notifyType)
    if notifyRoute(tipMessage, notifyType, duration, title) then return end
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 3)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", tipMessage)))
  
    Citizen.InvokeNative(0xB2920B9760F0F36B, structConfig:Buffer(), structData:Buffer(), 1)
end
  
CoreNotifications.NotifyObjective = function(message, duration)
    if notifyRoute(message, nil, duration, nil) then return end
    Citizen.InvokeNative("0xDD1232B332CBB9E7", 3, 1, 0)
  
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 3)
    local strMessage = CreateVarString(10, "LITERAL_STRING", message)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(strMessage))
  
    Citizen.InvokeNative(0xCEDBF17EFCC0E4A4, structConfig:Buffer(), structData:Buffer(), 1)
end
  

CoreNotifications.NotifySimpleTop = function(title, subtitle, duration)
    title = CoreNotifications.Label(title)
    local hasSub = subtitle ~= nil and tostring(subtitle) ~= ''
    if notifyRoute(hasSub and subtitle or title, nil, duration, hasSub and title or nil) then return end
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 7)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", title)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", subtitle)))
  
    Citizen.InvokeNative(0xA6F4216AB10EB08E, structConfig:Buffer(), structData:Buffer(), 1, 1)
end
  
CoreNotifications.NotifyAdvanced = function(text, dict, icon, text_color, duration, quality, showquality)
    -- The texture dictionary, colour and quality star are game-native concepts
    -- with no equivalent in the shared toast. The message is what matters, and
    -- this native is only ever used for transactions, hence the reward style.
    if notifyRoute(text, 'reward', duration, CoreNotifications.Label()) then return end
    CoreFunctions.LoadTexture(dict)

    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
    structConfig:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", "Transaction_Feed_Sounds")))
    structConfig:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", "Transaction_Positive")))

    local structData = DataView.ArrayBuffer(8 * 10)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", text)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", dict)))
    structData:SetInt64(8 * 3, CoreFunctions.BigInt(GetHashKey(icon)))
    structData:SetInt64(8 * 5, CoreFunctions.BigInt(GetHashKey(text_color or "COLOR_WHITE")))
    if showquality then
      structData:SetInt32(8 * 6, quality or 1)
    end

    Citizen.InvokeNative(0xB249EBCB30DD88E0, structConfig:Buffer(), structData:Buffer(), 1)

    Citizen.InvokeNative(0x4ACA10A91F66F1E2, dict)
end

CoreNotifications.NotifyAvanced = function(text, dict, icon, text_color, duration, quality, showquality)
    CoreNotifications.NotifyAdvanced(text, dict, icon, text_color, duration, quality, showquality)
end

CoreNotifications.NotifyBasicTop = function(text, duration)
    if notifyRoute(text, nil, duration, nil) then return end
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 7)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", text)))
  
    Citizen.InvokeNative(0x7AE0589093A2E088, structConfig:Buffer(), structData:Buffer(), 1)
end
  
CoreNotifications.NotifyCenter = function(text, duration, text_color)
    if notifyRoute(text, nil, duration, nil) then return end
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 4)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", text)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(GetHashKey(text_color or "COLOR_PURE_WHITE")))
  
    Citizen.InvokeNative(0x893128CDB4B81FBB, structConfig:Buffer(), structData:Buffer(), 1)
end
  
CoreNotifications.NotifyBottomRight = function(text, duration)
    if notifyRoute(text, nil, duration, nil) then return end
    local structConfig = DataView.ArrayBuffer(8 * 7)
    structConfig:SetInt32(8 * 0, tonumber(duration or 3000))
  
    local structData = DataView.ArrayBuffer(8 * 5)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", text)))
  
    Citizen.InvokeNative(0x2024F4F333095FB1, structConfig:Buffer(), structData:Buffer(), 1)
end
  
CoreNotifications.NotifyFail = function(title, subtitle, duration)
    title = CoreNotifications.Label(title)
    local hasSub = subtitle ~= nil and tostring(subtitle) ~= ''
    -- Routing also removes the Wait() below from the caller's thread.
    if notifyRoute(hasSub and subtitle or title, 'error', duration, hasSub and title or nil) then return end
    local structConfig = DataView.ArrayBuffer(8 * 5)
  
    local structData = DataView.ArrayBuffer(8 * 9)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", title)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", subtitle)))
  
    local result = Citizen.InvokeNative(0x9F2CC2439A04E7BA, structConfig:Buffer(), structData:Buffer(), 1)
    Wait(duration or 3000)
    Citizen.InvokeNative(0x00A15B94CBA4F76F, result)
end
  
-- Deliberately NOT routed to jrs_notify. This is the fullscreen death card with
-- its own audio cue, a game-state screen rather than a message, and shrinking it
-- to a corner toast would lose the death presentation entirely.
CoreNotifications.NotifyDead = function(title, audioRef, audioName, duration)
    local structConfig = DataView.ArrayBuffer(8 * 5)
  
    local structData = DataView.ArrayBuffer(8 * 9)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", title)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", audioRef)))
    structData:SetInt64(8 * 3, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", audioName)))
  
    local result = Citizen.InvokeNative(0x815C4065AE6E6071, structConfig:Buffer(), structData:Buffer(), 1)
    Wait(duration or 3000)
    Citizen.InvokeNative(0x00A15B94CBA4F76F, result)
end
  
CoreNotifications.NotifyUpdate = function(title, message, duration)
    CoreNotifications.NotifyWarning(title, message, nil, nil, duration)
end
  

CoreNotifications.NotifyWarning = function(title, message, audioRef, audioName, duration)
    local hasMessage = message ~= nil and tostring(message) ~= ''
    if notifyRoute(hasMessage and message or title, 'warning', duration,
        CoreNotifications.Label(hasMessage and title or nil)) then return end
    local structConfig = DataView.ArrayBuffer(8 * 5)
  
    local structData = DataView.ArrayBuffer(8 * 9)
    structData:SetInt64(8 * 1, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", title)))
    structData:SetInt64(8 * 2, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", message)))
    structData:SetInt64(8 * 3, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", audioRef)))
    structData:SetInt64(8 * 4, CoreFunctions.BigInt(CreateVarString(10, "LITERAL_STRING", audioName)))
  
    local result = Citizen.InvokeNative(0x339E16B41780FC35, structConfig:Buffer(), structData:Buffer(), 1)
    Wait(duration or 3000)
    Citizen.InvokeNative(0x00A15B94CBA4F76F, result)
end
  
CoreNotifications.NotifyLeftRank = function(title, subtitle, dict1, texture, duration, color)
    title = CoreNotifications.Label(title)
    local hasSub = subtitle ~= nil and tostring(subtitle) ~= ''
    if notifyRoute(hasSub and subtitle or title, 'reward', duration, hasSub and title or nil) then return end
    CoreFunctions.LoadTexture(dict1)
    duration = duration or 5000
    local dict = GetHashKey(dict1 or "TOASTS_MP_GENERIC")
    local texture = GetHashKey(texture or "toast_mp_standalone_sp")
    local string1 = CreateVarString(10, "LITERAL_STRING", title)
    local string2 = CreateVarString(10, "LITERAL_STRING", subtitle)
  
    local struct1 = DataView.ArrayBuffer(8 * 8)
    local struct2 = DataView.ArrayBuffer(8 * 10)
  
    struct1:SetInt32(8 * 0, duration)
  
    struct2:SetInt64(8 * 1, CoreFunctions.BigInt(string1))
    struct2:SetInt64(8 * 2, CoreFunctions.BigInt(string2))
    struct2:SetInt64(8 * 4, CoreFunctions.BigInt(dict))
    struct2:SetInt64(8 * 5, CoreFunctions.BigInt(texture))
    struct2:SetInt64(8 * 6, CoreFunctions.BigInt(GetHashKey(color or "COLOR_WHITE")))
    struct2:SetInt32(8 * 7, 1)
    Citizen.InvokeNative(0x3F9FDDBA79117C69, struct1:Buffer(), struct2:Buffer(), 1, 1)
    Citizen.InvokeNative(0x4ACA10A91F66F1E2, dict1)
end