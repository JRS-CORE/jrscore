-- ===========================================================================
-- Global state & static data tables
-- ===========================================================================

eWeaponAttachPoint ={WEAPON_ATTACH_POINT_INVALID = -1,	WEAPON_ATTACH_POINT_HAND_PRIMARY = 0,    WEAPON_ATTACH_POINT_PISTOL_R = 2,    WEAPON_ATTACH_POINT_PISTOL_L = 3,    WEAPON_ATTACH_POINT_KNIFE = 4,    WEAPON_ATTACH_POINT_LASSO = 5,    WEAPON_ATTACH_POINT_THROWER = 6,    WEAPON_ATTACH_POINT_BOW = 7,    WEAPON_ATTACH_POINT_BOW_ALTERNATE = 8,    WEAPON_ATTACH_POINT_RIFLE = 9,    WEAPON_ATTACH_POINT_RIFLE_ALTERNATE = 10,    WEAPON_ATTACH_POINT_LANTERN = 11,    WEAPON_ATTACH_POINT_TEMP_LANTERN = 12,    WEAPON_ATTACH_POINT_MELEE = 13,    WEAPON_ATTACH_POINT_HIP = 14,    WEAPON_ATTACH_POINT_BOOT = 15,    WEAPON_ATTACH_POINT_BACK = 16,    WEAPON_ATTACH_POINT_FRONT = 17,    WEAPON_ATTACH_POINT_SHOULDERSLING = 18,    WEAPON_ATTACH_POINT_LEFTBREAST = 19,    WEAPON_ATTACH_POINT_RIGHTBREAST = 20,    WEAPON_ATTACH_POINT_LEFTARMPIT = 21,    WEAPON_ATTACH_POINT_RIGHTARMPIT = 22,    WEAPON_ATTACH_POINT_LEFTARMPIT_RIFLE = 23,    WEAPON_ATTACH_POINT_LEFTARMPIT_BOW = 25,    WEAPON_ATTACH_POINT_RIGHT_HAND_EXTRA = 26,    WEAPON_ATTACH_POINT_LEFT_HAND_EXTRA = 27,    WEAPON_ATTACH_POINT_RIGHT_HAND_AUX = 28,};
ammo_list = {{0x38854A3B,"AMMO_MOONSHINEJUG"},{0x38854A3B,"AMMO_MOONSHINEJUG_MP"},{0x38854A3B,"AMMO_POISONBOTTLE"},{0x38854A3B, "AMMO_RIFLE_ELEPHANT"},{0x38854A3B,"AMMO_HATCHET"},{0x38854A3B,"AMMO_HATCHET_ANCIENT"},{0x38854A3B,"AMMO_HATCHET_CLEAVER"},{0x38854A3B,"AMMO_HATCHET_DOUBLE_BIT"},{0x38854A3B,"AMMO_HATCHET_DOUBLE_BIT_RUSTED"},{0x38854A3B,"AMMO_HATCHET_HEWING"},{0x38854A3B,"AMMO_HATCHET_HUNTER"},{0x38854A3B,"AMMO_HATCHET_HUNTER_RUSTED"},{0x38854A3B,"AMMO_HATCHET_VIKING"},	{0x38854A3B,"AMMO_ARROW"},	{0x38854A3B,"AMMO_22"},	{0x38854A3B,"AMMO_22_TRANQUILIZER"}, {0x38854A3B, "AMMO_REPEATER_SPLIT_POINT"}, {0x38854A3B,"AMMO_BOLAS"}, {0x5B6ABDF8,"AMMO_ARROW_DYNAMITE"},	{0xD19E0045,"AMMO_ARROW_FIRE"},	{0xD62A5A6C,"AMMO_ARROW_POISON"},	{0x3250353B,"AMMO_ARROW_IMPROVED"},	{0x9BD3BBB,"AMMO_ARROW_SMALL_GAME"},	{0xBB8A699D,"AMMO_DYNAMITE"},	{0xDC91634B,"AMMO_DYNAMITE_VOLATILE"},	{0x6AB063DE,"AMMO_MOLOTOV"},	{0xF8FB3AC1,"AMMO_MOLOTOV_VOLATILE"},	{0x80766738,"AMMO_PISTOL"},	{0xF1A91F32,"AMMO_PISTOL_EXPRESS"},	{0x331B008B,"AMMO_PISTOL_EXPRESS_EXPLOSIVE"},	{0x46F7AA64,"AMMO_PISTOL_HIGH_VELOCITY"},	{0xAD60BB5F,"AMMO_PISTOL_SPLIT_POINT"},	{0x5E490BAA,"AMMO_REPEATER"},	{0x197A9C10,"AMMO_REPEATER_EXPRESS"},	{0x2390F9C2,"AMMO_REPEATER_EXPRESS_EXPLOSIVE"},	{0x4FFBFA8C,"AMMO_REPEATER_HIGH_VELOCITY"},	{0x4CE87556,"AMMO_REVOLVER"},	{0x3C932F5C,"AMMO_REVOLVER_EXPRESS"},	{0xAFD00F7F,"AMMO_REVOLVER_EXPRESS_EXPLOSIVE"},	{0x129C46F,"AMMO_REVOLVER_HIGH_VELOCITY"},	{0x9C6310D4,"AMMO_REVOLVER_SPLIT_POINT"},	{0xBAFF5180,"AMMO_RIFLE"},	{0x2CE404A4,"AMMO_RIFLE_EXPRESS"},	{0x9116173,"AMMO_RIFLE_EXPRESS_EXPLOSIVE"},	{0xF76DC763,"AMMO_RIFLE_HIGH_VELOCITY"},	{0xC1711828,"AMMO_RIFLE_SPLIT_POINT"},	{0xB7DB96B8,"AMMO_RIFLE_VARMINT"},	{0x58B272F9,"AMMO_SHOTGUN"},	{0xC71EE56D,"AMMO_SHOTGUN_BUCKSHOT_INCENDIARY"},	{0x3450D03C,"AMMO_SHOTGUN_SLUG"},	{0x4BB641AD,"AMMO_SHOTGUN_EXPRESS_EXPLOSIVE"},	{0xCFE15715,"AMMO_THROWING_KNIVES"},	{0xB846FB5B,"AMMO_THROWING_KNIVES_IMPROVED"},{0xB846FB5B,"AMMO_TOMAHAWK"},{0x52D4ED54,"AMMO_TOMAHAWK_IMPROVED"},{0xF7E7B447,"AMMO_BOW"},{0x6D8A1ADE,"AMMO_BOW_FIRE"},{0x4CD3A132,"AMMO_BOW_IMPROVED"},{0x4E6EE57,"AMMO_BOW_POISON"},{0xDFE48CED,"AMMO_BOW_SMALL_GAME"},{0x5CBC3921,"AMMO_FISHINGPOLE"},{0x7D3A281B,"AMMO_FISHINGBAIT"},{0x89E4BE4A,"AMMO_LASSO"},{0x66251BC4,"AMMO_LASSO_REINFORCED"},{0xB5E9AAE,"AMMO_MELEE"},{0x2D7CC8AE,"AMMO_MELEE_COLT"},{0x10D7204B,"AMMO_MELEE_KNIFE"},{0x3E61454A,"AMMO_MELEE_LANTERN"},{0x8C514F89,"AMMO_MELEE_TORCH"},{0x4B0D01EE,"AMMO_MELEE_BROKENBOTTLE"},{0x832645C3,"AMMO_MELEE_HATCHET"},{0x7900F0D6,"AMMO_MELEE_HAMMER"},{0xE96216C,"AMMO_MELEE_CLEAVER"},{0x6A03B149,"AMMO_MELEE_ANCIENT_HATCHET"},{0x186EBF1,"AMMO_MELEE_HUNTER_HATCHET"},{0xAD14CC02,"AMMO_MELEE_HATCHET_VIKING"},{0x59C1D64B,"AMMO_MELEE_MACHETE"},{0xDA4BDDDA,"AMMO_MELEE_JAVELIN"}}
inventory_table, weapon_table, dropped_items, dropped_items_entity = {}, {}, {}, {}
max_weapons_limit = Config.Max_Weapons
weapon_first_used, weapon_second_used, rifle_first_used, rifle_second_used = false, false, false, false
active = false
buttons_prompt = GetRandomIntInRange(0, 0xffffff)
condition_level = {}
money_state = 0
gold_state = 0
dirtymoney_state = 0
storage_table = {}
size = 0
backup_save_throw = 0
is_last_ammo = false
id_container = 0
equip_spam = false
speed, count_in_inventory = tonumber(Config.DefaultMoveSpeed) or 0.0, 0.0
can_save, ignorMeForLoadThrow, ignorMeForLoadNormal = false, false, false
devReinitInProgress = false

