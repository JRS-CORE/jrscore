-- jrs_fishing | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
author 'JRS TEAM'
description 'A fishing script for jrs core framework'


shared_scripts {
	"config/config.lua",
	"config/baits.lua",
	"config/baitsPerFish.lua",
	"config/fishData.lua",
	"translation/translation.lua"
}

client_scripts {
	'client/client_js.js',
	'client/client.lua'
}

server_script {
	'server/server.lua'
}

dependencies {
	'jrs_core',
	'jrs_inventory'
}

exports {
	'GET_TASK_FISHING_DATA',
	'SET_TASK_FISHING_DATA',
	'VERTICAL_PROBE'
}

--dont touch
version '1.2'

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
