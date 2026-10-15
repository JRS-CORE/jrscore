fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

author 'JRS TEAM'
description 'jrs core native zone notifications for jrs_core'
version '1.3.0'

dependency 'jrs_core'

escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'html/locales/*.js',
}


ui_page 'html/index.html'

files {
    'html/locales/*.js',
    'html/jrs-i18n.css',
    'html/jrs-i18n.js',
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/assets/box_a_bg_1.png',
    'html/assets/zone_open.mp3'
}

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',

    'config/config.lua',
    'config/zones.lua'
}

client_scripts {
    '@jrs_core/shared/pad_guard.lua',
    '@jrs_core/shared/jrs_lang_nui.lua',
    'client/main.lua',
}
