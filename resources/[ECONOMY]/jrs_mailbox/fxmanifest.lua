-- jrs_mailbox | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_mailbox'
author 'JRS TEAM'
description 'Telegrams between characters and to the whole server'
version '2.0.0'

shared_script 'config.lua'
client_script 'client/main.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
}

dependencies { 'jrs_core', 'oxmysql' }

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
