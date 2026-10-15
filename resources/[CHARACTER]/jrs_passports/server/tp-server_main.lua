-----------------------------------------------------------
--[[ Local Functions  ]]--
-----------------------------------------------------------

-----------------------------------------------------------
--[[ General Events  ]]--
-----------------------------------------------------------

RegisterServerEvent("jrs_passports:server:register")
AddEventHandler("jrs_passports:server:register", function(targetId, avatar_url)
	local _source      = source

	-- registering someone else is staff-only; the photo must be a plain http(s) link
	if targetId ~= nil and tonumber(targetId) ~= 0 and not JRS.IsAdmin(_source) then targetId = nil end
	if targetId ~= nil and tonumber(targetId) == 0 then targetId = nil end
	avatar_url = type(avatar_url) == 'string' and avatar_url:match('^%s*(.-)%s*$') or nil
	if type(avatar_url) ~= 'string' or #avatar_url > 512 or not avatar_url:match('^https?://[%w%-%._~:/%?#@!%$&%+,;=%%]+$') then
		SendNotification(_source, Locales['PLAYER_INVALID'], "error")
		return
	end
	local targetSource = _source

	if targetId then -- fix 1.0.1 target was never added if was true. 
		targetSource = tonumber(targetId)
	end

	local xPlayer = JRS.MethodPlayer(targetSource)

	if GetPlayerName(targetSource) == nil or not xPlayer.loaded() then -- invalid target player (not online or in session)
		SendNotification(_source, Locales['PLAYER_INVALID'], "error")
		return
	end

 -- 1.0.1
	local charIdentifier = xPlayer.getCharacterIdentifier()
	local finished, isRegistered = false, false

	exports.oxmysql:execute("SELECT * FROM `passports` WHERE `charidentifier` = @charidentifier", { ['charidentifier'] = charIdentifier }, function(result)
		
		if result and result[1] then
			isRegistered = true
		end

		finished = true

	end)

	while not finished do
		Wait(500)
	end

	if isRegistered then

		if targetId then
			SendNotification(_source, Locales['ALREADY_REGISTERED_TARGET'], "error")
		else
			SendNotification(_source, Locales['ALREADY_REGISTERED'], "error")
		end

		return
	end


	local account = xPlayer.getAccount(0)

	if account < Config.PassportCosts.Registration then

		if targetId == nil or tonumber(targetId) == 0 then -- if target source is null, the target is source.
			SendNotification(_source, Locales['NOT_ENOUGH_MONEY_REGISTER'], "error")

		else -- if target source is not null, we send a notification in both.
			SendNotification(targetSource, Locales['NOT_ENOUGH_MONEY_REGISTER'], "error")
			SendNotification(_source, Locales['TARGET_DOES_NOT_HAVE_ENOUGH_MONEY'], "error")
		end

		return
	end

	xPlayer.removeAccount(0, Config.PassportCosts.Registration)

    local identifier     = xPlayer.getIdentifier()
    local charIdentifier = xPlayer.getCharacterIdentifier()
	local firstname      = xPlayer.getFirstName()
	local lastname       = xPlayer.getLastName()

	local gender         = xPlayer.getGender()
	local dob            = xPlayer.getDob()

	local steamName      = GetPlayerName(targetSource)

	local identityId     = xPlayer.getIdentityId()

	local registration_date = os.date('%d').. '/' ..os.date('%m').. '/' .. Config.Year .. " " .. os.date('%X')

	local RegistrationParameters = { 
		['identityId']          = identityId, 
		['identifier']          = identifier,
		['charidentifier']      = charIdentifier,
		['steamname']           = steamName,
		['firstname']           = firstname,
		['lastname']            = lastname,
		['dob']                 = dob,
		['sex']                 = gender,
		['registration_date']   = registration_date,
		['expiration_date']     = os.time() + ( Config.PassportExpirationDays * 86400), -- in days.
		['avatar_url']          = avatar_url,
	}
  
	exports.oxmysql:execute("INSERT INTO `passports` (`identityId`, `identifier`, `charidentifier`, `steamname`, `firstname`, `lastname`, `dob`, `sex`, `registration_date`, `expiration_date`, `avatar_url`) VALUES ( @identityId,  @identifier, @charidentifier, @steamname, @firstname, @lastname, @dob, @sex, @registration_date, @expiration_date, @avatar_url)", RegistrationParameters)

	xPlayer.addItem(Config.PassportItem, 1, { durability = -1, description = firstname .. ' ' .. lastname, identityId = identityId })

	if Config.Society.Enabled then
		-- (society ledger not used in the JRS edition)
	end

	if targetId == nil or tonumber(targetId) == 0 then -- if target source is null, the target is source.
		SendNotification(_source, Locales['PASSPORT_CREATE_SELF_SUCCESS'], "success")

	else -- if target source is not null, we send a notification in both.
		SendNotification(targetSource, Locales['PASSPORT_CREATE_SELF_SUCCESS'], "success")
		SendNotification(_source, Locales['TARGET_PASSPORT_CREATE_SUCCESS'], "success")
	end

	if Config.Webhooks['CREATED_PASSPORT'].Enabled then
		local title   = string.format("📄`New Passport Registration`", id)
		local message = string.format("The player with the Steam Name: `%s` and Identifier: `%s` (Character Identifier: `%s`) has registered a new passport.\n\n**Passport ID**: `%s`.\n\n**Image Url**:\n`%s`.", steamName, identifier, charIdentifier, identityId, avatar_url)
		local url     = JRS.Noop("jrs_passports", "CREATED_PASSPORT")
		JRS.Noop(url, title, message, avatar_url, Config.Webhooks['CREATED_PASSPORT'].Color)
	end

end)