xRes,yRes = 0.0,0.0
saveTableFilter, saveTableFilter2, backupAmmoNormal, ammoNormal, backupAmmoThrow, ammoThrow = {}, {}, {}, {}, {}, {}
weaponAmmoRevision = {}
transferCount, waitForInteraction = 0, nil
isAttachedToPlayer = false
canSkipWeapon = false
blockSpamming = false

local inventoryOperationSequence = 0
function NewInventoryOperationId(action)
    inventoryOperationSequence = inventoryOperationSequence + 1
    if inventoryOperationSequence > 999999 then inventoryOperationSequence = 1 end
    return ("%s:%s:%s:%s"):format(
        tostring(action or "inventory"),
        tostring(GetPlayerServerId(PlayerId())),
        tostring(GetGameTimer()),
        tostring(inventoryOperationSequence)
    )
end
slot1 = {}
slot2 = {}
slot3 = {}
slot4 = {}
slot5 = {}
giveItemEnable = false
idPlayerForItem = 0
playerDragId = 0
inventoryLoadPending = false
inventoryItemsReady = false
inventoryGroundReady = false
guiEnabled = false
inventoryCharacterReady = false
inventoryHudBlocked = false

-- Player robbery container mode. The right-hand inventory is a live player,
-- never an inventory_storage row. All moves are validated by the integrated robbery server module.
robberyMode = false
robberyTargetId = 0
robberyTargetName = ""
robberyPendingPayload = nil
robberyInitialOpenPending = false

-- Keep the metabolism HUD synchronized with every inventory/container path.
-- This explicit signal is more reliable than depending on NUI focus alone.
function SetInventoryHudBlocked(state)
	state = state == true
	if inventoryHudBlocked == state then return end

	inventoryHudBlocked = state
	-- Central gate: hides the jrs_core HUD too and forwards to jrs_metabolism.
	TriggerEvent('jrs_hud:busy', 'jrs_inventory', state)
	-- Direct fallback so the status HUD still hides if jrs_core is not running.
	TriggerEvent('jrs_metabolism:setHudBlocked', state, 'jrs_inventory')
end

local holsterKeyWasDown = false
local lanternKeyWasDown = false
local GROUND_PROMPT_DISTANCE = tonumber(Config.GroundPromptDistance) or 0.7

-- ===========================================================================
-- Button prompt
-- ===========================================================================

