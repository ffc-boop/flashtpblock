if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local LP = Players.LocalPlayer
local LocalPlayer = LP

--=============================================================================
-- Executor / stealth layer
--   Every risky primitive is guarded and has a fallback. No synthetic input
--   events are generated and no engine input service is touched. Nothing is
--   parented into workspace or into a character.
--=============================================================================
local S = {}
do
    S.ENV_PATCH = false   -- patches Net/Synchronizer environments: left off
    S.DEBUG_VIZ = false   -- neon path visualisation parts: left off

    local function inGame(i)
        if not i then return false end
        local ok, res = pcall(function() return i:IsDescendantOf(game) end)
        return ok and res
    end

    -- Container used for ScreenGuis: hidden UI first, then CoreGui, then PlayerGui.
    function S.hiddenRoot()
        local root
        pcall(function()
            if type(gethui) == "function" then root = gethui() end
        end)
        if not inGame(root) then
            local cg
            pcall(function() cg = game:GetService("CoreGui") end)
            if cg then root = cg end
        end
        if not inGame(root) then
            local pg
            pcall(function() pg = LP:FindFirstChildOfClass("PlayerGui") end)
            if pg then root = pg end
        end
        return root
    end

    function S.protect(gui)
        if not gui then return end
        pcall(function()
            if type(protectgui) == "function" then protectgui(gui) end
        end)
        pcall(function()
            if type(syn) == "table" and type(syn.protect_gui) == "function" then
                syn.protect_gui(gui)
            end
        end)
    end

    -- Client-only render container for world visuals (billboards, highlights).
    function S.visualRoot()
        if S._visualRoot and S._visualRoot.Parent then return S._visualRoot end
        local f = Instance.new("Folder")
        f.Name = "Fx"
        local root = S.hiddenRoot()
        if root then pcall(function() f.Parent = root end) end
        if not f.Parent then
            pcall(function() f.Parent = LP:FindFirstChildOfClass("PlayerGui") end)
        end
        S._visualRoot = f
        return f
    end

    local function fireConnections(signal)
        if type(getconnections) ~= "function" then return false end
        local ok, list = pcall(getconnections, signal)
        if not ok or type(list) ~= "table" then return false end
        local fired = false
        for _, c in ipairs(list) do
            if type(c.Fire) == "function" then
                pcall(function() c:Fire() end)
                fired = true
            end
        end
        return fired
    end

    -- Press a GuiButton without synthetic input. Signals that actually have a
    -- handler attached are preferred, so a no-op signal is never reported as a
    -- successful click.
    function S.clickButton(btn)
        if not btn or not btn.Parent then return false end
        if type(getconnections) == "function" then
            for _, signal in ipairs({ btn.MouseButton1Click, btn.Activated, btn.MouseButton1Up }) do
                local ok, list = pcall(getconnections, signal)
                if ok and type(list) == "table" and #list > 0 then
                    local fired = false
                    for _, c in ipairs(list) do
                        if type(c.Fire) == "function" then
                            pcall(function() c:Fire() end)
                            fired = true
                        end
                    end
                    if fired then return true end
                end
            end
        end
        if type(firesignal) == "function" then
            if pcall(firesignal, btn.MouseButton1Up) then return true end
            if pcall(firesignal, btn.MouseButton1Click) then return true end
            if pcall(firesignal, btn.Activated) then return true end
        end
        return false
    end

    -- Activate a Tool. Tool:Activate() is the engine's own activation entry
    -- point and replicates to the server, so it is tried first. mouse1click is
    -- only a fallback because it clicks wherever the cursor happens to be.
    function S.clickTool(tool)
        if not tool then return false end
        if tool:IsA("Tool") and pcall(function() tool:Activate() end) then return true end
        if type(mouse1click) == "function" then
            if pcall(mouse1click) then return true end
        end
        return fireConnections(tool.Activated)
    end

    -- Trigger a ProximityPrompt.
    function S.firePrompt(prompt)
        if not prompt or not prompt.Parent then return false end
        local hold = tonumber(prompt.HoldDuration) or 0
        if type(fireproximityprompt) == "function" then
            if pcall(fireproximityprompt, prompt, hold) then return true end
            if pcall(fireproximityprompt, prompt) then return true end
        end
        local held = false
        pcall(function()
            if type(prompt.InputHoldBegin) == "function" then
                prompt:InputHoldBegin()
                held = true
            end
        end)
        if held then
            task.wait(math.max(0.05, hold))
            pcall(function()
                if type(prompt.InputHoldEnd) == "function" then prompt:InputHoldEnd() end
            end)
            return true
        end
        return fireConnections(prompt.Triggered)
    end

    -- Fire the grapple: game remote first, tool API only if the remote is dead.
    function S.fireGrappleSafe()
        local remoteOK = false
        if type(_G.VanishFireGrapple) == "function" then
            remoteOK = pcall(_G.VanishFireGrapple) and _G.NetModuleReady == true
        end
        if remoteOK then return true end
        local char = LP.Character
        local tool = char and char:FindFirstChild("Grapple Hook")
        if not tool then
            local bp = char and char:FindFirstChildOfClass("Backpack")
            tool = bp and bp:FindFirstChild("Grapple Hook")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if tool and hum then pcall(function() hum:EquipTool(tool) end) end
        end
        if tool then return S.clickTool(tool) end
        return remoteOK
    end
end

local _BLOCKING_MACHINE_TYPES = { Fuse = true, Duel = true, Trade = true, Crafting = true }
local function _VanishIsFusing(animalData)
    if type(animalData) ~= "table" then return false end
    local m = animalData.Machine
    if type(m) ~= "table" then return false end
    return _BLOCKING_MACHINE_TYPES[m.Type] == true
end

do
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local getupvalue = getupvalue or (debug and debug.getupvalue)

    local function getInternalTable()
        local Packages = ReplicatedStorage:FindFirstChild("Packages")
        if not Packages then return nil end
        local SynMod = Packages:FindFirstChild("Synchronizer")
        if not SynMod then return nil end
        local ok, syn = pcall(require, SynMod)
        if not ok or not syn then return nil end
        local Get = syn.Get
        if type(Get) ~= "function" then return nil end
        for i = 1, 5 do
            local s, u = pcall(getupvalue, Get, i)
            if s and type(u) == "table" then
                if u.___private or u.___channels or u.___data then return u end
                for k, v in pairs(u) do
                    if (type(k) == "string" and k:match("^Plot_")) or type(v) == "table" then
                        return u
                    end
                end
            end
        end
        local s, e = pcall(getfenv, Get)
        if s and e and e.self then return e.self end
        return nil
    end

    local SyncInt = {_cache = {}, _data = nil}
    _G.SyncInt = SyncInt

    task.spawn(function()
        for i = 1, 10 do
            SyncInt._data = getInternalTable()
            if SyncInt._data then break end
            task.wait(1)
        end
    end)

    function _G.stealthGet(n)
        if not n or type(n) ~= "string" then return nil end
        if SyncInt._cache[n] == false then return nil end
        if SyncInt._data then
            for _, k in ipairs({n, "Plot_" .. n, "Plot" .. n, n .. "_Channel", "Channel_" .. n}) do
                if SyncInt._data[k] then
                    SyncInt._cache[n] = SyncInt._data[k]
                    return SyncInt._data[k]
                end
            end
            for k, v in pairs(SyncInt._data) do
                if type(k) == "string" and (k == n or k:find(n, 1, true)) and type(v) == "table" then
                    SyncInt._cache[n] = v
                    return v
                end
            end
        end
        SyncInt._cache[n] = false
        return nil
    end

    function _G.sProp(ch, p)
        if not ch or type(ch) ~= "table" then return nil end
        if ch[p] then return ch[p] end
        if type(ch.Get) == "function" then
            local ok, r = pcall(ch.Get, ch, p)
            if ok then return r end
        end
        local alts = {
            Owner = {"owner", "Owner", "plotOwner", "PlotOwner"},
            AnimalList = {"animalList", "AnimalList", "animals", "Animals", "pets"},
        }
        if alts[p] then
            for _, a in ipairs(alts[p]) do
                if ch[a] then return ch[a] end
            end
        end
        return nil
    end

    local Packages = ReplicatedStorage:FindFirstChild("Packages")
    local SynMod = Packages and Packages:FindFirstChild("Synchronizer")
    local okReq, syn = pcall(require, SynMod)
    -- Patching the internals of a game module is the loudest thing this file
    -- can do, and `isexecutorclosure` is not present on every executor. Both
    -- are reasons this block is opt-in and fully guarded.
    if S.ENV_PATCH and okReq and typeof(syn) == "table" and debug then
        local isExec = isexecutorclosure or checkclosure or function() return false end
        local newcc = newcclosure or function(f) return f end
        -- Xeno does not expose debug.getupvalues; every debug primitive here is
        -- optional and the whole block bails out when they are missing.
        local getups = debug.getupvalues or rawget(_G, "getupvalues")
        local setupv = debug.setupvalue or rawget(_G, "setupvalue")
        if type(getups) ~= "function" or type(setupv) ~= "function" then return end
        local function HasBoolUpvalue(Fn)
            local OkU, Ups = xpcall(getups, function() end, Fn)
            if not OkU or type(Ups) ~= "table" then return false end
            for _, V in pairs(Ups) do
                if typeof(V) == "boolean" then return true end
            end
            return false
        end
        for _, Fn in pairs(syn) do
            if typeof(Fn) == "function" and not isExec(Fn) then
                local OkU, Ups = xpcall(getups, function() end, Fn)
                if OkU and type(Ups) == "table" then
                    for Idx, V in pairs(Ups) do
                        if typeof(V) == "function" and not isExec(V) and HasBoolUpvalue(V) then
                            pcall(setupv, Fn, Idx, newcc(function() end))
                        end
                    end
                end
            end
        end
    end
end

