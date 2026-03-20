-- Hud.client.lua  (LocalScript in StarterPlayerScripts)
-- Displays a compact heads-up overlay.
-- • Money indicator — bottom-right corner (small, unobtrusive)
-- • Speed / Jump panel — top-right corner (compact stats strip)

local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

-- -------------------------------------------------------------------------
-- Build the ScreenGui
-- -------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 5
screenGui.Parent = localPlayer.PlayerGui

-- ── Money panel — bottom-right ───────────────────────────────────────────
local moneyPanel = Instance.new("Frame")
moneyPanel.Name = "MoneyPanel"
moneyPanel.Size = UDim2.new(0, 160, 0, 30)
moneyPanel.Position = UDim2.new(1, -170, 1, -100)
moneyPanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
moneyPanel.BackgroundTransparency = 0.45
moneyPanel.BorderSizePixel = 0
moneyPanel.Parent = screenGui

local moneyCorner = Instance.new("UICorner")
moneyCorner.CornerRadius = UDim.new(0, 6)
moneyCorner.Parent = moneyPanel

local moneyLabel = Instance.new("TextLabel")
moneyLabel.Name = "MoneyLabel"
moneyLabel.Size = UDim2.new(1, -8, 1, 0)
moneyLabel.Position = UDim2.new(0, 8, 0, 0)
moneyLabel.BackgroundTransparency = 1
moneyLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
moneyLabel.TextScaled = true
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.Font = Enum.Font.GothamBold
moneyLabel.Text = "💰 $0"
moneyLabel.Parent = moneyPanel

-- ── Stats panel — top-right (speed & jump) ──────────────────────────────
local statsPanel = Instance.new("Frame")
statsPanel.Name = "StatsPanel"
statsPanel.Size = UDim2.new(0, 150, 0, 52)
statsPanel.Position = UDim2.new(1, -160, 0, 10)
statsPanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
statsPanel.BackgroundTransparency = 0.5
statsPanel.BorderSizePixel = 0
statsPanel.Parent = screenGui

local statsCorner = Instance.new("UICorner")
statsCorner.CornerRadius = UDim.new(0, 6)
statsCorner.Parent = statsPanel

local statsPadding = Instance.new("UIPadding")
statsPadding.PaddingLeft = UDim.new(0, 6)
statsPadding.PaddingRight = UDim.new(0, 6)
statsPadding.PaddingTop = UDim.new(0, 4)
statsPadding.PaddingBottom = UDim.new(0, 4)
statsPadding.Parent = statsPanel

local statsLayout = Instance.new("UIListLayout")
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.Padding = UDim.new(0, 2)
statsLayout.Parent = statsPanel

local function makeStatRow(order, icon, color)
	local lbl = Instance.new("TextLabel")
	lbl.LayoutOrder = order
	lbl.Size = UDim2.new(1, 0, 0, 20)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = icon .. "  ..."
	lbl.Parent = statsPanel
	return lbl
end

local speedLabel = makeStatRow(1, "⚡ Speed:", Color3.fromRGB(100, 220, 255))
local jumpLabel = makeStatRow(2, "🦘 Jump:", Color3.fromRGB(180, 255, 130))

-- -------------------------------------------------------------------------
-- Update loop
-- -------------------------------------------------------------------------
task.spawn(function()
	while true do
		local ls = localPlayer:FindFirstChild("leaderstats")
		local money = ls and ls:FindFirstChild("Money")
		moneyLabel.Text = "💰  $" .. (money and money.Value or 0)

		local char = localPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			speedLabel.Text = "⚡ Spd:  " .. math.floor(humanoid.WalkSpeed)
			jumpLabel.Text = "🦘 Jmp:  " .. math.floor(humanoid.JumpPower)
		else
			speedLabel.Text = "⚡ Spd:  —"
			jumpLabel.Text = "🦘 Jmp:  —"
		end

		task.wait(0.5)
	end
end)
