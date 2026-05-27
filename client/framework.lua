BridgeFramework = BridgeFramework or {}

local RESOURCE = GetCurrentResourceName()
local selected = 'standalone'
local core = nil
local playerData = {}
local ndGroups = {}
local loaded = false

local function debugPrint(...)
    if Config and Config.Debug then
        print(('[%s][FW]'):format(RESOURCE), ...)
    end
end

local function stateStarted(resource)
    return resource and GetResourceState(resource) == 'started'
end

local function tryExport(resource, exportName, ...)
    if not stateStarted(resource) then return false, nil end

    local args = { ... }
    local ok, result = pcall(function()
        return exports[resource][exportName](exports[resource], table.unpack(args))
    end)

    if ok then return true, result end

    ok, result = pcall(function()
        return exports[resource][exportName](table.unpack(args))
    end)

    if ok then return true, result end

    debugPrint(('export %s:%s failed: %s'):format(resource, exportName, tostring(result)))
    return false, nil
end

local function isArray(tbl)
    if type(tbl) ~= 'table' then return false end
    local n = 0
    for k in pairs(tbl) do
        if type(k) ~= 'number' then return false end
        n += 1
    end
    return n > 0
end

local function getGrade(data)
    if type(data) ~= 'table' then return 0 end
    if type(data.grade) == 'table' then
        return tonumber(data.grade.level or data.grade.grade or data.grade.rank or data.grade.name) or 0
    end
    return tonumber(data.grade or data.rank or data.level) or 0
end

local function getName(data)
    if type(data) ~= 'table' then return nil end
    return data.name or data.id or data.label
end

local function gradePass(required, grade)
    if required == nil or required == false then return false end
    if required == true then return true end
    return (tonumber(grade) or 0) >= (tonumber(required) or 0)
end

local function matchGroupFilter(filter, currentName, currentGrade, extraGroups)
    if not filter then return true end
    if filter == 'all' then return true end

    local filterType = type(filter)

    if filterType == 'string' then
        if currentName == filter then return true end
        if extraGroups and extraGroups[filter] then return true end
        return false
    end

    if filterType ~= 'table' then return false end

    if isArray(filter) then
        for i = 1, #filter do
            local name = filter[i]
            if name == 'all' or currentName == name or (extraGroups and extraGroups[name]) then
                return true
            end
        end
        return false
    end

    for name, requiredGrade in pairs(filter) do
        if name == 'all' then return true end

        if currentName == name then
            if gradePass(requiredGrade, currentGrade) then return true end
        end

        local group = extraGroups and extraGroups[name]
        if group then
            local rank = type(group) == 'table' and (group.rank or group.grade or group.level) or group
            if gradePass(requiredGrade, rank) then return true end
        end
    end

    return false
end

local function setQbData()
    if not core or not core.Functions or not core.Functions.GetPlayerData then return end
    local ok, data = pcall(core.Functions.GetPlayerData)
    if ok and type(data) == 'table' then
        playerData = data
        loaded = true
        debugPrint('QBCore/Az player data refreshed', json.encode({ job = data.job and data.job.name, gang = data.gang and data.gang.name }))
    end
end

local function detectAzCore()
    for _, resource in ipairs(Config.AzFrameworkResources or {}) do
        if stateStarted(resource) then
            local ok, obj = tryExport(resource, 'GetCoreObject')
            if ok and obj then
                selected = 'az'
                core = obj
                debugPrint('detected Az core export', resource)
                setQbData()
                return true
            end

            ok, obj = tryExport(resource, 'GetCore')
            if ok and obj then
                selected = 'az'
                core = obj
                debugPrint('detected Az GetCore export', resource)
                setQbData()
                return true
            end
        end
    end

    return false
end

local function detectQbCore()
    if not stateStarted('qb-core') then return false end
    local ok, obj = tryExport('qb-core', 'GetCoreObject')
    if ok and obj then
        selected = 'qb'
        core = obj
        debugPrint('detected qb-core / Az-QBCore bridge')
        setQbData()
        return true
    end
    return false
end

local function detectND()
    if not stateStarted('ND_Core') then return false end
    selected = 'nd'

    local ok, data = tryExport('ND_Core', 'getPlayer')
    if ok and type(data) == 'table' then
        ndGroups = data.groups or {}
        playerData = data
        loaded = true
    end

    debugPrint('detected ND_Core')
    return true
end

local function detectESX()
    if not stateStarted('es_extended') then return false end
    local ok, obj = tryExport('es_extended', 'getSharedObject')
    if ok and obj then
        selected = 'esx'
        core = obj
        playerData = obj.PlayerData or {}
        loaded = true
        debugPrint('detected ESX')
        return true
    end
    return false
end