do
    -- Was a bare `do` block that finished with a chunk-level `return`. If any
    -- previous run had already set the flag, the whole file returned before the
    -- menu was ever built. It is now a closure, gated behind S.ENV_PATCH.
    local function patchEnvironment()
        local gv = (type(getgenv) == "function" and getgenv()) or _G
        if gv._net_getfenv_patched then return end
        gv._net_getfenv_patched = true

        local ok, NetModule = pcall(function()
            local pkgs = game:GetService("ReplicatedStorage"):WaitForChild("Packages", 10)
            local net = pkgs and pkgs:WaitForChild("Net", 10)
            local mod = net and net:FindFirstChildWhichIsA("ModuleScript", true)
            if not mod then return nil end
            return require(mod)
        end)
        if not ok or type(NetModule) ~= "table" then return end

        local getupvalues = debug and debug.getupvalues or rawget(_G, "getupvalues")
        local getprotos = debug and debug.getprotos or rawget(_G, "getprotos")
        local newcc = rawget(_G, "newcclosure") or function(fn) return fn end
        if not (getupvalues and getprotos) then return end

        local fake = newcc(function() return {} end)
        local scanned = {}
        local queue, processed = {}, 0
        local function enqueue(fn)
            if type(fn) == "function" and not scanned[fn] then queue[#queue + 1] = fn end
        end
        local function drain()
            while #queue > 0 do
                local fn = queue[#queue]; queue[#queue] = nil
                if not scanned[fn] then
                    scanned[fn] = true
                    local okUps, ups = pcall(getupvalues, fn)
                    if okUps and ups then
                        for _, up in pairs(ups) do
                            if type(up) == "table" then
                                for k, v in pairs(up) do
                                    if v == "getfenv" or v == "getrenv" then
                                        pcall(function() up[k] = fake end)
                                    elseif type(v) == "function" then
                                        enqueue(v)
                                    end
                                end
                            elseif type(up) == "function" then
                                enqueue(up)
                            end
                        end
                    end
                    local okProtos, protos = pcall(getprotos, fn)
                    if okProtos and protos then
                        for _, proto in ipairs(protos) do enqueue(proto) end
                    end
                    processed = processed + 1
                    if processed % 150 == 0 then task.wait() end
                end
            end
        end

        for _, v in pairs(NetModule) do enqueue(v) end

        local okSync, SyncModule = pcall(function()
            local pkgs = game:GetService("ReplicatedStorage"):WaitForChild("Packages", 10)
            local s = pkgs and pkgs:WaitForChild("Synchronizer", 10)
            if not s then return nil end
            return require(s)
        end)
        if okSync and type(SyncModule) == "table" then
            for _, v in pairs(SyncModule) do enqueue(v) end
        end

        drain()
    end

    -- Off by default: rewriting the environment of the game's own networking
    -- module is the loudest client-side tell in this file.
    if S.ENV_PATCH then
        task.spawn(function() pcall(patchEnvironment) end)
    end
end

_G.VanishGetSyncData = _G.VanishGetSyncData or function(plot)
    local plotName = type(plot) == "string" and plot or (plot and plot.Name)
    if not plotName then return nil end
    local Pkgs = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
    local Sync = Pkgs and Pkgs:FindFirstChild("Synchronizer")
    if not Sync then return nil end
    local okMod, mod = pcall(require, Sync)
    if not okMod or type(mod) ~= "table" then return nil end
    local okT, data = pcall(function() return mod:GetTableFromChannel(plotName) end)
    if okT and type(data) == "table" then return data end
    local okC, ch = pcall(function() return mod:Get(plotName) end)
    if okC and ch then
        local synth = { __channel = ch }
        pcall(function() synth.AnimalList = ch:Get("AnimalList") end)
        pcall(function() synth.Owner = ch:Get("Owner") end)
        return synth
    end
    return nil
end

local Synchronizer, AnimalsData, AnimalsShared, NumberUtils

local _lastModuleFail = 0
local function loadModules()
    if Synchronizer and AnimalsData and AnimalsShared then return true end
    -- Every WaitForChild below has a timeout. Retrying the whole set on every
    -- scan tick would stall the script for seconds per attempt, so back off.
    if os.clock() - _lastModuleFail < 8 then return false end
    local ok = pcall(function()
        local Packages = RS:WaitForChild("Packages", 5)
        local Datas = RS:WaitForChild("Datas", 5)
        local Shared = RS:WaitForChild("Shared", 5)
        local Utils = RS:WaitForChild("Utils", 5)
        Synchronizer = require(Packages:WaitForChild("Synchronizer"))
        AnimalsData = require(Datas:WaitForChild("Animals"))
        AnimalsShared = require(Shared:WaitForChild("Animals"))
        NumberUtils = require(Utils:WaitForChild("NumberUtils"))
    end)
    if ok and Synchronizer and AnimalsData and AnimalsShared then return true end
    _lastModuleFail = os.clock()
    return false
end

local NetModule
local function loadNet()
    if NetModule then return true end
    local ok, mod = pcall(function()
        return require(RS:WaitForChild("Packages", 5):WaitForChild("Net", 5):FindFirstChildWhichIsA("ModuleScript", true))
    end)
    if not ok or type(mod) ~= "table" then
        _G.NetModuleReady = false
        return false
    end
    NetModule = mod
    _G.NetModuleReady = true
    return true
end

local function fireGrapple()
    if not NetModule then loadNet() end
    if not NetModule then return end
    local char = LP.Character
    if not char then return end
    if not char:FindFirstChild("Grapple Hook") then
        local bp = LP:FindFirstChild("Backpack")
        local tool = bp and bp:FindFirstChild("Grapple Hook")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if tool and hum then pcall(function() hum:EquipTool(tool) end) end
    end
    if not char:FindFirstChild("Grapple Hook") then return end
    pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
end
_G.VanishFireGrapple = fireGrapple

local CARPET_SPEED = 400
_G.VanishCarpetSpeed = CARPET_SPEED
local SKY_CLONE_WAIT = 0.2
local CARPET_NAMES = { "Flying Carpet", "Carpet", "Cloud", "Witch's Broom", "Cupid's Wings", "Santa's Sleigh", "Magic Carpet" }
local function findTool(name)
    local char = LP.Character
    local bp = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
end
local GRAPPLE_NAMES = { "Grapple Hook", "Grappling Hook", "Grapple", "Hook", "Web Slinger", "Grapple Gun", "GrappleHook" }
local function equipCarpet()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    for _, n in ipairs(CARPET_NAMES) do
        local t = findTool(n)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return n
        end
    end
    return nil
end
local function carpetEngage()
    if not NetModule then pcall(loadNet) end
    local _t0 = os.clock()
    while not findTool("Grapple Hook") and os.clock() - _t0 < 5 do
        if not NetModule then pcall(loadNet) end
        RunService.Heartbeat:Wait()
    end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    if not char:FindFirstChild("Grapple Hook") then
        local g = findTool("Grapple Hook")
        if g then pcall(function() hum:EquipTool(g) end) end
    end
    task.wait(0.2)
    if NetModule and LP.Character and LP.Character:FindFirstChild("Grapple Hook") then
        pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
    end
    task.wait(0.15)
    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h then pcall(function() h:UnequipTools() end) end
    task.wait(0.15)
    local cn
    local _tc = os.clock()
    repeat
        cn = equipCarpet()
        local c = LP.Character
        if cn and c and c:FindFirstChild(cn) then break end
        RunService.Heartbeat:Wait()
    until os.clock() - _tc > 1
    _G.TPEngage = "carpet=" .. tostring(cn)
    return cn
end

local PET_PRIORITY_TIERS = {
    [1] = { pets = {"Headless Horseman"}, threshold = 0 },
    [2] = { pets = {"Signore Carapace"}, threshold = 0 },
    [3] = { pets = {"John Pork"}, threshold = 0 },
    [4] = { pets = {"Strawberry Elephant"}, threshold = 0 },
    [5] = { pets = {"Arcadragon"}, threshold = 5e9 },
    [6] = { pets = {"Elefanto Frigo"}, threshold = 10e9 },
    [7] = { pets = {"Meowl"}, threshold = 5e9 },
    [8] = { pets = {"Skibidi Toilet"}, threshold = 5e9 },
    [9] = { pets = {"Love Love Bear"}, threshold = 0 },
    [10] = { pets = {"Antonio"}, threshold = 0 },
    [11] = { pets = {"Pancake and Syrup"}, threshold = 0 },
    [12] = { pets = {"Griffin"}, threshold = 0 },
    [13] = { pets = {"Globa Steppa","La Supreme Combinasion","Fishino Clownino","Dragon Gingerini","Tirilikalika Tirilikalako"}, threshold = 5e9 },
    [14] = { pets = {"Ginger Gerat","Pet"}, threshold = 10e9 },
    [15] = { pets = {"Hydra Bunny","Digi Narwhal","Kalika Bros"}, threshold = 3e9 },
    [16] = { pets = {"Hydra Dragon Cannelloni","Dragon Cannelloni","Bunny and Eggy"}, threshold = 3e9 },
    [17] = { pets = {"Ketupat Bros","Rosey and Teddy","La Casa Boo","Fragola la la"}, threshold = 3e9 },
    [18] = { pets = {"Fragola La La La","Cerberus","Guest 666","Los Hackers"}, threshold = 1e9 },
    [19] = { pets = {"Garama and Madundung","Spooky and Pumpky","Reinito Sleighito","Burguro And Fryuro","Cooki and Milki","Fragrama and Chocrama","La Food Combinasion","Los Amigos","Foxini Lanternini","Capitano Moby","Fortunu and Cashuru","Los Sekolahs","Celestial Pegasus"}, threshold = 750e6 },
    [20] = { pets = {"La Secret Combinasion","Sammyni Fattini","Cloverat Clapat","Popcuru and Fizzuru"}, threshold = 1e9 },
}

local TIER_LOOKUP = {}
for tier, data in pairs(PET_PRIORITY_TIERS) do
    for _, name in ipairs(data.pets) do TIER_LOOKUP[name] = tier end
end

local LOCKED_TIERS = { [1]=true, [2]=true, [3]=true, [4]=true }

local DIRECT_THRESHOLDS = {
    [3] = { [4] = 10e9 },
    [4] = {},
    [5] = { [6] = math.huge },
    [6] = { [9] = math.huge, [10] = math.huge, [12] = 15e9 },
    [10] = { [12] = 20e9 },
    [11] = { [12] = 10e9 },
}

local MUTATION_PRIORITY = {
    ["Galaxy"]=1,["Candy"]=1,["Yin Yang"]=1,["YinYang"]=1,["Divine"]=1,
    ["Cursed"]=1,["Lava"]=1,["Radioactive"]=1,["Cyber"]=1,["Rainbow"]=1,["Bloodrot"]=2,
}

local MUTATED_BEATS_GRIFFIN = {
    ["Fishino Clownino"]=true,["Globa Steppa"]=true,
    ["La Supreme Combinasion"]=true,["Tirilikalika Tirilikalako"]=true,
}

local function getMutPrio(m)
    if not m or m == "" or m == "None" then return 0 end
    if MUTATION_PRIORITY[m] then return MUTATION_PRIORITY[m] end
    local n = tostring(m):lower():gsub("[%s%-_]","")
    if n == "bloodrot" then return 2 end
    if n == "yinyang" or n == "galaxy" or n == "candy" or n == "divine"
        or n == "cursed" or n == "lava" or n == "radioactive" or n == "cyber"
        or n == "rainbow" then return 1 end
    return 0
end

local function getCumThreshold(hi, lo)
    if DIRECT_THRESHOLDS[hi] and DIRECT_THRESHOLDS[hi][lo] then return DIRECT_THRESHOLDS[hi][lo] end
    if LOCKED_TIERS[hi] then return math.huge end
    local total = 0
    for t = hi + 1, lo do
        local td = PET_PRIORITY_TIERS[t]
        if td and td.threshold > 0 then total = total + td.threshold end
    end
    return total
end

local function petOutranks(aName, bName, aMut, bMut, aMPS, bMPS)
    if aName == "Strawberry Elephant" and bName == "John Pork" then return true end
    if aName == "John Pork" and bName == "Strawberry Elephant" then return false end
    if MUTATED_BEATS_GRIFFIN[aName] and bName == "Griffin" and getMutPrio(aMut) >= 1 then return true end
    if aName == "Griffin" and MUTATED_BEATS_GRIFFIN[bName] and getMutPrio(bMut) >= 1 then return false end
    if aName == "Antonio" and bName == "Elefanto Frigo" and getMutPrio(aMut) >= 1 then return true end
    if aName == "Elefanto Frigo" and bName == "Antonio" and getMutPrio(bMut) >= 1 then return false end
    local tA = TIER_LOOKUP[aName] or 99
    local tB = TIER_LOOKUP[bName] or 99
    if not (TIER_LOOKUP[aName] and TIER_LOOKUP[bName]) then
        if tA == tB then return (aMPS or 0) > (bMPS or 0) end
        return tA < tB
    end
    if tA == tB then
        local pA, pB = getMutPrio(aMut), getMutPrio(bMut)
        if pA ~= pB then return pA > pB end
        return (aMPS or 0) > (bMPS or 0)
    end
    if tA == 4 and tB == 3 then return true end
    if tA == 3 and tB == 4 then return false end
    local hi = math.min(tA, tB)
    local lo = math.max(tA, tB)
    local hiMPS = tA < tB and aMPS or bMPS
    local loMPS = tA < tB and bMPS or aMPS
    local cum = getCumThreshold(hi, lo)
    if cum > 0 and cum ~= math.huge then
        if (loMPS or 0) - (hiMPS or 0) > cum then return tA > tB end
    end
    return tA < tB
end

local function getPlotChannel(plotName)
    if not Synchronizer then return nil end
    local channel
    pcall(function() channel = Synchronizer:Get(plotName) end)
    if not channel then pcall(function() channel = Synchronizer:Wait(plotName) end) end
    return channel
end

local function channelGet(channel, key)
    if not channel then return nil end
    local v
    pcall(function() if type(channel.Get) == "function" then v = channel:Get(key) end end)
    if v == nil then pcall(function() v = channel.CacheTable and channel.CacheTable[key] end) end
    return v
end

local function isMyPlot(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
    if not owner then return false end
    local result = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            result = owner.UserId == LP.UserId
        elseif type(owner) == "table" and owner.UserId then
            result = owner.UserId == LP.UserId
        elseif typeof(owner) == "Instance" then
            result = owner == LP
        end
    end)
    return result
end

local function ownerInGame(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
    if not owner then return false end
    local inGame = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        elseif type(owner) == "number" then
            inGame = Players:GetPlayerByUserId(owner) ~= nil
        elseif type(owner) == "table" and owner.Name then
            inGame = Players:FindFirstChild(tostring(owner.Name)) ~= nil
        elseif typeof(owner) == "Instance" and owner.Name then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        end
    end)
    return inGame
end

local function getPetPosition(plot, slot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(tostring(slot))
    if not podium then return nil end
    for _, desc in ipairs(podium:GetDescendants()) do
        if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
            local hasMesh = false
            for _, c in ipairs(desc:GetDescendants()) do
                if c:IsA("MeshPart") then hasMesh = true; break end
            end
            if hasMesh then
                local ok, cf = pcall(function() return desc:GetBoundingBox() end)
                if ok then return cf.Position end
            end
        end
    end
    local ok, cf = pcall(function() return podium:GetPivot() end)
    if ok then return cf.Position end
    return podium.Position
end

local function scanAllPets()
    local pets = {}
    if not loadModules() then return pets end
    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return pets end
    for _, plot in ipairs(Plots:GetChildren()) do
        local channel = getPlotChannel(plot.Name)
        if not channel then continue end
        if isMyPlot(channel) then continue end
        if not ownerInGame(channel) then continue end
        local animalList = channelGet(channel, "AnimalList")
        if not animalList then continue end
        for slot, animalData in pairs(animalList) do
            if type(animalData) ~= "table" then continue end
            local animalName = animalData.Index
            if not animalName then continue end
            local animalInfo = AnimalsData and AnimalsData[animalName]
            if not animalInfo then continue end
            if _VanishIsFusing(animalData) then continue end
            local mutation = animalData.Mutation or "None"
            local genValue = 0
            pcall(function()
                genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
            end)
            local displayName = (animalInfo and animalInfo.DisplayName) or animalName
            local pos = getPetPosition(plot, slot)
            if pos then
                local owner = channelGet(channel, "Owner")
                local ownerName = nil
                if typeof(owner) == "Instance" and owner:IsA("Player") then ownerName = owner.Name end
                if type(owner) == "table" and owner.Name then ownerName = owner.Name end
                table.insert(pets, {
                    name = displayName,
                    mps = genValue,
                    mutation = mutation,
                    position = pos,
                    plot = plot.Name,
                    slot = tostring(slot),
                    owner = ownerName,
                    uid = plot.Name .. "_" .. tostring(slot)
                })
            end
        end
    end
    table.sort(pets, function(a, b)
        return petOutranks(a.name, b.name, a.mutation, b.mutation, a.mps, b.mps)
    end)
    return pets
end

local UPPER = {
    B = {{coord=Vector3.new(-487.921448,16.850713,-75.768013),facing="NORTH"},{coord=Vector3.new(-332.379730,16.850722,-75.762100),facing="NORTH"},{coord=Vector3.new(-487.134918,16.850713,-18.094154),facing="SOUTH"},{coord=Vector3.new(-316.300171,16.850713,-17.845898),facing="SOUTH"}},
    C = {{coord=Vector3.new(-330.765381,16.850713,31.424425),facing="NORTH"},{coord=Vector3.new(-502.989349,16.850713,31.172430),facing="NORTH"},{coord=Vector3.new(-489.077087,16.850713,89.010147),facing="SOUTH"},{coord=Vector3.new(-330.908936,16.850713,88.930145),facing="SOUTH"}},
    D = {{coord=Vector3.new(-331.264893,16.850713,138.209167),facing="NORTH"},{coord=Vector3.new(-487.935181,16.850713,138.026321),facing="NORTH"},{coord=Vector3.new(-487.774933,16.850713,195.882538),facing="SOUTH"},{coord=Vector3.new(-330.799133,16.850575,196.022354),facing="SOUTH"}},
}
local LOWER = {
    B = {{coord=Vector3.new(-335.725586,-3.048217,-74.984589),facing="NORTH"},{coord=Vector3.new(-503.214233,-3.048217,-75.043137),facing="NORTH"},{coord=Vector3.new(-483.619385,-3.718430,-18.844337),facing="SOUTH"},{coord=Vector3.new(-316.147095,-3.048218,-18.818844),facing="SOUTH"}},
    C = {{coord=Vector3.new(-335.985413,-3.048218,32.051426),facing="NORTH"},{coord=Vector3.new(-503.277008,-3.048217,31.956175),facing="NORTH"},{coord=Vector3.new(-483.749390,-3.048218,88.147003),facing="SOUTH"},{coord=Vector3.new(-315.793823,-3.048217,88.163979),facing="SOUTH"}},
    D = {{coord=Vector3.new(-335.476654,-3.048218,139.001083),facing="NORTH"},{coord=Vector3.new(-503.710083,-3.048218,138.989883),facing="NORTH"},{coord=Vector3.new(-315.654938,-3.048218,195.302444),facing="SOUTH"},{coord=Vector3.new(-483.859253,-3.048218,195.269043),facing="SOUTH"}},
}
local UPPER_Y_THRESHOLD = 7
local TALL_PETS = { ["La Secret Combinasion"]=true, ["La Jolly Grande"]=true }
local TALL_OFFSET = 3

local function findClosest(petPos, coordTable)
    local best, bestKey, bestDist = nil, nil, math.huge
    for skyKey, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            local c = data.coord
            local d = math.sqrt((petPos.X - c.X)^2 + (petPos.Z - c.Z)^2)
            if d < bestDist then bestDist = d; best = data; bestKey = skyKey end
        end
    end
    return best, bestKey
end

local _vizParts = {}
local function clearViz()
    for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
    table.clear(_vizParts)
end
local function vizLine(a, b, color)
    if not S.DEBUG_VIZ then return end
    local d = b - a
    if d.Magnitude < 0.05 then return end
    local p = Instance.new("Part")
    p.Name = "P"
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Archivable = false
    p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(0.4, 0.4, d.Magnitude)
    p.CFrame = CFrame.new((a + b) / 2, b)
    p.Parent = workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizDot(pos, color, sz)
    if not S.DEBUG_VIZ then return end
    local p = Instance.new("Part")
    p.Name = "P"
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Archivable = false
    p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(sz, sz, sz)
    p.Position = pos
    p.Parent = workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizPath(fromPos, waypoints)
    if not S.DEBUG_VIZ then return end
    if #waypoints == 0 then return end
    vizDot(fromPos, Color3.fromRGB(255, 255, 255), 1.8)
    local prev = fromPos
    for _, wp in ipairs(waypoints) do
        vizLine(prev, wp, Color3.fromRGB(255, 0, 120))
        vizDot(wp, Color3.fromRGB(255, 100, 0), 1.6)
        prev = wp
    end
end

local SPEED = 200
local ARRIVE = 3

local function vZero(hrp)
    if hrp then hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end
end

local function velMoveThrough(hrp, waypoints)
    if not hrp or not hrp.Parent or #waypoints == 0 then return end
    vizPath(hrp.Position, waypoints)
    local wpIdx = 1
    local done = false
    local conn
    local function finish()
        if done then return end
        done = true
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            local _, y = hrp.CFrame:ToEulerAnglesYXZ()
            hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
        end
        if conn then conn:Disconnect() end
    end
    local lastDist, stall = math.huge, 0
    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or done then
            if conn then conn:Disconnect() end
            return
        end
        equipCarpet()
        local target = waypoints[wpIdx]
        local diff = target - hrp.Position
        local mag = diff.Magnitude
        if mag < ARRIVE then
            wpIdx = wpIdx + 1
            if wpIdx > #waypoints then finish() return end
            lastDist, stall = math.huge, 0
            target = waypoints[wpIdx]
            diff = target - hrp.Position
            mag = diff.Magnitude
        end
        if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
        lastDist = mag
        if stall >= 18 then finish() return end
        if mag >= 0.1 then
            local dir = diff.Unit
            local _sp = (_G.VanishCarpetSpeed or CARPET_SPEED)
            hrp.Velocity = Vector3.new(dir.X * _sp, dir.Y * _sp, dir.Z * _sp)
        end
    end)
    local totalDist = 0
    local prev = hrp.Position
    for _, wp in ipairs(waypoints) do
        totalDist = totalDist + (prev - wp).Magnitude
        prev = wp
    end
    local timeout = totalDist / SPEED + 2
    local elapsed = 0
    while not done and elapsed < timeout do
        task.wait(0.05)
        elapsed = elapsed + 0.05
    end
    finish()
    vZero(hrp)
end

local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
local _STRUCT = { ["structure base home"] = true, ["Wall"] = true, ["Floor"] = true, ["Roof"] = true }
local _SKIP_NAME = { ["DeliveryHitbox"]=true, ["StealHitbox"]=true, ["LaserHitbox"]=true,
    ["AnimalTarget"]=true, ["Multiplier"]=true, ["Laser"]=true, ["Hitbox"]=true,
    ["Spawn"]=true, ["MainRoot"]=true, ["SecondFloor"]=true, ["ThirdFloor"]=true, ["Slope"]=true }
local function _blocks(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
    local s = inst.Size
    if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 150 then return true end
    return false
end
local function _block(origin, target)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip + 1] = pl.Character end
    end
    local o = origin
    for _ = 1, 16 do
        rp.FilterDescendantsInstances = skip
        local d = target - o
        if d.Magnitude < 0.05 then return nil end
        local res = workspace:Raycast(o, d, rp)
        if not res then return nil end
        if _blocks(res.Instance) then return res end
        skip[#skip + 1] = res.Instance
        o = res.Position + d.Unit * 0.3
    end
    return nil
end
local function _clear(a, b) return _block(a, b) == nil end
local function _clearDist(origin, dir, maxD)
    local res = _block(origin, origin + dir.Unit * maxD)
    if not res then return maxD end
    return (res.Position - origin).Magnitude
end
local function _pull(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clear(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end
local function _stages(toPos)
    local st = {}
    for _, dr in ipairs(_DIRS) do
        local cd = _clearDist(toPos, dr, 46)
        if cd >= 12 then st[#st + 1] = toPos + dr * math.min(cd - 5, 38) end
    end
    return st
end
local function _routeClear(pts)
    for i = 1, #pts - 1 do
        if not _clear(pts[i], pts[i + 1]) then return false end
    end
    return true
end
local function _peakY(pts)
    local m = -math.huge
    for _, p in ipairs(pts) do if p.Y > m then m = p.Y end end
    return m
end
local function _starts(fromPos)
    local pts = { fromPos }
    if _block(fromPos, fromPos + Vector3.new(0, 40, 0)) then
        for _, dr in ipairs(_DIRS) do
            local cd = _clearDist(fromPos, dr, 40)
            if cd >= 12 then pts[#pts + 1] = fromPos + dr * math.min(cd - 5, 34) end
        end
    end
    return pts
end

local PathfindingService = game:GetService("PathfindingService")
local _CLEARANCE = 6
local function _clearWide(a, b)
    if not _clear(a, b) then return false end
    local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
    if d.Magnitude < 0.1 then return true end
    local p = Vector3.new(-d.Z, 0, d.X).Unit * _CLEARANCE
    return _clear(a + p, b + p) and _clear(a - p, b - p)
end
local function _pullWide(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clearWide(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end

local function computeRoute(fromPos, toPos, facingDir)
    if _clear(fromPos, toPos) then return { toPos } end
    local entry = facingDir and (toPos - facingDir * 14) or toPos
    local groundTo = Vector3.new(entry.X, fromPos.Y, entry.Z)
    local path = PathfindingService:CreatePath({
        AgentRadius = 8, AgentHeight = 5, AgentCanJump = true, AgentJumpHeight = 10, AgentMaxSlope = 89,
    })
    local FLOAT = 3
    local nav = { fromPos }
    local ok = pcall(function()
        path:ComputeAsync(Vector3.new(fromPos.X, fromPos.Y, fromPos.Z), groundTo)
    end)
    if ok and path.Status == Enum.PathStatus.Success then
        local last = fromPos
        for _, wp in ipairs(path:GetWaypoints()) do
            if (wp.Position - last).Magnitude >= 8 then
                nav[#nav + 1] = wp.Position + Vector3.new(0, FLOAT, 0)
                last = wp.Position
            end
        end
    end
    nav[#nav + 1] = entry + Vector3.new(0, FLOAT, 0)
    local route = _pullWide(nav)
    route[#route + 1] = toPos
    return route
end

local function equipTool(name)
    local char = LP.Character
    if not char or char:FindFirstChild(name) then return char ~= nil end
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return false end
    local tool = bp:FindFirstChild(name)
    if tool and tool:IsA("Tool") then tool.Parent = char; return true end
    return false
end

local function doClone()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return false end
    local cloner
    for _ = 1, 60 do
        local bp = LP:FindFirstChildOfClass("Backpack")
        cloner = char:FindFirstChild("Quantum Cloner") or (bp and bp:FindFirstChild("Quantum Cloner"))
        if cloner then break end
        task.wait(0.05)
    end
    if not cloner then return false end
    if cloner.Parent ~= char then pcall(function() hum:EquipTool(cloner) end); task.wait(0.02) end
    S.clickTool(cloner)
    local cloneName = tostring(LP.UserId) .. "_Clone"
    local clone = workspace:FindFirstChild(cloneName) or workspace:WaitForChild(cloneName, 3)
    if not clone then return false end
    task.wait(0.03)
    local tpButton
    for _ = 1, 80 do
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        local tf = pg and pg:FindFirstChild("ToolsFrames")
        local qc = tf and tf:FindFirstChild("QuantumCloner")
        tpButton = qc and qc:FindFirstChild("TeleportToClone")
        if tpButton then break end
        task.wait(0.05)
    end
    if not tpButton then return false end
    pcall(function() tpButton.Visible = true end)
    task.wait()
    local function fire()
        if S.clickButton(tpButton) then return end
        pcall(function() tpButton.Visible = true end)
        S.clickButton(tpButton)
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local start = hrp and hrp.Position
    local cloneName2 = tostring(LP.UserId) .. "_Clone"
    local charAdded = false
    local caConn = LP.CharacterAdded:Connect(function() charAdded = true end)
    local refired = false
    local rebuilt = false
    fire()
    for i = 1, 300 do
        RunService.Heartbeat:Wait()
        local _c = LP.Character
        local _h = _c and _c:FindFirstChild("HumanoidRootPart")
        local cloneGone = not workspace:FindFirstChild(cloneName2)
        if charAdded or _c ~= char then rebuilt = true end
        if not _h or not _h.Parent then
            rebuilt = true
        else
            local moved = start and (_h.Position - start).Magnitude > 5
            if rebuilt or cloneGone or moved then
                if caConn then caConn:Disconnect() end
                RunService.Heartbeat:Wait()
                return true
            end
        end
        if not refired and i >= 4 then
            refired = true
            fire()
        end
    end
    if caConn then caConn:Disconnect() end
    return rebuilt or charAdded or (not workspace:FindFirstChild(cloneName2))
end

_G.GetQuantumOnTeleportRemote = _G.GetQuantumOnTeleportRemote or function()
    if _G._QuantumOnTeleportRemote and _G._QuantumOnTeleportRemote.Parent then return _G._QuantumOnTeleportRemote end
    local Pkgs = RS:WaitForChild("Packages", 5)
    local Net = Pkgs and Pkgs:WaitForChild("Net", 5)
    if not Net then return nil end
    local real
    pcall(function()
        local u2 = require(Net)
        local proxy = u2:RemoteEvent("QuantumCloner/OnTeleport")
        local stringed = tostring(proxy)
        real = Net:FindFirstChild(stringed)
    end)
    if real and (real:IsA("RemoteEvent") or real:IsA("RemoteFunction")) then
        _G._QuantumOnTeleportRemote = real
        return real
    end
    return nil
end

local cloneMethod = _G.CloneMethod or "Remote"
function _G.instantClone()
    if _G.isCloning then return end
    _G.isCloning = true
    pcall(function()
        local character = LP.Character or LP.CharacterAdded:Wait()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        local bp = LP:FindFirstChildOfClass("Backpack")
        local cloner = (bp and bp:FindFirstChild("Quantum Cloner")) or character:FindFirstChild("Quantum Cloner")
        if not cloner then return end
        if cloner.Parent ~= character then
            pcall(function() humanoid:UnequipTools() end)
            pcall(function() humanoid:EquipTool(cloner) end)
            task.wait(0.02)
        end
        -- One activation; the old code fired it three times back to back, which
        -- looks like spam on the server side.
        pcall(function() cloner:Activate() end)
        local cloneName = tostring(LP.UserId) .. "_Clone"
        local deadline = os.clock() + 1.5
        while os.clock() < deadline and not workspace:FindFirstChild(cloneName) do
            RunService.Heartbeat:Wait()
        end
        if cloneMethod == "Remote" then
            local r = _G.GetQuantumOnTeleportRemote and _G.GetQuantumOnTeleportRemote()
            if r then pcall(function() r:FireServer() end) end
        else
            local pg = LP:FindFirstChildOfClass("PlayerGui")
            local tf = pg and pg:FindFirstChild("ToolsFrames")
            local qc = tf and tf:FindFirstChild("QuantumCloner")
            local btn = qc and qc:FindFirstChild("TeleportToClone")
            if btn then
                S.clickButton(btn)
            end
        end
    end)
    _G.isCloning = false
end

local function findAdorneeGlobal(animalData)
    if not animalData then return nil end
    local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(animalData.plot)
    if plot then
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            local podium = podiums:FindFirstChild(animalData.slot)
            if podium then
                local base = podium:FindFirstChild("Base")
                if base then
                    local spawn = base:FindFirstChild("Spawn")
                    if spawn then return spawn end
                end
            end
        end
    end
    return nil
end

local function goToBrainrotAfterClone(targetPetData, toolName, landingDelay)
    if not targetPetData then return end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local bp = LP:FindFirstChildOfClass("Backpack")
    local tool = (bp and bp:FindFirstChild(toolName)) or char:FindFirstChild(toolName)
    if tool then hum:EquipTool(tool) end
    task.wait(0.3)
    local targetPart = findAdorneeGlobal(targetPetData)
    if not targetPart then return end

    -- Descent without inserting anything into the world. The old version spawned
    -- invisible anchored parts in workspace and left them there for 20s; a server
    -- scan for foreign parts finds them instantly. Anchoring the root locally and
    -- tweening it down gives the same result with no new instance.
    local function descendTo(destPos)
        local dist = (destPos - hrp.Position).Magnitude
        local duration = math.clamp(dist / 110, 0.12, 0.65)
        pcall(function() hum.PlatformStand = true end)
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        local anchored = pcall(function() hrp.Anchored = true end)
        if anchored then
            local tween = TweenService:Create(
                hrp,
                TweenInfo.new(duration, Enum.EasingStyle.Quad),
                { CFrame = CFrame.new(destPos) }
            )
            tween:Play()
            task.wait(duration + 0.05)
        else
            pcall(function() hrp.CFrame = CFrame.new(destPos) end)
        end
        pcall(function() hrp.Anchored = false end)
        pcall(function() hum.PlatformStand = false end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local verticalDiff = targetPart.Position.Y - hrp.Position.Y
    if verticalDiff > 2 then
        descendTo(Vector3.new(targetPart.Position.X, targetPart.Position.Y - 5, targetPart.Position.Z))
    else
        if (hrp.Position - targetPart.Position).Magnitude > 3 then
            descendTo(targetPart.Position)
        end
    end
    task.wait(landingDelay or 0.48)
end

local isTeleporting = false

local function doVelocityTP()
    if isTeleporting then return end
    isTeleporting = true
    clearViz()
    _G.TPStatus = "start"
    if not NetModule then pcall(loadNet) end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then _G.TPStatus = "no_char"; isTeleporting = false; return end
    local allPets = scanAllPets()
    if #allPets == 0 then
        local _t0 = os.clock()
        while #allPets == 0 and os.clock() - _t0 < 4 do
            task.wait(0.15)
            allPets = scanAllPets()
        end
    end
    if #allPets == 0 then _G.TPStatus = "no_brainrot_found"; warn("[TP] no_brainrot_found"); isTeleporting = false; return end
    local pet = allPets[1]
    local petPos = pet.position
    local petName = pet.name
    _G.TPStatus = "target=" .. tostring(petName)
    local adjY = petPos.Y
    if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
    local coordTable = adjY > UPPER_Y_THRESHOLD and UPPER or LOWER
    local closestData, skyKey = findClosest(petPos, coordTable)
    if not closestData or not skyKey then _G.TPStatus = "no_sky_platform"; warn("[TP] no_sky_platform"); isTeleporting = false; return end
    local destPos = closestData.coord
    local maxHP = hum.MaxHealth
    -- Only write when the value actually changes: re-asserting MaxHealth every
    -- single frame is a behavioural tell.
    if hum.Health < maxHP then pcall(function() hum.Health = maxHP end) end
    local healTicks = 0
    local healConn = RunService.Heartbeat:Connect(function()
        if not hum or not hum.Parent then return end
        healTicks = healTicks + 1
        if healTicks % 6 ~= 0 then return end
        if hum.Health < hum.MaxHealth then pcall(function() hum.Health = hum.MaxHealth end) end
    end)
    local _carpet = carpetEngage()
    _G.TPStatus = _carpet and ("carpet:" .. _carpet) or "NO_carpet"
    if not _carpet then warn("[TP] NO CARPET FOUND") end
    vZero(hrp)
    local facingDir = closestData.facing == "NORTH" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
    local _route = computeRoute(hrp.Position, destPos, facingDir)
    velMoveThrough(hrp, _route)
    hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
    vZero(hrp)
    local syncFrames = 5
    local syncConn
    syncConn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent then syncConn:Disconnect(); return end
        syncFrames = syncFrames - 1
        hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if syncFrames <= 0 then syncConn:Disconnect() end
    end)
    for _ = 1, 20 do
        task.wait(0.05)
        if hum.FloorMaterial ~= Enum.Material.Air then break end
    end
    healConn:Disconnect()
    isTeleporting = false
    do
        local stable = 0
        for _ = 1, 50 do
            local _hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not _hrp or not _hrp.Parent then break end
            local flat = (Vector3.new(_hrp.Position.X, 0, _hrp.Position.Z) - Vector3.new(destPos.X, 0, destPos.Z)).Magnitude
            if flat <= 3.5 and math.abs(_hrp.Position.Y - destPos.Y) <= 4 then
                stable = stable + 1
                if stable >= 4 then break end
            else
                stable = 0
                pcall(function() _hrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
                _hrp.AssemblyLinearVelocity = Vector3.zero
                _hrp.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end
    _G.TPStatus = "at_sky_before_clone"
    local _ahrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if _ahrp and _ahrp.Parent then
        _ahrp.AssemblyLinearVelocity = Vector3.zero
        _ahrp.AssemblyAngularVelocity = Vector3.zero
        pcall(function() _ahrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
        pcall(function() _ahrp.Anchored = true end)
    end
    task.wait(SKY_CLONE_WAIT)
    if _ahrp and _ahrp.Parent then pcall(function() _ahrp.Anchored = false end) end
    if doClone() then
        _G.TPStatus = "clone_ok"
        task.wait(0.1)
        goToBrainrotAfterClone(pet, "Grapple Hook", (_G.LandingDelay or 300) / 1000)
        -- Was SendKeyEvent(Enum.KeyCode.C): a synthetic key press through the
        -- engine input service. The intent is simply "fire the grapple".
        task.spawn(function() S.fireGrappleSafe() end)
        task.wait(0.1)
        local _fhrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if _fhrp and _fhrp.Parent then
            _fhrp.AssemblyLinearVelocity = Vector3.zero
            _fhrp.AssemblyAngularVelocity = Vector3.zero
        end
        _G.selectedStealPet = pet
        _G.focusStealPet = pet
    else
        _G.TPStatus = "clone_FAILED"
        local _fhrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if _fhrp and _fhrp.Parent then
            _fhrp.AssemblyLinearVelocity = Vector3.zero
            _fhrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
    warn("[TP] final status = " .. tostring(_G.TPStatus))
end

_G.VanishStartSideTP = doVelocityTP
_G.VanishFireGrapple = fireGrapple

task.spawn(function() pcall(loadModules) pcall(loadNet) end)

local function doTPtoPet(pet)
    if isTeleporting then return end
    isTeleporting = true
    clearViz()
    _G.TPStatus = "start"
    if not NetModule then pcall(loadNet) end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then _G.TPStatus = "no_char"; isTeleporting = false; return end
    local petPos = pet.position
    local petName = pet.name
    _G.TPStatus = "target=" .. tostring(petName)
    local adjY = petPos.Y
    if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
    local coordTable = adjY > UPPER_Y_THRESHOLD and UPPER or LOWER
    local closestData, skyKey = findClosest(petPos, coordTable)
    if not closestData or not skyKey then _G.TPStatus = "no_sky_platform"; warn("[TP] no_sky_platform"); isTeleporting = false; return end
    local destPos = closestData.coord
    local maxHP = hum.MaxHealth
    -- Only write when the value actually changes: re-asserting MaxHealth every
    -- single frame is a behavioural tell.
    if hum.Health < maxHP then pcall(function() hum.Health = maxHP end) end
    local healTicks = 0
    local healConn = RunService.Heartbeat:Connect(function()
        if not hum or not hum.Parent then return end
        healTicks = healTicks + 1
        if healTicks % 6 ~= 0 then return end
        if hum.Health < hum.MaxHealth then pcall(function() hum.Health = hum.MaxHealth end) end
    end)
    local _carpet = carpetEngage()
    _G.TPStatus = _carpet and ("carpet:" .. _carpet) or "NO_carpet"
    if not _carpet then warn("[TP] NO CARPET FOUND") end
    vZero(hrp)
    local facingDir = closestData.facing == "NORTH" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
    local _route = computeRoute(hrp.Position, destPos, facingDir)
    velMoveThrough(hrp, _route)
    hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
    vZero(hrp)
    local syncFrames = 5
    local syncConn
    syncConn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent then syncConn:Disconnect(); return end
        syncFrames = syncFrames - 1
        hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if syncFrames <= 0 then syncConn:Disconnect() end
    end)
    for _ = 1, 20 do
        task.wait(0.05)
        if hum.FloorMaterial ~= Enum.Material.Air then break end
    end
    healConn:Disconnect()
    isTeleporting = false
    do
        local stable = 0
        for _ = 1, 50 do
            local _hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not _hrp or not _hrp.Parent then break end
            local flat = (Vector3.new(_hrp.Position.X, 0, _hrp.Position.Z) - Vector3.new(destPos.X, 0, destPos.Z)).Magnitude
            if flat <= 3.5 and math.abs(_hrp.Position.Y - destPos.Y) <= 4 then
                stable = stable + 1
                if stable >= 4 then break end
            else
                stable = 0
                pcall(function() _hrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
                _hrp.AssemblyLinearVelocity = Vector3.zero
                _hrp.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end
    _G.TPStatus = "at_sky_before_clone"
    local _ahrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if _ahrp and _ahrp.Parent then
        _ahrp.AssemblyLinearVelocity = Vector3.zero
        _ahrp.AssemblyAngularVelocity = Vector3.zero
        pcall(function() _ahrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
        pcall(function() _ahrp.Anchored = true end)
    end
    task.wait(SKY_CLONE_WAIT)
    if _ahrp and _ahrp.Parent then pcall(function() _ahrp.Anchored = false end) end
    if doClone() then
        _G.TPStatus = "clone_ok"
        task.wait(0.1)
        goToBrainrotAfterClone(pet, "Grapple Hook", (_G.LandingDelay or 300) / 1000)
        -- Was SendKeyEvent(Enum.KeyCode.C): a synthetic key press through the
        -- engine input service. The intent is simply "fire the grapple".
        task.spawn(function() S.fireGrappleSafe() end)
        task.wait(0.1)
        local _fhrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if _fhrp and _fhrp.Parent then
            _fhrp.AssemblyLinearVelocity = Vector3.zero
            _fhrp.AssemblyAngularVelocity = Vector3.zero
        end
        _G.selectedStealPet = pet
        _G.focusStealPet = pet
    else
        _G.TPStatus = "clone_FAILED"
        local _fhrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if _fhrp and _fhrp.Parent then
            _fhrp.AssemblyLinearVelocity = Vector3.zero
            _fhrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
    warn("[TP] final status = " .. tostring(_G.TPStatus))
end

local function formatMPS(v)
    if not v or v == 0 then return "?" end
    if v >= 1e12 then return string.format("%.1fT", v / 1e12) end
    if v >= 1e9  then return string.format("%.1fB", v / 1e9)  end
    if v >= 1e6  then return string.format("%.1fM", v / 1e6)  end
    if v >= 1e3  then return string.format("%.1fK", v / 1e3)  end
    return tostring(math.floor(v))
end

local MUT_COLORS = {
    Galaxy     = Color3.fromRGB(255, 80, 80),
    Candy      = Color3.fromRGB(255, 80, 80),
    ["Yin Yang"] = Color3.fromRGB(255, 80, 80),
    YinYang    = Color3.fromRGB(255, 80, 80),
    Divine     = Color3.fromRGB(255, 80, 80),
    Cursed     = Color3.fromRGB(255, 80, 80),
    Lava       = Color3.fromRGB(255, 80, 80),
    Radioactive= Color3.fromRGB(255, 80, 80),
    Cyber      = Color3.fromRGB(255, 80, 80),
    Rainbow    = Color3.fromRGB(255, 80, 80),
    Bloodrot   = Color3.fromRGB(200, 0, 50),
}
local function getMutColor(mut)
    if not mut or mut == "" or mut == "None" then return Color3.fromRGB(180, 180, 180) end
    return MUT_COLORS[mut] or Color3.fromRGB(255, 80, 80)
end

-- FIX: the old version resolved `(gethui and gethui())` for the progress bar and
-- then called :Destroy() on it, which destroyed the executor's whole hidden UI
-- container. The menu was then parented into that dead container and never
-- rendered. It also touched CoreGui outside of a pcall, so an executor that
-- blocks CoreGui killed the script before the menu was built.
local function cleanupOldGui()
    local containers = {}
    local function addContainer(c)
        if c then
            for _, existing in ipairs(containers) do
                if existing == c then return end
            end
            containers[#containers + 1] = c
        end
    end
    pcall(function() addContainer(S.hiddenRoot()) end)
    pcall(function() addContainer(game:GetService("CoreGui")) end)
    pcall(function() addContainer(LP:FindFirstChildOfClass("PlayerGui")) end)

    local stale = { "SkiddedBrainrotTP", "StealProgressBar", "Fx" }
    for _, container in ipairs(containers) do
        for _, name in ipairs(stale) do
            local old
            pcall(function() old = container:FindFirstChild(name) end)
            if old then pcall(function() old:Destroy() end) end
        end
    end
    for _, name in ipairs({ "BrainrotESP", "SkiddedViz", "PathViz" }) do
        local old = workspace:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end
end
pcall(cleanupOldGui)

local U = {
    BG = Color3.fromRGB(0, 0, 0),
    CARD = Color3.fromRGB(0, 0, 0),
    LINE = Color3.fromRGB(44, 44, 52),
    PANEL_LINE = Color3.fromRGB(52, 52, 62),
    ACC = Color3.fromRGB(220, 72, 72),
    ACC_DIM = Color3.fromRGB(150, 42, 46),
    TRACK = Color3.fromRGB(40, 42, 50),
    TXT = Color3.fromRGB(234, 236, 242),
    MUT = Color3.fromRGB(132, 138, 154),
    KNOB = Color3.fromRGB(245, 247, 252),
    WHITE = Color3.fromRGB(255, 255, 255),
    FILE = "cfg_state.json",
}
local PAD = 10

local SG_ROOT = S.hiddenRoot()

local sg = Instance.new("ScreenGui")
sg.Name = "Panel"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okSg = pcall(function() sg.Parent = SG_ROOT end)
if not okSg or not sg.Parent then
    pcall(function() sg.Parent = LP:FindFirstChildOfClass("PlayerGui") end)
end
S.protect(sg)

local progressBarGui = Instance.new("ScreenGui")
progressBarGui.Name = "Hud"
progressBarGui.ResetOnSpawn = false
progressBarGui.IgnoreGuiInset = true
progressBarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okPb = pcall(function() progressBarGui.Parent = SG_ROOT end)
if not okPb or not progressBarGui.Parent then
    pcall(function() progressBarGui.Parent = LP:FindFirstChildOfClass("PlayerGui") end)
end
S.protect(progressBarGui)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 296, 0, 362)
mainFrame.Position = UDim2.new(0, 16, 0.5, -181)
mainFrame.BackgroundColor3 = U.BG
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = sg

local selectorFrame = Instance.new("Frame")
selectorFrame.Name = "BrainrotSelector"
selectorFrame.Size = UDim2.new(0, 224, 0, 250)
selectorFrame.Position = UDim2.new(0, 324, 0.5, -125)
selectorFrame.BackgroundColor3 = U.BG
selectorFrame.BorderSizePixel = 0
selectorFrame.Active = true
selectorFrame.Parent = sg

local H = {}
function H.corner(o, r)
    local c = Instance.new("UICorner", o)
    c.CornerRadius = UDim.new(0, r or 8)
    return c
end
function H.stroke(o, col, th, tr)
    local s = Instance.new("UIStroke", o)
    s.Color = col
    s.Thickness = th or 1
    s.Transparency = tr or 0
    return s
end
function H.accent(parent)
    local b = Instance.new("Frame")
    b.Size = UDim2.new(0, 3, 1, -12)
    b.Position = UDim2.new(0, 0, 0, 6)
    b.BackgroundColor3 = U.ACC
    b.BorderSizePixel = 0
    b.Parent = parent
    H.corner(b, 2)
end
function H.row(y, h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -PAD * 2, 0, h)
    f.Position = UDim2.new(0, PAD, 0, y)
    f.BackgroundColor3 = U.CARD
    f.BorderSizePixel = 0
    f.Parent = mainFrame
    H.corner(f, 7)
    H.stroke(f, U.LINE, 1, 0.2)
    H.accent(f)
    return f
end
function H.cap(y, txt)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -PAD * 2, 0, 12)
    l.Position = UDim2.new(0, PAD + 2, 0, y)
    l.BackgroundTransparency = 1
    l.Text = txt
    l.TextColor3 = U.MUT
    l.Font = Enum.Font.GothamBold
    l.TextSize = 9
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = mainFrame
end
function H.lbl(parent, w, txt)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 1, 0)
    l.Position = UDim2.new(0, 12, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = txt
    l.TextColor3 = U.TXT
    l.Font = Enum.Font.GothamBold
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end
function H.track(parent)
    local t = Instance.new("Frame")
    t.Size = UDim2.new(1, -134, 0, 5)
    t.Position = UDim2.new(0, 122, 0.5, -2)
    t.BackgroundColor3 = U.TRACK
    t.BorderSizePixel = 0
    t.Parent = parent
    H.corner(t, 3)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0.4, 0, 1, 0)
    fill.BackgroundColor3 = U.ACC
    fill.BorderSizePixel = 0
    fill.Parent = t
    H.corner(fill, 3)
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0.4, 0, 0.5, 0)
    knob.BackgroundColor3 = U.KNOB
    knob.BorderSizePixel = 0
    knob.AutoButtonColor = false
    knob.Text = ""
    knob.ZIndex = 5
    knob.Parent = t
    H.corner(knob, 7)
    H.stroke(knob, U.ACC, 2, 0)
    return t, fill, knob
end
function H.tog(x, y, w, txt)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 26)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = U.ACC_DIM
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Text = txt
    b.TextColor3 = U.WHITE
    b.Font = Enum.Font.GothamBold
    b.TextSize = 9
    b.Parent = mainFrame
    H.corner(b, 6)
    return b
end
function H.drag(handle, target, onDone)
    local dragging, startPos, origin
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = input.Position
            origin = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onDone then onDone(target.Position) end
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - startPos
            target.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
        end
    end)
end

H.corner(mainFrame, 10)
H.stroke(mainFrame, U.PANEL_LINE, 1, 0.05)
H.corner(selectorFrame, 10)
H.stroke(selectorFrame, U.PANEL_LINE, 1, 0.05)

do
    local ok, data = pcall(function()
        if readfile and isfile and isfile(U.FILE) then
            return game:GetService("HttpService"):JSONDecode(readfile(U.FILE))
        end
    end)
    if ok and type(data) == "table" then
        _G.SavedConfig = data
    end
end

local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(0, 320, 0, 40)
progressFrame.Position = UDim2.new(0.5, 0, 1, -64)
progressFrame.AnchorPoint = Vector2.new(0.5, 1)
progressFrame.BackgroundColor3 = U.BG
progressFrame.BorderSizePixel = 0
progressFrame.Parent = progressBarGui
H.corner(progressFrame, 9)
H.stroke(progressFrame, U.PANEL_LINE, 1, 0.1)

local progressDot = Instance.new("Frame")
progressDot.Size = UDim2.new(0, 7, 0, 7)
progressDot.AnchorPoint = Vector2.new(0, 0.5)
progressDot.Position = UDim2.new(0, 12, 0, 14)
progressDot.BackgroundColor3 = Color3.fromRGB(90, 110, 90)
progressDot.BorderSizePixel = 0
progressDot.ZIndex = 3
progressDot.Parent = progressFrame
H.corner(progressDot, 4)

local progressText = Instance.new("TextLabel")
progressText.Size = UDim2.new(1, -34, 0, 16)
progressText.Position = UDim2.new(0, 25, 0, 6)
progressText.BackgroundTransparency = 1
progressText.Text = "discord.gg/Z7vPrxecnJ"
progressText.TextColor3 = U.MUT
progressText.Font = Enum.Font.GothamBold
progressText.TextSize = 11
progressText.TextXAlignment = Enum.TextXAlignment.Left
progressText.Parent = progressFrame

local progressBg = Instance.new("Frame")
progressBg.Size = UDim2.new(1, -22, 0, 7)
progressBg.Position = UDim2.new(0, 11, 1, -13)
progressBg.BackgroundColor3 = U.TRACK
progressBg.BorderSizePixel = 0
progressBg.ZIndex = 0
progressBg.Parent = progressFrame
H.corner(progressBg, 4)

local progressBarFill = Instance.new("Frame")
progressBarFill.Size = UDim2.new(0, 0, 0, 7)
progressBarFill.Position = UDim2.new(0, 11, 1, -13)
progressBarFill.BackgroundColor3 = U.ACC
progressBarFill.BorderSizePixel = 0
progressBarFill.ZIndex = 1
progressBarFill.Parent = progressFrame
H.corner(progressBarFill, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = U.BG
header.BorderSizePixel = 0
header.Parent = mainFrame
H.corner(header, 10)
do
    local patch = Instance.new("Frame")
    patch.Size = UDim2.new(1, 0, 0, 12)
    patch.Position = UDim2.new(0, 0, 1, -12)
    patch.BackgroundColor3 = U.BG
    patch.BorderSizePixel = 0
    patch.Parent = header
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 1, -1)
    line.BackgroundColor3 = U.ACC
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0
    line.Parent = header
    local logo = Instance.new("Frame")
    logo.Size = UDim2.new(0, 14, 0, 14)
    logo.Position = UDim2.new(0, 10, 0.5, -7)
    logo.BackgroundColor3 = U.ACC
    logo.BorderSizePixel = 0
    logo.Parent = header
    H.corner(logo, 4)
    local logoText = Instance.new("TextLabel", logo)
logoText.Size = UDim2.new(1, 0, 1, 0)
logoText.BackgroundTransparency = 1
logoText.Text = "⚡️"
logoText.TextColor3 = Color3.fromRGB(255, 255, 255)
logoText.Font = Enum.Font.GothamBold
logoText.TextSize = 10
logoText.TextXAlignment = Enum.TextXAlignment.Center
logoText.TextYAlignment = Enum.TextYAlignment.Center
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -120, 1, 0)
    title.Position = UDim2.new(0, 30, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Brainrot TP"
    title.TextColor3 = U.WHITE
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
end

local statusBar = Instance.new("TextLabel")
statusBar.Size = UDim2.new(0, 84, 1, 0)
statusBar.Position = UDim2.new(1, -94, 0, 0)
statusBar.BackgroundTransparency = 1
statusBar.Text = "idle"
statusBar.TextColor3 = U.ACC
statusBar.Font = Enum.Font.GothamBold
statusBar.TextSize = 10
statusBar.TextXAlignment = Enum.TextXAlignment.Right
statusBar.Parent = header

H.cap(33, "MOVEMENT")

-- Sliders are built from a spec table instead of one local per widget. The main
-- chunk has to stay under Luau's 200-active-local limit, so a dozen widget
-- locals per slider is not affordable.
local SLIDERS = {}
local function makeSlider(spec)
    local row = H.row(spec.y, 28)
    local lbl = H.lbl(row, spec.lblW or 110, spec.header)

    local track, fill, knob
    if spec.plain then
        track = Instance.new("Frame")
        track.Size = UDim2.new(1, -116, 0, 5)
        track.Position = UDim2.new(0, 66, 0.5, -2)
        track.BackgroundColor3 = U.TRACK
        track.BorderSizePixel = 0
        track.Parent = row
        H.corner(track, 3)
        fill = Instance.new("Frame")
        fill.Size = UDim2.new(0.3, 0, 1, 0)
        fill.BackgroundColor3 = U.ACC
        fill.BorderSizePixel = 0
        fill.Parent = track
        H.corner(fill, 3)
        knob = Instance.new("TextButton")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(0.3, 0, 0.5, 0)
        knob.BackgroundColor3 = U.KNOB
        knob.BorderSizePixel = 0
        knob.AutoButtonColor = false
        knob.Text = ""
        knob.ZIndex = 5
        knob.Parent = track
        H.corner(knob, 7)
        H.stroke(knob, U.ACC, 2, 0)
    else
        track, fill, knob = H.track(row)
    end

    local valueLbl = lbl
    if spec.valueLabel then
        valueLbl = Instance.new("TextLabel")
        valueLbl.Size = UDim2.new(0, 34, 1, 0)
        valueLbl.Position = UDim2.new(1, -42, 0, 0)
        valueLbl.BackgroundTransparency = 1
        valueLbl.Text = ""
        valueLbl.TextColor3 = U.ACC
        valueLbl.Font = Enum.Font.GothamBold
        valueLbl.TextSize = 10
        valueLbl.TextXAlignment = Enum.TextXAlignment.Right
        valueLbl.Parent = row
    end

    local s = { track = track, fill = fill, knob = knob, minV = spec.minV, maxV = spec.maxV, dragging = false, value = spec.initial }
    function s.set(alpha)
        alpha = math.clamp(alpha, 0, 1)
        local v = math.floor(s.minV + alpha * (s.maxV - s.minV))
        s.value = v
        spec.onValue(v)
        valueLbl.Text = spec.fmt(v)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        _G.SavedConfig = _G.SavedConfig or {}
        _G.SavedConfig[spec.key] = v
    end
    function s.setRaw(v)
        v = math.clamp(tonumber(v) or spec.initial, s.minV, s.maxV)
        s.set((v - s.minV) / (s.maxV - s.minV))
    end

    knob.MouseButton1Down:Connect(function() s.dragging = true end)
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            s.dragging = true
            s.set((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
        end
    end)

    SLIDERS[#SLIDERS + 1] = s
    s.setRaw(spec.initial)
    return s
end

-- One shared input handler for all sliders instead of two connections each.
UIS.InputChanged:Connect(function(inp)
    if inp.UserInputType ~= Enum.UserInputType.MouseMovement and inp.UserInputType ~= Enum.UserInputType.Touch then return end
    for _, s in ipairs(SLIDERS) do
        if s.dragging then
            local ok, ax = pcall(function() return s.track.AbsolutePosition.X end)
            if ok then
                local w = s.track.AbsoluteSize.X
                if w > 0 then s.set((inp.Position.X - ax) / w) end
            end
        end
    end
end)
UIS.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        for _, s in ipairs(SLIDERS) do s.dragging = false end
    end
end)

local speedSlider = makeSlider({
    y = 46, header = "Speed: 400", key = "CarpetSpeed",
    minV = 50, maxV = 950,
    initial = (_G.SavedConfig and tonumber(_G.SavedConfig.CarpetSpeed)) or 400,
    fmt = function(v) return "Speed: " .. v end,
    onValue = function(v) _G.VanishCarpetSpeed = v end,
})
local joinSlider = makeSlider({
    y = 78, header = "Join: 5000ms", key = "JoinDelay",
    minV = 0, maxV = 15000,
    initial = (_G.SavedConfig and tonumber(_G.SavedConfig.JoinDelay)) or 5000,
    fmt = function(v) return "Join: " .. v .. "ms" end,
    onValue = function(v) _G.JoinDelay = v end,
})
local landingSlider = makeSlider({
    y = 110, header = "Land: 300ms", key = "LandingDelay",
    minV = 0, maxV = 3000,
    initial = (_G.SavedConfig and tonumber(_G.SavedConfig.LandingDelay)) or 300,
    fmt = function(v) return "Land: " .. v .. "ms" end,
    onValue = function(v) _G.LandingDelay = v end,
})
local radiusSlider = makeSlider({
    y = 220, lblW = 50, header = "Radius", plain = true, valueLabel = true,
    key = "StealRadius", minV = 5, maxV = 30,
    initial = (_G.SavedConfig and tonumber(_G.SavedConfig.StealRadius)) or 15,
    fmt = function(v) return tostring(v) end,
    onValue = function(v) _G.StealRadius = v end,
})

H.cap(252, "PROTECTION")

local autoTPToggle = H.tog(10, 266, 134, "Auto TP OFF")
local antiRagdollToggle = H.tog(152, 266, 134, "Anti-Ragdoll OFF")
local antiBeeToggle = H.tog(10, 296, 134, "Anti-Bee OFF")
local espToggle = H.tog(152, 296, 134, "ESP OFF")
local respawnBtn = H.tog(10, 326, 276, "INSTANT RESPAWN")
respawnBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)

local selHeader = Instance.new("Frame")
selHeader.Size = UDim2.new(1, 0, 0, 26)
selHeader.BackgroundColor3 = U.BG
selHeader.BorderSizePixel = 0
selHeader.Parent = selectorFrame
H.corner(selHeader, 10)
do
    local patch = Instance.new("Frame")
    patch.Size = UDim2.new(1, 0, 0, 11)
    patch.Position = UDim2.new(0, 0, 1, -11)
    patch.BackgroundColor3 = U.BG
    patch.BorderSizePixel = 0
    patch.Parent = selHeader
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 1, -1)
    line.BackgroundColor3 = U.ACC
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0
    line.Parent = selHeader
    local logo = Instance.new("Frame")
    logo.Size = UDim2.new(0, 12, 0, 12)
    logo.Position = UDim2.new(0, 9, 0.5, -6)
    logo.BackgroundColor3 = U.ACC
    logo.BorderSizePixel = 0
    logo.Parent = selHeader
    H.corner(logo, 3)
    local logoText = Instance.new("TextLabel", logo)
logoText.Size = UDim2.new(1, 0, 1, 0)
logoText.BackgroundTransparency = 1
logoText.Text = "🌀"
logoText.TextColor3 = Color3.fromRGB(255, 255, 255)
logoText.Font = Enum.Font.GothamBold
logoText.TextSize = 9
logoText.TextXAlignment = Enum.TextXAlignment.Center
logoText.TextYAlignment = Enum.TextYAlignment.Center
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -90, 1, 0)
    title.Position = UDim2.new(0, 26, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Brainrot"
    title.TextColor3 = U.WHITE
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = selHeader
end

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 54, 0, 18)
refreshBtn.Position = UDim2.new(1, -60, 0.5, -9)
refreshBtn.BackgroundColor3 = U.ACC_DIM
refreshBtn.BorderSizePixel = 0
refreshBtn.AutoButtonColor = true
refreshBtn.Text = "🔄"
refreshBtn.TextColor3 = U.WHITE
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 9
refreshBtn.Parent = selHeader
H.corner(refreshBtn, 5)

local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, -20, 0, 12)
countLabel.Position = UDim2.new(0, 10, 0, 30)
countLabel.BackgroundTransparency = 1
countLabel.Text = "Loading..."
countLabel.TextColor3 = U.MUT
countLabel.Font = Enum.Font.Gotham
countLabel.TextSize = 9
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = selectorFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -16, 1, -52)
scrollFrame.Position = UDim2.new(0, 8, 0, 44)
scrollFrame.BackgroundColor3 = U.BG
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 3
scrollFrame.ScrollBarImageColor3 = U.ACC
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = selectorFrame
H.corner(scrollFrame, 7)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = scrollFrame

local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 4)
listPad.PaddingLeft = UDim.new(0, 4)
listPad.PaddingRight = UDim.new(0, 4)
listPad.PaddingBottom = UDim.new(0, 4)
listPad.Parent = scrollFrame

do
    local sc = _G.SavedConfig
    local function applyPos(frame, pos)
        if type(pos) ~= "table" or #pos ~= 4 then return end
        for i = 1, 4 do
            if type(pos[i]) ~= "number" then return end
        end
        pcall(function()
            frame.Position = UDim2.new(pos[1], pos[2], pos[3], pos[4])
        end)
    end
    if sc then
        applyPos(mainFrame, sc.MainPos)
        applyPos(selectorFrame, sc.SelectorPos)
    end
end

H.drag(header, mainFrame, function(p)
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.MainPos = { p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset }
end)
H.drag(selHeader, selectorFrame, function(p)
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.SelectorPos = { p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset }
end)

task.spawn(function()
    local last = nil
    while sg and sg.Parent do
        local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(_G.SavedConfig or {}) end)
        if ok and enc and enc ~= last then
            last = enc
            pcall(function() if writefile then writefile(U.FILE, enc) end end)
        end
        task.wait(0.4)
    end
end)

local currentPets = {}

local function clearList()
    for _, c in ipairs(scrollFrame:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
    end
end

local function buildList(pets)
    clearList()
    currentPets = pets
    if #pets == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, -8, 0, 36)
        empty.BackgroundTransparency = 1
        empty.Text = "No brainrot found"
        empty.TextColor3 = Color3.fromRGB(160, 80, 80)
        empty.Font = Enum.Font.GothamBold
        empty.TextSize = 12
        empty.LayoutOrder = 1
        empty.Parent = scrollFrame
        countLabel.Text = "0 brainrot"
        return
    end
    countLabel.Text = tostring(#pets) .. " brainrot(s)"
    for i, pet in ipairs(pets) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -8, 0, 40)
        btn.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        btn.BorderSizePixel = 0
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.LayoutOrder = i
        btn.Parent = scrollFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
        local bStroke = Instance.new("UIStroke", btn)
        bStroke.Color = Color3.fromRGB(32, 36, 50)
        bStroke.Thickness = 1
        local rankLbl = Instance.new("TextLabel")
        rankLbl.Size = UDim2.new(0, 26, 1, 0)
        rankLbl.BackgroundTransparency = 1
        rankLbl.Text = "#" .. i
        rankLbl.TextColor3 = Color3.fromRGB(70, 75, 100)
        rankLbl.Font = Enum.Font.GothamBold
        rankLbl.TextSize = 9
        rankLbl.Parent = btn
        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -114, 0, 18)
        nameLbl.Position = UDim2.new(0, 26, 0, 3)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = pet.name
        nameLbl.TextColor3 = Color3.fromRGB(225, 228, 245)
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 11
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = btn
        local subLbl = Instance.new("TextLabel")
        subLbl.Size = UDim2.new(1, -114, 0, 16)
        subLbl.Position = UDim2.new(0, 26, 0, 20)
        subLbl.BackgroundTransparency = 1
        subLbl.Font = Enum.Font.Gotham
        subLbl.TextSize = 9
        subLbl.TextXAlignment = Enum.TextXAlignment.Left
        subLbl.Parent = btn
        if pet.mutation and pet.mutation ~= "" and pet.mutation ~= "None" then
            subLbl.Text = "✨" .. pet.mutation
            subLbl.TextColor3 = getMutColor(pet.mutation)
        else
            subLbl.Text = "Plot " .. tostring(pet.plot) .. " · Slot " .. tostring(pet.slot)
            subLbl.TextColor3 = Color3.fromRGB(70, 80, 105)
        end
        local mpsLbl = Instance.new("TextLabel")
        mpsLbl.Size = UDim2.new(0, 50, 0, 18)
        mpsLbl.Position = UDim2.new(1, -84, 0, 3)
        mpsLbl.BackgroundTransparency = 1
        mpsLbl.Text = formatMPS(pet.mps) .. "/s"
        mpsLbl.TextColor3 = Color3.fromRGB(200, 50, 50)
        mpsLbl.Font = Enum.Font.GothamBold
        mpsLbl.TextSize = 10
        mpsLbl.TextXAlignment = Enum.TextXAlignment.Right
        mpsLbl.Parent = btn
        local tpBtn = Instance.new("TextButton")
        tpBtn.Size = UDim2.new(0, 26, 0, 26)
        tpBtn.Position = UDim2.new(1, -30, 0.5, -13)
        tpBtn.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        tpBtn.BorderSizePixel = 0
        tpBtn.Text = "▶"
        tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        tpBtn.Font = Enum.Font.GothamBold
        tpBtn.TextSize = 11
        tpBtn.Parent = btn
        Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 5)
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(25, 28, 40)}):Play()
            TweenService:Create(bStroke, TweenInfo.new(0.1), {Color = Color3.fromRGB(200, 50, 50), Transparency = 0}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(18, 20, 27)}):Play()
            TweenService:Create(bStroke, TweenInfo.new(0.1), {Color = Color3.fromRGB(32, 36, 50), Transparency = 0}):Play()
        end)
        local function onTP()
            if isTeleporting then return end
            statusBar.Text = "→ " .. pet.name
            statusBar.TextColor3 = Color3.fromRGB(255, 100, 0)
            task.spawn(function() pcall(doTPtoPet, pet) end)
        end
        tpBtn.MouseButton1Click:Connect(onTP)
        btn.MouseButton1Click:Connect(onTP)
    end
