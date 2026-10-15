fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'jrs_loadingscreen'
author 'JRS TEAM'
description 'JRS Loading Screen - RedM / jrs_core compatible'
version '2.10.0'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',
    'config/shared.lua'
}

client_scripts {
    'client/main.lua',
    'client/language.lua'
}

server_scripts {
    'config/server.lua',
    'server/main.lua'
}

files {
    'web/**/*'
}

loadscreen 'web/index.html'
loadscreen_manual_shutdown 'yes'
loadscreen_cursor 'yes'
