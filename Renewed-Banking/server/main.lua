local cachedAccounts = {}
local cachedPlayers = {}

-- =========================
-- Logging (DF_Logs bridge via logs_integration.lua)
-- =========================
local function formatLogAction(action)
    local a = tostring(action or "Unknown")
    -- bank_transfer -> Transfer, bank_account_add -> Account Add, etc.
    if a:sub(1, 5) == "bank_" then
        a = a:sub(6)
    end
    a = a:gsub("_+", " ")
    -- Title Case
    a = a:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return a
end

local function BankLog(src, action, message, extra, opts)
    if not DFLogs or not DFLogs.Log then return end
    opts = opts or {}
    opts.extra = extra

    -- If called outside a player event (e.g. exports), ONLY log when another resource invoked us.
    -- This prevents noisy "SYSTEM@Renewed-Banking" logs for internal balance changes.
    if type(src) ~= "number" or src <= 0 then
        local inv = GetInvokingResource()
        if not inv or inv == "" then
            return
        end
        opts.allowNoSource = true
        opts.source = 0
        opts.resource = opts.resource or inv
        opts.player = opts.player or ("RESOURCE@" .. inv)
        DFLogs.Log(formatLogAction(action), tostring(message or "-"), opts)
        return
    end

    DFLogs.Log(src, formatLogAction(action), tostring(message or "-"), opts)
end