end

local isRefreshing = false
local function refreshList()
    if isRefreshing then return end
    isRefreshing = true
    refreshBtn.Text = "..."
    refreshBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
    countLabel.Text = "Scanning..."
    task.spawn(function()
        if not loadModules() then
            local _t0 = os.clock()
            while not loadModules() and os.clock() - _t0 < 5 do task.wait(0.3) end
        end
        local pets = {}
        local ok2, result = pcall(scanAllPets)
        if ok2 and result then pets = result end
        buildList(pets)
        refreshBtn.Text = "🔄"
        refreshBtn.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        isRefreshing = false
    end)
end

refreshBtn.MouseButton1Click:Connect(refreshList)

task.spawn(function()
    while sg and sg.Parent do
        local s = tostring(_G.TPStatus or "idle")
        if s == "idle" or s == "clone_ok" then
            statusBar.TextColor3 = Color3.fromRGB(200, 50, 50)
        elseif s:find("FAILED") or s:find("no_") then
            statusBar.TextColor3 = Color3.fromRGB(255, 80, 80)
        else
            statusBar.TextColor3 = Color3.fromRGB(255, 100, 0)
        end
        statusBar.Text = s
        task.wait(0.1)
    end
end)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.N then refreshList() end
end)

local autoTPEnabled = false
autoTPToggle.MouseButton1Click:Connect(function()
    autoTPEnabled = not autoTPEnabled
    if autoTPEnabled then
        autoTPToggle.Text = "Auto TP ON"
        autoTPToggle.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        task.spawn(function()
            local char = LP.Character or LP.CharacterAdded:Wait()
            char:WaitForChild("HumanoidRootPart", 10)
            if autoTPEnabled then task.spawn(doVelocityTP) end
        end)
    else
        autoTPToggle.Text = "Auto TP OFF"
        autoTPToggle.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
    end
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.AutoTPEnabled = autoTPEnabled
end)

