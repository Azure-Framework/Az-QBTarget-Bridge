BridgeConvert = BridgeConvert or {}

local RESOURCE = GetCurrentResourceName()
local optionCounter = 0

local function debugPrint(...)
    if Config and Config.Debug then
        print(('[%s][CONVERT]'):format(RESOURCE), ...)
    end
end

local function copyTable(tbl)
    local out = {}
    if type(tbl) ~= 'table' then return out end
    for k, v in pairs(tbl) do out[k] = v end
    return out
end

local function isArray(tbl)
    if type(tbl) ~= 'table' then return false end
    local count = 0
    for k in pairs(tbl) do
        if type(k) ~= 'number' then return false end
        count += 1
    end
    return count > 0
end

local function makeName(option, fallback)
    if option.name then return tostring(option.name) end
    if option.label then return tostring(option.label) end
    optionCounter += 1
    return ('az_qbtarget_%s_%s'):format(fallback or 'option', optionCounter)
end

local function normalizeOptions(input)
    local options = input
    if type(input) == 'table' and input.options then options = input.options end

    local list = {}
    if type(options) ~= 'table' then return list end

    if isArray(options) then
        for i = 1, #options do
            if type(options[i]) == 'table' then
                list[#list + 1] = options[i]
            end
        end
    else
        for key, value in pairs(options) do
            if type(value) == 'table' then
                if not value.name and type(key) == 'string' then value.name = key end
                list[#list + 1] = value
            end
        end
    end

    return list
end

local function buildPayload(original, data)
    local payload = copyTable(original)
    if type(data) == 'table' then
        payload.entity = data.entity
        payload.coords = data.coords or (data.entity and DoesEntityExist(data.entity) and GetEntityCoords(data.entity)) or nil
        payload.distance = data.distance
        payload.zone = data.zone
        payload.bone = data.bone
    end
    return payload
end

local function checkQbRestrictions(option, entity, distance)
    if option.distance and distance and distance > option.distance then return false end

    if option.job and not BridgeFramework.hasJob(option.job) then return false end
    if option.excludejob and BridgeFramework.hasJob(option.excludejob) then return false end

    if option.jobType and not BridgeFramework.hasJobType(option.jobType) then return false end
    if option.excludejobType and BridgeFramework.hasJobType(option.excludejobType) then return false end

    if option.gang and not BridgeFramework.hasGang(option.gang) then return false end
    if option.excludegang and BridgeFramework.hasGang(option.excludegang) then return false end

    local item = option.item or option.required_item
    if item and not BridgeFramework.hasItem(item) then return false end

    if option.citizenid and not BridgeFramework.hasCitizenId(option.citizenid) then return false end

    if option.canInteract then
        local ok, result = pcall(option.canInteract, entity, distance, option)
        if not ok then
            debugPrint(('canInteract failed for %s: %s'):format(tostring(option.label or option.name), tostring(result)))
            return false
        end
        if not result then return false end
    end

    return true
end

local function runQbOption(original, data)
    local payload = buildPayload(original, data)
    local entity = payload.entity

    if original.action then
        local ok, err = pcall(original.action, entity)
        if not ok then debugPrint(('action failed for %s: %s'):format(tostring(original.label or original.name), tostring(err))) end
        return
    end

    if original.onSelect then
        local ok, err = pcall(original.onSelect, data)
        if not ok then debugPrint(('onSelect failed for %s: %s'):format(tostring(original.label or original.name), tostring(err))) end
        return
    end

    if not original.event then
        debugPrint(('selected %s but it has no action/event/onSelect'):format(tostring(original.label or original.name)))
        return
    end

    if original.type == 'server' then
        TriggerServerEvent(original.event, payload)
    elseif original.type == 'command' then
        ExecuteCommand(original.event)
    elseif original.type == 'qbcommand' then
        TriggerServerEvent('QBCore:CallCommand', original.event, payload)
    else
        TriggerEvent(original.event, payload)
    end
end

function BridgeConvert.convertOptions(parameters, defaultDistance, context)
    local baseDistance = defaultDistance or Config.MaxDistance or 7.0
    if type(parameters) == 'table' and parameters.distance then baseDistance = parameters.distance end

    local qbOptions = normalizeOptions(parameters)
    local oxOptions = {}
    local names = {}

    for i = 1, #qbOptions do
        local original = qbOptions[i]
        local converted = copyTable(original)
        local name = makeName(original, context or 'target')

        converted.name = name
        converted.label = original.label or name
        converted.icon = original.icon
        converted.distance = original.distance or baseDistance

        
        converted.groups = nil
        converted.items = nil
        converted.anyItem = nil

        
        converted.action = nil
        converted.event = nil
        converted.type = nil
        converted.job = nil
        converted.excludejob = nil
        converted.jobType = nil
        converted.excludejobType = nil
        converted.gang = nil
        converted.excludegang = nil
        converted.item = nil
        converted.required_item = nil
        converted.citizenid = nil
        converted.qtarget = true
        converted.qbtarget = true
        converted.azBridge = true

        converted.canInteract = function(entity, distance, coords, optionName, bone)
            local ok, allowed = pcall(checkQbRestrictions, original, entity, distance)
            if not ok then
                debugPrint(('restriction check failed for %s: %s'):format(tostring(original.label or original.name), tostring(allowed)))
                return false
            end
            return allowed
        end

        converted.onSelect = function(data)
            runQbOption(original, data)
        end

        oxOptions[#oxOptions + 1] = converted
        names[#names + 1] = name
    end

    debugPrint(('converted %s qb option(s) for %s'):format(#oxOptions, tostring(context)))
    return oxOptions, names
end

function BridgeConvert.optionNames(parameters, context)
    local _, names = BridgeConvert.convertOptions(parameters, nil, context)
    return names
end
