-----------------------------------------------------------
--[[ Callbacks  ]]--
-----------------------------------------------------------

JRS.CreateCallback("jrs_passports:callbacks:isRegistered", function(source, cb)
    local _source        = source
	local xPlayer        = JRS.MethodPlayer(_source)
	local charIdentifier = xPlayer.getCharacterIdentifier()

	local finished, isRegistered, identityData = false, false, {}

    exports.oxmysql:execute("SELECT * FROM `passports` WHERE `charidentifier` = @charidentifier", { ['charidentifier'] = charIdentifier }, function(result)
		
		if result and result[1] then
			identityData = result[1]
			isRegistered = true
		end

		finished = true

	end)

	while not finished do
		Wait(500)
	end

	return cb( { registered = isRegistered, data = identityData })

end)
