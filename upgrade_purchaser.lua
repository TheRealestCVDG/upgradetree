--!nocheck
-- Uncanny Upgrade Tree | Modular State-Driven Upgrade Purchaser Framework
-- Architecture: SafeUtils -> TreeState -> PurchasePolicy -> UpgradePurchaser -> ConfigManager -> MiscController -> WindUI Dashboard

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local okVU, VirtualUser = pcall(game.GetService, game, "VirtualUser")
if not okVU then VirtualUser = nil end

-- Clean up any prior run before creating new connections or WindUI windows.
local PreviousPurchaser = getgenv().UncannyUpgradePurchaser
if PreviousPurchaser and type(PreviousPurchaser.destroy) == "function" then
    pcall(PreviousPurchaser.destroy)
end
local PreviousWindow = getgenv().__UncannyPurchaserWindow
if PreviousWindow then
    pcall(function() PreviousWindow:Destroy() end)
    getgenv().__UncannyPurchaserWindow = nil
end

local FALLBACK_CURRENCIES = {
    "Money", "Steel", "Points", "Gold", "Shares",
    "Renown", "Salvage", "Cargo", "Tickets", "Favors",
}

local TREE_ORDER_RANK = {
    Money = 1,
    Steel = 2,
    Points = 3,
    Gold = 4,
    Shares = 5,
    Park = 6,
    Sewers = 7,
    Waterfront = 8,
    Bend = 9,
    Pier = 10,
    Favors = 11,
    Board = 12,
}

local SORT_MODES = { "UnlocksFirst", "CheapestFirst", "MostExpensive", "TreeOrder" }

local PENDING_VERIFY_TIMEOUT = 0.35

local RESET_LAYERS = {
    { id = "prestige",  cfgKey = "AutoReset_prestige",  label = "Auto Prestige (Money -> Points)",        short = "Prestige" },
    { id = "strike",    cfgKey = "AutoReset_strike",    label = "Auto Strike Gold (Points -> Gold)",      short = "Strike Gold" },
    { id = "gopublic",  cfgKey = "AutoReset_gopublic",  label = "Auto Go Public (Gold -> Shares)",        short = "Go Public" },
    { id = "endow",     cfgKey = "AutoReset_endow",     label = "Auto Endow the Park (Shares -> Renown)", short = "Endow Park" },
    { id = "gounder",   cfgKey = "AutoReset_gounder",   label = "Auto Go Under (Renown -> Salvage)",      short = "Go Under" },
    { id = "shipout",   cfgKey = "AutoReset_shipout",   label = "Auto Ship Out (Salvage -> Cargo)",       short = "Ship Out" },
    { id = "lastferry", cfgKey = "AutoReset_lastferry", label = "Auto Last Ferry (Cargo -> Tickets)",     short = "Last Ferry" },
}

local CONFIG_FOLDER = "UncannyPurchaserConfigs"
local CONFIG_INDEX_FILE = CONFIG_FOLDER .. "/_autoload.json"
local NO_CONFIGS_LABEL = "No saved configs"

local CFG = {
    AutoBuyEnabled = false, -- Fail-closed on load
    BuyMax = true,
    SortMode = "UnlocksFirst",
    PurchaseInterval = 0.08,
    MaxBuysPerTick = 15,
    SkipExclusiveChoices = true,
    AllowSpendFavors = false,
    AutoClaimDaily = false,
    SkipMultiLevel = false,
    OnlyWithinRange = false,
    MaxRangeStuds = 65,
    ReservePercent = 0,
    EnabledTrees = {},
    BlacklistedNodes = {},
    AutoApproachNode = false,
    ApproachSettleDelay = 0.08,
    AutoResetEnabled = false,
    AutoResetTimerSeconds = 15,
    AutoResetApproach = true,
    AutoReset_prestige = false,
    AutoReset_strike = false,
    AutoReset_gopublic = false,
    AutoReset_endow = false,
    AutoReset_gounder = false,
    AutoReset_shipout = false,
    AutoReset_lastferry = false,
    MiscWalkSpeedEnabled = false,
    MiscWalkSpeed = 64,
    MiscJumpEnabled = false,
    MiscJumpHeight = 18,
    MiscInfJump = false,
    MiscFlyEnabled = false,
    MiscFlySpeed = 90,
    MiscNoclip = false,
    MiscFullbright = false,
    MiscNoFog = false,
    MiscNoPostEffects = false,
    MiscHeadlight = false,
    MiscUnlockZoom = false,
    MiscCameraMaxZoom = 400,
    MiscFOVEnabled = false,
    MiscFOV = 85,
    MiscBlackScreen = false,
    MiscGpuFpsCapEnabled = false,
    MiscGpuFpsCap = 15,
    MiscLowGraphics = false,
    MiscHideWatchers = false,
    MiscAntiAfk = false,
}

local State = {
    Running = true,
    RunSerial = 0,
    StateVersion = 0,
    Owned = {},
    Currencies = {},
    IncomePS = {},
    Rebirths = 0,
    Playtime = 0,
    FreedChoices = {},
    DailyNext = 0,
    Wager = "",
    WagerStage = 0,
    NodeAttempts = {},
    RecentLogs = {},
    StatusLogs = {},
    Connections = {},
    TotalBoughtSession = 0,
    LastAction = "Idle — Auto Purchase is OFF",
    LastDailyAttemptAt = 0,
    LastUpgradeBoughtAt = os.clock(),
    LastAutoResetAt = 0,
    PurchaserWake = false,
    SelectedManualNode = "",
    SelectedPrestigeNode = "",
    PrestigeConfirmUntil = 0,
    PrestigeConfirmId = "",
    ApplyingConfig = false,
    ApplySeq = 0,
    UIReady = false,
    ConfigNameInput = "",
    ConfigSelected = "",
    ActiveConfig = "",
    AutoloadEnabled = false,
    AutoloadProfile = "",
    SavedConfigs = {},
    DeleteConfigConfirmId = "",
    DeleteConfigConfirmUntil = 0,
    SelectedDistrict = "",
}

-- ── MODULE 1: SAFE UTILITIES & LIFECYCLE ──────────────────────────────────────
local SafeUtils = {}

function SafeUtils.isFiniteNumber(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function SafeUtils.getLocalPlayer()
    local ok, lp = pcall(function() return Players.LocalPlayer end)
    if ok and typeof(lp) == "Instance" and lp:IsA("Player") then
        return lp
    end
    return nil
end

function SafeUtils.findChild(parent, name)
    if typeof(parent) ~= "Instance" or type(name) ~= "string" then return nil end
    local ok, child = pcall(parent.FindFirstChild, parent, name)
    if ok and typeof(child) == "Instance" then
        return child
    end
    return nil
end

function SafeUtils.findPath(root, ...)
    local current = root
    for i = 1, select("#", ...) do
        current = SafeUtils.findChild(current, select(i, ...))
        if not current then return nil end
    end
    return current
end

function SafeUtils.getAttribute(inst, attrName)
    if typeof(inst) ~= "Instance" or type(attrName) ~= "string" then return nil end
    local ok, value = pcall(inst.GetAttribute, inst, attrName)
    if ok then return value end
    return nil
end

function SafeUtils.safeRequire(moduleScript)
    if typeof(moduleScript) ~= "Instance" or not moduleScript:IsA("ModuleScript") then
        return nil, "Target is not a ModuleScript"
    end
    local ok, result = pcall(require, moduleScript)
    if not ok then
        return nil, tostring(result)
    end
    return result, nil
end

function SafeUtils.safeJsonEncode(tbl)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, tbl)
    if ok and type(encoded) == "string" then
        return encoded, nil
    end
    return nil, tostring(encoded)
end

function SafeUtils.safeJsonDecode(str)
    if type(str) ~= "string" or str == "" then
        return nil, "Empty JSON string"
    end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, str)
    if ok then
        return decoded, nil
    end
    return nil, tostring(decoded)
end

