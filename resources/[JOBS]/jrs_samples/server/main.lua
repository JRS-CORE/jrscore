-- jrs_samples | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_samples | server
-- Sedated animals can be sampled once per character. The client only reports the network id; the server
-- finds the animal itself, checks it is a real ped of a known model right next to the player, and records
-- the sample with a UNIQUE key so it can never pay twice.

local MAX_DISTANCE <const> = 5.0        -- metres between player and animal
local MENU_GAP <const>     = 2000       -- ms between menu requests per player
local STATS_TTL <const>    = 30000      -- ms the leaderboard is cached

local featured = Config.FeaturedAnimal or ''

-- category -> list of { model hash, name, reward [, legendary] }; only these animals can be sampled
local catalogue = {
    ['Predator'] = {
        { -1124266369, 'bear', 500 }, { 730092646, 'american_black_bear', 400 },
        { -1143398950, 'big_grey_wolf', 650 }, { -885451903, 'medium_grey_wolf', 400 },
        { -829273561, 'small_grey_wolf', 250 }, { -1392359921, 'legendary_onyx_wolf', 1500, true },
        { 1654513481, 'panther', 400 }, { -1189368951, 'legendary_ghost_panther', 500, true },
        { 90264823, 'cougar', 350 }, { -1433814131, 'legendary_maza_cougar', 500, true },
        { 480688259, 'coyote', 200 }, { -1307757043, 'legendary_midnight_paw_coyote', 500, true },
    },
    ['Bird'] = {
        { -1003616053, 'duck', 100 }, { 1459778951, 'eagle', 150 }, { 831859211, 'egret', 120 },
        { 1104697660, 'vulture', 100 }, { -2011226991, 'wild_turkey', 100 },
        { -166054593, 'wild_turkey_variant', 100 }, { -466687768, 'red_footed_booby', 100 },
        { -164963696, 'herring_seagull', 80 }, { -1076508705, 'roseate_spoonbill', 120 },
        { 2023522846, 'dominique_rooster', 100 }, { -2063183075, 'dominique_chicken', 100 },
        { -575340245, 'western_raven', 90 }, { 2079703102, 'greater_prairie_chicken', 100 },
        { 1416324601, 'ring_necked_pheasant', 100 }, { 1265966684, 'american_white_pelican', 120 },
        { -1797450568, 'blue_yellow_macaw', 150 }, { 1205982615, 'californian_condor', 150 },
        { -2073130256, 'double_crested_cormorant', 120 }, { 723190474, 'canada_goose', 100 },
        { -2145890973, 'ferruginous_hawk', 150 }, { 1095117488, 'great_blue_heron', 120 },
        { 386506078, 'common_loon', 120 }, { -861544272, 'great_horned_owl', 150 },
        { -564099192, 'whooping_crane', 120 },
    },
    ['Reptile'] = {
        { -407730502, 'snapping_turtle', 120 }, { -229688157, 'water_snake', 80 },
        { 1464167925, 'snake_fer_de_lance', 150 }, { 846659001, 'black_tailed_rattlesnake', 120 },
        { 545068538, 'western_rattlesnake', 120 }, { 457416415, 'gila_monster', 150 },
        { -1854059305, 'green_iguana', 150 }, { -593056309, 'desert_iguana', 150 },
        { -2004866590, 'large_alligator', 400 }, { -1295720802, 'alligator', 350 },
        { -1892280447, 'alligator_swamp', 350 }, { -934450070, 'alligator_giant', 350 },
        { 825523615, 'alligator_pelt', 300 },
    },
    ['Ungulate'] = {
        { -1568716381, 'bighorn', 300 }, { -1963605336, 'buck', 250 }, { 1556473961, 'bison', 1200 },
        { 195700131, 'bull', 150 }, { 1110710183, 'deer', 200 }, { -2021043433, 'elk', 300 },
        { 1755643085, 'pronghorn_doe', 200 }, { -1098441944, 'moose', 400 }, { 556355544, 'angus_ox', 300 },
        { -50684386, 'florida_cracker_cow', 300 }, { 40345436, 'merino_sheep', 200 },
        { -753902995, 'alpine_goat', 200 }, { 1007418994, 'berkshire_pig', 200 }, { 1751700893, 'peccary_pig', 200 },
    },
    ['Small Game'] = {
        { 252669332, 'american_red_fox', 180 }, { 1458540991, 'north_american_raccoon', 100 },
        { -541762431, 'black_tailed_jackrabbit', 80 }, { -1414989025, 'virginia_opossum', 90 },
        { -1134449699, 'american_muskrat', 100 }, { 759906147, 'north_american_beaver', 150 },
        { -1149999295, 'legendary_moon_beaver', 500, true }, { -1211566332, 'striped_skunk', 90 },
        { 2028722809, 'boar', 200 },
    },
}