function Button_Prompt()
	Citizen.CreateThread(function()
		local str = _U('pick_up')
		PickItemGround = Citizen.InvokeNative(0x04F97DE45A519419)
		PromptSetControlAction(PickItemGround, Config.PickupControlHash)
		str = CreateVarString(10, 'LITERAL_STRING', str)
		PromptSetText(PickItemGround, str)
		PromptSetEnabled(PickItemGround, true)
		PromptSetVisible(PickItemGround, true)
		PromptSetHoldMode(PickItemGround, true)
		PromptSetGroup(PickItemGround, buttons_prompt)
		PromptRegisterEnd(PickItemGround)
	end)
end

-- ===========================================================================
-- Resource restart recovery
-- ===========================================================================

-- txAdmin restarts recreate this client resource without replaying the old
-- jrs:SelectedCharacter event. The server detects already-online players after
-- its own resource start and sends restartSyncReady only to those characters.
RegisterNetEvent('jrs_inventory:restartSyncReady')
AddEventHandler('jrs_inventory:restartSyncReady', function()
	if inventoryCharacterReady then return end
	inventoryCharacterReady = true
	TriggerServerEvent('jrs_inventory:get_items')
	TriggerServerEvent('jrs_inventory:get_money')
	Button_Prompt()
end)

RegisterNetEvent('jrs_inventory:forceInventoryReload')
AddEventHandler('jrs_inventory:forceInventoryReload', function()
	TriggerServerEvent('jrs_inventory:get_items')
end)

RegisterNetEvent('jrs_inventory:ReloadClanInventory')
AddEventHandler('jrs_inventory:ReloadClanInventory', function()
	TriggerEvent('jrs_inventory:forceInventoryReload')
end)

RegisterNetEvent('jrs_inventory:closeInventory')
AddEventHandler('jrs_inventory:closeInventory', function()
	TriggerEvent('jrs_inventory:CloseInv')
end)

RegisterNetEvent('jrs_inventory:can_save')
AddEventHandler('jrs_inventory:can_save', function()
	can_save = true
end)

RegisterNetEvent('jrs_inventory:saveAmmo')
AddEventHandler('jrs_inventory:saveAmmo', function()
	if checkNormalAmmo then checkNormalAmmo() end
	if saveThrowAmmo then saveThrowAmmo() end
end)

-- ===========================================================================
-- Commands & Dev Mode
-- ===========================================================================

RegisterCommand(Config.OpenInventoryCommand, function(source, args, rawCommand)
	OpenInventory()
end)

-- RedM inventory key handling intentionally uses the native control hash instead
-- of RegisterKeyMapping. RegisterKeyMapping is unreliable/not functional on some
-- RedM builds. A dedicated one-control frame loop below catches quick taps without
-- forcing the rest of the inventory background logic to run every frame.

if Config.DevMode then
	RegisterCommand(Config.DevCommand, function(source, args, rawCommand)
		TriggerServerEvent("jrs_inventory:devReinitRequest")
	end)
end

RegisterNetEvent('jrs_inventory:devReinitReset')
AddEventHandler('jrs_inventory:devReinitReset', function()
	devReinitInProgress = true
	inventoryLoadPending = false
	Show_Items(false, false)
	SetNuiFocus(false, false)
	guiEnabled = false
	-- Keep the last confirmed inventory until the server sends a replacement.
	-- Clearing it here made a failed development reload look like item loss.
	weaponAmmoRevision = {}
	Citizen.CreateThread(function()
		Citizen.Wait(Config.InventoryLoadTimeoutMs)
		devReinitInProgress = false
	end)
end)

-- ===========================================================================
-- Character selection
-- ===========================================================================

RegisterNetEvent("jrs_character:check_char")
AddEventHandler("jrs_character:check_char", function()
	inventoryCharacterReady = false
	inventoryLoadPending = false
	inventory_table = {}
	weapon_table = {}
	weaponAmmoRevision = {}
	slot1, slot2, slot3, slot4, slot5 = {}, {}, {}, {}, {}
	money_state = 0
	gold_state = 0
	dirtymoney_state = 0
	Show_Items(false)
	SetNuiFocus(false, false)
	guiEnabled = false
end)

RegisterNetEvent("jrs:SelectedCharacter")
AddEventHandler("jrs:SelectedCharacter", function()
	if inventoryCharacterReady then return end
	inventoryCharacterReady = true
	Citizen.CreateThread(function()
		Citizen.Wait(Config.CharacterLoadDelayMs)
		TriggerServerEvent("jrs_inventory:get_items")
		Citizen.Wait(500)
		TriggerServerEvent("jrs_inventory:get_money")
		Citizen.Wait(1000)
		equip_weapon_login()
		Button_Prompt()
	end)
	Citizen.CreateThread(function()
		local nextPromptNameRefreshAt = 0
		while true do
			local hasEquippedInventoryWeapon = false
			if weapon_first_used ~= false or weapon_second_used ~= false or rifle_first_used ~= false or rifle_second_used ~= false then
				hasEquippedInventoryWeapon = true
			else
				for _, weapon in pairs(weapon_table or {}) do
					if tonumber(weapon.used) == 1 then
						hasEquippedInventoryWeapon = true
						break
					end
				end
			end

			-- saveWeaponAmmo/saveThrowAmmo iterate the full ammo definition list and
			-- call natives for each type. When no inventory weapon is equipped, ammo
			-- cannot be changing, so the expensive scan is skipped completely.
			if can_save and hasEquippedInventoryWeapon then
				saveThrowAmmo()
				saveWeaponAmmo()
			end

			local now = GetGameTimer()
			if now >= nextPromptNameRefreshAt then
				for _, player in ipairs(GetActivePlayers()) do
					SetPedPromptName(GetPlayerPed(player), "Citizen (" .. tostring(GetPlayerServerId(player))..")")
				end
				nextPromptNameRefreshAt = now + ((Config.Performance and tonumber(Config.Performance.PedPromptNameRefreshMs)) or 15000)
			end

			local perf = Config.Performance or {}
			Citizen.Wait(hasEquippedInventoryWeapon and (tonumber(perf.AmmoSaveActiveMs) or 5000) or (tonumber(perf.AmmoSaveIdleMs) or 15000))
		end
	end)
end)

