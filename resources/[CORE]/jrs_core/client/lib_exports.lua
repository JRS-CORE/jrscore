-- ---------------------------------------------------------------------------
-- jrs_lib -> jrs_core : client export surface
-- ---------------------------------------------------------------------------
-- The standalone resource published its helpers as exports['jrs_lib']:jrs_lib().
-- jrs_core keeps the same shape under its own name, so a caller only swaps the
-- resource:
--
--     local lib = exports.jrs_core:jrs_lib()
--     local lib = exports.jrs_core:getLibApi()   -- same table, clearer name
--
-- Nothing in the tree calls this today (the old resource booted before
-- jrs_core and its server half errored out on load), but the surface is kept
-- so anything written against jrs_lib keeps working.
-- ---------------------------------------------------------------------------

local function buildLibApi()
    local self = {}

    self.getTarget = function()
        return JrsLib.getTarget()
    end
    self.getPromptButtonData = function(text, promptHash)
        return JrsLib.getPromptButtonData(text, promptHash)
    end
    self.getPrompt = function(promptHash, text)
        JrsLib.getPrompt(promptHash, text)
    end
    self.drawMe = function(x, y, z, text, dist, marker)
        JrsLib.drawMe(x, y, z, text, dist, marker)
    end
    self.createPrompt = function(text, key, promptHash, holdMode, event)
        JrsLib.createPrompt(text, key, promptHash, holdMode, event)
    end
    self.promptDelete = function(text, promptHash)
        JrsLib.promptDelete(text, promptHash)
    end
    self.showPrompt = function(name, prompt, show)
        JrsLib.showPrompt(name, prompt, show)
    end
    self.setPromptVisible = function(text, hash, state)
        JrsLib.setPromptVisible(text, hash, state)
    end
    self.setPromptEnable = function(text, hash, state)
        JrsLib.setPromptEnable(text, hash, state)
    end
    self.getPromptButton = function(text, promptHash)
        return JrsLib.getPromptButton(text, promptHash)
    end
    self.playerNearCoords = function(x, y, z, dist, mark)
        return JrsLib.playerNearCoords(x, y, z, dist, mark)
    end
    self.checkPlayersNearEntity = function(entity, distance)
        return JrsLib.checkPlayersNearEntity(entity, distance)
    end
    self.createPed = function(model, x, y, z, h, dist, scenario)
        JrsLib.createPed(model, x, y, z, h, dist, scenario)
    end
    self.getLastPed = function()
        return JrsLib.getLastPed()
    end
    self.createBlip = function(text, x, y, z, sprite)
        JrsLib.createBlip(text, x, y, z, sprite)
    end
    self.notify = function(title, text, time, img)
        JrsLib.notify(title, text, time, img)
    end
    self.getInput = function(title, subtext, cb)
        JrsLib.getInput(title, subtext, cb)
    end
    self.getAnswer = function(title, first, second, cb)
        JrsLib.getAnswer(title, first, second, cb)
    end
    self.createVehicle = function(model, x, y, z, h)
        JrsLib.createVehicle(model, x, y, z, h)
    end
    self.getLastVehicle = function()
        return JrsLib.getLastVehicle()
    end
    self.getAllPeds = function()
        return JrsLib.getAllPeds()
    end
    self.getAllEntities = function()
        return JrsLib.getAllEntities()
    end
    self.getAllVehicles = function()
        return JrsLib.getAllVehicles()
    end
    self.getPlayers = function()
        return JrsLib.getPlayers()
    end
    self.playAnim = function(entity, dict, anim, flag, time)
        JrsLib.playAnim(entity, dict, anim, flag, time)
    end
    self.deleteObj = function(obj)
        JrsLib.deleteObj(obj)
    end
    self.deletePed = function(obj)
        JrsLib.deletePed(obj)
    end
    self.groundCheck = function(x, y)
        return JrsLib.groundCheck(x, y)
    end
    self.getTime = function()
        return JrsLib.getTime()
    end
    self.IsPlayerInsidePolygon = function(playerPos, polyPoints, debug, issmall)
        return JrsLib.IsPlayerInsidePolygon(playerPos, polyPoints, debug, issmall)
    end
    self.calculatePolygonLength = function(polyPoints)
        return JrsLib.calculatePolygonLength(polyPoints)
    end

    return self
end

exports('jrs_lib', buildLibApi)
exports('getLibApi', buildLibApi)