local animals, known = {}, {}            -- model hash -> animal, name -> true
for category, list in pairs(catalogue) do
    for _, a in ipairs(list) do
        animals[a[1]] = { name = a[2], reward = a[3], category = category, legendary = a[4] == true }
        known[a[2]] = true
    end
end

local function debug(...) if Config.DebugServer then print('[jrs_samples]', ...) end end
local function tell(src, text, ms) JRS.Notify(src, text, ms or 5000) end

-- ------------------------------------------------------------------ leaderboard

local shared = { expires = 0 }

local function loadShared()
    if GetGameTimer() < shared.expires then return shared end

    local top = MySQL.query.await([[
        SELECT t.citizenid, t.cnt AS sample_count, CONCAT(p.firstname, ' ', p.lastname) AS name
        FROM (SELECT citizenid, COUNT(*) AS cnt FROM jrs_samples GROUP BY citizenid ORDER BY cnt DESC LIMIT 10) t
        LEFT JOIN jrs_characters p ON p.charidentifier = t.citizenid
        ORDER BY t.cnt DESC]]) or {}
    local ranked = {}
    for i, row in ipairs(top) do
        ranked[i] = { rank = i, citizenid = row.citizenid, name = row.name or row.citizenid, sample_count = row.sample_count }
    end

    local rarest = MySQL.single.await('SELECT sample_id, COUNT(*) AS collectors FROM jrs_samples GROUP BY sample_id ORDER BY collectors ASC LIMIT 1')
    local weekly = MySQL.single.await([[
        SELECT t.cnt, CONCAT(p.firstname, ' ', p.lastname) AS name
        FROM (SELECT citizenid, COUNT(*) AS cnt FROM jrs_samples WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
              GROUP BY citizenid ORDER BY cnt DESC LIMIT 1) t
        LEFT JOIN jrs_characters p ON p.charidentifier = t.citizenid]])

    shared = {
        expires = GetGameTimer() + STATS_TTL,
        topCollectors = ranked,
        globalStats = {
            totalCollected = MySQL.scalar.await('SELECT COUNT(*) FROM jrs_samples') or 0,
            rarestAnimal = rarest and rarest.sample_id or nil,
            rarestCount = rarest and rarest.collectors or 0,
            weeklyTopName = weekly and weekly.name or nil,
            weeklyTopCount = weekly and weekly.cnt or 0,
        },
    }
    return shared
end

-- ------------------------------------------------------------------ sampling

local working, lastAt = {}, {}           -- char id -> in progress / game timer of the last sample
local inMemory = {}                      -- char id -> { name = true }, used when Config.StoreSampleData is off

-- server natives may give unsigned hashes; the catalogue uses signed 32-bit ones
local function signed(hash)
    hash = tonumber(hash) or 0
    if hash > 0x7FFFFFFF then hash = hash - 0x100000000 end
    return math.tointeger(hash) or hash
end

