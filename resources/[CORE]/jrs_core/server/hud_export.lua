-- =====================================================================
-- jrs_core - COMPACT HUD LAYOUT EXPORT (admin)
-- =====================================================================
-- Lets an admin arrange the compact HUD in game, then applies that exact
-- layout straight into Config.HudDefaultLayout in the LIVE config/config.lua
-- (no manual review/paste step - 2026-09-06). That table is what any
-- character with no saved layout row falls back to (see
-- server/hud_layout.lua's loadLayoutForSource).
--
-- The same generated table is also sent back to the client, which copies it
-- to the OS clipboard (see client/hud_layout.lua + html/hud-export-clipboard.js),
-- purely as a convenience - the live file is already updated by the time
-- that happens.
--
-- Applying config.lua's Config.HudDefaultLayout takes effect on the next
-- resource restart, same as any other Config.* edit.
-- =====================================================================

local LIVE_FILE = 'config/config.lua'

-- Global on purpose (not `local`) - hud_layout.lua's loadLayoutForSource and
-- server/api.lua's ApplyHudLayout both call this too, so the NUI knows
-- whether to show the Developer/"Export Defaults" section at all, on top of
-- the enforcement below.
function isAdmin(src)
    src = tonumber(src or 0)
    if not src or src <= 0 then return false end

    local ok, user = pcall(jrsCore.getUser, src)
    if not ok or not user then return false end

    return Config.IsAdminGroup(user.group) == true
end

local function notify(src, text)
    TriggerClientEvent('jrsCore:notify', tonumber(src), 'HUD EXPORT', tostring(text or ''), 'placeholder', 6000)
end

local function quote(value)
    return "'" .. tostring(value):gsub("'", "\\'") .. "'"
end

-- Turns the flat {elementId = {x,y,scale,visible,color}} shape the NUI/
-- sanitizeLayout use into just the `{...}` table literal (no assignment,
-- no header comment) - this is what gets spliced into Config.HudDefaultLayout
-- in the live file, so it must be a bare value, not a statement.
local function serialiseTable(layout)
    local names = {}
    for elementId in pairs(layout) do names[#names + 1] = elementId end
    table.sort(names)

    local out = {}
    out[#out + 1] = '{'

    for _, elementId in ipairs(names) do
        local point = layout[elementId]
        if type(point) == 'table' then
            out[#out + 1] = ('    %s = {'):format(elementId)
            if elementId == 'crosshair' then
                -- Not a positioned element - shape/colour only, no x/y/scale.
                out[#out + 1] = ('        shape = %s,'):format(tostring(math.floor(tonumber(point.shape) or 0)))
                out[#out + 1] = '        v = 2,'
                out[#out + 1] = ('        color = %s,'):format(quote(type(point.color) == 'string' and point.color or 'white'))
            else
                out[#out + 1] = ('        x = %s,'):format(tostring(tonumber(point.x) or 0))
                out[#out + 1] = ('        y = %s,'):format(tostring(tonumber(point.y) or 0))
                out[#out + 1] = ('        scale = %s,'):format(tostring(tonumber(point.scale) or 1.0))
                out[#out + 1] = ('        visible = %s,'):format(point.visible == false and 'false' or 'true')
                if type(point.color) == 'string' then
                    out[#out + 1] = ('        color = %s,'):format(quote(point.color))
                end
            end
            out[#out + 1] = '    },'
        end
    end

    out[#out + 1] = '}'
    return table.concat(out, '\n'), #names
end

-- Splices `assignment` (a full "Config.HudDefaultLayout = { ... }" statement)
-- over whatever Config.HudDefaultLayout currently is in the live config.lua,
-- leaving everything else in the file untouched. %b{} does a balanced-brace
-- match, so this is safe even though the table itself contains nested {}.
local function applyToLiveConfig(assignment)
    local raw = LoadResourceFile(GetCurrentResourceName(), LIVE_FILE)
    if not raw then
        return false, 'could not read ' .. LIVE_FILE
    end

    local newRaw, count = raw:gsub('Config%.HudDefaultLayout%s*=%s*%b{}', function() return assignment end, 1)
    if count == 0 then
        return false, 'could not find Config.HudDefaultLayout in ' .. LIVE_FILE
    end

    if not SaveResourceFile(GetCurrentResourceName(), LIVE_FILE, newRaw, -1) then
        return false, 'could not write ' .. LIVE_FILE
    end

    return true
end

RegisterNetEvent('jrs_core:hud:exportDefaults', function(layout)
    local src = source

    if not isAdmin(src) then
        notify(src, _Up(src, 'core_you_do_not_have_permission_to'))
        return
    end

    local clean = sanitizeLayout(layout)
    if not clean or next(clean) == nil then
        notify(src, _Up(src, 'core_could_not_read_your_current_hud'))
        return
    end

    local tableBody, count = serialiseTable(clean)
    local assignment = 'Config.HudDefaultLayout = ' .. tableBody

    local ok, err = applyToLiveConfig(assignment)
    if not ok then
        notify(src, _Up(src, 'core_export_failed') .. tostring(err))
        print(('^1[jrs_core] HUD export failed: %s^0'):format(tostring(err)))
        return
    end

    notify(src, (_Up(src, 'core_hud_defaults_applied_live_elements_copied')):format(count))
    print(('^2[jrs_core]^7 HUD defaults applied live by ^3%s^7 -> ^2%s^7 (%d elements)')
        :format(GetPlayerName(src) or src, LIVE_FILE, count))

    -- Hand the same table back so the admin also has it on the clipboard
    -- (html/hud-export-clipboard.js does the actual copy, client-side only).
    TriggerClientEvent('jrs_core:client:hudExportReady', src, assignment)
end)
