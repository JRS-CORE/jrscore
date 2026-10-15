Config = {}

Config.defaultlang = 'ar' -- ar | en
Config.Debug = false
-- RedM server SyncTrees_RDR3 currently exposes no ped/vehicle health node.
-- Enable only on an artifact with verified server-side health support.
Config.ServerHealthChecks = false


------------------------------------------------------------------
------------------------- JRS Integration ------------------------
------------------------------------------------------------------
Config.Integration = {
    coreResource = 'jrs_core',
    inventoryResource = 'jrs_inventory',
}



------------------------------------------------------------------
----------------------------- Test Mode --------------------------
------------------------------------------------------------------
-- Development helper. Keep disabled on a live/production server.
-- When enabled, /chicken_test <stage> [hub] can jump directly to a
-- mission stage without server rewards, XP, cooldowns, or items.
Config.TestMode = {
    enabled = false,
    defaultHub = 'valentine',
    teleportPlayer = true,

    -- Test wagon direction. These headings are used for test stages that
    -- spawn the wagon at butcher/processing locations instead of the normal
    -- job-hub wagon spawn.
    wagonHeadings = {
        valentine = 92.94,
        tumbleweed = 102.76,
    },

    command = 'chicken_test',
    stopCommand = 'chicken_test_stop',

    -- Test mode NEVER grants money/items/XP even if this resource is
    -- accidentally left enabled. It only simulates progression client-side.
    noRewards = true,
}

Config.Prompts = {
    start = 'Start Chicken Job',
    catchChicken = 'Catch Chicken',
    loadChicken = 'Load Chicken',
    unloadChicken = 'Unload Chicken',
    killChicken = 'Slaughter Chicken',
    pickupDeadChicken = 'Pick Up Chicken',
    placeDeadChicken = 'Place on Table',
    cutChicken = 'Cut Chicken',
    pickupChest = 'Pick Up Products',
    loadChest = 'Load Products',
    unloadChest = 'Unload Products',
    deliverChest = 'Deliver Products',
    interact = 'Interact',
}