CreateThread(function()
    Wait(500)
    if not LoadResourceFile("Renewed-Banking", 'web/public/build/bundle.js') or GetCurrentResourceName() ~= "Renewed-Banking" then
        error(locale("ui_not_built"))
        return StopResource("Renewed-Banking")
    end
    local accounts = MySQL.query.await('SELECT * FROM bank_accounts_new', {})
    if accounts then
        for _,v in pairs (accounts) do
            local job = v.id
            v.auth = json.decode(v.auth)
            cachedAccounts[job] = { --  cachedAccounts[#cachedAccounts+1]
                id = job,
                type = locale("org"),
                name = GetSocietyLabel(job),
                frozen = v.isFrozen == 1,
                amount = v.amount,
                transactions = json.decode(v.transactions),
                auth = {},
                creator = v.creator
            }
            if #v.auth >= 1 then
                for k=1, #v.auth do
                    cachedAccounts[job].auth[v.auth[k]] = true
                end
            end
        end
    end
    local jobs, gangs = GetFrameworkGroups()
    local query = {}
    local function addCachedAccount(group)
        cachedAccounts[group] = {
            id = group,
            type = locale('org'),
            name = GetSocietyLabel(group),
            frozen = 0,
            amount = 0,
            transactions = {},
            auth = {},
            creator = nil
        }
        query[#query + 1] = {"INSERT INTO bank_accounts_new (id, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, NULL) ",
        { group, cachedAccounts[group].amount, json.encode(cachedAccounts[group].transactions), json.encode({}), cachedAccounts[group].frozen }}
    end
    for job in pairs(jobs) do
        if not cachedAccounts[job] then
            addCachedAccount(job)
        end
    end
    for gang in pairs(gangs) do
        if not cachedAccounts[gang] then
            addCachedAccount(gang)
        end
    end
    if #query >= 1 then
        MySQL.transaction.await(query)
    end
end)

function UpdatePlayerAccount(cid)
    local p = promise.new()
    MySQL.query('SELECT * FROM player_transactions WHERE id = ?', {cid}, function(account)
        local query = '%' .. cid .. '%'
        MySQL.query("SELECT * FROM bank_accounts_new WHERE auth LIKE ? ", {query}, function(shared)
            cachedPlayers[cid] = {
                isFrozen = 0,
                transactions = #account > 0 and json.decode(account[1].transactions) or {},
                accounts = {}
            }

            if #shared >= 1 then
                for k=1, #shared do
                    cachedPlayers[cid].accounts[#cachedPlayers[cid].accounts+1] = shared[k].id
                end
            end
            p:resolve(true)
        end)
    end)
	return Citizen.Await(p)
end

local function getBankData(source)
    local Player = GetPlayerObject(source)
    local bankData = {}
    local cid = GetIdentifier(Player)
    if not cachedPlayers[cid] then UpdatePlayerAccount(cid) end
    local funds = GetFunds(Player)
    bankData[#bankData+1] = {
        id = cid,
        type = locale("personal"),
        name = GetCharacterName(Player),
        frozen = cachedPlayers[cid].isFrozen,
        amount = funds.bank,
        cash = funds.cash,
        transactions = cachedPlayers[cid].transactions,
    }

    local jobs = GetJobs(Player)
    if #jobs > 0 then
        for k=1, #jobs do
            if cachedAccounts[jobs[k].name] and IsJobAuth(jobs[k].name, jobs[k].grade) then
                bankData[#bankData+1] = cachedAccounts[jobs[k].name]
            end
        end
    else
        local job = cachedAccounts[jobs.name]
        if job and IsJobAuth(jobs.name, jobs.grade) then
            bankData[#bankData+1] = job
        end
    end

    local gang = GetGang(Player)
    if gang and gang ~= 'none' then
        local gangData = cachedAccounts[gang]
        if gangData and IsGangAuth(Player, gang) then
            bankData[#bankData+1] = gangData
        end
    end

    local sharedAccounts = cachedPlayers[cid].accounts
    for k=1, #sharedAccounts do
        local sAccount = cachedAccounts[sharedAccounts[k]]
        bankData[#bankData+1] = sAccount
    end

    return bankData
end

lib.callback.register('renewed-banking:server:initalizeBanking', function(source)
    local bankData = getBankData(source)
    return bankData
end)

-- Events
local function genTransactionID()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local function sanitizeMessage(message)
    if type(message) ~= "string" then
        message = tostring(message)
    end
    message = message:gsub("'", "''"):gsub("\\", "\\\\")
    return message
end

local Type = type
local function handleTransaction(account, title, amount, message, issuer, receiver, transType, transID)
    if not account or Type(account) ~= 'string' then return print(locale("err_trans_account", account)) end
    if not title or Type(title) ~= 'string' then return print(locale("err_trans_title", title)) end
    if not amount or Type(amount) ~= 'number' then return print(locale("err_trans_amount", amount)) end
    if not message or Type(message) ~= 'string' then return print(locale("err_trans_message", message)) end
    if not issuer or Type(issuer) ~= 'string' then return print(locale("err_trans_issuer", issuer)) end
    if not receiver or Type(receiver) ~= 'string' then return print(locale("err_trans_receiver", receiver)) end
    if not transType or Type(transType) ~= 'string' then return print(locale("err_trans_type", transType)) end
    if transID and Type(transID) ~= 'string' then return print(locale("err_trans_transID", transID)) end

    local transaction = {
        trans_id = transID or genTransactionID(),
        title = title,
        amount = amount,
        trans_type = transType,
        receiver = receiver,
        message = sanitizeMessage(message),
        issuer = issuer,
        time = os.time()
    }
    -- Best-effort audit log
    BankLog(nil, "bank_transaction", locale("log_transaction_written"), {
        trans_id = transaction.trans_id,
        account = account,
        title = title,
        amount = amount,
        trans_type = transType,
        issuer = issuer,
        receiver = receiver
    })
    if cachedAccounts[account] then
        table.insert(cachedAccounts[account].transactions, 1, transaction)
        local transactions = json.encode(cachedAccounts[account].transactions)
        MySQL.prepare("INSERT INTO bank_accounts_new (id, transactions) VALUES (?, ?) ON DUPLICATE KEY UPDATE transactions = ?",{
            account, transactions, transactions
        })
    elseif cachedPlayers[account] then
        table.insert(cachedPlayers[account].transactions, 1, transaction)
        local transactions = json.encode(cachedPlayers[account].transactions)
        MySQL.prepare("INSERT INTO player_transactions (id, transactions) VALUES (?, ?) ON DUPLICATE KEY UPDATE transactions = ?", {
            account, transactions, transactions
        })
    else
        print(locale("invalid_account", account))
    end
    return transaction
end exports("handleTransaction", handleTransaction)

function GetAccountMoney(account)
    if not cachedAccounts[account] then
        locale("invalid_account", account)
        return false
    end
    return cachedAccounts[account].amount
end
exports('getAccountMoney', GetAccountMoney)

local function updateBalance(account)
    MySQL.prepare("UPDATE bank_accounts_new SET amount = ? WHERE id = ?",{ cachedAccounts[account].amount, account })
end

function AddAccountMoney(account, amount)
    if not cachedAccounts[account] then
        locale("invalid_account", account)
        BankLog(nil, "bank_account_add_failed", locale("log_invalid_account", account), { account = account, amount = amount })
        return false
    end
    cachedAccounts[account].amount += amount
    updateBalance(account)
    BankLog(nil, "bank_account_add", locale("log_success"), { account = account, amount = amount, new_balance = cachedAccounts[account].amount })
    return true
end
exports('addAccountMoney', AddAccountMoney)

local function getPlayerData(source, id)
    local Player = source and GetPlayerObject(source)
    if not Player then Player = GetPlayerObjectFromID(id) end
    if not Player then
        local msg = ("Cannot Find Account(%s)"):format(id)
        print(locale("invalid_account", id))
        if source then
            Notify(source, {title = locale("bank_name"), description = msg, type = "error"})
        end
    end
    return Player
end

lib.callback.register('Renewed-Banking:server:deposit', function(source, data)
    local Player = GetPlayerObject(source)
    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        Notify(source, {title = locale("bank_name"), description = locale("invalid_amount", "deposit"), type = "error"})
        BankLog(source, "bank_deposit_failed", locale("invalid_amount", locale("action_deposit")), { amount = data.amount, fromAccount = data.fromAccount })
        return false
    end
    local name = GetCharacterName(Player)
    -- Only log 'note' when player explicitly provided it (don't log the autogenerated default comment).
    local defaultComment = locale("comp_transaction", name, locale("action_deposit_past"), amount)
    local rawComment = type(data.comment) == "string" and data.comment or ""
    local note = (rawComment ~= "" and rawComment ~= defaultComment) and rawComment or nil
    data.comment = note and sanitizeMessage(rawComment) or defaultComment
    if RemoveMoney(Player, amount, 'cash', data.comment) then
        if cachedAccounts[data.fromAccount] then
            AddAccountMoney(data.fromAccount, amount)
        else
            AddMoney(Player, amount, 'bank', data.comment)
        end
        local Player2 = getPlayerData(source, data.fromAccount)
        Player2 = Player2 and GetCharacterName(Player2) or data.fromAccount
        local transaction = handleTransaction(data.fromAccount, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, Player2, "deposit")
        -- Message bewusst leer: DF_Logs zeigt dann nur die Extra-Felder an (siehe logs_integration.lua)
        BankLog(source, "bank_deposit", "", {
            note = note,
            trans_id = transaction and transaction.trans_id,
            amount = amount,
            toAccount = data.fromAccount
        })
        local bankData = getBankData(source)
        return bankData
    else
        TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("not_enough_money"))
        BankLog(source, "bank_deposit_failed", locale("not_enough_money"), { amount = amount, fromAccount = data.fromAccount })
        return false
    end
end)

function RemoveAccountMoney(account, amount)
    if not cachedAccounts[account] then
        print(locale("invalid_account", account))
        BankLog(nil, "bank_account_remove_failed", locale("log_invalid_account", account), { account = account, amount = amount })
        return false
    end
    if cachedAccounts[account].amount < amount then
        print(locale("broke_account", account, amount))
        BankLog(nil, "bank_account_remove_failed", locale("log_insufficient_funds"), { account = account, amount = amount, balance = cachedAccounts[account].amount })
        return false
    end

    cachedAccounts[account].amount -= amount
    updateBalance(account)
    BankLog(nil, "bank_account_remove", locale("log_success"), { account = account, amount = amount, new_balance = cachedAccounts[account].amount })
    return true
end
exports('removeAccountMoney', RemoveAccountMoney)

lib.callback.register('Renewed-Banking:server:withdraw', function(source, data)
    local Player = GetPlayerObject(source)
    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        Notify(source, {title = locale("bank_name"), description = locale("invalid_amount", "withdraw"), type = "error"})
        BankLog(source, "bank_withdraw_failed", locale("invalid_amount", locale("action_withdraw")), { amount = data.amount, fromAccount = data.fromAccount })
        return false
    end
    local name = GetCharacterName(Player)
    local funds = GetFunds(Player)
    -- Only log 'note' when player explicitly provided it (don't log the autogenerated default comment).
    local defaultComment = locale("comp_transaction", name, locale("action_withdraw_past"), amount)
    local rawComment = type(data.comment) == "string" and data.comment or ""
    local note = (rawComment ~= "" and rawComment ~= defaultComment) and rawComment or nil
    data.comment = note and sanitizeMessage(rawComment) or defaultComment

    local canWithdraw
    if cachedAccounts[data.fromAccount] then
        canWithdraw = RemoveAccountMoney(data.fromAccount, amount)
    else
        canWithdraw = funds.bank >= amount and RemoveMoney(Player, amount, 'bank', data.comment) or false
    end
    if canWithdraw then
        local Player2 = getPlayerData(source, data.fromAccount)
        Player2 = Player2 and GetCharacterName(Player2) or data.fromAccount
        AddMoney(Player, amount, 'cash', data.comment)
        local transaction = handleTransaction(data.fromAccount,locale("personal_acc") .. data.fromAccount, amount, data.comment, Player2, name, "withdraw")
        -- Message bewusst leer: DF_Logs zeigt dann nur die Extra-Felder an (siehe logs_integration.lua)
        BankLog(source, "bank_withdraw", "", {
            note = note,
            trans_id = transaction and transaction.trans_id,
            amount = amount,
            fromAccount = data.fromAccount
        })
        local bankData = getBankData(source)
        return bankData
    else
        TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("not_enough_money"))
        BankLog(source, "bank_withdraw_failed", locale("not_enough_money"), { amount = amount, fromAccount = data.fromAccount })
        return false
    end
end)

lib.callback.register('Renewed-Banking:server:transfer', function(source, data)
    local Player = GetPlayerObject(source)
    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        Notify(source, {title = locale("bank_name"), description = locale("invalid_amount", "transfer"), type = "error"})
        BankLog(source, "bank_transfer_failed", locale("invalid_amount", locale("action_transfer")), { amount = data.amount, fromAccount = data.fromAccount, to = data.stateid })
        return false
    end
    local name = GetCharacterName(Player)
    -- Only log 'note' when player explicitly provided it (don't log the autogenerated default comment).
    local defaultComment = locale("comp_transaction", name, locale("action_transfer_past"), amount)
    local rawComment = type(data.comment) == "string" and data.comment or ""
    local note = (rawComment ~= "" and rawComment ~= defaultComment) and rawComment or nil
    data.comment = note and sanitizeMessage(rawComment) or defaultComment
    if cachedAccounts[data.fromAccount] then
        if cachedAccounts[data.stateid] then
            local canTransfer = RemoveAccountMoney(data.fromAccount, amount)
            if canTransfer then
                AddAccountMoney(data.stateid, amount)
                local title = ("%s / %s"):format(cachedAccounts[data.fromAccount].name, data.fromAccount)
                local transaction = handleTransaction(data.fromAccount, title, amount, data.comment, cachedAccounts[data.fromAccount].name, cachedAccounts[data.stateid].name, "withdraw")
                handleTransaction(data.stateid, title, amount, data.comment, cachedAccounts[data.fromAccount].name, cachedAccounts[data.stateid].name, "deposit", transaction.trans_id)
                BankLog(source, "bank_transfer", locale("log_route", cachedAccounts[data.fromAccount].name, cachedAccounts[data.stateid].name), {
                    trans_id = transaction.trans_id,
                    amount = amount,
                    fromAccount = data.fromAccount,
                    toAccount = data.stateid,
                    note = note
                })
            else
                TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("not_enough_money"))
                BankLog(source, "bank_transfer_failed", locale("not_enough_money"), { amount = amount, fromAccount = data.fromAccount, to = data.stateid })
                return false
            end
        else
            local Player2 = getPlayerData(source, data.stateid)
            if not Player2 then
                TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("fail_transfer"))
                BankLog(source, "bank_transfer_failed", locale("fail_transfer"), { amount = amount, fromAccount = data.fromAccount, to = data.stateid })
                return false
            end
            local canTransfer = RemoveAccountMoney(data.fromAccount, amount)
            if canTransfer then
                AddMoney(Player2, amount, 'bank', data.comment)
                local plyName = GetCharacterName(Player2)
                local transaction = handleTransaction(data.fromAccount, ("%s / %s"):format(cachedAccounts[data.fromAccount].name, data.fromAccount), amount, data.comment, cachedAccounts[data.fromAccount].name, plyName, "withdraw")
                handleTransaction(data.stateid, ("%s / %s"):format(cachedAccounts[data.fromAccount].name, data.fromAccount), amount, data.comment, cachedAccounts[data.fromAccount].name, plyName, "deposit", transaction.trans_id)
                BankLog(source, "bank_transfer", locale("log_route", cachedAccounts[data.fromAccount].name, plyName), {
                    trans_id = transaction.trans_id,
                    amount = amount,
                    fromAccount = data.fromAccount,
                    toAccount = data.stateid,
                    note = note
                })
            else
                TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("not_enough_money"))
                BankLog(source, "bank_transfer_failed", locale("not_enough_money"), { amount = amount, fromAccount = data.fromAccount, to = data.stateid })
                return false
            end
        end
    else
        local funds = GetFunds(Player)
        if cachedAccounts[data.stateid] then
            if funds.bank >= amount and RemoveMoney(Player, amount, 'bank', data.comment) then
                AddAccountMoney(data.stateid, amount)
                local transaction = handleTransaction(data.fromAccount, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, cachedAccounts[data.stateid].name, "withdraw")
                handleTransaction(data.stateid, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, cachedAccounts[data.stateid].name, "deposit", transaction.trans_id)
                BankLog(source, "bank_transfer", locale("log_route", name, cachedAccounts[data.stateid].name), {
                    trans_id = transaction.trans_id,
                    amount = amount,
                    fromAccount = data.fromAccount,
                    toAccount = data.stateid,
                    note = note
                })
            else
                TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("not_enough_money"))
                BankLog(source, "bank_transfer_failed", locale("not_enough_money"), { amount = amount, fromAccount = data.fromAccount, to = data.stateid })
                return false
            end
        else
            local Player2 = getPlayerData(source, data.stateid)
            if not Player2 then
                TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("fail_transfer"))
                BankLog(source, "bank_transfer_failed", locale("fail_transfer"), { amount = amount, fromAccount = data.fromAccount, to = data.stateid })
                return false
            end

            if funds.bank >= amount and RemoveMoney(Player, amount, 'bank', data.comment) then
                AddMoney(Player2, amount, 'bank', data.comment)
                local name2 = GetCharacterName(Player2)
                local transaction = handleTransaction(data.fromAccount, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, name2, "withdraw")
                handleTransaction(data.stateid, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, name2, "deposit", transaction.trans_id)
                BankLog(source, "bank_transfer", locale("log_route", name, name2), {
                    trans_id = transaction.trans_id,
                    amount = amount,
                    fromAccount = data.fromAccount,
                    toAccount = data.stateid,
                    note = note
                })
            else
                TriggerClientEvent('Renewed-Banking:client:sendNotification', source, locale("not_enough_money"))
                BankLog(source, "bank_transfer_failed", locale("not_enough_money"), { amount = amount, fromAccount = data.fromAccount, to = data.stateid })
                return false
            end
        end
    end
    local bankData = getBankData(source)
    return bankData
end)

RegisterNetEvent('Renewed-Banking:server:createNewAccount', function(accountid)
    local Player = GetPlayerObject(source)
    if cachedAccounts[accountid] then return Notify(source, {title = locale("bank_name"), description = locale("account_taken"), type = "error"}) end
    local cid = GetIdentifier(Player)
    cachedAccounts[accountid] = {
        id = accountid,
        type = locale("org"),
        name = accountid,
        frozen = 0,
        amount = 0,
        transactions = {},
        auth = { [cid] = true },
        creator = cid

    }
    cachedPlayers[cid].accounts[#cachedPlayers[cid].accounts+1] = accountid
    MySQL.insert("INSERT INTO bank_accounts_new (id, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, ?) ",{
        accountid, cachedAccounts[accountid].amount, json.encode(cachedAccounts[accountid].transactions), json.encode({cid}), cachedAccounts[accountid].frozen, cid
    })
    BankLog(source, "bank_account_create", locale("log_success"), { account = accountid, creator = cid })
end)

RegisterNetEvent("Renewed-Banking:server:getPlayerAccounts", function()
    local Player = GetPlayerObject(source)
    local cid = GetIdentifier(Player)
    local accounts = cachedPlayers[cid].accounts
    local data = {}
    if #accounts >= 1 then
        for k=1, #accounts do
            if cachedAccounts[accounts[k]].creator == cid then
                data[#data+1] = accounts[k]
            end
        end
    end
    TriggerClientEvent("Renewed-Banking:client:accountsMenu", source, data)
end)

RegisterNetEvent("Renewed-Banking:server:viewMemberManagement", function(data)
    local Player = GetPlayerObject(source)

    local account = data.account
    local retData = {
        account = account,
        members = {}
    }
    local cid = GetIdentifier(Player)

    for k,_ in pairs(cachedAccounts[account].auth) do
        local Player2 = getPlayerData(source, k)
        if cid ~= GetIdentifier(Player2) then
            retData.members[k] = GetCharacterName(Player2)
        end
    end

    TriggerClientEvent("Renewed-Banking:client:viewMemberManagement", source, retData)
end)

RegisterNetEvent('Renewed-Banking:server:addAccountMember', function(account, member)
    local Player = GetPlayerObject(source)

    if GetIdentifier(Player) ~= cachedAccounts[account].creator then
        print(locale("illegal_action", GetPlayerName(source)))
        BankLog(source, "bank_member_add_failed", locale("illegal_action", GetPlayerName(source)), { account = account, member = member })
        return
    end
    local Player2 = getPlayerData(source, member)
    if not Player2 then return end

    local targetCID = GetIdentifier(Player2)
    if cachedPlayers[targetCID] then
        cachedPlayers[targetCID].accounts[#cachedPlayers[targetCID].accounts+1] = account
    end

    local auth = {}
    for k in pairs(cachedAccounts[account].auth) do auth[#auth+1] = k end
    auth[#auth+1] = targetCID
    cachedAccounts[account].auth[targetCID] = true
    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?',{json.encode(auth), account})
    BankLog(source, "bank_member_add", locale("log_success"), { account = account, member = targetCID })
end)

RegisterNetEvent('Renewed-Banking:server:removeAccountMember', function(data)
    local Player = GetPlayerObject(source)
    if GetIdentifier(Player) ~= cachedAccounts[data.account].creator then
        print(locale("illegal_action", GetPlayerName(source)))
        BankLog(source, "bank_member_remove_failed", locale("illegal_action", GetPlayerName(source)), { account = data.account, member = data.cid })
        return
    end
    local Player2 = getPlayerData(source, data.cid)
    if not Player2 then return end

    local targetCID = GetIdentifier(Player2)
    local tmp = {}
    for k in pairs(cachedAccounts[data.account].auth) do
        if targetCID ~= k then
            tmp[#tmp+1] = k
        end
    end

    if cachedPlayers[targetCID] then
        local newAccount = {}
        if #cachedPlayers[targetCID].accounts >= 1 then
            for k=1, #cachedPlayers[targetCID].accounts do
                if cachedPlayers[targetCID].accounts[k] ~= data.account then
                    newAccount[#newAccount+1] = cachedPlayers[targetCID].accounts[k]
                end
            end
        end
        cachedPlayers[targetCID].accounts = newAccount
    end
    cachedAccounts[data.account].auth[targetCID] = nil
    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?',{json.encode(tmp), data.account})
    BankLog(source, "bank_member_remove", locale("log_success"), { account = data.account, member = targetCID })
end)

RegisterNetEvent('Renewed-Banking:server:deleteAccount', function(data)
    local account = data.account
    local Player = GetPlayerObject(source)
    local cid = GetIdentifier(Player)

    cachedAccounts[account] = nil

    for k=1, #cachedPlayers[cid].accounts do
        if cachedPlayers[cid].accounts[k] == account then
            cachedPlayers[cid].accounts[k] = nil
        end
    end

    MySQL.update("DELETE FROM `bank_accounts_new` WHERE id=:id", { id = account })
    BankLog(source, "bank_account_delete", locale("log_success"), { account = account, by = cid })
end)

local find = string.find
local sub = string.sub
local function split(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = find(str, delimiter, from)
    while delim_from do
        result[#result + 1] = sub(str, from, delim_from - 1)
        from = delim_to + 1
        delim_from, delim_to = find(str, delimiter, from)
    end
    result[#result + 1] = sub(str, from)
    return result
end


local function updateAccountName(account, newName, src)
    if not account or not newName then return false end
    if not cachedAccounts[account] then
        local getTranslation = locale("invalid_account", account)
        print(getTranslation)
        if src then Notify(src, {title = locale("bank_name"), description = split(getTranslation, '0')[2], type = "error"}) end
        BankLog(src, "bank_account_rename_failed", locale("log_invalid_account", account), { account = account, newName = newName })
        return false
    end
    if cachedAccounts[newName] then
        local getTranslation = locale("existing_account", account)
        print(getTranslation)
        if src then Notify(src, {title = locale("bank_name"), description = split(getTranslation, '0')[2], type = "error"}) end
        BankLog(src, "bank_account_rename_failed", locale("existing_account", newName), { account = account, newName = newName })
        return false
    end
    if src then
        local Player = GetPlayerObject(src)
        if GetIdentifier(Player) ~= cachedAccounts[account].creator then
            local getTranslation = locale("illegal_action", GetPlayerName(src))
            print(getTranslation)
            Notify(src, {title = locale("bank_name"), description = split(getTranslation, '0')[2], type = "error"})
            BankLog(src, "bank_account_rename_failed", locale("illegal_action", GetPlayerName(src)), { account = account, newName = newName })
            return false
        end
    end

    cachedAccounts[newName] = json.decode(json.encode(cachedAccounts[account]))
    cachedAccounts[newName].id = newName
    cachedAccounts[newName].name = newName
    cachedAccounts[account] = nil
    for _, id in ipairs(GetPlayers()) do
        local Player2 = GetPlayerObject(id)
        if not Player2 then goto Skip end
        local cid = GetIdentifier(Player2)
        if #cachedPlayers[cid].accounts >= 1 then
            for k=1, #cachedPlayers[cid].accounts do
                if cachedPlayers[cid].accounts[k] == account then
                    table.remove(cachedPlayers[cid].accounts, k)
                    cachedPlayers[cid].accounts[#cachedPlayers[cid].accounts+1] = newName
                end
            end
        end
        ::Skip::
    end
    MySQL.update('UPDATE bank_accounts_new SET id = ? WHERE id = ?',{newName, account})
    BankLog(src, "bank_account_rename", locale("log_success"), { account = account, newName = newName })
    return true
end

RegisterNetEvent('Renewed-Banking:server:changeAccountName', function(account, newName)
    updateAccountName(account, newName, source)
end) exports("changeAccountName", updateAccountName)-- Should only use this on very secure backends to avoid anyone using this as this is a server side ONLY export --

--- Retrieves a cached job account if it exists.
---@param jobName string The name of the job whose account is being retrieved.
---@return table|nil account Returns the job account if it exists, otherwise `nil`.
function GetJobAccount(jobName)
    if type(jobName) ~= "string" or jobName == "" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(GetInvokingResource(), "Invalid job name: expected a non-empty string"))
    end
    return cachedAccounts[jobName] or nil -- Returns account if found, otherwise nil
end
exports('GetJobAccount', GetJobAccount)

--- Creates a shared job account for an organization/society.
--- @param job table A table containing job account details:
---        job.name string - The unique identifier for the job (e.g., "mechanic", "police").
---        job.label string - The display name/label for the job (e.g., "Mechanic", "Police Department").
--- @param initialBalance number? The starting balance of the account. Default is 0.
--- @return table Returns the account table if found or successfully created. This function may raise an error if validation or database insertion fails.
local function CreateJobAccount(job, initialBalance)
    local currentResourceName = GetInvokingResource()

    -- Validate input parameters
    if type(job) ~= "table" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Invalid parameter: expected a table (job)"))
    end


    if type(job.name) ~= "string" or job.name == "" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Invalid job name: expected a non-empty string"))
    end

    if type(job.label) ~= "string" or job.label == "" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Invalid job label: expected a non-empty string"))
    end
    
    -- Check if account already exists
    if cachedAccounts[job.name] then
        return cachedAccounts[job.name]
    end

    -- Create the job account in cache
    cachedAccounts[job.name] = {
        id = job.name,
        type = locale("org"),
        name = job.label,
        frozen = 0,
        amount = tonumber(initialBalance) or 0,
        transactions = {},
        auth = {},
        creator = nil
    }

    local success, errorMsg = MySQL.insert("INSERT INTO bank_accounts_new (id, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, NULL)", {
        job.name,
        cachedAccounts[job.name].amount,
        json.encode(cachedAccounts[job.name].transactions), -- Convert transactions to JSON
        json.encode(cachedAccounts[job.name].auth), -- Convert auth list to JSON
        cachedAccounts[job.name].frozen
    })

    -- Handle potential database errors
    if not success then
	cachedAccounts[job.name] = nil
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Database error: " .. tostring(errorMsg)))
    end

    BankLog(nil, "bank_job_account_create", locale("log_success"), {
        account = job.name,
        label = job.label,
        initialBalance = cachedAccounts[job.name].amount
    }, { resource = currentResourceName })

    return cachedAccounts[job.name]
end
exports("CreateJobAccount", CreateJobAccount)

local function addAccountMember(account, member)
    if not account or not member then return end

    if not cachedAccounts[account] then print(locale("invalid_account", account)) return end

    local Player2 = getPlayerData(false, member)
    if not Player2 then return end

    local targetCID = GetIdentifier(Player2)
    if cachedPlayers[targetCID] then
        cachedPlayers[targetCID].accounts[#cachedPlayers[targetCID].accounts+1] = account
    end

    local auth = {}
    for k, _ in pairs(cachedAccounts[account].auth) do auth[#auth+1] = k end
    auth[#auth+1] = targetCID
    cachedAccounts[account].auth[targetCID] = true
    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?',{json.encode(auth), account})

end
exports("addAccountMember", addAccountMember)

local function removeAccountMember(account, member)
    local Player2 = getPlayerData(false, member)

    if not Player2 then return end
    if not cachedAccounts[account] then print(locale("invalid_account", account)) return end

    local targetCID = GetIdentifier(Player2)

    local tmp = {}
    for k in pairs(cachedAccounts[account].auth) do
        if targetCID ~= k then
            tmp[#tmp+1] = k
        end
    end

    if cachedPlayers[targetCID] then
        local newAccount = {}
        if #cachedPlayers[targetCID].accounts >= 1 then
            for k=1, #cachedPlayers[targetCID].accounts do
                if cachedPlayers[targetCID].accounts[k] ~= account then
                    newAccount[#newAccount+1] = cachedPlayers[targetCID].accounts[k]
                end
            end
        end
        cachedPlayers[targetCID].accounts = newAccount
    end

    cachedAccounts[account].auth[targetCID] = nil

    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?',{json.encode(tmp), account})
end
exports("removeAccountMember", removeAccountMember)

local function getAccountTransactions(account)
    if cachedAccounts[account] then
        return cachedAccounts[account].transactions
    elseif cachedPlayers[account] then
        return cachedPlayers[account].transactions
    end
    print(locale("invalid_account", account))
    return false
end
exports("getAccountTransactions", getAccountTransactions)

lib.addCommand('givecash', {
    help = 'Gives an item to a player',
    params = {
        {
            name = 'target',
            type = 'playerId',
            help = locale("cmd_plyr_id"),
        },
        {
            name = 'amount',
            type = 'number',
            help = locale("cmd_amount"),
        }
    }
}, function(source, args)
    local Player = GetPlayerObject(source)
    if not Player then return end

    local iPlayer = GetPlayerObject(args.target)
    if not iPlayer then return Notify(source, {title = locale("bank_name"), description = locale('unknown_player', args.target), type = "error"}) end

    if IsDead(Player) then return Notify(source, {title = locale("bank_name"), description = locale('dead'), type = "error"}) end
    if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(args.target))) > 10.0 then return Notify(source, {title = locale("bank_name"), description = locale('too_far_away'), type = "error"}) end
    if args.amount < 0 then return Notify(source, {title = locale("bank_name"), description = locale('invalid_amount', "give"), type = "error"}) end

    if RemoveMoney(Player, args.amount, 'cash') then
        AddMoney(iPlayer, args.amount, 'cash')
        local nameA = GetCharacterName(Player)
        local nameB = GetCharacterName(iPlayer)
        Notify(source, {title = locale("bank_name"), description = locale('give_cash', nameB, tostring(args.amount)), type = "error"})
        Notify(args.target, {title = locale("bank_name"), description = locale('received_cash', nameA, tostring(args.amount)), type = "success"})
        BankLog(source, "bank_givecash", locale("log_success"), { target = args.target, amount = args.amount, from = nameA, to = nameB })
    else
        Notify(args.target, {title = locale("bank_name"), description = locale('not_enough_money'), type = "error"})
        BankLog(source, "bank_givecash_failed", locale("not_enough_money"), { target = args.target, amount = args.amount })
    end
end)

function ExportHandler(resource, name, cb)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCB)
        setCB(cb)
    end)
end

local createTables = {
    { query = "CREATE TABLE IF NOT EXISTS `bank_accounts_new` (`id` varchar(50) NOT NULL, `amount` int(11) DEFAULT 0, `transactions` longtext DEFAULT '[]', `auth` longtext DEFAULT '[]', `isFrozen` int(11) DEFAULT 0, `creator` varchar(50) DEFAULT NULL, PRIMARY KEY (`id`));", values = nil },
    { query = "CREATE TABLE IF NOT EXISTS `player_transactions` (`id` varchar(50) NOT NULL, `isFrozen` int(11) DEFAULT 0, `transactions` longtext DEFAULT '[]', PRIMARY KEY (`id`));", values = nil }
}

assert(MySQL.transaction.await(createTables), "Failed to create tables")