local autoTPConnection = nil
local function enableAutoTP()
    if autoTPConnection then autoTPConnection:Disconnect() end
    autoTPConnection = LP.CharacterAdded:Connect(function()
        if autoTPEnabled then
            local delay = _G.JoinDelay
            if not delay then delay = 5000 end
            task.wait(delay / 1000)
            task.spawn(doVelocityTP)
        end
    end)
end
enableAutoTP()

task.spawn(function()
    if _G.SavedConfig and _G.SavedConfig.AutoTPEnabled then
        autoTPEnabled = true
        autoTPToggle.Text = "Auto TP ON"
        autoTPToggle.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    end
    if not autoTPEnabled then return end
    local char = LP.Character or LP.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart", 10)
    pcall(loadModules); pcall(loadNet)
    local delay = (_G.SavedConfig and tonumber(_G.SavedConfig.JoinDelay)) or _G.JoinDelay or 5000
    task.wait(delay / 1000)
    local _t0 = os.clock()
    repeat
        local ok, pets = pcall(scanAllPets)
        if ok and pets and #pets > 0 then break end
        task.wait(0.4)
    until os.clock() - _t0 > 15
    if autoTPEnabled then task.spawn(doVelocityTP) end
end)

local InternalStealCache = {}
local function buildStealCallbacks(prompt)
    S._promptPrune = (S._promptPrune or 0) + 1
    if S._promptPrune % 40 == 0 then
        for p in pairs(InternalStealCache) do
            if not p.Parent then InternalStealCache[p] = nil end
        end
    end
    if InternalStealCache[prompt] then return end
    local data = { holdCallbacks = {}, triggerCallbacks = {}, ready = true }
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1) == "table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function) == "function" then
                table.insert(data.holdCallbacks, conn.Function)
            end
        end
    end
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2) == "table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function) == "function" then
                table.insert(data.triggerCallbacks, conn.Function)
            end
        end
    end
    if #data.holdCallbacks > 0 or #data.triggerCallbacks > 0 then
        InternalStealCache[prompt] = data
    end
