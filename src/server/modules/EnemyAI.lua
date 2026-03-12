-- EnemyAI.lua
-- Three creature types patrol and chase food-carrying players.
-- Floor 1: Wolves  |  Floor 2: Bears  |  Floor 3: Occultists

local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local EnemyAI = {}

local RemoteEvents = nil

function EnemyAI.init(remoteEvents)
	RemoteEvents = remoteEvents
end

-- -------------------------------------------------------------------------
-- Shared weld helper
-- -------------------------------------------------------------------------
local function weld(p0, p1)
	local w = Instance.new("WeldConstraint")
	w.Part0  = p0
	w.Part1  = p1
	w.Parent = p0
end

-- -------------------------------------------------------------------------
-- Wolf (Floor 1) — low quadruped, grey-brown, red eyes
-- -------------------------------------------------------------------------
local function buildWolf(name, startPos)
	local model = Instance.new("Model")
	model.Name = name

	local torso = Instance.new("Part")
	torso.Name      = "Torso"
	torso.Size      = Vector3.new(4, 1.5, 6)
	torso.Position  = startPos + Vector3.new(0, -0.5, 0)
	torso.BrickColor = BrickColor.new("Dark orange")
	torso.Material  = Enum.Material.Fabric
	torso.Parent    = model

	local head = Instance.new("Part")
	head.Name      = "Head"
	head.Size      = Vector3.new(2.5, 2, 3)
	head.Position  = startPos + Vector3.new(0, 0.8, -3.5)
	head.BrickColor = BrickColor.new("Dark orange")
	head.Material  = Enum.Material.SmoothPlastic
	head.Parent    = model

	local function makeEye(offset)
		local eye = Instance.new("Part")
		eye.Size      = Vector3.new(0.4, 0.5, 0.1)
		eye.Position  = head.Position + offset
		eye.BrickColor = BrickColor.new("Really red")
		eye.Material  = Enum.Material.Neon
		eye.Anchored  = false
		eye.Parent    = model
		return eye
	end
	local le = makeEye(Vector3.new(-0.5, 0.2, -1.5))
	le.Name = "LeftEye"
	local re = makeEye(Vector3.new(0.5, 0.2, -1.5))
	re.Name = "RightEye"

	-- Tail (WedgePart angled up)
	local tail = Instance.new("WedgePart")
	tail.Name      = "Tail"
	tail.Size      = Vector3.new(0.6, 0.6, 4)
	tail.CFrame    = CFrame.new(startPos + Vector3.new(0, 0.5, 3.5)) * CFrame.Angles(math.rad(-30), 0, 0)
	tail.BrickColor = BrickColor.new("Dark orange")
	tail.Material  = Enum.Material.Fabric
	tail.Parent    = model

	-- Four legs
	local legOffsets = {
		Vector3.new(-1.5, -1.5, -1.5), Vector3.new(1.5, -1.5, -1.5),
		Vector3.new(-1.5, -1.5,  1.5), Vector3.new(1.5, -1.5,  1.5),
	}
	for i, off in ipairs(legOffsets) do
		local leg = Instance.new("Part")
		leg.Name      = "Leg" .. i
		leg.Size      = Vector3.new(0.8, 2, 0.8)
		leg.Position  = startPos + off
		leg.BrickColor = BrickColor.new("Brown")
		leg.Material  = Enum.Material.Fabric
		leg.Parent    = model
		weld(torso, leg)
	end

	local eyeLight = Instance.new("PointLight")
	eyeLight.Name       = "EyeGlow"
	eyeLight.Color      = Color3.new(1, 0, 0)
	eyeLight.Brightness = 2
	eyeLight.Range      = 8
	eyeLight.Parent     = head

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	weld(torso, head)
	weld(head,  le)
	weld(head,  re)
	weld(torso, tail)

	model.PrimaryPart = torso
	model.Parent      = workspace

	return model, torso, head, humanoid, eyeLight
end

