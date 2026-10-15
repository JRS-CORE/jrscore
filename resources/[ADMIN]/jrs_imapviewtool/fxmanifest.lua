-- jrs_imapviewtool | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version "cerulean"
version '1.0.0'
game "rdr3"
author 'JRS TEAM'
rdr3_warning "I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships."

shared_script "@jrs_core/lib/import.lua"

client_scripts {
    "client.lua"
}

files {
    "imaps_with_coords_and_heading.lua",
}

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
