--[[
    Vibez's Upgrade Tree — Upgrade Autobuyer
    Author: olliE
    Modular state-driven upgrade autobuyer, reset layer controller,
    misc utilities, and JSON config manager with WindUI dashboard.
]]

--// =========================================================================
--// 1. LIFECYCLE & CLEAN RELOAD GUARD
--// =========================================================================

local GLOBAL_KEY = "VibezUpgradeAutobuyer"

local function getGlobalEnv()
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        return env
    end
    return _G
end

local GlobalEnv = getGlobalEnv()
if type(GlobalEnv[GLOBAL_KEY]) == "table" and type(GlobalEnv[GLOBAL_KEY].destroy) == "function" then
    pcall(GlobalEnv[GLOBAL_KEY].destroy)
end

--// =========================================================================
--// 2. SERVICES & SAFE UTILS
--// =========================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local SafeUtils = {}

function SafeUtils.safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "not a function"
    end
    local ok, a, b, c = pcall(fn, ...)
    return ok, a, b, c
end

function SafeUtils.safeFireClickDetector(cd, distance)
    if not cd or typeof(cd) ~= "Instance" or not cd:IsA("ClickDetector") then
        return false, "invalid ClickDetector"
    end
    if type(fireclickdetector) ~= "function" then
        return false, "fireclickdetector unavailable"
    end
    local ok, err = pcall(fireclickdetector, cd, distance or 0)
    return ok, err
end

function SafeUtils.safeFireServer(remote, ...)
    if not remote or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
        return false, "invalid RemoteEvent"
    end
    local ok, err = pcall(remote.FireServer, remote, ...)
    return ok, err
end

function SafeUtils.jsonEncode(tbl)
    local ok, res = pcall(HttpService.JSONEncode, HttpService, tbl)
    if ok and type(res) == "string" then
        return true, res
    end
    return false, res
end

function SafeUtils.jsonDecode(str)
    if type(str) ~= "string" or str == "" then
        return false, "empty json"
    end
    local ok, res = pcall(HttpService.JSONDecode, HttpService, str)
    if ok and type(res) == "table" then
        return true, res
    end
    return false, res
end

function SafeUtils.hasFS()
    return type(isfolder) == "function"
        and type(makefolder) == "function"
        and type(isfile) == "function"
        and type(readfile) == "function"
        and type(writefile) == "function"
        and type(listfiles) == "function"
end

function SafeUtils.ensureFolder(path)
    if not SafeUtils.hasFS() then
        return false
    end
    local okExists, exists = pcall(isfolder, path)
    if okExists and exists then
        return true
    end
    local okMake = pcall(makefolder, path)
    return okMake
end

function SafeUtils.readTextFile(path)
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        return false, nil
    end
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        return false, nil
    end
    local okRead, content = pcall(readfile, path)
    if okRead and type(content) == "string" then
        return true, content
    end
    return false, nil
end

function SafeUtils.writeTextFile(path, content)
    if type(writefile) ~= "function" then
        return false
    end
    local ok = pcall(writefile, path, content)
    return ok
end

function SafeUtils.deleteFile(path)
    if type(delfile) ~= "function" or type(isfile) ~= "function" then
        return false
    end
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        return true
    end
    local okDel = pcall(delfile, path)
    return okDel
end

function SafeUtils.shallowCopy(tbl)
    local out = {}
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do
            out[k] = v
        end
    end
    return out
end

