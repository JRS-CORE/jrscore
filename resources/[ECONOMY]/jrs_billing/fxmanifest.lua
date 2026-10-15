fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'jrs_billing'
author 'JRS TEAM'
description 'JRS Core - job billing: /bill a nearby player, money to the biller, receipt item'
version '1.0.0'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',
    'config.lua',
}
client_script 'client/main.lua'
server_scripts { 'server/main.lua' }

ui_page 'ui/index.html'
files { 'ui/*' }

dependencies { 'jrs_core', 'jrs_inventory' }
