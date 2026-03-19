-- FridgeClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Handles client-side fridge interactions:
--   • Q key with nearest player in range → fires GiveFood to server
--   • G key → fires DropFood to server
--   • StoreFoodInFridge / UpgradeFridge are triggered via ProximityPrompts on
--     the fridge Parts (handled here via PromptTriggered or fired directly).
--   • FridgeStoredFeedback → shows a price breakdown popup for 3 seconds.
--
-- Note: The actual ProximityPrompts for fridge interaction are added by
-- RefrigeratorSystem.lua on the server. This script only handles:
--   1. The G-key drop shortcut
--   2. The E-on-nearby-player give shortcut
--   3. The FridgeStoredFeedback price popup

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local GiveFood = eventsFolder:WaitForChild("GiveFood")
local DropFood = eventsFolder:WaitForChild("DropFood")
local FridgeStoredFeedback = eventsFolder:WaitForChild("FridgeStoredFeedback")

-- Debounce to avoid double-firing
local lastGive = 0
local lastDrop = 0

-- -------------------------------------------------------------------------
-- Find the nearest player within give range (12 studs)
-- -------------------------------------------------------------------------
local function findNearbyPlayer()
	local char = localPlayer.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local best, bestDist = nil, 12
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= localPlayer and other.Character then
			local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
			if otherHRP then
				local d = (otherHRP.Position - hrp.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = other
				end
			end
		end
	end
	return best
end

-- -------------------------------------------------------------------------
-- Price breakdown popup
-- -------------------------------------------------------------------------
local function showFeedbackPopup(foodName, basePrice, bonusAmt, finalPrice)
	-- Reuse or create a ScreenGui
	local existing = localPlayer.PlayerGui:FindFirstChild("FridgeFeedbackGui")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FridgeFeedbackGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = localPlayer.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 340, 0, 130)
	frame.Position = UDim2.new(0.5, -170, 0.65, 0)
	frame.BackgroundColor3 = Color3.fromRGB(10, 30, 50)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = frame

	local function addLine(text, color)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 22)
		lbl.Text = text
		lbl.TextColor3 = color
		lbl.BackgroundTransparency = 1
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextScaled = true
		lbl.Font = Enum.Font.SourceSansBold
		lbl.Parent = frame
		return lbl
	end

	addLine("Stored: " .. foodName, Color3.fromRGB(200, 200, 200))
	addLine("Base Price:    $" .. basePrice, Color3.fromRGB(180, 180, 180))
	addLine("Fridge Bonus:  +$" .. bonusAmt, Color3.fromRGB(80, 220, 80))
	addLine("Final Value:   $" .. finalPrice, Color3.fromRGB(255, 220, 50))

	-- Fade in
	frame.BackgroundTransparency = 1
	for _, lbl in ipairs(frame:GetChildren()) do
		if lbl:IsA("TextLabel") then
			lbl.TextTransparency = 1
		end
	end

	local fadeIn = TweenService:Create(frame, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 })
	fadeIn:Play()
	for _, lbl in ipairs(frame:GetChildren()) do
		if lbl:IsA("TextLabel") then
			TweenService:Create(lbl, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
		end
	end

	-- Hold then fade out
	task.delay(3, function()
		if not screenGui.Parent then
			return
		end
		local fadeOut = TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		fadeOut:Play()
		for _, lbl in ipairs(frame:GetChildren()) do
			if lbl:IsA("TextLabel") then
				TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			end
		end
		task.delay(0.5, function()
			screenGui:Destroy()
		end)
	end)
end

-- -------------------------------------------------------------------------
-- Key bindings
-- -------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	-- G key → drop equipped food
	if input.KeyCode == Enum.KeyCode.G then
		local now = tick()
		if now - lastDrop < 0.5 then
			return
		end
		lastDrop = now
		DropFood:FireServer()

	-- F key → give food to nearest player
	elseif input.KeyCode == Enum.KeyCode.F then
		local now = tick()
		if now - lastGive < 0.5 then
			return
		end
		lastGive = now
		local target = findNearbyPlayer()
		if target then
			GiveFood:FireServer(target)
		end
	end
end)

-- -------------------------------------------------------------------------
-- Fridge price breakdown popup
-- -------------------------------------------------------------------------
FridgeStoredFeedback.OnClientEvent:Connect(function(foodName, basePrice, bonusAmt, finalPrice)
	showFeedbackPopup(foodName, basePrice, bonusAmt, finalPrice)
end)
