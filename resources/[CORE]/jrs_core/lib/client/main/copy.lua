exports('copyToClipBoard', function(text)
    if not text or type(text) ~= "string" then
        return
    end
    JRSExtLibNUI({
        data = {
            type = 'copy',
            text = text
        }
    })
end)