-- -------------------------------------------------------------------------
-- Bear (Floor 2) — large upright, reddish-brown, amber eyes
-- -------------------------------------------------------------------------
local function buildBear(name, startPos)
	local model = Instance.new("Model")
	model.Name = name

	local torso = Instance.new("Part")
	torso.Name      = "Torso"
	torso.Size      = Vector3.new(5, 5, 4)
	torso.Position  = startPos
	torso.BrickColor = BrickColor.new("Reddish brown")
	torso.Material  = Enum.Material.SmoothPlastic
	torso.Parent    = model

	local head = Instance.new("Part")
	head.Name      = "Head"
	head.Shape     = Enum.PartType.Ball
	head.Size      = Vector3.new(5, 5, 5)
	head.Position  = startPos + Vector3.new(0, 5, 0)
	head.BrickColor = BrickColor.new("Reddish brown")
	head.Material  = Enum.Material.SmoothPlastic
	head.Parent    = model

	-- Ears
	local function makeEar(offset)
		local ear = Instance.new("Part")
		ear.Shape     = Enum.PartType.Cylinder
		ear.Size      = Vector3.new(1.5, 2, 1.5)
		ear.Position  = head.Position + offset
		ear.BrickColor = BrickColor.new("Reddish brown")
		ear.Material  = Enum.Material.SmoothPlastic
		ear.Parent    = model
		return ear
	end
	local le = makeEar(Vector3.new(-1.5, 2.5, 0))
	le.Name = "LeftEar"
	local re = makeEar(Vector3.new(1.5, 2.5, 0))
	re.Name = "RightEar"

	local function makeEye(offset)
		local eye = Instance.new("Part")
		eye.Size      = Vector3.new(0.6, 0.8, 0.1)
		eye.Position  = head.Position + offset
		eye.BrickColor = BrickColor.new("Bright orange")
		eye.Material  = Enum.Material.Neon
		eye.Anchored  = false
		eye.Parent    = model
		return eye
	end
	local le2 = makeEye(Vector3.new(-1, 0.3, -2.5))
	le2.Name = "LeftEye"
	local re2 = makeEye(Vector3.new(1, 0.3, -2.5))
	re2.Name = "RightEye"

	-- Arms and legs
	local function makeLimb(lname, size, offset)
		local limb = Instance.new("Part")
		limb.Name      = lname
		limb.Size      = size
		limb.Position  = startPos + offset
		limb.BrickColor = BrickColor.new("Reddish brown")
		limb.Material  = Enum.Material.SmoothPlastic
		limb.Parent    = model
		return limb
	end
	local la = makeLimb("LeftArm",  Vector3.new(2.5, 5, 2.5), Vector3.new(-3.5, 0, 0))
	local ra = makeLimb("RightArm", Vector3.new(2.5, 5, 2.5), Vector3.new(3.5, 0, 0))
	local ll = makeLimb("LeftLeg",  Vector3.new(2.5, 6, 2.5), Vector3.new(-1.5, -5, 0))
	local rl = makeLimb("RightLeg", Vector3.new(2.5, 6, 2.5), Vector3.new(1.5, -5, 0))

	local eyeLight = Instance.new("PointLight")
	eyeLight.Name       = "EyeGlow"
	eyeLight.Color      = Color3.new(1, 0.5, 0)
	eyeLight.Brightness = 3
	eyeLight.Range      = 15
	eyeLight.Parent     = head

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	weld(torso, head)
	weld(head,  le)
	weld(head,  re)
	weld(head,  le2)
	weld(head,  re2)
	weld(torso, la)
	weld(torso, ra)
	weld(torso, ll)
	weld(torso, rl)

	model.PrimaryPart = torso
	model.Parent      = workspace

	return model, torso, head, humanoid, eyeLight
end

