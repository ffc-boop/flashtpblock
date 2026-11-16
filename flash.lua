LEAKED BY STELLAR HUB REPORT TO https://discord.gg/XskZHq3y3 IF LEAKED TO YOU WILL GET A REWARD
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "sem"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui
local Panel = Instance.new("Frame")
Panel.Name = "el"
Panel.Size = UDim2.new(0, 220, 0, 68)
Panel.Position = UDim2.new(0.5, -110, 0.05, 0)  -- centered top, elegant placement
Panel.BackgroundColor3 = Color3.fromRGB(28, 20, 48)  -- deep elegant purple-black
Panel.BackgroundTransparency = 0.38               -- soft glass
Panel.BorderSizePixel = 0
Panel.Active = true
Panel.Draggable = true
Panel.Parent = ScreenGui
local PanelCorner = Instance.new("UICorner")
PanelCorner.CornerRadius = UDim.new(0, 20)
PanelCorner.Parent = Panel
local Shadow = Instance.new("ImageLabel")
Shadow.Size = UDim2.new(1, 20, 1, 20)
Shadow.Position = UDim2.new(0, -10, 0, -10)
Shadow.BackgroundTransparency = 1
Shadow.Image = "rbxassetid://6014261993" 
Shadow.ImageColor3 = Color3.fromRGB(0,0,0)
Shadow.ImageTransparency = 0.75
Shadow.ScaleType = Enum.ScaleType.Slice
Shadow.SliceCenter = Rect.new(49,49,450,450)
Shadow.ZIndex = -1
Shadow.Parent = Panel
local Gradient = Instance.new("UIGradient")
Gradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 50, 140)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 25, 70))
}
Gradient.Rotation = 90
Gradient.Transparency = NumberSequence.new{
    NumberSequenceKeypoint.new(0, 0.4),
    NumberSequenceKeypoint.new(1, 0.7)
}
Gradient.Parent = Panel
local BorderGlow = Instance.new("UIStroke")
BorderGlow.Color = Color3.fromRGB(190, 140, 240)
BorderGlow.Transparency = 0.55
BorderGlow.Thickness = 1.4
BorderGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
BorderGlow.Parent = Panel
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 22)
Title.BackgroundTransparency = 1
Title.Text = "Notion â€¢ Semi"
Title.TextColor3 = Color3.fromRGB(225, 200, 255)
Title.TextSize = 15
Title.Font = Enum.Font.GothamSemibold   -- refined & elegant
Title.TextXAlignment = Enum.TextXAlignment.Center
Title.TextTransparency = 0.15
Title.Parent = Panel
local Toggle = Instance.new("TextButton")
Toggle.Name = "Toggle"
Toggle.AnchorPoint = Vector2.new(0.5, 0.5)
Toggle.Size = UDim2.new(0.82, 0, 0.55, 0)
Toggle.Position = UDim2.new(0.5, 0, 0.62, 0)
Toggle.BackgroundColor3 = Color3.fromRGB(70, 45, 130)
Toggle.BackgroundTransparency = 0.45
Toggle.Text = "OFF"
Toggle.TextColor3 = Color3.fromRGB(240, 225, 255)
Toggle.TextSize = 14
Toggle.Font = Enum.Font.GothamMedium
Toggle.AutoButtonColor = false
Toggle.Parent = Panel
local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 12)
ToggleCorner.Parent = Toggle
local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(180, 130, 230)
ToggleStroke.Transparency = 0.6
ToggleStroke.Thickness = 1.2
ToggleStroke.Parent = Toggle
if UserInputService.TouchEnabled then
    Panel.Size = UDim2.new(0, 280, 0, 84)
    Title.TextSize = 17
    Toggle.TextSize = 16
    Toggle.Size = UDim2.new(0.84, 0, 0.56, 0)
end
local connections = { SemiInvisible = {} }
local isInvisible = false
local clone, oldRoot, hip, animTrack, stepConnection, charConnection
local DEPTH_OFFSET = 0.09
local mt, oldNamecall, oldNewindex
local function setupGodmode()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid", 8)
    if not hum then return false end
    mt = getrawmetatable(game)
    oldNamecall = mt.__namecall
    oldNewindex = mt.__newindex
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if self == hum then
            if m == "ChangeState" and select(1, ...) == Enum.HumanoidStateType.Dead then return end
            if m == "SetStateEnabled" and select(1, ...) == Enum.HumanoidStateType.Dead then return end
            if m == "Destroy" then return end
        end
        if self == char and m == "BreakJoints" then return end
        return oldNamecall(self, ...)
    end)
    mt.__newindex = newcclosure(function(self, k, v)
        if self == hum then
            if k == "Health" and type(v) == "number" and v <= 0 then return end
            if k == "MaxHealth" and type(v) == "number" and v < hum.MaxHealth then return end
            if k == "BreakJointsOnDeath" and v == true then return end
        end
        if self == char and k == "Parent" and v == nil then return end
        return oldNewindex(self, k, v)
    end)
    setreadonly(mt, true)
    return true
end
local function disableGodmode()
    if mt then
        setreadonly(mt, false)
        mt.__namecall = oldNamecall or mt.__namecall
        mt.__newindex = oldNewindex or mt.__newindex
        setreadonly(mt, true)
    end
end
local function removeFolders()
    local folder = workspace:FindFirstChild(LocalPlayer.Name)
    if not folder then return end
    pcall(function()
        if folder.DoubleRig then folder.DoubleRig:Destroy() end
        if folder.Constraints then folder.Constraints:Destroy() end
    end)
    local c = folder.ChildAdded:Connect(function(ch)
        if ch.Name == "DoubleRig" or ch.Name == "Constraints" then ch:Destroy() end
    end)
    table.insert(connections.SemiInvisible, c)
