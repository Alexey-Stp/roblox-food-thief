-- FlyingCarpet.lua
-- Single authority for flying carpets.
--
-- Two kinds of carpet, both created ONLY through FlyingCarpet.giveCarpet():
--   • Night carpet — one world pickup spawns at night near the restaurant and
--     is revoked at dawn. Ownership is tied to the Tool's lifetime: if the
--     tool is destroyed (owner died, left, …) the world carpet respawns.
--   • Bonus carpet — awarded by chests (ChestSystem, SkyHotel); kept by day.
-- A player can hold at most one carpet of either kind.
--
-- Flight validation is server-authoritative: the server samples every
-- carpet rider's HumanoidRootPart position on a fixed interval and
-- rubber-bands horizontal speed above CARPET_MAX_SPEED_VALIDATE or climbs
-- above CARPET_MAX_HEIGHT. Clients report nothing.
-- Server teleports stamp the Player attribute "LastServerTeleport"
-- (see ToolUtil.teleport) so they reset the baseline instead of tripping it.
--
-- Night detection: polls Lighting.ClockTime every second.
-- Night = ClockTime >= 20  OR  ClockTime < 6

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local ToolUtil = require(script.Parent.ToolUtil)

local FlyingCarpet = {}

local Config = nil
local RemoteEvents = nil

-- Module state
local carpetPart = nil -- world Part while the night carpet is on the ground
local nightCarpetTool = nil -- the night carpet Tool while someone holds it
local nightCarpetOwner = nil

-- Per-player validation samples: [Player] = { pos, time, teleportStamp }
local samples = {}

-- Forward declaration (buildCarpetPart ↔ tool-destroy respawn)
local spawnWorldCarpet

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
local function isNight()
	local t = Lighting.ClockTime
	return t >= 20 or t < 6
end

local function addBorderStrips(parentPart, container, anchoredStrips)
	local borders = {
		{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, 1.85) },
		{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, -1.85) },
		{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(2.85, 0, 0) },
		{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(-2.85, 0, 0) },
	}
	for _, b in ipairs(borders) do
		local strip = Instance.new("Part")
		strip.Name = "CarpetBorder"
		strip.Size = b.size
		strip.BrickColor = BrickColor.new("Bright yellow")
		strip.Material = Enum.Material.Neon
		strip.Anchored = anchoredStrips
		strip.CanCollide = false
		strip.Massless = true
		strip.CFrame = parentPart.CFrame * CFrame.new(b.offset)
		strip.Parent = container
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = parentPart, strip
		w.Parent = parentPart
	end
end

local function buildCarpetTool(isNightCarpet)
	local tool = Instance.new("Tool")
	tool.Name = "FlyingCarpet"
	tool.RequiresHandle = true
	tool.ToolTip = isNightCarpet and "A magical flying carpet! Vanishes at dawn." or "A magical flying carpet!"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(6, 0.3, 4)
	handle.BrickColor = BrickColor.new("Bright red")
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = false
	-- Tags: protected from confiscation; flight tuning read by FlyingCarpetClient
	handle:SetAttribute("IsCarpet", true)
	handle:SetAttribute("NightCarpet", isNightCarpet)
	handle:SetAttribute("FlightSpeed", Config.CARPET_FLIGHT_SPEED)
	handle:SetAttribute("AscentSpeed", Config.CARPET_ASCENT_SPEED)
	handle:SetAttribute("MaxHeight", Config.CARPET_MAX_HEIGHT)
	handle.Parent = tool

	addBorderStrips(handle, tool, false)
	return tool
end

local function releaseNightCarpet()
	nightCarpetTool = nil
	nightCarpetOwner = nil
	-- Owner lost the carpet (death, leave, …) — let someone else have it tonight
	if isNight() and not carpetPart then
		task.delay(2, function()
			if isNight() and not carpetPart and not nightCarpetTool then
				spawnWorldCarpet()
			end
		end)
	end
end

-- -------------------------------------------------------------------------
-- Public: grant a carpet. Returns true when a carpet was given.
-- -------------------------------------------------------------------------
function FlyingCarpet.giveCarpet(player, isNightCarpet)
	if ToolUtil.hasCarpet(player) then
		return false
	end
	if isNightCarpet and nightCarpetTool then
		return false
	end

	local tool = buildCarpetTool(isNightCarpet == true)
	if isNightCarpet then
		nightCarpetTool = tool
		nightCarpetOwner = player
		tool.Destroying:Connect(function()
			if nightCarpetTool == tool then
				releaseNightCarpet()
			end
		end)
	end
	tool.Parent = player.Backpack
	return true
