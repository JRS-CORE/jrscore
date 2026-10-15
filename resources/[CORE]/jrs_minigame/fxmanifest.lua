-- jrs_minigame | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_minigame'
author 'JRS TEAM'
description 'Skill bar: hit E (or click) while the bar is inside the zone'
version '2.0.0'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'config.lua',
}
client_script 'client.lua'

ui_page 'index.html'
files {
    'index.html',
    'scripts.js',
    'css/style.css',
}

jrs_api 'ext'
