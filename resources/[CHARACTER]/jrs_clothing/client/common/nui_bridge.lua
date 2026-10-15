function SendClothingNUIMessage(payload)
    if type(payload) == 'table' and payload.language == nil then
        pcall(function() payload.language = exports.jrs_core:GetLanguage() end)
    end
    SendNUIMessage(payload)
end
