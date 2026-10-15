fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core traders - NPC traders with stock-based prices, managed in game with /traderadmin'
version '1.0.0'

shared_scripts {
    'shared/locale.lua',
    'shared/jrs_kit.lua',
    'config.lua',
}

client_scripts { 'client/main.lua' }
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies { 'jrs_core', 'jrs_inventory', 'oxmysql' }

jrs_api 'ext'
