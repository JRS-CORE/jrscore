fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core passports - register, renew and show identity papers'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    'shared/jrs_kit.lua',
    'config.lua',
    'locales.lua',
}
server_scripts { 'server/*.lua' }
client_scripts { 'client/*.lua' }

dependencies { 'jrs_core', 'jrs_inventory', 'oxmysql' }

files { 'html/**/*' }

jrs_api 'ext'
