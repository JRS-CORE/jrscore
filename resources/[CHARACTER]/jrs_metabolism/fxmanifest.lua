fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
name 'JRS Metabolism'
version '1.1.0'
dependencies { 'jrs_core', 'jrs_inventory', 'oxmysql' }
shared_scripts { '@jrs_core/shared/jrs_lang.lua', 'config.lua', 'consumables.lua' }
client_scripts {
    'client/main.lua', 'client/voice.lua', 'client/utils.lua',
    'client/drain_status/movement.lua', 'client/consumable.lua'
}
server_scripts {
    '@oxmysql/lib/MySQL.lua', 'server/functions.lua', 'server/main.lua', 'server/consumable.lua'
}
ui_page 'ui/index.html'
files {
    'db.sql', 'ui/index.html', 'ui/assets/main.css', 'ui/assets/script.js', 'ui/assets/request.js',
    'ui/assets/fonts/*.ttf', 'ui/assets/icons/*.svg', 'ui/assets/icons/*.png'
}
