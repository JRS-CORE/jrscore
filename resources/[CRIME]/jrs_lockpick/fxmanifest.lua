-- jrs_lockpick | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_lockpick'
author 'JRS TEAM'
description 'Lockpicking minigame - exports.jrs_lockpick:startLockpick(picks)'
version '2.0.0'

shared_script '@jrs_core/shared/jrs_lang.lua'
client_script 'client.lua'

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
}

jrs_api 'ext'