end

local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if podium then
        local base = podium:FindFirstChild("Base")
        local spawn = base and base:FindFirstChild("Spawn")
        if spawn then
            local attach = spawn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") and p.Enabled then return p end
                end
            end
        end
    end
    return nil
end

local GRAB_CONFIG = { HOLD_MIN = 1.3, HOLD_MAX = 2.6, ENTRY_DELAY = 0.3, COOLDOWN = 0.05, PRIME_RANGE = 62 }
local PromptMemoryCache = {}
local grabState = { active = false, startTime = 0, phase = "idle", label = "", lastResult = "", lastResultTime = 0, totalSteals = 0, failedSteals = 0 }
local function petGrabDist(targetPet)
    local char = LP.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
    if not hrp or not targetPet or not targetPet.position then return math.huge end
    return (hrp.Position - targetPet.position).Magnitude
end
local function executeGrabAsync(prompt, targetPet)
    if not prompt or not prompt.Parent then return false end
    buildStealCallbacks(prompt)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then
        if data then return false end
        -- getconnections is missing or returned nothing on this executor. Drive
        -- the prompt through the engine path instead; the server still validates
        -- the distance, so this only fires when the client is actually in range.
        if grabState.active then return false end
        grabState.active = true
        grabState.startTime = tick()
        grabState.phase = "waitingRange"
        grabState.label = targetPet.name or "Animal"
        task.spawn(function()
            local fired = false
            while tick() - grabState.startTime <= GRAB_CONFIG.HOLD_MAX do
                if not prompt.Parent then break end
                if petGrabDist(targetPet) <= radiusSlider.value then
                    fired = S.firePrompt(prompt)
                    if fired then break end
                end
                task.wait(0.05)
            end
            if fired then
                grabState.totalSteals = grabState.totalSteals + 1
                grabState.lastResult = "Stole " .. grabState.label
            else
                grabState.failedSteals = grabState.failedSteals + 1
                grabState.lastResult = "Missed " .. grabState.label
            end
            grabState.active = false
            grabState.phase = "idle"
            grabState.lastResultTime = tick()
            task.wait(GRAB_CONFIG.COOLDOWN)
        end)
        return true
    end
    data.ready = false
    grabState.active = true
    grabState.startTime = tick()
    grabState.phase = "holding"
    grabState.label = targetPet.name or "Animal"
    task.spawn(function()
        for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
        task.wait(GRAB_CONFIG.HOLD_MIN)
        grabState.phase = "waitingRange"
        local alreadyInRange = petGrabDist(targetPet) <= radiusSlider.value
        local fired = false
        while true do
            local elapsed = tick() - grabState.startTime
            if elapsed > GRAB_CONFIG.HOLD_MAX then break end
            if not prompt.Parent then break end
            if petGrabDist(targetPet) <= radiusSlider.value then
                if not alreadyInRange then task.wait(GRAB_CONFIG.ENTRY_DELAY) end
                for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
                fired = true
                break
            end
            task.wait()
        end
        if fired then
            grabState.totalSteals = grabState.totalSteals + 1
            grabState.lastResult = "Stole " .. grabState.label
        else
            grabState.failedSteals = grabState.failedSteals + 1
            grabState.lastResult = "Missed " .. grabState.label
        end
        grabState.active = false
        grabState.phase = "idle"
        grabState.lastResultTime = tick()
        task.wait(GRAB_CONFIG.COOLDOWN)
        data.ready = true
    end)
    return true
