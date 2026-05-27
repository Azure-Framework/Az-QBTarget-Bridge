BridgePeds = BridgePeds or {}

local RESOURCE = GetCurrentResourceName()
local pedsReady = false
local spawnedPeds = {}

local function debugPrint(...)
    if Config and Config.Debug then
        print(('[%s][PEDS]'):format(RESOURCE), ...)
    end
end

local function modelHash(model)
    if type(model) == 'string' then return joaat(model) end
    return model
end

local function loadModel(model)
    local hash = modelHash(model)
    if not IsModelInCdimage(hash) then
        debugPrint('model does not exist', tostring(model))
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then
            debugPrint('model load timed out', tostring(model))
            return nil
        end
    end

    return hash
end

local function loadAnim(dict)
    if not dict then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        Wait(0)
        if GetGameTimer() > timeout then return false end
    end
    return true
end

local function toVector4(coords)
    if type(coords) == 'vector4' then return coords end
    if type(coords) == 'vector3' then return vector4(coords.x, coords.y, coords.z, 0.0) end
    if type(coords) == 'table' then
        return vector4(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0, coords.w or coords.h or coords.heading or coords[4] or 0.0)
    end
    return vector4(0.0, 0.0, 0.0, 0.0)
end

local function applyPedSettings(ped, data)
    if data.freeze then FreezeEntityPosition(ped, true) end
    if data.invincible then SetEntityInvincible(ped, true) end
    if data.blockevents then SetBlockingOfNonTemporaryEvents(ped, true) end

    if data.scenario then
        SetPedCanPlayAmbientAnims(ped, true)
        TaskStartScenarioInPlace(ped, data.scenario, 0, true)
    elseif data.animDict and data.anim and loadAnim(data.animDict) then
        TaskPlayAnim(ped, data.animDict, data.anim, 8.0, 0.0, -1, data.flag or 1, 0.0, false, false, false)
    end

    if data.pedrelations and type(data.pedrelations.groupname) == 'string' then
        local groupName = data.pedrelations.groupname
        local groupHash = joaat(groupName)

        if not DoesRelationshipGroupExist(groupHash) then
            AddRelationshipGroup(groupName)
        end

        SetPedRelationshipGroupHash(ped, groupHash)

        if data.pedrelations.toplayer then
            SetRelationshipBetweenGroups(data.pedrelations.toplayer, groupHash, joaat('PLAYER'))
        end

        if data.pedrelations.toowngroup then
            SetRelationshipBetweenGroups(data.pedrelations.toowngroup, groupHash, groupHash)
        end
    end

    if data.weapon and data.weapon.name then
        local weapon = modelHash(data.weapon.name)
        if IsWeaponValid(weapon) then
            SetCanPedEquipWeapon(ped, weapon, true)
            GiveWeaponToPed(ped, weapon, data.weapon.ammo or 0, data.weapon.hidden or false, true)
            SetPedCurrentWeaponVisible(ped, not data.weapon.hidden, true, false, false)
        end
    end
end

local function addTargetToPed(ped, data, model)
    if not data.target then return end

    local parameters = {
        options = data.target.options or {},
        distance = data.target.distance or Config.MaxDistance
    }

    CreateThread(function()
        Wait(0)
        if data.target.useModel then
            exports[RESOURCE]:AddTargetModel(model, parameters)
        else
            exports[RESOURCE]:AddTargetEntity(ped, parameters)
        end
    end)
end

local function spawnOne(data)
    if type(data) ~= 'table' then return nil end
    if not data.model or not data.coords then
        debugPrint('ped spawn skipped; missing model or coords')
        return nil
    end

    local hash = loadModel(data.model)
    if not hash then return nil end

    local coords = toVector4(data.coords)
    local z = data.minusOne and (coords.z - 1.0) or coords.z
    local ped = CreatePed(0, hash, coords.x, coords.y, z, coords.w, data.networked or false, true)

    if not ped or ped == 0 then
        debugPrint('CreatePed failed', tostring(data.model))
        return nil
    end

    SetEntityAsMissionEntity(ped, true, true)
    applyPedSettings(ped, data)
    addTargetToPed(ped, data, hash)
    SetModelAsNoLongerNeeded(hash)

    data.currentpednumber = ped
    spawnedPeds[#spawnedPeds + 1] = ped

    if data.action then
        local ok, err = pcall(data.action, data)
        if not ok then debugPrint('ped action failed', tostring(err)) end
    end

    debugPrint('spawned ped', ped)
    return ped
end

function BridgePeds.SpawnPed(data)
    if type(data) ~= 'table' then return nil end

    local firstKey, firstValue = next(data)
    if type(firstKey) == 'number' and type(firstValue) == 'table' then
        local results = {}
        for _, pedData in pairs(data) do
            if pedData.spawnNow ~= false then
                results[#results + 1] = spawnOne(pedData)
            end
            Config.Peds = Config.Peds or {}
            Config.Peds[#Config.Peds + 1] = pedData
        end
        return results
    end

    local ped
    if data.spawnNow ~= false then ped = spawnOne(data) end
    Config.Peds = Config.Peds or {}
    Config.Peds[#Config.Peds + 1] = data
    return ped
end

function BridgePeds.DeletePeds()
    for i = #spawnedPeds, 1, -1 do
        local ped = spawnedPeds[i]
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
        spawnedPeds[i] = nil
    end

    if Config.Peds then
        for _, data in pairs(Config.Peds) do
            data.currentpednumber = 0
        end
    end

    pedsReady = false
    debugPrint('deleted all bridge peds')
end

function BridgePeds.RemoveSpawnedPed(peds)
    if type(peds) == 'table' then
        for _, ped in pairs(peds) do
            if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
        end
    elseif type(peds) == 'number' then
        if DoesEntityExist(peds) then DeleteEntity(peds) end
    end
end

function BridgePeds.GetPeds()
    return Config.Peds or {}
end

function BridgePeds.UpdatePedsData(data)
    Config.Peds = data or {}
    BridgePeds.DeletePeds()
    pedsReady = false
    CreateThread(function()
        Wait(250)
        if Config.Peds and next(Config.Peds) then
            for _, pedData in pairs(Config.Peds) do
                if pedData.spawnNow ~= false then spawnOne(pedData) end
            end
            pedsReady = true
        end
    end)
end

local function spawnConfiguredPeds()
    if pedsReady then return end
    if not Config.Peds or not next(Config.Peds) then return end

    for _, pedData in pairs(Config.Peds) do
        if pedData.spawnNow ~= false then spawnOne(pedData) end
    end

    pedsReady = true
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', spawnConfiguredPeds)
RegisterNetEvent('ND:characterLoaded', spawnConfiguredPeds)
RegisterNetEvent('esx:playerLoaded', spawnConfiguredPeds)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() BridgePeds.DeletePeds() end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= RESOURCE then return end
    CreateThread(function()
        Wait(1000)
        spawnConfiguredPeds()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then BridgePeds.DeletePeds() end
end)
