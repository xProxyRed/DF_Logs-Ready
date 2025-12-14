-- logs_integration.lua
-- Standalone Helper für DF_Logs (zum Kopieren in andere Resources)
--
-- Ziel:
--  - Minimaler Code im eigentlichen Script
--  - Automatisch: Framework-Erkennung (ESX / QBCore / qbx_core), RP-Name, Resource-Name, Coords
--  - Einfache API: DFLogs.Log(action, message, opts)
--
-- Nutzung (Server):
--  1) Datei in deine Resource legen (z.B. resources/mein_script/logs_integration.lua)
--  2) In fxmanifest.lua eintragen (server_script):
--     server_scripts {
--       'logs_integration.lua',
--       'server/*.lua'
--     }
--  3) Im Code:
--     DFLogs.Log("my_action", "my message")
--     -- oder (wenn du source explizit mitgeben willst):
--     DFLogs.Log(source, "my_action", "my message")

DFLogs = DFLogs or {}

-- Wichtig:
-- - DF_Logs Export existiert NUR serverseitig.
-- - Wenn du DFLogs.Log(...) im Client nutzt, muss diese Datei auch serverseitig in der gleichen Resource geladen sein.
-- - Wir nutzen einen pro-Resource Eventnamen, damit es keine doppelten Logs gibt.
local EVENT_NAME = ("DFLogs:integration:log:%s"):format(GetCurrentResourceName())

-- =========================
-- CLIENT IMPLEMENTATION
-- =========================
if not IsDuplicityVersion() then
    -- Client: sammelt keine Framework-Daten (RP-Name/Coords) – das macht der Server sauber.
    -- API:
    --   DFLogs.Log("action", "message", opts?)
    -- opts:
    --   extra (table) - wird in message auf dem Server angehängt
    --   coords (vector3) - optional (wenn du client coords mitschicken willst)
    function DFLogs.Log(action, message, opts)
        opts = opts or {}
        TriggerServerEvent(EVENT_NAME, tostring(action or "Unknown"), tostring(message or "-"), opts)
        return true, true
    end

    -- Optionaler Alias:
    DFLog = DFLog or DFLogs.Log

    return DFLogs
end

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function hasResource(name)
    return GetResourceState(name) == "started" or GetResourceState(name) == "starting"
end

local function getInvokingOrCurrentResource()
    local inv = safeCall(GetInvokingResource)
    if inv and inv ~= "" then return inv end
    return GetCurrentResourceName()
end

local function getCoords(src)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        return c -- vector3
    end
    return nil
end

-- Framework: ESX
local function getESXPlayerName(src)
    -- es_extended (exports) (neuere Versionen)
    if hasResource("es_extended") then
        local ESX = safeCall(function()
            return exports["es_extended"]:getSharedObject()
        end)
        if ESX and ESX.GetPlayerFromId then
            local xPlayer = safeCall(ESX.GetPlayerFromId, src)
            if xPlayer then
                -- Je nach ESX Version
                local name = safeCall(function()
                    if xPlayer.getName then return xPlayer.getName() end
                    if xPlayer.get and xPlayer.get("name") then return xPlayer.get("name") end
                    if xPlayer.name then return xPlayer.name end
                    return nil
                end)
                if name and name ~= "" then return name end
            end
        end
    end
    return nil
end

-- Framework: QBCore
local function getQBCorePlayerName(src)
    if hasResource("qb-core") then
        local QBCore = safeCall(function()
            return exports["qb-core"]:GetCoreObject()
        end)
        if QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
            local player = safeCall(QBCore.Functions.GetPlayer, src)
            if player and player.PlayerData then
                local ci = player.PlayerData.charinfo or {}
                local first = ci.firstname or ci.firstName or ci.first_name
                local last = ci.lastname or ci.lastName or ci.last_name
                local full = (first or "") .. (first and last and " " or "") .. (last or "")
                full = full:gsub("^%s+", ""):gsub("%s+$", "")
                if full ~= "" then return full end
            end
        end
    end
    return nil
end

-- Framework: qbx_core (Qbox)
local function getQboxPlayerName(src)
    if hasResource("qbx_core") then
        -- qbx_core hat je nach Version unterschiedliche APIs – wir versuchen mehrere
        local player = safeCall(function()
            return exports["qbx_core"]:GetPlayer(src)
        end)
        if not player then
            player = safeCall(function()
                return exports["qbx_core"]:GetPlayerById(src)
            end)
        end

        if player then
            -- Häufig: player.PlayerData.charinfo
            local pd = player.PlayerData or player.playerData or player
            local ci = (pd and pd.charinfo) or (pd and pd.CharInfo) or {}
            local first = ci.firstname or ci.firstName or ci.first_name
            local last = ci.lastname or ci.lastName or ci.last_name
            local full = (first or "") .. (first and last and " " or "") .. (last or "")
            full = full:gsub("^%s+", ""):gsub("%s+$", "")
            if full ~= "" then return full end

            -- Fallback: name Feld
            local n = pd and (pd.name or pd.Name)
            if n and n ~= "" then return n end
        end
    end
    return nil