end
local function doClone()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    oldRoot = char:FindFirstChild("HumanoidRootPart")
    if not oldRoot then return false end
    hip = hum.HipHeight
    local temp = Instance.new("Model")
    temp.Parent = game
    char.Parent = temp
    clone = oldRoot:Clone()
    clone.Parent = char
    oldRoot.Parent = workspace.CurrentCamera
    clone.CFrame = oldRoot.CFrame
    char.PrimaryPart = clone
    char.Parent = workspace
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("Weld") or v:IsA("Motor6D") then
            if v.Part0 == oldRoot then v.Part0 = clone end
            if v.Part1 == oldRoot then v.Part1 = clone end
        end
    end
    temp:Destroy()
    return true
end
local function revertClone()
    if not oldRoot or not clone or not LocalPlayer.Character then return end
    local char = LocalPlayer.Character
    local temp = Instance.new("Model")
    temp.Parent = game
    char.Parent = temp
    oldRoot.Parent = char
    char.PrimaryPart = oldRoot
    char.Parent = workspace
    oldRoot.CanCollide = true
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("Weld") or v:IsA("Motor6D") then
            if v.Part0 == clone then v.Part0 = oldRoot end
            if v.Part1 == clone then v.Part1 = oldRoot end
        end
    end
    local pos = clone.CFrame
    clone:Destroy()
    clone = nil
    oldRoot.CFrame = pos
    oldRoot = nil
    local h = char:FindFirstChild("Humanoid")
    if h then h.HipHeight = hip end
    temp:Destroy()
end
local function animationTrickery()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://913402848"
    local animator = hum:FindFirstChild("Animator") or Instance.new("Animator", hum)
    animTrack = animator:LoadAnimation(anim)
    animTrack.Priority = Enum.AnimationPriority.Action4
    animTrack:Play(0, 1, 0)
    anim:Destroy()
    local stop = animTrack.Stopped:Connect(function()
        if isInvisible then animationTrickery() end
    end)
    table.insert(connections.SemiInvisible, stop)
    task.delay(0, function()
        if animTrack then animTrack.TimePosition = 0.7 end
        task.delay(1, function()
            if animTrack then animTrack:AdjustSpeed(math.huge) end
        end)
    end)
end
local function enableSemi()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    removeFolders()
    if not doClone() then return false end
    task.wait(0.1)
    animationTrickery()
    stepConnection = RunService.PreSimulation:Connect(function()
        if not isInvisible then return end
        local root = char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
        if not root or not oldRoot then return end
        local cf = root.CFrame - Vector3.new(0, char.Humanoid.HipHeight + (root.Size.Y / 2) - 1 + DEPTH_OFFSET, 0)
        oldRoot.CFrame = cf * CFrame.Angles(math.rad(180), 0, 0)
        oldRoot.Velocity = root.Velocity
        oldRoot.CanCollide = false
    end)
    table.insert(connections.SemiInvisible, stepConnection)
    charConnection = LocalPlayer.CharacterAdded:Connect(function()
        if isInvisible then
            isInvisible = false
            Toggle.Text = "OFF"
            disableSemi()
        end
    end)
    table.insert(connections.SemiInvisible, charConnection)
    return true
end
local function disableSemi()
    pcall(function()
        if animTrack then animTrack:Stop() animTrack:Destroy() animTrack = nil end
        if stepConnection then stepConnection:Disconnect() end
        if charConnection then charConnection:Disconnect() end
        revertClone()
        removeFolders()
    end)
end
local function toggle()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        Toggle.Text = "please wait..."
        task.delay(2, function() if not isInvisible then Toggle.Text = "OFF" end end)
        return
    end
    if not isInvisible then
        if setupGodmode() and enableSemi() then
            isInvisible = true
            Toggle.Text = "ENABLED"
            TweenService:Create(Toggle, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {
                BackgroundColor3 = Color3.fromRGB(110, 70, 180),
                BackgroundTransparency = 0.3,
                TextColor3 = Color3.fromRGB(255, 245, 255)
            }):Play()
            TweenService:Create(ToggleStroke, TweenInfo.new(0.35), {Transparency = 0.35}):Play()
            TweenService:Create(BorderGlow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.3}):Play()
        else
            disableGodmode()
            Toggle.Text = "error"
            task.delay(1.4, function() if not isInvisible then Toggle.Text = "OFF" end end)
        end
    else
        disableSemi()
        disableGodmode()
        isInvisible = false
        Toggle.Text = "OFF"
        TweenService:Create(Toggle, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {
            BackgroundColor3 = Color3.fromRGB(70, 45, 130),
            BackgroundTransparency = 0.45,
            TextColor3 = Color3.fromRGB(240, 225, 255)
        }):Play()
        TweenService:Create(ToggleStroke, TweenInfo.new(0.35), {Transparency = 0.6}):Play()
        TweenService:Create(BorderGlow, TweenInfo.new(0.4), {Transparency = 0.55}):Play()
        for _, c in ipairs(connections.SemiInvisible) do pcall(function() c:Disconnect() end) end
        connections.SemiInvisible = {}
    end
end
Toggle.MouseButton1Click:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F then
        toggle()
    end
end)
local hoverIn = TweenInfo.new(0.25, Enum.EasingStyle.Quint)
local hoverOut = TweenInfo.new(0.4, Enum.EasingStyle.Quint)
Toggle.MouseEnter:Connect(function()
    if not isInvisible then
        TweenService:Create(Toggle, hoverIn, {BackgroundTransparency = 0.35}):Play()
    end
end)
Toggle.MouseLeave:Connect(function()
    if not isInvisible then
        TweenService:Create(Toggle, hoverOut, {BackgroundTransparency = 0.45}):Play()
    end
end)