function BridgeFramework.detect()
    local wanted = (Config.Framework or 'auto'):lower()

    if wanted == 'standalone' then
        selected = 'standalone'
        debugPrint('framework forced standalone')
        return selected
    end

    if wanted == 'az' and detectAzCore() then return selected end
    if wanted == 'qb' and detectQbCore() then return selected end
    if wanted == 'nd' and detectND() then return selected end
    if wanted == 'esx' and detectESX() then return selected end

    if wanted == 'auto' then
        
        if detectAzCore() then return selected end
        if detectQbCore() then return selected end
        if detectND() then return selected end
        if detectESX() then return selected end
    end

    selected = 'standalone'
    loaded = true
    debugPrint('no framework detected; using standalone target permissions')
    return selected
end

function BridgeFramework.name()
    return selected
end

function BridgeFramework.loaded()
    return loaded
end

function BridgeFramework.getPlayerData()
    return playerData or {}
end

function BridgeFramework.hasJob(filter)
    if not filter then return true end

    if selected == 'nd' then
        return matchGroupFilter(filter, nil, 0, ndGroups)
    end

    if selected == 'esx' then
        local job = playerData.job or {}
        local job2 = playerData.job2 or {}
        return matchGroupFilter(filter, getName(job), getGrade(job)) or matchGroupFilter(filter, getName(job2), getGrade(job2))
    end

    local job = playerData.job or {}
    return matchGroupFilter(filter, getName(job), getGrade(job))
end

function BridgeFramework.hasJobType(filter)
    if not filter then return true end
    if filter == 'all' then return true end

    local job = playerData.job or {}
    local jobType = job.type

    if type(filter) == 'string' then return jobType == filter end
    if type(filter) == 'table' then
        if isArray(filter) then
            for i = 1, #filter do
                if filter[i] == jobType or filter[i] == 'all' then return true end
            end
        else
            return filter[jobType] ~= nil
        end
    end

    return false
end

function BridgeFramework.hasGang(filter)
    if not filter then return true end

    if selected == 'nd' then
        return matchGroupFilter(filter, nil, 0, ndGroups)
    end

    local gang = playerData.gang or {}
    return matchGroupFilter(filter, getName(gang), getGrade(gang))
end

function BridgeFramework.hasCitizenId(filter)
    if not filter then return true end

    local citizenid = playerData.citizenid or playerData.citizenId or playerData.charid or playerData.id
    if not citizenid then return false end

    if type(filter) == 'string' or type(filter) == 'number' then
        return tostring(filter) == tostring(citizenid)
    end

    if type(filter) == 'table' then
        return filter[citizenid] or filter[tostring(citizenid)] or false
    end

    return false
end

local function countItemFromPlayerData(name)
    local items = playerData.items or playerData.inventory
    if type(items) ~= 'table' then return 0 end

    if items[name] then
        local item = items[name]
        if type(item) == 'table' then return tonumber(item.amount or item.count or item.quantity) or 0 end
        return tonumber(item) or 0
    end

    for _, item in pairs(items) do
        if type(item) == 'table' and item.name == name then
            return tonumber(item.amount or item.count or item.quantity) or 0
        end
    end

    return 0
end

local function hasOneItem(name, amount)
    if not name then return true end
    amount = tonumber(amount) or 1

    if stateStarted(Config.InventoryResources and Config.InventoryResources.ox or 'ox_inventory') then
        local ok, count = pcall(function()
            return exports.ox_inventory:Search('count', name)
        end)
        if ok and (tonumber(count) or 0) >= amount then return true end
    end

    if core and core.Functions and core.Functions.HasItem then
        local ok, result = pcall(core.Functions.HasItem, name, amount)
        if ok and result then return true end
    end

    return countItemFromPlayerData(name) >= amount
end

function BridgeFramework.hasItem(filter)
    if not filter then return true end

    if type(filter) == 'string' then
        return hasOneItem(filter, 1)
    end

    if type(filter) ~= 'table' then return false end

    if isArray(filter) then
        
        for i = 1, #filter do
            if hasOneItem(filter[i], 1) then return true end
        end
        return false
    end

    
    for name, amount in pairs(filter) do
        if not hasOneItem(name, amount) then return false end
    end

    return true
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    setQbData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    playerData = {}
    loaded = false
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    playerData.job = job
    debugPrint('job update', job and job.name)
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    playerData.gang = gang
    debugPrint('gang update', gang and gang.name)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    if type(data) == 'table' then
        playerData = data
        loaded = true
    end
end)

RegisterNetEvent('ND:characterLoaded', function(data)
    selected = selected == 'standalone' and 'nd' or selected
    playerData = data or {}
    ndGroups = playerData.groups or {}
    loaded = true
    debugPrint('ND character loaded')
end)

RegisterNetEvent('ND:updateCharacter', function(data)
    if type(data) == 'table' then
        playerData = data
        ndGroups = data.groups or ndGroups or {}
        loaded = true
    end
end)

RegisterNetEvent('esx:playerLoaded', function(data)
    playerData = data or {}
    loaded = true
end)

RegisterNetEvent('esx:setJob', function(job)
    playerData.job = job
end)

RegisterNetEvent('esx:setJob2', function(job)
    playerData.job2 = job
end)

CreateThread(function()
    Wait(500)
    BridgeFramework.detect()
end)