-- -------------------------------------------------------------------------
-- Occultist (Floor 3) — robed humanoid, dark purple, glowing eyes, staff
-- -------------------------------------------------------------------------
local function buildOccultist(name, startPos)
	local model = Instance.new("Model")
	model.Name = name

	local torso = Instance.new("Part")
	torso.Name      = "Torso"
	torso.Size      = Vector3.new(2.5, 4, 1.5)
	torso.Position  = startPos
	torso.BrickColor = BrickColor.new("Eggplant")
	torso.Material  = Enum.Material.Fabric
	torso.Parent    = model

	-- Robe (larger Part below torso, semi-transparent)
	local robe = Instance.new("Part")
	robe.Name         = "Robe"
	robe.Size         = Vector3.new(4, 6, 3)
	robe.Position     = startPos + Vector3.new(0, -4, 0)
	robe.BrickColor   = BrickColor.new("Dark indigo")
	robe.Material     = Enum.Material.Fabric
	robe.Transparency = 0.3
	robe.Parent       = model

	local head = Instance.new("Part")
	head.Name      = "Head"
	head.Size      = Vector3.new(2.5, 2.5, 2.5)
	head.Position  = startPos + Vector3.new(0, 3.5, 0)
	head.BrickColor = BrickColor.new("Eggplant")
	head.Material  = Enum.Material.Neon
	head.Parent    = model

	-- Hood
	local hood = Instance.new("Part")
	hood.Name      = "Hood"
	hood.Size      = Vector3.new(3, 2, 3)
	hood.Position  = head.Position + Vector3.new(0, 1, 0)
	hood.BrickColor = BrickColor.new("Dark indigo")
	hood.Material  = Enum.Material.Fabric
	hood.Parent    = model

	local function makeEye(offset)
		local eye = Instance.new("Part")
		eye.Size      = Vector3.new(0.5, 0.6, 0.1)
		eye.Position  = head.Position + offset
		eye.BrickColor = BrickColor.new("Bright yellow")
		eye.Material  = Enum.Material.Neon
		eye.Anchored  = false
		eye.Parent    = model
		return eye
	end
	local le = makeEye(Vector3.new(-0.7, 0.2, -1.3))
	le.Name = "LeftEye"
	local re = makeEye(Vector3.new(0.7, 0.2, -1.3))
	re.Name = "RightEye"

	local leftArm = Instance.new("Part")
	leftArm.Name      = "LeftArm"
	leftArm.Size      = Vector3.new(1, 4, 1)
	leftArm.Position  = startPos + Vector3.new(-2, 0.5, 0)
	leftArm.BrickColor = BrickColor.new("Eggplant")
	leftArm.Material  = Enum.Material.Fabric
	leftArm.Parent    = model

	local rightArm = Instance.new("Part")
	rightArm.Name      = "RightArm"
	rightArm.Size      = Vector3.new(1, 4, 1)
	rightArm.Position  = startPos + Vector3.new(2, 0.5, 0)
	rightArm.BrickColor = BrickColor.new("Eggplant")
	rightArm.Material  = Enum.Material.Fabric
	rightArm.Parent    = model

	-- Staff attached to right arm
	local staff = Instance.new("Part")
	staff.Name      = "Staff"
	staff.Size      = Vector3.new(0.5, 8, 0.5)
	staff.Position  = startPos + Vector3.new(2.5, 2, 0)
	staff.BrickColor = BrickColor.new("Black")
	staff.Material  = Enum.Material.SmoothPlastic
	staff.Parent    = model

	-- Staff crystal tip
	local crystal = Instance.new("Part")
	crystal.Name      = "StaffCrystal"
	crystal.Shape     = Enum.PartType.Ball
	crystal.Size      = Vector3.new(1.5, 1.5, 1.5)
	crystal.Position  = startPos + Vector3.new(2.5, 6.5, 0)
	crystal.BrickColor = BrickColor.new("Bright violet")
	crystal.Material  = Enum.Material.Neon
	crystal.Parent    = model

	local eyeLight = Instance.new("PointLight")
	eyeLight.Name       = "EyeGlow"
	eyeLight.Color      = Color3.new(0.6, 0, 1)
	eyeLight.Brightness = 4
	eyeLight.Range      = 22
	eyeLight.Parent     = head

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	weld(torso, head)
	weld(torso, robe)
	weld(head,  hood)
	weld(head,  le)
	weld(head,  re)
	weld(torso, leftArm)
	weld(torso, rightArm)
	weld(rightArm, staff)
	weld(staff,    crystal)

	model.PrimaryPart = torso
	model.Parent      = workspace

	return model, torso, head, humanoid, eyeLight
