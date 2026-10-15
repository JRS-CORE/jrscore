-- JRS billing (server).

local function api() return exports.jrs_core:getCoreApi() end

local function character(source)
    local ok, user = pcall(function() return api().getUser(source) end)
    if ok and type(user) == "table" and type(user.getUsedCharacter) == "table" then
        return user.getUsedCharacter
    end
end

local function notify(source, text)
    pcall(function() api().NotifyObjective(source, text, 5000) end)
end

local function canBill(char)
    local minGrade = char and BillingConfig.Jobs[char.job]
    return minGrade ~= nil and (tonumber(char.jobgrade) or 0) >= minGrade
end

local function log(text)
    if BillingConfig.Webhook == "" then return end
    PerformHttpRequest(BillingConfig.Webhook, function() end, "POST", json.encode({
        username = "JRS Billing",
        embeds = { { title = "Bill", description = text, color = 16711680 } },
    }), { ["Content-Type"] = "application/json" })
end

RegisterCommand(BillingConfig.Command, function(source)
    if source <= 0 then return end
    if not canBill(character(source)) then
        return notify(source, _Up(source, "billing_not_allowed"))
    end
    TriggerClientEvent("jrs_billing:client:open", source, BillingConfig.MaxBillAmount)
end, false)

AddEventHandler("jrs_core:server:characterReady", function(source, char)
    if canBill(char) then
        TriggerClientEvent("chat:addSuggestion", source, "/" .. BillingConfig.Command, _Up(source, "billing_suggestion"), {})
    end
end)

local busy, lastBill = {}, {}
RegisterNetEvent("jrs_billing:server:send", function(data)
    local src = source
    if busy[src] or type(data) ~= "table" then return end
    -- one bill every 10 s per biller (no draining a player with spam)
    if lastBill[src] and os.time() - lastBill[src] < 10 then return end
    lastBill[src] = os.time()
    busy[src] = true
    local ok, err = pcall(function()
        local biller = character(src)
        if not canBill(biller) then return notify(src, _Up(src, "billing_not_allowed")) end

        local target = math.floor(tonumber(data.playerId) or 0)
        local amount = math.floor((tonumber(data.amount) or 0) * 100 + 0.5) / 100
        local reason = tostring(data.reason or ""):gsub("[<>]", ""):sub(1, 120)
        if target == src then return notify(src, _Up(src, "billing_self")) end
        if amount <= 0 or amount > BillingConfig.MaxBillAmount or amount ~= amount then
            return notify(src, _Up(src, "billing_bad_amount", BillingConfig.MaxBillAmount))
        end

        local targetChar = GetPlayerName(target) and character(target)
        if not targetChar then return notify(src, _Up(src, "billing_not_found")) end
        if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) > BillingConfig.MaxDistance then
            return notify(src, _Up(src, "billing_too_far"))
        end
        if (tonumber(targetChar.money) or 0) < amount then
            return notify(src, _Up(src, "billing_no_money"))
        end

        if targetChar.removeCurrency(target, 0, amount) == false then
            return notify(src, _Up(src, "billing_no_money"))
        end
        if BillingConfig.GiveMoneyToBiller then biller.addCurrency(src, 0, amount) end

        local billerName = ("%s %s"):format(biller.firstname or "", biller.lastname or "")
        local targetName = ("%s %s"):format(targetChar.firstname or "", targetChar.lastname or "")
        if BillingConfig.GiveReceipt then
            local date = os.date("%d/%m/") .. BillingConfig.ServerYear
            exports.jrs_inventory:addItem(target, BillingConfig.ReceiptItem, 1, {
                description = _Up(target, "billing_receipt", amount, billerName, date, reason),
            })
        end
        notify(src, _Up(src, "billing_sent", targetName, amount))
        notify(target, _Up(target, "billing_received", amount, billerName, reason))
        log(("**%s** (%s) billed **%s** (%s) $%s - %s"):format(billerName, GetPlayerName(src), targetName, GetPlayerName(target), amount, reason))
    end)
    busy[src] = nil
    if not ok then print("^1[jrs_billing] " .. tostring(err) .. "^0") end
end)

AddEventHandler("playerDropped", function() busy[source] = nil; lastBill[source] = nil end)
