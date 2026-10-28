-- jrs_imapviewtool | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_imapviewtool | client
-- Developer tool: draws the map sections (IPL/IMAP) around you, colour-coded by whether they are loaded,
-- and lets you load or unload them one by one. NEVER run this on a live server.
--
--   /toggleIplView [distance]   start / stop the viewer
--   /iplDistanceView <distance> change the range while it runs
--   /requestAll, /removeAll     load / unload every section in range
--   /testIpl <hash>             flip one section on and off
-- While it runs: previous/next document page keys pick a section, the animal-interact key loads/unloads it.

local imapDataRaw = LoadResourceFile(GetCurrentResourceName(), 'imaps_with_coords_and_heading.lua')
local Data <const> = imapDataRaw and load(imapDataRaw)() or { IPL_LIST = {} }
local Core <const> = exports.jrs_core:GetCore()

local KEY_PREV <const>   = joaat('INPUT_DOCUMENT_PAGE_PREV')
local KEY_NEXT <const>   = joaat('INPUT_DOCUMENT_PAGE_NEXT')
local KEY_TOGGLE <const> = joaat('INPUT_INTERACT_ANIMAL')

local RED, GREEN, YELLOW = { 255, 0, 0 }, { 0, 255, 0 }, { 255, 255, 0 }

local viewer = {
    on = false,
    range = 20.0,
    near = {},          -- nearby sections, closest first: { hash, data, away }
    picked = 1,
}

print('^1jrs_imapviewtool is a developer tool: do not run it on a live server^7')

local function hex(hash) return ('0x%X'):format(hash) end

local function isLoaded(hash) return IsIplActiveByHash(hash) == 1 end

local function floating(x, y, z, text, colour, alpha, size)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end
    local scale = (1 / #(GetGameplayCamCoord() - vector3(x, y, z))) * size * ((1 / GetGameplayCamFov()) * 100)
    SetTextScale(0.0, 0.55 * scale)
    BgSetTextColor(colour[1], colour[2], colour[3], alpha)
    SetTextFontForCurrentCommand(6)
    BgDisplayText(VarString(10, 'LITERAL_STRING', text), sx, sy)
end

-- ------------------------------------------------------------------ keeping the list of nearby sections

local function refresh()
    local here = GetEntityCoords(PlayerPedId())
    local list = {}
    for hash, data in pairs(Data.IPL_LIST) do
        local away = #(here - vec3(data.x, data.y, data.z))
        if away <= viewer.range then list[#list + 1] = { hash = hash, data = data, away = away } end
    end
    table.sort(list, function(a, b) return a.away < b.away end)
    viewer.near = list
    viewer.picked = math.max(1, math.min(viewer.picked, #list))
end

local function step(by)
    local count = #viewer.near
    if count == 0 then return end
    viewer.picked = (viewer.picked - 1 + by) % count + 1
    local entry = viewer.near[viewer.picked]
    print(('Selected %d/%d  loaded: %s'):format(viewer.picked, count, tostring(isLoaded(entry.hash))))
end

local function flip(entry)
    if isLoaded(entry.hash) then
        RemoveIplByHash(entry.hash)
        print('Removed ' .. hex(entry.hash))
    else
        RequestIplByHash(entry.hash)
        print('Loaded ' .. hex(entry.hash))
    end
end

-- ------------------------------------------------------------------ the viewer

local function run()
    Core.NotifyObjective('IPL VIEWER IS ACTIVATED', 3000)
    Core.NotifyTip(('previous/next page to scroll, ~%s~ to load or unload the selected one'):format('INPUT_INTERACT_ANIMAL'), -1)

    CreateThread(function()
        while viewer.on do
            refresh()
            Wait(1000)
        end
    end)

    while viewer.on do
        local wait = 1000
        if #viewer.near > 0 then
            wait = 0
            local here = GetEntityCoords(PlayerPedId())

            for index, entry in ipairs(viewer.near) do
                local d = entry.data
                local colour = isLoaded(entry.hash) and GREEN or RED
                local selected = index == viewer.picked
                if selected then colour = YELLOW end

                DrawLine(here.x, here.y, here.z, d.x, d.y, d.z, colour[1], colour[2], colour[3], selected and 255 or 150)
                local label = selected
                    and ('[SELECTED %d/%d] | HASH: %s | NAME: %s'):format(index, #viewer.near, hex(entry.hash), d.hashname or 'Unknown')
                    or ('%d hash: %s name: %s'):format(index, hex(entry.hash), d.hashname or 'Unknown')
                floating(d.x, d.y, d.z, label, colour, selected and 255 or 150, 9)
            end

            if IsControlJustPressed(0, KEY_PREV) then step(-1) end
            if IsControlJustPressed(0, KEY_NEXT) then step(1) end
            if IsControlJustPressed(0, KEY_TOGGLE) and viewer.near[viewer.picked] then flip(viewer.near[viewer.picked]) end
        end
        Wait(wait)
    end

    Core.NotifyObjective('IPL VIEWER IS DEACTIVATED', 3000)
    UiFeedClearChannel(1, true, true)
end

-- ------------------------------------------------------------------ commands

TriggerEvent('chat:addSuggestion', '/toggleIplView', 'Toggles the ipl viewer', { { name = 'distance', help = 'range in metres (optional)' } })
TriggerEvent('chat:addSuggestion', '/iplDistanceView', 'Sets the range of the viewer', { { name = 'distance', help = 'range in metres' } })
TriggerEvent('chat:addSuggestion', '/requestAll', 'Loads every ipl in range', {})
TriggerEvent('chat:addSuggestion', '/removeAll', 'Unloads every ipl in range', {})
TriggerEvent('chat:addSuggestion', '/testIpl', 'Unloads an ipl, run again to load it', { { name = 'hash', help = 'hash of the ipl' } })

RegisterCommand('toggleIplView', function(_, args)
    viewer.on = not viewer.on
    if args[1] then viewer.range = tonumber(args[1]) or viewer.range end
    if viewer.on then run() end
end, false)

RegisterCommand('iplDistanceView', function(_, args)
    if not viewer.on then return print('^1The ipl viewer is not activated^7') end
    local range = tonumber(args[1])
    if not range then return print('^1You need to specify a distance^7') end
    viewer.range = range
end, false)

RegisterCommand('requestAll', function()
    for _, entry in ipairs(viewer.near) do RequestIplByHash(entry.hash) end
end, false)

RegisterCommand('removeAll', function()
    for _, entry in ipairs(viewer.near) do RemoveIplByHash(entry.hash) end
end, false)

local flipped = false
RegisterCommand('testIpl', function(_, args)
    local hash = tonumber(args[1])
    if not hash then return print('^1You need to give the hash of an ipl^7') end
    flipped = not flipped
    if flipped then RemoveIplByHash(hash) else RequestIplByHash(hash) end
    print((flipped and 'Removed ' or 'Loaded ') .. hex(hash))
end, false)