end

-- -------------------------------------------------------------------------
-- Spawn: picks builder by floor level
-- -------------------------------------------------------------------------
local BUILDERS = { buildWolf, buildBear, buildOccultist }

function EnemyAI.spawn(creatureName, startPosition, Config, level)
	local speeds = Config.LEVEL_SPEEDS[level] or Config.LEVEL_SPEEDS[1]
	local CHASE  = speeds.chase
	local WANDER = speeds.wander
	local floorY = Config.HOTEL_CENTER.Y + (level - 1) * Config.FLOOR_HEIGHT + 1

	local build = BUILDERS[level] or BUILDERS[1]
	local waiter, torso, _, humanoid, eyeLight = build(creatureName, startPosition)

	local lastHit = {}
	local alive   = true

	waiter.Destroying:Connect(function()
		alive = false
	end)

	-- Touch: damage + food confiscation + knockback
	torso.Touched:Connect(function(hit)
		if not alive then return end
		local humanoidHit = hit.Parent:FindFirstChildOfClass("Humanoid")
		if not humanoidHit then return end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end

		local now = tick()
		if lastHit[player] and now - lastHit[player] < Config.HIT_DEBOUNCE then return end
		lastHit[player] = now

		humanoidHit:TakeDamage(Config.HIT_DAMAGE)

		local hitSound = Instance.new("Sound")
		hitSound.SoundId = "rbxassetid://5943191636"
		hitSound.Volume  = 1
		hitSound.Parent  = torso
		hitSound:Play()
		Debris:AddItem(hitSound, 2)

		if RemoteEvents then
			RemoteEvents.HitFlash:FireClient(player)
		end

		local character = player.Character
		if character then
			local equipped = character:FindFirstChildOfClass("Tool")
			if equipped then equipped:Destroy() end
		end
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") then item:Destroy() end
		end

		local rootPart = hit.Parent:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			local direction = (hit.Position - torso.Position).Unit
			rootPart.AssemblyLinearVelocity = direction * 50 + Vector3.new(0, 20, 0)
		end
	end)

	-- AI loop: chase food-carriers or wander
	task.spawn(function()
		while alive do
			task.wait(0.5)
			if not (waiter and waiter.Parent and humanoid) then break end

			local nearestPlayer   = nil
			local nearestDistance = Config.DETECTION_RANGE

			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					local hasFood = char:FindFirstChildOfClass("Tool") ~= nil
					if not hasFood then
						for _, item in ipairs(player.Backpack:GetChildren()) do
							if item:IsA("Tool") then hasFood = true break end
						end
					end

					if hasFood then
						local dist = (char.HumanoidRootPart.Position - torso.Position).Magnitude
						if dist < nearestDistance then
							nearestPlayer   = player
							nearestDistance = dist
						end
					end
				end
			end

			if nearestPlayer and nearestPlayer.Character then
				humanoid.WalkSpeed = CHASE
				humanoid:MoveTo(nearestPlayer.Character.HumanoidRootPart.Position)
				eyeLight.Brightness = 5
				eyeLight.Range      = 20
			else
				humanoid.WalkSpeed = WANDER
				local angle  = math.random() * math.pi * 2
				local radius = math.random(20, 60)
				local center = Config.HOTEL_CENTER
				humanoid:MoveTo(Vector3.new(
					center.X + math.cos(angle) * radius,
					floorY,
					center.Z + math.sin(angle) * radius))
				eyeLight.Brightness = 2
				eyeLight.Range      = 10
			end
		end
	end)

	return waiter
end

return EnemyAI