end

local stealEnabled = true
local stealMode = "Nearest"
stealToggle.MouseButton1Click:Connect(function()
    stealEnabled = not stealEnabled
    if stealEnabled then
        stealToggle.Text = "ON"
        stealToggle.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    else
        stealToggle.Text = "OFF"
        stealToggle.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
    end
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.StealEnabled = stealEnabled
end)
stealModeToggle.MouseButton1Click:Connect(function()
    if stealMode == "Nearest" then
        stealMode = "Highest"
        stealModeToggle.Text = "Mode: Highest"
        stealModeLbl.Text = "Steal: Highest"
    elseif stealMode == "Highest" then
        stealMode = "Selected"
        stealModeToggle.Text = "Mode: Selected"
        stealModeLbl.Text = "Steal: Selected"
    else
        stealMode = "Nearest"
        stealModeToggle.Text = "Mode: Nearest"
        stealModeLbl.Text = "Steal: Nearest"
    end
    _G.StealMode = stealMode
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.StealMode = stealMode
end)

local function pickGrabTarget(pets)
    local char = LP.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
    if not hrp then return nil end
    if stealMode == "Selected" and _G.selectedStealPet then
        for _, p in ipairs(pets) do
            if p.uid == _G.selectedStealPet.uid then return p end
        end
        _G.selectedStealPet = nil
        return nil
    elseif stealMode == "Highest" then
        for _, p in ipairs(pets) do
            if p.position and (hrp.Position - p.position).Magnitude <= GRAB_CONFIG.PRIME_RANGE then
                return p
            end
        end
        return nil
    else
        local best, bestDist = nil, math.huge
        for _, p in ipairs(pets) do
            if p.position then
                local d = (hrp.Position - p.position).Magnitude
                if d <= GRAB_CONFIG.PRIME_RANGE and d < bestDist then
                    bestDist = d
                    best = p
                end
            end
        end
        return best
    end