RegisterServerEvent("jrs_passports:server:retrieve")
AddEventHandler("jrs_passports:server:retrieve", function()
	local _source        = source
	local xPlayer        = JRS.MethodPlayer(_source)

	local identifier     = xPlayer.getIdentifier()
	local charIdentifier = xPlayer.getCharacterIdentifier()
	local steamName      = GetPlayerName(_source)

	local account        = xPlayer.getAccount(0)
	local cost           = Config.PassportCosts.Retrieve

	if account < cost then
		SendNotification(_source, Locales['NOT_ENOUGH_MONEY_RETRIEVE'], "error")
		return
	end

	exports.oxmysql:execute("SELECT * FROM `passports` WHERE `charidentifier` = @charidentifier", 
	{ ['charidentifier'] = charIdentifier }, 
	
	function(result)
		
		if result and result[1] then

			local res = result[1]

			xPlayer.removeAccount(0, cost)
			xPlayer.addItem(Config.PassportItem, 1, { durability = -1, description = res.firstname .. ' ' .. res.lastname, identityId = res.identityId })
		
			SendNotification(_source, Locales['PASSPORT_RETRIEVED'], "success")

			if Config.Society.Enabled then
				-- (society ledger not used in the JRS edition)
			end

			if Config.Webhooks['RETRIEVED_PASSPORT'].Enabled then
				local title   = string.format("📄`Passport Retrieval`", id)
				local message = string.format("The player with the Steam Name: `%s` and Identifier: `%s` (Character Identifier: `%s`) has retrieved a passport.\n\n**Passport ID**: `%s`.", steamName, identifier, charIdentifier, res.identityId)
			    local url = JRS.Noop('jrs_passports', 'RETRIEVED_PASSPORT')
				JRS.Noop(url, title, message, Config.Webhooks['RETRIEVED_PASSPORT'].Color)
			end

		end
		
	end)

end)


RegisterServerEvent("jrs_passports:server:renew")
AddEventHandler("jrs_passports:server:renew", function()
	local _source        = source
	local xPlayer        = JRS.MethodPlayer(_source)

	local identifier     = xPlayer.getIdentifier()
	local charIdentifier = xPlayer.getCharacterIdentifier()
	local steamName      = GetPlayerName(_source)

	local account        = xPlayer.getAccount(0)
	local cost           = Config.PassportCosts.Renewal

	if account < cost then
		SendNotification(_source, Locales['NOT_ENOUGH_MONEY_RENEW'], "error")
		return
	end

	exports.oxmysql:execute("SELECT * FROM `passports` WHERE `charidentifier` = @charidentifier", 
	{ ['charidentifier'] = charIdentifier }, 
	
	function(result)
		
		if result and result[1] then

			local res = result[1]
	
			-- Get current timestamp
			local current_timestamp = os.time()

			if current_timestamp <= res.expiration_date then 
				SendNotification(_source, Locales['PASSPORT_NOT_EXPIRED'], "error")
				return
			end

			xPlayer.removeAccount(0, cost)
			SendNotification(_source, Locales['PASSPORT_RENEWED'], "success")
		
			local Parameters = { 
				['charidentifier']   = charIdentifier, 
				['expiration_date']  = os.time() + ( Config.PassportExpirationDays * 86400), -- in days
			}
		  
			exports.oxmysql:execute("UPDATE `passports` SET `expiration_date` = @expiration_date WHERE `charidentifier` = @charidentifier", Parameters)
		
			if Config.Society.Enabled then
				-- (society ledger not used in the JRS edition)
			end

			if Config.Webhooks['RENEWED_PASSPORT'].Enabled then
				local title   = string.format("📄`Passport Renewal`", id)
				local message = string.format("The player with the Steam Name: `%s` and Identifier: `%s` (Character Identifier: `%s`) has renewed a passport.\n\n**Passport ID**: `%s`.", steamName, identifier, charIdentifier, res.identityId)
				local url     = JRS.Noop('jrs_passports', 'RENEWED_PASSPORT')
				JRS.Noop(url, title, message, Config.Webhooks['RENEWED_PASSPORT'].Color)
			end
			
		end

	end)


end)

