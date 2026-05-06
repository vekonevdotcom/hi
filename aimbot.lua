local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Holding = false

--//Notification\\--
game.StarterGui:SetCore("SendNotification", {
    Title = "turn on/off",
    Text = "on left alt",
    Duration = 2
})

_G.AimbotEnabled = true
_G.TeamCheck = false
_G.AimPart = "Head" 
_G.Sensitivity = 1 

_G.CircleSides = 64
_G.CircleColor = Color3.fromRGB(255, 255, 255)
_G.CircleTransparency = 0.7
_G.CircleRadius = 80
_G.CircleFilled = false
_G.CircleVisible = true
_G.CircleThickness = 0

--// FOV Drawing \\--
local FOVCircle = Drawing.new("Circle")
FOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
FOVCircle.Radius = _G.CircleRadius
FOVCircle.Filled = _G.CircleFilled
FOVCircle.Color = _G.CircleColor
FOVCircle.Visible = _G.CircleVisible
FOVCircle.Transparency = _G.CircleTransparency
FOVCircle.NumSides = _G.CircleSides
FOVCircle.Thickness = _G.CircleThickness

--// Target UI Setup \\--
local targetGui = Instance.new("ScreenGui")
targetGui.Name = "AimbotTargetUI"
local success = pcall(function() targetGui.Parent = game:GetService("CoreGui") end)
if not success then targetGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local bgFrame = Instance.new("Frame")
bgFrame.Size = UDim2.new(0, 200, 0, 40)
bgFrame.Position = UDim2.new(0.5, -100, 0.8, 0)
bgFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
bgFrame.BackgroundTransparency = 0.4
bgFrame.BorderSizePixel = 0
bgFrame.Visible = false
bgFrame.Parent = targetGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 6)
uiCorner.Parent = bgFrame

local targetText = Instance.new("TextLabel")
targetText.Size = UDim2.new(1, 0, 1, 0)
targetText.BackgroundTransparency = 1
targetText.TextColor3 = Color3.fromRGB(255, 255, 255)
targetText.TextSize = 18
targetText.Font = Enum.Font.GothamBold
targetText.Text = "Target: None"
targetText.Parent = bgFrame

--// THE FIX IS HERE \\--
local function GetClosestPlayer()
    local MaximumDistance = _G.CircleRadius
    local Target = nil

    for _, v in next, Players:GetPlayers() do
        if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") and v.Character:FindFirstChild("Humanoid") then
            if v.Character.Humanoid.Health > 0 then
                if not _G.TeamCheck or v.Team ~= LocalPlayer.Team then
                    
                    -- Capture the 'OnScreen' boolean to prevent aiming backwards
                    local ScreenPoint, OnScreen = Camera:WorldToScreenPoint(v.Character[_G.AimPart].Position)
                    
                    if OnScreen then
                        local MousePos = UserInputService:GetMouseLocation()
                        local VectorDistance = (Vector2.new(ScreenPoint.X, ScreenPoint.Y) - MousePos).Magnitude
                        
                        if VectorDistance < MaximumDistance then
                            MaximumDistance = VectorDistance -- Update distance to find the ABSOLUTE closest
                            Target = v
                        end
                    end
                end
            end
        end
    end

    return Target
end

UserInputService.InputBegan:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
        Holding = true
    end
end)

UserInputService.InputEnded:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
        Holding = false
        bgFrame.Visible = false
    end
end)

--// ДОБАВЛЕНО: Кнопка включения/выключения аимбота и круга \\--
_G.ToggleKey = Enum.KeyCode.LeftAlt -- Кнопка переключения

UserInputService.InputBegan:Connect(function(Input, gameProcessed)
    if not gameProcessed and Input.KeyCode == _G.ToggleKey then
        _G.AimbotEnabled = not _G.AimbotEnabled
        
        -- Уведомление о статусе
        local status = _G.AimbotEnabled and "ON" or "OFF"
        game.StarterGui:SetCore("SendNotification", {
            Title = "Aimbot Toggle",
            Text = "Aimbot is now: " .. status,
            Duration = 2
        })
        
        -- Управляем видимостью круга и интерфейса
        if _G.AimbotEnabled then
            FOVCircle.Visible = _G.CircleVisible -- Показываем круг (если он включен в настройках)
        else
            FOVCircle.Visible = false -- Прячем круг
            bgFrame.Visible = false   -- Прячем UI с именем цели
        end
    end
end)
--// КОНЕЦ ДОБАВЛЕНИЯ \\--

RunService.RenderStepped:Connect(function()
    -- Круг будет следовать за мышкой только если он видим
    if FOVCircle.Visible then
        FOVCircle.Position = UserInputService:GetMouseLocation()
    end

    if Holding and _G.AimbotEnabled then
        local Target = GetClosestPlayer()
        if Target and Target.Character and Target.Character:FindFirstChild(_G.AimPart) then
            bgFrame.Visible = true
            targetText.Text = "Target: " .. Target.Name

            local targetPos = Target.Character[_G.AimPart].Position
            local newCFrame = CFrame.lookAt(Camera.CFrame.Position, targetPos)
            
            Camera.CFrame = Camera.CFrame:Lerp(newCFrame, _G.Sensitivity)
        else
            bgFrame.Visible = false
        end
    else
        bgFrame.Visible = false
    end
end)
