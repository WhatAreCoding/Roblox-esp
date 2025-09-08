local success, error = pcall(function()

    if _G.ESP then
        _G.ESP:Cleanup()
        _G.ESP = nil
    end

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Teams = game:GetService("Teams")
    local CoreGui = game:GetService("CoreGui")

    local ESPManager = {}
    ESPManager.__index = ESPManager

    function ESPManager.new()
        local self = setmetatable({}, ESPManager)
        self:Initialize()
        return self
    end

    function ESPManager:Initialize()

        self.MAX_DISTANCE = 10000
        self.ALERT_DISTANCE = 0
        self.TARGET_FPS = 60
        self.UPDATE_RATE = 1 / self.TARGET_FPS
        self.RELOAD_TIME = 45

        self.espCache = {}
        self.positionCache = {}
        self.alertCooldowns = {}
        self.friendCache = {}
        self.connections = {}
        self.playerConnections = {}
        self.lastUpdate = 0
        self.reloadTime = tick()

        self.localPlayer = Players.LocalPlayer
        self.camera = workspace.CurrentCamera

        self:SetupConnections()
        self:InitializePlayers()
        
        print("ESP loaded successfully! ⚡️")
    end

    function ESPManager:Cleanup()

        for _, connection in pairs(self.connections) do
            if type(connection) == "userdata" and connection.Disconnect then
                pcall(connection.Disconnect, connection)
            end
        end
        
        for player, connections in pairs(self.playerConnections) do
            for _, connection in pairs(connections) do
                if type(connection) == "userdata" and connection.Disconnect then
                    pcall(connection.Disconnect, connection)
                end
            end
        end

        for player, data in pairs(self.espCache) do
            self:RemovePlayerESP(player)
        end

        self.connections = {}
        self.playerConnections = {}
        self.espCache = {}
        self.positionCache = {}
        
        print("")
    end

    function ESPManager:Restart()
        self:Cleanup()
        wait(0.1)
        self:Initialize()
    end

    function ESPManager:SetupConnections()
        self.connections.playerAdded = Players.PlayerAdded:Connect(function(player)
            if player ~= self.localPlayer then
                self:CreateHealthbar(player)
                self:SetupPlayerConnections(player)
            end
        end)

        self.connections.playerRemoving = Players.PlayerRemoving:Connect(function(player)
            self:RemovePlayerESP(player)
        end)

        self.connections.renderStepped = RunService.RenderStepped:Connect(function()
            self:UpdateESP()
            if tick() - self.reloadTime >= self.RELOAD_TIME then
                self:Restart()
            end
        end)

        self.connections.heartbeat = RunService.Heartbeat:Connect(function()
            self:UpdatePositions()
        end)
    end

    function ESPManager:SetupPlayerConnections(player)
        if not self.playerConnections[player] then
            self.playerConnections[player] = {}
        end
        
        self.playerConnections[player].characterAdded = player.CharacterAdded:Connect(function(character)
            task.spawn(function()
                wait(0.5) 
                
                if not self.espCache[player] or not character or not character.Parent then
                    return
                end

                if self.espCache[player].highlight then
                    pcall(function() self.espCache[player].highlight:Destroy() end)
                    self.espCache[player].highlight = nil
                end

                local playerColor = self.espCache[player].elements.barFill.Color
                self.espCache[player].highlight = Instance.new("Highlight")
                self.espCache[player].highlight.FillColor = playerColor
                self.espCache[player].highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                self.espCache[player].highlight.FillTransparency = 0.7
                self.espCache[player].highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                self.espCache[player].highlight.Parent = character
                self.espCache[player].highlight.Enabled = self.espCache[player].lastVisible
            end)
        end)
    end

    function ESPManager:InitializePlayers()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= self.localPlayer then
                self:CreateHealthbar(player)
                self:SetupPlayerConnections(player)
            end
        end
    end

    function ESPManager:UpdatePositions()
        for player, data in pairs(self.espCache) do
            if player and player.Character then
                local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    self.positionCache[player] = {
                        position = rootPart.Position,
                        timestamp = tick(),
                        valid = true
                    }
                end
            end
        end
    end

    function ESPManager:IsFriend(player)
        if player == nil then return false end
        if self.friendCache[player] == nil then
            local success, result = pcall(function()
                return self.localPlayer:IsFriendsWith(player.UserId)
            end)
            self.friendCache[player] = success and result or false
        end
        return self.friendCache[player]
    end

    function ESPManager:GetPlayerState(player)
        if not player or not player.Character then return "invalid", true end
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if not humanoid then return "no_humanoid", true end
        if humanoid.Health <= 0 then return "dead", true end
        return "alive", false
    end

    function ESPManager:GetPlayerColor(player, isAlert)
        if isAlert then
            return math.sin(tick() * 10) > 0 and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 150, 150)
        end
        
        local state, isDead = self:GetPlayerState(player)
        if isDead then return Color3.fromRGB(150, 150, 150) end
        if self:IsFriend(player) then
            return Color3.fromHSV((tick() % 5) / 5, 1, 1)
        end
        if player.Team then return player.Team.TeamColor.Color end
        return Color3.fromRGB(255, 255, 255)
    end

    function ESPManager:CreateHealthbar(player)
        if not player or self.espCache[player] then return end
        
        local playerColor = self:GetPlayerColor(player, false)
        local state, isDead = self:GetPlayerState(player)
        
        self.espCache[player] = {
            elements = {
                nickText = Drawing.new("Text"),
                hpText = Drawing.new("Text"),
                teamText = Drawing.new("Text"),
                distanceText = Drawing.new("Text"),
                barOutline = Drawing.new("Square"),
                barFill = Drawing.new("Square"),
                line = Drawing.new("Line")
            },
            highlight = nil,
            isFriend = self:IsFriend(player),
            isDead = isDead,
            lastVisible = false,
            lastAlertState = false,
            alertCooldown = 0
        }
        
        local drawings = self.espCache[player].elements

        drawings.nickText.Size = 15
        drawings.nickText.Outline = true
        drawings.nickText.Color = playerColor
        drawings.nickText.Center = true
        drawings.nickText.Text = tostring(player.Name)
        
        drawings.hpText.Size = 13
        drawings.hpText.Outline = true
        drawings.hpText.Color = isDead and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(200, 200, 200)
        drawings.hpText.Center = true
        
        drawings.teamText.Size = 11
        drawings.teamText.Outline = true
        drawings.teamText.Color = isDead and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(170, 170, 170)
        drawings.teamText.Center = true
        drawings.teamText.Text = player.Team and tostring(player.Team.Name) or "No Team"
        
        drawings.distanceText.Size = 11
        drawings.distanceText.Outline = true
        drawings.distanceText.Color = Color3.fromRGB(200, 200, 255)
        drawings.distanceText.Center = true
        
        drawings.barOutline.Thickness = 2
        drawings.barOutline.Filled = false
        drawings.barOutline.Color = Color3.fromRGB(0, 0, 0)
        drawings.barOutline.Rounding = 3
        
        drawings.barFill.Filled = true
        drawings.barFill.Thickness = 1
        drawings.barFill.Color = playerColor
        drawings.barFill.Rounding = 3

        drawings.line.Thickness = 1
        drawings.line.Color = playerColor
        drawings.line.Transparency = 0.8

        if player.Character then
            self.espCache[player].highlight = Instance.new("Highlight")
            self.espCache[player].highlight.FillColor = playerColor
            self.espCache[player].highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            self.espCache[player].highlight.FillTransparency = 0.7
            self.espCache[player].highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            self.espCache[player].highlight.Parent = player.Character
            self.espCache[player].highlight.Enabled = false
        end
    end

    function ESPManager:RemovePlayerESP(player)
        if not player or not self.espCache[player] then return end
        
        if self.playerConnections[player] then
            for _, connection in pairs(self.playerConnections[player]) do
                if type(connection) == "userdata" and connection.Disconnect then
                    pcall(connection.Disconnect, connection)
                end
            end
            self.playerConnections[player] = nil
        end
        
        local data = self.espCache[player]
        for _, drawing in pairs(data.elements) do
            pcall(function() drawing:Remove() end)
        end
        if data.highlight then
            pcall(function() data.highlight:Destroy() end)
        end
        
        self.espCache[player] = nil
        self.positionCache[player] = nil
        self.friendCache[player] = nil
    end

    function ESPManager:UpdateESP()
        local currentTime = tick()
        if currentTime - self.lastUpdate < self.UPDATE_RATE then return end
        self.lastUpdate = currentTime
        
        local myCharacter = self.localPlayer.Character
        local myRootPart = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
        if not myCharacter or not myRootPart then
            for _, data in pairs(self.espCache) do
                if data.lastVisible then
                    for _, drawing in pairs(data.elements) do
                        pcall(function() drawing.Visible = false end)
                    end
                    if data.highlight then 
                        pcall(function() data.highlight.Enabled = false end)
                    end
                    data.lastVisible = false
                end
            end
            return
        end
        
        local myWorldPosition = myRootPart.Position
        local myScreenPos = self.camera:WorldToViewportPoint(myWorldPosition)
        
        for player, data in pairs(self.espCache) do
            if not player or not player.Parent then
                self:RemovePlayerESP(player)
                continue
            end
            
            local state, isDead = self:GetPlayerState(player)
            
            if data.isDead ~= isDead then
                data.isDead = isDead
                if isDead then
                    pcall(function() 
                        data.elements.hpText.Text = "0/0"
                        data.elements.barOutline.Visible = false
                        data.elements.barFill.Visible = false
                    end)
                end
            end
            
            local posData = self.positionCache[player]
            if not posData or not posData.valid then continue end
            
            local distance = (myWorldPosition - posData.position).Magnitude
            if distance > self.MAX_DISTANCE then
                if data.lastVisible then
                    for _, drawing in pairs(data.elements) do
                        pcall(function() drawing.Visible = false end)
                    end
                    if data.highlight then 
                        pcall(function() data.highlight.Enabled = false end)
                    end
                    data.lastVisible = false
                end
                continue
            end
            
            local isAlert = distance <= self.ALERT_DISTANCE and not isDead and not data.isFriend
            if isAlert and not data.lastAlertState and data.alertCooldown <= currentTime then
                data.alertCooldown = currentTime + 8
            end
            data.lastAlertState = isAlert
            
            local playerColor = self:GetPlayerColor(player, isAlert)
            local drawings = data.elements
            
            pcall(function()
                drawings.nickText.Color = playerColor
                drawings.barFill.Color = playerColor
                drawings.line.Color = playerColor
            end)
            
            local headScreenPos = self.camera:WorldToViewportPoint(posData.position + Vector3.new(0, 2, 0))
            local isVisible = headScreenPos.Z > 0
            
            if isVisible then
                if not data.lastVisible then
                    for _, drawing in pairs(drawings) do
                        pcall(function() drawing.Visible = true end)
                    end
                    if data.highlight then 
                        pcall(function() data.highlight.Enabled = true end)
                    end
                    data.lastVisible = true
                end
                
                pcall(function()
                    drawings.nickText.Position = Vector2.new(headScreenPos.X, headScreenPos.Y - 57)
                    drawings.hpText.Position = Vector2.new(headScreenPos.X, headScreenPos.Y - 43)
                    drawings.teamText.Position = Vector2.new(headScreenPos.X, headScreenPos.Y - 30)
                    drawings.distanceText.Position = Vector2.new(headScreenPos.X, headScreenPos.Y - 19)
                end)
                
                local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
                local health = humanoid and math.floor(humanoid.Health) or 0
                local maxHealth = humanoid and math.floor(humanoid.MaxHealth) or 100
                
                pcall(function()
                    drawings.hpText.Text = isDead and "0/0" or string.format("%d/%d", health, maxHealth)
                    drawings.distanceText.Text = string.format("%d studs", math.floor(distance))
                end)
                
                if not isDead and humanoid then
                    local healthPercent = humanoid.Health / humanoid.MaxHealth
                    local barWidth = 60
                    local barHeight = 5
                    local barX = headScreenPos.X - barWidth / 2
                    local barY = headScreenPos.Y - 5
                    
                    pcall(function()
                        drawings.barOutline.Size = Vector2.new(barWidth, barHeight)
                        drawings.barOutline.Position = Vector2.new(barX, barY)
                        drawings.barOutline.Visible = true
                        
                        drawings.barFill.Size = Vector2.new(math.max(1, barWidth * healthPercent), barHeight)
                        drawings.barFill.Position = Vector2.new(barX, barY)
                        drawings.barFill.Visible = true
                    end)
                else
                    pcall(function()
                        drawings.barOutline.Visible = false
                        drawings.barFill.Visible = false
                    end)
                end
                
                pcall(function()
                    drawings.line.From = Vector2.new(myScreenPos.X, myScreenPos.Y)
                    drawings.line.To = Vector2.new(headScreenPos.X, headScreenPos.Y)
                end)
                
                if not data.highlight or not data.highlight.Parent or data.highlight.Parent ~= player.Character then
                    if data.highlight then
                        pcall(function() data.highlight:Destroy() end)
                    end
                    if player.Character then
                        data.highlight = Instance.new("Highlight")
                        data.highlight.FillColor = playerColor
                        data.highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                        data.highlight.FillTransparency = 0.7
                        data.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        data.highlight.Parent = player.Character
                        data.highlight.Enabled = true
                    end
                end
                
            elseif data.lastVisible then
                for _, drawing in pairs(drawings) do
                    pcall(function() drawing.Visible = false end)
                end
                if data.highlight then 
                    pcall(function() data.highlight.Enabled = false end)
                end
                data.lastVisible = false
            end
        end
    end

    _G.ESP = ESPManager.new()

end)

if not success then
    warn("ESP loading error:", error)
    pcall(function()
        if _G.ESP then
            _G.ESP:Cleanup()
            _G.ESP = nil
        end
    end)
end