Config.Texts = {
    ['ar'] = {
        start = 'بدء مهمة الدجاج',
        noJob = 'يجب أن تعمل بوظيفة عامل دواجن (chicken) للبدء. اختر الوظيفة من لوحة الوظائف.',
        levelRequired = 'مستواك غير كافٍ. يتطلب هذا العمل المستوى %s فما فوق (مستواك الحالي: %s).',
        cooldown = 'يجب عليك الانتظار قبل بدء مهمة أخرى.',
        cooldownTime = 'يجب عليك الانتظار %d دقيقة قبل بدء مهمة جديدة.',
        goWagon = 'توجه إلى عربة الدجاج، ستظهر الوجهة التالية فور الوصول إليها.',
        goCatch = 'قد العربة إلى منطقة صيد الدجاج المحددة على الخريطة.',
        catchStarted = 'أمسك بـ %d دجاجات. ترجل من العربة واقترب من الدجاج المحدد.',
        chickenSpawnFailed = 'تعذر استدعاء الدجاج، ابقَ قريباً من المنطقة وستتم إعادة المحاولة تلقائياً.',
        catchChicken = 'الإمساك بالدجاجة',
        loadChicken = 'تحميل الدجاجة في قفص العربة',
        goButcher = 'قد العربة إلى موقع الذبح والتقطيع المحدد على الخريطة.',
        unloadChicken = 'إنزال دجاجة من قفص العربة',
        killReady = 'احمل الدجاجة واذبحها أولاً قبل نقلها إلى طاولة التقطيع.',
        killChicken = 'ذبح الدجاجة',
        pickupDeadReady = 'تم ذبح الدجاجة بنجاح! التقطها واحملها إلى طاولة التقطيع.',
        pickupDeadChicken = 'حمل الدجاجة المذبوحة',
        carryToCut = 'احمل الدجاجة المذبوحة إلى طاولة التقطيع.',
        placeDeadChicken = 'وضع الدجاجة على طاولة التقطيع',
        cutChicken = 'تقطيع الدجاجة',
        cuttingChicken = 'جاري تقطيع وتجهيز لحم الدجاج...',
        nextChicken = 'عد إلى العربة وأنزل الدجاجة التالية.',
        pickupChest = 'حمل حوض المنتجات',
        loadChest = 'تحميل المنتجات في العربة',
        goDelivery = 'انقل المنتجات بالعربة إلى نقطة التسليم المحددة.',
        unloadChest = 'تنزيل حوض المنتجات من العربة',
        carryDelivery = 'احمل المنتجات إلى نقطة التسليم.',
        deliverChest = 'تسليم المنتجات',
        complete = 'اكتملت مهمة الدجاج بنجاح! استلمت مكافأتك بقيمة',
        missionFailed = 'فشلت مهمة الدجاج.',
        inventoryError = 'حقيبتك ممتلئة! تعذر إضافة بعض المنتجات إلى حقيبتك.',
        activeMission = 'لديك مهمة دجاج نشطة بالفعل.',
        wagonDestroyed = 'تم تدمير العربة! فشلت مهمة الدجاج.',
        horseDead = 'مات حصان العربة! فشلت مهمة الدجاج.',
        jobChanged = 'تم إلغاء مهمة الدجاج بسبب تغيير وظيفتك.',
        cageModelError = 'تعذر تحميل نموذج قفص الدجاج.',
        cageSpawnError = 'تعذر إنشاء قفص الدجاج.',
        wagonModelError = 'تعذر تحميل نموذج العربة.',
        noActiveMission = 'لا توجد مهمة دجاج نشطة حالياً.',
        testModeStopped = 'تم إيقاف اختبار عمل الدجاج.',
        missionCancelled = 'تم إلغاء مهمة الدجاج.',
        jobStatus = 'حالة عمل الدجاج: %s%s',
    },
    ['en'] = {
        start = 'Press [G] to start Chicken Job',
        noJob = 'You must have the Poultry Butcher (chicken) job to start. Select it from the job board.',
        levelRequired = 'Your level is too low. Level %s or higher is required (your level: %s).',
        cooldown = 'You must wait before starting another mission.',
        cooldownTime = 'You must wait %d minutes before starting another mission.',
        goWagon = 'Go to the chicken wagon. The next location will appear when you reach it.',
        goCatch = 'Drive to the marked chicken area.',
        catchStarted = 'Catch %d chickens. Get off the wagon and approach a marked chicken.',
        chickenSpawnFailed = 'Could not spawn the chickens. Stay near the marked area; the job will retry.',
        catchChicken = 'Catch chicken',
        loadChicken = 'Load chicken on wagon',
        goButcher = 'Take the wagon to the butcher.',
        unloadChicken = 'Take a chicken from the wagon',
        killReady = 'Carry the chicken to the marked butcher and slaughter it.',
        killChicken = 'Slaughter chicken',
        pickupDeadReady = 'The chicken is dead. Pick it up and take it to the cutting table.',
        pickupDeadChicken = 'Pick up dead chicken',
        carryToCut = 'Carry the dead chicken to the cutting table.',
        placeDeadChicken = 'Place dead chicken on the table',
        cutChicken = 'Cut chicken',
        cuttingChicken = 'Cutting and preparing chicken meat...',
        nextChicken = 'Unload the next chicken from the wagon.',
        pickupChest = 'Pick up the product basin',
        loadChest = 'Load products on wagon',
        goDelivery = 'Deliver the products.',
        unloadChest = 'Unload the products from wagon',
        carryDelivery = 'Carry the products to the delivery point.',
        deliverChest = 'Deliver the products',
        complete = 'Chicken job completed. You received',
        missionFailed = 'Mission failed.',
        inventoryError = 'Could not add one or more products (inventory full).',
        activeMission = 'You already have an active chicken mission.',
        wagonDestroyed = 'Wagon was destroyed! Mission failed.',
        horseDead = 'Draft horse died! Mission failed.',
        jobChanged = 'Mission cancelled because your job changed.',
        cageModelError = 'Could not load chicken cage model.',
        cageSpawnError = 'Could not spawn chicken cage.',
        wagonModelError = 'Could not load wagon model.',
        noActiveMission = 'No active chicken mission.',
        testModeStopped = 'Chicken Test Mode stopped.',
        missionCancelled = 'Chicken mission cancelled.',
        jobStatus = 'Chicken Job stage: %s%s',
    }
}

