-- jrs_trader | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- JRS kit: small helpers on top of jrs_core / jrs_inventory / jrs_progressbar.
-- Shared by the JRS scripts so they all talk to jrs_core / jrs_inventory the same way.
-- Needs `jrs_api 'ext'` in the fxmanifest.
JRS = {}
JRS.IsServer = IsDuplicityVersion()
JRS.Core = exports.jrs_core:GetCore()

-- Locales[lang][key]; Config.Language picks the language, English is the fallback.
function L(key, ...)
    local lang = Locales and (Locales[Config and Config.Language or 'en'] or Locales.en) or {}
    local text = lang[key] or (Locales and Locales.en and Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, text, ...)
        if ok then return out end
    end
    return text
end

-- English text for game prompts, blips and 3D text: the game font has no
-- Arabic glyphs, so those always use the English locale.
function LE(key, ...)
    local text = (Locales and Locales.en and Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, text, ...)
        if ok then return out end
    end
    return text
end

function JRS.TableLength(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

if JRS.IsServer then
    ---------------------------------------------------------------- server
    function JRS.Notify(src, text, ms) JRS.Core.NotifyRightTip(src, tostring(text), ms or 4000) end

    function JRS.Char(src)
        local user = JRS.Core.getUser(tonumber(src))
        return user and user.getUsedCharacter or nil
    end

    function JRS.CharId(src)
        local c = JRS.Char(src)
        return c and c.charIdentifier or nil
    end

    function JRS.Name(src)
        local c = JRS.Char(src)
        if not c then return GetPlayerName(src) or ('#' .. tostring(src)) end
        return ('%s %s'):format(c.firstname or '', c.lastname or '')
    end

    function JRS.Job(src)
        local c = JRS.Char(src)
        return c and c.job or nil, c and tonumber(c.jobGrade) or 0
    end

    function JRS.Group(src)
        local user = JRS.Core.getUser(tonumber(src))
        return user and user.getGroup or 'user'
    end

    function JRS.IsAdmin(src)
        local g = JRS.Group(src)
        return g == 'admin' or g == 'superadmin' or g == 'owner' or IsPlayerAceAllowed(src, 'command')
    end

    -- fn(source, ...) returns the reply (several values allowed); runs as a JRS callback
    function JRS.Callback(name, fn)
        JRS.Core.Callback.Register(name, function(source, cb, ...)
            local r = table.pack(pcall(fn, source, ...))
            if not r[1] then
                print(('^1[%s] callback %s: %s^7'):format(GetCurrentResourceName(), name, tostring(r[2])))
                return cb({ __jrs = true, n = 0 })
            end
            local out = { __jrs = true, n = r.n - 1 }
            for i = 2, r.n do out[i - 1] = r[i] end
            cb(out)
        end)
    end

    -- cb-style server callback: fn(source, cb, ...) and cb(...) any number of values
    function JRS.CreateCallback(name, fn)
        JRS.Callback(name, function(src, ...)
            local p = promise.new()
            fn(src, function(...) p:resolve(table.pack(...)) end, ...)
            local r = Citizen.Await(p)
            return table.unpack(r, 1, r.n)
        end)
    end

    function JRS.Count(src, item) return tonumber(exports.jrs_inventory:getItemCount(src, nil, item)) or 0 end
    function JRS.Has(src, item, n) return JRS.Count(src, item) >= (n or 1) end
    function JRS.CanCarry(src, item, n) return exports.jrs_inventory:canCarryItem(src, item, n or 1) == true end

    function JRS.Add(src, item, n, meta)
        n = n or 1
        if not JRS.CanCarry(src, item, n) then return false end
        return exports.jrs_inventory:addItem(src, item, n, meta or {}) == true
    end

    function JRS.Remove(src, item, n) return exports.jrs_inventory:subItem(src, item, n or 1) == true end

    function JRS.Usable(item, fn)
        exports.jrs_inventory:registerUsableItem(item, function(data)
            fn(data.source, data.item, data)
        end)
    end

    function JRS.ItemLabel(item)
        local def = exports.jrs_inventory:getItemDB(item)
        return def and def.label or item
    end

    function JRS.CloseInventory(src) exports.jrs_inventory:closeInventory(src) end

    -- currency 0 = cash, 1 = gold
    function JRS.Money(src, currency)
        local c = JRS.Char(src)
        if not c then return 0 end
        return tonumber(currency == 1 and c.gold or c.money) or 0
    end

    function JRS.TakeMoney(src, amount, currency)
        amount = tonumber(amount) or 0
        if amount <= 0 then return true end
        local c = JRS.Char(src)
        if not c or JRS.Money(src, currency) < amount then return false end
        c.removeCurrency(currency or 0, amount)
        return true
    end

    function JRS.GiveMoney(src, amount, currency)
        amount = tonumber(amount) or 0
        local c = JRS.Char(src)
        if not c or amount <= 0 then return false end
        c.addCurrency(currency or 0, amount)
        return true
    end

    function JRS.Near(src, coords, dist)
        local ped = GetPlayerPed(src)
        if ped == 0 then return false end
        return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= (dist or 3.0)
    end

    function JRS.Distance(a, b)
        local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
        if pa == 0 or pb == 0 then return math.huge end
        return #(GetEntityCoords(pa) - GetEntityCoords(pb))
    end


    ---------------------------------------------------------------- character as a player object
    -- For scripts written around a player object: PlayerData + Functions, all backed by JRS.
    function JRS.ItemDef(item)
        local def = exports.jrs_inventory:getItemDB(item)
        if not def then return nil end
        return { name = item, label = def.label or item, weight = def.weight, description = def.desc }
    end

    function JRS.Player(src)
        src = tonumber(src)
        if not src then return nil end
        local c = JRS.Char(src)
        if not c then return nil end
        local grade = tonumber(c.jobGrade) or 0
        local p = {
            PlayerData = {
                source = src,
                citizenid = tostring(c.charIdentifier),
                id = tonumber(c.charIdentifier),
                name = GetPlayerName(src),
                charinfo = { firstname = c.firstname or '', lastname = c.lastname or '' },
                job = { name = c.job or 'unemployed', label = c.jobLabel or c.job or 'unemployed', type = c.job,
                        grade = { level = grade, name = tostring(grade) }, onduty = true },
                money = { cash = tonumber(c.money) or 0, bank = 0, gold = tonumber(c.gold) or 0 },
                metadata = {},
            },
        }
        local function currency(kind) return kind == 'gold' and 1 or 0 end
        p.Functions = {
            GetItemByName = function(name)
                local n = JRS.Count(src, name)
                if n < 1 then return nil end
                return { name = name, amount = n, count = n, label = JRS.ItemLabel(name) }
            end,
            HasItem = function(name, amount) return JRS.Has(src, name, amount or 1) end,
            AddItem = function(name, amount) return JRS.Add(src, name, amount or 1) end,
            RemoveItem = function(name, amount)
                amount = amount or 1
                if JRS.Count(src, name) < amount then return false end
                return JRS.Remove(src, name, amount)
            end,
            GetMoney = function(kind) return JRS.Money(src, currency(kind)) end,
            AddMoney = function(kind, amount) return JRS.GiveMoney(src, amount, currency(kind)) end,
            RemoveMoney = function(kind, amount) return JRS.TakeMoney(src, amount, currency(kind)) end,
            SetJob = function(job, g) return exports.jrs_core:SetJob(src, job, g) end,
            SetMetaData = function() end,
        }
        return p
    end

    function JRS.Players()
        local out = {}
        for _, s in ipairs(GetPlayers()) do out[#out + 1] = tonumber(s) end
        return out
    end

    function JRS.PlayerByCharId(charId)
        charId = tostring(charId)
        for _, s in ipairs(GetPlayers()) do
            local c = JRS.Char(s)
            if c and tostring(c.charIdentifier) == charId then return JRS.Player(s) end
        end
    end


    -- Method-style player (getAccount / removeAccount / getCharacterIdentifier ...), backed by JRS.
    -- Accounts: 0 = dollars, 2 = gold (anything else reads as 0).
    function JRS.MethodPlayer(src)
        src = tonumber(src)
        local c = src and JRS.Char(src)
        if not c then return nil end
        local function cur(account) return tonumber(account) == 2 and 1 or (tonumber(account) == 0 and 0 or nil) end
        local p = {}
        p.source = src
        p.loaded = function() return true end
        p.getIdentifier = function() return c.identifier end
        p.getCharacterIdentifier = function() return c.charIdentifier end
        p.getIdentityId = function() return c.charIdentifier end
        p.getFirstName = function() return c.firstname or '' end
        p.getLastName = function() return c.lastname or '' end
        -- 0 = male, 1 = female
        p.getGender = function() return tostring(c.gender or ''):lower():find('fem') and 1 or 0 end
        p.getDob = function() return c.dateofbirth and tostring(c.dateofbirth) or (c.age and tostring(c.age)) or '' end
        p.getJob = function() return c.job end
        p.getJobGrade = function() return tonumber(c.jobGrade) or 0 end
        p.getGroup = function() return JRS.Group(src) end
        p.getAccount = function(account)
            local k = cur(account)
            return k and JRS.Money(src, k) or 0
        end
        p.addAccount = function(account, amount)
            local k = cur(account)
            return k and JRS.GiveMoney(src, amount, k) or false
        end
        p.removeAccount = function(account, amount)
            local k = cur(account)
            return k and JRS.TakeMoney(src, amount, k) or false
        end
        p.hasPermissionsByAce = function(ace) return IsPlayerAceAllowed(src, ace) end
        p.hasAdministratorPermissions = function() return JRS.IsAdmin(src) end
        p.addItem = function(item, amount, metadata) return JRS.Add(src, item, amount or 1, metadata) end
        p.removeItem = function(item, amount) return JRS.Remove(src, item, amount or 1) end
        p.canCarryItem = function(item, amount) return JRS.CanCarry(src, item, amount or 1) end
        p.getItemQuantity = function(item) return JRS.Count(src, item) end
        p.getInventoryContents = function()
            local ok, list = pcall(function() return exports.jrs_inventory:getUserInventoryItems(src) end)
            return ok and list or {}
        end
        p.getInventoryWeightCapacity = function() return 0 end
        p.disconnect = function(reason) DropPlayer(src, tostring(reason or '')) end
        p.ban = function(reason)
            print(('^1[%s] kicked %d (%s): %s^7'):format(GetCurrentResourceName(), src, GetPlayerName(src) or '?', tostring(reason)))
            DropPlayer(src, tostring(reason or ''))
        end
        return p
    end

    -- usable item with a table payload { source, itemId, item, label, metadata, durability }
    function JRS.UsableData(item, _, fn)
        exports.jrs_inventory:registerUsableItem(item, function(data)
            local it = data.item or {}
            fn({ source = data.source, itemId = it.id, item = it.name or item, label = it.label,
                 metadata = it.metadata or {}, durability = 100 })
        end)
    end

    function JRS.Noop() end

    -- send an event to every player within radius of coords
    function JRS.TriggerNearby(event, data, coords, radius)
        local c = vector3(coords.x, coords.y, coords.z)
        for _, s in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(s)
            if ped ~= 0 and #(GetEntityCoords(ped) - c) <= (radius or 50.0) then
                TriggerClientEvent(event, tonumber(s), data)
            end
        end
    end

    -- the client's own character summary (JRS.Me on the client)
    JRS.Callback(GetCurrentResourceName() .. ':kit:me', function(src)
        local c = JRS.Char(src)
        if not c then return nil end
        return { citizenid = tostring(c.charIdentifier), firstname = c.firstname, lastname = c.lastname,
                 job = c.job, jobLabel = c.jobLabel, grade = tonumber(c.jobGrade) or 0,
                 money = tonumber(c.money) or 0, gold = tonumber(c.gold) or 0,
                 charIdentifier = c.charIdentifier, identifier = c.identifier, jobGrade = tonumber(c.jobGrade) or 0 }
    end)

    -- lets the client ask "do I have this item?"
    JRS.Callback(GetCurrentResourceName() .. ':kit:hasItem', function(src, item, amount)
        if type(item) ~= 'string' then return false end
        return JRS.Has(src, item, tonumber(amount) or 1)
    end)

    -- simple per-player cooldown: JRS.Cooldown(src, 'key', seconds) -> true when allowed
    local cooldowns = {}
    function JRS.Cooldown(src, key, seconds)
        local id = tostring(src) .. ':' .. key
        local now = os.time()
        if cooldowns[id] and cooldowns[id] > now then return false end
        cooldowns[id] = now + seconds
        return true
    end
    AddEventHandler('playerDropped', function()
        local prefix = tostring(source) .. ':'
        for k in pairs(cooldowns) do
            if k:sub(1, #prefix) == prefix then cooldowns[k] = nil end
        end
    end)
else
    ---------------------------------------------------------------- client
    JRS.Menu = exports.jrs_core:GetMenuData()

    function JRS.Notify(text, ms) JRS.Core.NotifyRightTip(tostring(text), ms or 4000) end
    -- server scripts: TriggerClientEvent(resource .. ':notify', src, text | { title, description }, ms)
    RegisterNetEvent(GetCurrentResourceName() .. ':notify', function(a, ms)
        if type(a) == 'table' then JRS.NotifyT(a) else JRS.Notify(a, ms) end
    end)


    -- left / right notifications sent the JRS way: (title, message, ...) and (message, ms)
    RegisterNetEvent(GetCurrentResourceName() .. ':notifyLeft', function(title, msg)
        JRS.NotifyT({ title = title, description = msg })
    end)

    -- returns every value the server callback returned
    function JRS.Await(name, ...)
        local r = JRS.Core.Callback.TriggerAwait(name, ...)
        if type(r) == 'table' and r.__jrs then return table.unpack(r, 1, r.n or 0) end
        return r
    end

    -- cb-style client call: JRS.TriggerCallback(name, function(...) end, args...)
    function JRS.TriggerCallback(name, cb, ...)
        local args = table.pack(...)
        CreateThread(function() cb(JRS.Await(name, table.unpack(args, 1, args.n))) end)
    end

    local bar
    -- blocks for ms while the JRS progress bar runs
    function JRS.Progress(label, ms)
        bar = bar or exports.jrs_progressbar:initiate()
        local p = promise.new()
        bar.start(label, ms, function() p:resolve(true) end, 'linear', nil, nil, false)
        return Citizen.Await(p)
    end


    ---------------------------------------------------------------- small UI helpers
    -- opts = { label, duration, anim = { dict, clip, flag } } -> true when it ran to the end
    function JRS.ProgressBar(opts)
        opts = opts or {}
        local ped = PlayerPedId()
        local anim = opts.anim
        if anim and anim.dict and JRS.LoadDict(anim.dict) then
            TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, -1, anim.flag or 1, 0, false, false, false)
        elseif anim and anim.scenario then
            TaskStartScenarioInPlace(ped, joaat(anim.scenario), -1, true, false, false, false)
        end
        JRS.Progress(opts.label or '', opts.duration or 3000)
        if anim then ClearPedTasks(ped) end
        return not IsEntityDead(ped)
    end

    -- opts = { dict, name, blendInSpeed, blendOutSpeed, duration, flag, playbackRate }
    function JRS.PlayAnimation(ped, opts)
        if not opts or not opts.dict or not JRS.LoadDict(opts.dict) then return end
        TaskPlayAnim(ped, opts.dict, opts.name, opts.blendInSpeed or 1.0, opts.blendOutSpeed or 1.0,
            opts.duration or -1, opts.flag or 0, opts.playbackRate or 0.0, false, false, false)
    end

    function JRS.TeleportToCoords(x, y, z, h)
        local ped = PlayerPedId()
        SetEntityCoords(ped, x, y, z, false, false, false, false)
        if h then SetEntityHeading(ped, h) end
    end

    -- delete an entity we created and release its model
    function JRS.RemoveEntity(entity, model)
        if entity and DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
        if model then SetModelAsNoLongerNeeded(model) end
    end

    -- notification from a { title, description, duration } table
    function JRS.NotifyT(d)
        if type(d) ~= 'table' then return JRS.Notify(d) end
        local text = d.description and d.description ~= '' and (d.title and (d.title .. ': ' .. d.description) or d.description) or d.title
        JRS.Notify(text or '', d.duration or 5000)
    end

    -- bottom-centre hint while something is going on
    local hintText
    function JRS.ShowText(text)
        local first = hintText == nil
        hintText = tostring(text)
        if not first then return end
        CreateThread(function()
            while hintText do
                SetTextScale(0.35, 0.35)
                SetTextColor(255, 255, 255, 230)
                SetTextCentre(true)
                SetTextDropshadow(1, 0, 0, 0, 255)
                DisplayText(VarString(10, 'LITERAL_STRING', hintText), 0.5, 0.90)
                Wait(0)
            end
        end)
    end
    function JRS.HideText() hintText = nil end

    -- context menus: def = { id, title, options = { { title, description, onSelect | event, args, disabled } } }
    local contexts = {}
    function JRS.RegisterContext(def) if def and def.id then contexts[def.id] = def end end
    function JRS.ShowContext(id)
        local def = contexts[id]
        if not def then return end
        local elements = {}
        for i, o in ipairs(def.options or {}) do
            elements[#elements + 1] = { label = o.title or '', value = i, desc = o.description or '' }
        end
        JRS.OpenMenu('jrs_ctx_' .. id, def.title or '', '', elements, function(el, menu)
            local o = def.options[el.value]
            if not o or o.disabled then return end
            menu.close()
            if o.onSelect then o.onSelect(o.args)
            elseif o.event then TriggerEvent(o.event, o.args)
            elseif o.serverEvent then TriggerServerEvent(o.serverEvent, o.args) end
        end, def.menu and function() JRS.ShowContext(def.menu) end or nil)
    end

    -- returns 'confirm' or 'cancel'
    function JRS.Confirm(d)
        local p = promise.new()
        local labels = d.labels or {}
        JRS.OpenMenu('jrs_confirm', d.header or '', d.content or '', {
            { label = labels.confirm or 'Confirm', value = 'confirm', desc = '' },
            { label = labels.cancel or 'Cancel', value = 'cancel', desc = '' },
        }, function(el, menu) menu.close() p:resolve(el.value) end, function() p:resolve('cancel') end)
        return Citizen.Await(p)
    end

    -- own character summary { citizenid, firstname, lastname, job, jobLabel, grade, money, gold }, cached 5s
    local me, meAt = nil, 0
    function JRS.Me(fresh)
        if fresh or not me or GetGameTimer() > meAt then
            me = JRS.Await(GetCurrentResourceName() .. ':kit:me') or me
            meAt = GetGameTimer() + 5000
        end
        return me
    end

    function JRS.HasItem(item, amount)
        return JRS.Await(GetCurrentResourceName() .. ':kit:hasItem', item, amount or 1) == true
    end

    -- text input; numeric = true returns a number. nil when cancelled / empty.
    function JRS.Input(title, placeholder, numeric)
        local res = exports.jrs_core:advancedInput({
            type = 'enableinput', inputType = 'input', button = 'OK', placeholder = placeholder or '',
            style = 'block', attributes = { inputHeader = title or '', type = numeric and 'number' or 'text' },
        })
        if res == nil or res == '' then return nil end
        if numeric then return tonumber(res) end
        return tostring(res)
    end

    -- JRS menu. elements = { { label, value, desc } }. onSelect(element, menu); onClose(menu)
    function JRS.OpenMenu(id, title, subtext, elements, onSelect, onClose, align)
        JRS.Menu.CloseAll()
        JRS.Menu.Open('default', GetCurrentResourceName(), id, {
            title = title, subtext = subtext or '', align = align or 'top-left', elements = elements,
        }, function(data, menu)
            -- own thread: handlers may wait on inputs / callbacks / progress bars
            if data.current and onSelect then CreateThread(function() onSelect(data.current, menu) end) end
        end, function(_, menu)
            menu.close()
            if onClose then CreateThread(function() onClose(menu) end) end
        end)
    end

    function JRS.CloseMenu() JRS.Menu.CloseAll() end

    function JRS.LoadModel(model)
        model = type(model) == 'string' and joaat(model) or model
        if not IsModelValid(model) then return false end
        RequestModel(model)
        local t = GetGameTimer() + 5000
        while not HasModelLoaded(model) and GetGameTimer() < t do Wait(25) end
        return HasModelLoaded(model)
    end

    function JRS.LoadDict(dict)
        RequestAnimDict(dict)
        local t = GetGameTimer() + 5000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(25) end
        return HasAnimDictLoaded(dict)
    end

    function JRS.Blip(coords, sprite, name, scale)
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
        SetBlipSprite(blip, type(sprite) == 'string' and joaat(sprite) or sprite, true)
        SetBlipScale(blip, scale or 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, tostring(name or ''))
        return blip
    end

    -- Prompt group: local g = JRS.Prompts(); local p = g:add(key, 'Text', holdMs)
    -- every frame: g:show('Title'); if g:done(p) then ... end
    local PromptGroup = {}
    PromptGroup.__index = PromptGroup

    function JRS.Prompts()
        return setmetatable({ id = GetRandomIntInRange(0, 0xffffff), list = {} }, PromptGroup)
    end

    function PromptGroup:add(key, text, hold)
        local p = UiPromptRegisterBegin()
        UiPromptSetControlAction(p, key or 0x760A9C6F)
        UiPromptSetText(p, VarString(10, 'LITERAL_STRING', tostring(text)))
        UiPromptSetEnabled(p, true)
        UiPromptSetVisible(p, true)
        if hold then UiPromptSetHoldMode(p, hold) else UiPromptSetStandardMode(p, true) end
        UiPromptSetGroup(p, self.id, 0)
        UiPromptRegisterEnd(p)
        self.list[#self.list + 1] = { handle = p, hold = hold }
        return p
    end

    function PromptGroup:visible(p, state) UiPromptSetVisible(p, state == true) end
    function PromptGroup:enabled(p, state) UiPromptSetEnabled(p, state == true) end

    -- the group title must be a fresh VarString every frame (a cached one turns into garbage text)
    function PromptGroup:show(title)
        UiPromptSetActiveGroupThisFrame(self.id, VarString(10, 'LITERAL_STRING', tostring(title or '')), 0, 0, 0, 0)
    end

    function PromptGroup:done(p)
        for _, e in ipairs(self.list) do
            if e.handle == p then
                if e.hold then return UiPromptHasHoldModeCompleted(p) end
                return UiPromptHasStandardModeCompleted(p)
            end
        end
        return false
    end

    function PromptGroup:delete()
        for _, e in ipairs(self.list) do UiPromptDelete(e.handle) end
        self.list = {}
    end

    ---------------------------------------------------------------- interactions (no third-eye)
    -- Options: { name, label, distance, canInteract(entity, dist), onSelect(data) | event | serverEvent | command, args }
    -- Near a target a G prompt appears: one option runs directly, several open a JRS menu.
    local targets = { entities = {}, models = {}, players = {} }
    local targetCount = 0
    local INTERACT_KEY = 0x760A9C6F

    local function recount()
        local n = 0
        for _ in pairs(targets.entities) do n = n + 1 end
        for _ in pairs(targets.models) do n = n + 1 end
        targetCount = n + #targets.players
    end

    local function hashOf(m) return type(m) == 'string' and joaat(m) or m end

    function JRS.AddEntityTarget(entity, options)
        if not entity or entity == 0 then return end
        targets.entities[entity] = options
        recount()
    end

    function JRS.RemoveEntityTarget(entity)
        targets.entities[entity] = nil
        recount()
    end

    function JRS.AddModelTarget(models, options)
        if type(models) ~= 'table' then models = { models } end
        for _, m in ipairs(models) do
            local h = hashOf(m)
            targets.models[h] = targets.models[h] or {}
            for _, o in ipairs(options) do table.insert(targets.models[h], o) end
        end
        recount()
    end

    local function dropNamed(list, names)
        if names == nil then return {} end
        if type(names) ~= 'table' then names = { names } end
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        local out = {}
        for _, o in ipairs(list) do if not set[o.name] then out[#out + 1] = o end end
        return out
    end

    function JRS.RemoveModelTarget(models, names)
        if type(models) ~= 'table' then models = { models } end
        for _, m in ipairs(models) do
            local h = hashOf(m)
            if targets.models[h] then
                targets.models[h] = dropNamed(targets.models[h], names)
                if #targets.models[h] == 0 then targets.models[h] = nil end
            end
        end
        recount()
    end

    function JRS.AddPlayerTarget(options)
        for _, o in ipairs(options) do table.insert(targets.players, o) end
        recount()
    end

    function JRS.RemovePlayerTarget(names)
        targets.players = dropNamed(targets.players, names)
        recount()
    end

    local function validOptions(list, entity, dist)
        local out = {}
        for _, o in ipairs(list or {}) do
            if dist <= (o.distance or 2.5) then
                local ok, can = true, true
                if o.canInteract then ok, can = pcall(o.canInteract, entity, dist) end
                if ok and can then out[#out + 1] = o end
            end
        end
        return out
    end

    local function runOption(o, entity, dist)
        local data = { entity = entity, coords = GetEntityCoords(entity), distance = dist, args = o.args, name = o.name }
        if o.onSelect then
            o.onSelect(data)
        elseif o.event then
            TriggerEvent(o.event, o.args or data)
        elseif o.serverEvent then
            TriggerServerEvent(o.serverEvent, o.args or data)
        elseif o.command then
            ExecuteCommand(o.command)
        end
    end

    local function maxDistance(list)
        local m = 0
        for _, o in ipairs(list or {}) do m = math.max(m, o.distance or 2.5) end
        return m
    end

    local nearbyModels, modelScanAt = {}, 0

    -- nearest entity that has at least one usable option
    local function findTarget()
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local best, bestDist, bestOpts

        local function consider(entity, list)
            if entity == ped or not DoesEntityExist(entity) then return end
            local d = #(GetEntityCoords(entity) - pos)
            if d > maxDistance(list) or (bestDist and d >= bestDist) then return end
            local opts = validOptions(list, entity, d)
            if #opts > 0 then best, bestDist, bestOpts = entity, d, opts end
        end

        for entity, list in pairs(targets.entities) do
            if DoesEntityExist(entity) then consider(entity, list) else targets.entities[entity] = nil end
        end
        if next(targets.models) then
            -- full pool scans are expensive: refresh the nearby model list once a second
            local now = GetGameTimer()
            if now >= modelScanAt then
                modelScanAt = now + 1000
                nearbyModels = {}
                for _, pool in ipairs({ 'CObject', 'CPed', 'CVehicle' }) do
                    for _, e in ipairs(GetGamePool(pool)) do
                        if targets.models[GetEntityModel(e)] and #(GetEntityCoords(e) - pos) < 15.0 then
                            nearbyModels[#nearbyModels + 1] = e
                        end
                    end
                end
            end
            for _, e in ipairs(nearbyModels) do
                local list = targets.models[GetEntityModel(e)]
                if list then consider(e, list) end
            end
        end
        if #targets.players > 0 then
            for _, pid in ipairs(GetActivePlayers()) do
                if pid ~= PlayerId() then consider(GetPlayerPed(pid), targets.players) end
            end
        end
        return best, bestDist, bestOpts
    end

    CreateThread(function()
        local group = GetRandomIntInRange(0, 0xffffff)
        local prompt = UiPromptRegisterBegin()
        UiPromptSetControlAction(prompt, INTERACT_KEY)
        UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', 'Interact'))
        UiPromptSetEnabled(prompt, true)
        UiPromptSetVisible(prompt, true)
        UiPromptSetStandardMode(prompt, true)
        UiPromptSetGroup(prompt, group, 0)
        UiPromptRegisterEnd(prompt)
        AddEventHandler('onResourceStop', function(res)
            if res == GetCurrentResourceName() then UiPromptDelete(prompt) end
        end)

        local current, currentDist, currentOpts, label = nil, 0, nil, nil
        local nextScan = 0
        while true do
            if targetCount == 0 then
                current = nil
                Wait(1000)
            else
                local now = GetGameTimer()
                if now >= nextScan then
                    nextScan = now + 300
                    current, currentDist, currentOpts = findTarget()
                    if current then
                        local text = #currentOpts == 1 and currentOpts[1].label or (currentOpts[1].groupLabel or 'Interact')
                        if text ~= label then
                            label = text
                            UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', tostring(text)))
                        end
                    end
                end
                if current and not IsPauseMenuActive() then
                    local title = currentOpts[1].groupLabel or label or ''
                    UiPromptSetActiveGroupThisFrame(group, VarString(10, 'LITERAL_STRING', tostring(title)), 0, 0, 0, 0)
                    if UiPromptHasStandardModeCompleted(prompt) then
                        local entity, dist, opts = current, currentDist, currentOpts
                        if #opts == 1 then
                            CreateThread(function() runOption(opts[1], entity, dist) end)
                        else
                            local elements = {}
                            for i, o in ipairs(opts) do elements[i] = { label = o.label, value = i, desc = o.description or '' } end
                            JRS.OpenMenu('jrs_target', title, '', elements, function(el, menu)
                                menu.close()
                                runOption(opts[el.value], entity, dist)
                            end)
                        end
                        nextScan = GetGameTimer() + 800
                        current = nil
                    end
                    Wait(0)
                else
                    Wait(150)
                end
            end
        end
    end)

    function JRS.ClosestPlayer(maxDist)
        local me = PlayerPedId()
        local pos = GetEntityCoords(me)
        local best, bestDist
        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= PlayerId() then
                local d = #(GetEntityCoords(GetPlayerPed(pid)) - pos)
                if d <= maxDist and (not bestDist or d < bestDist) then best, bestDist = pid, d end
            end
        end
        return best, bestDist
    end

    function JRS.DrawText3D(coords, text)
        local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
        if not onScreen then return end
        SetTextScale(0.30, 0.30)
        SetTextFontForCurrentCommand(1)
        SetTextColor(255, 255, 255, 215)
        SetTextCentre(true)
        SetTextDropshadow(1, 0, 0, 0, 255)
        DisplayText(VarString(10, 'LITERAL_STRING', tostring(text)), x, y)
    end
end
