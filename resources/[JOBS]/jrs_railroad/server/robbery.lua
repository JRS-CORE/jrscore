---------------------------------------------------------------
-- TRAIN ROBBERY CONSEQUENCES
-- client/train_robbery.lua fires these two events but, until now,
-- nothing on the server listened for them: a "successful" robbery
-- never actually took any money, and a defeat never gave anything back.
---------------------------------------------------------------

-- Basic anti-spam: a client could otherwise fire robberyOccurred
-- repeatedly by hand to keep draining a company's register.
local ROBBERY_COOLDOWN_MS = 20000
local lastRobberyAt = {} -- [source] = GetGameTimer()

RegisterNetEvent('jrs_railroad:robberyOccurred', function(companyId)
    local src = source
    if not companyId or not Config.Companies[companyId] then return end

    local Player = JRS.Player(src)
    if not Player then return end

    local now = GetGameTimer()
    if lastRobberyAt[src] and (now - lastRobberyAt[src]) < ROBBERY_COOLDOWN_MS then return end
    lastRobberyAt[src] = now

    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then return end

    -- Only someone who could plausibly be driving one of this company's
    -- trains (its owner or an approved driver) can trigger a robbery
    -- payout for it. Without this, any player could fire this event for
    -- an arbitrary companyId to repeatedly drain a company they have no
    -- relation to, purely for griefing.
    local citizenid = Player.PlayerData.citizenid
    local isOwner = ownership.owner_citizenid == citizenid
    if not isOwner then
        local employee = DB.GetEmployeeByIds(companyId, citizenid)
        if not employee or employee.status ~= 'approved' then return end
    end

    local cfg = Config.TrainRobbery or {}
    local balance = tonumber(ownership.cash_register) or 0
    if balance <= 0 then return end

    local percent = cfg.RobberyTakePercent or 0.20
    local take = math.floor(balance * percent)
    take = math.max(cfg.RobberyTakeMin or 0, take)
    take = math.min(take, balance, cfg.RobberyTakeMax or take)

    if take <= 0 then return end

    DB.WithdrawFromCashRegister(companyId, take)
    print('[jrs_railroad] Train robbery: ' .. companyId .. ' lost $' .. take .. ' from cash register')

    Webhook.SendFields('robbery', 'Train Robbed', {
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'Amount Taken', '$' .. take },
        { 'Register Balance After', '$' .. (balance - take) },
    }, 'error')

    -- Let the owner know if they're online
    local ownerPlayer = JRS.PlayerByCharId(ownership.owner_citizenid)
    if ownerPlayer then
        local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', ownerPlayer.PlayerData.source, {
            title       = companyLabel,
            description = L('robbery_taken_notify', take),
            type        = 'error',
            duration    = 9000,
        })
    end
end)

RegisterNetEvent('jrs_railroad:robberyDefeated', function(companyId)
    local src = source
    local Player = JRS.Player(src)
    if not Player or not companyId then return end

    -- No direct cash reward for winning (avoids a "start robbery, win it"
    -- money loop) -- award a small amount of company XP instead.
    local xp = (Config.TrainRobbery and Config.TrainRobbery.DefeatXP) or 10
    DB.AddCompanyXP(Player.PlayerData.citizenid, companyId, xp)

    Webhook.SendFields('robbery', 'Outlaws Defeated', {
        { 'Player', GetPlayerFullName(Player) },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'XP Awarded', xp },
    }, 'success')
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastRobberyAt[src] = nil
end)
