local RESOURCE = GetCurrentResourceName()

local Registry = {
    zones = {},
    entityZones = {},
    bones = {},
    globals = {
        ped = {},
        vehicle = {},
        object = {},
        player = {},
        type1 = {},
        type2 = {},
        type3 = {}
    }
}

local function debugPrint(...)
    if Config and Config.Debug then
        print(('[%s][BRIDGE]'):format(RESOURCE), ...)
    end
end

local function oxReady()
    return GetResourceState('ox_target') == 'started'
end

local function oxCall(method, ...)
    if not oxReady() then
        debugPrint(('ox_target is not started; cannot call %s'):format(method))
        return nil
    end

    local args = { ... }
    local ok, result = pcall(function()
        return exports.ox_target[method](exports.ox_target, table.unpack(args))
    end)

    if ok then return result end

    ok, result = pcall(function()
        return exports.ox_target[method](table.unpack(args))
    end)

    if ok then return result end

    debugPrint(('ox_target:%s failed: %s'):format(method, tostring(result)))
    return nil
end

local function toVec3(value)
    if type(value) == 'vector3' then return value end
    if type(value) == 'vector4' then return vector3(value.x, value.y, value.z) end
    if type(value) == 'table' then return vector3(value.x or value[1] or 0.0, value.y or value[2] or 0.0, value.z or value[3] or 0.0) end
    return vector3(0.0, 0.0, 0.0)
end