Config.Text = Config.Texts[Config.defaultlang] or Config.Texts['ar']


------------------------------------------------------------------
----------------------- Animation / Carry ------------------------
------------------------------------------------------------------
-- These are native RDR2/RedM animations. If a specific clip is not
-- available on a build, the action still continues using the fallback.
Config.Animations = {
    enabled = true,

    pickup = {
        dict = 'amb_player@world_player_chore@bale_pick_up@male_a@stand_exit_withprop',
        clip = 'exit_front',
        duration = 950,
        attachAtMs = 650,
        flag = 0,
    },

    carry = {
        dict = 'amb_wander@code_human_hay_bale_wander@male_a@base',
        clip = 'base',
        duration = -1,
        flag = 25,
    },

    -- Two-hand front carry for chickens. This is shared by every chicken
    -- pickup path so the player always holds the chicken between both hands.
    chickenCarry = {
        dict = 'amb_wander@code_human_box_wander@male_a@base',
        clip = 'base',
        duration = -1,
        flag = 25,
        blendIn = 2.0,
        blendOut = 2.0,
    },

    putDown = {
        dict = 'amb_work@world_human_lumber@put_down@1@loaded_lumber@male_a@base',
        clip = 'base',
        duration = 1000,
        detachAtMs = 520,
        flag = 0,
    },

    -- RDR2 chicken-specific stow clip. Used when loading onto the wagon.
    chickenStow = {
        dict = 'mech_skin@chicken@horse_satchel@stow@rt',
        clip = 'enter_rf',
        duration = 1400,
        detachAtMs = 850,
        flag = 0,
    },

    -- v3.4.0: RDR2's own pick-up-a-chicken clip (used for every chicken
    -- pickup: field, wagon cage, ground after slaughter). The basin keeps
    -- `pickup` above.
    chickenPickup = {
        dict = 'mech_skin@chicken@pickup_handheld',
        clip = 'enter_rf',
        duration = 1300,
        attachAtMs = 700,
        flag = 0,
        blendIn = 4.0,
        blendOut = -4.0,
    },

    chickenUnstow = {
        dict = 'mech_skin@chicken@pickup_handheld',
        clip = 'enter_rf',
        duration = 1300,
        attachAtMs = 700,
        flag = 0,
    },

    -- The player visibly bends down and releases the live chicken before
    -- drawing the knife. This dictionary is the RDR2 handheld-chicken drop.
    killPlace = {
        dict = 'mech_skin@chicken@drop_handheld',
        clip = 'drop_handheld',
        entityClip = 'drop_handheld_chicken',
        duration = 1900,
        detachAtMs = 850,
        flag = 0,
        blendIn = 2.0,
        blendOut = 2.0,
    },

    -- v3.4.0: slaughter uses RDR2's own chicken field-dress (the knife
    -- kneel used when dressing a chicken in-game). The old dict
    -- 'melee@knife@streamed_core' does not exist in RDR3, so the hammer
    -- fallback always ran. enter -> success (chicken dies at strikePhase) -> exit.
    kill = {
        maleDict = 'mech_skin@chicken@field_dress',
        femaleDict = 'mp_mech_skin@female@chicken@field_dress',
        clips = { 'enter', 'success', 'exit' },
        strikeClip = 'success',
        strikePhase = 0.30,
        clipTimeoutMs = 4000,
        scenario = 'WORLD_HUMAN_BUTCHER_RABBIT',
        duration = 3000,
        strikeAtMs = 1350,
        blendIn = 4.0,
        blendOut = -4.0,
        freeze = true,
        knifeModel = 'w_melee_knife06',
        knifeBone = 'SKEL_R_Finger13',
        knifeOffset = {
            x = -0.01, y = -0.02, z = 0.02,
            rx = 190.0, ry = 0.0, rz = 0.0,
        },
        chickenForwardOffset = 0.45,
        chickenGroundOffset = 0.08,
        corpseSettleMs = 900,
    },

    -- Table cut. v3.4.0: first choice is Red Dead Online's own clip: Cripps
    -- working at the Trader butcher table (script_mp@trader@cripps /
    -- butcher_idle), the same mp005_s_posse_butcher01x table spawned below.
    -- It is a standing full-body clip, so it plays with rdoFlag (1 = loop).
    -- If it does not start, the rabbit-chop camp clips below are used.
    tableCut = {
        rdoDict = 'script_mp@trader@cripps',
        rdoClip = 'butcher_idle',
        rdoFlag = 1,
        useRdo = true,
        maleDict = 'amb_camp@prop_camp_butcher@working@rabbit@male_a@rabbit_chop@base',
        femaleDict = 'amb_camp@prop_camp_butcher@working@rabbit@female_a@rabbit_chop@base',
        dict = 'amb_camp@prop_camp_butcher@working@rabbit@male_a@rabbit_chop@base',
        clip = 'base',
        knifeModel = 'w_melee_knife06',
        knifeBone = 'SKEL_R_Finger13',
        knifeOffset = {
            x = -0.01, y = -0.02, z = 0.02,
            rx = 190.0, ry = 0.0, rz = 0.0,
        },
        duration = 7000,
        flag = 17, -- loop + upper body: legs stay standing at the table

        -- v3.3.0: what happens to the bird on the table during the cut.
        -- The chicken jolts on each chop, becomes a plucked carcass at
        -- pluckedAt, then halves + drumsticks at piecesAt (0..1 of the cut).
        visual = {
            enabled = true,
            chopEveryMs = 750,   -- match the chop rhythm of the clip
            firstChopMs = 450,
            joltHeight = 0.018,
            propZOffset = -0.08, -- props sit lower than the chicken ped root
            pluckedAt = 0.40,
            piecesAt = 0.70,
            plucked = { model = 'p_chicken01x', headingOffset = 0.0 },
            pieces = {
                { model = 'p_chickenhalf01x', x = -0.07, y = 0.02, z = 0.0, headingOffset = 0.0 },
                { model = 'p_chickenhalf02x', x =  0.07, y = 0.02, z = 0.0, headingOffset = 180.0 },
                { model = 'p_drumstick01x',   x = -0.02, y = 0.16, z = 0.0, headingOffset = 30.0 },
                { model = 'p_drumstick01x',   x =  0.03, y = -0.15, z = 0.0, headingOffset = -30.0 },
            },
        },
    },
}

