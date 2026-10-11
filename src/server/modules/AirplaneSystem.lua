-- AirplaneSystem.lua
-- Periodically (every AIRPLANE_INTERVAL_MIN–MAX s) an airplane flies across the
-- map at high altitude and drops food items that can be collected.
--
-- Split of responsibilities:
--   • Server: schedules flights, computes the plane's position from elapsed
--     time, and spawns the food drops (gameplay-relevant).
--   • Clients (AirplaneClient.client.lua): build and animate the airplane
--     model locally from the AirplaneFlight event — no per-frame replication.

local Workspace = game:GetService("Workspace")

local ToolUtil = require(script.Parent.ToolUtil)

local AirplaneSystem = {}

local Config = nil
local RemoteEvents = nil

local inFlight = false

-- -------------------------------------------------------------------------
-- Drop one food item below the airplane
-- -------------------------------------------------------------------------
local function dropFood(planePos)
	local ft = Config.FOOD_TYPES[math.random(1, #Config.FOOD_TYPES)]

	-- Horizontal scatter so drops feel natural
	local dropPos = planePos + Vector3.new(math.random(-6, 6), -8, math.random(-6, 6))

	local part = Instance.new("Part")
	part.Name = ft.name .. "_AirDrop"
	part.Size = ft.size
	part.BrickColor = ft.color
	part.Material = Enum.Material.SmoothPlastic
	part.Position = dropPos
	part.Anchored = false
	part.CanCollide = true
	ToolUtil.addFoodDecals(part, ft)
	part.Parent = Workspace
	ToolUtil.claimNetworkOwnership(part)

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Collect"
	pp.ObjectText = ft.name .. " (Air Drop!)"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = part

	local taken = false
	pp.Triggered:Connect(function(player)
		if taken or not part.Parent then
			return
		end
		if ToolUtil.countFood(player) >= Config.MAX_FOOD_CARRIED then
			RemoteEvents.Notify:FireClient(player, "Your hands are full!")
			return
		end
		taken = true

		-- Air-drop food gives no stealth Score (it's freely available)
		-- but can be sold / stored like any other food.
		ToolUtil.makeFoodTool(ft).Parent = player.Backpack
		part:Destroy()
	end)

	task.delay(Config.AIRPLANE_FOOD_DESPAWN, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- -------------------------------------------------------------------------
-- Single flight
-- -------------------------------------------------------------------------
local function runFlight()
	if inFlight then
		return
	end
	inFlight = true

	-- Random Z lane outside the hotel footprint (biased toward map edges)
	local zOptions = {}
	for z = -480, -200, 30 do
		table.insert(zOptions, z)
	end
	for z = 200, 480, 30 do
		table.insert(zOptions, z)
	end
	local zPos = zOptions[math.random(1, #zOptions)]

	local startPos = Vector3.new(Config.AIRPLANE_SPAWN_X, Config.AIRPLANE_ALTITUDE, zPos)
	local endPos = Vector3.new(Config.AIRPLANE_END_X, Config.AIRPLANE_ALTITUDE, zPos)
	local duration = (endPos - startPos).Magnitude / Config.AIRPLANE_SPEED

	-- Clients animate using the shared server clock
	RemoteEvents.AirplaneFlight:FireAllClients(startPos, endPos, Workspace:GetServerTimeNow(), duration)

	-- Drops happen at fixed points in time along the route (wall-clock based,
	-- so server lag does not slow the plane down)
	local startClock = os.clock()
	local nextDrop = Config.AIRPLANE_DROP_INTERVAL
	while nextDrop < duration do
		local waitFor = nextDrop - (os.clock() - startClock)
		if waitFor > 0 then
			task.wait(waitFor)
		end
		dropFood(startPos:Lerp(endPos, nextDrop / duration))
		nextDrop = nextDrop + Config.AIRPLANE_DROP_INTERVAL
	end

	local remaining = duration - (os.clock() - startClock)
	if remaining > 0 then
		task.wait(remaining)
	end
	inFlight = false
end

-- -------------------------------------------------------------------------
-- Scheduler loop
-- -------------------------------------------------------------------------
local function schedulerLoop()
	while true do
		task.wait(math.random(Config.AIRPLANE_INTERVAL_MIN, Config.AIRPLANE_INTERVAL_MAX))
		runFlight()
	end
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function AirplaneSystem.init(config, remoteEvents)
	Config = config
	RemoteEvents = remoteEvents
end

function AirplaneSystem.start()
	task.spawn(schedulerLoop)
end

return AirplaneSystem
