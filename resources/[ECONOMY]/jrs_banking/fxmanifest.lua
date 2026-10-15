-- jrs_banking | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version "cerulean"
game "rdr3"
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
author 'JRS TEAM'
description 'Bank system JRS'
lua54 'yes'

ui_page 'html/index.html'
files { 'html/**/*' }
dependency 'jrs_core'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'shared/language.lua',
    'config.lua',
    'shared/ui_language.lua'
}

client_scripts {
    'client/nui.lua',
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'logs.lua',
    'server/server.lua',
}

--dont touch
version '1.9'

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