local function toVec2List(points, z)
    local out = {}
    if type(points) ~= 'table' then return out end

    for i = 1, #points do
        local point = points[i]
        if type(point) == 'vector2' then
            out[#out + 1] = vector3(point.x, point.y, z)
        elseif type(point) == 'vector3' or type(point) == 'vector4' then
            out[#out + 1] = vector3(point.x, point.y, z or point.z)
        elseif type(point) == 'table' then
            out[#out + 1] = vector3(point.x or point[1] or 0.0, point.y or point[2] or 0.0, z or point.z or point[3] or 0.0)
        end
    end

    return out
end

local function normalizeList(value)
    if value == nil then return nil end
    if type(value) == 'table' then return value end
    return { value }
end

local function rememberNames(bucket, names)
    if not names then return end
    for i = 1, #names do bucket[#bucket + 1] = names[i] end
end

local function getNames(labels, fallback)
    if labels then return labels end
    if fallback and #fallback > 0 then return fallback end
    return nil
end

local function makeZoneObject(name, id, targetoptions)
    return {
        id = id,
        name = name,
        targetoptions = targetoptions,
        destroy = function() exports[RESOURCE]:RemoveZone(name) end,
        remove = function() exports[RESOURCE]:RemoveZone(name) end
    }
end

local function AddCircleZone(name, center, radius, options, targetoptions)
    options = options or {}
    targetoptions = targetoptions or {}

    local converted = BridgeConvert.convertOptions(targetoptions, targetoptions.distance or Config.MaxDistance, name)
    local id = oxCall('addSphereZone', {
        name = name,
        coords = toVec3(center),
        radius = radius or 1.0,
        debug = options.debugPoly or options.debug or false,
        options = converted
    })

    Registry.zones[name] = { id = id, type = 'circle' }
    debugPrint('AddCircleZone', name, id)
    return makeZoneObject(name, id, targetoptions)
end

exports('AddCircleZone', AddCircleZone)

local function AddBoxZone(name, center, length, width, options, targetoptions)
    options = options or {}
    targetoptions = targetoptions or {}

    local coords = toVec3(center)
    local minZ = options.minZ
    local maxZ = options.maxZ
    local thickness = 4.0

    if minZ and maxZ then
        thickness = math.abs(maxZ - minZ)
        if not options.useZ then
            coords = vector3(coords.x, coords.y, (minZ + maxZ) / 2)
        end
    elseif options.height then
        thickness = options.height
    end

    local converted = BridgeConvert.convertOptions(targetoptions, targetoptions.distance or Config.MaxDistance, name)
    local id = oxCall('addBoxZone', {
        name = name,
        coords = coords,
        size = vector3(width or 1.0, length or 1.0, thickness),
        rotation = options.heading or options.rotation or 0.0,
        debug = options.debugPoly or options.debug or false,
        options = converted
    })

    Registry.zones[name] = { id = id, type = 'box' }
    debugPrint('AddBoxZone', name, id)
    return makeZoneObject(name, id, targetoptions)
end

exports('AddBoxZone', AddBoxZone)

local function AddPolyZone(name, points, options, targetoptions)
    options = options or {}
    targetoptions = targetoptions or {}

    local minZ = options.minZ or 0.0
    local maxZ = options.maxZ or (minZ + 4.0)
    local thickness = math.abs(maxZ - minZ)
    local z = minZ + (thickness / 2)

    local converted = BridgeConvert.convertOptions(targetoptions, targetoptions.distance or Config.MaxDistance, name)
    local id = oxCall('addPolyZone', {
        name = name,
        points = toVec2List(points, z),
        thickness = thickness,
        debug = options.debugPoly or options.debug or false,
        options = converted
    })

    Registry.zones[name] = { id = id, type = 'poly' }
    debugPrint('AddPolyZone', name, id)
    return makeZoneObject(name, id, targetoptions)
end

exports('AddPolyZone', AddPolyZone)

local function AddComboZone(zones, options, targetoptions)
    options = options or {}
    targetoptions = targetoptions or {}

    local name = options.name or ('combo_%s'):format(GetGameTimer())
    local ids = {}

    
    if type(zones) == 'table' then
        for i = 1, #zones do
            local zone = zones[i]
            local childName = ('%s_%s'):format(name, i)
            local id

            if type(zone) == 'table' and zone.radius and zone.center then
                id = AddCircleZone(childName, zone.center, zone.radius, { debugPoly = options.debugPoly }, targetoptions).id
            elseif type(zone) == 'table' and zone.length and zone.width and zone.center then
                id = AddBoxZone(childName, zone.center, zone.length, zone.width, {
                    minZ = zone.minZ,
                    maxZ = zone.maxZ,
                    heading = zone.heading,
                    debugPoly = options.debugPoly
                }, targetoptions).id
            elseif type(zone) == 'table' and zone.points then
                id = AddPolyZone(childName, zone.points, {
                    minZ = zone.minZ,
                    maxZ = zone.maxZ,
                    debugPoly = options.debugPoly
                }, targetoptions).id
            elseif type(zone) == 'number' then
                id = zone
            end

            if id then ids[#ids + 1] = id end
        end
    end

    Registry.zones[name] = { id = ids, type = 'combo' }
    debugPrint('AddComboZone', name, #ids)
    return makeZoneObject(name, ids, targetoptions)
end

exports('AddComboZone', AddComboZone)

local function addEntityTarget(entity, options)
    if not entity or entity == 0 then return end

    if NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        return oxCall('addEntity', netId, options)
    end

    return oxCall('addLocalEntity', entity, options)
end

local function removeEntityTarget(entity, labels)
    if not entity or entity == 0 then return end

    if NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        return oxCall('removeEntity', netId, labels)
    end

    return oxCall('removeLocalEntity', entity, labels)
end

local function AddEntityZone(name, entity, options, targetoptions)
    targetoptions = targetoptions or {}
    local converted, names = BridgeConvert.convertOptions(targetoptions, targetoptions.distance or Config.MaxDistance, name)

    addEntityTarget(entity, converted)
    Registry.entityZones[name] = { entity = entity, names = names }

    debugPrint('AddEntityZone', name, entity)
    return makeZoneObject(name, entity, targetoptions)
end

exports('AddEntityZone', AddEntityZone)

local function RemoveZone(name)
    local zone = Registry.zones[name]
    if zone then
        if type(zone.id) == 'table' then
            for i = 1, #zone.id do oxCall('removeZone', zone.id[i]) end
        else
            oxCall('removeZone', zone.id or name)
        end
        Registry.zones[name] = nil
        debugPrint('RemoveZone', name)
        return
    end

    local entityZone = Registry.entityZones[name]
    if entityZone then
        removeEntityTarget(entityZone.entity, entityZone.names)
        Registry.entityZones[name] = nil
        debugPrint('RemoveEntityZone', name)
        return
    end

    oxCall('removeZone', name)
end

exports('RemoveZone', RemoveZone)

local function AddTargetBone(bones, parameters)
    parameters = parameters or {}
    local boneList = normalizeList(bones) or {}
    local converted, names = BridgeConvert.convertOptions(parameters, parameters.distance or Config.MaxDistance, 'bone')

    for i = 1, #converted do
        converted[i].bones = boneList
    end

    oxCall('addGlobalVehicle', converted)

    for i = 1, #boneList do
        local bone = boneList[i]
        Registry.bones[bone] = Registry.bones[bone] or {}
        rememberNames(Registry.bones[bone], names)
    end

    debugPrint('AddTargetBone', table.concat(boneList, ', '))
end

exports('AddTargetBone', AddTargetBone)

local function RemoveTargetBone(bones, labels)
    local boneList = normalizeList(bones) or {}
    local remove = labels

    if not remove then
        remove = {}
        for i = 1, #boneList do
            local stored = Registry.bones[boneList[i]] or {}
            for j = 1, #stored do remove[#remove + 1] = stored[j] end
            Registry.bones[boneList[i]] = nil
        end
    end

    if remove then oxCall('removeGlobalVehicle', remove) end
    debugPrint('RemoveTargetBone')
end

exports('RemoveTargetBone', RemoveTargetBone)

local function AddTargetEntity(entities, parameters)
    parameters = parameters or {}
    local converted = BridgeConvert.convertOptions(parameters, parameters.distance or Config.MaxDistance, 'entity')
    local list = normalizeList(entities) or {}

    for i = 1, #list do
        addEntityTarget(list[i], converted)
    end

    debugPrint('AddTargetEntity', #list)
end

exports('AddTargetEntity', AddTargetEntity)

local function RemoveTargetEntity(entities, labels)
    local list = normalizeList(entities) or {}
    for i = 1, #list do
        removeEntityTarget(list[i], labels)
    end
    debugPrint('RemoveTargetEntity', #list)
end

exports('RemoveTargetEntity', RemoveTargetEntity)

local function AddTargetModel(models, parameters)
    parameters = parameters or {}
    local converted = BridgeConvert.convertOptions(parameters, parameters.distance or Config.MaxDistance, 'model')
    oxCall('addModel', models, converted)
    debugPrint('AddTargetModel')
end

exports('AddTargetModel', AddTargetModel)

local function RemoveTargetModel(models, labels)
    oxCall('removeModel', models, labels)
    debugPrint('RemoveTargetModel')
end

exports('RemoveTargetModel', RemoveTargetModel)

local function AddGlobalType(targetType, parameters)
    parameters = parameters or {}
    local converted, names = BridgeConvert.convertOptions(parameters, parameters.distance or Config.MaxDistance, ('type%s'):format(targetType))

    if targetType == 1 then
        oxCall('addGlobalPed', converted)
        rememberNames(Registry.globals.type1, names)
    elseif targetType == 2 then
        oxCall('addGlobalVehicle', converted)
        rememberNames(Registry.globals.type2, names)
    elseif targetType == 3 then
        oxCall('addGlobalObject', converted)
        rememberNames(Registry.globals.type3, names)
    end
end

exports('AddGlobalType', AddGlobalType)

local function AddGlobalPed(parameters)
    local converted, names = BridgeConvert.convertOptions(parameters, parameters and parameters.distance or Config.MaxDistance, 'globalPed')
    oxCall('addGlobalPed', converted)
    rememberNames(Registry.globals.ped, names)
end

exports('AddGlobalPed', AddGlobalPed)

local function AddGlobalVehicle(parameters)
    local converted, names = BridgeConvert.convertOptions(parameters, parameters and parameters.distance or Config.MaxDistance, 'globalVehicle')
    oxCall('addGlobalVehicle', converted)
    rememberNames(Registry.globals.vehicle, names)
end

exports('AddGlobalVehicle', AddGlobalVehicle)

local function AddGlobalObject(parameters)
    local converted, names = BridgeConvert.convertOptions(parameters, parameters and parameters.distance or Config.MaxDistance, 'globalObject')
    oxCall('addGlobalObject', converted)
    rememberNames(Registry.globals.object, names)
end

exports('AddGlobalObject', AddGlobalObject)

local function AddGlobalPlayer(parameters)
    local converted, names = BridgeConvert.convertOptions(parameters, parameters and parameters.distance or Config.MaxDistance, 'globalPlayer')
    oxCall('addGlobalPlayer', converted)
    rememberNames(Registry.globals.player, names)
end

exports('AddGlobalPlayer', AddGlobalPlayer)

local function RemoveGlobalType(targetType, labels)
    if targetType == 1 then oxCall('removeGlobalPed', getNames(labels, Registry.globals.type1)); Registry.globals.type1 = {} end
    if targetType == 2 then oxCall('removeGlobalVehicle', getNames(labels, Registry.globals.type2)); Registry.globals.type2 = {} end
    if targetType == 3 then oxCall('removeGlobalObject', getNames(labels, Registry.globals.type3)); Registry.globals.type3 = {} end
end

exports('RemoveGlobalType', RemoveGlobalType)

local function RemoveGlobalPed(labels)
    oxCall('removeGlobalPed', getNames(labels, Registry.globals.ped))
    if not labels then Registry.globals.ped = {} end
end

exports('RemoveGlobalPed', RemoveGlobalPed)

local function RemoveGlobalVehicle(labels)
    oxCall('removeGlobalVehicle', getNames(labels, Registry.globals.vehicle))
    if not labels then Registry.globals.vehicle = {} end
end

exports('RemoveGlobalVehicle', RemoveGlobalVehicle)

local function RemoveGlobalObject(labels)
    oxCall('removeGlobalObject', getNames(labels, Registry.globals.object))
    if not labels then Registry.globals.object = {} end
end

exports('RemoveGlobalObject', RemoveGlobalObject)

local function RemoveGlobalPlayer(labels)
    oxCall('removeGlobalPlayer', getNames(labels, Registry.globals.player))
    if not labels then Registry.globals.player = {} end
end

exports('RemoveGlobalPlayer', RemoveGlobalPlayer)

local function AllowTargeting(value)
    oxCall('disableTargeting', value == false)
end

exports('AllowTargeting', AllowTargeting)

local function DisableTarget(value)
    oxCall('disableTargeting', value ~= false)
end

exports('DisableTarget', DisableTarget)
exports('DisableNUI', function() oxCall('disableTargeting', true) end)
exports('EnableNUI', function() oxCall('disableTargeting', false) end)
exports('LeftTarget', function() oxCall('disableTargeting', false) end)

local function IsTargetActive()
    return oxCall('isActive') or false
end

exports('IsTargetActive', IsTargetActive)
exports('IsTargetSuccess', IsTargetActive)
exports('RaycastCamera', function() return nil, 0.0, 0, 0 end)
exports('DrawOutlineEntity', function() end)
exports('CheckEntity', function() return false end)
exports('CheckBones', function() return false end)

exports('GetGlobalTypeData', function() return Registry.globals end)
exports('GetZoneData', function() return Registry.zones end)
exports('GetTargetBoneData', function() return Registry.bones end)
exports('GetTargetEntityData', function() return Registry.entityZones end)
exports('GetTargetModelData', function() return {} end)
exports('GetGlobalPedData', function() return Registry.globals.ped end)
exports('GetGlobalVehicleData', function() return Registry.globals.vehicle end)
exports('GetGlobalObjectData', function() return Registry.globals.object end)
exports('GetGlobalPlayerData', function() return Registry.globals.player end)
exports('GetFrameworkName', function() return BridgeFramework.name() end)

exports('UpdateGlobalTypeData', function(targetType, parameters) RemoveGlobalType(targetType); AddGlobalType(targetType, parameters) end)
exports('UpdateZoneData', function(name, data) if data then Registry.zones[name] = data end end)
exports('UpdateTargetBoneData', function() end)
exports('UpdateTargetEntityData', function() end)
exports('UpdateTargetModelData', function() end)
exports('UpdateGlobalPedData', function(parameters) RemoveGlobalPed(); AddGlobalPed(parameters) end)
exports('UpdateGlobalVehicleData', function(parameters) RemoveGlobalVehicle(); AddGlobalVehicle(parameters) end)
exports('UpdateGlobalObjectData', function(parameters) RemoveGlobalObject(); AddGlobalObject(parameters) end)
exports('UpdateGlobalPlayerData', function(parameters) RemoveGlobalPlayer(); AddGlobalPlayer(parameters) end)

exports('DeletePeds', function() return BridgePeds.DeletePeds() end)
exports('SpawnPed', function(data) return BridgePeds.SpawnPed(data) end)
exports('RemoveSpawnedPed', function(peds) return BridgePeds.RemoveSpawnedPed(peds) end)
exports('GetPeds', function() return BridgePeds.GetPeds() end)
exports('UpdatePedsData', function(data) return BridgePeds.UpdatePedsData(data) end)


local qtargetAliases = {
    AddCircleZone = AddCircleZone,
    AddBoxZone = AddBoxZone,
    AddPolyZone = AddPolyZone,
    AddComboZone = AddComboZone,
    AddEntityZone = AddEntityZone,
    RemoveZone = RemoveZone,
    AddTargetBone = AddTargetBone,
    RemoveTargetBone = RemoveTargetBone,
    AddTargetEntity = AddTargetEntity,
    RemoveTargetEntity = RemoveTargetEntity,
    AddTargetModel = AddTargetModel,
    RemoveTargetModel = RemoveTargetModel,
    Ped = AddGlobalPed,
    RemovePed = RemoveGlobalPed,
    Vehicle = AddGlobalVehicle,
    RemoveVehicle = RemoveGlobalVehicle,
    Object = AddGlobalObject,
    RemoveObject = RemoveGlobalObject,
    Player = AddGlobalPlayer,
    RemovePlayer = RemoveGlobalPlayer
}

for exportName, func in pairs(qtargetAliases) do
    AddEventHandler(('__cfx_export_qtarget_%s'):format(exportName), function(setCB)
        setCB(func)
    end)
end


for exportName, func in pairs({
    AddCircleZone = AddCircleZone,
    AddBoxZone = AddBoxZone,
    AddPolyZone = AddPolyZone,
    AddComboZone = AddComboZone,
    AddEntityZone = AddEntityZone,
    RemoveZone = RemoveZone,
    AddTargetBone = AddTargetBone,
    RemoveTargetBone = RemoveTargetBone,
    AddTargetEntity = AddTargetEntity,
    RemoveTargetEntity = RemoveTargetEntity,
    AddTargetModel = AddTargetModel,
    RemoveTargetModel = RemoveTargetModel,
    AddGlobalType = AddGlobalType,
    AddGlobalPed = AddGlobalPed,
    AddGlobalVehicle = AddGlobalVehicle,
    AddGlobalObject = AddGlobalObject,
    AddGlobalPlayer = AddGlobalPlayer,
    RemoveGlobalType = RemoveGlobalType,
    RemoveGlobalPed = RemoveGlobalPed,
    RemoveGlobalVehicle = RemoveGlobalVehicle,
    RemoveGlobalObject = RemoveGlobalObject,
    RemoveGlobalPlayer = RemoveGlobalPlayer,
    AllowTargeting = AllowTargeting,
    DisableTarget = DisableTarget,
    IsTargetActive = IsTargetActive,
    IsTargetSuccess = IsTargetActive
}) do
    AddEventHandler(('__cfx_export_qb-target_%s'):format(exportName), function(setCB)
        setCB(func)
    end)
end

RegisterNetEvent('qb-target:client:AddBoxZone', AddBoxZone)
RegisterNetEvent('qb-target:client:AddCircleZone', AddCircleZone)
RegisterNetEvent('qb-target:client:AddPolyZone', AddPolyZone)
RegisterNetEvent('qb-target:client:AddTargetModel', AddTargetModel)
RegisterNetEvent('qb-target:client:RemoveTargetModel', RemoveTargetModel)
RegisterNetEvent('qb-target:client:AddTargetEntity', AddTargetEntity)
RegisterNetEvent('qb-target:client:RemoveTargetEntity', RemoveTargetEntity)
RegisterNetEvent('qb-target:client:AddGlobalPed', AddGlobalPed)
RegisterNetEvent('qb-target:client:AddGlobalVehicle', AddGlobalVehicle)
RegisterNetEvent('qb-target:client:AddGlobalObject', AddGlobalObject)
RegisterNetEvent('qb-target:client:AddGlobalPlayer', AddGlobalPlayer)
RegisterNetEvent('qb-target:client:RemoveZone', RemoveZone)

if Config.TestCommands then
    RegisterCommand('aztargettestbox', function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        AddBoxZone('az_bridge_test_box', coords, 2.0, 2.0, {
            heading = GetEntityHeading(ped),
            minZ = coords.z - 1.0,
            maxZ = coords.z + 1.0,
            debugPoly = true
        }, {
            options = {
                {
                    icon = 'fas fa-code',
                    label = 'Az Bridge Test Box',
                    action = function(entity)
                        print('[qb-target bridge] Box option selected. entity=' .. tostring(entity))
                    end
                }
            },
            distance = 2.5
        })
    end, false)

    RegisterCommand('aztargettestped', function()
        local ped = PlayerPedId()
        local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
        BridgePeds.SpawnPed({
            model = 'a_m_m_business_01',
            coords = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped) + 180.0),
            freeze = true,
            invincible = true,
            blockevents = true,
            spawnNow = true,
            target = {
                options = {
                    {
                        icon = 'fas fa-user',
                        label = 'Az Bridge Test Ped',
                        action = function(entity)
                            print('[qb-target bridge] Ped option selected. entity=' .. tostring(entity))
                        end
                    }
                },
                distance = 2.5
            }
        })
    end, false)

    RegisterCommand('aztargetclear', function()
        RemoveZone('az_bridge_test_box')
        BridgePeds.DeletePeds()
        print('[qb-target bridge] Cleared test box and spawned bridge peds.')
    end, false)
end

CreateThread(function()
    while not oxReady() do Wait(250) end
    debugPrint('started; ox_target ready; framework=' .. tostring(BridgeFramework.name()))
end)