-- Prefer RDR2's native carriable system for chickens. It lets the game
-- control the player's hands/body pose instead of a manual hand attachment.
-- Manual offsets below are kept because chicken native carry is disabled here.
Config.CarrySystem = {
    native = true,
    -- Native small-animal carry grips the chicken through the body on this build.
    -- Keep native available for other carriables, but use our tuned hand grip for chickens.
    nativeForLiveChicken = false,
    nativeForDeadChicken = true,
    requireNativeDeadCarry = true,
    timeoutMs = 2600,
    fallbackManualAttach = true,
    fallbackCarryConfig = 'GENERIC_DEAD_CARRIABLE_SMALL_ANIMAL',
    taskSlot = 0,
    taskFlags = 0,
}

Config.CarryOffsets = {
    -- Attach chickens to the player's root instead of a rotating spine bone.
    -- These offsets are stable player-space coordinates: centered, in front
    -- of the waist and directly between the hands of the carry animation.
    liveChicken = {
        boneIndex = 0,
        x = 0.00, y = 0.35, z = 0.10,
        -- Keep the chicken upright: feet down and head up.
        rx = 0.0, ry = 0.0, rz = 8.0,
        playCarryAnim = true,
    },
    deadChicken = {
        boneIndex = 0,
        x = 0.00, y = 0.35, z = 0.08,
        rx = 2.0, ry = 0.0, rz = 10.0,
        playCarryAnim = true,
    },
    -- After slaughter, carry the whole dead chicken over the player's back/shoulder.
    -- No looping box-carry animation is played; the player can walk normally.
    deadChickenBack = {
        bone = 'SKEL_Spine3',
        x = -0.16, y = -0.23, z = 0.04,
        rx = 88.0, ry = 8.0, rz = -78.0,
        playCarryAnim = false,
    },
    pluckedChicken = {
        boneIndex = 0,
        x = 0.00, y = 0.35, z = 0.08,
        rx = 2.0, ry = 0.0, rz = 10.0,
        playCarryAnim = true,
    },
    basin = {
        bone = 'skel_r_hand',
        x = 0.08, y = 0.32, z = -0.18,
        rx = 12.0, ry = -2.0, rz = 88.0,
    },
}

