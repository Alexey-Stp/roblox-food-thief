-- AirplaneClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Builds and animates the fly-by airplane locally from the AirplaneFlight
-- event (startPos, endPos, serverStartTime, duration). The server only
-- schedules flights and spawns the food drops (AirplaneSystem.lua), so the
-- model costs no network traffic per frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local AirplaneFlight = eventsFolder:WaitForChild("AirplaneFlight")

-- -------------------------------------------------------------------------
-- Airplane model construction (all parts anchored; moved as one Model)
-- -------------------------------------------------------------------------
local function buildAirplane(startCFrame)
	local model = Instance.new("Model")
	model.Name = "Airplane"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(20, 5, 40)
	body.BrickColor = BrickColor.new("Medium stone grey")
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.CanCollide = false
	body.CFrame = startCFrame
	body.Parent = model
	model.PrimaryPart = body

	local sound = Instance.new("Sound")
	sound.Name = "EngineSound"
	sound.SoundId = "rbxassetid://5945658523"
	sound.Volume = 0.7
	sound.Looped = true
	sound.RollOffMaxDistance = 600
	sound.Parent = body

	local function attach(part, offset, rotation)
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = body.CFrame * CFrame.new(offset) * (rotation or CFrame.new())
		part.Parent = model
		return part
	end

	local lw = Instance.new("WedgePart")
	lw.Name = "LeftWing"
	lw.Size = Vector3.new(30, 1, 15)
	lw.BrickColor = BrickColor.new("Light grey")
	lw.Material = Enum.Material.Metal
	attach(lw, Vector3.new(-20, -1, 0), CFrame.Angles(0, math.pi, 0))

	local rw = Instance.new("WedgePart")
	rw.Name = "RightWing"
	rw.Size = Vector3.new(30, 1, 15)
	rw.BrickColor = BrickColor.new("Light grey")
	rw.Material = Enum.Material.Metal
	attach(rw, Vector3.new(20, -1, 0))

	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Size = Vector3.new(2, 8, 10)
	tail.BrickColor = BrickColor.new("Medium stone grey")
	tail.Material = Enum.Material.Metal
	attach(tail, Vector3.new(0, 4, 18))

	local le = Instance.new("Part")
	le.Name = "LeftEngine"
	le.Shape = Enum.PartType.Cylinder
	le.Size = Vector3.new(6, 3, 3)
	le.BrickColor = BrickColor.new("Dark grey")
	le.Material = Enum.Material.Metal
	attach(le, Vector3.new(-14, -3, 0))

	local re = le:Clone()
	re.Name = "RightEngine"
	attach(re, Vector3.new(14, -3, 0))

	local cockpit = Instance.new("Part")
	cockpit.Name = "Cockpit"
	cockpit.Shape = Enum.PartType.Ball
	cockpit.Size = Vector3.new(5, 4, 5)
	cockpit.BrickColor = BrickColor.new("Cyan")
	cockpit.Material = Enum.Material.Glass
	cockpit.Transparency = 0.4
	attach(cockpit, Vector3.new(0, 2, -18))

	model.Parent = Workspace
	sound:Play()
	return model
end

-- -------------------------------------------------------------------------
-- Flight animation
-- -------------------------------------------------------------------------
AirplaneFlight.OnClientEvent:Connect(function(startPos, endPos, serverStartTime, duration)
	if typeof(startPos) ~= "Vector3" or typeof(endPos) ~= "Vector3" or type(duration) ~= "number" then
		return
	end

	local model = buildAirplane(CFrame.lookAt(startPos, endPos))
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (Workspace:GetServerTimeNow() - serverStartTime) / duration
		if t >= 1 or not model.Parent then
			connection:Disconnect()
			model:Destroy()
			return
		end
		local pos = startPos:Lerp(endPos, math.max(t, 0))
		model:PivotTo(CFrame.lookAt(pos, endPos))
	end)
end)
