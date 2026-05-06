--//Toggle\\--
getgenv().Toggle = true 
getgenv().TC = false 
local PlayerName = "Name" 

--//Variables\\--
local P = game:GetService("Players")
local LP = P.LocalPlayer
local UIS = game:GetService("UserInputService") -- Добавлено для отслеживания кнопок

--//Debounce\\--
local DB = false

--//Notification\\--
game.StarterGui:SetCore("SendNotification", {
    Title = "ur script",
    Text = "works",
    Duration = 3
})

--// Функция очистки при выключении \\--
local function CleanESP()
    for _, v in pairs(P:GetPlayers()) do
        if v.Character then
            local highlight = v.Character:FindFirstChild("Totally NOT Esp")
            local icon = v.Character:FindFirstChild("Icon")
            if highlight then highlight:Destroy() end
            if icon then icon:Destroy() end
        end
    end
end

--// Переключатель на LeftAlt \\--
UIS.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftAlt then
        getgenv().Toggle = not getgenv().Toggle
        
        game.StarterGui:SetCore("SendNotification", {
            Title = "ESP Status",
            Text = getgenv().Toggle and "Enabled" or "Disabled",
            Duration = 2
        })
        
        if not getgenv().Toggle then
            CleanESP()
        end
    end
end)

--//Loop\\--
-- Убрал 'break', чтобы скрипт не "умирал" после первого выключения
while task.wait() do
    if getgenv().Toggle then
        if DB then continue end
        DB = true

        pcall(function()
            for i,v in pairs(P:GetChildren()) do
                if v:IsA("Player") and v ~= LP and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                    local hrp = v.Character:FindFirstChild("HumanoidRootPart")
                    local lp_hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                    
                    if lp_hrp then
                        local pos = math.floor((lp_hrp.Position - hrp.Position).magnitude)

                        if v.Character:FindFirstChild("Totally NOT Esp") == nil and v.Character:FindFirstChild("Icon") == nil and getgenv().TC == false then
                            --//ESP-Highlight\\--
                            local ESP = Instance.new("Highlight", v.Character)
                            ESP.Name = "Totally NOT Esp"
                            ESP.Adornee = v.Character
                            ESP.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            ESP.FillColor = v.TeamColor.Color
                            ESP.FillTransparency = 0.5
                            ESP.OutlineColor = Color3.fromRGB(255, 255, 255)

                            --//ESP-Text\\--
                            local Icon = Instance.new("BillboardGui", v.Character)
                            Icon.Name = "Icon"
                            Icon.AlwaysOnTop = true
                            Icon.ExtentsOffset = Vector3.new(0, 3, 0) -- Чуть выше головы
                            Icon.Size = UDim2.new(0, 200, 0, 50)

                            local ESPText = Instance.new("TextLabel", Icon)
                            ESPText.BackgroundTransparency = 1
                            ESPText.Size = UDim2.new(1, 0, 1, 0)
                            ESPText.Font = Enum.Font.SciFi
                            ESPText.Text = v[PlayerName].." | "..pos.."m"
                            ESPText.TextColor3 = v.TeamColor.Color
                            ESPText.TextSize = 14
                        else
                            -- Обновление дистанции
                            local icon = v.Character:FindFirstChild("Icon")
                            if icon and icon:FindFirstChildOfClass("TextLabel") then
                                icon:FindFirstChildOfClass("TextLabel").Text = v[PlayerName].." | "..pos.."m"
                            end
                        end
                    end
                end
            end
        end)
        
        DB = false
    end
end
