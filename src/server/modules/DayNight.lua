-- DayNight.lua
-- Advances Lighting.ClockTime (replicated; gameplay polls it for night
-- detection) and publishes the cycle length as the Lighting attribute
-- "DayLength". The ambient / fog colour blend for each hour is purely visual
-- and is applied by each client (DayNightLighting.client.lua).

local Lighting = game:GetService("Lighting")

local DayNight = {}

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

-- dayLength: real-world seconds for one full in-game day
function DayNight.start(dayLength)
	dayLength = dayLength or 240

	-- Start at early morning
	Lighting.ClockTime = 8
	Lighting:SetAttribute("DayLength", dayLength)

	task.spawn(function()
		while true do
			-- Advance clock: 24 hours over dayLength seconds → 24/dayLength per second
			local step = 24 / dayLength * 0.5 -- update twice per second
			Lighting.ClockTime = (Lighting.ClockTime + step) % 24
			task.wait(0.5)
		end
	end)
end

return DayNight
