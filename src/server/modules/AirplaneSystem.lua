-- AirplaneSystem.lua
-- Periodically (every 90–180 s) an airplane flies across the map at high altitude
-- and drops food items that fall to the ground and can be collected.
-- The airplane is built entirely from Parts — no external assets needed.
-- Only one airplane exists at a time; the scheduler waits until it leaves before
-- scheduling the next event.

local AirplaneSystem = {}

local Config = nil
local GameSystems = nil

-- Active flight state (nil when no airplane in the air)
local airplaneState = nil -- { model, alive }

-- -------------------------------------------------------------------------
-- Airplane model construction
-- -------------------------------------------------------------------------
local function buildAirplane(startPos)
	local model = Instance.new("Model")
	model.Name = "Airplane"

	-- Fuselage body (PrimaryPart — moved each frame)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(20, 5, 40)
	body.BrickColor = BrickColor.new("Medium stone grey")
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.CanCollide = false
	body.CFrame = CFrame.new(startPos)
	body.Parent = model
	model.PrimaryPart = body

	-- Engine sound
	local sound = Instance.new("Sound")
	sound.Name = "EngineSound"
	sound.SoundId = "rbxassetid://5945658523"
	sound.Volume = 0.7
	sound.Looped = true
	sound.RollOffMaxDistance = 600
	sound.Parent = body

	-- Helper: attach a Part to the body via WeldConstraint
	local function attach(part, offset, rotation)
		part.Anchored = false
		part.CanCollide = false
		part.CFrame = body.CFrame * CFrame.new(offset) * (rotation or CFrame.new())
		part.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = body, part
		w.Parent = body
		return part
	end

	-- Left wing
	local lw = Instance.new("WedgePart")
	lw.Name = "LeftWing"
	lw.Size = Vector3.new(30, 1, 15)
	lw.BrickColor = BrickColor.new("Light grey")
	lw.Material = Enum.Material.Metal
	attach(lw, Vector3.new(-20, -1, 0), CFrame.Angles(0, math.pi, 0))

	-- Right wing (mirrored)
	local rw = Instance.new("WedgePart")
	rw.Name = "RightWing"
	rw.Size = Vector3.new(30, 1, 15)
	rw.BrickColor = BrickColor.new("Light grey")
	rw.Material = Enum.Material.Metal
	attach(rw, Vector3.new(20, -1, 0))

	-- Tail fin
	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Size = Vector3.new(2, 8, 10)
	tail.BrickColor = BrickColor.new("Medium stone grey")
	tail.Material = Enum.Material.Metal
	attach(tail, Vector3.new(0, 4, 18), CFrame.Angles(0, 0, 0))

	-- Left engine
	local le = Instance.new("Part")
	le.Name = "LeftEngine"
	le.Shape = Enum.PartType.Cylinder
	le.Size = Vector3.new(6, 3, 3)
	le.BrickColor = BrickColor.new("Dark grey")
	le.Material = Enum.Material.Metal
	attach(le, Vector3.new(-14, -3, 0))

	-- Right engine
	local re = le:Clone()
	re.Name = "RightEngine"
	attach(re, Vector3.new(14, -3, 0))

	-- Cockpit (glass bubble)
	local cockpit = Instance.new("Part")
	cockpit.Name = "Cockpit"
	cockpit.Shape = Enum.PartType.Ball
	cockpit.Size = Vector3.new(5, 4, 5)
	cockpit.BrickColor = BrickColor.new("Cyan")
	cockpit.Material = Enum.Material.Glass
	cockpit.Transparency = 0.4
	attach(cockpit, Vector3.new(0, 2, -18))

	model.Parent = workspace
	return model
end

