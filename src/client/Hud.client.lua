-- Hud.client.lua  (LocalScript in StarterPlayerScripts)
-- Displays a heads-up overlay showing the local player's Money, Walk Speed,
-- and Jump Power.  Updates every 0.5 seconds.

local Players    = game:GetService("Players")

local localPlayer = Players.LocalPlayer

-- -------------------------------------------------------------------------
-- Build the ScreenGui
-- -------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "PlayerHUD"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = false
screenGui.DisplayOrder    = 5
screenGui.Parent          = localPlayer.PlayerGui

-- Compact panel in the top-right corner
local panel = Instance.new("Frame")
panel.Name              = "HudPanel"
panel.Size              = UDim2.new(0, 200, 0, 110)
panel.Position          = UDim2.new(1, -210, 0, 10)
panel.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
panel.BackgroundTransparency = 0.45
panel.BorderSizePixel   = 0
panel.Parent            = screenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent       = panel

-- Padding
local padding = Instance.new("UIPadding")
padding.PaddingLeft   = UDim.new(0, 8)
padding.PaddingRight  = UDim.new(0, 8)
padding.PaddingTop    = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent        = panel

-- Auto-layout for the three rows
local layout = Instance.new("UIListLayout")
layout.SortOrder   = Enum.SortOrder.LayoutOrder
layout.Padding     = UDim.new(0, 4)
layout.Parent      = panel

-- Helper: create a single label row
local function makeRow(order, icon, color)
	local lbl = Instance.new("TextLabel")
	lbl.LayoutOrder          = order
	lbl.Size                 = UDim2.new(1, 0, 0, 28)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3           = color
	lbl.TextScaled           = true
	lbl.TextXAlignment       = Enum.TextXAlignment.Left
	lbl.Font                 = Enum.Font.GothamBold
	lbl.Text                 = icon .. "  ..."
	lbl.Parent               = panel
	return lbl
end

local moneyLabel = makeRow(1, "💰 Money:",  Color3.fromRGB(255, 215,   0))
local speedLabel = makeRow(2, "⚡ Speed:",  Color3.fromRGB(100, 220, 255))
local jumpLabel  = makeRow(3, "🦘 Jump:",   Color3.fromRGB(180, 255, 130))

-- -------------------------------------------------------------------------
-- Update loop
-- -------------------------------------------------------------------------
task.spawn(function()
	while true do
		local ls = localPlayer:FindFirstChild("leaderstats")
		local money = ls and ls:FindFirstChild("Money")
		moneyLabel.Text = "💰 Money:  $" .. (money and money.Value or 0)

		local char      = localPlayer.Character
		local humanoid  = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			speedLabel.Text = "⚡ Speed:   " .. math.floor(humanoid.WalkSpeed)
			jumpLabel.Text  = "🦘 Jump:    " .. math.floor(humanoid.JumpPower)
		else
			speedLabel.Text = "⚡ Speed:   —"
			jumpLabel.Text  = "🦘 Jump:    —"
		end

		task.wait(0.5)
	end
end)