end

-- -------------------------------------------------------------------------
-- Night world carpet
-- -------------------------------------------------------------------------
spawnWorldCarpet = function()
	local pos = Config.CARPET_SPAWN_POS

	local part = Instance.new("Part")
	part.Name = "FlyingCarpet_World"
	part.Size = Vector3.new(6, 0.3, 4)
	part.BrickColor = BrickColor.new("Bright red")
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CFrame = CFrame.new(pos)
	part.Parent = workspace
	addBorderStrips(part, part, true)

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 15
	light.Color = Color3.fromRGB(255, 200, 80)
	light.Parent = part

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Grab Carpet"
	pp.ObjectText = "Flying Carpet"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = part

	pp.Triggered:Connect(function(player)
		if carpetPart ~= part then
			return
		end
		if not FlyingCarpet.giveCarpet(player, true) then
			RemoteEvents.Notify:FireClient(player, "You already have a carpet")
			return
		end
		carpetPart = nil
		part:Destroy()
	end)

	carpetPart = part
	RemoteEvents.CarpetSpawned:FireAllClients()
end

local function despawnNightCarpet()
	if nightCarpetTool then
		local owner = nightCarpetOwner
		local tool = nightCarpetTool
		nightCarpetTool = nil -- prevent the Destroying handler from respawning it
		nightCarpetOwner = nil
		tool:Destroy()
		if owner and owner.Parent then
			RemoteEvents.CarpetRevoked:FireClient(owner)
		end
	end
	if carpetPart then
		carpetPart:Destroy()
		carpetPart = nil
	end
end

-- -------------------------------------------------------------------------
-- Server-side flight validation
-- -------------------------------------------------------------------------
local function ridingCarpet(char)
	for _, item in ipairs(char:GetChildren()) do
		if ToolUtil.isCarpet(item) then
			return true
		end
	end
	return false
end

local function validatePlayer(player, now)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not ridingCarpet(char) then
		samples[player] = nil
		return
	end

	local pos = hrp.Position
	local teleportStamp = player:GetAttribute("LastServerTeleport")
	local sample = samples[player]

	-- New rider or server teleport since the last sample: reset the baseline
	if not sample or sample.teleportStamp ~= teleportStamp then
		samples[player] = { pos = pos, time = now, teleportStamp = teleportStamp }
		return
	end

	local dt = now - sample.time
	if dt <= 0 then
		return
	end

	local horizontal = Vector3.new(pos.X - sample.pos.X, 0, pos.Z - sample.pos.Z).Magnitude
	if horizontal / dt > Config.CARPET_MAX_SPEED_VALIDATE then
		-- Rubber-band to the last valid position
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.CFrame = CFrame.new(sample.pos)
		sample.time = now
		return
	end

	-- Height cap only applies to climbing (players may ride at the Sky Hotel)
	local cap = Config.CARPET_MAX_HEIGHT + 5
	if pos.Y > cap and pos.Y > sample.pos.Y + 1 then
		local clampedY = math.max(sample.pos.Y, Config.CARPET_MAX_HEIGHT)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.CFrame = CFrame.new(pos.X, clampedY, pos.Z)
		pos = Vector3.new(pos.X, clampedY, pos.Z)
	end

	sample.pos = pos
	sample.time = now
end

local function startValidator()
	task.spawn(function()
		while true do
			task.wait(Config.CARPET_VALIDATE_INTERVAL)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				validatePlayer(player, now)
			end
		end
	end)
end

-- -------------------------------------------------------------------------
-- Night watcher loop
-- -------------------------------------------------------------------------
local function startNightWatcher()
	local wasNight = isNight()
	if wasNight then
		spawnWorldCarpet()
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local nowNight = isNight()
			if nowNight and not wasNight then
				if not carpetPart and not nightCarpetTool then
					spawnWorldCarpet()
				end
			elseif not nowNight and wasNight then
				despawnNightCarpet()
			end
			wasNight = nowNight
		end
	end)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function FlyingCarpet.init(remoteEvents, config)
	RemoteEvents = remoteEvents
	Config = config

	Players.PlayerRemoving:Connect(function(player)
		samples[player] = nil
		-- The owner's Backpack is destroyed with the player, which fires the
		-- tool's Destroying handler; this is a fallback in case it was not.
		if player == nightCarpetOwner then
			releaseNightCarpet()
		end
	end)
end

function FlyingCarpet.start()
	startNightWatcher()
	startValidator()
end

return FlyingCarpet