end

local function getRPName(src)
    return getQboxPlayerName(src)
        or getQBCorePlayerName(src)
        or getESXPlayerName(src)
        or GetPlayerName(src)
        or ("Player#" .. tostring(src))
end

local function ensureDFLogsAvailable()
    if not hasResource("DF_Logs") then
        return false, "DF_Logs resource is not started"
    end
    if not exports or not exports["DF_Logs"] or not exports["DF_Logs"].log then
        return false, "DF_Logs export not available"
    end
    return true, nil
end

-- Baut die Standard-Payload für DF_Logs
-- opts:
--  - resource (string): überschreibt resourceName
--  - coords (vector3): überschreibt Coords
--  - player (string): überschreibt player name
--  - source (number): optional; falls nicht gesetzt wird automatisch die globale 'source' genutzt (Event-Context)
--  - extra (table): beliebige Zusatzfelder (z.B. item, amount, plate etc.) -> wird als Text in message angehängt
local function buildPayload(src, action, message, opts)
    opts = opts or {}
    local resName = opts.resource or getInvokingOrCurrentResource()

    -- Wenn kein Player-Source vorhanden ist (z.B. Script/Export), können wir optional trotzdem loggen.
    local hasPlayer = type(src) == "number" and src > 0
    local rpName = opts.player
        or (hasPlayer and getRPName(src) or nil)
        or (not hasPlayer and (resName and ("SYSTEM@" .. tostring(resName)) or "SYSTEM") or nil)
        or "Unknown"

    local coords = opts.coords or (hasPlayer and getCoords(src) or nil)

    local msg = tostring(message or "")
    if msg == "" then msg = "-" end

    -- Optionale Extra-Infos ans Message-Ende hängen (kurz & lesbar)
    if opts.extra and type(opts.extra) == "table" then
        local parts = {}
        for k, v in pairs(opts.extra) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        end
        table.sort(parts)
        if #parts > 0 then
            msg = msg .. " | " .. table.concat(parts, " | ")
        end
    end


    local displayPlayer = tostring(rpName or "Unknown")

    return {
        player = displayPlayer,
        action = tostring(action or "Unknown"),
        message = msg,
        coords = coords, -- DF_Logs kann vector3 verarbeiten; falls nicht, wird es ignoriert
        resource = resName
    }
end

-- Public API (eine Funktion, zwei Aufruf-Varianten)
-- 1) In Player-Events (source ist global verfügbar):
--    DFLogs.Log("action", "message", opts?)
-- 2) Wenn du source explizit mitgeben willst:
--    DFLogs.Log(source, "action", "message", opts?)
function DFLogs.Log(a, b, c, d)
    local src, action, message, opts

    if type(a) == "number" then
        -- DFLogs.Log(source, action, message, opts?)
        src = tonumber(a)
        action = b
        message = c
        opts = d or {}
        opts.source = opts.source or src
    else
        -- DFLogs.Log(action, message, opts?)
        action = a
        message = b
        opts = c or {}
    end

    local ok, err = ensureDFLogsAvailable()
    if not ok then return false, err end

    src = tonumber(opts.source)
    if not src then
        -- In Server-Event-Handlern ist 'source' i.d.R. global verfügbar
        src = tonumber(rawget(_G, "source"))
    end

    -- Standard: ohne Player-Source nicht loggen (damit Logs nicht "anonym" sind).
    -- Ausnahme: opts.allowNoSource = true (für Script/Export Logs).
    if not src or src <= 0 then
        if not opts.allowNoSource then
            return false, "Missing player source (call DFLogs.Log inside a player event, or pass source explicitly)"
        end
        src = 0
    end

    local payload = buildPayload(src, action, message, opts)
    exports["DF_Logs"]:log(payload)
    return true, payload
end

-- Optionaler Alias (noch kürzer im Script):
-- DFLog("action", "message")
DFLog = DFLog or DFLogs.Log

-- Bridge: Client -> Server (pro Resource, damit kein globales Doppel-Logging passiert)
RegisterNetEvent(EVENT_NAME, function(action, message, opts)
    if type(opts) ~= "table" then opts = {} end
    -- source ist hier IMMER der Spieler, der den Client-Event ausgelöst hat
    DFLogs.Log(source, action, message, opts)
end)

return DFLogs


