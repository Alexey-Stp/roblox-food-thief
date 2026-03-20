-- HealthBar.client.lua  (LocalScript in StarterPlayerScripts)
-- Displays a compact custom health bar for the local player near the bottom
-- of the screen.  Updates at 10 Hz and colour-shifts green → yellow → red
-- as health drops.

local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

-- -------------------------------------------------------------------------
-- Build the ScreenGui
-- -------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HealthBarHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 8 -- above all other HUDs
screenGui.Parent = localPlayer.PlayerGui

-- Outer panel — bottom-center, compact
local panel = Instance.new("Frame")
panel.Name = "HealthPanel"
panel.Size = UDim2.new(0, 260, 0, 26)
panel.Position = UDim2.new(0.5, -130, 1, -80)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Parent = screenGui

local outerCorner = Instance.new("UICorner")
outerCorner.CornerRadius = UDim.new(0, 6)
outerCorner.Parent = panel

-- Green fill bar (inside the panel)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 1, 0)
fill.Position = UDim2.new(0, 0, 0, 0)
fill.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
fill.BorderSizePixel = 0
fill.ZIndex = 1
fill.Parent = panel

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = fill

-- Overlay text label (HP numbers)
local label = Instance.new("TextLabel")
label.Name = "HealthLabel"
label.Size = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = "❤  100 / 100"
label.ZIndex = 2
label.Parent = panel

-- -------------------------------------------------------------------------
-- Update loop — 10 Hz
-- -------------------------------------------------------------------------
task.spawn(function()
	while true do
		local char = localPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local hp = humanoid.Health
			local maxHp = humanoid.MaxHealth
			local ratio = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0

			fill.Size = UDim2.new(ratio, 0, 1, 0)
			label.Text = string.format("❤  %d / %d", math.floor(hp), math.floor(maxHp))

			-- Colour shift: green → yellow → red
			if ratio > 0.5 then
				fill.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
			elseif ratio > 0.25 then
				fill.BackgroundColor3 = Color3.fromRGB(220, 180, 30)
			else
				fill.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
			end
		end

		task.wait(0.1)
	end
end)