Config.Basin = {
    model = 'p_washbasin01x',
    groundHeading = 0.0,
    wagonAttach = {
        x = 0.0, y = -1.35, z = 1.05,
        rx = 0.0, ry = 0.0, rz = 0.0,
    },
}


------------------------------------------------------------------
----------------------- Discord Webhook --------------------------
------------------------------------------------------------------
Config.Webhook = {
    enabled = true,
    url = '',
    botName = 'rakan chicken',
    color = 16753920,
}

------------------------------------------------------------------
--------------------------- Job Check ----------------------------
------------------------------------------------------------------
Config.JobCheck = {
    enabled = true,
    job = 'chicken',
    minLevel = 0,
    showBlipOnlyIfJob = true, -- true = show blip on map ONLY for players who have the chicken job
}

------------------------------------------------------------------
------------------------ Feature Toggles -------------------------
------------------------------------------------------------------
Config.Features = {
    npc      = true,  -- job start NPC + blip
    wagon    = true,  -- wagon spawn + load chickens
    catch    = true,  -- catch zone + chickens
    kill     = true,  -- animated kill/chop phase
    cut      = true,  -- G butcher cut scenario + inventory items
    chest    = true,  -- basin: store products after cut
    delivery = true,  -- final delivery point
    gps      = true,  -- yellow route on minimap
    markers  = true,  -- world markers (hidden when you arrive)
    blips    = true,  -- objective blips
    sounds   = false,
}

------------------------------------------------------------------
------------------------ Multi-player sync -----------------------
-- Others SEE your chickens / wagon / table / anims
-- Only YOU can catch, kill, or process your mission entities
------------------------------------------------------------------
Config.Sync = {
    enabled = true,
    viewDistance = 120.0,
}

Config.Gps = {
    -- The mission uses a REAL map waypoint (SetNewWaypoint), exactly like
    -- selecting a destination manually from the RDR2 map.
    color = 'COLOR_YELLOW',
    hudColor = 6, -- used only by the emergency multi-route fallback

    -- Optional 3D world indicator from jrs_core. Keep false if you only want
    -- the normal map/minimap GPS route.
    useCoreDestination = false,

    enableBlipRouteFallback = false,
}

Config.ObjectiveBlips = {
    wagon    = 'blip_ambient_wagon',
    catch    = 'blip_ambient_herd',
    process  = 'blip_proc_cleaver',
    chest    = 'blip_ambient_loot',
    delivery = 'blip_ambient_delivery',
}

------------------------------------------------------------------
----------------------------- Keys -------------------------------
------------------------------------------------------------------
Config.Keys = {
    interact = 0x760A9C6F, -- G
}

------------------------------------------------------------------
------------------------ Mission Cooldown ------------------------
-- Saved in DB — survives disconnect / reconnect
------------------------------------------------------------------
Config.MissionCooldown = {
    enabled = false,
    minutes = 0,
}

------------------------------------------------------------------
------------------------- JRS Core (XP) -------------------------
-- Uses jrs_core:AddJobXP (Job = 'chicken').
-- Awards XP to the Poultry Butcher (chicken) job level in jrs_job_levels
-- and automatically feeds Config.JobXP.CoreShare into the player's global level.
-- Set Enabled = false to disable all XP.
------------------------------------------------------------------
Config.XP = {
    Enabled = true,
    Job = 'chicken',
    Multiplier = 1.0,
    Default = 0,
    Rewards = {
        cutChicken      = 10,   -- تقطيع الدجاجة على الطاولة
        loadChicken     = 5,    -- تحميل الدجاجة في قفص العربة
        killChicken     = 5,    -- ذبح الدجاجة
        catchComplete   = 15,   -- إكمال صيد وتحميل كل الدجاج
        chestOnWagon    = 15,   -- تحميل حوض المنتجات في العربة
        missionComplete = 40,   -- تسليم المنتجات وإنهاء المهمة
    },
}
-- Legacy alias kept for backwards compatibility
Config.RakanLevel = Config.XP

