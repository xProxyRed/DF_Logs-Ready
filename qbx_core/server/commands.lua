local config = require 'config.server'
local logger = require 'modules.logger'

GlobalState.PVPEnabled = config.server.pvp

local function truncate(str, maxLen)
    str = tostring(str or '')
    maxLen = maxLen or 200
    if #str <= maxLen then return str end
    return str:sub(1, maxLen) .. '...'
end

local function LogCommand(src, cmd, message, extra)
    if not (DFLogs and DFLogs.Log) then return end
    local action = locale('logs.command.action', tostring(cmd or 'unknown'))
    -- WICHTIG: logs_integration.lua hängt opts.extra automatisch an die Message an.
    -- Für qbx_core Command-Logs wollen wir das NICHT, daher senden wir keine opts.extra.
    pcall(DFLogs.Log, src, action, truncate(message or '-', 300))
end

local function getVehicleModelName(vehicle)
    local modelHash = GetEntityModel(vehicle)
    if not modelHash then return 'unknown' end
    -- Server: GetDisplayNameFromVehicleModel ist client-only.
    -- Versuch, den Namen über qbx_core Vehicle-DB aufzulösen; sonst Hash loggen.
    local ok, v = pcall(function()
        return exports.qbx_core:GetVehiclesByHash(modelHash)
    end)
    if ok and v then
        -- Je nach Vehicle-Definition existiert z.B. model/name.
        local name = v.model or v.name
        if name and name ~= '' then
            return tostring(name):lower()
        end
    end
    return tostring(modelHash)
end