-- Called by spawnmanager on normal spawns/respawns. The character-ready guard
-- prevents the character-selection preview ped from affecting inventory data.
AddEventHandler('playerSpawned', function()
	if not Config.UnequipWeaponsOnSpawn then return end

	Citizen.CreateThread(function()
		Citizen.Wait(tonumber(Config.RespawnWeaponCleanupDelayMs) or 1500)
		if inventoryCharacterReady then
			UnequipAllWeaponsToInventory(true)
		end
	end)
end)

-- Other respawn/death resources can call this event after reviving the player:
-- TriggerEvent('jrs_inventory:unequipWeaponsToBag')
RegisterNetEvent('jrs_inventory:unequipWeaponsToBag')
AddEventHandler('jrs_inventory:unequipWeaponsToBag', function()
	Citizen.CreateThread(function()
		Citizen.Wait(tonumber(Config.RespawnWeaponCleanupDelayMs) or 1500)
		if inventoryCharacterReady then
			UnequipAllWeaponsToInventory(true)
		end
	end)
end)

-- ===========================================================================
-- Main loops
-- ===========================================================================

-- The server broadcasts drop changes. Avoid refreshing the entire ground list
-- merely because the player walked near a prop; that caused slot flicker in NUI.

local function perfMs(key, fallback)
	local perf = Config.Performance or {}
	return math.max(0, tonumber(perf[key]) or fallback)
end

local function isControlDown(controlHash)
	local value = Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, controlHash)
	return value == true or value == 1
end

-- Dedicated RedM-native open-key watcher. Only ONE control native is queried per
-- frame while gameplay is active. This catches even very quick taps while keeping
-- the heavier inventory/ground/weapon scans on their low-frequency timers.
Citizen.CreateThread(function()
	local inventoryOpenKeyWasDown = false
	while true do
		if not inventoryCharacterReady then
			inventoryOpenKeyWasDown = false
			Citizen.Wait(500)
		elseif guiEnabled then
			-- Keep the previous key state while NUI owns focus. This prevents a held
			-- I key from immediately reopening the inventory after it is closed.
			Citizen.Wait(100)
		else
			local keyDown = isControlDown(Config.openinv)
			if keyDown and not inventoryOpenKeyWasDown then
				inventoryOpenKeyWasDown = true
				OpenInventory()
			elseif not keyDown then
				inventoryOpenKeyWasDown = false
			end
			Citizen.Wait(0)
		end
	end
end)

Citizen.CreateThread(function()
	TriggerServerEvent("jrs_inventory:check_drops_1")
	while true do
		-- Before a character is selected there is nothing for this loop to do.
		if not inventoryCharacterReady then
			holsterKeyWasDown, lanternKeyWasDown = false, false
			Citizen.Wait(1000)
		elseif guiEnabled then
			-- NUI owns input while the inventory is open.
			holsterKeyWasDown, lanternKeyWasDown = false, false
			Citizen.Wait(perfMs('OpenKeyUiMs', 250))
		else
			is_last_ammo = false
			local ped = PlayerPedId()

			-- Holster and lantern actions are edge-triggered. Holding the key no longer
			-- repeats expensive weapon natives several times per second.
			local canDualHolster = weapon_first_used ~= false and weapon_second_used ~= false
			local holsterDown = canDualHolster and isControlDown(Config.WeaponHolsterControlHash) or false
			if holsterDown and not holsterKeyWasDown then
				Citizen.InvokeNative(0x5E3BDDBCB83F3D84, ped, GetHashKey(weapon_first_used), 0, 1, 1, 2, 0, 0.5, 1.0, GetHashKey('ADD_REASON_DEFAULT'), 0, 0.0, false)
				Citizen.InvokeNative(0x5E3BDDBCB83F3D84, ped, GetHashKey(weapon_second_used), 0, 1, 1, 3, 1, 0.5, 1.0, GetHashKey('ADD_REASON_DEFAULT'), 1, 0.0, false)
				Citizen.InvokeNative(0xADF692B254977C0C, ped, GetHashKey(weapon_first_used), 0, 0, 0, 0)
				Citizen.InvokeNative(0xADF692B254977C0C, ped, GetHashKey(weapon_second_used), 0, 1, 0, 0)
			end
			holsterKeyWasDown = holsterDown

			local lanternDown = isControlDown(Config.LanternToggleControlHash)
			if lanternDown and not lanternKeyWasDown then
				local _, wepHash = GetCurrentPedWeapon(ped, true, 0, true)
				if GetHashKey('weapon_melee_davy_lantern') == wepHash then
					GiveWeaponToPed_2(ped, GetHashKey('weapon_melee_davy_lantern'), 0, true, true, 12, false, 0.5, 1.0, 752097756, false, 0, false)
					Citizen.InvokeNative(0xADF692B254977C0C, ped, GetHashKey('weapon_melee_davy_lantern'), 0, 12, 0, 0)
				end
			end
			lanternKeyWasDown = lanternDown

			Citizen.Wait(perfMs('OpenKeyIdleMs', 50))
		end
	end
end)

