fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-target'
author 'MadeByAzure'
description 'Az-Framework qb-target compatibility bridge powered by ox_target'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/framework.lua',
    'client/convert.lua',
    'client/peds.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target'
}
