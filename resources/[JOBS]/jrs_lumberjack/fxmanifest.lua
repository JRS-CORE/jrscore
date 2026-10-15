-- jrs_lumberjack | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_lumberjack'
author 'JRS TEAM'
description 'Chop trees for wood and forest goods'
version '2.0.0'

shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies { 'jrs_core', 'jrs_inventory', 'jrs_minigame' }

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