-- Cache prompt strings. Creating VarStrings and scanning the full item/weapon
-- definitions every frame was one of the most expensive ground-drop paths.
local groundPromptStringCache = {}
local groundItemLabelCache = {}
local groundWeaponLabelCache = {}

local function findGroundItemLabel(itemName)
	itemName = tostring(itemName or '')
	if groundItemLabelCache[itemName] then return groundItemLabelCache[itemName] end
	for _, value in pairs(table_item or {}) do
		if tostring(value.item) == itemName then
			groundItemLabelCache[itemName] = tostring(value.label or itemName)
			return groundItemLabelCache[itemName]
		end
	end
	groundItemLabelCache[itemName] = itemName
	return itemName
end

local function findGroundWeaponLabel(weaponName)
	weaponName = tostring(weaponName or '')
	if groundWeaponLabelCache[weaponName] then return groundWeaponLabelCache[weaponName] end
	for _, value in pairs(wp_table or {}) do
		if tostring(value.item) == weaponName then
			groundWeaponLabelCache[weaponName] = tostring(value.label or weaponName)
			return groundWeaponLabelCache[weaponName]
		end
	end
	groundWeaponLabelCache[weaponName] = weaponName
	return weaponName
end

local function getGroundPromptString(drop)
	local key = table.concat({ tostring(drop.item or ''), tostring(drop.count or 1), tostring(drop.weapon_model or '') }, ':')
	-- Only the Lua text is cached: a CreateVarString pointer is valid for one
	-- frame, reusing it later shows another script's text in the prompt title.
	if groundPromptStringCache[key] then return CreateVarString(10, 'LITERAL_STRING', groundPromptStringCache[key]) end

	local text
	if drop.weapon == true then
		text = _U('box_with') .. ' : ' .. findGroundWeaponLabel(drop.weapon_model)
	elseif drop.item == 'money' then
		text = _U('moneys') .. ' : ' .. tostring(drop.count or 1) .. '$'
	elseif drop.item == 'gold' then
		text = _U('busket_with_gold') .. ' : ' .. tostring(drop.count or 1) .. 'G'
	elseif drop.item == 'dirtymoney' then
		text = _U('dirtymoney') .. ' : ' .. tostring(drop.count or 1) .. '$'
	else
		text = _U('busket_with_items') .. ' : ' .. tostring(drop.count or 1) .. 'x ' .. findGroundItemLabel(drop.item)
	end

	groundPromptStringCache[key] = text
	return CreateVarString(10, 'LITERAL_STRING', text)
end

Citizen.CreateThread(function()
	-- Ground drops are intentionally visual props only. With this disabled,
	-- the world pickup prompt thread exits completely and costs no runtime.
	if Config.GroundWorldPromptEnabled ~= true then return end

	while true do
		-- Zero drops is the common case. Do not call any player/entity natives here.
		if not inventoryCharacterReady or next(dropped_items_entity or {}) == nil then
			Citizen.Wait(perfMs('GroundNoDropsMs', 2000))
		else
			local ped = PlayerPedId()
			local playerCoords = GetEntityCoords(ped)
			local nearestDrop, nearestDistanceSq = nil, math.huge

			-- Player coordinates are read once per scan. The previous implementation
			-- called GetEntityCoords(PlayerPedId()) once for every single ground drop.
			for _, drop in pairs(dropped_items_entity or {}) do
				local dx, dy, dz
				if drop.x ~= nil and drop.y ~= nil and drop.z ~= nil then
					dx = playerCoords.x - (tonumber(drop.x) or 0.0)
					dy = playerCoords.y - (tonumber(drop.y) or 0.0)
					dz = playerCoords.z - (tonumber(drop.z) or 0.0)
				elseif drop.entity and drop.entity ~= 0 and DoesEntityExist(drop.entity) then
					local c = GetEntityCoords(drop.entity)
					dx, dy, dz = playerCoords.x - c.x, playerCoords.y - c.y, playerCoords.z - c.z
				end
				if dx then
					local distanceSq = dx * dx + dy * dy + dz * dz
					if distanceSq < nearestDistanceSq then
						nearestDrop, nearestDistanceSq = drop, distanceSq
					end
				end
			end

			local nearestDistance = nearestDrop and math.sqrt(nearestDistanceSq) or math.huge
			if nearestDrop and nearestDistance <= GROUND_PROMPT_DISTANCE and active == false then
				local _, closestDistance = GetClosestPlayer()
				if closestDistance == -1 or closestDistance >= 2.0 then
					PromptSetActiveGroupThisFrame(buttons_prompt, getGroundPromptString(nearestDrop))
					if Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, Config.PickupControlHash) then OpenInventory() end
				end
				Citizen.Wait(perfMs('GroundNearScanMs', 15))
			elseif nearestDrop and nearestDistance <= perfMs('GroundMidDistance', 3.0) then
				Citizen.Wait(perfMs('GroundMidScanMs', 100))
			else
				Citizen.Wait(perfMs('GroundFarScanMs', 600))
			end
		end
	end
end)

local hotbarControlWasDown = { false, false, false, false, false }
local hotbarBlockUntilRelease = { false, false, false, false, false }
local hotbarUseAllowedAt = { 0, 0, 0, 0, 0 }
local hotbarRepairSaveAllowedAt = 0

local function HotbarSnapshot()
	return {
		slot1 = type(slot1) == "table" and slot1 or {},
		slot2 = type(slot2) == "table" and slot2 or {},
		slot3 = type(slot3) == "table" and slot3 or {},
		slot4 = type(slot4) == "table" and slot4 or {},
		slot5 = type(slot5) == "table" and slot5 or {}
	}
end

