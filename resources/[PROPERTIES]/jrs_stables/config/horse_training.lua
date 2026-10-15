-- JRS horse abilities: scores are out of 10, horse level is 1 to 4.
-- Values are applied to the horse in-game, not just displayed in the menu.
Config.HorseTraining = {
    enabled = true,
    revivePrice = 10, -- Dollars, charged by the server at a stable.
    shopDistance = 8,
    defaults = { health = { start = 5, max = 7 }, stamina = { start = 5, max = 7 } },
    -- One completed course awards 10 XP; ten courses fully train that ability.
    xpToMax = 100,
    xpPerSession = 10,
    healthSeconds = 20, -- Stand beside your horse and care for it.
    staminaSeconds = 30, -- Ride/lead your horse for at least the distance below.
    staminaDistance = 100,
    sessionTimeout = 120,
    sessionCooldown = 10,
    maxTrainingSpeed = 15, -- Metres per second; reject jumps/teleports.
    cancelKey = 0x4AF4D473, -- Delete cancels the current course.
    -- Each breed can have its own starting scores and training ceiling.
    breeds = {
        ['American Paint'] = { health={start=5,max=7}, stamina={start=5,max=7} },
        ['American Standardbred'] = { health={start=5,max=7}, stamina={start=5,max=8} },
        ['Andalusian'] = { health={start=5,max=8}, stamina={start=5,max=7} },
        ['Appaloosa'] = { health={start=5,max=7}, stamina={start=5,max=7} },
        ['Arabian'] = { health={start=5,max=8}, stamina={start=5,max=9} },
        ['Ardennes'] = { health={start=5,max=9}, stamina={start=5,max=7} },
        ['Belgian Draft'] = { health={start=5,max=8}, stamina={start=5,max=7} },
        ['Breton'] = { health={start=5,max=9}, stamina={start=5,max=8} },
        ['Criollo'] = { health={start=5,max=7}, stamina={start=5,max=8} },
        ['Dutch Warmblood'] = { health={start=5,max=8}, stamina={start=5,max=8} },
        ['Gypsy Cob'] = { health={start=5,max=8}, stamina={start=5,max=8} },
        ['Hungarian Halfbred'] = { health={start=5,max=8}, stamina={start=5,max=7} },
        ['Kentucky Saddler'] = { health={start=5,max=7}, stamina={start=5,max=7} },
        ['Kladruber'] = { health={start=5,max=9}, stamina={start=5,max=8} },
        ['Missouri Fox Trotter'] = { health={start=5,max=8}, stamina={start=5,max=9} },
        ['Morgan'] = { health={start=5,max=7}, stamina={start=5,max=7} },
        ['Mustang'] = { health={start=5,max=8}, stamina={start=5,max=8} },
        ['Nokota'] = { health={start=5,max=7}, stamina={start=5,max=8} },
        ['Norfolk Roadster'] = { health={start=5,max=8}, stamina={start=5,max=9} },
        ['Shire'] = { health={start=5,max=9}, stamina={start=5,max=7} },
        ['Suffolk Punch'] = { health={start=5,max=8}, stamina={start=5,max=7} },
        ['Tennessee Walker'] = { health={start=5,max=7}, stamina={start=5,max=7} },
        ['Thoroughbred'] = { health={start=5,max=7}, stamina={start=5,max=9} },
        ['Turkoman'] = { health={start=5,max=9}, stamina={start=5,max=8} },
        ['Special'] = { health={start=5,max=7}, stamina={start=5,max=7} },
        ['Other'] = { health={start=5,max=7}, stamina={start=5,max=7} },
    },
    -- A model override takes priority over its breed. Add any catalogue model here.
    models = {
        -- ['a_c_horse_arabian_white'] = { health={start=5,max=7}, stamina={start=5,max=8} },
    },
}
