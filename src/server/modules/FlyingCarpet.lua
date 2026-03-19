-- FlyingCarpet.lua
-- Spawns a collectible flying carpet at night; removes it at dawn.
-- When a player picks it up they receive a "FlyingCarpet" Tool.
-- While equipped, FlyingCarpetClient.client.lua drives the flight via
-- AssemblyLinearVelocity; this module validates positions server-side.
--
-- Night detection: polls Lighting.ClockTime every second.
-- Night = ClockTime >= 20  OR  ClockTime < 6

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local FlyingCarpet = {}

local Config = nil
local RemoteEvents = nil

-- Module state
local carpetPart = nil -- world Part while carpet is on the ground
local carpetOwner = nil -- Player who currently holds the carpet Tool

-- Per-owner server-side position validation
-- carpetValidation[userId] = { lastPos, lastTime }
local carpetValidation = {}

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
local function isNight()
	local t = Lighting.ClockTime
	return t >= 20 or t < 6
end

local function isProtectedTool(item)
	if not item or not item:IsA("Tool") then
		return true
	end
	local h = item:FindFirstChild("Handle")
	return h and h:GetAttribute("IsCarpet") == true
end

-- -------------------------------------------------------------------------
-- Carpet world Part construction
-- -------------------------------------------------------------------------
local function buildCarpetPart()
	local pos = Config.CARPET_SPAWN_POS

	-- Main flat rug
	local part = Instance.new("Part")
	part.Name = "FlyingCarpet_World"
	part.Size = Vector3.new(6, 0.3, 4)
	part.BrickColor = BrickColor.new("Bright red")
	part.Material = Enum.Material.Fabric
	part.Position = pos
	part.Anchored = true
	part.CFrame = CFrame.new(pos)
	part.Parent = workspace

	-- Decorative neon border strips
	local borderColor = BrickColor.new("Bright yellow")
	local borders = {
		{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, 1.85) },
		{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, -1.85) },
		{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(2.85, 0, 0) },
		{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(-2.85, 0, 0) },
	}
	for _, b in ipairs(borders) do
		local strip = Instance.new("Part")
		strip.Size = b.size
		strip.BrickColor = borderColor
		strip.Material = Enum.Material.Neon
		strip.Anchored = true
		strip.CanCollide = false
		strip.CFrame = part.CFrame * CFrame.new(b.offset)
		strip.Parent = workspace
		-- Weld to main part so they move together if CFrame changes
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, strip
		w.Parent = part
	end

	-- PointLight so it glows at night
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 15
	light.Color = Color3.fromRGB(255, 200, 80)
	light.Parent = part

	-- ProximityPrompt to pick up
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Grab Carpet"
	pp.ObjectText = "Flying Carpet"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = part

	pp.Triggered:Connect(function(player)
		-- Only one player can own the carpet at a time
		if carpetOwner then
			return
		end
		pp.Enabled = false
		giveCarpetTool(player)
		if carpetPart and carpetPart.Parent then
			carpetPart:Destroy()
		end
		carpetPart = nil
	end)

	return part
end

-- -------------------------------------------------------------------------
-- Flying carpet Tool given to the player on pickup
-- -------------------------------------------------------------------------
function giveCarpetTool(player)
	carpetOwner = player

	local tool = Instance.new("Tool")
	tool.Name = "FlyingCarpet"
	tool.RequiresHandle = true
	tool.ToolTip = "A magical flying carpet!"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(6, 0.3, 4)
	handle.BrickColor = BrickColor.new("Bright red")
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = false
	-- Tag so EnemyAI / guards do not confiscate it
	handle:SetAttribute("IsCarpet", true)
	handle.Parent = tool

	-- Neon border strips on handle too
	for _, b in ipairs({
		{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, 1.85) },
		{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, -1.85) },
		{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(2.85, 0, 0) },
		{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(-2.85, 0, 0) },
	}) do
		local strip = Instance.new("Part")
		strip.Size = b.size
		strip.BrickColor = BrickColor.new("Bright yellow")
		strip.Material = Enum.Material.Neon
		strip.CanCollide = false
		strip.CFrame = CFrame.new(b.offset)
		strip.Parent = tool
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = handle, strip
		w.Parent = handle
	end

	tool.Parent = player.Backpack

	-- Seed validation state
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	carpetValidation[player.UserId] = {
		lastPos = hrp and hrp.Position or Vector3.zero,
		lastTime = tick(),
	}
end

-- -------------------------------------------------------------------------
-- Strip carpet from a player (called at dawn)
-- -------------------------------------------------------------------------
local function stripCarpetFromPlayer(player)
	local char = player.Character
	if char then
		local eq = char:FindFirstChildOfClass("Tool")
		if eq and eq.Name == "FlyingCarpet" then
			eq:Destroy()
		end
	end
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if item.Name == "FlyingCarpet" then
			item:Destroy()
		end
	end
	carpetValidation[player.UserId] = nil
end

-- -------------------------------------------------------------------------
-- Despawn carpet (called at dawn)
-- -------------------------------------------------------------------------
local function despawnCarpet()
	if carpetOwner then
		stripCarpetFromPlayer(carpetOwner)
		RemoteEvents.CarpetRevoked:FireClient(carpetOwner)
		carpetOwner = nil
	end
	if carpetPart and carpetPart.Parent then
		carpetPart:Destroy()
		carpetPart = nil
	end
end

-- -------------------------------------------------------------------------
-- Server position validation handler
-- -------------------------------------------------------------------------
local function onPositionUpdate(player, newPos)
	if player ~= carpetOwner then
		return
	end
	if typeof(newPos) ~= "Vector3" then
		return
	end

	local data = carpetValidation[player.UserId]
	if not data then
		return
	end

	local now = tick()
	local dt = now - data.lastTime
	if dt < 0.05 then
		return
	end -- rate-limit: ignore updates faster than 20 Hz

	-- Speed validation
	local dist = (newPos - data.lastPos).Magnitude
	if dt > 0 and (dist / dt) > Config.CARPET_MAX_SPEED_VALIDATE then
		-- Rubber-band back to last known valid position
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(data.lastPos)
			end
		end
		return
	end

	-- Height cap
	if newPos.Y > Config.CARPET_MAX_HEIGHT + 5 then
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(newPos.X, Config.CARPET_MAX_HEIGHT, newPos.Z)
			end
		end
		return
	end

	data.lastPos = newPos
	data.lastTime = now
end

-- -------------------------------------------------------------------------
-- Night watcher loop
-- -------------------------------------------------------------------------
local function startNightWatcher()
	local wasNight = isNight()

	task.spawn(function()
		while true do
			task.wait(1)
			local nowNight = isNight()

			if nowNight and not wasNight then
				-- Became night: spawn carpet
				if not carpetPart and not carpetOwner then
					carpetPart = buildCarpetPart()
					-- Notify all clients so they can show a hint
					RemoteEvents.CarpetSpawned:FireAllClients()
				end
			elseif not nowNight and wasNight then
				-- Became day: remove carpet
				despawnCarpet()
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

	remoteEvents.CarpetPositionUpdate.OnServerEvent:Connect(onPositionUpdate)

	Players.PlayerRemoving:Connect(function(player)
		if player == carpetOwner then
			carpetOwner = nil
			carpetValidation[player.UserId] = nil
			-- Respawn carpet so other players can still get it
			if isNight() and not carpetPart then
				task.delay(2, function()
					if isNight() and not carpetOwner and not carpetPart then
						carpetPart = buildCarpetPart()
					end
				end)
			end
		end
	end)
end

function FlyingCarpet.start()
	startNightWatcher()
end

return FlyingCarpet
