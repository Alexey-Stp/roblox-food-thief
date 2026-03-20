-- FlyingCarpetClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Drives flight when the player has the FlyingCarpet Tool equipped.
-- Movement:
--   W/A/S/D  — camera-relative horizontal flight
--   Space    — ascend
--   LeftShift— descend
-- Uses LinearVelocity + AlignOrientation constraints for smooth physics.
-- Periodically sends the local HumanoidRootPart position to the server
-- (CarpetPositionUpdate) so it can validate speed and height.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Wait for RemoteEvents to be created by the server
local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local CarpetPositionUpdate = eventsFolder:WaitForChild("CarpetPositionUpdate")
local CarpetRevoked = eventsFolder:WaitForChild("CarpetRevoked")
local CarpetSpawned = eventsFolder:WaitForChild("CarpetSpawned")

local FLIGHT_SPEED  = 60 -- horizontal studs/sec (matches Config.CARPET_FLIGHT_SPEED)
local ASCENT_SPEED  = 15 -- vertical studs/sec   (matches Config.CARPET_ASCENT_SPEED)
local DESCENT_SPEED = 8  -- gentle fall when pressing Shift

-- -------------------------------------------------------------------------
-- Active flight state
-- -------------------------------------------------------------------------
local flightConnection    = nil
local flightAttachment    = nil
local flightLinearVel     = nil
local flightAlignOrient   = nil
local reportTimer         = 0
local REPORT_INTERVAL     = 0.1 -- seconds between server position reports

-- -------------------------------------------------------------------------
-- Start / stop flight using constraint-based physics
-- -------------------------------------------------------------------------
local function startFlight(character)
	if flightConnection then
		return
	end -- already flying

	local hrp      = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.PlatformStand = false

	-- Attachment anchored to HRP (required by both constraints)
	flightAttachment = Instance.new("Attachment")
	flightAttachment.Name = "FlightAttachment"
	flightAttachment.Parent = hrp

	-- LinearVelocity drives movement; MaxForce overrides gravity/friction
	flightLinearVel = Instance.new("LinearVelocity")
	flightLinearVel.Attachment0 = flightAttachment
	flightLinearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	flightLinearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	flightLinearVel.MaxForce = 1e6
	flightLinearVel.VectorVelocity = Vector3.zero
	flightLinearVel.Parent = hrp

	-- AlignOrientation keeps the character upright (no tumbling during flight)
	flightAlignOrient = Instance.new("AlignOrientation")
	flightAlignOrient.Attachment0 = flightAttachment
	flightAlignOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	flightAlignOrient.MaxTorque = 1e6
	flightAlignOrient.Responsiveness = 10
	flightAlignOrient.CFrame = CFrame.new() -- world-up aligned
	flightAlignOrient.Parent = hrp

	flightConnection = RunService.Heartbeat:Connect(function(dt)
		-- Stop if carpet was removed
		if not character:FindFirstChild("FlyingCarpet") then
			stopFlight(character) -- defined below; forward reference is fine in Lua
			return
		end

		-- Camera-relative horizontal direction
		local cam     = workspace.CurrentCamera
		local forward = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		local right   = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)

		if forward.Magnitude > 0 then forward = forward.Unit end
		if right.Magnitude   > 0 then right   = right.Unit   end

		local moveDir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + forward end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - forward end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - right   end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + right   end
		if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end

		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			vertical = ASCENT_SPEED
		elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			vertical = -DESCENT_SPEED
		end

		flightLinearVel.VectorVelocity = moveDir * FLIGHT_SPEED + Vector3.new(0, vertical, 0)

		-- Periodic position report to server for validation
		reportTimer = reportTimer + dt
		if reportTimer >= REPORT_INTERVAL then
			reportTimer = 0
			CarpetPositionUpdate:FireServer(hrp.Position)
		end
	end)
end

function stopFlight(character)
	if flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end
	if flightLinearVel then
		flightLinearVel:Destroy()
		flightLinearVel = nil
	end
	if flightAlignOrient then
		flightAlignOrient:Destroy()
		flightAlignOrient = nil
	end
	if flightAttachment then
		flightAttachment:Destroy()
		flightAttachment = nil
	end
	-- Zero out residual velocity as a safety net
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
end

-- -------------------------------------------------------------------------
-- Watch for the FlyingCarpet Tool in the character
-- -------------------------------------------------------------------------
local function onCharacterAdded(character)
	-- Check for carpet already equipped (unlikely on spawn, but safe)
	local existing = character:FindFirstChild("FlyingCarpet")
	if existing and existing:IsA("Tool") then
		existing.Equipped:Connect(function()
			startFlight(character)
		end)
		existing.Unequipped:Connect(function()
			stopFlight(character)
		end)
	end

	-- Watch for carpet being added later
	character.ChildAdded:Connect(function(child)
		if child.Name == "FlyingCarpet" and child:IsA("Tool") then
			child.Equipped:Connect(function()
				startFlight(character)
			end)
			child.Unequipped:Connect(function()
				stopFlight(character)
			end)
		end
	end)
end

-- -------------------------------------------------------------------------
-- Server tells us the carpet was revoked (dawn arrived)
-- -------------------------------------------------------------------------
CarpetRevoked.OnClientEvent:Connect(function()
	stopFlight(localPlayer.Character)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CarpetRevokedGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = localPlayer.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 400, 0, 60)
	frame.Position = UDim2.new(0.5, -200, 0.15, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 20, 0)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = "The flying carpet vanished at dawn!"
	lbl.TextColor3 = Color3.fromRGB(255, 180, 50)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.SourceSansBold
	lbl.Parent = frame

	game:GetService("Debris"):AddItem(screenGui, 5)
end)

-- -------------------------------------------------------------------------
-- Server tells all clients the carpet spawned
-- -------------------------------------------------------------------------
CarpetSpawned.OnClientEvent:Connect(function()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CarpetSpawnedGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = localPlayer.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 420, 0, 60)
	frame.Position = UDim2.new(0.5, -210, 0.15, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 0, 60)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = "A Flying Carpet appeared near the restaurant!"
	lbl.TextColor3 = Color3.fromRGB(180, 130, 255)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.SourceSansBold
	lbl.Parent = frame

	game:GetService("Debris"):AddItem(screenGui, 8)
end)

-- -------------------------------------------------------------------------
-- Initialise for current and future characters
-- -------------------------------------------------------------------------
localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
