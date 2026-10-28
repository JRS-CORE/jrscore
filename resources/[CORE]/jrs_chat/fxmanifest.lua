-- ===================================================================
-- JRS CHAT | Manifest
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

author 'JRS TEAM'
description 'Native JRS RedM Roleplay Chat with Local Proximity, Suggestions and Custom UI'
version '2.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'jrs_core'
}

provide 'chat'
