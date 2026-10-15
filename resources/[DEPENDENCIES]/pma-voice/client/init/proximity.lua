-- used when muted
local disableUpdates = false
local isListenerEnabled = false
local plyCoords = GetEntityCoords(PlayerPedId())

-- Hard voice gate for dead players. This works below the push-to-talk keybind:
-- even if the player rebinds N, a dead client has no Mumble voice targets.
local function isLocalPlayerDeadForVoice()
    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.adminMuted == true then
            return true
        end
        if LocalPlayer.state.isDead == true then
            return true
        end
    end

    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        if IsEntityDead(ped) then
            return true
        end

        if GetEntityHealth(ped) <= 0 then
            return true
        end
    end

    return false
end

function orig_addProximityCheck(ply)
	local tgtPed = GetPlayerPed(ply)
	local voiceModeData = Cfg.voiceModes[mode]
	local distance = GetConvar('voice_useNativeAudio', 'false') == 'true' and voiceModeData[1] * 3 or voiceModeData[1]

	return #(plyCoords - GetEntityCoords(tgtPed)) < distance
end
local addProximityCheck = orig_addProximityCheck

exports("overrideProximityCheck", function(fn)
	addProximityCheck = fn
end)

exports("resetProximityCheck", function()
	addProximityCheck = orig_addProximityCheck
end)

function addNearbyPlayers()
	if disableUpdates then return end

	-- Death is checked here instead of on a keyboard control, so rebinding the
	-- normal push-to-talk key cannot bypass it. Clearing the complete target
	-- immediately stops outgoing proximity voice.
	if isLocalPlayerDeadForVoice() then
		MumbleClearVoiceTarget(voiceTarget)
		MumbleSetVoiceTarget(voiceTarget)
		return
	end

	-- update here so we don't have to update every call of addProximityCheck
	plyCoords = GetEntityCoords(PlayerPedId())

	MumbleClearVoiceTargetChannels(voiceTarget)
	local players = GetActivePlayers()
	for i = 1, #players do
		local ply = players[i]
		local serverId = GetPlayerServerId(ply)

		if addProximityCheck(ply) then
			if isTarget then goto skip_loop end

			logger.verbose('Added %s as a voice target', serverId)
			MumbleAddVoiceTargetChannel(voiceTarget, serverId)
		end

		::skip_loop::
	end
end

function setSpectatorMode(enabled)
	logger.info('Setting spectate mode to %s', enabled)
	isListenerEnabled = enabled
	local players = GetActivePlayers()
	if isListenerEnabled then
		for i = 1, #players do
			local ply = players[i]
			local serverId = GetPlayerServerId(ply)
			if serverId == playerServerId then goto skip_loop end
			logger.verbose("Adding %s to listen table", serverId)
			MumbleAddVoiceChannelListen(serverId)
			::skip_loop::
		end
	else
		for i = 1, #players do
			local ply = players[i]
			local serverId = GetPlayerServerId(ply)
			if serverId == playerServerId then goto skip_loop end
			logger.verbose("Removing %s from listen table", serverId)
			MumbleRemoveVoiceChannelListen(serverId)
			::skip_loop::
		end
	end
end

RegisterNetEvent('onPlayerJoining', function(serverId)
	if isListenerEnabled then
		MumbleAddVoiceChannelListen(serverId)
		logger.verbose("Adding %s to listen table", serverId)
	end
end)

RegisterNetEvent('onPlayerDropped', function(serverId)
	if isListenerEnabled then
		MumbleRemoveVoiceChannelListen(serverId)
		logger.verbose("Removing %s from listen table", serverId)
	end
end)

-- cache talking status so we only send a nui message when its not the same as what it was before
local lastTalkingStatus = false
local lastRadioStatus = false
local voiceState = "proximity"
CreateThread(function()
	TriggerEvent('chat:addSuggestion', '/muteply', 'Mutes the player with the specified id / كتم صوت اللاعب بالرقم المحدد', {
		{ name = "player id", help = "the player to toggle mute / اللاعب المراد كتمه" },
		{ name = "duration", help = "(opt) the duration the mute in seconds (default: 900) / مدة الكتم بالثواني (اختياري، الافتراضي 900)" }
	})
	while true do
		-- wait for mumble to reconnect
		while not MumbleIsConnected() do
			Wait(100)
		end
		-- Leave the check here as we don't want to do any of this logic 
		if GetConvarInt('voice_enableUi', 1) == 1 then
			local curTalkingStatus = MumbleIsPlayerTalking(PlayerId()) == 1
			if lastRadioStatus ~= radioPressed or lastTalkingStatus ~= curTalkingStatus then
				lastRadioStatus = radioPressed
				lastTalkingStatus = curTalkingStatus

				TriggerEvent("jrshud:isTalking",lastTalkingStatus)
				sendUIMessage({
					usingRadio = lastRadioStatus,
					talking = lastTalkingStatus
				})
			end
		end

		if voiceState == "proximity" then
			addNearbyPlayers()
			local isSpectating = NetworkIsInSpectatorMode()
			if isSpectating and not isListenerEnabled then
				setSpectatorMode(true)
			elseif not isSpectating and isListenerEnabled then
				setSpectatorMode(false)
			end
		end

		Wait(GetConvarInt('voice_refreshRate', 200))
	end
end)

exports("setVoiceState", function(_voiceState, channel)
	if _voiceState ~= "proximity" and _voiceState ~= "channel" then
		logger.error("Didn't get a proper voice state, expected proximity or channel, got %s", _voiceState)
	end
	voiceState = _voiceState
	if voiceState == "channel" then
		type_check({channel, "number"})
		-- 65535 is the highest a client id can go, so we add that to the base channel so we don't manage to get onto a players channel
		channel = channel + 65535
		MumbleSetVoiceChannel(channel)
		while MumbleGetVoiceChannelFromServerId(playerServerId) ~= channel do
			Wait(250)
		end
		MumbleAddVoiceTargetChannel(voiceTarget, channel)
	elseif voiceState == "proximity" then
		handleInitialState()
	end
end)


AddEventHandler("onClientResourceStop", function(resource)
	if type(addProximityCheck) == "table" then
		local proximityCheckRef = addProximityCheck.__cfx_functionReference
		if proximityCheckRef then
			local isResource = string.match(proximityCheckRef, resource)
			if isResource then
				addProximityCheck = orig_addProximityCheck
				logger.warn('Reset proximity check to default, the original resource [%s] which provided the function restarted', resource)
			end
		end
	end
end)