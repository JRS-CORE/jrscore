
local ProtectedPlayers   = {}
local BlacklistedPlayers = {} -- returns the players who are already getting searched by other players.
local Searching          = {} -- searcher -> target

-----------------------------------------------------------
--[[ Local Functions  ]]--
-----------------------------------------------------------

local function GetPlayerData(source)
	local _source = source
    local xPlayer = JRS.MethodPlayer(_source)

	return {
    steamName      = GetPlayerName(_source),
    username       = xPlayer.getFirstName() .. ' ' .. xPlayer.getLastName(),
		identifier     = xPlayer.getIdentifier(),
    charIdentifier = xPlayer.getCharacterIdentifier(),
		job            = xPlayer.getJob(),
	}

end

local ContainsValue = function(table, value)

  if table == nil or #table == 0 then 
    return false
  end

  for _, v in pairs (table) do 

    if v == value then 
      return true 
    end

  end

  return false

end

-----------------------------------------------------------
--[[ Base Events  ]]--
-----------------------------------------------------------

AddEventHandler('onResourceStop', function(resourceName)
  if (GetCurrentResourceName() ~= resourceName) then
    return
  end

  ProtectedPlayers   = nil
  BlacklistedPlayers = nil

end)

-----------------------------------------------------------
--[[ Events  ]]--
-----------------------------------------------------------

-- server-side only (a client must not be able to make itself unsearchable)
AddEventHandler("jrs_search:server:protect", function(_source)
  _source              = tonumber(_source)
  local xPlayer        = _source and JRS.MethodPlayer(_source)
  if not xPlayer then return end
  local charIdentifier = xPlayer.getCharacterIdentifier()

  if not ProtectedPlayers[charIdentifier] then 
    ProtectedPlayers[charIdentifier] = {}
    ProtectedPlayers[charIdentifier].char     = charIdentifier
    ProtectedPlayers[charIdentifier].duration = 0
  end

end)

RegisterServerEvent("jrs_search:server:reset_searched_target")
AddEventHandler("jrs_search:server:reset_searched_target", function(targetId)
  local _source = source
  local _tsource = tonumber(targetId)
  -- only the player who is searching that target can free it
  if not _tsource or Searching[_source] ~= _tsource then return end
  Searching[_source] = nil
  BlacklistedPlayers[_tsource] = nil
end)

RegisterServerEvent("jrs_search:server:search")
AddEventHandler("jrs_search:server:search", function(targetId)
  local _source  = source
  local _tsource = tonumber(targetId)
  if not _tsource or _tsource == _source or GetPlayerPed(_tsource) == 0 or Searching[_source] then return end

  Wait(math.random(100, 1000))

  local xPlayer         = JRS.MethodPlayer(_source)
  if not xPlayer or not JRS.MethodPlayer(_tsource) then return end
  local charIdentifier  = xPlayer.getCharacterIdentifier()
  local xJob            = xPlayer.getJob()

  local isAllowed       = true 

  local coords1 = GetEntityCoords(GetPlayerPed(_source))
  local coords2 = GetEntityCoords(GetPlayerPed(_tsource))

  if #(coords1 - coords2) > 4.0 then
    return
  end

  -- the target must really be restrained / surrendering (checked here, not on the searcher's client)
  local tstate = Player(_tsource).state
  local surrendering = (Config.SearchHandsUp and tstate.jrs_handsup == true) or tstate.jrs_robbery_cuffed == true
  if not surrendering and not ContainsValue(Config.LawJobs, xJob) then
    SendNotification(_source, Locales['PLAYER_TARGET_NOT_SURRENDERED'].text, 'error', Locales['PLAYER_TARGET_NOT_SURRENDERED'].duration)
    return
  end

  if Config.SearchByJobsOnly ~= false and JRS.TableLength(Config.SearchByJobsOnly) > 0 then
    isAllowed = ContainsValue(Config.SearchByJobsOnly, xJob)
  end

  if not isAllowed then 
    SendNotification(_source, Locales['NOT_REQUIRED_JOB'].text, 'error', Locales['NOT_REQUIRED_JOB'].duration)
    return 
  end

  local tPlayer         = JRS.MethodPlayer(_tsource)
  local tcharIdentifier = tPlayer.getCharacterIdentifier()
  local tJob            = tPlayer.getJob()

  if ProtectedPlayers[tcharIdentifier] then 

    local hasBypassJob = ContainsValue(Config.NewCharacterSafeDurationJobBypass, xJob)
    
    if not hasBypassJob then 
      SendNotification(_source, Locales['PLAYER_TARGET_UNDER_PROTECTION'].text, 'error', Locales['PLAYER_TARGET_UNDER_PROTECTION'].duration)
      return 
    end

  end

  local isBlacklistedTargetJob = ContainsValue(Config.BlacklistedJobs, tJob)

  if isBlacklistedTargetJob then 
    SendNotification(_source, Locales['PLAYER_TARGET_BLACKLISTED_JOB'].text, 'error', Locales['PLAYER_TARGET_BLACKLISTED_JOB'].duration)
    return 
  end

  if BlacklistedPlayers[_tsource] then 
    SendNotification(_source, Locales['CANNOT_SEARCH_PLAYER_IS_BUSY'].text, 'error', Locales['CANNOT_SEARCH_PLAYER_IS_BUSY'].duration)
    return
  end

  BlacklistedPlayers[_tsource] = 1

  Searching[_source] = _tsource
  TriggerClientEvent("jrs_search:client:setSearchingState", _source, true)
  exports.jrs_inventory:OpenPlayerInventoryAdmin(_source, _tsource, 4.0)

end)

-- the searcher closed the window: the target can be searched again
RegisterNetEvent('jrsCore:closestorage', function(id)
  local _source = source
  local target = Searching[_source]
  if target and tostring(id) == ('admin_search:%d'):format(target) then
    Searching[_source] = nil
    BlacklistedPlayers[target] = nil
    TriggerClientEvent("jrs_search:client:closed", _source, false)
    TriggerClientEvent("jrs_search:client:setSearchingState", _source, false)
  end
end)

AddEventHandler('playerDropped', function()
  local _source = source
  if Searching[_source] then BlacklistedPlayers[Searching[_source]] = nil end
  Searching[_source] = nil
  BlacklistedPlayers[_source] = nil
end)

-----------------------------------------------------------
--[[ Events  ]]--
-----------------------------------------------------------

if Config.NewCharacterSafeDuration > 0 then 

  Citizen.CreateThread(function()
  
    while true do 

      Wait(60000)

      if JRS.TableLength(ProtectedPlayers) > 0 then

        for _, player in pairs (ProtectedPlayers) do 

          player.duration = player.duration + 1

          if player.duration >= Config.NewCharacterSafeDuration then 
            ProtectedPlayers[player.char] = nil
          end
    
        end

      end

    end

  end)

end