local function SyncHotbarRepair(force)
	local now = GetGameTimer()
	if not force and now < hotbarRepairSaveAllowedAt then return end
	hotbarRepairSaveAllowedAt = now + 750
	local hotbar = HotbarSnapshot()
	TriggerServerEvent("jrs_inventory:saveHotbar", hotbar)
	SendNUIMessage({ type = "loadHotbar", hotbar = hotbar })
end

local function ClearRuntimeHotbarSlot(index, slotData)
	if type(slotData) == "table" then
		for key in pairs(slotData) do slotData[key] = nil end
	end
	hotbarControlWasDown[index] = false
	SyncHotbarRepair(false)
end

local function FindRuntimeHotbarWeapon(slotData)
	local wantedId = tonumber(slotData and slotData.id)
	local wantedName = tostring(slotData and slotData.item or "")
	if not wantedId or wantedName == "" then return nil end

	local wantedUpper = string.upper(wantedName)
	for _, weapon in pairs(weapon_table or {}) do
		if tonumber(weapon.id) == wantedId and string.upper(tostring(weapon.name)) == wantedUpper then
			return weapon
		end
	end
	return nil
end

local function FindRuntimeHotbarItem(slotData)
	local wantedId = tonumber(slotData and slotData.id)
	local wantedName = tostring(slotData and slotData.item or "")
	local fallbackItem = nil
	if wantedName == "" then return nil, false end

	for _, item in pairs(inventory_table or {}) do
		if tostring(item.item) == wantedName and tonumber(item.count or 0) > 0 then
			fallbackItem = fallbackItem or item
			if wantedId and tonumber(item.itemId) == wantedId then
				return item, false
			end
		end
	end

	return fallbackItem, fallbackItem ~= nil
end

local function HandleHotbarControl(index, controlHash, slotData)
	local hasSlot = type(slotData) == "table" and next(slotData) ~= nil
	if not hasSlot then
		hotbarControlWasDown[index] = false
		return false
	end

	DisableControlAction(0, controlHash, true)
	local isPressed = IsDisabledControlJustPressed(0, controlHash) or IsControlJustPressed(0, controlHash)

	if guiEnabled or hotbarBlockUntilRelease[index] then
		if not IsDisabledControlPressed(0, controlHash) and not IsControlPressed(0, controlHash) then
			hotbarBlockUntilRelease[index] = false
		end
		return true
	end

	if not isPressed then
		return true
	end

	local now = GetGameTimer()
	if now < (hotbarUseAllowedAt[index] or 0) then
		return true
	end
	hotbarUseAllowedAt[index] = now + (tonumber(Config.HotbarUseCooldownMs) or 400)

	if slotData.weapon == true then
		local weapon = FindRuntimeHotbarWeapon(slotData)
		if not weapon then
			ClearRuntimeHotbarSlot(index, slotData)
			return false
		end

		UseWeapon({ id = tonumber(weapon.id) or weapon.id, model = weapon.name })
		return true
	end

	local itemToUse, repairedId = FindRuntimeHotbarItem(slotData)
	if not itemToUse then
		ClearRuntimeHotbarSlot(index, slotData)
		return false
	end

	if repairedId or tonumber(slotData.id) ~= tonumber(itemToUse.itemId) then
		slotData.id = tonumber(itemToUse.itemId) or itemToUse.itemId
		SyncHotbarRepair(false)
	end

	TriggerServerEvent("jrs:use", itemToUse.item, itemToUse.itemId)
	return true
end

-- Hotbar input is isolated from the player-target interaction scanner. When at
-- least one shortcut exists this tiny five-control loop runs each frame so even
-- a very quick 1..5 tap is captured; with an empty hotbar it sleeps deeply.
Citizen.CreateThread(function()
	while true do
		if not inventoryCharacterReady then
			hotbarControlWasDown = { false, false, false, false, false }
			Citizen.Wait(1000)
		elseif guiEnabled then
			-- Number keys pressed while NUI has focus must be released before a
			-- gameplay shortcut can fire after closing the inventory.
			hotbarControlWasDown = { false, false, false, false, false }
			hotbarBlockUntilRelease = { true, true, true, true, true }
			Citizen.Wait(perfMs('OpenKeyUiMs', 250))
		else
			local has1 = type(slot1) == 'table' and next(slot1) ~= nil
			local has2 = type(slot2) == 'table' and next(slot2) ~= nil
			local has3 = type(slot3) == 'table' and next(slot3) ~= nil
			local has4 = type(slot4) == 'table' and next(slot4) ~= nil
			local has5 = type(slot5) == 'table' and next(slot5) ~= nil
			local hasAnySlot = has1 or has2 or has3 or has4 or has5

			if has1 then HandleHotbarControl(1, Config.WeaponSlot1ControlHash, slot1) else hotbarControlWasDown[1] = false end
			if has2 then HandleHotbarControl(2, Config.WeaponSlot2ControlHash, slot2) else hotbarControlWasDown[2] = false end
			if has3 then HandleHotbarControl(3, Config.WeaponSlot3ControlHash, slot3) else hotbarControlWasDown[3] = false end
			if has4 then HandleHotbarControl(4, Config.WeaponSlot4ControlHash, slot4) else hotbarControlWasDown[4] = false end
			if has5 then HandleHotbarControl(5, Config.WeaponSlot5ControlHash, slot5) else hotbarControlWasDown[5] = false end

			Citizen.Wait(hasAnySlot and 0 or perfMs('HotbarIdleMs', 500))
		end
	end
end)

local socialPromptTarget = 0
local socialPromptHostage = false
local playerInteractions = Config.GetPlayerInteractions()

