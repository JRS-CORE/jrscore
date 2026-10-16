-- jrs_mdt | client: paying fines at the clerks and keeping the player's list of open fines
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local fines = {}                                  -- the player's unpaid and overdue fines
local clerksReady = false

local CLERK_MODEL <const> = joaat('u_m_m_valsheriff_01')

local function total()
    local sum = 0
    for _, fine in ipairs(fines) do sum = sum + (fine.total_amount or 0) end
    return sum
end

-- "2 days 3 hours left" for a unix due time, and the seconds that remain
local function timeLeft(due)
    if type(due) ~= 'number' or due <= 0 then return locale('fines_unknown'), 0 end

    local seconds = due - GetCloudTimeAsInt()
    if seconds <= 0 then return locale('fines_overdue'), 0 end

    local days, hours = seconds // 86400, seconds % 86400 // 3600
    local minutes, rest = seconds % 3600 // 60, seconds % 60
    local function plural(n) return n == 1 and '' or 's' end

    if days > 0 then return locale('fines_amount_left', days, plural(days), hours, plural(hours)), seconds end
    if hours > 0 then return locale('fines_hours_left', hours, plural(hours), minutes), seconds end
    if minutes > 0 then return locale('fines_minutes_left', minutes, rest), seconds end
    return locale('fines_seconds_left', rest, plural(rest)), seconds
end

exports('hasUnpaidFines', function() return #fines > 0 end)
exports('getTotalFinesAmount', total)
exports('getPlayerFines', function() return fines end)

local function pushToPage()
    NUI.Message('playerFinesUpdated', { fines = fines, total = total() })
end

local function reload(after)
    JRS.TriggerCallback('jrs_mdt:server:getPlayerFines', function(list)
        fines = list or {}
        if after then after() end
    end)
end

local function drop(fineId)
    for i, fine in ipairs(fines) do
        if fine.id == fineId then table.remove(fines, i) break end
    end
    pushToPage()
end

RegisterNetEvent('jrs_mdt:client:updatePlayerFines', function(list)
    fines = list or {}
    pushToPage()
end)

RegisterNetEvent('jrs_mdt:client:finePaymentResult', function(data)
    MDTNotify({ title = locale('fines_title'), description = data.message, type = data.success and 'success' or 'error' })
end)

-- an officer's page and the player's own list both learn that a fine was paid
RegisterNetEvent('jrs_mdt:client:finePaid', function(data)
    drop(data.fineId)
    NUI.Message('finePaid', data)
end)

RegisterNetEvent('jrs_mdt:client:playerFinePaid', function(data) drop(data.fineId) end)
RegisterNetEvent('jrs_mdt:client:fineStatusUpdated', function(data) NUI.Message('fineStatusUpdated', data) end)

-- ------------------------------------------------------------------ the clerk

local function confirmPay(header, content, yes)
    return MDTConfirm({
        header = header, content = content, centered = true, cancel = true,
        labels = { confirm = yes, cancel = locale('fines_cancel') },
    }) == 'confirm'
end

-- the menu with every open fine and a "pay all" entry
local function showPayMenu(clerk)
    if #fines == 0 then
        return MDTNotify({ title = locale('fines_title'), description = locale('notification_no_unpaid_fines'), type = 'inform' })
    end

    local options = {}
    for _, fine in ipairs(fines) do
        options[#options + 1] = {
            title = locale('fines_fine_label'):format(fine.id) .. (fine.status == 'overdue' and locale('fines_fine_overdue') or ''),
            description = locale('fines_fine_detail', fine.total_amount, (timeLeft(fine.due_timestamp))),
            onSelect = function()
                if not confirmPay(locale('fines_pay_header'), locale('fines_pay_content', fine.id, fine.total_amount), locale('fines_pay_confirm')) then return end
                local result = JRS.Await('jrs_mdt:server:payFine', fine.id)
                if result and result.success then reload() end
            end,
        }
    end

    options[#options + 1] = {
        title = locale('fines_pay_all_title'),
        description = locale('fines_pay_all_total', total()),
        onSelect = function()
            if not confirmPay(locale('fines_pay_all_title'), locale('fines_pay_all_content', #fines, total()), locale('fines_pay_all_confirm')) then return end
            for _, fine in ipairs(fines) do JRS.Await('jrs_mdt:server:payFine', fine.id) end
            reload()
        end,
    }

    MDTRegisterContext({ id = 'fines_payment_menu', title = locale('fines_unpaid_title', clerk), options = options })
    MDTShowContext('fines_payment_menu')
end

local function checkFines()
    reload(function()
        if #fines == 0 then
            MDTNotify({ title = locale('fines_title'), description = locale('notification_no_unpaid_fines_clear'), type = 'success' })
        else
            MDTNotify({ title = locale('fines_title'), description = locale('notification_unpaid_fines_count', #fines, total()), type = 'warning' })
        end
    end)
end

local function spawnClerk(index, place)
    RequestModel(CLERK_MODEL)
    local waited = 0
    while not HasModelLoaded(CLERK_MODEL) and waited < 5000 do Wait(100) waited = waited + 100 end

    local name = place.name or locale('system_court_clerk')
    if not HasModelLoaded(CLERK_MODEL) then
        return print('[jrs_mdt] could not load the clerk ped for ' .. name)
    end

    local at = place.coords
    local ped = CreatePed(CLERK_MODEL, at.x, at.y, at.z - 1.0, place.heading or 0.0, false, true, true, true)
    SetModelAsNoLongerNeeded(CLERK_MODEL)
    SetRandomOutfitVariation(ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanPlayAmbientAnims(ped, true)
    SetPedCanRagdoll(ped, false)

    JRS.AddEntityTarget(ped, {
        {
            name = 'pay_fines_' .. index, icon = 'fa-solid fa-money-bill', label = locale('fines_pay_label'), distance = 2.5,
            canInteract = function() return #fines > 0 end,
            onSelect = function() reload(function() showPayMenu(name) end) end,
        },
        { name = 'check_fines_' .. index, icon = 'fa-solid fa-file-invoice-dollar', label = locale('fines_check_label'), distance = 2.5, onSelect = checkFines },
    })
end

local function spawnClerks()
    if clerksReady or not (Config.Fines and Config.Fines.enabled) then return end
    for i, place in ipairs(Config.Fines.paymentLocations or {}) do spawnClerk(i, place) end
    clerksReady = true
end

CreateThread(function()
    Wait(3000)
    reload()
    spawnClerks()
end)

RegisterNetEvent('jrs:SelectedCharacter', function()
    Wait(2000)
    reload()
end)

-- ------------------------------------------------------------------ the page

RegisterNuiCallback('getPlayerFines', function(_, cb) cb(JRS.Await('jrs_mdt:server:getPlayerFines') or {}) end)
RegisterNuiCallback('getUnpaidFinesCount', function(data, cb) cb(JRS.Await('jrs_mdt:server:getUnpaidFinesCount', data.citizenid) or 0) end)
RegisterNuiCallback('getCitizenFines', function(data, cb) cb(JRS.Await('jrs_mdt:server:getCitizenFines', data.citizenid) or {}) end)
RegisterNuiCallback('getAllUnpaidFines', function(_, cb) cb(JRS.Await('jrs_mdt:server:getAllUnpaidFines') or {}) end)

RegisterNuiCallback('payFine', function(data, cb)
    cb(JRS.Await('jrs_mdt:server:payFine', data.fineId) or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('markFinePaid', function(data, cb)
    cb(JRS.Await('jrs_mdt:server:markFinePaid', data.fineId) or { success = false, message = locale('notification_unknown_error') })
end)
