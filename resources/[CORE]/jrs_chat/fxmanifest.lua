-- jrs_chat | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core chat - character names, OOC, server announcements and spam protection'
version '1.0.0'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/css/style.css',
  'html/js/config.js',
  'html/js/App.js',
  'html/js/Message.js',
  'html/js/Suggestions.js',
}

shared_scripts {
  'shared/locale.lua',
  'shared/jrs_kit.lua',
  'config.lua',
}

client_scripts {
  'client/main.lua',
}

server_scripts {
  'server/main.lua',
}

chat_theme 'gtao' {
  msgTemplates = {
    default = '<b>{0}</b><span>{1}</span>'
  }
}

dependencies { 'jrs_core' }

-- the chat other resources talk to (chat:addMessage / chat:addSuggestion ...)
provide 'chat'

jrs_api 'ext'