local function deleteSocialPrompts()
	if player_prompt then pcall(function() player_prompt:delete() end); player_prompt = nil end
	if player_prompt2 then pcall(function() player_prompt2:delete() end); player_prompt2 = nil end
	if player_prompt3 then pcall(function() player_prompt3:delete() end); player_prompt3 = nil end
	socialPromptTarget = 0
	socialPromptHostage = false
end

local function ensureSocialPrompts(targetPed, canHostage)
	if socialPromptTarget == targetPed and socialPromptHostage == canHostage then
		return
	end
	deleteSocialPrompts()
	local promptGroup = PromptGetGroupIdForTargetEntity(targetPed)
	if playerInteractions.GiveHand ~= false then
		player_prompt = Uiprompt:new(playerInteractions.GiveHandControlHash, _U('give_hand'), promptGroup)
	end
	if playerInteractions.GiveSlap ~= false then
		player_prompt2 = Uiprompt:new(playerInteractions.GiveSlapControlHash, _U('give_slap'), promptGroup)
	end
	if canHostage and playerInteractions.TakeHostage ~= false then
		player_prompt3 = Uiprompt:new(playerInteractions.TakeHostageControlHash, _U('hostage'), promptGroup)
	end
	socialPromptTarget = targetPed
	socialPromptHostage = canHostage
end

local function playerIndexFromPed(targetPed)
	for _, player in ipairs(GetActivePlayers()) do
		if GetPlayerPed(player) == targetPed then return player end
	end
	return -1
end

Citizen.CreateThread(function()
	while true do
		local waitMs = perfMs('SocialIdleMs', 350)
		if playerInteractions.Enabled == false then
			deleteSocialPrompts()
			waitMs = 1000
		elseif not inventoryCharacterReady then
			deleteSocialPrompts()
			waitMs = 1000
		elseif guiEnabled then
			deleteSocialPrompts()
			waitMs = perfMs('OpenKeyUiMs', 250)
		elseif #GetActivePlayers() <= 1 then
			-- No other streamed player can be targeted, so skip target/entity natives.
			deleteSocialPrompts()
			waitMs = 1000
		else
			local isTargetting, targetEntity = GetPlayerTargetEntity(PlayerId())
			if isTargetting and targetEntity and targetEntity ~= 0 then
				local targetPlayer = playerIndexFromPed(targetEntity)
				if targetPlayer ~= -1 then
					local ped = PlayerPedId()
					local holding = Citizen.InvokeNative(0xD806CD2A4F2C2996, ped)
					local targetCoords = GetEntityCoords(targetEntity)
					local myCoords = GetEntityCoords(ped)
					local dx, dy, dz = myCoords.x - targetCoords.x, myCoords.y - targetCoords.y, myCoords.z - targetCoords.z
					local distanceSq = (dx * dx) + (dy * dy) + (dz * dz)

					if holding == false and distanceSq < (Config.InteractionDistance * Config.InteractionDistance) then
						local combatStance = IsPedInMeleeCombat(ped)
						if combatStance == false and not IsEntityDead(targetEntity) and GetEntityHealth(ped) > 0 and GetMount(targetEntity) == 0 and GetMount(ped) == 0 and GetVehiclePedIsUsing(targetEntity) == 0 and GetEntityHealth(targetEntity) >= 0.0 then
							local _, wepHash = GetCurrentPedWeapon(ped, true, 0, true)
							local canHostage = GetHashKey('GROUP_MELEE') == GetWeapontypeGroup(wepHash)
							ensureSocialPrompts(targetEntity, canHostage)
							local serverId = GetPlayerServerId(targetPlayer)
							waitMs = perfMs('SocialTargetMs', 15)

							if canHostage and playerInteractions.TakeHostage ~= false and Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, playerInteractions.TakeHostageControlHash) then
								TriggerServerEvent("jrs_inventory:hostage", serverId)
								Citizen.Wait(tonumber(playerInteractions.HostageTakeCooldownMs) or 1000)
							elseif playerInteractions.GiveSlap ~= false and Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, playerInteractions.GiveSlapControlHash) then
								TriggerServerEvent("jrs_inventory:give_slap", serverId)
								Citizen.Wait(tonumber(playerInteractions.SocialActionCooldownMs) or 2000)
							elseif playerInteractions.GiveHand ~= false and Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, playerInteractions.GiveHandControlHash) then
								TriggerServerEvent("jrs_inventory:give_hand", serverId)
								Citizen.Wait(tonumber(playerInteractions.SocialActionCooldownMs) or 2000)
							end
						else
							deleteSocialPrompts()
						end
					else
						deleteSocialPrompts()
					end
				else
					deleteSocialPrompts()
				end
			else
				deleteSocialPrompts()
			end
		end
		Citizen.Wait(waitMs)
	end
end)

-- Carried-weight locomotion limiter.
-- The original working JRS system used SET_PED_MAX_MOVE_BLEND_RATIO. A later
-- optimization switched this to SET_PED_MOVE_RATE_OVERRIDE, which changed the
-- meaning/range of the configured values and caused the RedM weight penalty to
-- stop behaving as intended. Keep the original RDR3 blend-ratio mechanism and
-- refresh it every frame only while a penalty is active.
Citizen.CreateThread(function()
	local lastPed = 0
	local wasLimited = false

	while true do
		local ped = PlayerPedId()
		local normalBlend = math.max(0.0, math.min(3.0, tonumber(Config.NormalMoveBlendRatio) or 3.0))
		local currentBlend = math.max(0.0, math.min(3.0, tonumber(speed) or 0.0))
		local hasWeightPenalty = Config.WeightSpeedEnabled ~= false
			and currentBlend > 0.0
			and currentBlend < normalBlend

		if ped ~= 0 then
			if hasWeightPenalty then
				-- RDR3 native: SET_PED_MAX_MOVE_BLEND_RATIO
				Citizen.InvokeNative(0x433083750C5E064A, ped, currentBlend)
				wasLimited = true
			elseif wasLimited or ped ~= lastPed then
				-- Explicitly restore full movement when weight drops below the first tier,
				-- when the system is disabled, or when the player's ped changes.
				Citizen.InvokeNative(0x433083750C5E064A, ped, normalBlend)
				SetPedMoveRateOverride(ped, 1.0)
				wasLimited = false
			end
		end

		lastPed = ped
		if hasWeightPenalty then
			Citizen.Wait(0)
		else
			Citizen.Wait(perfMs('MoveSpeedRefreshMs', 1000))
		end
	end
end)

