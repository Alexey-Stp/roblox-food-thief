-- FlyingCarpetClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Drives flight while a carpet Tool (handle attribute IsCarpet) is equipped.
-- Movement:
--   W/A/S/D  — camera-relative horizontal flight
--   Space    — ascend
--   LeftShift— descend
-- Uses LinearVelocity + AlignOrientation constraints for smooth physics.
-- The server validates flight by sampling the HumanoidRootPart itself
-- (FlyingCarpet.lua); this script sends nothing.
-- Flight tuning comes from attributes the server puts on the carpet handle.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local CarpetRevoked = eventsFolder:WaitForChild("CarpetRevoked")
local CarpetSpawned = eventsFolder:WaitForChild("CarpetSpawned")

local DEFAULT_FLIGHT_SPEED = 60
local DEFAULT_ASCENT_SPEED = 15
local DESCENT_SPEED = 8 -- gentle fall when pressing Shift

-- -------------------------------------------------------------------------
-- Active flight state
-- -------------------------------------------------------------------------
local flight = nil -- { connection, attachment, linearVel, alignOrient, character }

local function isCarpetTool(item)
	if not item:IsA("Tool") then
		return false
	end
	local h = item:FindFirstChild("Handle")
	return h ~= nil and h:GetAttribute("IsCarpet") == true
end

local function stopFlight()
	if not flight then
		return
	end
	flight.connection:Disconnect()
	flight.linearVel:Destroy()
	flight.alignOrient:Destroy()
	flight.attachment:Destroy()

	-- Zero out residual velocity as a safety net
	local hrp = flight.character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	flight = nil
end

local function startFlight(character, carpetTool)
	if flight then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local handle = carpetTool:FindFirstChild("Handle")
	if not hrp or not handle then
		return
	end

	local flightSpeed = handle:GetAttribute("FlightSpeed") or DEFAULT_FLIGHT_SPEED
	local ascentSpeed = handle:GetAttribute("AscentSpeed") or DEFAULT_ASCENT_SPEED
	local maxHeight = handle:GetAttribute("MaxHeight")

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = hrp

	-- LinearVelocity drives movement; MaxForce overrides gravity/friction
	local linearVel = Instance.new("LinearVelocity")
	linearVel.Attachment0 = attachment
	linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.MaxForce = 1e6
	linearVel.VectorVelocity = Vector3.zero
	linearVel.Parent = hrp

	-- AlignOrientation keeps the character upright (no tumbling during flight)
	local alignOrient = Instance.new("AlignOrientation")
	alignOrient.Attachment0 = attachment
	alignOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrient.MaxTorque = 1e6
	alignOrient.Responsiveness = 10
	alignOrient.CFrame = CFrame.new()
	alignOrient.Parent = hrp

	local connection = RunService.Heartbeat:Connect(function()
		local cam = workspace.CurrentCamera
		local forward = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
		if forward.Magnitude > 0 then
			forward = forward.Unit
		end
		if right.Magnitude > 0 then
			right = right.Unit
		end

		local moveDir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveDir = moveDir + forward
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveDir = moveDir - forward
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveDir = moveDir - right
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveDir = moveDir + right
		end
		if moveDir.Magnitude > 0 then
			moveDir = moveDir.Unit
		end

		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			-- Stop climbing at the server's height cap instead of being rubber-banded
			if not maxHeight or hrp.Position.Y < maxHeight then
				vertical = ascentSpeed
			end
		elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			vertical = -DESCENT_SPEED
		end

		linearVel.VectorVelocity = moveDir * flightSpeed + Vector3.new(0, vertical, 0)
	end)

	flight = {
		connection = connection,
		attachment = attachment,
		linearVel = linearVel,
		alignOrient = alignOrient,
		character = character,
	}
end

-- -------------------------------------------------------------------------
-- A Tool parented to the character is equipped; removed means unequipped.
-- One ChildAdded/ChildRemoved pair per character — no per-equip connections.
-- -------------------------------------------------------------------------
local function onCharacterAdded(character)
	stopFlight()

	for _, child in ipairs(character:GetChildren()) do
		if isCarpetTool(child) then
			startFlight(character, child)
		end
	end

	character.ChildAdded:Connect(function(child)
		if isCarpetTool(child) then
			startFlight(character, child)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if flight and flight.character == character and isCarpetTool(child) then
			stopFlight()
		end
	end)
end

-- -------------------------------------------------------------------------
-- Banner helper
-- -------------------------------------------------------------------------
local function showBanner(name, text, textColor, bgColor, lifetime)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = name
	screenGui.ResetOnSpawn = false
	screenGui.Parent = localPlayer.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 420, 0, 60)
	frame.Position = UDim2.new(0.5, -210, 0.15, 0)
	frame.BackgroundColor3 = bgColor
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = text
	lbl.TextColor3 = textColor
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.SourceSansBold
	lbl.Parent = frame

	Debris:AddItem(screenGui, lifetime)
end

-- Server tells us the night carpet was revoked (dawn arrived)
CarpetRevoked.OnClientEvent:Connect(function()
	stopFlight()
	showBanner(
		"CarpetRevokedGui",
		"The flying carpet vanished at dawn!",
		Color3.fromRGB(255, 180, 50),
		Color3.fromRGB(40, 20, 0),
		5
	)
end)

-- Server tells all clients the night carpet spawned
CarpetSpawned.OnClientEvent:Connect(function()
	showBanner(
		"CarpetSpawnedGui",
		"A Flying Carpet appeared near the restaurant!",
		Color3.fromRGB(180, 130, 255),
		Color3.fromRGB(20, 0, 60),
		8
	)
end)

-- -------------------------------------------------------------------------
-- Initialise for current and future characters
-- -------------------------------------------------------------------------
localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
