-- ============================================================
-- jrs_core API - Usage Examples for External Scripts
-- ============================================================

-- SERVER-SIDE EXAMPLES
-- These can be used in any server script after jrs_core starts.

-- Method 1: Using exports
local JRS = exports.jrs_core:getCoreApi()

-- Get player data
local function getPlayerInfo(source)
    return JRS.getCharacter(source)
end

-- Notify a player
JRS.NotifyRightTip(source, "Welcome!", 5000)
JRS.NotifyLeft(source, "Title", "Description", "dict", "icon", 5000, "COLOR_WHITE")

-- Money management
JRS.addMoney(source, 0, 100)  -- Currency type 0 = money
JRS.removeMoney(source, 0, 50)

-- Job management
JRS.setJob(source, "police", 0)

-- Group management
JRS.setGroup(source, "admin")


-- Method 2: Using callbacks (recommended for external scripts)
-- Usage: TriggerEvent("jrs_core:ExecuteServerCallBack", "callbackName", function(result) ... end, data)

-- Notifications via callback
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:notifyRightTip", function(result) end, {
    text = "Hello from external script!",
    duration = 5000
})

-- Get player data
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:getPlayerData", function(data)
    print("Player: " .. data.firstname .. " " .. data.lastname)
    print("Job: " .. data.job .. " Grade: " .. data.jobGrade)
    print("Money: $" .. data.money .. " Gold: " .. data.gold)
end, {})

-- Add money
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:addMoney", function(result)
    if result.success then print("Money added!") end
end, { amount = 100 })

-- Give item to player
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:addItem", function(result)
    if result.success then print("Item given!") end
end, { item = "bread", count = 5, metadata = {} })

-- Check if player has item
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:hasItem", function(result)
    if result.has then print("Player has " .. result.total .. " of that item") end
end, { item = "bread", count = 1 })

-- Give weapon
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:giveWeapon", function(result)
    if result.success then print("Weapon given!") end
end, { weapon = "WEAPON_REVOLVER_CATTLEMAN", ammo = 100 })

-- Set player job
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:setPlayerJob", function(result)
    if result.success then print("Job set!") end
end, { job = "police", grade = 3 })

-- Get online players
TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:getOnlinePlayers", function(players)
    for _, p in ipairs(players) do
        print("Player: " .. p.name .. " (ID: " .. p.source .. ")")
    end
end, {})


-- CLIENT-SIDE EXAMPLES

-- Get the client API
local ClientAPI = exports.jrs_core:getCoreApi()

-- Make a server callback from client
ClientAPI.RpcCall("jrs:getPlayerData", function(data)
    print("My money: " .. data.money)
end, {})

-- Use client notifications directly
local Notify = exports.jrs_core:getCoreApi()
Notify.NotifyRightTip(_U('core_hello_from_client'), 5000)

-- Teleport player (from client)
Notify.teleportToCoords(0, 0, 0, 0)


-- Dirty Money / Illegal Money (server-side)
-- local JRS = exports.jrs_core:getCoreApi()
-- JRS.AddDirtyMoney(source, 100)
-- JRS.RemoveDirtyMoney(source, 25)
-- local dirtyBalance = JRS.GetDirtyMoney(source)
-- Generic currency type: 3
