-- jrs_wildhorse | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core wild horses - break in wild horses and sell them to a trainer'
version '1.3.0'

shared_scripts {
    'config.lua',
    'shared/locale.lua',
}
client_script 'client/main.lua'
server_script 'server/main.lua'

dependency 'jrs_core'

jrs_api 'ext'