lib.addCommand('tp', {
    help = locale('command.tp.help'),
    params = {
        { name = locale('command.tp.params.x.name'), help = locale('command.tp.params.x.help'), optional = false },
        { name = locale('command.tp.params.y.name'), help = locale('command.tp.params.y.help'), optional = true },
        { name = locale('command.tp.params.z.name'), help = locale('command.tp.params.z.help'), optional = true }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local xArg = args[locale('command.tp.params.x.name')]
    local yArg = args[locale('command.tp.params.y.name')]
    local zArg = args[locale('command.tp.params.z.name')]

    if xArg and not yArg and not zArg then
        local targetId = tonumber(xArg) --[[@as number]]
        local target = GetPlayerPed(targetId)
        if target ~= 0 then
            local coords = GetEntityCoords(target)
            TriggerClientEvent('QBCore:Command:TeleportToPlayer', source, coords)
            LogCommand(source, 'tp', locale('logs.command.tp.to_player', targetId), { targetId = targetId })
        else
            Notify(source, locale('error.not_online'), 'error')
            LogCommand(source, 'tp', locale('logs.command.tp.fail_offline', tostring(targetId)), { targetId = targetId, result = 'not_online' })
        end
    else
        if xArg and yArg and zArg then
            local x = tonumber((xArg:gsub(',',''))) + .0
            local y = tonumber((yArg:gsub(',',''))) + .0
            local z = tonumber((zArg:gsub(',',''))) + .0
            if x ~= 0 and y ~= 0 and z ~= 0 then
                TriggerClientEvent('QBCore:Command:TeleportToCoords', source, x, y, z)
                LogCommand(source, 'tp', locale('logs.command.tp.to_coords', x, y, z), { x = x, y = y, z = z })
            else
                Notify(source, locale('error.wrong_format'), 'error')
                LogCommand(source, 'tp', locale('logs.command.tp.fail_wrong_format'), { x = xArg, y = yArg, z = zArg, result = 'wrong_format' })
            end
        else
            Notify(source, locale('error.missing_args'), 'error')
            LogCommand(source, 'tp', locale('logs.command.tp.fail_missing_args'), { x = xArg, y = yArg, z = zArg, result = 'missing_args' })
        end
    end
end)

lib.addCommand('tpm', {
    help = locale('command.tpm.help'),
    restricted = 'group.admin'
}, function(source)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local coords = lib.callback.await('qbx_core:client:getWaypointCoords', source)
    TriggerClientEvent('QBCore:Command:GoToMarker', source)
    if coords and coords.x and coords.y and coords.z then
        LogCommand(source, 'tpm', locale('logs.command.tpm.marker', coords.x, coords.y, coords.z), nil)
    else
        LogCommand(source, 'tpm', locale('logs.command.tpm.fail_no_waypoint'), nil)
    end
end)

lib.addCommand('togglepvp', {
    help = locale('command.togglepvp.help'),
    restricted = 'group.admin'
}, function(source)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    config.server.pvp = not config.server.pvp
    GlobalState.PVPEnabled = config.server.pvp
    LogCommand(source, 'togglepvp', locale('logs.command.togglepvp.toggled', config.server.pvp and locale('logs.common.on') or locale('logs.common.off')), { enabled = config.server.pvp })
end)

lib.addCommand('addpermission', {
    help = locale('command.addpermission.help'),
    params = {
        { name = locale('command.addpermission.params.id.name'), help = locale('command.addpermission.params.id.help'), type = 'playerId' },
        { name = locale('command.addpermission.params.permission.name'), help = locale('command.addpermission.params.permission.help'), type = 'string' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.addpermission.params.id.name')])
    local permission = args[locale('command.addpermission.params.permission.name')]
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'addpermission', locale('logs.command.addpermission.fail_offline'), { target = args[locale('command.addpermission.params.id.name')], permission = permission, result = 'not_online' })
        return
    end

    ---@diagnostic disable-next-line: deprecated
    AddPermission(player.PlayerData.source, permission)
    LogCommand(source, 'addpermission', locale('logs.command.addpermission.success', player.PlayerData.source, permission), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, permission = permission })
end)

lib.addCommand('removepermission', {
    help = locale('command.removepermission.help'),
    params = {
        { name = locale('command.removepermission.params.id.name'), help = locale('command.removepermission.params.id.help'), type = 'playerId' },
        { name = locale('command.removepermission.params.permission.name'), help = locale('command.removepermission.params.permission.help'), type = 'string' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.removepermission.params.id.name')])
    local permission = args[locale('command.removepermission.params.permission.name')]
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'removepermission', locale('logs.command.removepermission.fail_offline'), { target = args[locale('command.removepermission.params.id.name')], permission = permission, result = 'not_online' })
        return
    end

    ---@diagnostic disable-next-line: deprecated
    RemovePermission(player.PlayerData.source, permission)
    LogCommand(source, 'removepermission', locale('logs.command.removepermission.success', player.PlayerData.source, permission), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, permission = permission })
end)

lib.addCommand('openserver', {
    help = locale('command.openserver.help'),
    restricted = 'group.admin'
}, function(source)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    if not config.server.closed then
        Notify(source, locale('error.server_already_open'), 'error')
        LogCommand(source, 'openserver', locale('logs.command.openserver.fail_already_open'), { result = 'already_open' })
        return
    end

    if IsPlayerAceAllowed(source, 'admin') then
        config.server.closed = false
        Notify(source, locale('success.server_opened'), 'success')
        LogCommand(source, 'openserver', locale('logs.command.openserver.success'), nil)
    else
        LogCommand(source, 'openserver', locale('logs.command.openserver.fail_no_permission'), { result = 'no_permission' })
        DropPlayer(source, locale('error.no_permission'))
    end
end)

lib.addCommand('closeserver', {
    help = locale('command.openserver.help'),
    params = {
        { name = locale('command.closeserver.params.reason.name'), help = locale('command.closeserver.params.reason.help'), type = 'string' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    if config.server.closed then
        Notify(source, locale('error.server_already_closed'), 'error')
        LogCommand(source, 'closeserver', locale('logs.command.closeserver.fail_already_closed'), { result = 'already_closed' })
        return
    end

    if IsPlayerAceAllowed(source, 'admin') then
        local reason = args[locale('command.closeserver.params.reason.name')] or 'No reason specified'
        config.server.closed = true
        config.server.closedReason = reason
        for k in pairs(QBX.Players) do
            if not IsPlayerAceAllowed(k --[[@as string]], config.server.whitelistPermission) then
                DropPlayer(k --[[@as string]], reason)
            end
        end

        Notify(source, locale('success.server_closed'), 'success')
        LogCommand(source, 'closeserver', locale('logs.command.closeserver.success', reason), { reason = reason })
    else
        LogCommand(source, 'closeserver', locale('logs.command.closeserver.fail_no_permission'), { result = 'no_permission' })
        DropPlayer(source, locale('error.no_permission'))
    end
end)

lib.addCommand('car', {
    help = locale('command.car.help'),
    params = {
        { name = locale('command.car.params.model.name'), help = locale('command.car.params.model.help') },
        { name = locale('command.car.params.keepCurrentVehicle.name'), help = locale('command.car.params.keepCurrentVehicle.help'), optional = true },
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    if not args then return end

    local ped, bucket = GetPlayerPed(source), GetPlayerRoutingBucket(source)
    local keepCurrentVehicle = args[locale('command.car.params.keepCurrentVehicle.name')]
    local currentVehicle = not keepCurrentVehicle and GetVehiclePedIsIn(ped, false)
    local deletedCurrent = currentVehicle and currentVehicle ~= 0
    if currentVehicle and currentVehicle ~= 0 then
        DeleteVehicle(currentVehicle)
    end

    local carModel = args[locale('command.car.params.model.name')]
    local _, vehicle = qbx.spawnVehicle({
        model = carModel,
        spawnSource = ped,
        warp = true,
        bucket = bucket
    })

    local plate = qbx.getVehiclePlate(vehicle)
    local keepTxt = keepCurrentVehicle and locale('logs.common.yes') or locale('logs.common.no')
    LogCommand(
        source,
        'car',
        locale('logs.command.car.spawned', tostring(carModel), tostring(plate), keepTxt),
        { model = carModel, plate = plate, keepCurrent = keepCurrentVehicle and true or false, deletedCurrent = deletedCurrent and true or false, bucket = bucket }
    )
    config.giveVehicleKeys(source, plate, vehicle)
end)

lib.addCommand('dv', {
    help = locale('command.dv.help'),
    params = {
        { name = locale('command.dv.params.radius.name'), help = locale('command.dv.params.radius.help'), type = 'number', optional = true }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local ped = GetPlayerPed(source)
    local pedCars = {GetVehiclePedIsIn(ped, false)}
    local radius = args[locale('command.dv.params.radius.name')]

    if pedCars[1] == 0 or radius then -- Only execute when player is not in a vehicle or radius is explicitly defined
        pedCars = lib.callback.await('qbx_core:client:getVehiclesInRadius', source, radius)
    else
        pedCars[1] = NetworkGetNetworkIdFromEntity(pedCars[1])
    end

    if #pedCars ~= 0 then
        local deleted = 0
        local details = {}
        local maxDetails = 5
        for i = 1, #pedCars do
            local pedCar = NetworkGetEntityFromNetworkId(pedCars[i])
            if pedCar and DoesEntityExist(pedCar) then
                if #details < maxDetails then
                    local modelName = getVehicleModelName(pedCar)
                    local plate = qbx.getVehiclePlate(pedCar) or 'unknown'
                    details[#details + 1] = ('Model=%s | Plate=%s'):format(modelName, plate)
                end
                DeleteVehicle(pedCar)
                deleted = deleted + 1
            end
        end
        local detailStr = (#details > 0) and table.concat(details, ' ; ') or '-'
        if deleted > maxDetails then
            detailStr = detailStr .. (' ; +%d more'):format(deleted - maxDetails)
        end
        LogCommand(source, 'dv', locale('logs.command.dv.deleted', detailStr), nil)
    else
        LogCommand(source, 'dv', locale('logs.command.dv.none'), nil)
    end
end)

lib.addCommand('givemoney', {
    help = locale('command.givemoney.help'),
    params = {
        { name = locale('command.givemoney.params.id.name'), help = locale('command.givemoney.params.id.help'), type = 'playerId' },
        { name = locale('command.givemoney.params.moneytype.name'), help = locale('command.givemoney.params.moneytype.help'), type = 'string' },
        { name = locale('command.givemoney.params.amount.name'), help = locale('command.givemoney.params.amount.help'), type = 'number' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.givemoney.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'givemoney', locale('logs.command.givemoney.fail_offline'), { target = args[locale('command.givemoney.params.id.name')], result = 'not_online' })
        return
    end

    local moneyType = args[locale('command.givemoney.params.moneytype.name')]
    local amount = args[locale('command.givemoney.params.amount.name')]
    player.Functions.AddMoney(moneyType, amount)
    LogCommand(source, 'givemoney', locale('logs.command.givemoney.success', tostring(amount), tostring(moneyType), tostring(player.PlayerData.source)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, moneyType = moneyType, amount = amount })
end)

lib.addCommand('setmoney', {
    help = locale('command.setmoney.help'),
    params = {
        { name = locale('command.setmoney.params.id.name'), help = locale('command.setmoney.params.id.help'), type = 'playerId' },
        { name = locale('command.setmoney.params.moneytype.name'), help = locale('command.setmoney.params.moneytype.help'), type = 'string' },
        { name = locale('command.setmoney.params.amount.name'), help = locale('command.setmoney.params.amount.help'), type = 'number' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.setmoney.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'setmoney', locale('logs.command.setmoney.fail_offline'), { target = args[locale('command.setmoney.params.id.name')], result = 'not_online' })
        return
    end

    local moneyType = args[locale('command.setmoney.params.moneytype.name')]
    local amount = args[locale('command.setmoney.params.amount.name')]
    player.Functions.SetMoney(moneyType, amount)
    LogCommand(source, 'setmoney', locale('logs.command.setmoney.success', tostring(amount), tostring(moneyType), tostring(player.PlayerData.source)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, moneyType = moneyType, amount = amount })
end)

lib.addCommand('job', {
    help = locale('command.job.help')
}, function(source)
    local PlayerJob = GetPlayer(source).PlayerData.job
    Notify(source, locale('info.job_info', PlayerJob?.label, PlayerJob?.grade.name, PlayerJob?.onduty))
    LogCommand(source, 'job', locale('logs.command.job.checked', tostring(PlayerJob?.name or PlayerJob?.label), tostring(PlayerJob?.grade?.level or PlayerJob?.grade?.name), tostring(PlayerJob?.onduty)), { job = PlayerJob?.name, grade = PlayerJob?.grade?.level, onduty = PlayerJob?.onduty })
end)

lib.addCommand('setjob', {
    help = locale('command.setjob.help'),
    params = {
        { name = locale('command.setjob.params.id.name'), help = locale('command.setjob.params.id.help'), type = 'playerId' },
        { name = locale('command.setjob.params.job.name'), help = locale('command.setjob.params.job.help'), type = 'string' },
        { name = locale('command.setjob.params.grade.name'), help = locale('command.setjob.params.grade.help'), type = 'number', optional = true }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.setjob.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'setjob', locale('logs.command.setjob.fail_offline'), { target = args[locale('command.setjob.params.id.name')], result = 'not_online' })
        return
    end

    local jobName = args[locale('command.setjob.params.job.name')]
    local grade = args[locale('command.setjob.params.grade.name')] or 0
    local success, errorResult = player.Functions.SetJob(jobName, grade)
    if success then
        LogCommand(source, 'setjob', locale('logs.command.setjob.success', tostring(player.PlayerData.source), tostring(jobName), tostring(grade)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, grade = grade, success = true })
    else
        LogCommand(source, 'setjob', locale('logs.command.setjob.fail', tostring(player.PlayerData.source), tostring(jobName), tostring(grade)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, grade = grade, success = false, error = errorResult })
    end
    assert(success, json.encode(errorResult))
end)

lib.addCommand('changejob', {
    help = locale('command.changejob.help'),
    params = {
        { name = locale('command.changejob.params.id.name'), help = locale('command.changejob.params.id.help'), type = 'playerId' },
        { name = locale('command.changejob.params.job.name'), help = locale('command.changejob.params.job.help'), type = 'string' },
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.changejob.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'changejob', locale('logs.command.changejob.fail_offline'), { target = args[locale('command.changejob.params.id.name')], result = 'not_online' })
        return
    end

    local jobName = args[locale('command.changejob.params.job.name')]
    local success, errorResult = SetPlayerPrimaryJob(player.PlayerData.citizenid, jobName)
    if success then
        LogCommand(source, 'changejob', locale('logs.command.changejob.success', tostring(player.PlayerData.source), tostring(jobName)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, success = true })
    else
        LogCommand(source, 'changejob', locale('logs.command.changejob.fail', tostring(player.PlayerData.source), tostring(jobName)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, success = false, error = errorResult })
    end
    assert(success, json.encode(errorResult))
end)

lib.addCommand('addjob', {
    help = locale('command.addjob.help'),
    params = {
        { name = locale('command.addjob.params.id.name'), help = locale('command.addjob.params.id.help'), type = 'playerId' },
        { name = locale('command.addjob.params.job.name'), help = locale('command.addjob.params.job.help'), type = 'string' },
        { name = locale('command.addjob.params.grade.name'), help = locale('command.addjob.params.grade.help'), type = 'number', optional = true}
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.addjob.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'addjob', locale('logs.command.addjob.fail_offline'), { target = args[locale('command.addjob.params.id.name')], result = 'not_online' })
        return
    end

    local jobName = args[locale('command.addjob.params.job.name')]
    local grade = args[locale('command.addjob.params.grade.name')] or 0
    local success, errorResult = AddPlayerToJob(player.PlayerData.citizenid, jobName, grade)
    if success then
        LogCommand(source, 'addjob', locale('logs.command.addjob.success', tostring(player.PlayerData.source), tostring(jobName), tostring(grade)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, grade = grade, success = true })
    else
        LogCommand(source, 'addjob', locale('logs.command.addjob.fail', tostring(player.PlayerData.source), tostring(jobName), tostring(grade)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, grade = grade, success = false, error = errorResult })
    end
    assert(success, json.encode(errorResult))
end)

lib.addCommand('removejob', {
    help = locale('command.removejob.help'),
    params = {
        { name = locale('command.removejob.params.id.name'), help = locale('command.removejob.params.id.help'), type = 'playerId' },
        { name = locale('command.removejob.params.job.name'), help = locale('command.removejob.params.job.help'), type = 'string' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.removejob.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'removejob', locale('logs.command.removejob.fail_offline'), { target = args[locale('command.removejob.params.id.name')], result = 'not_online' })
        return
    end

    local jobName = args[locale('command.removejob.params.job.name')]
    local success, errorResult = RemovePlayerFromJob(player.PlayerData.citizenid, jobName)
    if success then
        LogCommand(source, 'removejob', locale('logs.command.removejob.success', tostring(player.PlayerData.source), tostring(jobName)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, success = true })
    else
        LogCommand(source, 'removejob', locale('logs.command.removejob.fail', tostring(player.PlayerData.source), tostring(jobName)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, job = jobName, success = false, error = errorResult })
    end
    assert(success, json.encode(errorResult))
end)

lib.addCommand('gang', {
    help = locale('command.gang.help')
}, function(source)
    local PlayerGang = GetPlayer(source).PlayerData.gang
    Notify(source, locale('info.gang_info', PlayerGang?.label, PlayerGang?.grade.name))
    LogCommand(source, 'gang', locale('logs.command.gang.checked', tostring(PlayerGang?.name or PlayerGang?.label), tostring(PlayerGang?.grade?.level or PlayerGang?.grade?.name)), { gang = PlayerGang?.name, grade = PlayerGang?.grade?.level })
end)

lib.addCommand('setgang', {
    help = locale('command.setgang.help'),
    params = {
        { name = locale('command.setgang.params.id.name'), help = locale('command.setgang.params.id.help'), type = 'playerId' },
        { name = locale('command.setgang.params.gang.name'), help = locale('command.setgang.params.gang.help'), type = 'string' },
        { name = locale('command.setgang.params.grade.name'), help = locale('command.setgang.params.grade.help'), type = 'number', optional = true }
    },
    restricted = 'group.admin'
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args[locale('command.setgang.params.id.name')])
    if not player then
        Notify(source, locale('error.not_online'), 'error')
        LogCommand(source, 'setgang', locale('logs.command.setgang.fail_offline'), { target = args[locale('command.setgang.params.id.name')], result = 'not_online' })
        return
    end

    local gangName = args[locale('command.setgang.params.gang.name')]
    local grade = args[locale('command.setgang.params.grade.name')] or 0
    local success, errorResult = player.Functions.SetGang(gangName, grade)
    if success then
        LogCommand(source, 'setgang', locale('logs.command.setgang.success', tostring(player.PlayerData.source), tostring(gangName), tostring(grade)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, gang = gangName, grade = grade, success = true })
    else
        LogCommand(source, 'setgang', locale('logs.command.setgang.fail', tostring(player.PlayerData.source), tostring(gangName), tostring(grade)), { target = player.PlayerData.source, citizenid = player.PlayerData.citizenid, gang = gangName, grade = grade, success = false, error = errorResult })
    end
    assert(success, json.encode(errorResult))
end)

lib.addCommand('ooc', {
    help = locale('command.ooc.help')
}, function(source, args)
    local message = table.concat(args, ' ')
    local players = GetPlayers()
    local player = GetPlayer(source)
    if not player then return end
    LogCommand(source, 'ooc', locale('logs.command.ooc.message', message), { message = truncate(message, 250) })

    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    for _, v in pairs(players) do
        if v == source then
            exports.chat:addMessage(v --[[@as Source]], {
                color = { 0, 0, 255},
                multiline = true,
                args = {('OOC | %s'):format(GetPlayerName(source)), message}
            })
        elseif #(playerCoords - GetEntityCoords(GetPlayerPed(v))) < 20.0 then
            exports.chat:addMessage(v --[[@as Source]], {
                color = { 0, 0, 255},
                multiline = true,
                args = {('OOC | %s'):format(GetPlayerName(source)), message}
            })
        elseif IsPlayerAceAllowed(v --[[@as string]], 'admin') then
            if IsOptin(v --[[@as Source]]) then
                exports.chat:addMessage(v--[[@as Source]], {
                    color = { 0, 0, 255},
                    multiline = true,
                    args = {('Proximity OOC | %s'):format(GetPlayerName(source)), message}
                })
                logger.log({
                    source = 'qbx_core',
                    webhook  = 'ooc',
                    event = 'OOC',
                    color = 'white',
                    tags = config.logging.role,
                    message = ('**%s** (CitizenID: %s | ID: %s) **Message:** %s'):format(GetPlayerName(source), player.PlayerData.citizenid, source, message)
                })
            end
        end
    end
end)

lib.addCommand('me', {
    help = locale('command.me.help'),
    params = {
        { name = locale('command.me.params.message.name'), help = locale('command.me.params.message.help'), type = 'string' }
    }
}, function(source, args)
    args[1] = args[locale('command.me.params.message.name')]
    args[locale('command.me.params.message.name')] = nil
    if #args < 1 then Notify(source, locale('error.missing_args2'), 'error') return end
    local msg = table.concat(args, ' '):gsub('[~<].-[>~]', '')
    LogCommand(source, 'me', locale('logs.command.me.message', msg), { message = truncate(msg, 250) })
    local playerState = Player(source).state
    playerState:set('me', msg, true)

    -- We have to reset the playerState since the state does not get replicated on StateBagHandler if the value is the same as the previous one --
    playerState:set('me', nil, true)
end)

lib.addCommand('id', {help = locale('info.check_id')}, function(source)
    Notify(source, 'ID: ' .. source)
    LogCommand(source, 'id', locale('logs.command.id.checked', tostring(source)), nil)
end)

lib.addCommand('logout', {
    help = locale('info.logout_command_help'),
    restricted = 'group.admin',
}, function(source)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end
    LogCommand(source, 'logout', locale('logs.command.logout.executed'), nil)
    Logout(source)
end)

lib.addCommand('deletechar', {
    help = locale('info.deletechar_command_help'),
    restricted = 'group.admin',
    params = {
        { name = 'id', help = locale('info.deletechar_command_arg_player_id'), type = 'number' },
    }
}, function(source, args)
    if not IsOptin(source) then Notify(source, locale('error.not_optin'), 'error') return end

    local player = GetPlayer(args.id)
    if not player then return end

    local citizenId = player.PlayerData.citizenid
    ForceDeleteCharacter(citizenId)
    Notify(source, locale('success.character_deleted_citizenid', citizenId))
    LogCommand(source, 'deletechar', locale('logs.command.deletechar.executed', tostring(player.PlayerData.source), tostring(citizenId)), { target = player.PlayerData.source, citizenid = citizenId })
end)

lib.addCommand('optin', {
    help = locale('command.optin.help'),
    restricted = 'group.admin'
}, function(source, args)
    ToggleOptin(source)
    local state = IsOptin(source) and 'in' or 'out'
    Notify(source, locale('success.optin_set', state))
    LogCommand(source, 'optin', locale('logs.command.optin.changed', locale('logs.common.' .. state)), { optin = state })
end)