function SafeUtils.trackConnection(conn)
    if typeof(conn) == "RBXScriptConnection" then
        State.Connections[#State.Connections + 1] = conn
    end
    return conn
end

function SafeUtils.disconnectAll()
    for i = #State.Connections, 1, -1 do
        local conn = State.Connections[i]
        State.Connections[i] = nil
        if typeof(conn) == "RBXScriptConnection" then
            pcall(conn.Disconnect, conn)
        end
    end
end

function SafeUtils.logStatus(key, message, isWarning)
    local now = os.clock()
    local text = tostring(message)
    local entry = State.StatusLogs[key]
    if entry and entry.message == text and (now - entry.at) < 10 then
        return
    end
    State.StatusLogs[key] = { message = text, at = now }

    local stamp = os.date("%H:%M:%S")
    State.RecentLogs[#State.RecentLogs + 1] = string.format("[%s] %s", stamp, text)
    while #State.RecentLogs > 12 do
        table.remove(State.RecentLogs, 1)
    end

    if isWarning then
        warn("[UpgradePurchaser] " .. text)
    else
        print("[UpgradePurchaser] " .. text)
    end
end

function SafeUtils.normalizeMultiSelect(value)
    local selected = {}
    if type(value) == "string" then
        if value ~= "" then
            selected[value] = true
        end
    elseif type(value) == "table" then
        for k, v in pairs(value) do
            if type(k) == "string" and v == true then
                selected[k] = true
            elseif type(v) == "string" and v ~= "" then
                selected[v] = true
            end
        end
    end
    return selected
end

function SafeUtils.formatNum(value, treeConfig)
    if not SafeUtils.isFiniteNumber(value) then
        return "0"
    end
    if treeConfig and type(treeConfig.format) == "function" then
        local ok, formatted = pcall(treeConfig.format, value)
        if ok and type(formatted) == "string" and formatted ~= "" then
            return formatted
        end
    end
    local absVal = math.abs(value)
    local sign = value < 0 and "-" or ""
    if absVal < 1000 then
        if absVal == math.floor(absVal) then
            return string.format("%s%d", sign, math.floor(absVal))
        end
        return string.format("%s%.2f", sign, absVal)
    end
    local suffixes = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
    local tier = math.floor(math.log10(absVal) / 3)
    if tier >= 1 and tier <= #suffixes then
        local scaled = absVal / (10 ^ (tier * 3))
        return string.format("%s%.2f%s", sign, scaled, suffixes[tier])
    end
    return string.format("%s%.2e", sign, absVal)
end

-- ── MODULE 2: TREE STATE READER ───────────────────────────────────────────────
local TreeState = {
    Ready = false,
    InitError = nil,
    Config = nil,
    Nodes = {},
    NodeById = {},
    OrderedTrees = {},
    Currencies = {},
    Remotes = {
        Folder = nil,
        GetState = nil,
        StateChanged = nil,
        Buy = nil,
    },
    OnStateUpdated = nil,
}

local function parseFreedChoices(raw, treeConfig)
    if treeConfig and type(treeConfig.parseFreed) == "function" then
        local ok, parsed = pcall(treeConfig.parseFreed, raw)
        if ok and type(parsed) == "table" then
            local clean = {}
            for k, v in pairs(parsed) do
                if type(k) == "string" and v == true then
                    clean[k] = true
                end
            end
            return clean
        end
    end
    local fallback = {}
    if type(raw) == "string" and raw ~= "" then
        for id in raw:gmatch("[^,]+") do
            local trimmed = id:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                fallback[trimmed] = true
            end
        end
    end
    return fallback
end

function TreeState.syncAttributes()
    local lp = SafeUtils.getLocalPlayer()
    if not lp then return false end

    for _, cur in ipairs(TreeState.Currencies) do
        local bal = tonumber(SafeUtils.getAttribute(lp, cur))
        State.Currencies[cur] = (SafeUtils.isFiniteNumber(bal) and bal >= 0) and bal or 0

        local ps = tonumber(SafeUtils.getAttribute(lp, cur .. "PS"))
        State.IncomePS[cur] = SafeUtils.isFiniteNumber(ps) and ps or 0
    end

    local rebirths = tonumber(SafeUtils.getAttribute(lp, "Rebirths"))
    State.Rebirths = (SafeUtils.isFiniteNumber(rebirths) and rebirths >= 0) and math.floor(rebirths) or 0

    local playtime = tonumber(SafeUtils.getAttribute(lp, "Playtime"))
    State.Playtime = (SafeUtils.isFiniteNumber(playtime) and playtime >= 0) and playtime or 0

    local dailyNext = tonumber(SafeUtils.getAttribute(lp, "DailyNext"))
    State.DailyNext = (SafeUtils.isFiniteNumber(dailyNext) and dailyNext >= 0) and dailyNext or 0

    local wager = SafeUtils.getAttribute(lp, "Wager")
    State.Wager = type(wager) == "string" and wager or ""

    local wagerStage = tonumber(SafeUtils.getAttribute(lp, "WagerStage"))
    State.WagerStage = (SafeUtils.isFiniteNumber(wagerStage) and wagerStage >= 0) and math.floor(wagerStage) or 0

    local freedRaw = SafeUtils.getAttribute(lp, "FreedChoices")
    State.FreedChoices = parseFreedChoices(freedRaw, TreeState.Config)

    return true
end

function TreeState.applyOwnedState(rawOwned, boughtNodeId)
    if type(rawOwned) ~= "table" then
        return false
    end

    local prevOwned = State.Owned
    local prevCount = 0
    for _, lvl in pairs(prevOwned) do
        if (tonumber(lvl) or 0) > 0 then
            prevCount += 1
        end
    end

    local nextOwned = {}
    local nextCount = 0
    local anyIncreased = false
    for k, v in pairs(rawOwned) do
        if type(k) == "string" then
            local lvl = tonumber(v)
            if SafeUtils.isFiniteNumber(lvl) and lvl >= 0 then
                local cleanLvl = math.floor(lvl)
                nextOwned[k] = cleanLvl
                if cleanLvl > 0 then
                    nextCount += 1
                end
                if cleanLvl > (prevOwned[k] or 0) then
                    State.NodeAttempts[k] = nil
                    anyIncreased = true
                end
            end
        end
    end

    if type(boughtNodeId) == "string" and boughtNodeId ~= "" then
        local newLvl = nextOwned[boughtNodeId] or 0
        local oldLvl = prevOwned[boughtNodeId] or 0
        if newLvl > oldLvl then
            State.NodeAttempts[boughtNodeId] = nil
            State.TotalBoughtSession += 1
            anyIncreased = true
        end
    end

    if State.StateVersion == 0 then
        State.LastUpgradeBoughtAt = os.clock()
    elseif anyIncreased then
        State.LastUpgradeBoughtAt = os.clock()
        State.PurchaserWake = true
    elseif prevCount > 0 and nextCount < prevCount then
        State.NodeAttempts = {}
        State.LastUpgradeBoughtAt = os.clock()
        State.PurchaserWake = true
    end

    State.Owned = nextOwned
    State.StateVersion += 1

    if type(TreeState.OnStateUpdated) == "function" then
        pcall(TreeState.OnStateUpdated, boughtNodeId)
    end
    return true
end

function TreeState.refresh()
    TreeState.syncAttributes()

    local getStateRemote = TreeState.Remotes.GetState
    if not getStateRemote or not getStateRemote:IsA("RemoteFunction") then
        return false, "GetState remote is unavailable"
    end

    local ok, result = pcall(getStateRemote.InvokeServer, getStateRemote)
    if not ok then
        SafeUtils.logStatus("getstate_err", "GetState failed: " .. tostring(result), true)
        return false, tostring(result)
    end
    if type(result) ~= "table" then
        return false, "GetState returned non-table payload"
    end

    TreeState.applyOwnedState(result, nil)
    return true
end

function TreeState.bindEvents()
    local stateChanged = TreeState.Remotes.StateChanged
    if stateChanged and stateChanged:IsA("RemoteEvent") then
        SafeUtils.trackConnection(stateChanged.OnClientEvent:Connect(function(ownedMap, boughtNodeId)
            if not State.Running then return end
            TreeState.syncAttributes()
            if type(ownedMap) == "table" then
                TreeState.applyOwnedState(ownedMap, boughtNodeId)
            end
        end))
    end

    local lp = SafeUtils.getLocalPlayer()
    if lp then
        SafeUtils.trackConnection(lp.AttributeChanged:Connect(function(attrName)
            if not State.Running then return end
            TreeState.syncAttributes()
            if attrName ~= "Playtime" and type(TreeState.OnStateUpdated) == "function" then
                pcall(TreeState.OnStateUpdated, nil)
            end
        end))
    end
end

function TreeState.getNodePosition(node)
    if type(node) ~= "table" or type(node.id) ~= "string" then
        return nil
    end

    local tilePart = SafeUtils.findPath(Workspace, "TreeButtons", node.id)
    if tilePart and tilePart:IsA("BasePart") then
        local okPos, pos = pcall(function() return tilePart.Position end)
        if okPos and typeof(pos) == "Vector3" then
            return pos
        end
    end

    if (node.at ~= nil or node.pos ~= nil)
        and TreeState.Config
        and type(TreeState.Config.worldPos) == "function"
    then
        local okWorld, worldPos = pcall(TreeState.Config.worldPos, node)
        if okWorld and typeof(worldPos) == "Vector3" then
            return worldPos
        end
    end

    return nil
end

function TreeState.getDistanceToNode(node)
    local lp = SafeUtils.getLocalPlayer()
    if not lp then return math.huge end

    local okChar, hrp = pcall(function()
        local char = lp.Character
        return char and char:FindFirstChild("HumanoidRootPart") or nil
    end)
    if not okChar or not hrp or not hrp:IsA("BasePart") then
        return math.huge
    end

    local nodePos = TreeState.getNodePosition(node)
    if not nodePos then
        return math.huge
    end

    local okDist, dist = pcall(function()
        return (hrp.Position - nodePos).Magnitude
    end)
    if okDist and SafeUtils.isFiniteNumber(dist) then
        return dist
    end
    return math.huge
end

function TreeState.getSnapshot()
    local ownedCopy = {}
    for k, v in pairs(State.Owned) do
        ownedCopy[k] = v
    end

    local currenciesCopy = {}
    for k, v in pairs(State.Currencies) do
        currenciesCopy[k] = v
    end

    local psCopy = {}
    for k, v in pairs(State.IncomePS) do
        psCopy[k] = v
    end

    local freedCopy = {}
    for k, v in pairs(State.FreedChoices) do
        freedCopy[k] = v
    end

    return {
        Owned = ownedCopy,
        Currencies = currenciesCopy,
        IncomePS = psCopy,
        Rebirths = State.Rebirths,
        Playtime = State.Playtime,
        FreedChoices = freedCopy,
        DailyNext = State.DailyNext,
        Wager = State.Wager,
        WagerStage = State.WagerStage,
        StateVersion = State.StateVersion,
    }
end

function TreeState.init()
    TreeState.Ready = false
    TreeState.InitError = nil

    local tcModule = SafeUtils.findChild(ReplicatedStorage, "TreeConfig")
    local cfg, reqErr = SafeUtils.safeRequire(tcModule)
    if type(cfg) ~= "table" or type(cfg.Nodes) ~= "table" then
        TreeState.InitError = "Failed to load ReplicatedStorage.TreeConfig: " .. tostring(reqErr)
        SafeUtils.logStatus("tc_load_err", TreeState.InitError, true)
        return false, TreeState.InitError
    end

    TreeState.Config = cfg

    -- Index nodes & node map
    local nodesList = {}
    local nodeById = {}
    local treeSet = {}

    if type(cfg.Trees) == "table" then
        for treeName in pairs(cfg.Trees) do
            if type(treeName) == "string" and treeName ~= "" then
                treeSet[treeName] = true
            end
        end
    end

    for _, node in ipairs(cfg.Nodes) do
        if type(node) == "table" and type(node.id) == "string" and node.id ~= "" then
            nodesList[#nodesList + 1] = node
            nodeById[node.id] = node
            if type(node.tree) == "string" and node.tree ~= "" then
                treeSet[node.tree] = true
            end
        end
    end

    if type(cfg.NodeById) == "table" then
        for id, node in pairs(cfg.NodeById) do
            if type(id) == "string" and type(node) == "table" and not nodeById[id] then
                nodeById[id] = node
                nodesList[#nodesList + 1] = node
            end
        end
    end

    TreeState.Nodes = nodesList
    TreeState.NodeById = nodeById

    -- Build ordered tree list & default filter config
    local orderedTrees = {}
    for treeName in pairs(treeSet) do
        orderedTrees[#orderedTrees + 1] = treeName
    end
    table.sort(orderedTrees, function(a, b)
        local ra = TREE_ORDER_RANK[a] or 999
        local rb = TREE_ORDER_RANK[b] or 999
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    TreeState.OrderedTrees = orderedTrees

    CFG.EnabledTrees = {}
    for _, treeName in ipairs(orderedTrees) do
        CFG.EnabledTrees[treeName] = (treeName ~= "Favors" and treeName ~= "Board")
    end

    -- Currencies
    local currencies = {}
    if type(cfg.Currencies) == "table" and #cfg.Currencies > 0 then
        for _, cur in ipairs(cfg.Currencies) do
            if type(cur) == "string" and cur ~= "" then
                currencies[#currencies + 1] = cur
            end
        end
    end
    if #currencies == 0 then
        for _, cur in ipairs(FALLBACK_CURRENCIES) do
            currencies[#currencies + 1] = cur
        end
    end
    TreeState.Currencies = currencies

    -- Remotes
    local remotesFolder = SafeUtils.findChild(ReplicatedStorage, "Remotes")
    local getState = SafeUtils.findChild(remotesFolder, "GetState")
    local stateChanged = SafeUtils.findChild(remotesFolder, "StateChanged")
    local buyRemote = SafeUtils.findChild(remotesFolder, "Buy")

    TreeState.Remotes = {
        Folder = remotesFolder,
        GetState = (getState and getState:IsA("RemoteFunction")) and getState or nil,
        StateChanged = (stateChanged and stateChanged:IsA("RemoteEvent")) and stateChanged or nil,
        Buy = (buyRemote and buyRemote:IsA("RemoteEvent")) and buyRemote or nil,
    }

    if not TreeState.Remotes.GetState or not TreeState.Remotes.StateChanged or not TreeState.Remotes.Buy then
        TreeState.InitError = "Required Remotes (GetState/StateChanged/Buy) missing"
        SafeUtils.logStatus("remotes_missing", TreeState.InitError, true)
        return false, TreeState.InitError
    end

    TreeState.Ready = true
    TreeState.bindEvents()
    TreeState.refresh()
    SafeUtils.logStatus("init_ok", string.format("Loaded %d nodes across %d trees", #TreeState.Nodes, #TreeState.OrderedTrees), false)
    return true
end

-- ── MODULE 3: PURCHASE POLICY (PURE EVALUATION) ───────────────────────────────
local PurchasePolicy = {}

function PurchasePolicy.classifyNode(node, snapshot)
    if type(node) ~= "table" then
        return "invalid", true, "Invalid node"
    end
    if node.hidden then
        return "hidden", true, "Hidden internal node"
    end
    if node.challenge then
        return "challenge", true, "Board wager (resets run)"
    end
    if node.handicap then
        return "handicap", true, "Wager handicap flag"
    end
    if node.rebirth then
        return "rebirth", true, "Rebirth reset node"
    end
    if node.prestige then
        return "prestige", true, "Prestige reset (manual only)"
    end
    if node.daily then
        return "daily", false, "Daily Favor Box"
    end

    local owned = snapshot and snapshot.Owned or {}
    local freed = snapshot and snapshot.FreedChoices or {}
    if node.excludes then
        local isFreed = freed[node.id] == true
        local untilFulfilled = node.excludeUntil ~= nil and (owned[node.excludeUntil] or 0) >= 1
        if not isFreed and not untilFulfilled then
            return "exclusive", false, "Mutually exclusive with " .. tostring(node.excludes)
        end
    end

    if node.currency == "Favors" or node.tree == "Favors" then
        return "favor", false, "Uses Favors"
    end

    if (tonumber(node.maxLevel) or 1) > 1 then
        return "multi", false, "Multi-level upgrade"
    end

    return "normal", false, nil
end

function PurchasePolicy.getCost(node, currentLevel)
    if type(node) ~= "table" then return math.huge end
    local lvl = math.max(0, math.floor(tonumber(currentLevel) or 0))
    local tc = TreeState.Config
    if tc and type(tc.getCost) == "function" then
        local ok, cost = pcall(tc.getCost, node, lvl)
        if ok and SafeUtils.isFiniteNumber(cost) and cost >= 0 then
            return cost
        end
    end
    local base = tonumber(node.cost) or 0
    local scale = tonumber(node.costScale) or 1
    local computed = base * (scale ^ lvl)
    if SafeUtils.isFiniteNumber(computed) and computed >= 0 then
        return computed
    end
    return math.huge
end

function PurchasePolicy.computeBuyMaxSpend(node, startLevel, spendable)
    local maxLvl = math.max(1, math.floor(tonumber(node.maxLevel) or 1))
    local lvl = math.max(0, math.floor(tonumber(startLevel) or 0))
    local cap = math.min(maxLvl, lvl + 1000)
    local total = 0
    local count = 0
    for l = lvl, cap - 1 do
        local c = PurchasePolicy.getCost(node, l)
        if not SafeUtils.isFiniteNumber(c) or c < 0 then
            break
        end
        if c > 0 and (total + c) > spendable then
            break
        end
        total += c
        count += 1
    end
    return total, count
end

function PurchasePolicy.isUnlocked(node, snapshot)
    if type(node) ~= "table" or type(snapshot) ~= "table" then
        return false
    end

    local tc = TreeState.Config
    local owned = snapshot.Owned or {}
    local freed = snapshot.FreedChoices or {}
    local rebirths = snapshot.Rebirths or 0

    local unlockedOk = true
    if tc and type(tc.isUnlocked) == "function" then
        local ok, res = pcall(tc.isUnlocked, node, owned, freed)
        unlockedOk = ok and (res == true)
    else
        if node.excludes and not freed[node.id] then
            if (owned[node.excludes] or 0) >= 1 and (not node.excludeUntil or (owned[node.excludeUntil] or 0) < 1) then
                unlockedOk = false
            end
        end
        if unlockedOk and type(node.parents) == "table" then
            for _, parentId in ipairs(node.parents) do
                if (owned[parentId] or 0) < 1 then
                    unlockedOk = false
                    break
                end
            end
        end
    end
    if not unlockedOk then
        return false
    end

    if tc and type(tc.meetsRequirement) == "function" then
        local okReq, reqMet = pcall(tc.meetsRequirement, node, rebirths, owned)
        return okReq and (reqMet == true)
    end

    return true
end

function PurchasePolicy.getPrestigeGain(node, snapshot)
    if type(node) ~= "table" or not node.prestige then return 0 end
    local tc = TreeState.Config
    if tc and type(tc.prestigeGain) == "function" then
        local ok, gain = pcall(
            tc.prestigeGain,
            node,
            snapshot.Owned or {},
            snapshot.Currencies or {},
            snapshot.Playtime or 0,
            snapshot.Rebirths or 0
        )
        if ok and SafeUtils.isFiniteNumber(gain) then
            return math.max(0, math.floor(gain))
        end
    end
    return 0
end

function PurchasePolicy.evaluateNode(node, cfg, snapshot, attempts, now, orderIndex)
    local id = node.id
    local name = type(node.name) == "string" and node.name ~= "" and node.name or id
    local tree = type(node.tree) == "string" and node.tree or "Unknown"
    local currency = type(node.currency) == "string" and node.currency or "Money"

    local owned = snapshot.Owned or {}
    local level = owned[id] or 0
    local maxLevel = math.max(1, math.floor(tonumber(node.maxLevel) or 1))
    local maxed = level >= maxLevel

    local category, hardBlocked, classReason = PurchasePolicy.classifyNode(node, snapshot)
    local unlocked = PurchasePolicy.isUnlocked(node, snapshot)
    local cost = maxed and 0 or PurchasePolicy.getCost(node, level)
    local balance = (snapshot.Currencies and snapshot.Currencies[currency]) or 0
    local reservePct = math.clamp(tonumber(cfg.ReservePercent) or 0, 0, 90)
    local spendable = (cost <= 0) and balance or (balance * (1 - reservePct / 100))
    local affordable = (cost <= 0) or (spendable >= cost)

    local enforceRangeFilter = (cfg.OnlyWithinRange == true) and (cfg.AutoApproachNode ~= true)
    local distance = math.huge
    if enforceRangeFilter and unlocked and not maxed and not hardBlocked then
        distance = TreeState.getDistanceToNode(node)
    end

    local blockedReason = nil
    if maxed then
        blockedReason = "Maxed"
    elseif hardBlocked then
        blockedReason = classReason
    elseif not unlocked then
        blockedReason = "Locked"
    elseif cfg.BlacklistedNodes and cfg.BlacklistedNodes[id] then
        blockedReason = "Blacklisted"
    elseif cfg.EnabledTrees and cfg.EnabledTrees[tree] ~= true then
        blockedReason = "Tree disabled"
    elseif category == "daily" then
        blockedReason = "Daily box"
    elseif category == "exclusive" and cfg.SkipExclusiveChoices then
        blockedReason = classReason
    elseif category == "favor" and not cfg.AllowSpendFavors then
        blockedReason = "Favors protected"
    elseif category == "multi" and cfg.SkipMultiLevel then
        blockedReason = "Multi-level skipped"
    elseif enforceRangeFilter and distance > (tonumber(cfg.MaxRangeStuds) or 65) then
        blockedReason = string.format("Out of range (%.0f studs)", distance)
    else
        local attempt = attempts and attempts[id]
        if attempt and attempt.backoffUntil and attempt.backoffUntil > now then
            blockedReason = string.format("Backoff (%.1fs)", attempt.backoffUntil - now)
        elseif attempt and attempt.pendingVerify and (now - (attempt.lastAttemptAt or 0)) < PENDING_VERIFY_TIMEOUT then
            blockedReason = "Pending confirm"
        elseif not affordable then
            blockedReason = "Need " .. tostring(currency)
        end
    end

    return {
        node = node,
        id = id,
        name = name,
        tree = tree,
        currency = currency,
        level = level,
        maxLevel = maxLevel,
        cost = cost,
        balance = balance,
        spendable = spendable,
        distance = distance,
        category = category,
        hardBlocked = hardBlocked,
        unlocked = unlocked,
        maxed = maxed,
        affordable = affordable,
        eligible = (blockedReason == nil),
        blockedReason = blockedReason,
        orderIndex = orderIndex or 0,
    }
end

local function unlockPriorityTier(eval)
    local node = eval.node
    if node.unlock ~= nil then
        return 1
    end
    if not node.filler then
        return 2
    end
    return 3
end

function PurchasePolicy.collectCandidates(cfg, snapshot, attempts, now)
    local eligibleAffordable = {}
    local unlockedPreview = {}
    local prestiges = {}
    local dailyNode = nil
    local dailyEval = nil
    local dailyReady = false

    local stats = {
        ownedNodes = 0,
        maxedNodes = 0,
        totalVisibleNodes = 0,
        unlockedCount = 0,
        affordableCount = 0,
        blockedByBackoff = 0,
    }

    for idx, node in ipairs(TreeState.Nodes) do
        local eval = PurchasePolicy.evaluateNode(node, cfg, snapshot, attempts, now, idx)

        if not node.hidden then
            stats.totalVisibleNodes += 1
            if eval.level >= 1 then
                stats.ownedNodes += 1
            end
            if eval.maxed then
                stats.maxedNodes += 1
            end
        end

        if eval.category == "daily" then
            dailyNode = node
            dailyEval = eval
            dailyReady = eval.unlocked and (not eval.maxed) and (os.time() >= (snapshot.DailyNext or 0))
        elseif eval.category == "prestige" and eval.unlocked then
            local gain = PurchasePolicy.getPrestigeGain(node, snapshot)
            prestiges[#prestiges + 1] = {
                node = node,
                eval = eval,
                gain = gain,
                ready = gain >= 1,
            }
        elseif not eval.hardBlocked and not eval.maxed and eval.unlocked then
            stats.unlockedCount += 1
            unlockedPreview[#unlockedPreview + 1] = eval
            if eval.eligible then
                stats.affordableCount += 1
                eligibleAffordable[#eligibleAffordable + 1] = eval
            elseif eval.blockedReason and eval.blockedReason:sub(1, 7) == "Backoff" then
                stats.blockedByBackoff += 1
            end
        end
    end

    local sortMode = cfg.SortMode or "UnlocksFirst"
    table.sort(eligibleAffordable, function(a, b)
        if sortMode == "UnlocksFirst" then
            local ta = unlockPriorityTier(a)
            local tb = unlockPriorityTier(b)
            if ta ~= tb then return ta < tb end
            if a.cost ~= b.cost then return a.cost < b.cost end
        elseif sortMode == "CheapestFirst" then
            if a.cost ~= b.cost then return a.cost < b.cost end
        elseif sortMode == "MostExpensive" then
            if a.cost ~= b.cost then return a.cost > b.cost end
        end
        if a.orderIndex ~= b.orderIndex then
            return a.orderIndex < b.orderIndex
        end
        return a.id < b.id
    end)

    table.sort(unlockedPreview, function(a, b)
        if a.affordable ~= b.affordable then
            return a.affordable
        end
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.orderIndex < b.orderIndex
    end)

    table.sort(prestiges, function(a, b)
        return a.eval.orderIndex < b.eval.orderIndex
    end)

    return {
        eligibleAffordable = eligibleAffordable,
        unlockedPreview = unlockedPreview,
        prestiges = prestiges,
        dailyNode = dailyNode,
        dailyEval = dailyEval,
        dailyReady = dailyReady,
        stats = stats,
    }
end

-- ── MODULE 4: UPGRADE PURCHASER ENGINE ────────────────────────────────────────
local UpgradePurchaser = {}
local ResetLayerController -- forward declaration wired in Module 4.6
local MiscController -- forward declaration wired in Module 4.75
local refreshUIFromState -- forward declaration wired in UI section

local function settlePendingBackoffs(snapshot, now)
    for nodeId, attempt in pairs(State.NodeAttempts) do
        if attempt.pendingVerify and (now - (attempt.lastAttemptAt or 0)) >= PENDING_VERIFY_TIMEOUT then
            local currentLevel = (snapshot.Owned and snapshot.Owned[nodeId]) or 0
            if currentLevel > (attempt.lastLevel or 0) then
                State.NodeAttempts[nodeId] = nil
            else
                local fails = (attempt.failCount or 0) + 1
                local waitSecs = math.min(15, 0.4 * (2 ^ (fails - 1)))
                attempt.failCount = fails
                attempt.pendingVerify = false
                attempt.backoffUntil = now + waitSecs
                SafeUtils.logStatus(
                    "backoff_" .. nodeId,
                    string.format("Purchase unconfirmed for %s; backing off %.2fs (attempt #%d)", nodeId, waitSecs, fails),
                    true
                )
            end
        end
    end
end

function UpgradePurchaser.purchaseNode(nodeOrId, buyMax, bypassPolicy, preEval)
    if not State.Running then
        return false, "Purchaser is stopped"
    end
    if not TreeState.Ready or not TreeState.Remotes.Buy then
        return false, "Game remotes not ready"
    end

    local node = type(nodeOrId) == "string" and TreeState.NodeById[nodeOrId] or nodeOrId
    if type(node) ~= "table" or type(node.id) ~= "string" then
        return false, "Invalid upgrade node"
    end

    local now = os.clock()
    local eval
    local levelForAttempt
    if type(preEval) == "table" and bypassPolicy == nil then
        eval = preEval
        local curLvl = State.Owned[node.id] or 0
        if curLvl >= (eval.maxLevel or 1) then
            return false, tostring(eval.name or node.id) .. " is already maxed"
        end
        levelForAttempt = curLvl
    else
        TreeState.syncAttributes()
        local snapshot = TreeState.getSnapshot()
        eval = PurchasePolicy.evaluateNode(node, CFG, snapshot, State.NodeAttempts, now, 0)

        if eval.hardBlocked then
            return false, eval.blockedReason or "Node is blocked by safety policy"
        end
        if eval.category == "daily" then
            return false, "Use claimDaily() for daily box"
        end
        if eval.maxed then
            return false, eval.name .. " is already maxed"
        end
        if not eval.unlocked then
            return false, eval.name .. " is currently locked"
        end
        if not eval.affordable then
            return false, string.format(
                "Need %s %s (have %s)",
                SafeUtils.formatNum(eval.cost, TreeState.Config),
                eval.currency,
                SafeUtils.formatNum(eval.balance, TreeState.Config)
            )
        end

        local allowManualBypass = (bypassPolicy == "manual" or bypassPolicy == "manual_exclusive")
        if not eval.eligible and not allowManualBypass then
            return false, eval.blockedReason or "Filtered by policy"
        end
        levelForAttempt = eval.level
    end

    local prevAttempt = State.NodeAttempts[node.id]
    State.NodeAttempts[node.id] = {
        lastAttemptAt = now,
        lastLevel = levelForAttempt,
        failCount = prevAttempt and prevAttempt.failCount or 0,
        pendingVerify = true,
        backoffUntil = 0,
    }

    local useBuyMax = (eval.maxLevel > 1) and (buyMax == true)
    local buyRemote = TreeState.Remotes.Buy
    local ok, err = pcall(buyRemote.FireServer, buyRemote, node.id, useBuyMax)
    if not ok then
        SafeUtils.logStatus("buy_fire_err", "Buy:FireServer failed: " .. tostring(err), true)
        return false, tostring(err)
    end

    State.LastAction = string.format(
        "Purchased %s (%s) — %s %s",
        eval.name,
        node.id,
        eval.cost <= 0 and "Free" or SafeUtils.formatNum(eval.cost, TreeState.Config),
        eval.cost <= 0 and "" or eval.currency
    )
    SafeUtils.logStatus("buy_" .. node.id, State.LastAction, false)
    return true, eval
end

function UpgradePurchaser.claimDaily()
    if not State.Running then
        return false, "Purchaser is stopped"
    end
    if not TreeState.Ready or not TreeState.Remotes.Buy then
        return false, "Game remotes not ready"
    end

    local now = os.clock()
    if (now - State.LastDailyAttemptAt) < 5 then
        return false, "Daily claim cooldown active"
    end

    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    local dailyNode = TreeState.NodeById["favorbox"]
    if not dailyNode or not dailyNode.daily then
        for _, n in ipairs(TreeState.Nodes) do
            if n.daily then
                dailyNode = n
                break
            end
        end
    end
    if not dailyNode then
        return false, "Daily node not found"
    end
    if not PurchasePolicy.isUnlocked(dailyNode, snapshot) then
        return false, "Daily box is not unlocked"
    end
    if os.time() < (snapshot.DailyNext or 0) then
        return false, "Daily box is on cooldown"
    end

    State.LastDailyAttemptAt = now
    local buyRemote = TreeState.Remotes.Buy
    local ok, err = pcall(buyRemote.FireServer, buyRemote, dailyNode.id)
    if not ok then
        return false, tostring(err)
    end

    State.LastAction = "Claimed Daily Favor Box"
    SafeUtils.logStatus("daily_claim", State.LastAction, false)
    return true
end

function UpgradePurchaser.triggerPrestige(nodeId, allowAutoApproach)
    if not State.Running then
        return false, "Purchaser is stopped"
    end
    if not TreeState.Ready or not TreeState.Remotes.Buy then
        return false, "Game remotes not ready"
    end
    if type(nodeId) ~= "string" or nodeId == "" then
        return false, "No prestige node selected"
    end

    local node = TreeState.NodeById[nodeId]
    if not node or not node.prestige then
        return false, "Selected node is not a prestige node"
    end

    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    if not PurchasePolicy.isUnlocked(node, snapshot) then
        return false, "Selected prestige is locked"
    end

    local gain = PurchasePolicy.getPrestigeGain(node, snapshot)
    if gain < 1 then
        return false, string.format(
            "Need at least %s %s to prestige",
            SafeUtils.formatNum(node.prestige.min or 0, TreeState.Config),
            tostring(node.prestige.from or "currency")
        )
    end

    if (allowAutoApproach == true or CFG.AutoApproachNode == true)
        and MiscController
        and type(MiscController.approachNodeIfFar) == "function"
    then
        local okCall, okApp, didTp = pcall(MiscController.approachNodeIfFar, node, 55)
        if not (okCall and okApp) then
            return false, "Failed to approach reset node"
        end
        if didTp then
            local settleDelay = math.clamp(tonumber(CFG.ApproachSettleDelay) or 0.08, 0.03, 0.30)
            task.wait(settleDelay)
            if not State.Running then
                return false, "Purchaser is stopped"
            end
        end
    end

    local buyRemote = TreeState.Remotes.Buy
    local ok, err = pcall(buyRemote.FireServer, buyRemote, node.id)
    if not ok then
        return false, tostring(err)
    end

    State.LastAction = string.format(
        "Triggered %s (+%s %s)",
        tostring(node.name or node.id),
        SafeUtils.formatNum(gain, TreeState.Config),
        tostring(node.prestige.to or "")
    )
    SafeUtils.logStatus("prestige_" .. node.id, State.LastAction, false)
    return true, gain
end

function UpgradePurchaser.purchaseStep(manualBypass)
    if not State.Running then
        return 0, "Stopped"
    end
    if not TreeState.Ready then
        return 0, TreeState.InitError or "TreeState not ready"
    end

    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    local now = os.clock()

    settlePendingBackoffs(snapshot, now)
    local result = PurchasePolicy.collectCandidates(CFG, snapshot, State.NodeAttempts, now)

    if CFG.AutoClaimDaily and result.dailyReady and not manualBypass then
        UpgradePurchaser.claimDaily()
    end

    -- Track local currency spending within this tick so we never over-commit before server replicates.
    local workingCurrencies = {}
    for k, v in pairs(snapshot.Currencies) do
        workingCurrencies[k] = v
    end
    local reservePct = math.clamp(tonumber(CFG.ReservePercent) or 0, 0, 90)
    local maxBuys = math.clamp(math.floor(tonumber(CFG.MaxBuysPerTick) or 15), 1, 30)
    local settleDelay = math.clamp(tonumber(CFG.ApproachSettleDelay) or 0.08, 0.03, 0.30)
    local boughtCount = 0

    local function canAffordWorking(eval)
        local bal = workingCurrencies[eval.currency] or 0
        local spendable = (eval.cost <= 0) and bal or (bal * (1 - reservePct / 100))
        return eval.cost <= 0 or spendable >= eval.cost, bal, spendable
    end

    local function tryBuyCandidate(eval)
        if not State.Running or boughtCount >= maxBuys then
            return false
        end
        if not manualBypass and not CFG.AutoBuyEnabled then
            return false
        end
        local okAfford, bal, spendable = canAffordWorking(eval)
        if not okAfford then
            return false
        end
        local ok = UpgradePurchaser.purchaseNode(eval.node, CFG.BuyMax, nil, eval)
        if ok then
            boughtCount += 1
            if eval.maxLevel > 1 and CFG.BuyMax then
                local spent = PurchasePolicy.computeBuyMaxSpend(eval.node, eval.level, spendable)
                workingCurrencies[eval.currency] = math.max(0, bal - spent)
            else
                workingCurrencies[eval.currency] = math.max(0, bal - eval.cost)
            end
            return true
        end
        return false
    end

    if CFG.AutoApproachNode == true and MiscController and type(MiscController.approachNodeIfFar) == "function" then
        local nearby = {}
        local far = {}
        for _, eval in ipairs(result.eligibleAffordable) do
            if TreeState.getDistanceToNode(eval.node) <= 55 then
                nearby[#nearby + 1] = eval
            else
                far[#far + 1] = eval
            end
        end

        for _, eval in ipairs(nearby) do
            if not State.Running or boughtCount >= maxBuys then
                break
            end
            tryBuyCandidate(eval)
        end

        if State.Running and boughtCount < maxBuys and #far > 0 and (manualBypass or CFG.AutoBuyEnabled) then
            local targetIdx, targetFar = nil, nil
            for i, eval in ipairs(far) do
                if canAffordWorking(eval) then
                    targetIdx = i
                    targetFar = eval
                    break
                end
            end

            if targetFar then
                local okCall, okApp, didTp = pcall(MiscController.approachNodeIfFar, targetFar.node, 55)
                if okCall and okApp then
                    if didTp then
                        task.wait(settleDelay)
                    end
                    if State.Running and (manualBypass or CFG.AutoBuyEnabled) then
                        tryBuyCandidate(targetFar)
                        for j = targetIdx + 1, #far do
                            if not State.Running or boughtCount >= maxBuys then
                                break
                            end
                            if not manualBypass and not CFG.AutoBuyEnabled then
                                break
                            end
                            local nextEval = far[j]
                            if TreeState.getDistanceToNode(nextEval.node) <= 55 then
                                tryBuyCandidate(nextEval)
                            end
                        end
                    end
                end
            end
        end
    else
        for _, eval in ipairs(result.eligibleAffordable) do
            if not State.Running or boughtCount >= maxBuys then
                break
            end
            tryBuyCandidate(eval)
        end
    end

    return boughtCount, result
end

function UpgradePurchaser.resetBackoffs()
    State.NodeAttempts = {}
    State.LastAction = "Reset all node backoff timers"
    SafeUtils.logStatus("reset_backoff", State.LastAction, false)
end

function UpgradePurchaser.start()
    State.RunSerial += 1
    local mySerial = State.RunSerial
    local lastResyncAt = os.clock()

    task.spawn(function()
        while State.Running and State.RunSerial == mySerial do
            local now = os.clock()
            if (now - lastResyncAt) >= 30 then
                lastResyncAt = now
                pcall(TreeState.refresh)
            end

            if CFG.AutoBuyEnabled then
                local ok, err = pcall(UpgradePurchaser.purchaseStep, false)
                if not ok then
                    SafeUtils.logStatus("step_err", "purchaseStep error: " .. tostring(err), true)
                end
            else
                if State.LastAction == "" then
                    State.LastAction = "Idle — Auto Purchase is OFF"
                end
            end

            if CFG.AutoResetEnabled and ResetLayerController and type(ResetLayerController.step) == "function" then
                local okReset, errReset = pcall(ResetLayerController.step)
                if not okReset then
                    SafeUtils.logStatus("reset_err", "ResetLayerController error: " .. tostring(errReset), true)
                end
            end

            local interval = math.clamp(tonumber(CFG.PurchaseInterval) or 0.08, 0.02, 2.0)
            State.PurchaserWake = false
            local deadline = os.clock() + interval
            while State.Running and State.RunSerial == mySerial and not State.PurchaserWake do
                local rem = deadline - os.clock()
                if rem <= 0 then
                    break
                end
                task.wait(math.min(0.02, rem))
            end
        end
    end)
end

function UpgradePurchaser.stop()
    CFG.AutoBuyEnabled = false
    State.RunSerial += 1
    State.LastAction = "Stopped — Auto Purchase is OFF"
end

-- ── MODULE 4.5: CONFIG MANAGER (SAVE / LOAD / AUTOLOAD) ───────────────────────
local ConfigManager = {
    OnApplyUI = nil,
}

function ConfigManager.isSupported()
    return type(isfolder) == "function"
        and type(makefolder) == "function"
        and type(listfiles) == "function"
        and type(isfile) == "function"
        and type(readfile) == "function"
        and type(writefile) == "function"
end

function ConfigManager.canDelete()
    return type(delfile) == "function"
end

function ConfigManager.cleanName(raw)
    if type(raw) ~= "string" then
        return ""
    end
    local cleaned = raw:gsub("[^%w%-%_ ]", "")
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :sub(1, 48)
    if cleaned == "" or cleaned:sub(1, 1) == "_" then
        return ""
    end
    return cleaned
end

function ConfigManager.profilePath(name)
    local clean = ConfigManager.cleanName(name)
    if clean == "" then
        return nil, ""
    end
    return CONFIG_FOLDER .. "/" .. clean .. ".json", clean
end

function ConfigManager.ensureFolder()
    if not ConfigManager.isSupported() then
        return false, "Executor filesystem API is unavailable"
    end
    local okCheck, exists = pcall(isfolder, CONFIG_FOLDER)
    if not okCheck then
        return false, "isfolder failed: " .. tostring(exists)
    end
    if exists then
        return true
    end
    local okMake, errMake = pcall(makefolder, CONFIG_FOLDER)
    if not okMake then
        return false, "makefolder failed: " .. tostring(errMake)
    end
    return true
end

function ConfigManager.listProfiles()
    if not ConfigManager.isSupported() then
        State.SavedConfigs = {}
        return State.SavedConfigs
    end
    local okFolder = ConfigManager.ensureFolder()
    if not okFolder then
        State.SavedConfigs = {}
        return State.SavedConfigs
    end

    local okList, files = pcall(listfiles, CONFIG_FOLDER)
    if not okList or type(files) ~= "table" then
        State.SavedConfigs = {}
        return State.SavedConfigs
    end

    local seen = {}
    local profiles = {}
    for _, fullPath in ipairs(files) do
        if type(fullPath) == "string" then
            local fileName = fullPath:match("([^/\\]+)$") or fullPath
            local stem = fileName:match("^(.+)%.json$")
            if stem and stem:sub(1, 1) ~= "_" then
                local clean = ConfigManager.cleanName(stem)
                if clean ~= "" and not seen[clean] then
                    seen[clean] = true
                    profiles[#profiles + 1] = clean
                end
            end
        end
    end

    table.sort(profiles)
    State.SavedConfigs = profiles
    return profiles
end

function ConfigManager.serializeCFG(profileName)
    local enabledTrees = {}
    for _, treeName in ipairs(TreeState.OrderedTrees) do
        if CFG.EnabledTrees and CFG.EnabledTrees[treeName] == true then
            enabledTrees[#enabledTrees + 1] = treeName
        end
    end

    local blacklistedNodes = {}
    if type(CFG.BlacklistedNodes) == "table" then
        for nodeId, flagged in pairs(CFG.BlacklistedNodes) do
            if type(nodeId) == "string" and nodeId ~= "" and flagged == true then
                blacklistedNodes[#blacklistedNodes + 1] = nodeId
            end
        end
    end
    table.sort(blacklistedNodes)

    local settings = {
        AutoBuyEnabled = CFG.AutoBuyEnabled == true,
        BuyMax = CFG.BuyMax == true,
        SortMode = table.find(SORT_MODES, CFG.SortMode) and CFG.SortMode or "UnlocksFirst",
        PurchaseInterval = math.clamp(tonumber(CFG.PurchaseInterval) or 0.08, 0.02, 2.0),
        MaxBuysPerTick = math.clamp(math.floor(tonumber(CFG.MaxBuysPerTick) or 15), 1, 30),
        SkipExclusiveChoices = CFG.SkipExclusiveChoices == true,
        AllowSpendFavors = CFG.AllowSpendFavors == true,
        AutoClaimDaily = CFG.AutoClaimDaily == true,
        SkipMultiLevel = CFG.SkipMultiLevel == true,
        OnlyWithinRange = CFG.OnlyWithinRange == true,
        MaxRangeStuds = math.clamp(tonumber(CFG.MaxRangeStuds) or 65, 10, 500),
        ReservePercent = math.clamp(math.floor(tonumber(CFG.ReservePercent) or 0), 0, 90),
        EnabledTrees = enabledTrees,
        BlacklistedNodes = blacklistedNodes,
        AutoApproachNode = CFG.AutoApproachNode == true,
        ApproachSettleDelay = math.clamp(tonumber(CFG.ApproachSettleDelay) or 0.08, 0.03, 0.30),
        AutoResetEnabled = CFG.AutoResetEnabled == true,
        AutoResetTimerSeconds = math.clamp(math.floor(tonumber(CFG.AutoResetTimerSeconds) or 15), 1, 300),
        AutoResetApproach = CFG.AutoResetApproach == true,
        MiscWalkSpeedEnabled = CFG.MiscWalkSpeedEnabled == true,
        MiscWalkSpeed = math.clamp(tonumber(CFG.MiscWalkSpeed) or 64, 16, 200),
        MiscJumpEnabled = CFG.MiscJumpEnabled == true,
        MiscJumpHeight = math.clamp(tonumber(CFG.MiscJumpHeight) or 18, 7.2, 60),
        MiscInfJump = CFG.MiscInfJump == true,
        MiscFlyEnabled = CFG.MiscFlyEnabled == true,
        MiscFlySpeed = math.clamp(tonumber(CFG.MiscFlySpeed) or 90, 20, 250),
        MiscNoclip = CFG.MiscNoclip == true,
        MiscFullbright = CFG.MiscFullbright == true,
        MiscNoFog = CFG.MiscNoFog == true,
        MiscNoPostEffects = CFG.MiscNoPostEffects == true,
        MiscHeadlight = CFG.MiscHeadlight == true,
        MiscUnlockZoom = CFG.MiscUnlockZoom == true,
        MiscCameraMaxZoom = math.clamp(tonumber(CFG.MiscCameraMaxZoom) or 400, 128, 1000),
        MiscFOVEnabled = CFG.MiscFOVEnabled == true,
        MiscFOV = math.clamp(tonumber(CFG.MiscFOV) or 85, 70, 120),
        MiscBlackScreen = CFG.MiscBlackScreen == true,
        MiscGpuFpsCapEnabled = CFG.MiscGpuFpsCapEnabled == true,
        MiscGpuFpsCap = math.clamp(math.floor(tonumber(CFG.MiscGpuFpsCap) or 15), 5, 60),
        MiscLowGraphics = CFG.MiscLowGraphics == true,
        MiscHideWatchers = CFG.MiscHideWatchers == true,
        MiscAntiAfk = CFG.MiscAntiAfk == true,
    }
    for _, layer in ipairs(RESET_LAYERS) do
        settings[layer.cfgKey] = CFG[layer.cfgKey] == true
    end

    return {
        version = 1,
        name = ConfigManager.cleanName(profileName),
        savedAt = os.time(),
        settings = settings,
    }
end

function ConfigManager.validateAndNormalize(payload)
    if type(payload) ~= "table" or type(payload.settings) ~= "table" then
        return nil, "Invalid config format: missing settings table"
    end

    local s = payload.settings
    local function boolField(key, defaultVal)
        if type(s[key]) == "boolean" then
            return s[key]
        end
        return defaultVal
    end

    local function numField(key, minVal, maxVal, defaultVal, isInt)
        local n = tonumber(s[key])
        if not SafeUtils.isFiniteNumber(n) then
            return defaultVal
        end
        local clamped = math.clamp(n, minVal, maxVal)
        return isInt and math.floor(clamped) or clamped
    end

    local sortMode = (type(s.SortMode) == "string" and table.find(SORT_MODES, s.SortMode)) and s.SortMode or "UnlocksFirst"
    local purchaseInterval = numField("PurchaseInterval", 0.02, 2.0, 0.08, false)
    local maxBuysPerTick = numField("MaxBuysPerTick", 1, 30, 15, true)
    local maxRangeStuds = numField("MaxRangeStuds", 10, 500, 65, false)
    local reservePercent = numField("ReservePercent", 0, 90, 0, true)

    local enabledTrees = {}
    if s.EnabledTrees ~= nil then
        local selected = SafeUtils.normalizeMultiSelect(s.EnabledTrees)
        for _, treeName in ipairs(TreeState.OrderedTrees) do
            enabledTrees[treeName] = (selected[treeName] == true)
        end
    else
        for _, treeName in ipairs(TreeState.OrderedTrees) do
            enabledTrees[treeName] = (treeName ~= "Favors" and treeName ~= "Board")
        end
    end

    local blacklistedNodes = {}
    if s.BlacklistedNodes ~= nil then
        local selectedBlack = SafeUtils.normalizeMultiSelect(s.BlacklistedNodes)
        for nodeId, flagged in pairs(selectedBlack) do
            if type(nodeId) == "string" and nodeId ~= "" and flagged == true then
                blacklistedNodes[nodeId] = true
            end
        end
    end

    local normalized = {
        AutoBuyEnabled = boolField("AutoBuyEnabled", false),
        BuyMax = boolField("BuyMax", true),
        SortMode = sortMode,
        PurchaseInterval = purchaseInterval,
        MaxBuysPerTick = maxBuysPerTick,
        SkipExclusiveChoices = boolField("SkipExclusiveChoices", true),
        AllowSpendFavors = boolField("AllowSpendFavors", false),
        AutoClaimDaily = boolField("AutoClaimDaily", false),
        SkipMultiLevel = boolField("SkipMultiLevel", false),
        OnlyWithinRange = boolField("OnlyWithinRange", false),
        MaxRangeStuds = maxRangeStuds,
        ReservePercent = reservePercent,
        EnabledTrees = enabledTrees,
        BlacklistedNodes = blacklistedNodes,
        AutoApproachNode = boolField("AutoApproachNode", false),
        ApproachSettleDelay = numField("ApproachSettleDelay", 0.03, 0.30, 0.08, false),
        AutoResetEnabled = boolField("AutoResetEnabled", false),
        AutoResetTimerSeconds = numField("AutoResetTimerSeconds", 1, 300, 15, true),
        AutoResetApproach = boolField("AutoResetApproach", true),
        MiscWalkSpeedEnabled = boolField("MiscWalkSpeedEnabled", false),
        MiscWalkSpeed = numField("MiscWalkSpeed", 16, 200, 64, false),
        MiscJumpEnabled = boolField("MiscJumpEnabled", false),
        MiscJumpHeight = numField("MiscJumpHeight", 7.2, 60, 18, false),
        MiscInfJump = boolField("MiscInfJump", false),
        MiscFlyEnabled = boolField("MiscFlyEnabled", false),
        MiscFlySpeed = numField("MiscFlySpeed", 20, 250, 90, false),
        MiscNoclip = boolField("MiscNoclip", false),
        MiscFullbright = boolField("MiscFullbright", false),
        MiscNoFog = boolField("MiscNoFog", false),
        MiscNoPostEffects = boolField("MiscNoPostEffects", false),
        MiscHeadlight = boolField("MiscHeadlight", false),
        MiscUnlockZoom = boolField("MiscUnlockZoom", false),
        MiscCameraMaxZoom = numField("MiscCameraMaxZoom", 128, 1000, 400, false),
        MiscFOVEnabled = boolField("MiscFOVEnabled", false),
        MiscFOV = numField("MiscFOV", 70, 120, 85, false),
        MiscBlackScreen = boolField("MiscBlackScreen", false),
        MiscGpuFpsCapEnabled = boolField("MiscGpuFpsCapEnabled", false),
        MiscGpuFpsCap = numField("MiscGpuFpsCap", 5, 60, 15, true),
        MiscLowGraphics = boolField("MiscLowGraphics", false),
        MiscHideWatchers = boolField("MiscHideWatchers", false),
        MiscAntiAfk = boolField("MiscAntiAfk", false),
    }
    for _, layer in ipairs(RESET_LAYERS) do
        normalized[layer.cfgKey] = boolField(layer.cfgKey, false)
    end
    return normalized, nil
end

local function runWithApplyGuard(fn)
    State.ApplySeq += 1
    local mySeq = State.ApplySeq
    State.ApplyingConfig = true
    local ok, err = pcall(fn)
    task.defer(function()
        if State.ApplySeq == mySeq then
            State.ApplyingConfig = false
        end
    end)
    return ok, err
end

function ConfigManager.applySettings(cleanSettings)
    if type(cleanSettings) ~= "table" then
        return false, "Invalid settings payload"
    end

    local wasAutoResetEnabled = CFG.AutoResetEnabled == true
    local okApply, errApply = runWithApplyGuard(function()
        CFG.AutoBuyEnabled = cleanSettings.AutoBuyEnabled == true
        CFG.BuyMax = cleanSettings.BuyMax == true
        CFG.SortMode = cleanSettings.SortMode
        CFG.PurchaseInterval = cleanSettings.PurchaseInterval
        CFG.MaxBuysPerTick = cleanSettings.MaxBuysPerTick
        CFG.SkipExclusiveChoices = cleanSettings.SkipExclusiveChoices == true
        CFG.AllowSpendFavors = cleanSettings.AllowSpendFavors == true
        CFG.AutoClaimDaily = cleanSettings.AutoClaimDaily == true
        CFG.SkipMultiLevel = cleanSettings.SkipMultiLevel == true
        CFG.OnlyWithinRange = cleanSettings.OnlyWithinRange == true
        CFG.MaxRangeStuds = cleanSettings.MaxRangeStuds
        CFG.ReservePercent = cleanSettings.ReservePercent
        CFG.EnabledTrees = cleanSettings.EnabledTrees or {}
        CFG.BlacklistedNodes = cleanSettings.BlacklistedNodes or {}
        CFG.AutoApproachNode = cleanSettings.AutoApproachNode == true
        CFG.ApproachSettleDelay = cleanSettings.ApproachSettleDelay
        CFG.AutoResetEnabled = cleanSettings.AutoResetEnabled == true
        CFG.AutoResetTimerSeconds = cleanSettings.AutoResetTimerSeconds
        CFG.AutoResetApproach = cleanSettings.AutoResetApproach == true
        for _, layer in ipairs(RESET_LAYERS) do
            CFG[layer.cfgKey] = cleanSettings[layer.cfgKey] == true
        end
        CFG.MiscWalkSpeedEnabled = cleanSettings.MiscWalkSpeedEnabled == true
        CFG.MiscWalkSpeed = cleanSettings.MiscWalkSpeed
        CFG.MiscJumpEnabled = cleanSettings.MiscJumpEnabled == true
        CFG.MiscJumpHeight = cleanSettings.MiscJumpHeight
        CFG.MiscInfJump = cleanSettings.MiscInfJump == true
        CFG.MiscFlyEnabled = cleanSettings.MiscFlyEnabled == true
        CFG.MiscFlySpeed = cleanSettings.MiscFlySpeed
        CFG.MiscNoclip = cleanSettings.MiscNoclip == true
        CFG.MiscFullbright = cleanSettings.MiscFullbright == true
        CFG.MiscNoFog = cleanSettings.MiscNoFog == true
        CFG.MiscNoPostEffects = cleanSettings.MiscNoPostEffects == true
        CFG.MiscHeadlight = cleanSettings.MiscHeadlight == true
        CFG.MiscUnlockZoom = cleanSettings.MiscUnlockZoom == true
        CFG.MiscCameraMaxZoom = cleanSettings.MiscCameraMaxZoom
        CFG.MiscFOVEnabled = cleanSettings.MiscFOVEnabled == true
        CFG.MiscFOV = cleanSettings.MiscFOV
        CFG.MiscBlackScreen = cleanSettings.MiscBlackScreen == true
        CFG.MiscGpuFpsCapEnabled = cleanSettings.MiscGpuFpsCapEnabled == true
        CFG.MiscGpuFpsCap = cleanSettings.MiscGpuFpsCap
        CFG.MiscLowGraphics = cleanSettings.MiscLowGraphics == true
        CFG.MiscHideWatchers = cleanSettings.MiscHideWatchers == true
        CFG.MiscAntiAfk = cleanSettings.MiscAntiAfk == true

        State.LastAction = CFG.AutoBuyEnabled and "Auto Purchase enabled (from config)" or "Idle — Auto Purchase is OFF"
        if CFG.AutoResetEnabled and not wasAutoResetEnabled and ResetLayerController and type(ResetLayerController.resetTimer) == "function" then
            ResetLayerController.resetTimer()
        end
        if MiscController and type(MiscController.applyAll) == "function" then
            pcall(MiscController.applyAll)
        end
        if type(ConfigManager.OnApplyUI) == "function" then
            ConfigManager.OnApplyUI()
        end
    end)

    if not okApply then
        SafeUtils.logStatus("cfg_apply_err", "Failed applying config UI sync: " .. tostring(errApply), true)
        return false, tostring(errApply)
    end
    return true
end

function ConfigManager.saveIndex()
    if not ConfigManager.isSupported() then
        return false, "Filesystem API unavailable"
    end
    local okFolder, errFolder = ConfigManager.ensureFolder()
    if not okFolder then
        return false, errFolder
    end

    local payload = {
        version = 1,
        autoloadEnabled = State.AutoloadEnabled == true,
        autoloadProfile = ConfigManager.cleanName(State.AutoloadProfile),
        lastSelected = ConfigManager.cleanName(State.ConfigSelected),
    }
    local encoded, errEnc = SafeUtils.safeJsonEncode(payload)
    if not encoded then
        return false, errEnc
    end
    local okWrite, errWrite = pcall(writefile, CONFIG_INDEX_FILE, encoded)
    if not okWrite then
        return false, "writefile failed: " .. tostring(errWrite)
    end
    return true
end

function ConfigManager.loadIndex()
    if not ConfigManager.isSupported() then
        State.AutoloadEnabled = false
        State.AutoloadProfile = ""
        return false
    end

    local okExists, exists = pcall(isfile, CONFIG_INDEX_FILE)
    if not okExists or not exists then
        State.AutoloadEnabled = false
        State.AutoloadProfile = ""
        return false
    end

    local okRead, raw = pcall(readfile, CONFIG_INDEX_FILE)
    if not okRead or type(raw) ~= "string" then
        State.AutoloadEnabled = false
        State.AutoloadProfile = ""
        return false
    end

    local decoded = SafeUtils.safeJsonDecode(raw)
    if type(decoded) ~= "table" then
        State.AutoloadEnabled = false
        State.AutoloadProfile = ""
        return false
    end

    local autoProf = ConfigManager.cleanName(decoded.autoloadProfile)
    local autoOn = (decoded.autoloadEnabled == true) and autoProf ~= ""
    if autoProf ~= "" then
        local path = ConfigManager.profilePath(autoProf)
        local okProf, profExists = pcall(isfile, path)
        if not okProf or not profExists then
            autoProf = ""
            autoOn = false
        end
    end

    State.AutoloadProfile = autoProf
    State.AutoloadEnabled = autoOn

    local lastSel = ConfigManager.cleanName(decoded.lastSelected)
    if lastSel ~= "" then
        local path = ConfigManager.profilePath(lastSel)
        local okSel, selExists = pcall(isfile, path)
        if okSel and selExists then
            State.ConfigSelected = lastSel
            if State.ConfigNameInput == "" then
                State.ConfigNameInput = lastSel
            end
        end
    end

    return true
end

function ConfigManager.saveProfile(name)
    if not ConfigManager.isSupported() then
        return false, "Executor filesystem API is unavailable"
    end
    local okFolder, errFolder = ConfigManager.ensureFolder()
    if not okFolder then
        return false, errFolder
    end

    local rawName = (type(name) == "string" and name ~= "") and name
        or (State.ConfigNameInput ~= "" and State.ConfigNameInput or State.ConfigSelected)
    local path, clean = ConfigManager.profilePath(rawName)
    if not path then
        return false, "Enter a valid config name (letters, numbers, -, _, spaces; cannot start with _)"
    end

    local payload = ConfigManager.serializeCFG(clean)
    local encoded, errEnc = SafeUtils.safeJsonEncode(payload)
    if not encoded then
        return false, "JSON encode failed: " .. tostring(errEnc)
    end

    local okWrite, errWrite = pcall(writefile, path, encoded)
    if not okWrite then
        return false, "Failed to write config: " .. tostring(errWrite)
    end

    State.ConfigSelected = clean
    State.ConfigNameInput = clean
    State.ActiveConfig = clean
    ConfigManager.listProfiles()
    ConfigManager.saveIndex()
    SafeUtils.logStatus("cfg_save_" .. clean, "Saved config: " .. clean, false)
    return true, clean
end

function ConfigManager.loadProfile(name)
    if not ConfigManager.isSupported() then
        return false, "Executor filesystem API is unavailable"
    end

    local rawName = (type(name) == "string" and name ~= "") and name
        or (State.ConfigSelected ~= "" and State.ConfigSelected or State.ConfigNameInput)
    local path, clean = ConfigManager.profilePath(rawName)
    if not path then
        return false, "Select or enter a valid config name"
    end

    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        return false, "Config not found: " .. clean
    end

    local okRead, raw = pcall(readfile, path)
    if not okRead or type(raw) ~= "string" then
        return false, "Failed to read config: " .. tostring(raw)
    end

    local decoded, errDec = SafeUtils.safeJsonDecode(raw)
    if not decoded then
        return false, "Corrupted config JSON: " .. tostring(errDec)
    end

    local cleanSettings, errVal = ConfigManager.validateAndNormalize(decoded)
    if not cleanSettings then
        return false, tostring(errVal)
    end

    State.ConfigSelected = clean
    State.ConfigNameInput = clean
    State.ActiveConfig = clean

    local okApply, errApply = ConfigManager.applySettings(cleanSettings)
    if not okApply then
        return false, tostring(errApply)
    end

    ConfigManager.saveIndex()
    SafeUtils.logStatus("cfg_load_" .. clean, "Loaded config: " .. clean, false)
    return true, clean
end

function ConfigManager.deleteProfile(name)
    if not ConfigManager.isSupported() then
        return false, "Executor filesystem API is unavailable"
    end
    if not ConfigManager.canDelete() then
        return false, "delfile API is unavailable in this executor"
    end

    local rawName = (type(name) == "string" and name ~= "") and name or State.ConfigSelected
    local path, clean = ConfigManager.profilePath(rawName)
    if not path then
        return false, "Select a valid config to delete"
    end

    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        return false, "Config does not exist: " .. clean
    end

    local okDel, errDel = pcall(delfile, path)
    if not okDel then
        return false, "Failed to delete config: " .. tostring(errDel)
    end

    if State.AutoloadProfile == clean then
        State.AutoloadProfile = ""
        State.AutoloadEnabled = false
    end
    if State.ConfigSelected == clean then
        State.ConfigSelected = ""
    end
    if State.ActiveConfig == clean then
        State.ActiveConfig = ""
    end
    if State.ConfigNameInput == clean then
        State.ConfigNameInput = ""
    end

    ConfigManager.listProfiles()
    ConfigManager.saveIndex()
    SafeUtils.logStatus("cfg_del_" .. clean, "Deleted config: " .. clean, false)
    return true, clean
end

function ConfigManager.setAutoload(enabled, profileName, clearProfile)
    if enabled == true then
        local candidate = ConfigManager.cleanName(
            (type(profileName) == "string" and profileName ~= "") and profileName
            or (State.AutoloadProfile ~= "" and State.AutoloadProfile or State.ConfigSelected)
        )
        local path = candidate ~= "" and ConfigManager.profilePath(candidate) or nil
        local okExists, exists = false, false
        if path then
            okExists, exists = pcall(isfile, path)
        end
        if candidate == "" or not okExists or not exists then
            return false, "Select or save a valid config before enabling Autoload"
        end
        State.AutoloadProfile = candidate
        State.AutoloadEnabled = true
        ConfigManager.saveIndex()
        SafeUtils.logStatus("cfg_auto_on", "Autoload set to: " .. candidate, false)
        return true, candidate
    end

    State.AutoloadEnabled = false
    if clearProfile == true then
        State.AutoloadProfile = ""
    elseif type(profileName) == "string" and profileName ~= "" then
        local clean = ConfigManager.cleanName(profileName)
        if clean ~= "" then
            State.AutoloadProfile = clean
        end
    end
    ConfigManager.saveIndex()
    SafeUtils.logStatus("cfg_auto_off", clearProfile and "Cleared autoload config" or "Disabled autoload", false)
    return true, State.AutoloadProfile
end

function ConfigManager.tryAutoload()
    ConfigManager.listProfiles()
    ConfigManager.loadIndex()

    if State.AutoloadEnabled and State.AutoloadProfile ~= "" then
        local ok, res = ConfigManager.loadProfile(State.AutoloadProfile)
        if not ok then
            -- Fail closed if autoloaded profile is missing or invalid.
            CFG.AutoBuyEnabled = false
            State.LastAction = "Autoload failed — Auto Purchase is OFF"
            SafeUtils.logStatus("cfg_autoload_fail", "Autoload failed for '" .. tostring(State.AutoloadProfile) .. "': " .. tostring(res), true)
            return false, res
        end
        return true, res
    end

    return false, "Autoload disabled"
end

-- ── MODULE 4.6: RESET LAYER CONTROLLER (AUTO PRESTIGE / LAYERS + TIMER) ────────
ResetLayerController = {}

function ResetLayerController.resetTimer()
    State.LastUpgradeBoughtAt = os.clock()
end

function ResetLayerController.getTimerInfo(now)
    local t = now or os.clock()
    local timerSecs = math.clamp(math.floor(tonumber(CFG.AutoResetTimerSeconds) or 15), 1, 300)
    local lastAt = tonumber(State.LastUpgradeBoughtAt) or t
    local elapsed = math.max(0, t - lastAt)
    local remaining = math.max(0, timerSecs - elapsed)
    return {
        elapsed = elapsed,
        timerSecs = timerSecs,
        remaining = remaining,
        readyByTimer = elapsed >= timerSecs,
    }
end

function ResetLayerController.hasPendingPurchase(now)
    local t = now or os.clock()
    for _, att in pairs(State.NodeAttempts) do
        if att.pendingVerify and (t - (att.lastAttemptAt or 0)) < PENDING_VERIFY_TIMEOUT then
            return true
        end
    end
    return false
end

function ResetLayerController.getLayerStatuses(snapshot)
    local snap = snapshot or TreeState.getSnapshot()
    local statuses = {}
    for _, layer in ipairs(RESET_LAYERS) do
        local node = TreeState.NodeById[layer.id]
        local unlocked = (node ~= nil) and PurchasePolicy.isUnlocked(node, snap) or false
        local gain = (node ~= nil and unlocked) and PurchasePolicy.getPrestigeGain(node, snap) or 0
        statuses[#statuses + 1] = {
            layer = layer,
            node = node,
            enabled = (CFG[layer.cfgKey] == true),
            unlocked = unlocked,
            gain = gain,
            ready = (node ~= nil and unlocked and gain >= 1),
        }
    end
    return statuses
end

function ResetLayerController.pickNextReadyLayer(snapshot)
    local statuses = ResetLayerController.getLayerStatuses(snapshot)
    for i = #statuses, 1, -1 do
        local s = statuses[i]
        if s.enabled and s.ready then
            return s
        end
    end
    return nil
end

function ResetLayerController.step()
    if not State.Running or not TreeState.Ready or not CFG.AutoResetEnabled then
        return false, "Auto-reset disabled or not ready"
    end

    local now = os.clock()
    if (now - (State.LastAutoResetAt or 0)) < 2.0 then
        return false, "Post-reset cooldown"
    end
    if ResetLayerController.hasPendingPurchase(now) then
        return false, "Pending purchase confirmation"
    end

    local timerInfo = ResetLayerController.getTimerInfo(now)
    if not timerInfo.readyByTimer then
        return false, "Waiting for countdown"
    end

    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    local target = ResetLayerController.pickNextReadyLayer(snapshot)
    if not target or not target.node then
        return false, "No enabled ready reset layer"
    end

    local ok, res = UpgradePurchaser.triggerPrestige(target.node.id, CFG.AutoResetApproach == true)
    if not ok then
        return false, res
    end

    local doneAt = os.clock()
    State.LastAutoResetAt = doneAt
    State.LastUpgradeBoughtAt = doneAt
    State.NodeAttempts = {}
    local toCur = tostring(target.node.prestige and target.node.prestige.to or "")
    local msg = string.format(
        "Auto-reset triggered: %s (+%s %s)",
        tostring(target.layer.short or target.node.name or target.node.id),
        SafeUtils.formatNum(res, TreeState.Config),
        toCur
    )
    State.LastAction = msg
    SafeUtils.logStatus("autoreset_" .. tostring(target.node.id), msg, false)
    return true, target.node.id, res
end

-- ── MODULE 4.75: MISC CONTROLLER (MOBILITY / LIGHTING / QOL) ──────────────────
MiscController = {
    OnBlackScreenChanged = nil,
}

local lightingApplied = false
local lightingOriginals = nil
local noFogApplied = false
local fogOriginals = nil
local atmosphereOriginals = setmetatable({}, { __mode = "k" })
local postEffectsApplied = false
local postEffectOriginals = setmetatable({}, { __mode = "k" })
local zoomApplied = false
local originalMaxZoom = nil
local fovApplied = false
local originalFOV = nil
local walkSpeedApplied = false
local originalWalkSpeed = nil
local jumpApplied = false
local originalJumpHeight = nil
local originalJumpPower = nil
local flyActive = false
local noclipActive = false
local noclipParts = setmetatable({}, { __mode = "k" })
local districtMap = {}
local blackScreenGui = nil
local renderingDisabled = false
local fpsCapApplied = false
local lowGraphicsApplied = false
local originalQualityLevel = nil
local lowGraphicsEffects = setmetatable({}, { __mode = "k" })

local function getOverlayParent()
    if type(gethui) == "function" then
        local okHui, hui = pcall(gethui)
        if okHui and typeof(hui) == "Instance" then
            return hui
        end
    end
    local okCore, coreGui = pcall(game.GetService, game, "CoreGui")
    if okCore and typeof(coreGui) == "Instance" then
        return coreGui
    end
    local lp = SafeUtils.getLocalPlayer()
    if lp then
        local okPg, pg = pcall(lp.FindFirstChildOfClass, lp, "PlayerGui")
        if okPg and typeof(pg) == "Instance" then
            return pg
        end
    end
    return nil
end

function MiscController.getCharacterParts()
    local lp = SafeUtils.getLocalPlayer()
    if not lp then return nil, nil, nil end
    local okChar, char = pcall(function() return lp.Character end)
    if not okChar or typeof(char) ~= "Instance" then
        return nil, nil, nil
    end
    local hrp = SafeUtils.findChild(char, "HumanoidRootPart")
    if hrp and not hrp:IsA("BasePart") then hrp = nil end
    local hum = SafeUtils.findChildOfClass and SafeUtils.findChildOfClass(char, "Humanoid")
    if not hum then
        local okHum, h = pcall(char.FindFirstChildOfClass, char, "Humanoid")
        hum = okHum and h or nil
    end
    return char, hrp, hum
end

function MiscController.teleportToPosition(pos)
    if typeof(pos) ~= "Vector3" then
        return false, "Invalid target position"
    end
    local _, hrp, hum = MiscController.getCharacterParts()
    if not hrp then
        return false, "Character HumanoidRootPart unavailable"
    end
    local okTp, errTp = pcall(function()
        if hum and hum.SeatPart then
            hum.Sit = false
        end
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end)
    if not okTp then
        return false, tostring(errTp)
    end
    return true
end

function MiscController.teleportToNode(nodeOrId)
    local node = type(nodeOrId) == "string" and TreeState.NodeById[nodeOrId] or nodeOrId
    if type(node) ~= "table" then
        return false, "Invalid node"
    end
    local pos = TreeState.getNodePosition(node)
    if not pos then
        return false, "Node position unavailable"
    end
    return MiscController.teleportToPosition(pos)
end

function MiscController.approachNodeIfFar(nodeOrId, maxRange)
    local node = type(nodeOrId) == "string" and TreeState.NodeById[nodeOrId] or nodeOrId
    if type(node) ~= "table" then
        return false, false, "Invalid node"
    end
    local threshold = tonumber(maxRange) or 55
    local dist = TreeState.getDistanceToNode(node)
    if dist > threshold then
        local ok, err = MiscController.teleportToNode(node)
        if ok then
            SafeUtils.logStatus("approach_" .. tostring(node.id), string.format("Approached %s (was %.0f studs away)", tostring(node.id), dist), false)
            return true, true, nil
        end
        return false, false, err
    end
    return true, false, nil
end

function MiscController.teleportToNearestAffordable()
    if not TreeState.Ready then
        return false, "TreeState not ready"
    end
    local _, hrp = MiscController.getCharacterParts()
    if not hrp then
        return false, "Character unavailable"
    end
    local okPos, hrpPos = pcall(function() return hrp.Position end)
    if not okPos or typeof(hrpPos) ~= "Vector3" then
        return false, "Character position unavailable"
    end

    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    local collected = PurchasePolicy.collectCandidates(CFG, snapshot, State.NodeAttempts, os.clock())
    local pool = collected.eligibleAffordable
    if #pool == 0 then
        return false, "No affordable upgrades in enabled trees"
    end

    local bestEval, bestPos, bestDist = nil, nil, math.huge
    for _, eval in ipairs(pool) do
        local pos = TreeState.getNodePosition(eval.node)
        if pos then
            local d = (hrpPos - pos).Magnitude
            if d < bestDist then
                bestDist = d
                bestPos = pos
                bestEval = eval
            end
        end
    end

    if not bestEval or not bestPos then
        return false, "No reachable unlocked upgrade found"
    end
    local ok, err = MiscController.teleportToPosition(bestPos)
    if not ok then
        return false, err
    end
    return true, string.format("Teleported to [%s] %s (%.0f studs)", bestEval.tree, bestEval.name, bestDist)
end

function MiscController.getDistrictList()
    local list = {}
    districtMap = {}
    local tc = TreeState.Config
    if tc and type(tc.Travel) == "table" then
        for _, entry in ipairs(tc.Travel) do
            if type(entry) == "table" and type(entry.name) == "string" and type(entry.at) == "table" then
                local x, y, z = tonumber(entry.at[1]), tonumber(entry.at[2]), tonumber(entry.at[3])
                if SafeUtils.isFiniteNumber(x) and SafeUtils.isFiniteNumber(y) and SafeUtils.isFiniteNumber(z) then
                    local note = type(entry.note) == "string" and entry.note ~= "" and (" (" .. entry.note .. ")") or ""
                    local label = entry.name .. note
                    list[#list + 1] = label
                    districtMap[label] = Vector3.new(x, y, z)
                end
            end
        end
    end
    local sewerY = (tc and SafeUtils.isFiniteNumber(tc.SEWER_Y)) and tc.SEWER_Y or -22
    local sewerLabel = "Sewers Underground (Salvage)"
    list[#list + 1] = sewerLabel
    districtMap[sewerLabel] = Vector3.new(0, sewerY, 0)
    return list
end

function MiscController.teleportToDistrict(label)
    if type(label) ~= "string" or label == "" then
        return false, "Select a district first"
    end
    if not districtMap[label] then
        MiscController.getDistrictList()
    end
    local pos = districtMap[label]
    if not pos then
        return false, "Unknown district: " .. tostring(label)
    end
    local ok, err = MiscController.teleportToPosition(pos)
    if not ok then
        return false, err
    end
    return true, "Teleported to " .. label
end

function MiscController.applyLighting()
    if CFG.MiscFullbright or CFG.MiscLowGraphics then
        if not lightingOriginals then
            local captured = {}
            local okCap = pcall(function()
                captured.Brightness = Lighting.Brightness
                captured.ClockTime = Lighting.ClockTime
                captured.Ambient = Lighting.Ambient
                captured.OutdoorAmbient = Lighting.OutdoorAmbient
                captured.GlobalShadows = Lighting.GlobalShadows
                captured.ExposureCompensation = Lighting.ExposureCompensation
            end)
            if okCap then
                lightingOriginals = captured
            end
        end
        if CFG.MiscFullbright then
            pcall(function()
                Lighting.Brightness = 2.5
                Lighting.ClockTime = 14
                Lighting.Ambient = Color3.fromRGB(190, 190, 190)
                Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
                Lighting.GlobalShadows = false
                Lighting.ExposureCompensation = 0.25
            end)
        elseif lightingApplied and lightingOriginals then
            pcall(function()
                Lighting.Brightness = lightingOriginals.Brightness
                Lighting.ClockTime = lightingOriginals.ClockTime
                Lighting.Ambient = lightingOriginals.Ambient
                Lighting.OutdoorAmbient = lightingOriginals.OutdoorAmbient
                Lighting.GlobalShadows = false
                Lighting.ExposureCompensation = lightingOriginals.ExposureCompensation
            end)
        else
            pcall(function()
                Lighting.GlobalShadows = false
            end)
        end
        lightingApplied = true
    elseif lightingApplied and lightingOriginals then
        pcall(function()
            Lighting.Brightness = lightingOriginals.Brightness
            Lighting.ClockTime = lightingOriginals.ClockTime
            Lighting.Ambient = lightingOriginals.Ambient
            Lighting.OutdoorAmbient = lightingOriginals.OutdoorAmbient
            Lighting.GlobalShadows = lightingOriginals.GlobalShadows
            Lighting.ExposureCompensation = lightingOriginals.ExposureCompensation
        end)
        lightingApplied = false
    end
end

function MiscController.applyNoFog()
    if CFG.MiscNoFog then
        if not fogOriginals then
            local captured = {}
            local okCap = pcall(function()
                captured.FogStart = Lighting.FogStart
                captured.FogEnd = Lighting.FogEnd
            end)
            if okCap then
                fogOriginals = captured
            end
        end
        pcall(function()
            Lighting.FogStart = 1e6
            Lighting.FogEnd = 1e6
            for _, inst in ipairs(Lighting:GetDescendants()) do
                if inst:IsA("Atmosphere") then
                    if not atmosphereOriginals[inst] then
                        atmosphereOriginals[inst] = {
                            Density = inst.Density,
                            Haze = inst.Haze,
                            Glare = inst.Glare,
                            Offset = inst.Offset,
                        }
                    end
                    inst.Density = 0
                    inst.Haze = 0
                    inst.Glare = 0
                end
            end
        end)
        noFogApplied = true
    elseif noFogApplied then
        pcall(function()
            if fogOriginals then
                Lighting.FogStart = fogOriginals.FogStart
                Lighting.FogEnd = fogOriginals.FogEnd
            end
            for inst, orig in pairs(atmosphereOriginals) do
                if typeof(inst) == "Instance" and inst.Parent then
                    inst.Density = orig.Density
                    inst.Haze = orig.Haze
                    inst.Glare = orig.Glare
                    inst.Offset = orig.Offset
                end
                atmosphereOriginals[inst] = nil
            end
        end)
        noFogApplied = false
    end
end

function MiscController.applyPostEffects()
    if CFG.MiscNoPostEffects then
        pcall(function()
            for _, inst in ipairs(Lighting:GetDescendants()) do
                if inst:IsA("PostEffect") then
                    if postEffectOriginals[inst] == nil then
                        postEffectOriginals[inst] = inst.Enabled
                    end
                    inst.Enabled = false
                end
            end
        end)
        postEffectsApplied = true
    elseif postEffectsApplied then
        pcall(function()
            for inst, origEnabled in pairs(postEffectOriginals) do
                if typeof(inst) == "Instance" and inst.Parent then
                    inst.Enabled = origEnabled
                end
                postEffectOriginals[inst] = nil
            end
        end)
        postEffectsApplied = false
    end
end

function MiscController.applyHeadlight()
    local _, hrp = MiscController.getCharacterParts()
    if not hrp then return end

    local existing = SafeUtils.findChild(hrp, "__UUP_Headlight")
    if CFG.MiscHeadlight then
        if not existing or not existing:IsA("PointLight") then
            if existing then pcall(existing.Destroy, existing) end
            pcall(function()
                local light = Instance.new("PointLight")
                light.Name = "__UUP_Headlight"
                light.Brightness = 2.5
                light.Range = 60
                light.Shadows = false
                light.Color = Color3.fromRGB(255, 250, 235)
                light.Parent = hrp
            end)
        end
    elseif existing then
        pcall(existing.Destroy, existing)
    end
end

function MiscController.applyFOV()
    local okCam, cam = pcall(function() return Workspace.CurrentCamera end)
    if not okCam or not cam then return end

    if CFG.MiscFOVEnabled then
        if originalFOV == nil then
            local okF, curF = pcall(function() return cam.FieldOfView end)
            if okF and SafeUtils.isFiniteNumber(curF) then
                originalFOV = curF
            end
        end
        local targetFOV = math.clamp(tonumber(CFG.MiscFOV) or 85, 70, 120)
        pcall(function() cam.FieldOfView = targetFOV end)
        fovApplied = true
    elseif fovApplied then
        local restoreFOV = originalFOV or 70
        pcall(function() cam.FieldOfView = restoreFOV end)
        originalFOV = nil
        fovApplied = false
    end
end

function MiscController.applyCamera()
    local lp = SafeUtils.getLocalPlayer()
    if lp then
        if CFG.MiscUnlockZoom then
            if originalMaxZoom == nil then
                local okZ, curZ = pcall(function() return lp.CameraMaxZoomDistance end)
                if okZ and SafeUtils.isFiniteNumber(curZ) then
                    originalMaxZoom = curZ
                end
            end
            local targetZoom = math.clamp(tonumber(CFG.MiscCameraMaxZoom) or 400, 128, 1000)
            pcall(function() lp.CameraMaxZoomDistance = targetZoom end)
            zoomApplied = true
        elseif zoomApplied then
            local restoreZoom = originalMaxZoom or 128
            pcall(function() lp.CameraMaxZoomDistance = restoreZoom end)
            originalMaxZoom = nil
            zoomApplied = false
        end
    end

    MiscController.applyFOV()
end

function MiscController.applyHideWatchers()
    if not CFG.MiscHideWatchers then return end
    local folder = SafeUtils.findChild(Workspace, "Watchers")
    if folder then
        pcall(function()
            for _, child in ipairs(folder:GetChildren()) do
                child:Destroy()
            end
        end)
    end
end

function MiscController.applyWalkSpeed()
    local _, _, hum = MiscController.getCharacterParts()
    if not hum then return end

    if CFG.MiscWalkSpeedEnabled then
        if originalWalkSpeed == nil then
            local okWs, curWs = pcall(function() return hum.WalkSpeed end)
            if okWs and SafeUtils.isFiniteNumber(curWs) then
                originalWalkSpeed = curWs
            end
        end
        local targetWs = math.clamp(tonumber(CFG.MiscWalkSpeed) or 64, 16, 200)
        pcall(function() hum.WalkSpeed = targetWs end)
        walkSpeedApplied = true
    elseif walkSpeedApplied then
        local lp = SafeUtils.getLocalPlayer()
        local attrSpeed = lp and tonumber(SafeUtils.getAttribute(lp, "WalkSpeed"))
        local restoreSpeed = (SafeUtils.isFiniteNumber(attrSpeed) and attrSpeed > 0) and attrSpeed or (originalWalkSpeed or 24)
        pcall(function() hum.WalkSpeed = restoreSpeed end)
        originalWalkSpeed = nil
        walkSpeedApplied = false
    end
end

function MiscController.applyJump()
    local _, _, hum = MiscController.getCharacterParts()
    if not hum then return end

    if CFG.MiscJumpEnabled then
        if originalJumpHeight == nil then
            local okJh, curJh = pcall(function() return hum.JumpHeight end)
            if okJh and SafeUtils.isFiniteNumber(curJh) then
                originalJumpHeight = curJh
            end
        end
        if originalJumpPower == nil then
            local okJp, curJp = pcall(function() return hum.JumpPower end)
            if okJp and SafeUtils.isFiniteNumber(curJp) then
                originalJumpPower = curJp
            end
        end
        local targetH = math.clamp(tonumber(CFG.MiscJumpHeight) or 18, 7.2, 60)
        pcall(function()
            hum.JumpHeight = targetH
            if hum.UseJumpPower then
                hum.JumpPower = math.sqrt(2 * Workspace.Gravity * targetH)
            end
        end)
        jumpApplied = true
    elseif jumpApplied then
        pcall(function()
            if originalJumpHeight ~= nil then
                hum.JumpHeight = originalJumpHeight
            end
            if originalJumpPower ~= nil then
                hum.JumpPower = originalJumpPower
            end
        end)
        originalJumpHeight = nil
        originalJumpPower = nil
        jumpApplied = false
    end
end

function MiscController.cleanupFly()
    local _, hrp, hum = MiscController.getCharacterParts()
    if hrp then
        local fv = SafeUtils.findChild(hrp, "__UUP_FlyVel")
        if fv then pcall(fv.Destroy, fv) end
        local fg = SafeUtils.findChild(hrp, "__UUP_FlyGyro")
        if fg then pcall(fg.Destroy, fg) end
        pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
    end
    if hum then
        pcall(function() hum.PlatformStand = false end)
    end
    flyActive = false
end

function MiscController.stepFly()
    if not CFG.MiscFlyEnabled then
        if flyActive then
            MiscController.cleanupFly()
        end
        return
    end

    local _, hrp, hum = MiscController.getCharacterParts()
    if not hrp or not hum or hum.Health <= 0 then
        return
    end

    local okCam, cam = pcall(function() return Workspace.CurrentCamera end)
    if not okCam or not cam then return end

    local fv = SafeUtils.findChild(hrp, "__UUP_FlyVel")
    if not fv or not fv:IsA("BodyVelocity") then
        if fv then pcall(fv.Destroy, fv) end
        fv = Instance.new("BodyVelocity")
        fv.Name = "__UUP_FlyVel"
        fv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        fv.P = 12500
        fv.Velocity = Vector3.new(0, 0, 0)
        fv.Parent = hrp
    end

    local fg = SafeUtils.findChild(hrp, "__UUP_FlyGyro")
    if not fg or not fg:IsA("BodyGyro") then
        if fg then pcall(fg.Destroy, fg) end
        fg = Instance.new("BodyGyro")
        fg.Name = "__UUP_FlyGyro"
        fg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        fg.P = 12500
        fg.CFrame = cam.CFrame
        fg.Parent = hrp
    end

    pcall(function() hum.PlatformStand = true end)
    flyActive = true

    local moveDir = Vector3.new(0, 0, 0)
    local okFocus, focused = pcall(UserInputService.GetFocusedTextBox, UserInputService)
    if not okFocus or focused == nil then
        local cf = cam.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
            moveDir -= Vector3.new(0, 1, 0)
        end
    end

    local speed = math.clamp(tonumber(CFG.MiscFlySpeed) or 90, 20, 250)
    if moveDir.Magnitude > 0 then
        moveDir = moveDir.Unit * speed
    end

    pcall(function()
        fv.Velocity = moveDir
        fg.CFrame = cam.CFrame
    end)
end

function MiscController.cleanupNoclip()
    for part in pairs(noclipParts) do
        if typeof(part) == "Instance" and part.Parent then
            pcall(function() part.CanCollide = true end)
        end
        noclipParts[part] = nil
    end
    noclipActive = false
end

function MiscController.stepNoclip()
    if not CFG.MiscNoclip then
        if noclipActive then
            MiscController.cleanupNoclip()
        end
        return
    end
    local char = MiscController.getCharacterParts()
    if not char then return end
    noclipActive = true
    pcall(function()
        for _, inst in ipairs(char:GetDescendants()) do
            if inst:IsA("BasePart") and inst.CanCollide then
                noclipParts[inst] = true
                inst.CanCollide = false
            end
        end
    end)
end

local LOW_GFX_EFFECT_CLASSES = {
    ParticleEmitter = true,
    Trail = true,
    Beam = true,
    Smoke = true,
    Fire = true,
    Sparkles = true,
}

local function destroyStrayBlackScreens(parent)
    if typeof(parent) ~= "Instance" then return end
    pcall(function()
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == "__UUP_BlackScreen" and child:IsA("ScreenGui") then
                child:Destroy()
            end
        end
    end)
end

function MiscController.applyBlackScreen()
    if CFG.MiscBlackScreen == true then
        pcall(RunService.Set3dRenderingEnabled, RunService, false)
        renderingDisabled = true

        if not blackScreenGui or not blackScreenGui.Parent then
            local parent = getOverlayParent()
            if parent then
                destroyStrayBlackScreens(parent)
                local okGui, gui = pcall(function()
                    local sg = Instance.new("ScreenGui")
                    sg.Name = "__UUP_BlackScreen"
                    sg.IgnoreGuiInset = true
                    sg.ResetOnSpawn = false
                    sg.DisplayOrder = 2147483647
                    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

                    local backdrop = Instance.new("Frame")
                    backdrop.Name = "Backdrop"
                    backdrop.Size = UDim2.fromScale(1, 1)
                    backdrop.Position = UDim2.fromScale(0, 0)
                    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                    backdrop.BorderSizePixel = 0
                    backdrop.Active = true
                    backdrop.Parent = sg

                    local btn = Instance.new("TextButton")
                    btn.Name = "DisableButton"
                    btn.AnchorPoint = Vector2.new(0.5, 0.5)
                    btn.Position = UDim2.fromScale(0.5, 0.5)
                    btn.Size = UDim2.fromOffset(320, 64)
                    btn.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
                    btn.Text = "Disable Black Screen"
                    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                    btn.Font = Enum.Font.GothamBold
                    btn.TextSize = 22
                    btn.AutoButtonColor = true
                    btn.Parent = backdrop

                    local corner = Instance.new("UICorner")
                    corner.CornerRadius = UDim.new(0, 10)
                    corner.Parent = btn

                    local stroke = Instance.new("UIStroke")
                    stroke.Color = Color3.fromRGB(80, 80, 95)
                    stroke.Thickness = 1.5
                    stroke.Parent = btn

                    local subtitle = Instance.new("TextLabel")
                    subtitle.Name = "Subtitle"
                    subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
                    subtitle.Position = UDim2.new(0.5, 0, 0.5, 52)
                    subtitle.Size = UDim2.fromOffset(420, 28)
                    subtitle.BackgroundTransparency = 1
                    subtitle.Text = "GPU Optimizer Active — 3D Rendering Disabled"
                    subtitle.TextColor3 = Color3.fromRGB(160, 160, 170)
                    subtitle.Font = Enum.Font.Gotham
                    subtitle.TextSize = 14
                    subtitle.Parent = backdrop

                    btn.MouseButton1Click:Connect(function()
                        CFG.MiscBlackScreen = false
                        pcall(MiscController.applyBlackScreen)
                        if type(MiscController.OnBlackScreenChanged) == "function" then
                            pcall(MiscController.OnBlackScreenChanged, false)
                        end
                    end)

                    sg.Parent = parent
                    return sg
                end)
                if okGui and typeof(gui) == "Instance" then
                    blackScreenGui = gui
                end
            end
        end
    else
        if blackScreenGui then
            pcall(blackScreenGui.Destroy, blackScreenGui)
            blackScreenGui = nil
        end
        destroyStrayBlackScreens(getOverlayParent())
        if renderingDisabled then
            pcall(RunService.Set3dRenderingEnabled, RunService, true)
            renderingDisabled = false
        end
    end
end

function MiscController.applyGpuFpsCap()
    if type(setfpscap) ~= "function" then
        return
    end
    if CFG.MiscGpuFpsCapEnabled then
        local cap = math.clamp(math.floor(tonumber(CFG.MiscGpuFpsCap) or 15), 5, 60)
        pcall(setfpscap, cap)
        fpsCapApplied = true
    elseif fpsCapApplied then
        pcall(setfpscap, 0)
        fpsCapApplied = false
    end
end

function MiscController.applyLowGraphics()
    if CFG.MiscLowGraphics then
        pcall(function()
            local renderSettings = settings().Rendering
            if originalQualityLevel == nil then
                originalQualityLevel = renderSettings.QualityLevel
            end
            renderSettings.QualityLevel = Enum.QualityLevel.Level01
        end)
        pcall(function()
            for _, inst in ipairs(Workspace:GetDescendants()) do
                if LOW_GFX_EFFECT_CLASSES[inst.ClassName] then
                    if lowGraphicsEffects[inst] == nil then
                        lowGraphicsEffects[inst] = inst.Enabled
                    end
                    inst.Enabled = false
                end
            end
        end)
        lowGraphicsApplied = true
        pcall(MiscController.applyLighting)
    elseif lowGraphicsApplied then
        pcall(function()
            if originalQualityLevel ~= nil then
                settings().Rendering.QualityLevel = originalQualityLevel
                originalQualityLevel = nil
            end
        end)
        pcall(function()
            for inst, origEnabled in pairs(lowGraphicsEffects) do
                if typeof(inst) == "Instance" and inst.Parent then
                    inst.Enabled = origEnabled
                end
                lowGraphicsEffects[inst] = nil
            end
        end)
        lowGraphicsApplied = false
        pcall(MiscController.applyLighting)
    end
end

function MiscController.applyAll()
    MiscController.applyLighting()
    MiscController.applyNoFog()
    MiscController.applyPostEffects()
    MiscController.applyHeadlight()
    MiscController.applyCamera()
    MiscController.applyHideWatchers()
    MiscController.applyWalkSpeed()
    MiscController.applyJump()
    MiscController.applyBlackScreen()
    MiscController.applyGpuFpsCap()
    MiscController.applyLowGraphics()
    if not CFG.MiscFlyEnabled and flyActive then
        MiscController.cleanupFly()
    end
    if not CFG.MiscNoclip and noclipActive then
        MiscController.cleanupNoclip()
    end
end

function MiscController.cleanup()
    local savedFlags = {
        MiscFullbright = CFG.MiscFullbright,
        MiscNoFog = CFG.MiscNoFog,
        MiscNoPostEffects = CFG.MiscNoPostEffects,
        MiscHeadlight = CFG.MiscHeadlight,
        MiscUnlockZoom = CFG.MiscUnlockZoom,
        MiscFOVEnabled = CFG.MiscFOVEnabled,
        MiscWalkSpeedEnabled = CFG.MiscWalkSpeedEnabled,
        MiscJumpEnabled = CFG.MiscJumpEnabled,
        MiscFlyEnabled = CFG.MiscFlyEnabled,
        MiscNoclip = CFG.MiscNoclip,
        MiscBlackScreen = CFG.MiscBlackScreen,
        MiscGpuFpsCapEnabled = CFG.MiscGpuFpsCapEnabled,
        MiscLowGraphics = CFG.MiscLowGraphics,
    }
    CFG.MiscFullbright = false
    CFG.MiscNoFog = false
    CFG.MiscNoPostEffects = false
    CFG.MiscHeadlight = false
    CFG.MiscUnlockZoom = false
    CFG.MiscFOVEnabled = false
    CFG.MiscWalkSpeedEnabled = false
    CFG.MiscJumpEnabled = false
    CFG.MiscFlyEnabled = false
    CFG.MiscNoclip = false
    CFG.MiscBlackScreen = false
    CFG.MiscGpuFpsCapEnabled = false
    CFG.MiscLowGraphics = false

    pcall(MiscController.applyBlackScreen)
    pcall(MiscController.applyGpuFpsCap)
    pcall(MiscController.applyLowGraphics)
    pcall(RunService.Set3dRenderingEnabled, RunService, true)
    pcall(MiscController.applyLighting)
    pcall(MiscController.applyNoFog)
    pcall(MiscController.applyPostEffects)
    pcall(MiscController.applyHeadlight)
    pcall(MiscController.applyCamera)
    pcall(MiscController.applyWalkSpeed)
    pcall(MiscController.applyJump)
    pcall(MiscController.cleanupFly)
    pcall(MiscController.cleanupNoclip)

    for k, v in pairs(savedFlags) do
        CFG[k] = v
    end
end

function MiscController.bindEvents()
    local lastPeriodic = 0
    SafeUtils.trackConnection(RunService.Heartbeat:Connect(function()
        if not State.Running then return end
        if CFG.MiscFlyEnabled or flyActive then
            pcall(MiscController.stepFly)
        end
        if CFG.MiscFOVEnabled then
            pcall(MiscController.applyFOV)
        end
        if CFG.MiscNoFog then
            pcall(MiscController.applyNoFog)
        end
        local now = os.clock()
        if (now - lastPeriodic) >= 0.2 then
            lastPeriodic = now
            if CFG.MiscWalkSpeedEnabled then pcall(MiscController.applyWalkSpeed) end
            if CFG.MiscJumpEnabled then pcall(MiscController.applyJump) end
            if CFG.MiscFullbright or CFG.MiscLowGraphics then pcall(MiscController.applyLighting) end
            if CFG.MiscNoPostEffects then pcall(MiscController.applyPostEffects) end
            if CFG.MiscHeadlight then pcall(MiscController.applyHeadlight) end
            if CFG.MiscUnlockZoom then pcall(MiscController.applyCamera) end
            if CFG.MiscHideWatchers then pcall(MiscController.applyHideWatchers) end
        end
    end))

    SafeUtils.trackConnection(RunService.Stepped:Connect(function()
        if not State.Running then return end
        if CFG.MiscNoclip or noclipActive then
            pcall(MiscController.stepNoclip)
        end
    end))

    SafeUtils.trackConnection(UserInputService.JumpRequest:Connect(function()
        if not State.Running or not CFG.MiscInfJump then return end
        local _, _, hum = MiscController.getCharacterParts()
        if hum and hum.Health > 0 then
            pcall(hum.ChangeState, hum, Enum.HumanoidStateType.Jumping)
        end
    end))

    local lp = SafeUtils.getLocalPlayer()
    if lp then
        SafeUtils.trackConnection(lp.Idled:Connect(function()
            if not State.Running or not CFG.MiscAntiAfk or not VirtualUser then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end))
    end
end

-- ── INITIALIZE TREE STATE & PRELOAD CONFIG INDEX ──────────────────────────────
TreeState.init()
ConfigManager.listProfiles()
ConfigManager.loadIndex()
MiscController.bindEvents()

-- ── MODULE 5: WINDUI DASHBOARD ────────────────────────────────────────────────
local function loadWindUI()
    local ok, lib = pcall(function()
        local src = game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua")
        return loadstring(src)()
    end)
    if ok and type(lib) == "table" then
        getgenv().__UncannyPurchaserWindUI = lib
        return lib
    end
    SafeUtils.logStatus("windui_fail", "WindUI failed to load: " .. tostring(lib), true)
    return nil
end

local WindUI = loadWindUI()
local Window = nil

local StatusParagraph
local CurrenciesParagraph
local UpcomingParagraph
local PrestigeParagraph
local ResetLayersStatusParagraph
local ResetLayersListParagraph
local DiagnosticsParagraph
local ConfigStatusParagraph
local ManualNodeDropdown
local PrestigeDropdown
local ConfigNameInputWidget
local ConfigProfileDropdown
local AutoloadToggleWidget

local UIWidgets = {}
local manualOptionToId = {}
local prestigeOptionToId = {}

local function notify(title, content, duration)
    if not WindUI then return end
    pcall(function()
        WindUI:Notify({
            Title = tostring(title),
            Content = tostring(content),
            Duration = duration or 3,
        })
    end)
end

local function updateConfigStatusParagraph()
    if not ConfigStatusParagraph then return end
    local fsStatus = ConfigManager.isSupported() and "Available" or "Unavailable"
    local autoText = (State.AutoloadEnabled and State.AutoloadProfile ~= "")
        and ("ON (" .. State.AutoloadProfile .. ")")
        or (State.AutoloadProfile ~= "" and ("OFF (Target: " .. State.AutoloadProfile .. ")") or "OFF")
    local lines = {
        string.format("Filesystem API: %s | Folder: %s/", fsStatus, CONFIG_FOLDER),
        string.format("Active Config: %s | Selected: %s", State.ActiveConfig ~= "" and State.ActiveConfig or "None", State.ConfigSelected ~= "" and State.ConfigSelected or "None"),
        string.format("Autoload: %s | Saved Configs: %d", autoText, #State.SavedConfigs),
    }
    pcall(function() ConfigStatusParagraph:SetDesc(table.concat(lines, "\n")) end)
end

local function syncWidgetsFromCFG()
    if not Window then return end
    runWithApplyGuard(function()
        if UIWidgets.AutoBuyEnabled then pcall(function() UIWidgets.AutoBuyEnabled:Set(CFG.AutoBuyEnabled == true) end) end
        if UIWidgets.BuyMax then pcall(function() UIWidgets.BuyMax:Set(CFG.BuyMax == true) end) end
        if UIWidgets.AutoBuyMultiLevel then pcall(function() UIWidgets.AutoBuyMultiLevel:Set(CFG.SkipMultiLevel ~= true) end) end
        if UIWidgets.SortMode then pcall(function() UIWidgets.SortMode:Select(CFG.SortMode) end) end
        if UIWidgets.PurchaseInterval then pcall(function() UIWidgets.PurchaseInterval:Set(CFG.PurchaseInterval) end) end
        if UIWidgets.MaxBuysPerTick then pcall(function() UIWidgets.MaxBuysPerTick:Set(CFG.MaxBuysPerTick) end) end

        if UIWidgets.EnabledTrees then
            local enabledList = {}
            for _, treeName in ipairs(TreeState.OrderedTrees) do
                if CFG.EnabledTrees and CFG.EnabledTrees[treeName] == true then
                    enabledList[#enabledList + 1] = treeName
                end
            end
            pcall(function() UIWidgets.EnabledTrees:Select(enabledList) end)
        end

        if UIWidgets.SkipExclusiveChoices then pcall(function() UIWidgets.SkipExclusiveChoices:Set(CFG.SkipExclusiveChoices == true) end) end
        if UIWidgets.AllowSpendFavors then pcall(function() UIWidgets.AllowSpendFavors:Set(CFG.AllowSpendFavors == true) end) end
        if UIWidgets.AutoClaimDaily then pcall(function() UIWidgets.AutoClaimDaily:Set(CFG.AutoClaimDaily == true) end) end
        if UIWidgets.SkipMultiLevel then pcall(function() UIWidgets.SkipMultiLevel:Set(CFG.SkipMultiLevel == true) end) end
        if UIWidgets.OnlyWithinRange then pcall(function() UIWidgets.OnlyWithinRange:Set(CFG.OnlyWithinRange == true) end) end
        if UIWidgets.ReservePercent then pcall(function() UIWidgets.ReservePercent:Set(CFG.ReservePercent) end) end
        if UIWidgets.AutoApproachNode then pcall(function() UIWidgets.AutoApproachNode:Set(CFG.AutoApproachNode == true) end) end
        if UIWidgets.ApproachSettleDelay then pcall(function() UIWidgets.ApproachSettleDelay:Set(CFG.ApproachSettleDelay) end) end
        if UIWidgets.AutoResetEnabled then pcall(function() UIWidgets.AutoResetEnabled:Set(CFG.AutoResetEnabled == true) end) end
        if UIWidgets.AutoResetTimerSeconds then pcall(function() UIWidgets.AutoResetTimerSeconds:Set(CFG.AutoResetTimerSeconds) end) end
        if UIWidgets.AutoResetApproach then pcall(function() UIWidgets.AutoResetApproach:Set(CFG.AutoResetApproach == true) end) end
        for _, layer in ipairs(RESET_LAYERS) do
            local widget = UIWidgets[layer.cfgKey]
            if widget then
                pcall(function() widget:Set(CFG[layer.cfgKey] == true) end)
            end
        end
        if UIWidgets.MiscWalkSpeedEnabled then pcall(function() UIWidgets.MiscWalkSpeedEnabled:Set(CFG.MiscWalkSpeedEnabled == true) end) end
        if UIWidgets.MiscWalkSpeed then pcall(function() UIWidgets.MiscWalkSpeed:Set(CFG.MiscWalkSpeed) end) end
        if UIWidgets.MiscJumpEnabled then pcall(function() UIWidgets.MiscJumpEnabled:Set(CFG.MiscJumpEnabled == true) end) end
        if UIWidgets.MiscJumpHeight then pcall(function() UIWidgets.MiscJumpHeight:Set(CFG.MiscJumpHeight) end) end
        if UIWidgets.MiscInfJump then pcall(function() UIWidgets.MiscInfJump:Set(CFG.MiscInfJump == true) end) end
        if UIWidgets.MiscFlyEnabled then pcall(function() UIWidgets.MiscFlyEnabled:Set(CFG.MiscFlyEnabled == true) end) end
        if UIWidgets.MiscFlySpeed then pcall(function() UIWidgets.MiscFlySpeed:Set(CFG.MiscFlySpeed) end) end
        if UIWidgets.MiscNoclip then pcall(function() UIWidgets.MiscNoclip:Set(CFG.MiscNoclip == true) end) end
        if UIWidgets.MiscFullbright then pcall(function() UIWidgets.MiscFullbright:Set(CFG.MiscFullbright == true) end) end
        if UIWidgets.MiscNoFog then pcall(function() UIWidgets.MiscNoFog:Set(CFG.MiscNoFog == true) end) end
        if UIWidgets.MiscNoPostEffects then pcall(function() UIWidgets.MiscNoPostEffects:Set(CFG.MiscNoPostEffects == true) end) end
        if UIWidgets.MiscHeadlight then pcall(function() UIWidgets.MiscHeadlight:Set(CFG.MiscHeadlight == true) end) end
        if UIWidgets.MiscUnlockZoom then pcall(function() UIWidgets.MiscUnlockZoom:Set(CFG.MiscUnlockZoom == true) end) end
        if UIWidgets.MiscCameraMaxZoom then pcall(function() UIWidgets.MiscCameraMaxZoom:Set(CFG.MiscCameraMaxZoom) end) end
        if UIWidgets.MiscFOVEnabled then pcall(function() UIWidgets.MiscFOVEnabled:Set(CFG.MiscFOVEnabled == true) end) end
        if UIWidgets.MiscFOV then pcall(function() UIWidgets.MiscFOV:Set(CFG.MiscFOV) end) end
        if UIWidgets.MiscBlackScreen then pcall(function() UIWidgets.MiscBlackScreen:Set(CFG.MiscBlackScreen == true) end) end
        if UIWidgets.MiscGpuFpsCapEnabled then pcall(function() UIWidgets.MiscGpuFpsCapEnabled:Set(CFG.MiscGpuFpsCapEnabled == true) end) end
        if UIWidgets.MiscGpuFpsCap then pcall(function() UIWidgets.MiscGpuFpsCap:Set(CFG.MiscGpuFpsCap) end) end
        if UIWidgets.MiscLowGraphics then pcall(function() UIWidgets.MiscLowGraphics:Set(CFG.MiscLowGraphics == true) end) end
        if UIWidgets.MiscHideWatchers then pcall(function() UIWidgets.MiscHideWatchers:Set(CFG.MiscHideWatchers == true) end) end
        if UIWidgets.MiscAntiAfk then pcall(function() UIWidgets.MiscAntiAfk:Set(CFG.MiscAntiAfk == true) end) end
    end)
end

MiscController.OnBlackScreenChanged = function(enabled)
    if not Window then return end
    runWithApplyGuard(function()
        if UIWidgets.MiscBlackScreen then
            pcall(function() UIWidgets.MiscBlackScreen:Set(enabled == true) end)
        end
    end)
end

local function refreshConfigUI()
    local profiles = ConfigManager.listProfiles()
    runWithApplyGuard(function()
        if ConfigProfileDropdown then
            pcall(function()
                ConfigProfileDropdown:Refresh(#profiles > 0 and profiles or { NO_CONFIGS_LABEL })
            end)
            if State.ConfigSelected ~= "" and table.find(profiles, State.ConfigSelected) then
                pcall(function() ConfigProfileDropdown:Select(State.ConfigSelected) end)
            end
        end
        if ConfigNameInputWidget then
            pcall(function() ConfigNameInputWidget:Set(State.ConfigNameInput) end)
        end
        if AutoloadToggleWidget then
            pcall(function() AutoloadToggleWidget:Set(State.AutoloadEnabled == true) end)
        end
    end)
    updateConfigStatusParagraph()
end

local function buildManualAndPrestigeOptions(collected)
    local manualValues = {}
    manualOptionToId = {}
    for _, eval in ipairs(collected.unlockedPreview) do
        local costText = eval.cost <= 0 and "Free" or (SafeUtils.formatNum(eval.cost, TreeState.Config) .. " " .. eval.currency)
        local tag = eval.category == "exclusive" and " [CHOOSE ONE]"
            or (CFG.BlacklistedNodes[eval.id] and " [BLACKLISTED]" or "")
        local label = string.format("[%s] %s (%s) — %s%s", eval.tree, eval.name, eval.id, costText, tag)
        manualValues[#manualValues + 1] = label
        manualOptionToId[label] = eval.id
    end
    if #manualValues == 0 then
        manualValues[1] = "No unlocked upgrades"
    end

    local prestigeValues = {}
    prestigeOptionToId = {}
    for _, p in ipairs(collected.prestiges) do
        local n = p.node
        local label = string.format("%s (%s) — +%s %s", tostring(n.name or n.id), n.id, SafeUtils.formatNum(p.gain, TreeState.Config), tostring(n.prestige.to or ""))
        prestigeValues[#prestigeValues + 1] = label
        prestigeOptionToId[label] = n.id
    end
    if #prestigeValues == 0 then
        prestigeValues[1] = "No prestige nodes unlocked"
    end

    return manualValues, prestigeValues
end

local function refreshDropdownLists()
    if not TreeState.Ready then return end
    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    local collected = PurchasePolicy.collectCandidates(CFG, snapshot, State.NodeAttempts, os.clock())
    local manualValues, prestigeValues = buildManualAndPrestigeOptions(collected)

    if ManualNodeDropdown then
        pcall(function()
            ManualNodeDropdown:Refresh(manualValues)
        end)
    end
    if PrestigeDropdown then
        pcall(function()
            PrestigeDropdown:Refresh(prestigeValues)
        end)
    end
end

local function updateDashboard()
    if not State.Running then return end
    if not TreeState.Ready then
        if StatusParagraph then
            pcall(function() StatusParagraph:SetDesc("TreeState Error: " .. tostring(TreeState.InitError)) end)
        end
        return
    end

    TreeState.syncAttributes()
    local snapshot = TreeState.getSnapshot()
    local now = os.clock()
    local collected = PurchasePolicy.collectCandidates(CFG, snapshot, State.NodeAttempts, now)
    local stats = collected.stats

    if StatusParagraph then
        local dailyLine = "N/A"
        if collected.dailyNode then
            if collected.dailyReady then
                dailyLine = "READY"
            else
                local rem = math.max(0, (snapshot.DailyNext or 0) - os.time())
                dailyLine = string.format("%dh %dm", rem // 3600, (rem % 3600) // 60)
            end
        end

        local statusDesc = table.concat({
            string.format("Auto Purchase: %s | Mode: %s | Buy Max: %s", CFG.AutoBuyEnabled and "ON" or "OFF", tostring(CFG.SortMode), CFG.BuyMax and "ON" or "OFF"),
            string.format("Progress: %d/%d owned (%d maxed) | Unlocked: %d | Eligible Now: %d", stats.ownedNodes, stats.totalVisibleNodes, stats.maxedNodes, stats.unlockedCount, stats.affordableCount),
            string.format("Session Buys: %d | Daily Box: %s | Rebirths: %d", State.TotalBoughtSession, dailyLine, snapshot.Rebirths),
            "Last Action: " .. tostring(State.LastAction),
        }, "\n")
        pcall(function() StatusParagraph:SetDesc(statusDesc) end)
    end

    if CurrenciesParagraph then
        local curLines = {}
        for _, cur in ipairs(TreeState.Currencies) do
            local bal = snapshot.Currencies[cur] or 0
            local ps = snapshot.IncomePS[cur] or 0
            if bal > 0 or ps > 0 or cur == "Money" or cur == "Favors" then
                curLines[#curLines + 1] = string.format(
                    "%s: %s (+%s/s)",
                    cur,
                    SafeUtils.formatNum(bal, TreeState.Config),
                    SafeUtils.formatNum(ps, TreeState.Config)
                )
            end
        end
        pcall(function()
            CurrenciesParagraph:SetDesc(#curLines > 0 and table.concat(curLines, "\n") or "No currency data")
        end)
    end

    if UpcomingParagraph then
        local upLines = {}
        local limit = math.min(8, #collected.unlockedPreview)
        for i = 1, limit do
            local e = collected.unlockedPreview[i]
            local statusTag = e.eligible and "[READY]" or ("[" .. tostring(e.blockedReason or "WAIT") .. "]")
            local costStr = e.cost <= 0 and "Free" or (SafeUtils.formatNum(e.cost, TreeState.Config) .. " " .. e.currency)
            upLines[#upLines + 1] = string.format("%s [%s] %s (%d/%d) — %s", statusTag, e.tree, e.name, e.level, e.maxLevel, costStr)
        end
        pcall(function()
            UpcomingParagraph:SetDesc(#upLines > 0 and table.concat(upLines, "\n") or "No unlocked upgrades remaining")
        end)
    end

    if PrestigeParagraph then
        local pLines = {}
        for _, p in ipairs(collected.prestiges) do
            local pr = p.node.prestige
            if p.ready then
                pLines[#pLines + 1] = string.format(
                    "[READY] %s: +%s %s (from %s)",
                    tostring(p.node.name or p.node.id),
                    SafeUtils.formatNum(p.gain, TreeState.Config),
                    tostring(pr.to or ""),
                    tostring(pr.from or "")
                )
            else
                pLines[#pLines + 1] = string.format(
                    "[WAIT] %s: Needs %s %s",
                    tostring(p.node.name or p.node.id),
                    SafeUtils.formatNum(pr.min or 0, TreeState.Config),
                    tostring(pr.from or "")
                )
            end
        end
        pcall(function()
            PrestigeParagraph:SetDesc(#pLines > 0 and table.concat(pLines, "\n") or "No prestige nodes unlocked yet")
        end)
    end

    if ResetLayersStatusParagraph or ResetLayersListParagraph then
        local timerInfo = ResetLayerController.getTimerInfo(now)
        local layerStatuses = ResetLayerController.getLayerStatuses(snapshot)
        local nextTarget = nil
        for i = #layerStatuses, 1, -1 do
            local s = layerStatuses[i]
            if s.enabled and s.ready then
                nextTarget = s
                break
            end
        end

        if ResetLayersStatusParagraph then
            local countdownText = timerInfo.readyByTimer
                and "READY (0.0s remaining)"
                or string.format("%.1fs remaining", timerInfo.remaining)
            local nextText = "None ready/enabled"
            if nextTarget and nextTarget.node then
                nextText = string.format(
                    "%s (+%s %s)",
                    tostring(nextTarget.layer.short),
                    SafeUtils.formatNum(nextTarget.gain, TreeState.Config),
                    tostring(nextTarget.node.prestige and nextTarget.node.prestige.to or "")
                )
            end
            local rlStatusLines = {
                string.format(
                    "Auto Reset: %s | Delay: %ds | Auto-TP: %s",
                    CFG.AutoResetEnabled and "ON" or "OFF",
                    timerInfo.timerSecs,
                    CFG.AutoResetApproach and "ON" or "OFF"
                ),
                string.format("Since Latest Buy: %.1fs | Countdown: %s", timerInfo.elapsed, countdownText),
                "Next Eligible Layer: " .. nextText,
            }
            pcall(function() ResetLayersStatusParagraph:SetDesc(table.concat(rlStatusLines, "\n")) end)
        end

        if ResetLayersListParagraph then
            local listLines = {}
            for _, s in ipairs(layerStatuses) do
                local autoTag = s.enabled and "[AUTO ON]" or "[AUTO OFF]"
                local stateTag
                if s.ready and s.node then
                    stateTag = string.format(
                        "[READY +%s %s]",
                        SafeUtils.formatNum(s.gain, TreeState.Config),
                        tostring(s.node.prestige and s.node.prestige.to or "")
                    )
                elseif s.unlocked and s.node then
                    stateTag = string.format(
                        "[WAIT: Needs %s %s]",
                        SafeUtils.formatNum(s.node.prestige and s.node.prestige.min or 0, TreeState.Config),
                        tostring(s.node.prestige and s.node.prestige.from or "")
                    )
                else
                    stateTag = "[LOCKED]"
                end
                listLines[#listLines + 1] = string.format("%s %s — %s", autoTag, s.layer.short, stateTag)
            end
            pcall(function() ResetLayersListParagraph:SetDesc(table.concat(listLines, "\n")) end)
        end
    end

    if DiagnosticsParagraph then
        local backoffCount = 0
        for _, att in pairs(State.NodeAttempts) do
            if att.backoffUntil and att.backoffUntil > now then
                backoffCount += 1
            end
        end
        local blacklistCount = 0
        for _, flagged in pairs(CFG.BlacklistedNodes) do
            if flagged then blacklistCount += 1 end
        end

        local diagLines = {
            string.format("TreeState Ready: %s | Nodes: %d | Trees: %d", tostring(TreeState.Ready), #TreeState.Nodes, #TreeState.OrderedTrees),
            string.format("StateVersion: %d | RunSerial: %d | Connections: %d", State.StateVersion, State.RunSerial, #State.Connections),
            string.format("Backed-Off Nodes: %d | Blacklisted Nodes: %d", backoffCount, blacklistCount),
            "Recent Logs:",
        }
        for i = math.max(1, #State.RecentLogs - 5), #State.RecentLogs do
            diagLines[#diagLines + 1] = "  " .. tostring(State.RecentLogs[i])
        end
        pcall(function() DiagnosticsParagraph:SetDesc(table.concat(diagLines, "\n")) end)
    end

    updateConfigStatusParagraph()
end

local pendingUIDebounce = false
refreshUIFromState = function()
    if pendingUIDebounce or not State.Running then return end
    pendingUIDebounce = true
    task.defer(function()
        task.wait(0.1)
        pendingUIDebounce = false
        if State.Running then
            pcall(updateDashboard)
        end
    end)
end
TreeState.OnStateUpdated = refreshUIFromState

ConfigManager.OnApplyUI = function()
    syncWidgetsFromCFG()
    refreshDropdownLists()
    updateDashboard()
    refreshConfigUI()
end

if WindUI then
    local okWin, winObj = pcall(function()
        return WindUI:CreateWindow({
            Title = "Uncanny Upgrade Purchaser",
            Author = "by olliE",
            Folder = "UncannyPurchaserUI",
            Icon = "git-branch",
            Size = UDim2.fromOffset(640, 520),
            Theme = "Dark",
            Transparent = true,
            ToggleKey = Enum.KeyCode.RightShift,
            OpenButton = {
                Title = "Upgrade Purchaser",
                Enabled = true,
                Draggable = true,
                OnlyMobile = false,
            },
        })
    end)

    if okWin and winObj then
        Window = winObj
        getgenv().__UncannyPurchaserWindow = Window

        -- Tab 1: Purchaser
        local PurchaserTab = Window:Tab({ Title = "Purchaser", Icon = "shopping-cart" })
        PurchaserTab:Section({ Title = "Live Engine Status" })
        StatusParagraph = PurchaserTab:Paragraph({
            Title = "Status",
            Desc = "Initializing...",
        })

        PurchaserTab:Section({ Title = "Automation Controls" })
        UIWidgets.AutoBuyEnabled = PurchaserTab:Toggle({
            Title = "Auto Purchase",
            Value = false,
            Flag = "AutoBuyEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AutoBuyEnabled = (value == true)
                State.LastAction = CFG.AutoBuyEnabled and "Auto Purchase enabled" or "Idle — Auto Purchase is OFF"
                updateDashboard()
            end,
        })
        -- Guarantee fail-closed on initial startup regardless of prior saved flags.
        CFG.AutoBuyEnabled = false

        UIWidgets.BuyMax = PurchaserTab:Toggle({
            Title = "Buy Max (Multi-Level Upgrades)",
            Value = CFG.BuyMax,
            Flag = "BuyMax",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.BuyMax = (value == true)
            end,
        })

        UIWidgets.AutoBuyMultiLevel = PurchaserTab:Toggle({
            Title = "Auto-Buy Multi-Level Upgrades",
            Value = not CFG.SkipMultiLevel,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.SkipMultiLevel = not (value == true)
                runWithApplyGuard(function()
                    if UIWidgets.SkipMultiLevel then
                        pcall(function() UIWidgets.SkipMultiLevel:Set(CFG.SkipMultiLevel == true) end)
                    end
                end)
                updateDashboard()
            end,
        })

        UIWidgets.SortMode = PurchaserTab:Dropdown({
            Title = "Sort Priority",
            Flag = "SortMode",
            Values = SORT_MODES,
            Value = CFG.SortMode,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                if type(value) == "table" then value = value[1] end
                if table.find(SORT_MODES, value) then
                    CFG.SortMode = value
                    updateDashboard()
                end
            end,
        })

        UIWidgets.PurchaseInterval = PurchaserTab:Slider({
            Title = "Purchase Interval (seconds)",
            Flag = "PurchaseInterval",
            Value = { Min = 0.02, Max = 2.0, Default = CFG.PurchaseInterval },
            Step = 0.01,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.PurchaseInterval = math.clamp(tonumber(value) or 0.08, 0.02, 2.0)
            end,
        })

        UIWidgets.MaxBuysPerTick = PurchaserTab:Slider({
            Title = "Max Buys Per Tick",
            Flag = "MaxBuysPerTick",
            Value = { Min = 1, Max = 30, Default = CFG.MaxBuysPerTick },
            Step = 1,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MaxBuysPerTick = math.clamp(math.floor(tonumber(value) or 15), 1, 30)
            end,
        })

        PurchaserTab:Section({ Title = "Immediate Actions" })
        PurchaserTab:Button({
            Title = "Buy Affordable Now (Single Pass)",
            Callback = function()
                local count, info = UpgradePurchaser.purchaseStep(true)
                notify("Purchaser", count > 0 and ("Dispatched " .. tostring(count) .. " purchase(s)") or tostring(info and "No eligible affordable upgrades" or info), 3)
                updateDashboard()
            end,
        })
        PurchaserTab:Button({
            Title = "Force Resync State",
            Callback = function()
                local ok, err = TreeState.refresh()
                refreshDropdownLists()
                updateDashboard()
                notify("Resync", ok and "State synchronized with server" or tostring(err), 3)
            end,
        })
        PurchaserTab:Button({
            Title = "Reset Backoff Timers",
            Callback = function()
                UpgradePurchaser.resetBackoffs()
                updateDashboard()
                notify("Backoff", "Cleared all node backoff timers", 3)
            end,
        })

        -- Tab 2: Filters & Safety
        local FiltersTab = Window:Tab({ Title = "Filters & Safety", Icon = "shield-check" })
        FiltersTab:Section({ Title = "Tree & Node Filters" })

        local defaultEnabledList = {}
        for _, treeName in ipairs(TreeState.OrderedTrees) do
            if CFG.EnabledTrees[treeName] then
                defaultEnabledList[#defaultEnabledList + 1] = treeName
            end
        end

        UIWidgets.EnabledTrees = FiltersTab:Dropdown({
            Title = "Enabled Trees",
            Flag = "EnabledTrees",
            Values = #TreeState.OrderedTrees > 0 and TreeState.OrderedTrees or { "Money" },
            Value = defaultEnabledList,
            Multi = true,
            AllowNone = true,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                local selected = SafeUtils.normalizeMultiSelect(value)
                local nextEnabled = {}
                for _, treeName in ipairs(TreeState.OrderedTrees) do
                    nextEnabled[treeName] = (selected[treeName] == true)
                end
                CFG.EnabledTrees = nextEnabled
                updateDashboard()
            end,
        })

        UIWidgets.SkipExclusiveChoices = FiltersTab:Toggle({
            Title = "Skip Exclusive Choices (\"CHOOSE ONE\")",
            Value = CFG.SkipExclusiveChoices,
            Flag = "SkipExclusiveChoices",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.SkipExclusiveChoices = (value == true)
                updateDashboard()
            end,
        })

        UIWidgets.AllowSpendFavors = FiltersTab:Toggle({
            Title = "Allow Spending Favors",
            Value = CFG.AllowSpendFavors,
            Flag = "AllowSpendFavors",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AllowSpendFavors = (value == true)
                updateDashboard()
            end,
        })

        UIWidgets.AutoClaimDaily = FiltersTab:Toggle({
            Title = "Auto-Claim Daily Favor Box",
            Value = CFG.AutoClaimDaily,
            Flag = "AutoClaimDaily",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AutoClaimDaily = (value == true)
            end,
        })

        UIWidgets.SkipMultiLevel = FiltersTab:Toggle({
            Title = "Skip Multi-Level Upgrades",
            Value = CFG.SkipMultiLevel,
            Flag = "SkipMultiLevel",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.SkipMultiLevel = (value == true)
                runWithApplyGuard(function()
                    if UIWidgets.AutoBuyMultiLevel then
                        pcall(function() UIWidgets.AutoBuyMultiLevel:Set(not CFG.SkipMultiLevel) end)
                    end
                end)
                updateDashboard()
            end,
        })

        UIWidgets.OnlyWithinRange = FiltersTab:Toggle({
            Title = "Only Buy Within Range (65 studs)",
            Value = CFG.OnlyWithinRange,
            Flag = "OnlyWithinRange",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.OnlyWithinRange = (value == true)
                updateDashboard()
            end,
        })

        UIWidgets.ReservePercent = FiltersTab:Slider({
            Title = "Currency Reserve %",
            Flag = "ReservePercent",
            Value = { Min = 0, Max = 90, Default = CFG.ReservePercent },
            Step = 5,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.ReservePercent = math.clamp(tonumber(value) or 0, 0, 90)
                updateDashboard()
            end,
        })

        FiltersTab:Section({ Title = "Manual & Blacklist" })
        ManualNodeDropdown = FiltersTab:Dropdown({
            Title = "Unlocked Upgrade Node",
            Values = { "Loading..." },
            AllowNone = true,
            Callback = function(value)
                if type(value) == "table" then value = value[1] end
                State.SelectedManualNode = (type(value) == "string" and manualOptionToId[value]) or ""
            end,
        })
        FiltersTab:Button({
            Title = "Refresh Node List",
            Callback = function()
                refreshDropdownLists()
                notify("Node List", "Refreshed unlocked upgrade options", 2)
            end,
        })
        FiltersTab:Button({
            Title = "Buy Selected Node Once",
            Callback = function()
                if State.SelectedManualNode == "" then
                    notify("Manual Buy", "Select an unlocked node first", 3)
                    return
                end
                local ok, res = UpgradePurchaser.purchaseNode(State.SelectedManualNode, CFG.BuyMax, "manual_exclusive")
                notify("Manual Buy", ok and ("Purchased " .. State.SelectedManualNode) or tostring(res), 3)
                refreshDropdownLists()
                updateDashboard()
            end,
        })
        FiltersTab:Button({
            Title = "Toggle Blacklist for Selected",
            Callback = function()
                local id = State.SelectedManualNode
                if id == "" then
                    notify("Blacklist", "Select a node first", 3)
                    return
                end
                if CFG.BlacklistedNodes[id] then
                    CFG.BlacklistedNodes[id] = nil
                    notify("Blacklist", "Removed " .. id .. " from blacklist", 3)
                else
                    CFG.BlacklistedNodes[id] = true
                    notify("Blacklist", "Blacklisted " .. id, 3)
                end
                refreshDropdownLists()
                updateDashboard()
            end,
        })
        FiltersTab:Button({
            Title = "Clear Blacklist",
            Callback = function()
                CFG.BlacklistedNodes = {}
                refreshDropdownLists()
                updateDashboard()
                notify("Blacklist", "Cleared all blacklisted nodes", 3)
            end,
        })

        -- Tab 3: Overview & Prestige
        local OverviewTab = Window:Tab({ Title = "Overview & Prestige", Icon = "bar-chart-2" })
        OverviewTab:Section({ Title = "Currencies & Income/s" })
        CurrenciesParagraph = OverviewTab:Paragraph({
            Title = "Balances",
            Desc = "Loading...",
        })

        OverviewTab:Section({ Title = "Upcoming Unlocked Upgrades" })
        UpcomingParagraph = OverviewTab:Paragraph({
            Title = "Next Upgrades",
            Desc = "Loading...",
        })

        OverviewTab:Section({ Title = "Prestige Readiness (Manual Only)" })
        PrestigeParagraph = OverviewTab:Paragraph({
            Title = "Prestige Status",
            Desc = "Loading...",
        })
        PrestigeDropdown = OverviewTab:Dropdown({
            Title = "Select Prestige Node",
            Values = { "Loading..." },
            AllowNone = true,
            Callback = function(value)
                if type(value) == "table" then value = value[1] end
                State.SelectedPrestigeNode = (type(value) == "string" and prestigeOptionToId[value]) or ""
                State.PrestigeConfirmUntil = 0
                State.PrestigeConfirmId = ""
            end,
        })
        OverviewTab:Button({
            Title = "Trigger Selected Prestige (Double-Click Confirm)",
            Callback = function()
                local id = State.SelectedPrestigeNode
                if id == "" then
                    notify("Prestige", "Select an unlocked prestige node first", 3)
                    return
                end
                local now = os.clock()
                if State.PrestigeConfirmId ~= id or now > State.PrestigeConfirmUntil then
                    State.PrestigeConfirmId = id
                    State.PrestigeConfirmUntil = now + 5
                    notify("Prestige Confirm", "Click again within 5s to confirm prestige (" .. id .. ")", 5)
                    return
                end
                State.PrestigeConfirmId = ""
                State.PrestigeConfirmUntil = 0
                local ok, res = UpgradePurchaser.triggerPrestige(id, CFG.AutoApproachNode == true)
                notify("Prestige", ok and ("Triggered " .. id .. " (+" .. SafeUtils.formatNum(res, TreeState.Config) .. ")") or tostring(res), 4)
                refreshDropdownLists()
                updateDashboard()
            end,
        })

        -- Tab 4: Reset Layers
        local ResetLayersTab = Window:Tab({ Title = "Reset Layers", Icon = "refresh-cw" })
        ResetLayersTab:Section({ Title = "Auto-Reset Status" })
        ResetLayersStatusParagraph = ResetLayersTab:Paragraph({
            Title = "Status & Countdown",
            Desc = "Loading...",
        })

        ResetLayersTab:Section({ Title = "Timer & Controls" })
        UIWidgets.AutoResetEnabled = ResetLayersTab:Toggle({
            Title = "Enable Auto Reset Layers",
            Value = false,
            Flag = "AutoResetEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AutoResetEnabled = (value == true)
                if CFG.AutoResetEnabled then
                    ResetLayerController.resetTimer()
                end
                updateDashboard()
            end,
        })
        CFG.AutoResetEnabled = false

        UIWidgets.AutoResetTimerSeconds = ResetLayersTab:Slider({
            Title = "Countdown After Latest Buy (seconds)",
            Flag = "AutoResetTimerSeconds",
            Value = { Min = 1, Max = 300, Default = CFG.AutoResetTimerSeconds },
            Step = 1,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AutoResetTimerSeconds = math.clamp(math.floor(tonumber(value) or 15), 1, 300)
                updateDashboard()
            end,
        })

        UIWidgets.AutoResetApproach = ResetLayersTab:Toggle({
            Title = "Auto-TP to Reset Button (<55 studs)",
            Value = CFG.AutoResetApproach,
            Flag = "AutoResetApproach",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AutoResetApproach = (value == true)
                updateDashboard()
            end,
        })

        ResetLayersTab:Button({
            Title = "Reset Countdown Timer Now",
            Callback = function()
                ResetLayerController.resetTimer()
                updateDashboard()
                notify("Reset Layers", "Countdown timer reset", 2)
            end,
        })

        ResetLayersTab:Section({ Title = "Enabled Reset Layers (Highest Ready Priority)" })
        for _, layer in ipairs(RESET_LAYERS) do
            UIWidgets[layer.cfgKey] = ResetLayersTab:Toggle({
                Title = layer.label,
                Value = CFG[layer.cfgKey] == true,
                Flag = layer.cfgKey,
                Callback = function(value)
                    if State.ApplyingConfig or not State.UIReady then return end
                    CFG[layer.cfgKey] = (value == true)
                    updateDashboard()
                end,
            })
        end

        ResetLayersTab:Section({ Title = "Layer Readiness" })
        ResetLayersListParagraph = ResetLayersTab:Paragraph({
            Title = "All Reset Layers",
            Desc = "Loading...",
        })

        -- Tab 5: Configs
        local ConfigsTab = Window:Tab({ Title = "Configs", Icon = "save" })
        ConfigsTab:Section({ Title = "Config Status" })
        ConfigStatusParagraph = ConfigsTab:Paragraph({
            Title = "Config Manager",
            Desc = "Loading...",
        })

        ConfigsTab:Section({ Title = "Save & Load Configs" })
        ConfigNameInputWidget = ConfigsTab:Input({
            Title = "Config Name",
            Value = State.ConfigNameInput,
            Placeholder = "e.g. default, early_game, afk",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                State.ConfigNameInput = ConfigManager.cleanName(value)
            end,
        })

        local initialConfigSelected = (State.ConfigSelected ~= "" and table.find(State.SavedConfigs, State.ConfigSelected))
            and State.ConfigSelected or nil
        ConfigProfileDropdown = ConfigsTab:Dropdown({
            Title = "Saved Configs",
            Values = #State.SavedConfigs > 0 and State.SavedConfigs or { NO_CONFIGS_LABEL },
            Value = initialConfigSelected,
            AllowNone = true,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                if type(value) == "table" then value = value[1] end
                local selected = ""
                if type(value) == "string" and value ~= NO_CONFIGS_LABEL then
                    selected = ConfigManager.cleanName(value)
                end
                local prevSelected = State.ConfigSelected
                State.ConfigSelected = selected
                State.DeleteConfigConfirmId = ""
                State.DeleteConfigConfirmUntil = 0
                if selected ~= "" then
                    State.ConfigNameInput = selected
                    if ConfigNameInputWidget then
                        runWithApplyGuard(function()
                            pcall(function() ConfigNameInputWidget:Set(selected) end)
                        end)
                    end
                end
                if selected ~= prevSelected then
                    ConfigManager.saveIndex()
                end
                updateConfigStatusParagraph()
            end,
        })

        ConfigsTab:Button({
            Title = "Save Config",
            Callback = function()
                local target = State.ConfigNameInput ~= "" and State.ConfigNameInput or State.ConfigSelected
                local ok, res = ConfigManager.saveProfile(target)
                refreshConfigUI()
                updateDashboard()
                notify("Configs", ok and ("Saved config: " .. tostring(res)) or tostring(res), 3)
            end,
        })

        ConfigsTab:Button({
            Title = "Load Selected Config",
            Callback = function()
                local target = State.ConfigSelected ~= "" and State.ConfigSelected or State.ConfigNameInput
                local ok, res = ConfigManager.loadProfile(target)
                refreshConfigUI()
                notify("Configs", ok and ("Loaded config: " .. tostring(res)) or tostring(res), 3)
            end,
        })

        ConfigsTab:Button({
            Title = "Delete Selected Config (Double-Click Confirm)",
            Callback = function()
                local target = State.ConfigSelected ~= "" and State.ConfigSelected or State.ConfigNameInput
                local clean = ConfigManager.cleanName(target)
                if clean == "" then
                    notify("Configs", "Select a saved config to delete", 3)
                    return
                end
                local now = os.clock()
                if State.DeleteConfigConfirmId ~= clean or now > State.DeleteConfigConfirmUntil then
                    State.DeleteConfigConfirmId = clean
                    State.DeleteConfigConfirmUntil = now + 5
                    notify("Delete Config", "Click again within 5s to delete '" .. clean .. "'", 5)
                    return
                end
                State.DeleteConfigConfirmId = ""
                State.DeleteConfigConfirmUntil = 0
                local ok, res = ConfigManager.deleteProfile(clean)
                refreshConfigUI()
                updateDashboard()
                notify("Configs", ok and ("Deleted config: " .. tostring(res)) or tostring(res), 3)
            end,
        })

        ConfigsTab:Button({
            Title = "Refresh Config List",
            Callback = function()
                refreshConfigUI()
                notify("Configs", string.format("%d saved config(s) found", #State.SavedConfigs), 3)
            end,
        })

        ConfigsTab:Section({ Title = "Autoload on Startup" })
        AutoloadToggleWidget = ConfigsTab:Toggle({
            Title = "Enable Autoload on Startup",
            Value = State.AutoloadEnabled == true,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                local want = (value == true)
                if want then
                    local target = ConfigManager.cleanName(
                        State.AutoloadProfile ~= "" and State.AutoloadProfile or State.ConfigSelected
                    )
                    local ok, res = ConfigManager.setAutoload(true, target)
                    if not ok then
                        runWithApplyGuard(function()
                            pcall(function() AutoloadToggleWidget:Set(false) end)
                        end)
                        notify("Autoload", tostring(res), 4)
                    else
                        notify("Autoload", "Enabled autoload for: " .. tostring(res), 3)
                    end
                else
                    ConfigManager.setAutoload(false, State.AutoloadProfile, false)
                    notify("Autoload", "Autoload disabled", 3)
                end
                refreshConfigUI()
            end,
        })

        ConfigsTab:Button({
            Title = "Set Selected as Autoload",
            Callback = function()
                local target = State.ConfigSelected ~= "" and State.ConfigSelected or State.ConfigNameInput
                local ok, res = ConfigManager.setAutoload(true, target)
                refreshConfigUI()
                notify("Autoload", ok and ("Autoload set to: " .. tostring(res)) or tostring(res), 3)
            end,
        })

        ConfigsTab:Button({
            Title = "Clear Autoload",
            Callback = function()
                ConfigManager.setAutoload(false, "", true)
                refreshConfigUI()
                notify("Autoload", "Cleared autoload config", 3)
            end,
        })

        -- Tab 5: Misc
        local MiscTab = Window:Tab({ Title = "Misc", Icon = "compass" })
        MiscTab:Section({ Title = "Maneuverability & Range" })
        UIWidgets.AutoApproachNode = MiscTab:Toggle({
            Title = "Auto-Approach Out-of-Range Upgrades (>55 studs)",
            Value = CFG.AutoApproachNode,
            Flag = "AutoApproachNode",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.AutoApproachNode = (value == true)
            end,
        })
        UIWidgets.ApproachSettleDelay = MiscTab:Slider({
            Title = "Auto-TP Settle Delay (seconds)",
            Flag = "ApproachSettleDelay",
            Value = { Min = 0.03, Max = 0.30, Default = CFG.ApproachSettleDelay },
            Step = 0.01,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.ApproachSettleDelay = math.clamp(tonumber(value) or 0.08, 0.03, 0.30)
            end,
        })
        MiscTab:Button({
            Title = "Teleport to Nearest Affordable Upgrade",
            Callback = function()
                local ok, msg = MiscController.teleportToNearestAffordable()
                notify("Quick Move", tostring(msg), 3)
            end,
        })
        UIWidgets.MiscWalkSpeedEnabled = MiscTab:Toggle({
            Title = "Custom WalkSpeed",
            Value = CFG.MiscWalkSpeedEnabled,
            Flag = "MiscWalkSpeedEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscWalkSpeedEnabled = (value == true)
                pcall(MiscController.applyWalkSpeed)
            end,
        })
        UIWidgets.MiscWalkSpeed = MiscTab:Slider({
            Title = "WalkSpeed",
            Flag = "MiscWalkSpeed",
            Value = { Min = 16, Max = 200, Default = CFG.MiscWalkSpeed },
            Step = 2,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscWalkSpeed = math.clamp(tonumber(value) or 64, 16, 200)
                if CFG.MiscWalkSpeedEnabled then pcall(MiscController.applyWalkSpeed) end
            end,
        })
        UIWidgets.MiscJumpEnabled = MiscTab:Toggle({
            Title = "Custom Jump Boost",
            Value = CFG.MiscJumpEnabled,
            Flag = "MiscJumpEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscJumpEnabled = (value == true)
                pcall(MiscController.applyJump)
            end,
        })
        UIWidgets.MiscJumpHeight = MiscTab:Slider({
            Title = "Jump Height",
            Flag = "MiscJumpHeight",
            Value = { Min = 7.2, Max = 60, Default = CFG.MiscJumpHeight },
            Step = 1,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscJumpHeight = math.clamp(tonumber(value) or 18, 7.2, 60)
                if CFG.MiscJumpEnabled then pcall(MiscController.applyJump) end
            end,
        })
        UIWidgets.MiscInfJump = MiscTab:Toggle({
            Title = "Infinite Jump",
            Value = CFG.MiscInfJump,
            Flag = "MiscInfJump",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscInfJump = (value == true)
            end,
        })
        UIWidgets.MiscFlyEnabled = MiscTab:Toggle({
            Title = "Camera Flight (WASD + Space / Ctrl)",
            Value = CFG.MiscFlyEnabled,
            Flag = "MiscFlyEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscFlyEnabled = (value == true)
                if not CFG.MiscFlyEnabled then pcall(MiscController.cleanupFly) end
            end,
        })
        UIWidgets.MiscFlySpeed = MiscTab:Slider({
            Title = "Flight Speed",
            Flag = "MiscFlySpeed",
            Value = { Min = 20, Max = 250, Default = CFG.MiscFlySpeed },
            Step = 5,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscFlySpeed = math.clamp(tonumber(value) or 90, 20, 250)
            end,
        })
        UIWidgets.MiscNoclip = MiscTab:Toggle({
            Title = "Noclip",
            Value = CFG.MiscNoclip,
            Flag = "MiscNoclip",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscNoclip = (value == true)
                if not CFG.MiscNoclip then pcall(MiscController.cleanupNoclip) end
            end,
        })

        MiscTab:Section({ Title = "Quick Travel" })
        local districts = MiscController.getDistrictList()
        if State.SelectedDistrict == "" and #districts > 0 then
            State.SelectedDistrict = districts[1]
        end
        MiscTab:Dropdown({
            Title = "District Destination",
            Values = #districts > 0 and districts or { "Main Street (Money)" },
            Value = State.SelectedDistrict ~= "" and State.SelectedDistrict or nil,
            AllowNone = true,
            Callback = function(value)
                if type(value) == "table" then value = value[1] end
                State.SelectedDistrict = type(value) == "string" and value or ""
            end,
        })
        MiscTab:Button({
            Title = "Teleport to Selected District",
            Callback = function()
                local ok, msg = MiscController.teleportToDistrict(State.SelectedDistrict)
                notify("Travel", tostring(msg), 3)
            end,
        })
        MiscTab:Button({
            Title = "Return to Main Street (Spawn)",
            Callback = function()
                local ok, msg = MiscController.teleportToPosition(Vector3.new(0, 0, 40))
                notify("Travel", ok and "Returned to Main Street" or tostring(msg), 3)
            end,
        })

        MiscTab:Section({ Title = "Visibility & Lighting" })
        UIWidgets.MiscFullbright = MiscTab:Toggle({
            Title = "Fullbright (Midday + No Shadows)",
            Value = CFG.MiscFullbright,
            Flag = "MiscFullbright",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscFullbright = (value == true)
                pcall(MiscController.applyLighting)
            end,
        })
        UIWidgets.MiscNoFog = MiscTab:Toggle({
            Title = "No Fog & Clear Atmosphere",
            Value = CFG.MiscNoFog,
            Flag = "MiscNoFog",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscNoFog = (value == true)
                pcall(MiscController.applyNoFog)
            end,
        })
        UIWidgets.MiscNoPostEffects = MiscTab:Toggle({
            Title = "Disable Dark Post-Effects (HauntMood / Bloom / Blur)",
            Value = CFG.MiscNoPostEffects,
            Flag = "MiscNoPostEffects",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscNoPostEffects = (value == true)
                pcall(MiscController.applyPostEffects)
            end,
        })
        UIWidgets.MiscHeadlight = MiscTab:Toggle({
            Title = "Personal Headlight (60-stud Lantern)",
            Value = CFG.MiscHeadlight,
            Flag = "MiscHeadlight",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscHeadlight = (value == true)
                pcall(MiscController.applyHeadlight)
            end,
        })
        UIWidgets.MiscUnlockZoom = MiscTab:Toggle({
            Title = "Unlock Camera Max Zoom",
            Value = CFG.MiscUnlockZoom,
            Flag = "MiscUnlockZoom",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscUnlockZoom = (value == true)
                pcall(MiscController.applyCamera)
            end,
        })
        UIWidgets.MiscCameraMaxZoom = MiscTab:Slider({
            Title = "Max Zoom Distance",
            Flag = "MiscCameraMaxZoom",
            Value = { Min = 128, Max = 1000, Default = CFG.MiscCameraMaxZoom },
            Step = 25,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscCameraMaxZoom = math.clamp(tonumber(value) or 400, 128, 1000)
                if CFG.MiscUnlockZoom then pcall(MiscController.applyCamera) end
            end,
        })
        UIWidgets.MiscFOVEnabled = MiscTab:Toggle({
            Title = "Custom Field of View (FOV)",
            Value = CFG.MiscFOVEnabled,
            Flag = "MiscFOVEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscFOVEnabled = (value == true)
                pcall(MiscController.applyCamera)
            end,
        })
        UIWidgets.MiscFOV = MiscTab:Slider({
            Title = "Camera FOV",
            Flag = "MiscFOV",
            Value = { Min = 70, Max = 120, Default = CFG.MiscFOV },
            Step = 1,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscFOV = math.clamp(tonumber(value) or 85, 70, 120)
                if CFG.MiscFOVEnabled then pcall(MiscController.applyCamera) end
            end,
        })

        MiscTab:Section({ Title = "Performance & GPU Optimizer" })
        UIWidgets.MiscBlackScreen = MiscTab:Toggle({
            Title = "Black Screen (GPU Optimizer — Disables 3D Render)",
            Value = CFG.MiscBlackScreen,
            Flag = "MiscBlackScreen",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscBlackScreen = (value == true)
                pcall(MiscController.applyBlackScreen)
            end,
        })
        UIWidgets.MiscLowGraphics = MiscTab:Toggle({
            Title = "Low Graphics (Disable Particles / Trails / Shadows)",
            Value = CFG.MiscLowGraphics,
            Flag = "MiscLowGraphics",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscLowGraphics = (value == true)
                pcall(MiscController.applyLowGraphics)
            end,
        })
        UIWidgets.MiscGpuFpsCapEnabled = MiscTab:Toggle({
            Title = "Limit FPS (GPU Saver)",
            Value = CFG.MiscGpuFpsCapEnabled,
            Flag = "MiscGpuFpsCapEnabled",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscGpuFpsCapEnabled = (value == true)
                pcall(MiscController.applyGpuFpsCap)
            end,
        })
        UIWidgets.MiscGpuFpsCap = MiscTab:Slider({
            Title = "FPS Cap",
            Flag = "MiscGpuFpsCap",
            Value = { Min = 5, Max = 60, Default = CFG.MiscGpuFpsCap },
            Step = 1,
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscGpuFpsCap = math.clamp(math.floor(tonumber(value) or 15), 5, 60)
                if CFG.MiscGpuFpsCapEnabled then
                    pcall(MiscController.applyGpuFpsCap)
                end
            end,
        })

        MiscTab:Section({ Title = "Utility" })
        UIWidgets.MiscHideWatchers = MiscTab:Toggle({
            Title = "Hide Watchers",
            Value = CFG.MiscHideWatchers,
            Flag = "MiscHideWatchers",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscHideWatchers = (value == true)
                if CFG.MiscHideWatchers then pcall(MiscController.applyHideWatchers) end
            end,
        })
        UIWidgets.MiscAntiAfk = MiscTab:Toggle({
            Title = "Anti-AFK",
            Value = CFG.MiscAntiAfk,
            Flag = "MiscAntiAfk",
            Callback = function(value)
                if State.ApplyingConfig or not State.UIReady then return end
                CFG.MiscAntiAfk = (value == true)
            end,
        })

        -- Tab 6: Diagnostics
        local DiagTab = Window:Tab({ Title = "Diagnostics", Icon = "settings" })
        DiagTab:Section({ Title = "Runtime Diagnostics" })
        DiagnosticsParagraph = DiagTab:Paragraph({
            Title = "Engine Telemetry",
            Desc = "Loading...",
        })
        DiagTab:Button({
            Title = "Unload / Destroy Hub",
            Callback = function()
                if getgenv().UncannyUpgradePurchaser and type(getgenv().UncannyUpgradePurchaser.destroy) == "function" then
                    pcall(getgenv().UncannyUpgradePurchaser.destroy)
                end
            end,
        })

        refreshDropdownLists()
        updateDashboard()
    else
        SafeUtils.logStatus("windui_win_fail", "WindUI CreateWindow failed: " .. tostring(winObj), true)
    end
end

-- Attempt autoload after UI & TreeState initialization (works in both UI and headless mode).
local autoloaded, autoloadResult = ConfigManager.tryAutoload()
refreshConfigUI()
if autoloaded then
    notify("Configs", "Autoloaded config: " .. tostring(autoloadResult), 4)
elseif State.AutoloadEnabled then
    notify("Configs", "Autoload failed: " .. tostring(autoloadResult), 4)
end

-- Enable live widget callbacks only after WindUI creation and autoload settle.
task.delay(0.1, function()
    if State.Running then
        State.UIReady = true
    end
end)

-- Supervised UI refresh loop (1.0s cadence)
task.spawn(function()
    local mySerial = State.RunSerial
    while State.Running do
        if Window then
            pcall(updateDashboard)
        end
        task.wait(0.5)
        if mySerial ~= State.RunSerial and not State.Running then
            break
        end
    end
end)

-- Start background purchaser loop (stays idle unless AutoBuyEnabled was enabled via autoload or toggle)
UpgradePurchaser.start()

-- ── MODULE 6: PUBLIC EXPORT & CLEAN SHUTDOWN ──────────────────────────────────
getgenv().UncannyUpgradePurchaser = {
    CFG = CFG,
    State = State,
    SafeUtils = SafeUtils,
    TreeState = TreeState,
    PurchasePolicy = PurchasePolicy,
    UpgradePurchaser = UpgradePurchaser,
    ConfigManager = ConfigManager,
    ResetLayerController = ResetLayerController,
    MiscController = MiscController,
    refreshUI = function()
        syncWidgetsFromCFG()
        refreshDropdownLists()
        refreshConfigUI()
        updateDashboard()
    end,
    destroy = function()
        State.Running = false
        pcall(UpgradePurchaser.stop)
        pcall(MiscController.cleanup)
        SafeUtils.disconnectAll()
        if Window then
            pcall(function() Window:Destroy() end)
            Window = nil
        end
        if getgenv().__UncannyPurchaserWindow then
            pcall(function() getgenv().__UncannyPurchaserWindow:Destroy() end)
            getgenv().__UncannyPurchaserWindow = nil
        end
        getgenv().UncannyUpgradePurchaser = nil
    end,
}

print("[UpgradePurchaser] Ready — modular Upgrade Purchaser loaded (AutoBuyEnabled = " .. tostring(CFG.AutoBuyEnabled) .. ")")