function SafeUtils.deepCopy(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = SafeUtils.deepCopy(v)
    end
    return out
end

local SUFFIXES = {
    "", "k", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "O", "N", "De",
    "UDe", "DDe", "TDe", "QdDe", "QnDe", "SxDe", "SpDe", "OcDe", "NoDe",
    "Vt", "UVt", "DVt", "TVt", "QdVt", "QnVt", "SxVt", "SpVt", "OcVt", "NoVt",
    "Tg", "UTg", "DTg", "TTg", "QdTg", "QnTg", "SxTg", "SpTg", "OcTg", "NoTg",
}

function SafeUtils.formatNumber(n)
    if type(n) ~= "number" or n ~= n or n <= 0 then
        return "0"
    end
    if n == math.huge then
        return "INF"
    end
    if n < 100 then
        return (string.format("%.2f", n):gsub("%.00", ""))
    end
    if n < 1000 then
        return (string.format("%.1f", n):gsub("%.0", ""))
    end
    local tier = math.floor(math.log10(n) / 3)
    if tier + 1 > #SUFFIXES then
        local exp = math.floor(math.log10(n))
        return (string.format("%.2fe%d", n / (10 ^ exp), exp):gsub("%.00e", "e"))
    end
    local scaled = n / (10 ^ (tier * 3))
    return (string.format("%.1f%s", scaled, SUFFIXES[tier + 1]):gsub("%.0", ""))
end

function SafeUtils.formatDuration(seconds)
    local s = math.max(0, math.floor(tonumber(seconds) or 0))
    local m = math.floor(s / 60)
    local rem = s % 60
    if m > 0 then
        return string.format("%dm %02ds", m, rem)
    end
    return string.format("%ds", rem)
end

function SafeUtils.getGuiContainer()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then
            return hui
        end
    end
    return CoreGui
end

--// =========================================================================
--// 3. RUNTIME STATE, JANITOR & DEFAULT CONFIG
--// =========================================================================

local TREE_ORDER = {
    "Basic",
    "Rebirth",
    "Extra",
    "UselessRebirth",
    "Sacrifice",
    "Ascension",
    "Blackhole",
    "Halloween",
}

local RESET_LAYER_DEFS = {
    { id = "Rebirth", label = "Auto Rebirth", remote = "TriggerRebirth", isClickButton = false },
    { id = "Prestige", label = "Auto Prestige", remote = nil, isClickButton = true },
    { id = "Sacrifice", label = "Auto Sacrifice", remote = "TriggerSacrifice", isClickButton = false },
    { id = "Ascension", label = "Auto Ascension", remote = "TriggerAscension", isClickButton = false },
    { id = "DarkMatter", label = "Auto Dark Matter", remote = "DarkMatterRequest", isClickButton = false },
    { id = "Reboot", label = "Auto Reboot", remote = "RebootRequest", isClickButton = false },
    { id = "UselessRebirth", label = "Auto Useless Rebirth", remote = "TriggerUselessRebirth", isClickButton = false },
    { id = "Zombie", label = "Auto Zombify", remote = "ZombieRequest", isClickButton = false },
    { id = "Ghost", label = "Auto Ghost", remote = "GhostRequest", isClickButton = false },
    { id = "HalloweenLoop", label = "Auto Halloween Loop", remote = "HalloweenLoopRequest", isClickButton = false },
}

local TREE_BRANCH = {
    Basic = "Main",
    Rebirth = "Main",
    Sacrifice = "Main",
    Ascension = "Main",
    Blackhole = "Main",
    Extra = "Useless",
    UselessRebirth = "Useless",
    Halloween = "Halloween",
}

local RESET_BRANCH_ORDER = { "Main", "Useless", "Halloween" }

local RESET_BRANCH_PRIORITY = {
    Main = { "Reboot", "DarkMatter", "Ascension", "Sacrifice", "Prestige", "Rebirth" },
    Useless = { "UselessRebirth" },
    Halloween = { "HalloweenLoop", "Ghost", "Zombie" },
}

local LAYER_BRANCH = {
    Rebirth = "Main",
    Prestige = "Main",
    Sacrifice = "Main",
    Ascension = "Main",
    DarkMatter = "Main",
    Reboot = "Main",
    UselessRebirth = "Useless",
    Zombie = "Halloween",
    Ghost = "Halloween",
    HalloweenLoop = "Halloween",
}

local LAYER_REWARD_STAT = {
    Rebirth = "RebirthPoints",
    Prestige = "Prestige",
    Sacrifice = "Sacrifices",
    Ascension = "Ascensions",
    DarkMatter = "DarkMatter",
    Reboot = "Reboot",
    UselessRebirth = "UselessRebirthPoints",
    Zombie = "Zombies",
    Ghost = "Ghosts",
    HalloweenLoop = "HalloweenLoop",
}

local DEFAULT_CONFIG = {
    AutoBuyEnabled = false,
    ScanInterval = 0.15,
    MaxBuysPerTick = 10,
    Strategy = "Cheapest", -- "Cheapest", "Most Expensive", "Tree Order", "Nearest"
    CurrencyReservePct = 0,
    AllowRemoteClick = true,
    ClickRange = 115,
    AutoTP = false,
    ApproachSettleDelay = 0.08,
    ReturnToOrigin = true,
    EnabledTrees = {
        Basic = true,
        Rebirth = true,
        Extra = true,
        UselessRebirth = true,
        Sacrifice = true,
        Ascension = true,
        Blackhole = true,
        Halloween = true,
    },

    -- Reset Layers (ALL OFF BY DEFAULT)
    ResetTimerEnabled = true,
    ResetCountdownSeconds = 15,
    ResetCooldownSeconds = 3,
    ResetRequireBuySinceReset = true,
    ResetWaitUntilNoUpgrades = true,
    ResetLayers = {
        Rebirth = false,
        Prestige = false,
        Sacrifice = false,
        Ascension = false,
        DarkMatter = false,
        Reboot = false,
        UselessRebirth = false,
        Zombie = false,
        Ghost = false,
        HalloweenLoop = false,
    },

    -- Misc
    WalkSpeedEnabled = false,
    WalkSpeed = 32,
    JumpPowerEnabled = false,
    JumpPower = 60,
    InfiniteJump = false,
    FlightEnabled = false,
    FlightSpeed = 75,
    NoclipEnabled = false,
    Fullbright = false,
    NoFog = false,
    FOVEnabled = false,
    FOVValue = 90,
    UnlockMaxZoom = false,
    GpuOptimizer = false,
    FPSCapEnabled = false,
    FPSCap = 60,
    BlackScreen = false,
    AutoCollectAtoms = false,
    AtomCollectInterval = 0.5,
}

local Config = SafeUtils.deepCopy(DEFAULT_CONFIG)

local State = {
    Running = true,
    RunSerial = (tonumber(GlobalEnv.__VIBEZ_RUN_SERIAL) or 0) + 1,
    UIReady = false,
    ApplyingConfig = false,
    ApplySeq = 0,

    Connections = {},
    Overlays = {},
    Window = nil,

    LastUpgradeBoughtAt = os.clock(),
    LastUpgradeBoughtAtByBranch = {
        Main = os.clock(),
        Useless = os.clock(),
        Halloween = os.clock(),
    },
    LastBuyTickAt = 0,
    SessionBuys = 0,
    TotalTickRuns = 0,
    LastResetAt = 0,
    LastResetAtByBranch = {
        Main = 0,
        Useless = 0,
        Halloween = 0,
    },
    LastResetLayer = "None",
    LastActionMessage = "Idle (fail-closed on startup)",
    ActivityLog = {},

    NodeAttempts = {},
    Rates = {
        Points = 0,
        RebirthPoints = 0,
        Sacrifices = 0,
        Ascensions = 0,
        AscensionPoints = 0,
        Matter = 0,
        Pumpkins = 0,
    },

    OriginCFrame = nil,
    MovedByAutoTP = false,

    OriginalLighting = nil,
    OriginalFog = nil,
    OriginalFOV = nil,
    OriginalMaxZoom = nil,
    Original3DRender = true,
    BodyVelocity = nil,
    BodyGyro = nil,
    BlackScreenGui = nil,
}
GlobalEnv.__VIBEZ_RUN_SERIAL = State.RunSerial

local function trackConn(conn)
    if conn then
        table.insert(State.Connections, conn)
    end
    return conn
end

local function logActivity(msg)
    local stamp = os.date("%H:%M:%S")
    table.insert(State.ActivityLog, 1, string.format("[%s] %s", stamp, tostring(msg)))
    if #State.ActivityLog > 14 then
        table.remove(State.ActivityLog)
    end
    State.LastActionMessage = tostring(msg)
end

--// =========================================================================
--// 4. GAME STATE READER (LIVE DATA)
--// =========================================================================

local TREE_DEFS = {
    {
        id = "Basic",
        wsFolder = "Buttons",
        ownedFolder = "OwnedBasicButtons",
        boughtEvent = "BasicButtonBought",
        root = "Button1",
        excluded = {},
    },
    {
        id = "Rebirth",
        wsFolder = "RebirthButtons",
        ownedFolder = "OwnedRebirthButtons",
        boughtEvent = "RebirthButtonBought",
        root = "Button1",
        excluded = { RebirthButton = true, PrestigeButton1 = true },
    },
    {
        id = "Extra",
        wsFolder = "ExtraButtons",
        ownedFolder = "OwnedExtraButtons",
        boughtEvent = "ExtraButtonBought",
        root = "Button1",
        excluded = {},
    },
    {
        id = "UselessRebirth",
        wsFolder = "UselessRebirthButtons",
        ownedFolder = "OwnedUselessRebirthButtons",
        boughtEvent = "UselessRebirthButtonBought",
        root = "Button1",
        excluded = { UselessRebirthButton = true },
    },
    {
        id = "Sacrifice",
        wsFolder = "SacrificeButtons",
        ownedFolder = "OwnedSacrificeButtons",
        boughtEvent = "SacrificeButtonBought",
        root = "Button1",
        excluded = { SacrificeButton = true },
    },
    {
        id = "Ascension",
        wsFolder = "AscensionButtons",
        ownedFolder = "OwnedAscensionButtons",
        boughtEvent = "AscensionButtonBought",
        root = "Button1a",
        excluded = { AscensionButton = true },
    },
    {
        id = "Blackhole",
        wsFolder = "BlackholeButtons",
        ownedFolder = "OwnedBlackholeButtons",
        boughtEvent = "BlackholeButtonBought",
        root = "Button1at",
        excluded = { AscensionButton = true },
    },
    {
        id = "Halloween",
        wsFolder = "HalloweenButtons",
        ownedFolder = "OwnedHalloweenButtons",
        boughtEvent = "HalloweenButtonBought",
        root = "Button1p",
        excluded = {},
    },
}

local GameState = {}

local function getNumberStat(folder, name)
    if not folder then
        return 0
    end
    local obj = folder:FindFirstChild(name)
    if obj and obj:IsA("ValueBase") and type(obj.Value) == "number" then
        return obj.Value
    end
    return 0
end

local function getOwnedSet(folderName)
    local set = {}
    local f = LocalPlayer and LocalPlayer:FindFirstChild(folderName)
    if f then
        for _, child in ipairs(f:GetChildren()) do
            set[child.Name] = true
        end
    end
    return set
end

local function countSet(set)
    local n = 0
    for _ in pairs(set) do
        n += 1
    end
    return n
end

local function resolveCurrencyForButton(treeId, btnName)
    if treeId == "Basic" then
        return "Points"
    elseif treeId == "Rebirth" then
        return "RebirthPoints"
    elseif treeId == "Extra" then
        if string.find(btnName, "^UselessButton") or string.find(btnName, "^UslessButton") then
            return "UselessPoints"
        end
        return "Points"
    elseif treeId == "UselessRebirth" then
        return "UselessRebirthPoints"
    elseif treeId == "Sacrifice" then
        return "Sacrifices"
    elseif treeId == "Ascension" then
        if string.find(btnName, "ap") then
            return "AscensionPoints"
        elseif string.find(btnName, "a") then
            return "Ascensions"
        end
        return "Sacrifices"
    elseif treeId == "Blackhole" then
        local suffix = string.match(btnName, "^Button%d+(%a+)$")
        if suffix == "rt" then
            return "RebootTokens"
        elseif suffix == "at" then
            return "Atoms"
        elseif suffix == "m" then
            return "Matter"
        end
        return "DarkMatter"
    elseif treeId == "Halloween" then
        if string.find(btnName, "p") then
            return "Pumpkins"
        elseif string.find(btnName, "z") then
            return "Zombies"
        end
        return "Ghosts"
    end
    return "Points"
end

local function isResetTriggerName(treeDef, btnName)
    if treeDef.excluded[btnName] then
        return true
    end
    if string.find(btnName, "^PrestigeButton") then
        return true
    end
    return false
end

local function parseOrderNum(btnName)
    local num = string.match(btnName, "(%d+)")
    return tonumber(num) or 999999
end

local function readButtonTexts(model)
    local btnPart = model:FindFirstChild("Button")
    if not btnPart then
        return model.Name, ""
    end
    local sg = btnPart:FindFirstChild("SurfaceGui")
    local frame = sg and sg:FindFirstChild("Frame")
    if not frame then
        return model.Name, ""
    end
    local uName = frame:FindFirstChild("UpgradeName")
    local uNum = frame:FindFirstChild("UpgradeNumber")
    local title = (uName and uName:IsA("TextLabel") and uName.Text ~= "") and uName.Text or model.Name
    local numTag = (uNum and uNum:IsA("TextLabel")) and uNum.Text or ""
    return title, numTag
end

local function collectNextButtons(model, outSet)
    local bs = model:FindFirstChild("ButtonStuff")
    local nb = bs and bs:FindFirstChild("NextButtons")
    if not nb then
        return
    end
    for _, nv in ipairs(nb:GetChildren()) do
        if nv:IsA("ObjectValue") then
            local targetName = (nv.Value and nv.Value.Name) or nv.Name
            if type(targetName) == "string" and targetName ~= "" then
                outSet[targetName] = true
            end
        end
    end
end

function GameState:GetCurrencies()
    local ls = LocalPlayer and LocalPlayer:FindFirstChild("leaderstats")
    local hs = LocalPlayer and LocalPlayer:FindFirstChild("HiddenStats")
    return {
        Points = getNumberStat(ls, "Points"),
        Level = getNumberStat(ls, "Level"),
        RebirthPoints = getNumberStat(hs, "RebirthPoints"),
        Prestige = getNumberStat(hs, "Prestige"),
        Sacrifices = getNumberStat(hs, "Sacrifices"),
        Ascensions = getNumberStat(hs, "Ascensions"),
        AscensionPoints = getNumberStat(hs, "AscensionPoints"),
        UselessPoints = getNumberStat(hs, "UselessPoints"),
        UselessRebirthPoints = getNumberStat(hs, "UselessRebirthPoints"),
        Atoms = getNumberStat(hs, "Atoms"),
        Matter = getNumberStat(hs, "Matter"),
        DarkMatter = getNumberStat(hs, "DarkMatter"),
        Reboot = getNumberStat(hs, "Reboot"),
        RebootTokens = getNumberStat(hs, "RebootTokens"),
        Pumpkins = getNumberStat(hs, "Pumpkins"),
        Zombies = getNumberStat(hs, "Zombies"),
        Ghosts = getNumberStat(hs, "Ghosts"),
        HalloweenLoop = getNumberStat(hs, "HalloweenLoop"),
        XP = getNumberStat(hs, "XP"),
    }
end

function GameState:GetPlayerRoot()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then
        return nil
    end
    return char:FindFirstChild("HumanoidRootPart")
end

function GameState:GetSnapshot()
    local currencies = self:GetCurrencies()
    local hrp = self:GetPlayerRoot()
    local playerPos = hrp and hrp.Position or nil

    local ownedByTree = {}
    for _, def in ipairs(TREE_DEFS) do
        ownedByTree[def.id] = getOwnedSet(def.ownedFolder)
    end

    local gateOpen = {
        Basic = true,
        Rebirth = ownedByTree.Basic["Button10"] == true,
        Extra = true,
        UselessRebirth = ownedByTree.Extra["UselessButton20"] == true,
        Sacrifice = currencies.Prestige >= 5 or currencies.Sacrifices > 0 or countSet(ownedByTree.Sacrifice) > 0,
        Ascension = ownedByTree.Sacrifice["Button38"] == true or currencies.Ascensions > 0 or countSet(ownedByTree.Ascension) > 0,
        BlackholeMain = ownedByTree.Ascension["Button11a"] == true or currencies.Atoms > 0 or currencies.Matter > 0 or currencies.DarkMatter > 0,
        Halloween = true,
    }

    local nodes = {}
    local treeStats = {}

    for _, def in ipairs(TREE_DEFS) do
        local wsFolder = Workspace:FindFirstChild(def.wsFolder)
        local ownedSet = ownedByTree[def.id]
        local unlockedSet = {}
        local rtUnlockedSet = {}

        if wsFolder then
            for _, model in ipairs(wsFolder:GetChildren()) do
                if ownedSet[model.Name] and not isResetTriggerName(def, model.Name) then
                    if def.id == "Blackhole" then
                        if string.match(model.Name, "^Button%d+rt$") then
                            collectNextButtons(model, rtUnlockedSet)
                        else
                            collectNextButtons(model, unlockedSet)
                        end
                    else
                        collectNextButtons(model, unlockedSet)
                    end
                end
            end
        end

        -- Cross-tree unlock rules verified from game controllers
        if def.id == "Basic" then
            if ownedByTree.Rebirth["Button6"] then
                unlockedSet["Button11"] = true
            end
            if currencies.Reboot >= 4 then
                unlockedSet["Button18"] = true
            end
        elseif def.id == "Rebirth" then
            if currencies.Reboot >= 4 then
                unlockedSet["Button21"] = true
            end
        elseif def.id == "Sacrifice" then
            if ownedByTree.Ascension["Button12ap"] then
                unlockedSet["Button39"] = true
            end
        end

        local totalUpgrades = 0
        local ownedUpgrades = 0
        local unlockedUpgrades = 0

        if wsFolder then
            for _, model in ipairs(wsFolder:GetChildren()) do
                if not isResetTriggerName(def, model.Name) then
                    local bs = model:FindFirstChild("ButtonStuff")
                    local priceObj = bs and bs:FindFirstChild("Price")
                    local cd = model:FindFirstChildOfClass("ClickDetector")
                    local btnPart = model:FindFirstChild("Button")
                    if priceObj and priceObj:IsA("ValueBase") and cd then
                        totalUpgrades += 1
                        local isOwned = ownedSet[model.Name] == true
                        if isOwned then
                            ownedUpgrades += 1
                        end

                        local isUnlocked = false
                        if not isOwned then
                            if def.id == "Blackhole" then
                                local rtNum = tonumber(string.match(model.Name, "^Button(%d+)rt$"))
                                if rtNum then
                                    if rtNum <= 4 then
                                        isUnlocked = (currencies.Reboot >= 6) or (rtUnlockedSet[model.Name] == true)
                                    else
                                        isUnlocked = (rtUnlockedSet[model.Name] == true)
                                    end
                                elseif gateOpen.BlackholeMain then
                                    isUnlocked = (model.Name == def.root) or (unlockedSet[model.Name] == true)
                                end
                            else
                                if gateOpen[def.id] then
                                    isUnlocked = (model.Name == def.root) or (unlockedSet[model.Name] == true)
                                end
                            end
                        end

                        if isUnlocked then
                            unlockedUpgrades += 1
                        end

                        local pos = btnPart and btnPart.Position or nil
                        local dist = (pos and playerPos) and (pos - playerPos).Magnitude or 0
                        local title, numTag = readButtonTexts(model)

                        table.insert(nodes, {
                            key = def.id .. ":" .. model.Name,
                            treeId = def.id,
                            name = model.Name,
                            title = title,
                            numTag = numTag,
                            price = tonumber(priceObj.Value) or 0,
                            currency = resolveCurrencyForButton(def.id, model.Name),
                            owned = isOwned,
                            unlocked = isUnlocked,
                            isResetTrigger = false,
                            clickDetector = cd,
                            position = pos,
                            distance = dist,
                            orderNum = parseOrderNum(model.Name),
                        })
                    end
                end
            end
        end

        treeStats[def.id] = {
            total = totalUpgrades,
            owned = ownedUpgrades,
            unlocked = unlockedUpgrades,
            gateOpen = (def.id == "Blackhole") and (gateOpen.BlackholeMain or currencies.Reboot >= 6) or (gateOpen[def.id] == true),
        }
    end

    return {
        currencies = currencies,
        ownedByTree = ownedByTree,
        gateOpen = gateOpen,
        nodes = nodes,
        treeStats = treeStats,
        playerPos = playerPos,
    }
end

--// =========================================================================
--// 5. PURCHASE POLICY (PURE EVALUATOR)
--// =========================================================================

local PurchasePolicy = {}

local function isBlockedByAttempt(attempts, key, now)
    local rec = attempts[key]
    if not rec then
        return false, "none"
    end
    if rec.pendingVerify and (now - (rec.lastAttemptAt or 0)) < 0.35 then
        return true, "pending"
    end
    if rec.nextRetryAt and now < rec.nextRetryAt then
        return true, "backoff"
    end
    return false, "ready"
end

function PurchasePolicy.Evaluate(snapshot, cfg, attempts, now)
    now = now or os.clock()
    local reservePct = math.clamp(tonumber(cfg.CurrencyReservePct) or 0, 0, 99)
    local clickRange = math.max(10, tonumber(cfg.ClickRange) or 115)
    local allowRemote = cfg.AllowRemoteClick == true

    local budget = {}
    for currName, bal in pairs(snapshot.currencies) do
        if type(bal) == "number" then
            budget[currName] = bal * (1 - reservePct / 100)
        end
    end

    local eligible = {}
    local blockedCount = 0
    local unaffordableCount = 0

    for _, node in ipairs(snapshot.nodes) do
        if not node.owned and not node.isResetTrigger and node.unlocked then
            if cfg.EnabledTrees[node.treeId] then
                local blocked = isBlockedByAttempt(attempts, node.key, now)
                if blocked then
                    blockedCount += 1
                else
                    local bal = budget[node.currency] or 0
                    if node.price == 0 or bal >= node.price then
                        table.insert(eligible, node)
                    else
                        unaffordableCount += 1
                    end
                end
            end
        end
    end

    local strategy = cfg.Strategy or "Cheapest"
    table.sort(eligible, function(a, b)
        if strategy == "Most Expensive" then
            if a.price ~= b.price then
                return a.price > b.price
            end
        elseif strategy == "Tree Order" then
            if a.treeId ~= b.treeId then
                return a.treeId < b.treeId
            end
            if a.orderNum ~= b.orderNum then
                return a.orderNum < b.orderNum
            end
        elseif strategy == "Nearest" then
            if math.abs(a.distance - b.distance) > 1 then
                return a.distance < b.distance
            end
        else -- "Cheapest"
            if a.price ~= b.price then
                return a.price < b.price
            end
        end
        if a.orderNum ~= b.orderNum then
            return a.orderNum < b.orderNum
        end
        return a.key < b.key
    end)

    local nearby = {}
    local far = {}

    for _, node in ipairs(eligible) do
        local rem = budget[node.currency] or 0
        if node.price == 0 or rem >= node.price then
            if node.price > 0 then
                budget[node.currency] = rem - node.price
            end
            if allowRemote or node.distance <= clickRange then
                table.insert(nearby, node)
            else
                table.insert(far, node)
            end
        end
    end

    return {
        nearby = nearby,
        far = far,
        totalEligible = #eligible,
        blockedCount = blockedCount,
        unaffordableCount = unaffordableCount,
    }
end

--// =========================================================================
--// 6. UPGRADE AUTOBUYER ENGINE
--// =========================================================================

local UpgradeAutobuyer = {}

function UpgradeAutobuyer:ReconcileAttempts(snapshot, now)
    for _, node in ipairs(snapshot.nodes) do
        local rec = State.NodeAttempts[node.key]
        if rec then
            if node.owned then
                State.NodeAttempts[node.key] = nil
            elseif rec.pendingVerify and (now - (rec.lastAttemptAt or 0)) >= 0.45 then
                rec.pendingVerify = false
                rec.fails = (rec.fails or 0) + 1
                local delay = math.min(5.0, 0.6 * (2 ^ (rec.fails - 1)))
                rec.nextRetryAt = now + delay
            end
        end
    end
end

function UpgradeAutobuyer:ClearBackoff()
    State.NodeAttempts = {}
    logActivity("Cleared pending/backoff table")
end

function UpgradeAutobuyer:FireNode(node, now)
    local cd = node.clickDetector
    if not cd or not cd.Parent then
        return false
    end
    local ok = SafeUtils.safeFireClickDetector(cd, 0)
    if ok then
        local prev = State.NodeAttempts[node.key]
        State.NodeAttempts[node.key] = {
            pendingVerify = true,
            lastAttemptAt = now,
            fails = prev and prev.fails or 0,
            nextRetryAt = nil,
        }
    end
    return ok
end

function UpgradeAutobuyer:Step(isManual)
    if not State.Running then
        return 0
    end
    local mySerial = State.RunSerial
    local now = os.clock()
    local snapshot = GameState:GetSnapshot()
    self:ReconcileAttempts(snapshot, now)

    local plan = PurchasePolicy.Evaluate(snapshot, Config, State.NodeAttempts, now)
    local maxBuys = math.max(1, math.floor(tonumber(Config.MaxBuysPerTick) or 10))
    local fired = 0

    for _, node in ipairs(plan.nearby) do
        if not State.Running or State.RunSerial ~= mySerial or fired >= maxBuys then
            break
        end
        if self:FireNode(node, now) then
            fired += 1
            logActivity(string.format("Buy [%s] %s (%s)", node.treeId, node.title, node.price == 0 and "Free" or SafeUtils.formatNumber(node.price)))
        end
    end

    if fired == 0 and Config.AutoTP and #plan.far > 0 and State.Running and State.RunSerial == mySerial then
        local target = plan.far[1]
        local hrp = GameState:GetPlayerRoot()
        if hrp and target.position then
            if not State.MovedByAutoTP then
                State.OriginCFrame = hrp.CFrame
                State.MovedByAutoTP = true
            end
            hrp.CFrame = CFrame.new(target.position + Vector3.new(0, 4, 0))
            local settle = math.clamp(tonumber(Config.ApproachSettleDelay) or 0.08, 0, 0.5)
            if settle > 0 then
                task.wait(settle)
            end
            if State.Running and State.RunSerial == mySerial and (isManual or Config.AutoBuyEnabled) then
                if self:FireNode(target, os.clock()) then
                    fired += 1
                    logActivity(string.format("TP+Buy [%s] %s", target.treeId, target.title))
                end
            end
        end
    elseif #plan.far == 0 and State.MovedByAutoTP then
        if Config.ReturnToOrigin and State.OriginCFrame then
            local hrp = GameState:GetPlayerRoot()
            if hrp then
                hrp.CFrame = State.OriginCFrame
            end
        end
        State.OriginCFrame = nil
        State.MovedByAutoTP = false
    end

    State.LastBuyTickAt = now
    State.TotalTickRuns += 1
    return fired
end

function UpgradeAutobuyer:BuyOnce()
    return self:Step(true)
end

--// =========================================================================
--// 7. RESET LAYER CONTROLLER
--// =========================================================================

local ResetLayerController = {
    LastLayerFireAt = {},
    LayerAttempts = {},
}

function ResetLayerController:ClearLayerBackoff()
    self.LayerAttempts = {}
end

function ResetLayerController:CanTriggerLayer(layerId, snapshot)
    local c = snapshot.currencies
    local o = snapshot.ownedByTree

    if layerId == "Rebirth" then
        return o.Basic["Button10"] == true and c.Points >= 100000
    elseif layerId == "Prestige" then
        if o.Basic["Button10"] ~= true or c.Prestige >= 5 then
            return false
        end
        local rb = Workspace:FindFirstChild("RebirthButtons")
        local pb1 = rb and rb:FindFirstChild("PrestigeButton1")
        local bs = pb1 and pb1:FindFirstChild("ButtonStuff")
        local priceObj = bs and bs:FindFirstChild("Price")
        local cd = pb1 and pb1:FindFirstChildOfClass("ClickDetector")
        if priceObj and cd then
            return c.RebirthPoints >= (tonumber(priceObj.Value) or math.huge)
        end
        return false
    elseif layerId == "Sacrifice" then
        return c.Prestige >= 5
    elseif layerId == "Ascension" then
        return o.Sacrifice["Button38"] == true and c.Prestige >= 5 and c.Sacrifices >= 2500000
    elseif layerId == "DarkMatter" then
        return (o.Blackhole["Button11m"] == true or c.DarkMatter > 0) and c.Matter > 0
    elseif layerId == "Reboot" then
        local requiredDM = 10
        if c.Reboot >= 8 then
            requiredDM = 100
        elseif c.Reboot == 7 then
            requiredDM = 75
        elseif c.Reboot == 6 then
            requiredDM = 50
        elseif c.Reboot == 5 then
            requiredDM = 25
        end
        return c.DarkMatter >= requiredDM
    elseif layerId == "UselessRebirth" then
        return o.Extra["UselessButton20"] == true and c.UselessPoints >= 10000000
    elseif layerId == "Zombie" then
        return (o.Halloween["Button15p"] == true or c.Zombies > 0) and c.Pumpkins >= 1000000000
    elseif layerId == "Ghost" then
        return (o.Halloween["Button11z"] == true or c.Ghosts > 0) and c.Zombies >= 500
    elseif layerId == "HalloweenLoop" then
        return (o.Halloween["Button31g"] == true or c.HalloweenLoop > 0) and c.Ghosts > 0
    end
    return false
end

function ResetLayerController:ReconcileLayerAttempts(snapshot, now)
    now = now or os.clock()
    for layerId, rec in pairs(self.LayerAttempts) do
        local statName = LAYER_REWARD_STAT[layerId]
        local currVal = statName and snapshot.currencies[statName] or nil
        if type(currVal) == "number" and currVal > (rec.prevStat or 0) then
            self.LayerAttempts[layerId] = nil
            local branch = LAYER_BRANCH[layerId]
            if branch then
                State.LastResetAtByBranch[branch] = now
                for key, _ in pairs(State.NodeAttempts) do
                    local treeId = string.match(key, "^([^:]+):")
                    if treeId and TREE_BRANCH[treeId] == branch then
                        State.NodeAttempts[key] = nil
                    end
                end
            end
        elseif rec.pending and (now - (rec.firedAt or 0)) >= 0.4 then
            rec.pending = false
            rec.fails = (rec.fails or 0) + 1
            local delay = math.min(4.0, 0.5 * (2 ^ (rec.fails - 1)))
            rec.nextRetryAt = now + delay
        end
    end
end

function ResetLayerController:IsLayerBlocked(layerId, now)
    local rec = self.LayerAttempts[layerId]
    if not rec then
        return false
    end
    if rec.pending and (now - (rec.firedAt or 0)) < 0.4 then
        return true
    end
    if rec.nextRetryAt and now < rec.nextRetryAt then
        return true
    end
    return false
end

function ResetLayerController:FireLayer(layerId, snapshot)
    local now = os.clock()
    local statName = LAYER_REWARD_STAT[layerId]
    local prevStat = 0
    if snapshot and statName and type(snapshot.currencies[statName]) == "number" then
        prevStat = snapshot.currencies[statName]
    else
        local cur = GameState:GetCurrencies()
        if statName and type(cur[statName]) == "number" then
            prevStat = cur[statName]
        end
    end

    local ok = false
    if layerId == "Prestige" then
        local rb = Workspace:FindFirstChild("RebirthButtons")
        local pb1 = rb and rb:FindFirstChild("PrestigeButton1")
        local cd = pb1 and pb1:FindFirstChildOfClass("ClickDetector")
        if cd then
            ok = SafeUtils.safeFireClickDetector(cd, 0)
        end
    else
        local events = ReplicatedStorage:FindFirstChild("Events")
        local remoteName = nil
        for _, def in ipairs(RESET_LAYER_DEFS) do
            if def.id == layerId then
                remoteName = def.remote
                break
            end
        end
        local rem = events and remoteName and events:FindFirstChild(remoteName)
        if rem and rem:IsA("RemoteEvent") then
            ok = SafeUtils.safeFireServer(rem)
        end
    end

    if ok then
        State.LastResetAt = now
        State.LastResetLayer = layerId
        self.LastLayerFireAt[layerId] = now
        local branch = LAYER_BRANCH[layerId]
        if branch then
            State.LastResetAtByBranch[branch] = now
        end
        local prevRec = self.LayerAttempts[layerId]
        self.LayerAttempts[layerId] = {
            pending = true,
            firedAt = now,
            prevStat = prevStat,
            fails = prevRec and prevRec.fails or 0,
            nextRetryAt = nil,
        }
        logActivity("Triggered Reset Layer: " .. layerId)
    end
    return ok
end

function ResetLayerController:GetCountdownRemaining(now, branch)
    now = now or os.clock()
    if not Config.ResetTimerEnabled then
        return 0
    end
    local waitSec = math.max(0, tonumber(Config.ResetCountdownSeconds) or 0)
    local anchor = branch and (State.LastUpgradeBoughtAtByBranch[branch] or State.LastUpgradeBoughtAt) or State.LastUpgradeBoughtAt
    local lastReset = branch and (State.LastResetAtByBranch[branch] or 0) or State.LastResetAt
    if not Config.ResetRequireBuySinceReset and lastReset > anchor then
        anchor = lastReset
    end
    local elapsed = now - anchor
    return math.max(0, waitSec - elapsed)
end

function ResetLayerController:Step()
    if not State.Running then
        return
    end
    local anyEnabled = false
    for _, def in ipairs(RESET_LAYER_DEFS) do
        if Config.ResetLayers[def.id] then
            anyEnabled = true
            break
        end
    end
    if not anyEnabled then
        return
    end

    local now = os.clock()
    local snapshot = GameState:GetSnapshot()
    self:ReconcileLayerAttempts(snapshot, now)

    local eligibleByBranch = { Main = 0, Useless = 0, Halloween = 0 }
    if Config.ResetWaitUntilNoUpgrades then
        local plan = PurchasePolicy.Evaluate(snapshot, Config, State.NodeAttempts, now)
        for _, node in ipairs(plan.nearby) do
            local b = TREE_BRANCH[node.treeId]
            if b then
                eligibleByBranch[b] = (eligibleByBranch[b] or 0) + 1
            end
        end
        for _, node in ipairs(plan.far) do
            local b = TREE_BRANCH[node.treeId]
            if b then
                eligibleByBranch[b] = (eligibleByBranch[b] or 0) + 1
            end
        end
    end

    local cooldown = math.max(0, tonumber(Config.ResetCooldownSeconds) or 3)
    for _, branch in ipairs(RESET_BRANCH_ORDER) do
        local branchList = RESET_BRANCH_PRIORITY[branch]
        local branchEnabled = false
        for _, layerId in ipairs(branchList) do
            if Config.ResetLayers[layerId] then
                branchEnabled = true
                break
            end
        end

        if branchEnabled then
            local branchReady = true
            if self:GetCountdownRemaining(now, branch) > 0 then
                branchReady = false
            elseif Config.ResetRequireBuySinceReset and (State.LastUpgradeBoughtAtByBranch[branch] or 0) <= (State.LastResetAtByBranch[branch] or 0) then
                branchReady = false
            elseif Config.ResetWaitUntilNoUpgrades and (eligibleByBranch[branch] or 0) > 0 then
                branchReady = false
            end

            if branchReady then
                for _, layerId in ipairs(branchList) do
                    if Config.ResetLayers[layerId] then
                        local lastFire = self.LastLayerFireAt[layerId] or 0
                        if (now - lastFire) >= cooldown
                            and not self:IsLayerBlocked(layerId, now)
                            and self:CanTriggerLayer(layerId, snapshot)
                        then
                            self:FireLayer(layerId, snapshot)
                            break
                        end
                    end
                end
            end
        end
    end
end

--// =========================================================================
--// 8. MISC CONTROLLER (MOVEMENT, VISUALS, OPTIMIZER, BLACK SCREEN)
--// =========================================================================

local MiscController = {}

local function ensureOriginalVisuals()
    if not State.OriginalLighting then
        State.OriginalLighting = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
        }
    end
    if not State.OriginalFog then
        State.OriginalFog = {
            FogEnd = Lighting.FogEnd,
            FogStart = Lighting.FogStart,
        }
    end
    local cam = Workspace.CurrentCamera
    if cam and not State.OriginalFOV then
        State.OriginalFOV = cam.FieldOfView
    end
    if LocalPlayer and not State.OriginalMaxZoom then
        State.OriginalMaxZoom = LocalPlayer.CameraMaxZoomDistance
    end
