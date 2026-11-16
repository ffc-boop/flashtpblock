Clone tp and block https://discord.gg/XdJWR5vZxk

local function solsras_main()
    local Players = game:GetService('Players')
    local VirtualInputManager = game:GetService('VirtualInputManager')
    local CoreGui = game:GetService('CoreGui')
    local StarterGui = game:GetService('StarterGui')
    local UserInputService = game:GetService('UserInputService')
    local MarketplaceService = game:GetService('MarketplaceService')
    local RunService = game:GetService('RunService')
    local TweenService = game:GetService('TweenService')
    local Workspace = game:GetService("Workspace")
    local localPlayer = Players.LocalPlayer
    
    repeat task.wait() until localPlayer
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid", 5)
    local backpack = localPlayer:WaitForChild("Backpack", 5)
    local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    
    local autoStealEnabled = false
    local adminPlayers = {}
    local guiVisible = true
    local isHovering = false
    local hoverConnection = nil
    local hoverY = nil
    local blockDelay = 0.7
    
    local STEAL_RADIUS = 7
    local TARGET_POSITION = Vector3.new(-332.5, 2.5, 30.6)
    
    local PURPLE_DEEP = Color3.fromRGB(45, 0, 75)
    local PURPLE_MEDIUM = Color3.fromRGB(85, 0, 130)
    local PURPLE_LIGHT = Color3.fromRGB(140, 60, 200)
    local PURPLE_GLOW = Color3.fromRGB(170, 100, 255)
    local PURPLE_OUTLINE = Color3.fromRGB(120, 40, 200)
    local PURPLE_DARK = Color3.fromRGB(25, 0, 45)
    local PURPLE_BUTTON = Color3.fromRGB(65, 20, 110)
    local PURPLE_BUTTON_HOVER = Color3.fromRGB(100, 40, 160)
    local TEXT_WHITE = Color3.fromRGB(230, 220, 255)
    
    local GamePassId = 1227013099
    
    local function checkAdminPass(player)
        local success, ownsPass = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GamePassId)
        end)
        return success and ownsPass
    end
    
    local function createAdminIndicator(character, player)
        if not character or not player then return end
        local head = character:WaitForChild("Head", 5)
        if not head then return end
        
        local highlight = Instance.new("Highlight")
        highlight.Name = "AdminHighlight"
        highlight.FillColor = PURPLE_LIGHT
        highlight.OutlineColor = PURPLE_GLOW
        highlight.FillTransparency = 0.7
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = character
        
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "AdminBillboard"
        billboard.Size = UDim2.new(0, 150, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        billboard.Parent = head
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "AdminLabel"
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 0.3
        textLabel.BackgroundColor3 = PURPLE_DEEP
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextSize = 18
        textLabel.Text = "ADMIN"
        textLabel.TextColor3 = PURPLE_GLOW
        textLabel.TextStrokeColor3 = PURPLE_MEDIUM
        textLabel.TextStrokeTransparency = 0.3
        textLabel.TextScaled = true
        textLabel.Parent = billboard
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = textLabel
    end
    
    local function setupAdminDetection(player)
        if player == localPlayer then return end
        local hasPass = checkAdminPass(player)
        if not hasPass then return end
        adminPlayers[player] = true
        if player.Character then
            createAdminIndicator(player.Character, player)
        end
        player.CharacterAdded:Connect(function(character)
            createAdminIndicator(character, player)
        end)
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(setupAdminDetection, player)
    end
    Players.PlayerAdded:Connect(setupAdminDetection)
    Players.PlayerRemoving:Connect(function(player)
        adminPlayers[player] = nil
    end)
    
    if CoreGui:FindFirstChild("clone tp and block") then
        CoreGui["clone tp and block"]:Destroy()
    end
    
    local screengui = Instance.new("ScreenGui")
    screengui.Name = "clone tp and block"
    screengui.Parent = CoreGui
    screengui.ResetOnSpawn = false
    screengui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screengui.DisplayOrder = 999
    screengui.Enabled = true
    screengui.IgnoreGuiInset = true
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 240, 0, 420)
    frame.Position = UDim2.new(0.5, -120, 0.5, -210)
    frame.BackgroundColor3 = PURPLE_DEEP
    frame.BackgroundTransparency = 0.1
    frame.Active = true
    frame.Draggable = true
    frame.Parent = screengui
    
    local outline = Instance.new("UIStroke")
    outline.Color = PURPLE_OUTLINE
    outline.Thickness = 2
    outline.Transparency = 0.2
    outline.Parent = frame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame
    
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PURPLE_DEEP),
        ColorSequenceKeypoint.new(0.5, PURPLE_MEDIUM),
        ColorSequenceKeypoint.new(1, PURPLE_DARK)
    })
    gradient.Rotation = 135
    gradient.Parent = frame
    
    local particles = {}
    for i = 1, 15 do
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 2, 0, 2)
        dot.Position = UDim2.new(math.random(), 0, math.random(), 0)
        dot.BackgroundColor3 = PURPLE_GLOW
        dot.BackgroundTransparency = 0.7
        dot.BorderSizePixel = 0
        dot.Parent = frame
        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot
        table.insert(particles, {
            frame = dot,
            speedX = (math.random() - 0.5) * 0.002,
            speedY = (math.random() - 0.5) * 0.002,
            baseX = dot.Position.X.Scale,
            baseY = dot.Position.Y.Scale
        })
    end
    
    RunService.Heartbeat:Connect(function()
        for _, p in ipairs(particles) do
            if p.frame and p.frame.Parent then
                local newX = p.baseX + math.sin(tick() * 0.5 + p.baseY) * 0.01 + p.speedX
                local newY = p.baseY + math.cos(tick() * 0.5 + p.baseX) * 0.01 + p.speedY
                p.frame.Position = UDim2.new(newX, 0, newY, 0)
            end
        end
    end)
    
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = PURPLE_DARK
    titleBar.BackgroundTransparency = 0.2
    titleBar.Parent = frame
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = titleBar
    
    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(1, 0, 0, 2)
    accentLine.Position = UDim2.new(0, 0, 1, -2)
    accentLine.BackgroundColor3 = PURPLE_GLOW
    accentLine.BorderSizePixel = 0
    accentLine.Parent = titleBar
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "SOLSRAS"
    title.TextColor3 = TEXT_WHITE
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.Position = UDim2.new(1, -32, 0.5, -12)
    closeBtn.BackgroundColor3 = PURPLE_MEDIUM
    closeBtn.Text = "X"
    closeBtn.TextColor3 = TEXT_WHITE
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = titleBar
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn
    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.2), {BackgroundColor3 = PURPLE_GLOW}):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.2), {BackgroundColor3 = PURPLE_MEDIUM}):Play()
    end)
    closeBtn.MouseButton1Click:Connect(function()
        screengui:Destroy()
    end)
    
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 24, 0, 24)
    minBtn.Position = UDim2.new(1, -60, 0.5, -12)
    minBtn.BackgroundColor3 = PURPLE_MEDIUM
    minBtn.Text = "−"
    minBtn.TextColor3 = TEXT_WHITE
    minBtn.TextSize = 18
    minBtn.Font = Enum.Font.GothamBold
    minBtn.Parent = titleBar
    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 6)
    minCorner.Parent = minBtn
    minBtn.MouseEnter:Connect(function()
        TweenService:Create(minBtn, TweenInfo.new(0.2), {BackgroundColor3 = PURPLE_GLOW}):Play()
    end)
    minBtn.MouseLeave:Connect(function()
        TweenService:Create(minBtn, TweenInfo.new(0.2), {BackgroundColor3 = PURPLE_MEDIUM}):Play()
    end)
    minBtn.MouseButton1Click:Connect(function()
        guiVisible = not guiVisible
        for _, v in ipairs(frame:GetChildren()) do
            if v ~= titleBar and v ~= gradient and v ~= outline then
                v.Visible = guiVisible
            end
        end
        minBtn.Text = guiVisible and "−" or "+"
    end)
    
    local function createButton(text, yPos)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.85, 0, 0, 38)
        btn.Position = UDim2.new(0.5, 0, yPos, 0)
        btn.AnchorPoint = Vector2.new(0.5, 0.5)
        btn.Text = text
        btn.BackgroundColor3 = PURPLE_BUTTON
        btn.TextColor3 = TEXT_WHITE
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 13
        btn.Parent = frame
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn
        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = PURPLE_OUTLINE
        btnStroke.Thickness = 1
        btnStroke.Transparency = 0.5
        btnStroke.Parent = btn
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {
                BackgroundColor3 = PURPLE_BUTTON_HOVER,
                Size = UDim2.new(0.87, 0, 0, 40)
            }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {
                BackgroundColor3 = PURPLE_BUTTON,
                Size = UDim2.new(0.85, 0, 0, 38)
            }):Play()
        end)
        return btn
    end
    
    local mainBtn = createButton("CARPET + TP + CLONE", 0.16)
    local stealBtn = createButton("AUTO-STEAL: OFF", 0.3)
    local hoverBtn = createButton("HOVER: OFF", 0.44)
    local blockBtn = createButton("BLOCK ALL", 0.58)
    
    local progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(0, 0, 0, 3)
    progressBar.Position = UDim2.new(0, 0, 1, -3)
    progressBar.BackgroundColor3 = PURPLE_GLOW
    progressBar.BorderSizePixel = 0
    progressBar.Parent = stealBtn
    progressBar.ZIndex = 10
    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, 2)
    progressCorner.Parent = progressBar
    
    local statusFrame = Instance.new("Frame")
    statusFrame.Size = UDim2.new(0.85, 0, 0, 45)
    statusFrame.Position = UDim2.new(0.5, 0, 0.76, 0)
    statusFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    statusFrame.BackgroundColor3 = PURPLE_DARK
    statusFrame.BackgroundTransparency = 0.2
    statusFrame.Parent = frame
    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 8)
    statusCorner.Parent = statusFrame
    local statusStroke = Instance.new("UIStroke")
    statusStroke.Color = PURPLE_OUTLINE
    statusStroke.Thickness = 1
    statusStroke.Transparency = 0.5
    statusStroke.Parent = statusFrame
    
    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -10, 0.5, 0)
    statusText.Position = UDim2.new(0, 5, 0, 2)
    statusText.BackgroundTransparency = 1
    statusText.Text = "READY"
    statusText.TextColor3 = PURPLE_GLOW
    statusText.Font = Enum.Font.Gotham
    statusText.TextSize = 11
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Parent = statusFrame
    
    local adminFrame = Instance.new("Frame")
    adminFrame.Size = UDim2.new(0.85, 0, 0, 20)
    adminFrame.Position = UDim2.new(0.5, 0, 0.86, 0)
    adminFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    adminFrame.BackgroundColor3 = PURPLE_DARK
    adminFrame.BackgroundTransparency = 0.3
    adminFrame.Parent = frame
    local adminCorner = Instance.new("UICorner")
    adminCorner.CornerRadius = UDim.new(0, 6)
    adminCorner.Parent = adminFrame
    
    local adminText = Instance.new("TextLabel")
    adminText.Size = UDim2.new(1, -10, 1, 0)
    adminText.Position = UDim2.new(0, 5, 0, 0)
    adminText.BackgroundTransparency = 1
    adminText.Text = "ADMINS: 0"
    adminText.TextColor3 = PURPLE_LIGHT
    adminText.Font = Enum.Font.Gotham
    adminText.TextSize = 10
    adminText.TextXAlignment = Enum.TextXAlignment.Left
    adminText.Parent = adminFrame
    
    local radiusText = Instance.new("TextLabel")
    radiusText.Size = UDim2.new(1, -10, 0, 15)
    radiusText.Position = UDim2.new(0, 5, 1, -15)
    radiusText.BackgroundTransparency = 1
    radiusText.Text = "STEAL RADIUS: 7"
    radiusText.TextColor3 = PURPLE_LIGHT
    radiusText.Font = Enum.Font.Gotham
    radiusText.TextSize = 8
    radiusText.TextXAlignment = Enum.TextXAlignment.Left
    radiusText.Parent = frame
    
    task.spawn(function()
        while screengui and screengui.Parent do
            local count = 0
            for _ in pairs(adminPlayers) do
                count = count + 1
            end
            adminText.Text = "ADMINS: " .. count
            task.wait(1)
        end
    end)
    
    local function startHovering()
        if isHovering then return end
        local character = localPlayer.Character
        if not character then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        hoverY = root.Position.Y
        isHovering = true
        if hoverConnection then
            hoverConnection:Disconnect()
            hoverConnection = nil
        end
        hoverConnection = RunService.Heartbeat:Connect(function()
            if not isHovering then return end
            local char = localPlayer.Character
            if not char then
                stopHovering()
                return
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")
            if hum and root then
                hum:ChangeState(Enum.HumanoidStateType.Freefall)
                local currentY = root.Position.Y
                local yDiff = hoverY - currentY
                local yVel = math.clamp(yDiff * 8, -12, 12)
                root.AssemblyLinearVelocity = Vector3.new(
                    root.AssemblyLinearVelocity.X,
                    yVel,
                    root.AssemblyLinearVelocity.Z
                )
            end
        end)
        statusText.Text = "HOVER ON"
        statusText.TextColor3 = PURPLE_GLOW
        hoverBtn.Text = "HOVER: ON"
        hoverBtn.BackgroundColor3 = PURPLE_BUTTON_HOVER
    end
    
    local function stopHovering()
        isHovering = false
        if hoverConnection then
            hoverConnection:Disconnect()
            hoverConnection = nil
        end
        local character = localPlayer.Character
        if character then
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
        statusText.Text = "HOVER OFF"
        statusText.TextColor3 = TEXT_WHITE
        hoverBtn.Text = "HOVER: OFF"
        hoverBtn.BackgroundColor3 = PURPLE_BUTTON
    end
    
    local function getHRP()
        local char = localPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end
    
    local function getPromptPosition(prompt)
        local parent = prompt.Parent
        if not parent then return nil end
        if parent:IsA("BasePart") then
            return parent.Position
        end
        if parent:IsA("Model") and parent.PrimaryPart then
            return parent.PrimaryPart.Position
        end
        if parent:IsA("Model") then
            local part = parent:FindFirstChildWhichIsA("BasePart")
            if part then
                return part.Position
            end
        end
        if parent:IsA("Attachment") then
            return parent.WorldPosition
        end
        local part = parent:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
        return nil
    end
    
    local function findNearestStealPrompt()
        local hrp = getHRP()
        if not hrp then return nil end
        local myPos = hrp.Position
        local nearest = nil
        local nearestDist = STEAL_RADIUS + 1
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                for _, obj in ipairs(plot:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local actionText = obj.ActionText or ""
                        if actionText == "Steal" then
                            local pos = getPromptPosition(obj)
                            if pos then
                                local dist = (myPos - pos).Magnitude
                                if dist <= STEAL_RADIUS and dist < nearestDist then
                                    nearest = obj
                                    nearestDist = dist
                                end
                            end
                        end
                    end
                end
            end
        end
        if not nearest then
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and obj.Enabled then
                    local actionText = obj.ActionText or ""
                    if actionText == "Steal" then
                        local pos = getPromptPosition(obj)
                        if pos then
                            local dist = (myPos - pos).Magnitude
                            if dist <= STEAL_RADIUS and dist < nearestDist then
                                nearest = obj
                                nearestDist = dist
                            end
                        end
                    end
                end
            end
        end
        return nearest
    end
    
    local function firePrompt(prompt)
        if not prompt then return end
        task.spawn(function()
            pcall(function()
                if fireproximityprompt then
                    fireproximityprompt(prompt, 1)
                end
            end)
            pcall(function()
                prompt:InputHoldBegin()
                task.wait(0.05)
                prompt:InputHoldEnd()
            end)
        end)
    end
    
    task.spawn(function()
        while true do
            if autoStealEnabled then
                local nearest = findNearestStealPrompt()
                if nearest then
                    statusText.Text = "STEALING..."
                    statusText.TextColor3 = PURPLE_GLOW
                    progressBar:TweenSize(
                        UDim2.new(1, 0, 1, 0),
                        Enum.EasingDirection.Out,
                        Enum.EasingStyle.Quad,
                        0.1,
                        true
                    )
                    firePrompt(nearest)
                    task.wait(0.1)
                    progressBar:TweenSize(
                        UDim2.new(0, 0, 1, 0),
                        Enum.EasingDirection.Out,
                        Enum.EasingStyle.Quad,
                        0.2,
                        true
                    )
                    statusText.Text = "READY"
                    statusText.TextColor3 = PURPLE_GLOW
                end
            end
            task.wait(0.1)
        end
    end)
    
    stealBtn.MouseButton1Click:Connect(function()
        autoStealEnabled = not autoStealEnabled
        if autoStealEnabled then
            stealBtn.Text = "AUTO-STEAL: ON"
            stealBtn.BackgroundColor3 = PURPLE_BUTTON_HOVER
            statusText.Text = "STEAL ON"
            radiusText.Text = "STEAL RADIUS: 7"
        else
            stealBtn.Text = "AUTO-STEAL: OFF"
            stealBtn.BackgroundColor3 = PURPLE_BUTTON
            statusText.Text = "STEAL OFF"
        end
    end)
    
    local function blockAllPlayers()
        statusText.Text = "BLOCKING..."
        statusText.TextColor3 = PURPLE_GLOW
        local blocked = 0
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.UserId > 0 then
                pcall(function()
                    StarterGui:SetCore("PromptBlockPlayer", player)
                end)
                blocked = blocked + 1
                statusText.Text = "BLOCKING: " .. player.Name
                task.wait(blockDelay)
            end
        end
        statusText.Text = "BLOCKED " .. blocked
        statusText.TextColor3 = PURPLE_GLOW
        task.wait(2)
        statusText.Text = "READY"
    end
    
    blockBtn.MouseButton1Click:Connect(blockAllPlayers)
    
    local function findCarpet()
        if localPlayer.Character then
            for _, child in ipairs(localPlayer.Character:GetChildren()) do
                if child:IsA("Tool") then
                    local name = child.Name:lower()
                    if name:find("carpet") or name:find("flying") then
                        return child
                    end
                end
            end
        end
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then
                    local name = child.Name:lower()
                    if name:find("carpet") or name:find("flying") then
                        return child
                    end
                end
            end
        end
        return nil
    end
    
    local function findCloner()
        if localPlayer.Character then
            for _, child in ipairs(localPlayer.Character:GetChildren()) do
                if child:IsA("Tool") then
                    local name = child.Name:lower()
                    if name:find("quantum") or name:find("cloner") then
                        return child, "character"
                    end
                end
            end
        end
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then
                    local name = child.Name:lower()
                    if name:find("quantum") or name:find("cloner") then
                        return child, "backpack"
                    end
                end
            end
        end
        return nil, nil
    end
    
    local function equipTool(tool, location)
        if not tool then return false end
        if location == "backpack" then
            if humanoid then
                pcall(function()
                    humanoid:EquipTool(tool)
                end)
                return true
            end
        elseif location == "character" then
            return true
        end
        return false
    end
    
    local function performMainAction()
        task.spawn(function()
            statusText.Text = "FINDING CARPET..."
            statusText.TextColor3 = PURPLE_GLOW
            
            -- Turn off hover before clone sequence
            if isHovering then
                statusText.Text = "TURNING OFF HOVER..."
                stopHovering()
                task.wait(0.3)
            end
            
            local carpet = findCarpet()
            if carpet then
                if carpet.Parent == backpack then
                    humanoid:EquipTool(carpet)
                end
                statusText.Text = "CARPET EQUIPPED"
                task.wait(0.2)
                
                statusText.Text = "TELEPORTING..."
                rootPart.CFrame = CFrame.new(TARGET_POSITION)
                task.wait(0.2)
                
                statusText.Text = "FINDING CLONER..."
                local cloner, clonerLoc = findCloner()
                
                if cloner then
                    statusText.Text = "CLONER FOUND"
                    task.wait(0.1)
                    
                    local equipped = equipTool(cloner, clonerLoc)
                    
                    if equipped then
                        task.wait(0.1)
                        
                        statusText.Text = "CLONING 6X..."
                        
                        local viewport = Workspace.CurrentCamera.ViewportSize
                        local clickX = viewport.X / 2 + 50
                        local clickY = viewport.Y * 0.82
                        
                        for i = 1, 6 do
                            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
                            task.wait(0.01)
                            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
                            statusText.Text = "CLICK " .. i .. "/6"
                            task.wait(0.02)
                        end
                        
                        statusText.Text = "COMPLETE"
                        statusText.TextColor3 = PURPLE_GLOW
                    else
                        statusText.Text = "EQUIP FAILED"
                        statusText.TextColor3 = TEXT_WHITE
                    end
                else
                    statusText.Text = "NO CLONER"
                    statusText.TextColor3 = TEXT_WHITE
                end
            else
                statusText.Text = "NO CARPET"
                statusText.TextColor3 = TEXT_WHITE
            end
            
            task.wait(1.5)
            statusText.Text = "READY"
            statusText.TextColor3 = PURPLE_GLOW
        end)
    end
    
    mainBtn.MouseButton1Click:Connect(performMainAction)
    hoverBtn.MouseButton1Click:Connect(function()
        if isHovering then stopHovering() else startHovering() end
    end)
    
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.C then
            mainBtn:Click()
        elseif input.KeyCode == Enum.KeyCode.S then
            stealBtn:Click()
        elseif input.KeyCode == Enum.KeyCode.H then
            hoverBtn:Click()
        elseif input.KeyCode == Enum.KeyCode.B then
            blockBtn:Click()
        elseif input.KeyCode == Enum.KeyCode.RightShift then
            screengui.Enabled = not screengui.Enabled
        end
    end)
    
    screengui.Destroying:Connect(function()
        if isHovering then stopHovering() end
    end)
end

local success, err = pcall(solsras_main)
if not success then
    warn("Failed to load:", err)
end

https://discord.gg/XdJWR5vZxk
