fx_version 'cerulean'
games { 'rdr3' }
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core barber - hair, beard and hair colour in the barber chair'
version '1.1.0'

provide 'jrs_barber'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',
    'shared/callbacks.lua',
    'shared/barber/config.lua',
    'shared/barber/lang.lua',
    'shared/barber/overlays.lua',
    'shared/barber/assets.lua',
}

client_scripts {
    '@jrs_core/shared/pad_guard.lua',
    '@jrs_core/client/dataview.lua',
    'client/common/nui_bridge.lua',
    'client/barber/engine.lua',
    'client/barber/adapter.lua',
    'client/barber/shop.lua',
    'client/barber/seat.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/common/adapter.lua',
    'server/barber/database.lua',
    'server/barber/callbacks.lua',
    'server/barber/server.lua',
}

ui_page 'ui/index.html'
files { 'ui/*' }

dependencies { 'oxmysql', 'jrs_core', 'jrs_inventory' }
