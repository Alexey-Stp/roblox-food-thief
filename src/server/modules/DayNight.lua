-- DayNight.lua
-- Runs a smooth day/night cycle by advancing Lighting.ClockTime and
-- updating the sky / ambient colours based on time of day.

local Lighting = game:GetService("Lighting")

local DayNight = {}

-- Hour thresholds used to determine whether it is currently night
local NIGHT_START_HOUR = 20
local NIGHT_END_HOUR   = 6

-- -------------------------------------------------------------------------
-- Sky presets (applied at specific clock hours)
-- -------------------------------------------------------------------------
local SKY_PRESETS = {
	-- { hour, ambientColor, outdoorAmbient, brightness, fogColor }
	{ hour =  6, ambient = Color3.fromRGB( 80,  60,  40), outdoor = Color3.fromRGB(120,  90,  60), brightness = 1.0, fogColor = Color3.fromRGB(200, 180, 160) },  -- dawn
	{ hour =  8, ambient = Color3.fromRGB(100, 100, 100), outdoor = Color3.fromRGB(150, 150, 150), brightness = 2.0, fogColor = Color3.fromRGB(180, 200, 220) },  -- morning
	{ hour = 12, ambient = Color3.fromRGB(120, 120, 120), outdoor = Color3.fromRGB(180, 180, 180), brightness = 3.0, fogColor = Color3.fromRGB(160, 190, 220) },  -- noon
	{ hour = 17, ambient = Color3.fromRGB(110, 100,  80), outdoor = Color3.fromRGB(160, 140,  90), brightness = 2.0, fogColor = Color3.fromRGB(220, 180, 120) },  -- dusk
	{ hour = 20, ambient = Color3.fromRGB( 30,  30,  50), outdoor = Color3.fromRGB( 40,  40,  70), brightness = 0.6, fogColor = Color3.fromRGB( 30,  30,  50) },  -- evening
	{ hour = 24, ambient = Color3.fromRGB( 15,  15,  30), outdoor = Color3.fromRGB( 20,  20,  40), brightness = 0.3, fogColor = Color3.fromRGB( 20,  20,  35) },  -- midnight
}

-- -------------------------------------------------------------------------
-- Linear interpolation helpers
-- -------------------------------------------------------------------------
local function lerpNumber(a, b, t)
	return a + (b - a) * t
end

local function lerpColor(a, b, t)
	return Color3.new(
		lerpNumber(a.R, b.R, t),
		lerpNumber(a.G, b.G, t),
		lerpNumber(a.B, b.B, t))
end

-- Return the two surrounding presets for a given clock hour and the blend factor
local function getPresets(hour)
	-- Normalize hour into [0, 24)
	local h = hour % 24
	local prev = SKY_PRESETS[#SKY_PRESETS]
	local next = SKY_PRESETS[1]

	for i = 1, #SKY_PRESETS do
		local p = SKY_PRESETS[i]
		local prevP = (i == 1) and SKY_PRESETS[#SKY_PRESETS] or SKY_PRESETS[i - 1]
		local ph = prevP.hour % 24
		local nh = p.hour % 24

		-- Wrap-around handling (midnight boundary)
		if ph > nh then
			if h >= ph or h < nh then
				prev = prevP
				next = p
				local span = (24 - ph) + nh
				local elapsed = (h >= ph) and (h - ph) or (24 - ph + h)
				return prev, next, elapsed / span
			end
		else
			if h >= ph and h < nh then
				prev = prevP
				next = p
				return prev, next, (h - ph) / (nh - ph)
			end
		end
	end
	return SKY_PRESETS[#SKY_PRESETS], SKY_PRESETS[1], 0
end

-- Apply blended lighting values to Lighting service
local function applyLighting(hour)
	local p, n, t = getPresets(hour)

	Lighting.Ambient          = lerpColor(p.ambient,  n.ambient,  t)
	Lighting.OutdoorAmbient   = lerpColor(p.outdoor,  n.outdoor,  t)
	Lighting.Brightness       = lerpNumber(p.brightness, n.brightness, t)
	Lighting.FogColor         = lerpColor(p.fogColor, n.fogColor, t)

	-- Fog distance: dense at night, clear midday
	local isNight = (hour >= NIGHT_START_HOUR or hour < NIGHT_END_HOUR)
	Lighting.FogEnd   = isNight and 600 or 2000
	Lighting.FogStart = isNight and 200 or 800
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

-- dayLength: real-world seconds for one full in-game day
function DayNight.start(dayLength)
	dayLength = dayLength or 240

	-- Start at early morning
	Lighting.ClockTime = 8

	task.spawn(function()
		while true do
			-- Advance clock: 24 hours over dayLength seconds → 24/dayLength per second
			local step = 24 / dayLength * 0.5   -- update twice per second
			Lighting.ClockTime = (Lighting.ClockTime + step) % 24
			applyLighting(Lighting.ClockTime)
			task.wait(0.5)
		end
	end)
end

return DayNight