-- ===========================================================================
-- Resource stop cleanup
-- ===========================================================================

AddEventHandler('onResourceStop', function(resourceName)
	if (GetCurrentResourceName() == resourceName) then
		local ped = PlayerPedId()
		if ped ~= 0 then
			Citizen.InvokeNative(0x433083750C5E064A, ped, math.max(0.0, math.min(3.0, tonumber(Config.NormalMoveBlendRatio) or 3.0)))
			SetPedMoveRateOverride(ped, 1.0)
		end
		SetInventoryHudBlocked(false)
		for k,v in pairs(dropped_items_entity) do
            DeleteEntity(v.entity)
        end
	end
end)

-- ===========================================================================
-- CloseInv2 (used by transfer flow)
-- ===========================================================================

RegisterNetEvent('jrs_inventory:CloseInv2')
AddEventHandler('jrs_inventory:CloseInv2', function()
	Show_Items(false, false)
	SetNuiFocus(true, true)
end)

-- ===========================================================================
-- Give player selector
-- ===========================================================================

-- Player selection for Give Item / Give Weapon is handled by the integrated
-- on-screen player selector in client/inventory.lua.  The previous raycast
-- cursor selector was removed so only the visible ID markers are used.

-- ===========================================================================
-- DataView class (binary buffer)
-- ===========================================================================

local _strblob = string.blob or function(length)
    return string.rep("\0", math.max(40 + 1, length))
end

DataView = {
    EndBig = ">",
    EndLittle = "<",
    Types = {
        Int8 = { code = "i1", size = 1 },
        Uint8 = { code = "I1", size = 1 },
        Int16 = { code = "i2", size = 2 },
        Uint16 = { code = "I2", size = 2 },
        Int32 = { code = "i4", size = 4 },
        Uint32 = { code = "I4", size = 4 },
        Int64 = { code = "i8", size = 8 },
        Uint64 = { code = "I8", size = 8 },
        LuaInt = { code = "j", size = 8 },
        UluaInt = { code = "J", size = 8 },
        LuaNum = { code = "n", size = 8},
        Float32 = { code = "f", size = 4 },
        Float64 = { code = "d", size = 8 },
        String = { code = "z", size = -1, },
    },
    FixedTypes = {
        String = { code = "c", size = -1, },
        Int = { code = "i", size = -1, },
        Uint = { code = "I", size = -1, },
    },
}
DataView.__index = DataView

local function _ib(o, l, t) return ((t.size < 0 and true) or (o + (t.size - 1) <= l)) end
local function _ef(big) return (big and DataView.EndBig) or DataView.EndLittle end
local SetFixed = nil

function DataView.ArrayBuffer(length)
    return setmetatable({
        offset = 1, length = length, blob = _strblob(length)
    }, DataView)
end

function DataView.Wrap(blob)
    return setmetatable({
        offset = 1, blob = blob, length = blob:len(),
    }, DataView)
end

function DataView:Buffer() return self.blob end
function DataView:ByteLength() return self.length end
function DataView:ByteOffset() return self.offset end
function DataView:SubView(offset)
    return setmetatable({
        offset = offset, blob = self.blob, length = self.length,
    }, DataView)
end

for label,datatype in pairs(DataView.Types) do
    DataView["Get" .. label] = function(self, offset, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            local v,_ = string.unpack(_ef(endian) .. datatype.code, self.blob, o)
            return v
        end
        return nil
    end

    DataView["Set" .. label] = function(self, offset, value, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            return SetFixed(self, o, value, _ef(endian) .. datatype.code)
        end
        return self
    end

    if datatype.size >= 0 and string.packsize(datatype.code) ~= datatype.size then
        local msg = "Pack size of %s (%d) does not match cached length: (%d)"
        error(msg:format(label, string.packsize(fmt[#fmt]), datatype.size))
        return nil
    end
end

for label,datatype in pairs(DataView.FixedTypes) do
    DataView["GetFixed" .. label] = function(self, offset, typelen, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            local v,_ = string.unpack(code, self.blob, o)
            return v
        end
        return nil
    end

    DataView["SetFixed" .. label] = function(self, offset, typelen, value, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            return SetFixed(self, o, value, code)
        end
        return self
    end
end

SetFixed = function(self, offset, value, code)
    local fmt = { }
    local values = { }

    if self.offset < offset then
        local size = offset - self.offset
        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(self.offset, size)
    end

    fmt[#fmt + 1] = code
    values[#values + 1] = value

    local ps = string.packsize(fmt[#fmt])
    if (offset + ps) <= self.length then
        local newoff = offset + ps
        local size = self.length - newoff + 1

        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(newoff, self.length)
    end

    self.blob = string.pack(table.concat(fmt, ""), table.unpack(values))
    self.length = self.blob:len()
    return self
end
