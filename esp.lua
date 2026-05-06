--//Toggle\\--
getgenv().Toggle = true 
getgenv().TC = false 

--//Variables\\--
local P = game:GetService("Players")
local LP = P.LocalPlayer
local UIS = game:GetService("UserInputService")

--//Debounce\\--
local DB = false

--//Notification\\--
game.StarterGui:SetCore("SendNotification", {
    Title = "ur script",
    Text = "works",
    Duration = 3
})

--// Clean ESP \\--
local function CleanESP()
    for _, v in pairs(P:GetPlayers()) do
        if v.Character then
            local highlight = v.Character:FindFirstChild("Totally NOT Esp")
            local healthBar = v.Character:FindFirstChild("HealthBar")
            if highlight then highlight:Destroy() end
            if healthBar then healthBar:Destroy() end
        end
    end
end

--// LeftAlt toggle \\--
UIS.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftAlt then
        getgenv().Toggle = not getgenv().Toggle
        game.StarterGui:SetCore("SendNotification", {
            Title = "ESP Status",
            Text = getgenv().Toggle and "Enabled" or "Disabled",
            Duration = 2
        })
        if not getgenv().Toggle then CleanESP() end
    end
end)

--//Loop\\--
while task.wait() do
    if getgenv().Toggle then
        if DB then continue end
        DB = true

        pcall(function()
            for _, v in pairs(P:GetChildren()) do
                if v:IsA("Player") and v ~= LP and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                    local humanoid = v.Character:FindFirstChildOfClass("Humanoid")

                    -- Highlight ESP
                    if not v.Character:FindFirstChild("Totally NOT Esp") and not getgenv().TC then
                        local ESP = Instance.new("Highlight", v.Character)
                        ESP.Name = "Totally NOT Esp"
                        ESP.Adornee = v.Character
                        ESP.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        ESP.FillColor = v.TeamColor.Color
                        ESP.FillTransparency = 0.5
                        ESP.OutlineColor = Color3.fromRGB(255, 255, 255)
                    end

                    -- Health bar (vertical "|" to the right)
                    if not v.Character:FindFirstChild("HealthBar") then
                        local BarGui = Instance.new("BillboardGui", v.Character)
                        BarGui.Name = "HealthBar"
                        BarGui.AlwaysOnTop = true
                        BarGui.Size = UDim2.new(0, 5, 0, 55)
                        BarGui.StudsOffset = Vector3.new(1.4, 0, 0) -- sits right of the character

                        local BG = Instance.new("Frame", BarGui)
                        BG.Name = "BG"
                        BG.Size = UDim2.new(1, 0, 1, 0)
                        BG.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                        BG.BorderSizePixel = 0

                        local Fill = Instance.new("Frame", BG)
                        Fill.Name = "Fill"
                        Fill.AnchorPoint = Vector2.new(0, 1)
                        Fill.Position = UDim2.new(0, 0, 1, 0)
                        Fill.Size = UDim2.new(1, 0, 1, 0)
                        Fill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
                        Fill.BorderSizePixel = 0
                    end

                    -- Update health bar fill + color
                    if humanoid then
                        local bar = v.Character:FindFirstChild("HealthBar")
                        if bar and bar:FindFirstChild("BG") then
                            local fill = bar.BG:FindFirstChild("Fill")
                            if fill then
                                local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                                fill.Size = UDim2.new(1, 0, pct, 0)
                                -- Green → Red gradient
                                fill.BackgroundColor3 = Color3.fromRGB(
                                    math.floor((1 - pct) * 255),
                                    math.floor(pct * 255),
                                    0
                                )
                            end
                        end
                    end
                end
            end
        end)

        DB = false
    end
end