------------------------------------------------------------------
------------------------ Job Hubs (multi NPC) --------------------
-- Each hub: NPC, wagon spawn, catch zones, butcher, delivery
------------------------------------------------------------------
Config.JobHubs = {
    {
        id = 'valentine',
        label = 'Valentine',
        npc = {
            model = 'a_m_m_rhdforeman_01',
            coords = vector4(-291.39, 862.16, 120.72, 158.46),
            scenario = 'WORLD_HUMAN_STAND_WAITING',
            blip = {
                enabled = true,
                sprite = 'blip_supplies_food',
                name = 'Chicken Job — Valentine',
                scale = 0.45,
            },
        },
        wagonSpawn = vector4(-282.19, 853.51, 119.97, 182.73),
        catchZones = {
            vector4(-380.52, 899.73, 116.07, 314.12), 
            vector4(1365.2120, 281.9471, 88.3536, 7.3439),
            --add more catch zones here
        },
        -- Indexed to catchZones: only the second field has a fixed loading park.
        catchParking = {
            [2] = vector4(1363.6161, 303.2199, 87.4644, 277.4092),
        },
        catchParkingRadius = 5.0,
        butcherSiteId = 'valentine',
        cutSiteId = 'valentine_chicken', -- separate chicken cutting table
        deliveryPoints = {
            vector3(1413.8738, 317.1164, 88.4075),  
            vector3(488.1865, 590.4960, 109.2383),  
            --add more delivery points here
        },
    },

    {
        id = 'tumbleweed',
        label = 'Tumbleweed',
        npc = {
            model = 'a_m_m_rhdforeman_01',
            coords = vector4(-5524.58, -2931.74, -2.01, 219.01),
            scenario = 'WORLD_HUMAN_STAND_WAITING',
            blip = {
                enabled = true,
                sprite = 'blip_supplies_food',
                name = 'Chicken Job — Tumbleweed',
                scale = 0.45,
            },
        },
        wagonSpawn = vector4(-5540.97, -2936.96, -1.67, 102.76),
        catchZones = {
            vector4(-5603.77, -2963.24, 2.38, 62.73),
            vector4(-5599.73, -3035.75, 1.76, 102.65),
            --add more catch zones here
        },
        butcherSiteId = 'tumbleweed',
        cutSiteId = 'tumbleweed_chicken', -- separate chicken cutting table
        deliveryPoints = {
            vector3(-5545.9570, -2413.1426, -9.3129),
            vector3(-5869.9175, -3191.2815, -13.3660), 
            --add more delivery points here
        },
    },
}

function Config.GetJobHub(hubId)
    if not hubId or not Config.JobHubs then return nil end
    for _, hub in ipairs(Config.JobHubs) do
        if hub.id == hubId then return hub end
    end
    return nil
end

