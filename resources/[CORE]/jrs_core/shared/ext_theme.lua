-- JRS theme export: use the jrs_core look in your own NUI.
--   local theme = exports.jrs_core:GetTheme()
--   theme.css  -> 'nui://jrs_core/html/theme/jrs-theme.css'
-- In your html:  <link rel="stylesheet" href="nui://jrs_core/html/theme/jrs-theme.css">
-- Classes: jrs-panel, jrs-header, jrs-title, jrs-btn (+ .active), jrs-card (+ .active), jrs-input, jrs-muted
local base = 'nui://jrs_core/html/'
local THEME = {
    css = base .. 'theme/jrs-theme.css',
    images = {
        panel = base .. 'storeui/panel-background.png',
        header = base .. 'storeui/ui-header.png',
        tab = base .. 'storeui/tab.png',
        tabActive = base .. 'storeui/tab-active.png',
        card = base .. 'storeui/card.png',
        cardActive = base .. 'storeui/card-active.png',
    },
    fonts = {
        title = base .. 'RDRLino-Regular.ttf',
        body = base .. 'Hapna-Regular.ttf',
    },
    colors = {
        text = '#f2eee7', muted = '#c8c3bb', dim = '#85817b', line = 'rgba(255,255,255,.09)',
        field = 'rgba(0,0,0,.44)', danger = '#c77f79', success = '#9db5a7',
    },
}

exports('GetTheme', function()
    return json.decode(json.encode(THEME))
end)