end

function MiscController:SetBlackScreen(enabled)
    Config.BlackScreen = enabled == true
    if Config.BlackScreen then
        pcall(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        if not State.BlackScreenGui or not State.BlackScreenGui.Parent then
            local sg = Instance.new("ScreenGui")
            sg.Name = "VibezBlackScreenOverlay"
            sg.IgnoreGuiInset = true
            sg.ResetOnSpawn = false
            sg.DisplayOrder = 999999

            local bg = Instance.new("Frame")
            bg.Name = "Backdrop"
            bg.Size = UDim2.fromScale(1, 1)
            bg.BackgroundColor3 = Color3.new(0, 0, 0)
            bg.BorderSizePixel = 0
            bg.Parent = sg

            local btn = Instance.new("TextButton")
            btn.Name = "DisableBtn"
            btn.Size = UDim2.fromOffset(260, 54)
            btn.Position = UDim2.fromScale(0.5, 0.5)
            btn.AnchorPoint = Vector2.new(0.5, 0.5)
            btn.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
            btn.TextColor3 = Color3.fromRGB(240, 240, 245)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 18
            btn.Text = "Disable Black Screen"
            btn.Parent = bg

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 10)
            corner.Parent = btn

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(90, 90, 110)
            stroke.Thickness = 1.5
            stroke.Parent = btn

            trackConn(btn.MouseButton1Click:Connect(function()
                self:SetBlackScreen(false)
            end))

            sg.Parent = SafeUtils.getGuiContainer()
            State.BlackScreenGui = sg
            table.insert(State.Overlays, sg)
        end
        State.BlackScreenGui.Enabled = true
    else
        pcall(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        if State.BlackScreenGui then
            State.BlackScreenGui.Enabled = false
        end
    end
end

function MiscController:ApplyFPSCap()
    if type(setfpscap) ~= "function" then
        return
    end
    if Config.FPSCapEnabled then
        pcall(setfpscap, math.clamp(tonumber(Config.FPSCap) or 60, 10, 240))
    else
        pcall(setfpscap, 0)
    end
end

function MiscController:ApplyGpuOptimizer(enabled)
    Config.GpuOptimizer = enabled == true
    if enabled then
        pcall(function()
            Lighting.GlobalShadows = false
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("ParticleEmitter") or d:IsA("Trail") then
                    d.Enabled = false
                end
            end
        end)
    else
        if State.OriginalLighting then
            pcall(function()
                Lighting.GlobalShadows = State.OriginalLighting.GlobalShadows
            end)
        end
    end
end

function MiscController:TeleportToZone(zoneName)
    local hrp = GameState:GetPlayerRoot()
    if not hrp then
        return false
    end
    local tpFolder = Workspace:FindFirstChild("TeleportParts")
    local target = nil
    if zoneName == "Spawn" then
        target = tpFolder and tpFolder:FindFirstChild("TeleportPartSpawn") or Workspace:FindFirstChild("SpawnLocation")
    elseif zoneName == "Halloween" then
        target = tpFolder and tpFolder:FindFirstChild("TeleportPartHalloween")
    elseif zoneName == "Blackhole" then
        target = tpFolder and tpFolder:FindFirstChild("TeleportPartBlackhole")
    elseif zoneName == "Rebirth" then
        local f = Workspace:FindFirstChild("RebirthButtons")
        local b = f and f:FindFirstChild("Button1")
        target = b and b:FindFirstChild("Button")
    elseif zoneName == "Sacrifice" then
        local f = Workspace:FindFirstChild("SacrificeButtons")
        local b = f and f:FindFirstChild("Button1")
        target = b and b:FindFirstChild("Button")
    elseif zoneName == "Ascension" then
        local f = Workspace:FindFirstChild("AscensionButtons")
        local b = f and f:FindFirstChild("Button1a")
        target = b and b:FindFirstChild("Button")
    elseif zoneName == "Extra" then
        local f = Workspace:FindFirstChild("ExtraButtons")
        local b = f and f:FindFirstChild("Button1")
        target = b and b:FindFirstChild("Button")
    end

    if target and target:IsA("BasePart") then
        hrp.CFrame = target.CFrame + Vector3.new(0, 4, 0)
        logActivity("Teleported to " .. zoneName)
        return true
    end
    logActivity("Zone not streamed/unlocked: " .. zoneName)
    return false
end

function MiscController:ClearFlight()
    if State.BodyVelocity then
        pcall(State.BodyVelocity.Destroy, State.BodyVelocity)
        State.BodyVelocity = nil
    end
    if State.BodyGyro then
        pcall(State.BodyGyro.Destroy, State.BodyGyro)
        State.BodyGyro = nil
    end
end

function MiscController:RestoreAll()
    self:SetBlackScreen(false)
    self:ClearFlight()
    if type(setfpscap) == "function" then
        pcall(setfpscap, 0)
    end
    if State.OriginalLighting then
        pcall(function()
            Lighting.Brightness = State.OriginalLighting.Brightness
            Lighting.ClockTime = State.OriginalLighting.ClockTime
            Lighting.GlobalShadows = State.OriginalLighting.GlobalShadows
            Lighting.Ambient = State.OriginalLighting.Ambient
            Lighting.OutdoorAmbient = State.OriginalLighting.OutdoorAmbient
        end)
    end
    if State.OriginalFog then
        pcall(function()
            Lighting.FogEnd = State.OriginalFog.FogEnd
            Lighting.FogStart = State.OriginalFog.FogStart
        end)
    end
    local cam = Workspace.CurrentCamera
    if cam and State.OriginalFOV then
        pcall(function()
            cam.FieldOfView = State.OriginalFOV
        end)
    end
    if LocalPlayer and State.OriginalMaxZoom then
        pcall(function()
            LocalPlayer.CameraMaxZoomDistance = State.OriginalMaxZoom
        end)
    end
end

function MiscController:StartLoops()
    ensureOriginalVisuals()

    trackConn(UserInputService.JumpRequest:Connect(function()
        if not State.Running or not Config.InfiniteJump then
            return
        end
        local char = LocalPlayer and LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))

    trackConn(RunService.Heartbeat:Connect(function()
        if not State.Running then
            return
        end
        local char = LocalPlayer and LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hum then
            if Config.WalkSpeedEnabled then
                hum.WalkSpeed = math.clamp(tonumber(Config.WalkSpeed) or 16, 16, 250)
            end
            if Config.JumpPowerEnabled then
                hum.UseJumpPower = true
                hum.JumpPower = math.clamp(tonumber(Config.JumpPower) or 50, 50, 300)
            end
        end

        if Config.Fullbright then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        end
        if Config.NoFog then
            Lighting.FogEnd = 100000
            Lighting.FogStart = 100000
        end
        local cam = Workspace.CurrentCamera
        if cam and Config.FOVEnabled then
            cam.FieldOfView = math.clamp(tonumber(Config.FOVValue) or 70, 50, 120)
        end
        if LocalPlayer and Config.UnlockMaxZoom then
            LocalPlayer.CameraMaxZoomDistance = 1000
        end

        if Config.FlightEnabled and hrp and cam then
            if not State.BodyVelocity or State.BodyVelocity.Parent ~= hrp then
                self:ClearFlight()
                local bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                bv.Velocity = Vector3.zero
                bv.Parent = hrp
                State.BodyVelocity = bv

                local bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                bg.P = 9e4
                bg.Parent = hrp
                State.BodyGyro = bg
            end
            local move = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                move += cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                move -= cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                move -= cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                move += cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                move += Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                move -= Vector3.new(0, 1, 0)
            end
            local speed = math.clamp(tonumber(Config.FlightSpeed) or 75, 16, 400)
            State.BodyVelocity.Velocity = (move.Magnitude > 0) and (move.Unit * speed) or Vector3.zero
            State.BodyGyro.CFrame = cam.CFrame
        elseif State.BodyVelocity then
            self:ClearFlight()
        end
    end))

    trackConn(RunService.Stepped:Connect(function()
        if not State.Running or not Config.NoclipEnabled then
            return
        end
        local char = LocalPlayer and LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end))

    -- Optional Blackhole Atom Collector loop
    task.spawn(function()
        local mySerial = State.RunSerial
        while State.Running and State.RunSerial == mySerial do
            local interval = math.clamp(tonumber(Config.AtomCollectInterval) or 0.5, 0, 2.0)
            if Config.AutoCollectAtoms then
                local ownedAsc = LocalPlayer and LocalPlayer:FindFirstChild("OwnedAscensionButtons")
                if ownedAsc and ownedAsc:FindFirstChild("Button11a") then
                    local events = ReplicatedStorage:FindFirstChild("Events")
                    local collectAtom = events and events:FindFirstChild("CollectAtom")
                    if collectAtom then
                        SafeUtils.safeFireServer(collectAtom)
                    end
                end
            end
            task.wait(interval)
        end
    end)
end

--// =========================================================================
--// 9. CONFIG MANAGER (JSON SAVE / LOAD / DELETE / AUTOLOAD)
--// =========================================================================

local ConfigManager = {
    Folder = "VibezUpgradeAutobuyerConfigs",
    AutoloadFile = "VibezUpgradeAutobuyerConfigs/_autoload.json",
    WidgetRefreshers = {},
}

function ConfigManager:SanitizeName(name)
    local clean = tostring(name or ""):gsub("[^%w%-%_]", "")
    return clean
end

function ConfigManager:GetConfigPath(name)
    return self.Folder .. "/" .. self:SanitizeName(name) .. ".json"
end

function ConfigManager:ListConfigs()
    if not SafeUtils.ensureFolder(self.Folder) then
        return {}
    end
    local okList, files = pcall(listfiles, self.Folder)
    if not okList or type(files) ~= "table" then
        return {}
    end
    local out = {}
    for _, fullPath in ipairs(files) do
        local normalized = tostring(fullPath):gsub("\\", "/")
        local fileName = normalized:match("([^/]+)$") or normalized
        local cfgName = fileName:match("^(.+)%.json$")
        if cfgName and cfgName ~= "_autoload" then
            table.insert(out, cfgName)
        end
    end
    table.sort(out)
    return out
end

function ConfigManager:ExportTable()
    return SafeUtils.deepCopy(Config)
end

function ConfigManager:MergeIntoConfig(loaded)
    local fresh = SafeUtils.deepCopy(DEFAULT_CONFIG)
    if type(loaded) == "table" then
        for k, v in pairs(fresh) do
            if type(v) == "table" and type(loaded[k]) == "table" then
                for subK, _ in pairs(v) do
                    if loaded[k][subK] ~= nil then
                        fresh[k][subK] = loaded[k][subK]
                    end
                end
            elseif loaded[k] ~= nil and type(loaded[k]) == type(v) then
                fresh[k] = loaded[k]
            end
        end
    end
    for k, v in pairs(fresh) do
        Config[k] = v
    end
end

function ConfigManager:RunWithApplyGuard(fn)
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

function ConfigManager:RefreshAllWidgets()
    self:RunWithApplyGuard(function()
        for _, refreshFn in ipairs(self.WidgetRefreshers) do
            pcall(refreshFn)
        end
    end)
end

function ConfigManager:Save(name)
    local clean = self:SanitizeName(name)
    if clean == "" then
        return false, "Invalid config name"
    end
    if not SafeUtils.ensureFolder(self.Folder) then
        return false, "Filesystem unavailable"
    end
    local okEnc, json = SafeUtils.jsonEncode(self:ExportTable())
    if not okEnc then
        return false, "JSON encode failed"
    end
    local okWrite = SafeUtils.writeTextFile(self:GetConfigPath(clean), json)
    if okWrite then
        logActivity("Saved config: " .. clean)
        return true, clean
    end
    return false, "Write failed"
end

function ConfigManager:Load(name)
    local clean = self:SanitizeName(name)
    if clean == "" then
        return false, "Invalid config name"
    end
    local okRead, content = SafeUtils.readTextFile(self:GetConfigPath(clean))
    if not okRead then
        return false, "Config not found"
    end
    local okDec, tbl = SafeUtils.jsonDecode(content)
    if not okDec then
        return false, "Invalid JSON"
    end
    self:MergeIntoConfig(tbl)
    self:RefreshAllWidgets()
    MiscController:ApplyFPSCap()
    MiscController:ApplyGpuOptimizer(Config.GpuOptimizer)
    MiscController:SetBlackScreen(Config.BlackScreen)
    logActivity("Loaded config: " .. clean)
    return true, clean
end

function ConfigManager:Delete(name)
    local clean = self:SanitizeName(name)
    if clean == "" then
        return false
    end
    local ok = SafeUtils.deleteFile(self:GetConfigPath(clean))
    if ok then
        if self:GetAutoload() == clean then
            self:ClearAutoload()
        end
        logActivity("Deleted config: " .. clean)
    end
    return ok
end

function ConfigManager:GetAutoload()
    local okRead, content = SafeUtils.readTextFile(self.AutoloadFile)
    if not okRead then
        return nil
    end
    local okDec, tbl = SafeUtils.jsonDecode(content)
    if okDec and type(tbl.autoload) == "string" and tbl.autoload ~= "" then
        return tbl.autoload
    end
    return nil
end

function ConfigManager:SetAutoload(name)
    local clean = self:SanitizeName(name)
    if clean == "" then
        return false
    end
    if not SafeUtils.ensureFolder(self.Folder) then
        return false
    end
    local okEnc, json = SafeUtils.jsonEncode({ autoload = clean })
    if not okEnc then
        return false
    end
    local ok = SafeUtils.writeTextFile(self.AutoloadFile, json)
    if ok then
        logActivity("Autoload set: " .. clean)
    end
    return ok
end

function ConfigManager:ClearAutoload()
    local ok = SafeUtils.deleteFile(self.AutoloadFile)
    if ok then
        logActivity("Autoload cleared")
    end
    return ok
end

function ConfigManager:TryAutoload()
    local autoName = self:GetAutoload()
    if autoName then
        local ok = self:Load(autoName)
        return ok, autoName
    end
    return false, nil
end

--// =========================================================================
--// 10. EVENT BINDINGS & BACKGROUND LOOPS
--// =========================================================================

local function bindGameEvents()
    local events = ReplicatedStorage:FindFirstChild("Events")
    if events then
        local rateMap = {
            UpdatePPS = "Points",
            UpdateRPS = "RebirthPoints",
            UpdateSPS = "Sacrifices",
            UpdateAPS = "Ascensions",
            UpdateAPPS = "AscensionPoints",
            UpdateMPS = "Matter",
            UpdatePumpsPS = "Pumpkins",
        }
        for remoteName, rateKey in pairs(rateMap) do
            local rem = events:FindFirstChild(remoteName)
            if rem and rem:IsA("RemoteEvent") then
                trackConn(rem.OnClientEvent:Connect(function(val)
                    if type(val) == "number" then
                        State.Rates[rateKey] = val
                    end
                end))
            end
        end
    end

    for _, def in ipairs(TREE_DEFS) do
        local branch = TREE_BRANCH[def.id]
        local ownedFolder = LocalPlayer and LocalPlayer:FindFirstChild(def.ownedFolder)
        if ownedFolder then
            trackConn(ownedFolder.ChildAdded:Connect(function(child)
                local now = os.clock()
                State.LastUpgradeBoughtAt = now
                if branch then
                    State.LastUpgradeBoughtAtByBranch[branch] = now
                end
                State.SessionBuys += 1
                State.NodeAttempts[def.id .. ":" .. child.Name] = nil
            end))
        end
        if events then
            local boughtEvent = events:FindFirstChild(def.boughtEvent)
            if boughtEvent and boughtEvent:IsA("RemoteEvent") then
                trackConn(boughtEvent.OnClientEvent:Connect(function(btnName)
                    if type(btnName) == "string" then
                        local now = os.clock()
                        State.LastUpgradeBoughtAt = now
                        if branch then
                            State.LastUpgradeBoughtAtByBranch[branch] = now
                        end
                        State.NodeAttempts[def.id .. ":" .. btnName] = nil
                    end
                end))
            end
        end
    end
end

local function startEngineLoops()
    task.spawn(function()
        local mySerial = State.RunSerial
        while State.Running and State.RunSerial == mySerial do
            if Config.AutoBuyEnabled then
                pcall(function()
                    UpgradeAutobuyer:Step(false)
                end)
            end
            pcall(function()
                ResetLayerController:Step()
            end)
            local waitTime = math.clamp(tonumber(Config.ScanInterval) or 0.15, 0, 2.0)
            task.wait(waitTime)
        end
    end)
end

--// =========================================================================
--// 11. WINDUI DASHBOARD
--// =========================================================================

local function buildUI()
    local okLoad, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
    end)
    if not okLoad or type(WindUI) ~= "table" then
        warn("[VibezUpgradeAutobuyer] Failed to load WindUI: " .. tostring(WindUI))
        return nil
    end

    local Window = WindUI:CreateWindow({
        Title = "Vibez's Upgrade Tree",
        Icon = "sparkles",
        Author = "by olliE",
        Folder = "VibezUpgradeAutobuyerUI",
        Size = UDim2.fromOffset(620, 480),
        Transparent = true,
        Theme = "Dark",
        ToggleKey = Enum.KeyCode.RightShift,
        OpenButton = {
            Title = "Vibez's Upgrade Tree",
            Icon = "sparkles",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
        },
    })
    State.Window = Window
    if type(Window.EditOpenButton) == "function" then
        pcall(Window.EditOpenButton, Window, {
            Title = "Vibez's Upgrade Tree",
            Icon = "sparkles",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
        })
    end
    if type(Window.SetToggleKey) == "function" then
        pcall(Window.SetToggleKey, Window, Enum.KeyCode.RightShift)
    end

    local function registerToggle(tab, opts, getter, setter)
        local t = tab:Toggle({
            Title = opts.Title,
            Desc = opts.Desc,
            Value = getter(),
            Callback = function(v)
                if State.ApplyingConfig or not State.UIReady then
                    return
                end
                setter(v == true)
            end,
        })
        table.insert(ConfigManager.WidgetRefreshers, function()
            if t and type(t.Set) == "function" then
                t:Set(getter())
            end
        end)
        return t
    end

    local function registerSlider(tab, opts, getter, setter)
        local s = tab:Slider({
            Title = opts.Title,
            Desc = opts.Desc,
            Step = opts.Step,
            Value = { Min = opts.Min, Max = opts.Max, Default = getter() },
            Callback = function(v)
                if State.ApplyingConfig or not State.UIReady then
                    return
                end
                local num = tonumber(v)
                if num then
                    setter(num)
                end
            end,
        })
        table.insert(ConfigManager.WidgetRefreshers, function()
            if s and type(s.Set) == "function" then
                s:Set(getter())
            end
        end)
        return s
    end

    local function registerDropdown(tab, opts, getter, setter)
        local d = tab:Dropdown({
            Title = opts.Title,
            Desc = opts.Desc,
            Values = opts.Values,
            Value = getter(),
            Multi = opts.Multi == true,
            AllowNone = opts.AllowNone == true,
            Callback = function(v)
                if State.ApplyingConfig or not State.UIReady then
                    return
                end
                setter(v)
            end,
        })
        table.insert(ConfigManager.WidgetRefreshers, function()
            if d and type(d.Select) == "function" then
                d:Select(getter())
            end
        end)
        return d
    end

    --// Tab 1: Autobuyer
    local TabAuto = Window:Tab({ Title = "Autobuyer", Icon = "shopping-cart" })
    TabAuto:Section({ Title = "Core Controls" })

    registerToggle(TabAuto, {
        Title = "Enable Upgrade Autobuyer",
        Desc = "Automatically buys unlocked & affordable upgrades across selected trees (excludes reset buttons).",
    }, function() return Config.AutoBuyEnabled end, function(v)
        Config.AutoBuyEnabled = v
        logActivity(v and "Autobuyer ENABLED" or "Autobuyer DISABLED")
    end)

    TabAuto:Button({
        Title = "Buy Once (Single Pass)",
        Desc = "Runs one immediate evaluation and purchase pass without toggling Auto-Buy.",
        Callback = function()
            local count = UpgradeAutobuyer:BuyOnce()
            WindUI:Notify({ Title = "Buy Once", Content = "Fired " .. tostring(count) .. " upgrade(s).", Duration = 2.5 })
        end,
    })

    TabAuto:Button({
        Title = "Clear Pending / Backoff",
        Desc = "Resets retry backoff timers for all buttons and reset layers.",
        Callback = function()
            UpgradeAutobuyer:ClearBackoff()
            ResetLayerController:ClearLayerBackoff()
        end,
    })

    TabAuto:Section({ Title = "Policy & Speed" })

    registerDropdown(TabAuto, {
        Title = "Purchase Strategy",
        Desc = "Order in which eligible upgrades are bought.",
        Values = { "Cheapest", "Most Expensive", "Tree Order", "Nearest" },
    }, function() return Config.Strategy end, function(v)
        if type(v) == "string" then
            Config.Strategy = v
        end
    end)

    registerDropdown(TabAuto, {
        Title = "Enabled Upgrade Trees",
        Desc = "Select which upgrade trees the autobuyer can purchase from.",
        Values = TREE_ORDER,
        Multi = true,
        AllowNone = true,
    }, function()
        local selected = {}
        for _, id in ipairs(TREE_ORDER) do
            if Config.EnabledTrees[id] then
                table.insert(selected, id)
            end
        end
        return selected
    end, function(v)
        local newMap = {}
        for _, id in ipairs(TREE_ORDER) do
            newMap[id] = false
        end
        if type(v) == "table" then
            for k, item in pairs(v) do
                if type(item) == "string" and newMap[item] ~= nil then
                    newMap[item] = true
                elseif type(k) == "string" and item == true and newMap[k] ~= nil then
                    newMap[k] = true
                end
            end
        end
        Config.EnabledTrees = newMap
    end)

    registerSlider(TabAuto, {
        Title = "Scan Interval (s)",
        Desc = "Delay between autobuyer ticks.",
        Step = 0.05,
        Min = 0,
        Max = 2.0,
    }, function() return Config.ScanInterval end, function(v) Config.ScanInterval = v end)

    registerSlider(TabAuto, {
        Title = "Max Buys Per Tick",
        Desc = "Maximum upgrades fired in a single scan.",
        Step = 1,
        Min = 1,
        Max = 25,
    }, function() return Config.MaxBuysPerTick end, function(v) Config.MaxBuysPerTick = v end)

    registerSlider(TabAuto, {
        Title = "Currency Reserve (%)",
        Desc = "Keep this percentage of each currency unspent (0% = spend freely; free buttons always buy).",
        Step = 5,
        Min = 0,
        Max = 95,
    }, function() return Config.CurrencyReservePct end, function(v) Config.CurrencyReservePct = v end)

    TabAuto:Section({ Title = "Range & Auto-TP" })

    registerToggle(TabAuto, {
        Title = "Allow Remote Click",
        Desc = "Fire ClickDetectors from any distance without teleporting.",
    }, function() return Config.AllowRemoteClick end, function(v) Config.AllowRemoteClick = v end)

    registerSlider(TabAuto, {
        Title = "Click Range (studs)",
        Desc = "Distance threshold when Allow Remote Click is off.",
        Step = 5,
        Min = 20,
        Max = 250,
    }, function() return Config.ClickRange end, function(v) Config.ClickRange = v end)

    registerToggle(TabAuto, {
        Title = "Auto-TP to Far Upgrades",
        Desc = "Teleports to 1 far upgrade per tick when Allow Remote Click is off.",
    }, function() return Config.AutoTP end, function(v) Config.AutoTP = v end)

    registerSlider(TabAuto, {
        Title = "TP Settle Delay (s)",
        Desc = "Wait after teleporting before firing ClickDetector.",
        Step = 0.01,
        Min = 0,
        Max = 0.50,
    }, function() return Config.ApproachSettleDelay end, function(v) Config.ApproachSettleDelay = v end)

    registerToggle(TabAuto, {
        Title = "Return to Origin After TP",
        Desc = "Returns character to starting position once far queue empties.",
    }, function() return Config.ReturnToOrigin end, function(v) Config.ReturnToOrigin = v end)

    --// Tab 2: Reset Layers
    local TabReset = Window:Tab({ Title = "Reset Layers", Icon = "refresh-cw" })
    TabReset:Section({ Title = "Countdown Timer (From Latest Upgrade Bought)" })

    local resetStatusPara = TabReset:Paragraph({
        Title = "Reset Timer Status",
        Desc = "Initializing...",
    })

    registerToggle(TabReset, {
        Title = "Enable Countdown Timer",
        Desc = "Waits X seconds after the latest upgrade purchase before triggering enabled reset layers.",
    }, function() return Config.ResetTimerEnabled end, function(v) Config.ResetTimerEnabled = v end)

    registerSlider(TabReset, {
        Title = "Countdown Seconds",
        Desc = "Seconds after latest upgrade bought before resetting.",
        Step = 1,
        Min = 0,
        Max = 300,
    }, function() return Config.ResetCountdownSeconds end, function(v) Config.ResetCountdownSeconds = v end)

    registerSlider(TabReset, {
        Title = "Cooldown Between Resets (s)",
        Desc = "Minimum seconds between consecutive reset triggers.",
        Step = 0.5,
        Min = 0,
        Max = 60,
    }, function() return Config.ResetCooldownSeconds end, function(v) Config.ResetCooldownSeconds = v end)

    registerToggle(TabReset, {
        Title = "Require Buy Since Last Reset",
        Desc = "Only trigger a reset if at least 1 upgrade was bought since the last reset.",
    }, function() return Config.ResetRequireBuySinceReset end, function(v) Config.ResetRequireBuySinceReset = v end)

    registerToggle(TabReset, {
        Title = "Wait Until No Upgrades Eligible",
        Desc = "Pause auto-reset while enabled upgrade trees still have affordable upgrades.",
    }, function() return Config.ResetWaitUntilNoUpgrades end, function(v) Config.ResetWaitUntilNoUpgrades = v end)

    TabReset:Section({ Title = "Auto Reset Layers (All Off by Default)" })

    for _, def in ipairs(RESET_LAYER_DEFS) do
        registerToggle(TabReset, {
            Title = def.label,
            Desc = "Automatically trigger " .. def.id .. " when requirements & timer are met.",
        }, function() return Config.ResetLayers[def.id] == true end, function(v)
            Config.ResetLayers[def.id] = v
            ResetLayerController.LayerAttempts[def.id] = nil
        end)

        TabReset:Button({
            Title = "Trigger " .. def.id .. " Now",
            Desc = "Manually fire " .. def.id .. " once.",
            Callback = function()
                local ok = ResetLayerController:FireLayer(def.id)
                WindUI:Notify({
                    Title = "Reset Layer",
                    Content = ok and ("Triggered " .. def.id) or (def.id .. " unavailable / not streamed"),
                    Duration = 2.5,
                })
            end,
        })
    end

    --// Tab 3: Status
    local TabStatus = Window:Tab({ Title = "Status", Icon = "activity" })
    local statusCurrPara = TabStatus:Paragraph({ Title = "Currencies & Income", Desc = "Loading..." })
    local statusTreePara = TabStatus:Paragraph({ Title = "Tree Progress", Desc = "Loading..." })
    local statusQueuePara = TabStatus:Paragraph({ Title = "Next Buyable Queue", Desc = "Loading..." })
    local statusLogPara = TabStatus:Paragraph({ Title = "Recent Activity", Desc = "Idle" })

    --// Tab 4: Misc
    local TabMisc = Window:Tab({ Title = "Misc", Icon = "sliders" })
    TabMisc:Section({ Title = "Movement" })

    registerToggle(TabMisc, { Title = "Override WalkSpeed" }, function() return Config.WalkSpeedEnabled end, function(v) Config.WalkSpeedEnabled = v end)
    registerSlider(TabMisc, { Title = "WalkSpeed", Step = 2, Min = 16, Max = 200 }, function() return Config.WalkSpeed end, function(v) Config.WalkSpeed = v end)
    registerToggle(TabMisc, { Title = "Override JumpPower" }, function() return Config.JumpPowerEnabled end, function(v) Config.JumpPowerEnabled = v end)
    registerSlider(TabMisc, { Title = "JumpPower", Step = 5, Min = 50, Max = 250 }, function() return Config.JumpPower end, function(v) Config.JumpPower = v end)
    registerToggle(TabMisc, { Title = "Infinite Jump" }, function() return Config.InfiniteJump end, function(v) Config.InfiniteJump = v end)
    registerToggle(TabMisc, { Title = "Flight (WASD + Space/Ctrl)" }, function() return Config.FlightEnabled end, function(v) Config.FlightEnabled = v end)
    registerSlider(TabMisc, { Title = "Flight Speed", Step = 5, Min = 20, Max = 300 }, function() return Config.FlightSpeed end, function(v) Config.FlightSpeed = v end)
    registerToggle(TabMisc, { Title = "Noclip" }, function() return Config.NoclipEnabled end, function(v) Config.NoclipEnabled = v end)

    TabMisc:Section({ Title = "Zone Teleports" })
    local selectedZone = "Spawn"
    TabMisc:Dropdown({
        Title = "Select Zone",
        Values = { "Spawn", "Extra", "Rebirth", "Sacrifice", "Ascension", "Blackhole", "Halloween" },
        Value = "Spawn",
        Callback = function(v)
            if type(v) == "string" then
                selectedZone = v
            end
        end,
    })
    TabMisc:Button({
        Title = "Teleport to Selected Zone",
        Callback = function()
            MiscController:TeleportToZone(selectedZone)
        end,
    })

    TabMisc:Section({ Title = "Visuals" })
    registerToggle(TabMisc, { Title = "Fullbright" }, function() return Config.Fullbright end, function(v) Config.Fullbright = v end)
    registerToggle(TabMisc, { Title = "No Fog" }, function() return Config.NoFog end, function(v) Config.NoFog = v end)
    registerToggle(TabMisc, { Title = "Custom Camera FOV" }, function() return Config.FOVEnabled end, function(v) Config.FOVEnabled = v end)
    registerSlider(TabMisc, { Title = "Camera FOV", Step = 2, Min = 50, Max = 120 }, function() return Config.FOVValue end, function(v) Config.FOVValue = v end)
    registerToggle(TabMisc, { Title = "Unlock Max Camera Zoom" }, function() return Config.UnlockMaxZoom end, function(v) Config.UnlockMaxZoom = v end)

    TabMisc:Section({ Title = "GPU & AFK Optimization" })
    registerToggle(TabMisc, {
        Title = "GPU Optimizer",
        Desc = "Disables shadows and particle trails to reduce GPU load.",
    }, function() return Config.GpuOptimizer end, function(v) MiscController:ApplyGpuOptimizer(v) end)

    registerToggle(TabMisc, { Title = "Enable FPS Cap" }, function() return Config.FPSCapEnabled end, function(v)
        Config.FPSCapEnabled = v
        MiscController:ApplyFPSCap()
    end)
    registerSlider(TabMisc, { Title = "FPS Cap", Step = 5, Min = 10, Max = 240 }, function() return Config.FPSCap end, function(v)
        Config.FPSCap = v
        MiscController:ApplyFPSCap()
    end)

    registerToggle(TabMisc, {
        Title = "Black Screen Mode",
        Desc = "Disables 3D rendering and shows a centered 'Disable Black Screen' button.",
    }, function() return Config.BlackScreen end, function(v) MiscController:SetBlackScreen(v) end)

    TabMisc:Section({ Title = "Blackhole Helper" })
    registerToggle(TabMisc, {
        Title = "Auto Collect Atoms",
        Desc = "Fires CollectAtom once unlocked (Ascension Button11a).",
    }, function() return Config.AutoCollectAtoms end, function(v) Config.AutoCollectAtoms = v end)
    registerSlider(TabMisc, { Title = "Atom Collect Interval (s)", Step = 0.1, Min = 0, Max = 2.0 }, function() return Config.AtomCollectInterval end, function(v) Config.AtomCollectInterval = v end)

    --// Tab 5: Configs
    local TabCfg = Window:Tab({ Title = "Configs", Icon = "save" })
    local configNameInput = "default"
    local selectedConfig = "default"

    local autoloadPara = TabCfg:Paragraph({
        Title = "Autoload Status",
        Desc = "Autoload: " .. (ConfigManager:GetAutoload() or "None"),
    })

    TabCfg:Input({
        Title = "Config Name",
        Placeholder = "default",
        Value = "default",
        Callback = function(v)
            if type(v) == "string" and v ~= "" then
                configNameInput = v
            end
        end,
    })

    local cfgDropdown = TabCfg:Dropdown({
        Title = "Saved Configs",
        Values = ConfigManager:ListConfigs(),
        Value = ConfigManager:GetAutoload() or "default",
        AllowNone = true,
        Callback = function(v)
            if type(v) == "string" and v ~= "" then
                selectedConfig = v
            end
        end,
    })

    local function refreshConfigUI()
        local list = ConfigManager:ListConfigs()
        if cfgDropdown and type(cfgDropdown.Refresh) == "function" then
            ConfigManager:RunWithApplyGuard(function()
                cfgDropdown:Refresh(list)
            end)
        end
        if autoloadPara and type(autoloadPara.SetDesc) == "function" then
            autoloadPara:SetDesc("Autoload: " .. (ConfigManager:GetAutoload() or "None"))
        end
    end

    TabCfg:Button({
        Title = "Save Config",
        Callback = function()
            local ok, msg = ConfigManager:Save(configNameInput)
            refreshConfigUI()
            WindUI:Notify({ Title = "Configs", Content = ok and ("Saved " .. msg) or tostring(msg), Duration = 2.5 })
        end,
    })

    TabCfg:Button({
        Title = "Load Selected Config",
        Callback = function()
            local ok, msg = ConfigManager:Load(selectedConfig)
            refreshConfigUI()
            WindUI:Notify({ Title = "Configs", Content = ok and ("Loaded " .. msg) or tostring(msg), Duration = 2.5 })
        end,
    })

    TabCfg:Button({
        Title = "Delete Selected Config",
        Callback = function()
            local ok = ConfigManager:Delete(selectedConfig)
            refreshConfigUI()
            WindUI:Notify({ Title = "Configs", Content = ok and ("Deleted " .. selectedConfig) or "Delete failed", Duration = 2.5 })
        end,
    })

    TabCfg:Button({
        Title = "Refresh Config List",
        Callback = refreshConfigUI,
    })

    TabCfg:Button({
        Title = "Set Selected as Autoload",
        Callback = function()
            local ok = ConfigManager:SetAutoload(selectedConfig)
            refreshConfigUI()
            WindUI:Notify({ Title = "Autoload", Content = ok and ("Autoload set to " .. selectedConfig) or "Failed", Duration = 2.5 })
        end,
    })

    TabCfg:Button({
        Title = "Clear Autoload",
        Callback = function()
            ConfigManager:ClearAutoload()
            refreshConfigUI()
            WindUI:Notify({ Title = "Autoload", Content = "Autoload cleared", Duration = 2.5 })
        end,
    })

    --// Tab 6: Diagnostics
    local TabDiag = Window:Tab({ Title = "Diagnostics", Icon = "terminal" })
    local diagPara = TabDiag:Paragraph({ Title = "Engine Diagnostics", Desc = "Loading..." })

    TabDiag:Button({
        Title = "Copy Diagnostics Report",
        Callback = function()
            local snap = GameState:GetSnapshot()
            local plan = PurchasePolicy.Evaluate(snap, Config, State.NodeAttempts, os.clock())
            local report = string.format(
                "PlaceId=%d | RunSerial=%d | SessionBuys=%d | TickRuns=%d | Nodes=%d | Nearby=%d | Far=%d | Blocked=%d",
                game.PlaceId,
                State.RunSerial,
                State.SessionBuys,
                State.TotalTickRuns,
                #snap.nodes,
                #plan.nearby,
                #plan.far,
                plan.blockedCount
            )
            if type(setclipboard) == "function" then
                pcall(setclipboard, report)
            end
            WindUI:Notify({ Title = "Diagnostics", Content = report, Duration = 4 })
        end,
    })

    TabDiag:Button({
        Title = "Unload Script",
        Desc = "Stops all loops, restores visuals/FPS, and closes the UI.",
        Callback = function()
            if type(GlobalEnv[GLOBAL_KEY]) == "table" and type(GlobalEnv[GLOBAL_KEY].destroy) == "function" then
                GlobalEnv[GLOBAL_KEY].destroy()
            end
        end,
    })

    -- Live UI Status Updater (0.5s)
    task.spawn(function()
        local mySerial = State.RunSerial
        while State.Running and State.RunSerial == mySerial do
            pcall(function()
                local now = os.clock()
                local snap = GameState:GetSnapshot()
                local plan = PurchasePolicy.Evaluate(snap, Config, State.NodeAttempts, now)
                local c = snap.currencies

                if statusCurrPara and type(statusCurrPara.SetDesc) == "function" then
                    statusCurrPara:SetDesc(string.format(
                        "Points: %s (%s/s) | Level: %s | Prestige: %d | Reboot: %d\nRP: %s (%s/s) | Sacrifices: %s | Asc: %s | AP: %s\nUP: %s | URP: %s | Atoms: %s | Matter: %s | DM: %s | RT: %s\nPumpkins: %s | Zombies: %s | Ghosts: %s | HLoop: %s",
                        SafeUtils.formatNumber(c.Points), SafeUtils.formatNumber(State.Rates.Points),
                        SafeUtils.formatNumber(c.Level), c.Prestige, c.Reboot,
                        SafeUtils.formatNumber(c.RebirthPoints), SafeUtils.formatNumber(State.Rates.RebirthPoints),
                        SafeUtils.formatNumber(c.Sacrifices), SafeUtils.formatNumber(c.Ascensions), SafeUtils.formatNumber(c.AscensionPoints),
                        SafeUtils.formatNumber(c.UselessPoints), SafeUtils.formatNumber(c.UselessRebirthPoints),
                        SafeUtils.formatNumber(c.Atoms), SafeUtils.formatNumber(c.Matter), SafeUtils.formatNumber(c.DarkMatter), SafeUtils.formatNumber(c.RebootTokens),
                        SafeUtils.formatNumber(c.Pumpkins), SafeUtils.formatNumber(c.Zombies), SafeUtils.formatNumber(c.Ghosts), SafeUtils.formatNumber(c.HalloweenLoop)
                    ))
                end

                if statusTreePara and type(statusTreePara.SetDesc) == "function" then
                    local lines = {}
                    for _, id in ipairs(TREE_ORDER) do
                        local st = snap.treeStats[id]
                        if st then
                            table.insert(lines, string.format("%s: %d/%d owned (%d unlocked)%s",
                                id, st.owned, st.total, st.unlocked, st.gateOpen and "" or " [Gated]"))
                        end
                    end
                    statusTreePara:SetDesc(table.concat(lines, "\n"))
                end

                if statusQueuePara and type(statusQueuePara.SetDesc) == "function" then
                    local q = {}
                    for i = 1, math.min(5, #plan.nearby) do
                        local n = plan.nearby[i]
                        table.insert(q, string.format("%d. [%s] %s (%s %s)", i, n.treeId, n.title, n.price == 0 and "Free" or SafeUtils.formatNumber(n.price), n.currency))
                    end
                    if #q == 0 and #plan.far > 0 then
                        for i = 1, math.min(3, #plan.far) do
                            local n = plan.far[i]
                            table.insert(q, string.format("TP %d. [%s] %s (%dm)", i, n.treeId, n.title, math.floor(n.distance)))
                        end
                    end
                    statusQueuePara:SetDesc(#q > 0 and table.concat(q, "\n") or "No affordable unlocked upgrades in selected trees.")
                end

                if statusLogPara and type(statusLogPara.SetDesc) == "function" then
                    statusLogPara:SetDesc(#State.ActivityLog > 0 and table.concat(State.ActivityLog, "\n") or "Idle")
                end

                if resetStatusPara and type(resetStatusPara.SetDesc) == "function" then
                    local rem = ResetLayerController:GetCountdownRemaining(now)
                    local sinceBuy = math.max(0, now - State.LastUpgradeBoughtAt)
                    resetStatusPara:SetDesc(string.format(
                        "Countdown Remaining: %s | Since Last Buy: %s | Last Reset: %s",
                        SafeUtils.formatDuration(rem),
                        SafeUtils.formatDuration(sinceBuy),
                        State.LastResetLayer
                    ))
                end

                if diagPara and type(diagPara.SetDesc) == "function" then
                    local pendingCount = 0
                    for _ in pairs(State.NodeAttempts) do
                        pendingCount += 1
                    end
                    diagPara:SetDesc(string.format(
                        "RunSerial: %d | Session Buys: %d | Tick Runs: %d\nStreamed Upgrades: %d | Eligible: %d (Nearby: %d, Far: %d)\nPending/Backoff Entries: %d | Unaffordable Unlocked: %d\nLast Action: %s",
                        State.RunSerial, State.SessionBuys, State.TotalTickRuns,
                        #snap.nodes, plan.totalEligible, #plan.nearby, #plan.far,
                        pendingCount, plan.unaffordableCount,
                        State.LastActionMessage
                    ))
                end
            end)
            task.wait(0.5)
        end
    end)

    return Window
end

--// =========================================================================
--// 12. DESTROY / EXPORT API & BOOTSTRAP
--// =========================================================================

local API = {
    Config = Config,
    State = State,
    GameState = GameState,
    PurchasePolicy = PurchasePolicy,
    UpgradeAutobuyer = UpgradeAutobuyer,
    ResetLayerController = ResetLayerController,
    MiscController = MiscController,
    ConfigManager = ConfigManager,
}

function API.destroy()
    if not State.Running then
        return
    end
    State.Running = false
    State.RunSerial += 1
    Config.AutoBuyEnabled = false

    for _, conn in ipairs(State.Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    State.Connections = {}

    pcall(function()
        MiscController:RestoreAll()
    end)

    for _, overlay in ipairs(State.Overlays) do
        pcall(function()
            overlay:Destroy()
        end)
    end
    State.Overlays = {}

    if State.Window then
        pcall(function()
            if type(State.Window.Destroy) == "function" then
                State.Window:Destroy()
            elseif type(State.Window.Close) == "function" then
                State.Window:Close()
            end
        end)
        State.Window = nil
    end

    if GlobalEnv[GLOBAL_KEY] == API then
        GlobalEnv[GLOBAL_KEY] = nil
    end
end

GlobalEnv[GLOBAL_KEY] = API

bindGameEvents()
MiscController:StartLoops()
buildUI()
ConfigManager:TryAutoload()
startEngineLoops()

task.delay(0.1, function()
    if State.Running then
        State.UIReady = true
    end
end)

return API