------------------------------------------------------------------
----------------------------- Wagon ------------------------------
------------------------------------------------------------------
Config.Wagon = {
    model = 'wagon02x',
    useDraftVehicle = true,
    draftHorseGroup = 'DRAFT_HORSES_MID',
    maxChickens = 5,
    pickupDistance = 10.0,  -- G prompt / auto-start near wagon
    loadDistance = 4.0,     -- distance to load chicken on wagon
    rearLoadDistance = 2.5,
    rearLoadOffset = vector3(0.0, -1.10, -0.15), -- relative to the rear cage
    unloadDistance = 4.0,   -- distance to take chicken from wagon
    chestLoadDistance = 4.0, -- distance to load/unload basin on wagon
    loadMarkerOffset = vector3(0.0, -1.85, 0.0), -- marker at rear of wagon bed
    searchRadius = 150.0,
    autoStartWhenInWagon = true, -- continue mission when player enters the wagon
   
    -- Physical chicken cage carried in the wagon bed.
    -- Chickens are attached to this object, not directly to the wagon.
    chickenTrap = {
        enabled = true,
        model = 'p_trap01x',
        -- Whole cage group adjustment. +Y moves toward the horses; +Z raises it.
        -- Rear position follows the user's live calibration; lower by 0.25m.
        groupOffset = { x = 0.0, y = -0.30, z = 0.75 },
        -- One centered row, rear to front. Measured cage footprint is
        -- 1.022m wide x 0.530m deep; 0.65m spacing leaves a 0.12m gap.
        cages = {
            { x = 0.00, y = -1.40, z = -0.60 },
            { x = 0.00, y = -0.75, z = -0.60 },
            { x = 0.00, y = -0.10, z = -0.60 },
        },

        -- Legacy single-cage fallback, only used when cages is absent.
        -- Use groupOffset above to move the active three-cage layout.
        attach = {
            -- wagon02x rear/tailgate is on the negative local Y side.
            -- Keep the cage just inside the rear door and sitting on the bed.
            x = 0.0,
            y = -1.48,
            z = 0.15,
            rx = 0.0,
            ry = 0.0,
            rz = 0.0,
        },

        -- Chicken feet are kept slightly above the trap floor so their bodies
        -- remain visibly inside p_trap01x instead of clipping below the cage.
        chickenSlots = {
            { x = -0.16, y = 0.0, z = 0.16, rz = 20.0 },
            { x =  0.16, y = 0.0, z = 0.16, rz = 160.0 },
        },
    },
    -- Fail mission if wagon destroyed or draft horse dies
    failMission = {
        enabled = true,
        checkIntervalMs = 1000,
        minBodyHealth = 1.0,
        harnessSlots = 4,
    },
}

------------------------------------------------------------------
------------------------ Catch Zones -----------------------------
-- Random zone picked each job run
------------------------------------------------------------------
Config.ChickensRequired = 5
Config.Chicken = {
    model = 'a_c_chicken_01',
    zoneTriggerRadius = 25.0, -- broad streaming/search area
    arrivalRadius = 16.0,      -- actual arrival distance before chickens spawn
    spawnRadius = 7.0,
    minSpacing = 2.0,
    catchDistance = 1.8,
    showMarkers = false,      -- circular marker under every live chicken (disabled, text only)
    showBlips = true,         -- chicken icons stay visible until that chicken is picked up
    blipSprite = 'blip_ambient_herd',
    blipScale = 0.55,
    marker = {
        type = 0x94FDAE17,
        rgba = { 255, 200, 50, 175 },
        size = { 0.68, 0.68, 0.12 },
    },
    drawText = {
        enabled = true,
        text = 'G  •  CATCH',
        distance = 18.0,
        zOffset = 0.62,
        scale = 0.27,
        rgba = { 255, 220, 90, 235 },
    },
    maxHeightDiff = 6.0,
    -- carryUsePed = true  -> live chicken ped in hands (not dead prop)
    carryUsePed = true,
    carryModel = 'a_c_chicken_01',
    carryProp = 'p_chicken01x', -- only used when carryUsePed = false (dead plucked prop)
   
}

------------------------------------------------------------------
-------- Butcher table cut --------
------------------------------------------------------------------
Config.ButcherScenario = {
    -- Chicken cutting uses the rabbit-butcher scenario on the spawned table.
    ScenarioTypes = { 'WORLD_HUMAN_BUTCHER_RABBIT', 'WORLD_HUMAN_BUTCHER_RABBIT_ALWAYS' },
    FallbackScenario = 'WORLD_HUMAN_BUTCHER_RABBIT',
    DistanceThreshold = 2.5,
    ScenarioWait = 8000,
    DirectCutDurationMs = 7200,
    DirectCutHoldMs = 8000,
}
------------------------------------------------------------------
---------------- Butcher / Wagon Unload Sites --------------------
------------------------------------------------------------------
Config.ButcherSites = {
    {
        id = 'valentine',
        label = 'Valentine',
        coords = vector3(-339.17, 767.37, 116.57),
        radius = 8.0,
        wagonStation = vector3(-360.52, 765.7, 116.28),
        chickenBucket = {
            coords = vector4(-338.9103, 766.4498, 116.5897, 117.3164),
            radius = 1.5,
            chickenHeight = 0.65,
        },
        wagonUnloadDistance = 2.0,
        chest = vector3(-349.12, 751.45, 115.53),
        chestRadius = 2.5,
    },
    {
        id = 'tumbleweed',
        label = 'Tumbleweed',
        coords = vector3(-5508.9634, -2946.3203, -2.8876),
        radius = 8.0,
        wagonStation = vector3(-5518.87, -2945.06, -1.91),
        wagonUnloadDistance = 2.0,
        chest = vector3(-5509.56, -2951.01, -1.85),
        chestRadius = 2.5,
    },
}


