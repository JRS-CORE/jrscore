AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Startup banner + version report are printed by server/version.lua,
    -- after every resource has finished starting, so they land at the very end
    -- of the boot log instead of in the middle of it.

    local function loadCharacters()
        exports.oxmysql:execute('SELECT * FROM jrs_characters', {}, function(result)
            if result then
                for _, row in ipairs(result) do
                    table.insert(AllCharacters, {
                        setJob = Character.setJob,
                        setMeta = Character.setMeta,
                        addCurrency = Character.addCurrency,
                        removeCurrency = Character.removeCurrency,
                        buySkin = Character.buySkin,
                        changeSkin = Character.changeSkin,
                        buySkinPlayer = Character.buySkinPlayer,
                        identifier = row.identifier,
                        charIdentifier = row.charidentifier,
                        firstname = row.firstname,
                        lastname = row.lastname,
                        skin = row.skinPlayer,
                        comp = row.compPlayer,
                        inventory = row.inventory,
                        meta = row.meta,
                        money = row.money,
                        gold = row.gold,
                        rol = row.rol,
                        dirtymoney = row.dirtymoney,
                        job = row.job,
                        jobgrade = row.jobgrade,
                        coords = row.coords,
                    })
                end
            else
                table.insert(AllCharacters, {
                    setJob = Character.setJob,
                    setMeta = Character.setMeta,
                    addCurrency = Character.addCurrency,
                    removeCurrency = Character.removeCurrency,
                    buySkin = Character.buySkin,
                    changeSkin = Character.changeSkin,
                    buySkinPlayer = Character.buySkinPlayer,
                    identifier = 'steam:00000000',
                    charIdentifier = '0',
                    firstname = 'clean',
                    lastname = 'clean',
                    skin = json.encode('{}'),
                    comp = json.encode('{}'),
                    inventory = json.encode('{}'),
                    meta = json.encode('{}'),
                    money = 0.0,
                    gold = 0.0,
                    rol = 0.0,
                    dirtymoney = 0.0,
                    job = 'Unemployed',
                    jobgrade = 0,
                    coords = json.encode('{}'),
                })
            end
        end)
    end

    -- Dirty Money uses its own database field. Create it automatically on older databases.
    exports.oxmysql:execute("SHOW COLUMNS FROM `jrs_characters` LIKE 'dirtymoney'", {}, function(columns)
        if columns and #columns > 0 then
            loadCharacters()
            return
        end

        exports.oxmysql:execute(
            "ALTER TABLE `jrs_characters` ADD COLUMN `dirtymoney` DECIMAL(20,2) NOT NULL DEFAULT 0.00 AFTER `money`",
            {},
            function()
                print("^2[jrs_core] Added characters.dirtymoney database column.^0")
                loadCharacters()
            end
        )
    end)

    -- Config.Char_Count is the default. Individual staff overrides are stored separately.
    exports.oxmysql:execute('UPDATE jrs_users SET `chars` = @chars WHERE `chars_override` IS NULL', { chars = Config.Char_Count })

    exports.oxmysql:execute('SELECT * FROM jrs_users', {}, function(result)
        if result then
            for _, row in ipairs(result) do
                LoadedUsers[row.identifier] = {
                    identifier = row.identifier,
                    group = row.group,
                    chars = tonumber(row.chars_override) or Config.Char_Count,
                    warnings = row.warnings,
                    banned = row.banned,
                    setUsedCharacter = User.setUsedCharacter,
                    addCharacter = jrsCore.addCharacter,
                    setGroup = User.setGroup,
                }
            end
        else
            LoadedUsers['steam:00000000'] = {
                identifier = 'steam:00000000',
                group = 'admin',
                chars = 0,
                warnings = 0,
                banned = 0,
                setUsedCharacter = User.setUsedCharacter,
                addCharacter = jrsCore.addCharacter,
                setGroup = User.setGroup,
            }
        end

        -- jrs_core just wiped PlayerData/UserBySource/characterReady by
        -- restarting. Anyone still connected who already had a character
        -- selected is now invisible to IsCharacterReady/GetCharacter until
        -- they relog, which silently fails every gated action elsewhere
        -- (stores, banking, etc.) with NO_CHARACTER. Reattach them here from
        -- their surviving state bag instead of waiting for a relog.
        if type(jrsCore.RestoreConnectedCharacter) == 'function' then
            for _, rawSource in ipairs(GetPlayers()) do
                local src = tonumber(rawSource)
                if src then
                    pcall(jrsCore.RestoreConnectedCharacter, src)
                end
            end
        end
    end)
end)