-- liveness is checked by the client (the prompt only exists for living sedated peds), the server checks
-- that the entity exists, is a non-player ped of a known model and is close
local function animalFor(src, netId)
    netId = tonumber(netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return debug('entity not found', netId) end
    if GetEntityType(entity) ~= 1 or IsPedAPlayer(entity) then return debug('not an animal', netId) end

    local away = #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(entity))
    if away > MAX_DISTANCE then return debug('too far', away) end
    return animals[signed(GetEntityModel(entity))]
end

-- true when this was the character's first sample of that animal
local function record(char, name)
    if Config.StoreSampleData then
        local rows = MySQL.update.await('INSERT IGNORE INTO jrs_samples (citizenid, sample_id) VALUES (?, ?)', { char, name })
        return rows and rows > 0
    end
    inMemory[char] = inMemory[char] or {}
    if inMemory[char][name] then return false end
    inMemory[char][name] = true
    return true
end

local function pay(src, player, animal)
    local char, name = tostring(player.charIdentifier), animal.name
    if not record(char, name) then return tell(src, L('already_collected')) end
    shared.expires = 0

    local special = featured ~= '' and name == featured
    local reward = special and math.floor(animal.reward * Config.FeaturedMultiplier) or animal.reward
    JRS.GiveMoney(src, reward)
    if special then tell(src, L('sample_featured', name, reward, Config.FeaturedMultiplier), 6000)
    else tell(src, L('sample_collected', name, reward)) end

    if not Config.StoreSampleData then return end

    -- our row is already stored, so a count of 1 means we were the first on the server
    if Config.FirstDiscoveryBonus > 0 and MySQL.scalar.await('SELECT COUNT(*) FROM jrs_samples WHERE sample_id = ?', { name }) == 1 then
        JRS.GiveMoney(src, Config.FirstDiscoveryBonus)
        tell(src, L('first_discovery', name, Config.FirstDiscoveryBonus), 7000)
    end

    local total = MySQL.scalar.await('SELECT COUNT(*) FROM jrs_samples WHERE citizenid = ?', { char })
    local step = Config.MilestoneRewards[total]
    if step then
        JRS.GiveMoney(src, step.bonus)
        tell(src, L('milestone_reached', step.label, step.bonus), 7000)
    end
    debug('Sampled', name, 'by', char, 'reward $' .. reward)
end

RegisterNetEvent('jrs_samples:server:sampleAnimal', function(netId)
    local src = source
    local player = JRS.Char(src)
    if not player then return end

    local char = tostring(player.charIdentifier)
    local now = GetGameTimer()
    if working[char] or (lastAt[char] and now - lastAt[char] < Config.SampleCooldown) then return end

    local animal = animalFor(src, netId)
    if not animal then return tell(src, L('sample_invalid')) end

    working[char], lastAt[char] = true, now
    local ok, err = pcall(pay, src, player, animal)
    working[char] = nil
    if not ok then print('[jrs_samples] ^1sample error:^7', err) end
end)

-- ------------------------------------------------------------------ journal

local askedAt = {}

local function sendJournal(src)
    local player = JRS.Char(src)
    if not player then return end
    local now = GetGameTimer()
    if askedAt[src] and now - askedAt[src] < MENU_GAP then return end
    askedAt[src] = now

    local char, mine = tostring(player.charIdentifier), {}
    if Config.StoreSampleData then
        for _, row in ipairs(MySQL.query.await('SELECT sample_id, created_at FROM jrs_samples WHERE citizenid = ?', { char }) or {}) do
            mine[row.sample_id] = { created_at = row.created_at }
        end
    else
        for name in pairs(inMemory[char] or {}) do mine[name] = {} end
    end

    local all = {}
    for _, a in pairs(animals) do all[#all + 1] = a end
    local stats = loadShared()
    TriggerClientEvent('jrs_samples:client:openSamplesMenu', src, {
        viewMode = 'menu',
        allSamples = all,
        collectedSamples = mine,
        topCollectors = stats.topCollectors,
        globalStats = stats.globalStats,
        currentCitizenId = char,
        playerName = JRS.Name(src),
        featuredAnimal = featured,
        featuredMultiplier = Config.FeaturedMultiplier,
    })
end

RegisterCommand('samplesmenu', function(src) if src > 0 then sendJournal(src) end end, false)

RegisterNetEvent('jrs_samples:server:requestMenu', function()
    local src = source
    local spot = Config.LeaderboardLocation
    if #(GetEntityCoords(GetPlayerPed(src)) - spot.coords) <= spot.radius + 5.0 then sendJournal(src) end
end)

-- /setfeatured [animal]  (admins; no name clears it)
RegisterCommand('setfeatured', function(src, args)
    if src > 0 and not JRS.IsAdmin(src) then return tell(src, L('no_permission')) end

    local name = (args[1] or ''):lower()
    if name ~= '' and not known[name] then
        if src > 0 then tell(src, L('featured_invalid', name)) end
        return
    end
    featured = name
    if src > 0 then tell(src, name ~= '' and L('featured_set', name) or L('featured_cleared')) end
    debug('Featured animal set to', featured, 'by', src)
end, false)

AddEventHandler('playerDropped', function() askedAt[source] = nil end)