------------------------------------------------------------------
-- Chicken cutting stations.
-- Valentine uses a spawned butcher table with its own attached scenario point.
------------------------------------------------------------------
Config.CutStations = {
    {
        id = 'valentine_chicken', label = 'Valentine Butcher Table',
        table = {
            spawn = true,
            model = 'mp005_s_posse_butcher01x',
            coords = vector4(-351.0308, 753.2722, 115.53, 321.7869),
            placeOnGround = true,
            freeze = true,
            networked = true,
            deadChickenOffset = { x = -0.05, y = -0.52, z = 0.92, headingOffset = 90.0 },
            -- v3.2.0: the table is measured in-game. The chicken is laid this far
            -- in from the player's edge, this high above the measured table top.
            chickenEdgeInset = 0.26,
            chickenSurfaceLift = 0.10,
        },
        tablePlaceRadius = 3.0,
        scenario = {
            -- v3.2.0: player stands on the ground this far outside the table's
            -- long edge, facing it. `offset` below is only a fallback now.
            standClearance = 0.48,
            authored = false,
            createIfMissing = false,
            preferConfigured = true,
            useNativeScenarioPoint = false,
            type = 'WORLD_HUMAN_BUTCHER_RABBIT',
            attachToTable = false,
            heading = 321.7869,
            headingOffset = 0.0,
            radius = 1.25,
            searchRadius = 3.0,
            distance = 3.0,
            -- Player stands directly in front of the table edge on the ground, not on top of it.
            offset = { x = -0.15, y = -1.22, z = 0.0 }
        },
    },
    {
        id = 'tumbleweed_chicken', label = 'Tumbleweed Butcher Table',
        table = {
            spawn = false,
            coords = vector4(-5508.96337890625, -2946.3203125, -2.88762593269348, 0.0),
            deadChickenOffset = { x = -0.05, y = 0.52, z = 0.85, headingOffset = 90.0 },
        },
        tablePlaceRadius = 3.0,
        scenario = { authored=true, createIfMissing=true, searchRadius=3.0, distance=3.0, offset={x=-0.15, y=-1.22, z=0.0} },
    },
}

function Config.GetCutStation(cutSiteId)
    if not cutSiteId or not Config.CutStations then return nil end
    for _, site in ipairs(Config.CutStations) do
        if site.id == cutSiteId then return site end
    end
    return nil
end

------------------------------------------------------------------
------------------ Processing defaults (all sites) -----------------
------------------------------------------------------------------
Config.ProcessStation = {
    advanceOnItemFail = true,
    wagonUnloadDistance = 2.0,

    -- table, phases, chest, steps.kill -> client/coords.lua
    steps = {
        cut = {
            enabled = true,
            time = 7000,
            preScenarioWait = 300,
            products = {
                { item = 'chicken_thigh',     amount = { min = 1, max = 2 } },
                { item = 'chicken_wing',      amount = { min = 1, max = 2 } },
                { item = 'chicken_breast',    amount = { min = 1, max = 2 } },
                { item = 'chicken_drumstick', amount = { min = 1, max = 2 } },
                { item = 'Feather',           amount = { min = 2, max = 4 } },
            },
        },
    },
}

------------------------------------------------------------------
------------------------- Delivery -------------------------------
------------------------------------------------------------------
Config.Delivery = {
    payment = { min = 3.0, max = 5.0 },
    areaRadius = 35.0,  -- wagon near delivery point to unload basin
    dropRadius = 8.0,   -- player distance to place basin or deliver at drop point
    returnRadius = 5.0,
}

------------------------------------------------------------------
--------------------------- Markers ------------------------------
------------------------------------------------------------------
Config.Marker = {
    type = 0x94FDAE17,
    rgba = { 255, 200, 50, 120 },
    size = { 1.5, 1.5, 0.4 },
}
