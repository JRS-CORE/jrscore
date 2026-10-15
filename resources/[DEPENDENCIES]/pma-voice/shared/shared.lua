Cfg = {}

voiceTarget = 1

gameVersion = GetGameName()

-- these are just here to satisfy linting
if not IsDuplicityVersion() then
	LocalPlayer = LocalPlayer
	playerServerId = GetPlayerServerId(PlayerId())
end
Player = Player
Entity = Entity

if GetConvar('voice_useNativeAudio', 'false') == 'true' then
	-- native audio distance seems to be larger then regular gta units
	Cfg.voiceModes = {
		{1.5, "Whisper"}, -- Whisper speech distance in gta distance units
		{3.0, "Normal"}, -- Normal speech distance in gta distance units
		{6.0, "Shouting"} -- Shout speech distance in gta distance units
	}
else
	Cfg.voiceModes = {
		{3.5, "Whisper"},  -- whisper range, in game distance units
		{8.0, "Normal"},   -- normal speech range
		{15.0, "Loud"},    -- raised voice range
		{20.0, "Shouting"} -- shouting range
	}

end

logger = {
	log = function(message, ...)
-- REMOVED-PRINT: 		print((message):format(...))
	end,
	info = function(message, ...)
		if GetConvarInt('voice_debugMode', 0) >= 1 then
-- REMOVED-PRINT: 			print(('[info] ' .. message):format(...))
		end
	end,
	warn = function(message, ...)
		print(('[^1WARNING^7] ' .. message):format(...))
	end,
	error = function(message, ...)
		error((message):format(...))
	end,
	verbose = function(message, ...)
		if GetConvarInt('voice_debugMode', 0) >= 4 then
-- REMOVED-PRINT: 			print(('[verbose] ' .. message):format(...))
		end
	end,
}


function tPrint(tbl, indent)
	indent = indent or 0
	for k, v in pairs(tbl) do
		local tblType = type(v)
		local formatting = string.rep("  ", indent) .. k .. ": "

		if tblType == "table" then
-- REMOVED-PRINT: 			print(formatting)
			tPrint(v, indent + 1)
		elseif tblType == 'boolean' then
-- REMOVED-PRINT: 			print(formatting .. tostring(v))
		elseif tblType == "function" then
-- REMOVED-PRINT: 			print(formatting .. tostring(v))
		else
-- REMOVED-PRINT: 			print(formatting .. v)
		end
	end
end

local function types(args)
    local argType = type(args[1])
    for i = 2, #args do
        local arg = args[i]
        if argType == arg then
            return true, argType
        end
    end
    return false, argType
end

function type_check(...)
    local vars = {...}
    for i = 1, #vars do
        local var = vars[i]
        local matchesType, varType = types(var)
        if not matchesType then
            table.remove(var, 1)
            error(("Invalid type sent to argument #%s, expected %s, got %s"):format(i, table.concat(var, "|"), varType))
        end
    end
end