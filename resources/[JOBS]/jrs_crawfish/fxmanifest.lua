-- jrs_crawfish | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_crawfish'
author 'JRS TEAM'
description 'Search crawfish holes and harvest the catch'
version '3.0.0'

shared_scripts { 'config.lua', 'shared/text.lua' }
client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies { 'jrs_core', 'jrs_inventory', 'jrs_progressbar' }

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
