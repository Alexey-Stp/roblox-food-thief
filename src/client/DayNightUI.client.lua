-- DayNightUI.client.lua  (LocalScript in StarterPlayerScripts)
-- Shows a day/night clock panel with current in-game time, current phase,
-- and a countdown to the next phase (evening → night → dawn).
-- The panel background colour shifts with the time of day.

local Players    = game:GetService("Players")
local Lighting   = game:GetService("Lighting")

local localPlayer = Players.LocalPlayer

-- -------------------------------------------------------------------------
-- Day-cycle constants
-- DAY_CYCLE_SECONDS must equal Config.DAY_LENGTH on the server (default 240).
-- If you change Config.DAY_LENGTH, update this value to match so that the
-- countdown timers remain accurate.  (Lighting.ClockTime is replicated so
-- the client always has the correct current hour; only the rate differs.)
-- -------------------------------------------------------------------------
local DAY_CYCLE_SECONDS = 240   -- real seconds for one full 24-hour in-game day

-- Phase thresholds (in-game hours)
local HOUR_DAWN    =  6
local HOUR_EVENING = 17
local HOUR_NIGHT   = 20

-- -------------------------------------------------------------------------
-- Build the ScreenGui
-- -------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "DayNightHUD"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder   = 6   -- above the PlayerHUD (DisplayOrder 5)
screenGui.Parent         = localPlayer.PlayerGui

-- Main panel — top-center of the screen
local panel = Instance.new("Frame")
panel.Name                   = "ClockPanel"
panel.Size                   = UDim2.new(0, 240, 0, 100)
panel.Position               = UDim2.new(0.5, -120, 0, 8)
panel.BackgroundColor3       = Color3.fromRGB(30, 80, 160)
panel.BackgroundTransparency = 0.3
panel.BorderSizePixel        = 0
panel.Parent                 = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent       = panel

local padding = Instance.new("UIPadding")
padding.PaddingLeft   = UDim.new(0, 10)
padding.PaddingRight  = UDim.new(0, 10)
padding.PaddingTop    = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent        = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding   = UDim.new(0, 3)
layout.Parent    = panel

-- Row 1: current time  (e.g. "🕐 3:45 PM")
local timeLabel = Instance.new("TextLabel")
timeLabel.Name                   = "TimeLabel"
timeLabel.LayoutOrder            = 1
timeLabel.Size                   = UDim2.new(1, 0, 0, 32)
timeLabel.BackgroundTransparency = 1
timeLabel.TextColor3             = Color3.fromRGB(255, 255, 220)
timeLabel.TextScaled             = true
timeLabel.TextXAlignment         = Enum.TextXAlignment.Center
timeLabel.Font                   = Enum.Font.GothamBold
timeLabel.Text                   = "🕐 Loading..."
timeLabel.Parent                 = panel

-- Row 2: phase name  (e.g. "☀ Daytime")
local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name                   = "PhaseLabel"
phaseLabel.LayoutOrder            = 2
phaseLabel.Size                   = UDim2.new(1, 0, 0, 22)
phaseLabel.BackgroundTransparency = 1
phaseLabel.TextColor3             = Color3.fromRGB(200, 230, 255)
phaseLabel.TextScaled             = true
phaseLabel.TextXAlignment         = Enum.TextXAlignment.Center
phaseLabel.Font                   = Enum.Font.Gotham
phaseLabel.Text                   = ""
phaseLabel.Parent                 = panel

-- Row 3: countdown  (e.g. "Evening in: 4m 30s")
local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name                   = "CountdownLabel"
countdownLabel.LayoutOrder            = 3
countdownLabel.Size                   = UDim2.new(1, 0, 0, 22)
countdownLabel.BackgroundTransparency = 1
countdownLabel.TextColor3             = Color3.fromRGB(255, 220, 130)
countdownLabel.TextScaled             = true
countdownLabel.TextXAlignment         = Enum.TextXAlignment.Center
countdownLabel.Font                   = Enum.Font.Gotham
countdownLabel.Text                   = ""
countdownLabel.Parent                 = panel

-- -------------------------------------------------------------------------
-- Helper: format an in-game hour (0-24 float) as "H:MM AM/PM"
-- -------------------------------------------------------------------------
local function formatTime(hour)
	local h   = math.floor(hour) % 24
	local min = math.floor((hour - math.floor(hour)) * 60)
	local suffix = h >= 12 and "PM" or "AM"
	local h12   = h % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%d:%02d %s", h12, min, suffix)
end

-- -------------------------------------------------------------------------
-- Helper: seconds of real time until a target hour, given current clock
-- -------------------------------------------------------------------------
local function secondsUntil(currentHour, targetHour)
	-- Hours remaining (wraps past 24)
	local hoursRemaining = (targetHour - currentHour) % 24
	-- Convert in-game hours → real seconds
	local realSeconds = hoursRemaining / (24 / DAY_CYCLE_SECONDS)
	return realSeconds
end

-- -------------------------------------------------------------------------
-- Helper: format real seconds as "Xm Ys" (or "< 1s")
-- -------------------------------------------------------------------------
local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds == 0 then return "< 1s" end
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	if m > 0 then
		return string.format("%dm %02ds", m, s)
	else
		return string.format("%ds", s)
	end
end

-- -------------------------------------------------------------------------
-- Panel background colours per time-of-day phase
-- -------------------------------------------------------------------------
local PHASE_COLOURS = {
	-- { bgColor, border/accent }
	dawn    = Color3.fromRGB( 80,  60, 120),
	day     = Color3.fromRGB( 20,  80, 170),
	evening = Color3.fromRGB(160,  80,  20),
	night   = Color3.fromRGB( 10,  10,  40),
}

-- -------------------------------------------------------------------------
-- Main update loop (runs every second)
-- -------------------------------------------------------------------------
task.spawn(function()
	while true do
		local hour = Lighting.ClockTime  -- 0–24

		-- ── current time string ──────────────────────────────────────────
		timeLabel.Text = "🕐 " .. formatTime(hour)

		-- ── determine current phase and next milestone ───────────────────
		local bgColor, phaseText, countdownText

		if hour >= HOUR_NIGHT or hour < HOUR_DAWN then
			-- Night / early morning
			bgColor     = PHASE_COLOURS.night
			phaseText   = "🌙 Night"
			local secs  = secondsUntil(hour, HOUR_DAWN)
			countdownText = "Dawn in: " .. formatCountdown(secs)

		elseif hour >= HOUR_EVENING then
			-- Evening (17–20)
			bgColor     = PHASE_COLOURS.evening
			phaseText   = "🌆 Evening"
			local secs  = secondsUntil(hour, HOUR_NIGHT)
			countdownText = "Night in: " .. formatCountdown(secs)

		elseif hour >= HOUR_DAWN and hour < 8 then
			-- Dawn (6–8)
			bgColor     = PHASE_COLOURS.dawn
			phaseText   = "🌅 Dawn"
			local secs  = secondsUntil(hour, HOUR_EVENING)
			countdownText = "Evening in: " .. formatCountdown(secs)

		else
			-- Daytime (8–17)
			bgColor     = PHASE_COLOURS.day
			phaseText   = "☀ Daytime"
			local secs  = secondsUntil(hour, HOUR_EVENING)
			countdownText = "Evening in: " .. formatCountdown(secs)
		end

		panel.BackgroundColor3 = bgColor
		phaseLabel.Text        = phaseText
		countdownLabel.Text    = countdownText

		task.wait(1)
	end
end)