-- -------------------------------------------------------------------------
-- Drop one food item below the airplane
-- -------------------------------------------------------------------------
local function dropFood(bodyPos)
	local ft = Config.FOOD_TYPES[math.random(1, #Config.FOOD_TYPES)]

	-- Horizontal scatter so drops feel natural
	local dropPos = bodyPos + Vector3.new(math.random(-6, 6), -8, math.random(-6, 6))

	local part = Instance.new("Part")
	part.Name = ft.name .. "_AirDrop"
	part.Size = ft.size
	part.BrickColor = ft.color
	part.Material = Enum.Material.SmoothPlastic
	part.Position = dropPos
	part.Anchored = false
	part.CanCollide = true
	part.Parent = workspace

	-- Texture
	if ft.texture then
		local d = Instance.new("Decal")
		d.Texture = ft.texture
		d.Face = Enum.NormalId.Top
		d.Parent = part
	end

	-- Pickup prompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Collect"
	pp.ObjectText = ft.name .. " (Air Drop!)"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = part

	pp.Triggered:Connect(function(player)
		if not part.Parent then
			return
		end

		-- Create the same Tool format as FoodSystem
		local tool = Instance.new("Tool")
		tool.Name = ft.name
		tool.RequiresHandle = true

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = ft.size * 0.7
		handle.BrickColor = ft.color
		handle.Material = Enum.Material.SmoothPlastic
		handle.CanCollide = false

		-- Food metadata attributes (so sell stand picks up the price)
		handle:SetAttribute("BaseSellPrice", ft.sellPrice)
		handle:SetAttribute("CurrentSellPrice", ft.sellPrice)
		handle:SetAttribute("Rarity", ft.rarity or "Common")
		handle:SetAttribute("FoodId", ft.name)

		if ft.texture then
			local d = Instance.new("Decal")
			d.Texture = ft.texture
			d.Face = Enum.NormalId.Top
			d.Parent = handle
		end

		handle.Parent = tool
		tool.Parent = player.Backpack

		-- Air-drop food gives no stealth Score (it's freely available)
		-- but the food can still be sold at the sell stand normally.
		part:Destroy()
	end)

	-- Safety despawn
	task.delay(Config.AIRPLANE_FOOD_DESPAWN, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
end

-- -------------------------------------------------------------------------
-- Single airplane flight
-- -------------------------------------------------------------------------
local function runFlight()
	if airplaneState then
		return
	end -- only one airplane at a time

	-- Choose a random Z lane; keep path outside the 350-stud hotel footprint
	-- by biasing Z toward map edges (outside -175..+175 hotel Z range)
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

	local model = buildAirplane(startPos)
	local body = model.PrimaryPart

	-- Orient fuselage toward direction of travel (+X)
	body.CFrame = CFrame.new(startPos, endPos)

	local sound = body:FindFirstChild("EngineSound")
	if sound then
		sound:Play()
	end

	airplaneState = { model = model, alive = true }

	local totalDist = (endPos - startPos).Magnitude
	local duration = totalDist / Config.AIRPLANE_SPEED -- ~16 s at 100 studs/s
	local elapsed = 0
	local dropTimer = 0
	local STEP = 0.05 -- 20 Hz

	while elapsed < duration and airplaneState do
		task.wait(STEP)
		elapsed = elapsed + STEP
		dropTimer = dropTimer + STEP

		local t = math.min(elapsed / duration, 1)
		body.CFrame = CFrame.new(startPos:Lerp(endPos, t), endPos)

		if dropTimer >= Config.AIRPLANE_DROP_INTERVAL then
			dropTimer = 0
			dropFood(body.Position)
		end
	end

	if model and model.Parent then
		model:Destroy()
	end
	airplaneState = nil
end

-- -------------------------------------------------------------------------
-- Scheduler loop
-- -------------------------------------------------------------------------
local function schedulerLoop()
	while true do
		local waitTime = math.random(Config.AIRPLANE_INTERVAL_MIN, Config.AIRPLANE_INTERVAL_MAX)
		task.wait(waitTime)
		-- runFlight blocks until the airplane reaches the far edge
		runFlight()
	end
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function AirplaneSystem.init(config, gameSystems)
	Config = config
	GameSystems = gameSystems
end

function AirplaneSystem.start()
	task.spawn(schedulerLoop)
end

return AirplaneSystem
