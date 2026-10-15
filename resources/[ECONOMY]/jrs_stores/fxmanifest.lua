-- jrs_stores | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
name 'jrs stores'
author 'JRS TEAM'
description 'A store script for jrs core framework'
lua54 'yes'


ui_page 'html/index.html'
files { 'html/**/*' }
dependencies { 'jrs_core', 'jrs_inventory' }

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'config.lua',
    'shared/buyitemsCFG.lua',
    'shared/sellitemsCFG.lua',
    'shared/language.lua',
    'shared/ui.lua'
}
client_scripts { 'client/nui.lua', 'client/client.lua' }

server_script 'server/server.lua'


version '2.5.0'

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