end
task.spawn(function()
    while true do
        task.wait(0.15)
        if not stealEnabled then continue end
        if grabState.active then continue end
        if LP:GetAttribute("Stealing") then continue end
        local pets = scanAllPets()
        if #pets == 0 then continue end
        local targetPet = pickGrabTarget(pets)
        if not targetPet then continue end
        local prompt = PromptMemoryCache[targetPet.uid]
        if not prompt or not prompt.Parent then
            prompt = findProximityPromptForAnimal(targetPet)
            if prompt then PromptMemoryCache[targetPet.uid] = prompt end
        end
        if prompt then executeGrabAsync(prompt, targetPet) end
    end
end)

do
    local lastFillPct = 0
    local HOLD_COLOR = U.ACC
    local RANGE_COLOR = Color3.fromRGB(255, 170, 60)
    local OK_COLOR = Color3.fromRGB(90, 220, 130)
    local BAD_COLOR = Color3.fromRGB(235, 70, 90)
    RunService.RenderStepped:Connect(function(dt)
        local active = grabState.active
        local justFinished = grabState.lastResultTime > 0 and (tick() - grabState.lastResultTime) < 1.2
        local success = justFinished and string.find(grabState.lastResult, "Stole") ~= nil
        local dotTarget
        if active then
            dotTarget = grabState.phase == "waitingRange" and RANGE_COLOR or HOLD_COLOR
        elseif justFinished then
            dotTarget = success and OK_COLOR or BAD_COLOR
        else
            dotTarget = Color3.fromRGB(90, 110, 90)
        end
        progressDot.BackgroundColor3 = progressDot.BackgroundColor3:Lerp(dotTarget, math.min(dt * 8, 1))
        local targetPct, targetColor
        if active then
            targetPct = math.clamp((tick() - grabState.startTime) / GRAB_CONFIG.HOLD_MAX, 0, 1)
            targetColor = grabState.phase == "waitingRange" and RANGE_COLOR or HOLD_COLOR
        elseif justFinished then
            targetPct = 1
            targetColor = success and OK_COLOR or BAD_COLOR
        else
            targetPct = 0
            targetColor = HOLD_COLOR
        end
        lastFillPct = lastFillPct + (targetPct - lastFillPct) * math.min(dt * 14, 1)
        progressBarFill.Size = UDim2.new(lastFillPct, -22 * lastFillPct, 0, 7)
        progressBarFill.BackgroundColor3 = progressBarFill.BackgroundColor3:Lerp(targetColor, math.min(dt * 8, 1))
        if active then
            local elapsed = tick() - grabState.startTime
            progressText.Text = string.upper(grabState.label) .. "  ·  " .. string.format("%.2fs", elapsed)
            progressText.TextColor3 = Color3.fromRGB(245, 245, 255)
        elseif justFinished then
            progressText.Text = string.upper(grabState.lastResult)
            progressText.TextColor3 = success and Color3.fromRGB(210, 255, 225) or Color3.fromRGB(255, 215, 215)
        else
            progressText.Text = "discord.gg/Z7vPrxecnJ"
            progressText.TextColor3 = U.MUT
        end
    end)
end

local antiRagdollEnabled = false
local function enableAntiRagdoll() antiRagdollEnabled = true end
local function disableAntiRagdoll() antiRagdollEnabled = false end
do
    local antiRagdollConnections = {}
    local antiRagdollCharacter, antiRagdollHumanoid, antiRagdollRootPart, antiRagdollAnimator
    local lastVelocity = Vector3.new(0, 0, 0)
    local velocityChangeThreshold = 40
    local velocityMagnitudeThreshold = 25
    local maxVelocity = 15
    local function isRagdolledLocal()
        if not antiRagdollEnabled then return false end
        if not antiRagdollHumanoid then return false end
        local state = antiRagdollHumanoid:GetState()
        if state ~= Enum.HumanoidStateType.Physics
           and state ~= Enum.HumanoidStateType.Ragdoll
           and state ~= Enum.HumanoidStateType.FallingDown
           and state ~= Enum.HumanoidStateType.GettingUp then
            return false
        end
        return true
    end
    local function enableAntiRagdollControls()
        pcall(function()
            local PlayerModule = LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
            require(PlayerModule):GetControls():Enable()
        end)
    end
    local cleanupRagdoll = function()
        if not antiRagdollCharacter then return end
        local function processChildren(parent)
            for _, obj in ipairs(parent:GetChildren()) do
                if obj:IsA("BallSocketConstraint")
                   or obj:IsA("NoCollisionConstraint")
                   or obj:IsA("HingeConstraint")
                   or (obj:IsA("Attachment") and (obj.Name == "A" or obj.Name == "B")) then
                    obj:Destroy()
                elseif obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                    obj:Destroy()
                elseif obj:IsA("Motor6D") then
                    obj.Enabled = true
                elseif obj:IsA("BasePart") then
                    for _, child in ipairs(obj:GetChildren()) do
                        if child:IsA("BallSocketConstraint") or child:IsA("NoCollisionConstraint")
                           or child:IsA("HingeConstraint") or child:IsA("Motor6D") then
                            if child:IsA("Motor6D") then
                                child.Enabled = true
                            else
                                child:Destroy()
                            end
                        elseif child:IsA("Attachment") and (child.Name == "A" or child.Name == "B") then
                            child:Destroy()
                        end
                    end
                end
            end
        end
        pcall(function() processChildren(antiRagdollCharacter) end)
        if antiRagdollAnimator then
            for _, track in pairs(antiRagdollAnimator:GetPlayingAnimationTracks()) do
                local animName = track.Animation and track.Animation.Name:lower() or ""
                if animName:find("rag") or animName:find("fall") or animName:find("hurt") or animName:find("down") then
                    track:Stop(0)
                end
            end
        end
    end
    local function setupAntiRagdollCharacter(char)
        antiRagdollCharacter = char
        antiRagdollHumanoid = char:WaitForChild("Humanoid", 10)
        antiRagdollRootPart = char:WaitForChild("HumanoidRootPart", 10)
        antiRagdollAnimator = antiRagdollHumanoid:WaitForChild("Animator", 10)
        lastVelocity = Vector3.new(0, 0, 0)
    end
    local function clearAntiRagdollConnections()
        for _, connection in pairs(antiRagdollConnections) do
            pcall(function() connection:Disconnect() end)
        end
        antiRagdollConnections = {}
    end
    local function setupAntiRagdollConnections()
        clearAntiRagdollConnections()
        table.insert(antiRagdollConnections, antiRagdollHumanoid.StateChanged:Connect(function()
            if isRagdolledLocal() then
                antiRagdollHumanoid:ChangeState(Enum.HumanoidStateType.Running)
                cleanupRagdoll()
                workspace.CurrentCamera.CameraSubject = antiRagdollHumanoid
                enableAntiRagdollControls()
            end
        end))
        table.insert(antiRagdollConnections, antiRagdollCharacter.DescendantAdded:Connect(function()
            if isRagdolledLocal() then cleanupRagdoll() end
        end))
        table.insert(antiRagdollConnections, RunService.Heartbeat:Connect(function()
            if isRagdolledLocal() then
                cleanupRagdoll()
                local v = antiRagdollRootPart.AssemblyLinearVelocity
                if (v - lastVelocity).Magnitude > velocityChangeThreshold
                   and v.Magnitude > velocityMagnitudeThreshold then
                    antiRagdollRootPart.AssemblyLinearVelocity = v.Unit * math.min(v.Magnitude, maxVelocity)
                end
                lastVelocity = v
            end
        end))
        enableAntiRagdollControls()
        cleanupRagdoll()
    end
    local function activateForCharacter(char)
        setupAntiRagdollCharacter(char)
        setupAntiRagdollConnections()
    end
    if LP.Character then
        task.spawn(activateForCharacter, LP.Character)
    end
    LP.CharacterAdded:Connect(function(char)
        activateForCharacter(char)
    end)
end

local antiBeeEnabled = false
local antiBeeConnections = {}
local originalMoveFunction = nil
local controlsProtected = false
local badLightingNames = { Blue = true, DiscoEffect = true, BeeBlur = true, ColorCorrection = true }

local function nukeLighting(obj)
    if not obj or not obj.Parent then return end
    if badLightingNames[obj.Name] then
        pcall(function() obj:Destroy() end)
    end
end

local function protectControls()
    if controlsProtected then return end
    local playerScripts = LP:FindFirstChild("PlayerScripts")
    local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
    if not playerModule then return end
    local Controls = require(playerModule):GetControls()
    if not Controls then return end
    if not originalMoveFunction then
        originalMoveFunction = Controls.moveFunction
    end
    local function protectedMoveFunction(self, moveVector, relativeToCamera)
        if originalMoveFunction then
            originalMoveFunction(self, moveVector, relativeToCamera)
        end
    end
    table.insert(antiBeeConnections, RunService.Heartbeat:Connect(function()
        if not antiBeeEnabled then return end
        if Controls.moveFunction ~= protectedMoveFunction then
            Controls.moveFunction = protectedMoveFunction
        end
    end))
    Controls.moveFunction = protectedMoveFunction
    controlsProtected = true
end

local function restoreControls()
    if not controlsProtected then return end
    local playerScripts = LP:FindFirstChild("PlayerScripts")
    local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
    if playerModule then
        local Controls = require(playerModule):GetControls()
        if Controls and originalMoveFunction then
            Controls.moveFunction = originalMoveFunction
        end
    end
    controlsProtected = false
end

local function blockBuzzingSound()
    local beeScript = LP.PlayerScripts:FindFirstChild("Bee", true)
    if beeScript then
        local buzzing = beeScript:FindFirstChild("Buzzing")
        if buzzing and buzzing:IsA("Sound") then
            buzzing:Stop()
            buzzing.Volume = 0
        end
    end
end

local function enableAntiBee()
    antiBeeEnabled = true
    for _, inst in ipairs(Lighting:GetDescendants()) do
        nukeLighting(inst)
    end
    table.insert(antiBeeConnections, Lighting.DescendantAdded:Connect(function(obj)
        if not antiBeeEnabled then return end
        nukeLighting(obj)
    end))
    protectControls()
    table.insert(antiBeeConnections, RunService.Heartbeat:Connect(function()
        if not antiBeeEnabled then return end
        blockBuzzingSound()
    end))
end

local function disableAntiBee()
    antiBeeEnabled = false
    restoreControls()
    for _, conn in ipairs(antiBeeConnections) do
        if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    antiBeeConnections = {}
end

local espEnabled = false
local brainrotESPFolder = nil
local brainrotBillboards = {}

local function getMutationColorESP(mut)
    local colors = {
        Cursed = Color3.fromRGB(255,50,50),
        Gold = Color3.fromRGB(255,215,0),
        Diamond = Color3.fromRGB(0,255,255),
        YinYang = Color3.fromRGB(220,220,220),
        Rainbow = Color3.fromRGB(255,100,200),
        Lava = Color3.fromRGB(255,100,20),
        Candy = Color3.fromRGB(255,105,180),
        Radioactive = Color3.fromRGB(0,255,0),
        Divine = Color3.fromRGB(255,255,255)
    }
    return colors[mut] or Color3.fromRGB(0, 220, 120)
end

