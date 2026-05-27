local RESOURCE = GetCurrentResourceName()

local function debugPrint(...)
    if Config and Config.Debug then
        print(('[%s][SERVER]'):format(RESOURCE), ...)
    end
end

CreateThread(function()
    debugPrint('server bridge started')
end)
