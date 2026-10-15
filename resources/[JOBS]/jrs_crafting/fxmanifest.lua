fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core crafting - stations, campfires and recipes in the JRS menu'
version '2.0.0'

shared_scripts {
    'shared/jrs_kit.lua',
    'config.lua',
    'config/animations.lua',
    'config/recipes.lua',
    'shared/locale.lua',
    'languages/*.lua',
}

client_scripts {
    'client/client.lua',
    'client/services/*.lua',
}

server_script 'server/server.lua'

dependencies { 'jrs_core', 'jrs_inventory', 'jrs_progressbar' }

jrs_api 'ext'