local function createBrainrotBillboard(data)
    local bb = Instance.new("BillboardGui")
    bb.Name = "Tag_" .. tostring(data.uid)
    bb.Size = UDim2.new(0, 210, 0, 46)
    bb.StudsOffset = Vector3.new(0, 7, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 2500
    bb.ResetOnSpawn = false
    local card = Instance.new("Frame", bb)
    card.Size = UDim2.new(1, 0, 1, 0)
    card.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
    card.BackgroundTransparency = 0.25
    card.BorderSizePixel = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", card)
    stroke.Name = "CardStroke"
    stroke.Color = Color3.fromRGB(0, 220, 120)
    stroke.Thickness = 2.0
    stroke.Transparency = 0.2
    local nameLabel = Instance.new("TextLabel", card)
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(0.55, -14, 0, 17)
    nameLabel.Position = UDim2.new(0, 14, 0, 5)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 12
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    local genLabel = Instance.new("TextLabel", card)
    genLabel.Name = "Gen"
    genLabel.Size = UDim2.new(0.58, -14, 0, 15)
    genLabel.Position = UDim2.new(0, 14, 0, 24)
    genLabel.BackgroundTransparency = 1
    genLabel.TextColor3 = Color3.fromRGB(80, 220, 130)
    genLabel.Font = Enum.Font.GothamBold
    genLabel.TextSize = 11
    genLabel.TextXAlignment = Enum.TextXAlignment.Left
    local mutLabel = Instance.new("TextLabel", card)
    mutLabel.Name = "Mutation"
    mutLabel.Size = UDim2.new(1, -18, 0, 12)
    mutLabel.Position = UDim2.new(0, 14, 0, 42)
    mutLabel.BackgroundTransparency = 1
    mutLabel.Font = Enum.Font.GothamBold
    mutLabel.TextSize = 10
    mutLabel.TextXAlignment = Enum.TextXAlignment.Left
    mutLabel.Visible = false
    local distLabel = Instance.new("TextLabel", card)
    distLabel.Name = "Dist"
    distLabel.Size = UDim2.new(0.4, -8, 0, 15)
    distLabel.Position = UDim2.new(0.6, 0, 0, 24)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(155,155,180)
    distLabel.Font = Enum.Font.GothamMedium
    distLabel.TextSize = 10
    distLabel.TextXAlignment = Enum.TextXAlignment.Right
    return bb
end

local function updateBrainrotBillboard(bb, data, hrp)
    local nameLabel = bb:FindFirstChild("Name", true)
    local genLabel = bb:FindFirstChild("Gen", true)
    if nameLabel then nameLabel.Text = data.name or "Unknown" end
    if genLabel then
        genLabel.Text = (data.genValue and string.format("$%.1fM/s", data.genValue/1e6)) or ""
    end
    local mutLabel = bb:FindFirstChild("Mutation", true)
    if mutLabel then
        local hasMut = data.mutation and data.mutation ~= "None"
        mutLabel.Text = hasMut and data.mutation or ""
        mutLabel.Visible = hasMut
    end
    local distLabel = bb:FindFirstChild("Dist", true)
    if distLabel and hrp and data.adornee then
        local dist = (hrp.Position - data.adornee.Position).Magnitude
        distLabel.Text = math.floor(dist) .. " studs"
    end
    local stroke = bb:FindFirstChild("CardStroke", true)
    if stroke then stroke.Color = getMutationColorESP(data.mutation) end
end

local function refreshBrainrotESP()
    if not espEnabled then return end
    local cache = scanAllPets()
    if not cache or #cache == 0 then return end
    if not brainrotESPFolder or not brainrotESPFolder.Parent then
        -- Client-only container: billboards/highlights with Adornee render fine
        -- from the hidden UI root and are invisible to workspace scans.
        brainrotESPFolder = Instance.new("Folder")
        brainrotESPFolder.Name = "Fx"
        local root = S.visualRoot()
        pcall(function() brainrotESPFolder.Parent = root end)
    end
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local entries = {}
    for _, pet in ipairs(cache) do
        local adornee = findAdorneeGlobal(pet)
        if adornee then
            table.insert(entries, {
                uid = pet.uid,
                name = pet.name,
                genValue = pet.mps,
                mutation = pet.mutation,
                adornee = adornee,
            })
        end
    end
    local seen = {}
    for _, data in ipairs(entries) do
        if data and data.uid and data.adornee and data.adornee.Parent then
            seen[data.uid] = true
            local entry = brainrotBillboards[data.uid]
            if not entry or not entry.bb or not entry.bb.Parent then
                if entry and entry.bb then entry.bb:Destroy() end
                local bb = createBrainrotBillboard(data)
                bb.Adornee = data.adornee
                bb.Parent = brainrotESPFolder
                local hl = Instance.new("Highlight")
                hl.Name = "H_" .. data.uid
                hl.Adornee = data.adornee
                hl.FillColor = Color3.fromRGB(255,200,0)
                hl.FillTransparency = 0.5
                hl.OutlineTransparency = 0
                hl.Parent = brainrotESPFolder
                brainrotBillboards[data.uid] = { bb = bb, highlight = hl, adornee = data.adornee }
                entry = brainrotBillboards[data.uid]
            end
            updateBrainrotBillboard(entry.bb, data, hrp)
        end
    end
    for uid, entry in pairs(brainrotBillboards) do
        if not seen[uid] then
            if entry.bb then entry.bb:Destroy() end
            if entry.highlight then entry.highlight:Destroy() end
            brainrotBillboards[uid] = nil
        end
    end
end

local function enableESP()
    espEnabled = true
    task.spawn(function()
        while espEnabled do
            refreshBrainrotESP()
            task.wait(0.35)
        end
    end)
end

local function disableESP()
    espEnabled = false
    if brainrotESPFolder then brainrotESPFolder:Destroy() end
    brainrotBillboards = {}
end

antiRagdollToggle.MouseButton1Click:Connect(function()
    if antiRagdollEnabled then
        antiRagdollEnabled = false
        disableAntiRagdoll()
        antiRagdollToggle.Text = "Anti-Ragdoll OFF"
        antiRagdollToggle.BackgroundColor3 = Color3.fromRGB(170,0,0)
    else
        antiRagdollEnabled = true
        enableAntiRagdoll()
        antiRagdollToggle.Text = "Anti-Ragdoll ON"
        antiRagdollToggle.BackgroundColor3 = Color3.fromRGB(200,50,50)
    end
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.AntiRagdoll = antiRagdollEnabled
end)

antiBeeToggle.MouseButton1Click:Connect(function()
    if antiBeeEnabled then
        antiBeeEnabled = false
        disableAntiBee()
        antiBeeToggle.Text = "Anti-Bee OFF"
        antiBeeToggle.BackgroundColor3 = Color3.fromRGB(170,0,0)
    else
        antiBeeEnabled = true
        enableAntiBee()
        antiBeeToggle.Text = "Anti-Bee ON"
        antiBeeToggle.BackgroundColor3 = Color3.fromRGB(200,50,50)
    end
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.AntiBee = antiBeeEnabled
end)

espToggle.MouseButton1Click:Connect(function()
    if espEnabled then
        espEnabled = false
        disableESP()
        espToggle.Text = "ESP OFF"
        espToggle.BackgroundColor3 = Color3.fromRGB(170,0,0)
    else
        espEnabled = true
        enableESP()
        espToggle.Text = "ESP ON"
        espToggle.BackgroundColor3 = Color3.fromRGB(200,50,50)
    end
    _G.SavedConfig = _G.SavedConfig or {}
    _G.SavedConfig.ESP = espEnabled
end)

local function setupAntiDie()
    if _G.AntiDieConnection then pcall(function() _G.AntiDieConnection:Disconnect() end) _G.AntiDieConnection = nil end
    if _G.AntiDieDiedConnection then pcall(function() _G.AntiDieDiedConnection:Disconnect() end) _G.AntiDieDiedConnection = nil end
    if _G.AntiDieHeartbeatConnection then pcall(function() _G.AntiDieHeartbeatConnection:Disconnect() end) _G.AntiDieHeartbeatConnection = nil end
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    pcall(function()
        hum.BreakJointsOnDeath = false
        hum.RequiresNeck = false
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
    end)
    _G.AntiDieConnection = hum:GetPropertyChangedSignal("Health"):Connect(function()
        if _G.AntiDieDisabled then return end
        if hum.Health <= 0 then
            hum.Health = hum.MaxHealth
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        end
    end)
    _G.AntiDieDiedConnection = hum.Died:Connect(function()
        if _G.AntiDieDisabled then return end
        pcall(function() hum.Health = hum.MaxHealth end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end)
    _G.AntiDieHeartbeatConnection = RunService.Heartbeat:Connect(function()
        if _G.AntiDieDisabled then return end
        if hum and hum.Parent then
            if hum.Health <= 0 then
                hum.Health = hum.MaxHealth
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            end
            local state = hum:GetState()
            if state == Enum.HumanoidStateType.Dead or
               state == Enum.HumanoidStateType.Ragdoll or
               state == Enum.HumanoidStateType.FallingDown then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            end
        end
    end)
    return {_G.AntiDieConnection, _G.AntiDieDiedConnection, _G.AntiDieHeartbeatConnection}
end
_G.setupAntiDie = setupAntiDie

task.spawn(function()
    setupAntiDie()
    LP.CharacterAdded:Connect(function()
        task.wait(0.2)
        setupAntiDie()
    end)
end)

-- INSTANT RESPAWN (without balloon remote, uses forced death + LoadCharacter)
local function resetMoveAllToolsToBackpack(character)
    if not character then return end
    for _, ch in ipairs(character:GetChildren()) do
        if ch:IsA("Tool") then
            pcall(function() ch.Parent = LocalPlayer.Backpack end)
        end
    end
end

-- Call this function to respawn instantly
function InstantRespawn()
    -- Disable anti-die temporarily
    _G.AntiDieDisabled = true
    if _G.AntiDieConnection then
        pcall(function() _G.AntiDieConnection:Disconnect() end)
        _G.AntiDieConnection = nil
    end
    if _G.AntiDieHeartbeatConnection then
        pcall(function() _G.AntiDieHeartbeatConnection:Disconnect() end)
        _G.AntiDieHeartbeatConnection = nil
    end

    local function restoreAntiDie()
        _G.AntiDieDisabled = false
        if _G.setupAntiDie then
            pcall(_G.setupAntiDie)
        end
    end

    local function armAntiDieRestoreAfterNextSpawn()
        local conn
        conn = LocalPlayer.CharacterAdded:Connect(function(newChar)
            if conn then
                conn:Disconnect()
                conn = nil
            end
            task.defer(function()
                pcall(function() newChar:WaitForChild("Humanoid", 12) end)
                RunService.Heartbeat:Wait()
                restoreAntiDie()
            end)
        end)
    end

    local character = LocalPlayer.Character
    if not character then
        armAntiDieRestoreAfterNextSpawn()
        pcall(function() LocalPlayer:LoadCharacter() end)
        return
    end

    pcall(function()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not (rootPart and humanoid) then return end

        -- Optional: move all tools to backpack
        resetMoveAllToolsToBackpack(character)

        -- Force death by moving high up and killing
        rootPart.CFrame = CFrame.new(0, 15000, 0)
        RunService.Heartbeat:Wait()

        humanoid = character:FindFirstChildOfClass("Humanoid")
        rootPart = character:FindFirstChild("HumanoidRootPart")
        if not (humanoid and rootPart) then return end

        pcall(function() humanoid.Health = 0 end)
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Dead) end)

        if humanoid.Health > 0 then
            pcall(function() humanoid:TakeDamage(humanoid.MaxHealth * 99) end)
        end

        if humanoid.Health > 0 then
            pcall(function() character:BreakJoints() end)
        end

        humanoid = character:FindFirstChildOfClass("Humanoid")
        rootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoid and rootPart and humanoid.Health > 0 then
            pcall(function()
                rootPart.Velocity = Vector3.new()
                rootPart.CFrame = CFrame.new(
                    rootPart.Position.X,
                    workspace.FallenPartsDestroyHeight - 500,
                    rootPart.Position.Z
                )
            end)
        end
    end)

    armAntiDieRestoreAfterNextSpawn()

    task.defer(function()
        pcall(function() LocalPlayer:LoadCharacter() end)
    end)
end

respawnBtn.MouseButton1Click:Connect(function()
    task.spawn(InstantRespawn)
end)

task.spawn(function()
    if _G.SavedConfig then
        if _G.SavedConfig.CarpetSpeed then speedSlider.setRaw(_G.SavedConfig.CarpetSpeed) end
        if _G.SavedConfig.JoinDelay then joinSlider.setRaw(_G.SavedConfig.JoinDelay) end
        if _G.SavedConfig.LandingDelay then landingSlider.setRaw(_G.SavedConfig.LandingDelay) end
        if _G.SavedConfig.CloneMethod then cloneMethod = _G.SavedConfig.CloneMethod; if cloneMethod == "Remote" then cloneToggle.Text = "Method: Remote"; cloneLbl.Text = "Clone: Remote" else cloneToggle.Text = "Method: FireSignal"; cloneLbl.Text = "Clone: FireSignal" end end
        if _G.SavedConfig.StealEnabled then stealEnabled = _G.SavedConfig.StealEnabled; stealToggle.Text = stealEnabled and "ON" or "OFF"; stealToggle.BackgroundColor3 = stealEnabled and Color3.fromRGB(200,50,50) or Color3.fromRGB(170,0,0) end
        if _G.SavedConfig.StealMode then stealMode = _G.SavedConfig.StealMode; if stealMode == "Nearest" then stealModeToggle.Text = "Mode: Nearest"; stealModeLbl.Text = "Steal: Nearest" elseif stealMode == "Highest" then stealModeToggle.Text = "Mode: Highest"; stealModeLbl.Text = "Steal: Highest" else stealModeToggle.Text = "Mode: Selected"; stealModeLbl.Text = "Steal: Selected" end end
        if _G.SavedConfig.StealRadius then radiusSlider.setRaw(_G.SavedConfig.StealRadius) end
        if _G.SavedConfig.AutoTPEnabled then autoTPEnabled = _G.SavedConfig.AutoTPEnabled; autoTPToggle.Text = autoTPEnabled and "Auto TP ON" or "Auto TP OFF"; autoTPToggle.BackgroundColor3 = autoTPEnabled and Color3.fromRGB(200,50,50) or Color3.fromRGB(170,0,0) end
        if _G.SavedConfig.AntiRagdoll then
            antiRagdollEnabled = _G.SavedConfig.AntiRagdoll
            if antiRagdollEnabled then enableAntiRagdoll() else disableAntiRagdoll() end
            antiRagdollToggle.Text = antiRagdollEnabled and "Anti-Ragdoll ON" or "Anti-Ragdoll OFF"
            antiRagdollToggle.BackgroundColor3 = antiRagdollEnabled and Color3.fromRGB(200,50,50) or Color3.fromRGB(170,0,0)
        end
        if _G.SavedConfig.AntiBee then
            antiBeeEnabled = _G.SavedConfig.AntiBee
            if antiBeeEnabled then enableAntiBee() else disableAntiBee() end
            antiBeeToggle.Text = antiBeeEnabled and "Anti-Bee ON" or "Anti-Bee OFF"
            antiBeeToggle.BackgroundColor3 = antiBeeEnabled and Color3.fromRGB(200,50,50) or Color3.fromRGB(170,0,0)
        end
        if _G.SavedConfig.ESP then
            espEnabled = _G.SavedConfig.ESP
            if espEnabled then enableESP() else disableESP() end
            espToggle.Text = espEnabled and "ESP ON" or "ESP OFF"
            espToggle.BackgroundColor3 = espEnabled and Color3.fromRGB(200,50,50) or Color3.fromRGB(170,0,0)
        end
    end
end)

task.spawn(function()
    local char = LP.Character or LP.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart", 10)
    pcall(loadModules); pcall(loadNet)
    local _t0 = os.clock()
    repeat
        local ok2, pets = pcall(scanAllPets)
        if ok2 and pets and #pets > 0 then buildList(pets); break end
        task.wait(0.4)
    until os.clock() - _t0 > 15
    if not currentPets or #currentPets == 0 then refreshList() end
end)

print("[+] menu loaded")
