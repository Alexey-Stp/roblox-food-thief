-- AmbientCreatures.lua
-- Non-interactive ambient wildlife: Dogs and Cats.
-- Purely cosmetic — no damage, no interaction, no DataStore.
-- Dogs and cats wander slowly on the ground.
-- Birds are purely visual and run client-side (AmbientBirds.client.lua).

local ToolUtil = require(script.Parent.ToolUtil)

local AmbientCreatures = {}

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
local function makePart(name, size, pos, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Anchored = true
	p.BrickColor = BrickColor.new(color)
	p.Material = material
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
end

-- -------------------------------------------------------------------------
-- Dog model (grey-brown quadruped)
-- -------------------------------------------------------------------------
local function buildDog(pos, parent)
	local model = Instance.new("Model")
	model.Name = "AmbientDog"
	model.Parent = parent

	local body = makePart(
		"Body",
		Vector3.new(1.8, 1, 2.5),
		pos + Vector3.new(0, 0.5, 0),
		"Sand red",
		Enum.Material.SmoothPlastic,
		model
	)
	body.Anchored = false
	model.PrimaryPart = body

	local head = makePart(
		"Head",
		Vector3.new(1, 0.9, 1),
		pos + Vector3.new(0, 1.2, 1),
		"Sand red",
		Enum.Material.SmoothPlastic,
		model
	)
	head.Anchored = false
	weld(body, head)

	local snout = makePart(
		"Snout",
		Vector3.new(0.5, 0.4, 0.5),
		pos + Vector3.new(0, 1.0, 1.5),
		"Nougat",
		Enum.Material.SmoothPlastic,
		model
	)
	snout.Anchored = false
	weld(body, snout)

	local tail = makePart(
		"Tail",
		Vector3.new(0.3, 0.3, 1),
		pos + Vector3.new(0, 0.8, -1.5),
		"Sand red",
		Enum.Material.SmoothPlastic,
		model
	)
	tail.Anchored = false
	weld(body, tail)

	-- Four legs
	for _, offset in ipairs({
		Vector3.new(0.6, -0.75, 0.8),
		Vector3.new(-0.6, -0.75, 0.8),
		Vector3.new(0.6, -0.75, -0.8),
		Vector3.new(-0.6, -0.75, -0.8),
	}) do
		local leg =
			makePart("Leg", Vector3.new(0.35, 0.9, 0.35), pos + offset, "Sand red", Enum.Material.SmoothPlastic, model)
		leg.Anchored = false
		weld(body, leg)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 4
	humanoid.MaxHealth = 50
	humanoid.Health = 50
	humanoid.Parent = model

	return model, body, humanoid
end

-- -------------------------------------------------------------------------
-- Cat model (tan, smaller)
-- -------------------------------------------------------------------------
local function buildCat(pos, parent)
	local model = Instance.new("Model")
	model.Name = "AmbientCat"
	model.Parent = parent

	local body = makePart(
		"Body",
		Vector3.new(1.2, 0.7, 1.8),
		pos + Vector3.new(0, 0.35, 0),
		"Tan",
		Enum.Material.SmoothPlastic,
		model
	)
	body.Anchored = false
	model.PrimaryPart = body

	local head = makePart(
		"Head",
		Vector3.new(0.8, 0.7, 0.8),
		pos + Vector3.new(0, 0.9, 0.7),
		"Tan",
		Enum.Material.SmoothPlastic,
		model
	)
	head.Anchored = false
	weld(body, head)

	local earL = makePart(
		"EarL",
		Vector3.new(0.2, 0.3, 0.1),
		pos + Vector3.new(0.25, 1.3, 0.7),
		"Tan",
		Enum.Material.SmoothPlastic,
		model
	)
	earL.Anchored = false
	weld(body, earL)
	local earR = makePart(
		"EarR",
		Vector3.new(0.2, 0.3, 0.1),
		pos + Vector3.new(-0.25, 1.3, 0.7),
		"Tan",
		Enum.Material.SmoothPlastic,
		model
	)
	earR.Anchored = false
	weld(body, earR)

	local tail = makePart(
		"Tail",
		Vector3.new(0.2, 0.2, 1.2),
		pos + Vector3.new(0, 0.5, -1.2),
		"Tan",
		Enum.Material.SmoothPlastic,
		model
	)
	tail.Anchored = false
	weld(body, tail)

	for _, offset in ipairs({
		Vector3.new(0.4, -0.5, 0.55),
		Vector3.new(-0.4, -0.5, 0.55),
		Vector3.new(0.4, -0.5, -0.55),
		Vector3.new(-0.4, -0.5, -0.55),
	}) do
		local leg =
			makePart("Leg", Vector3.new(0.25, 0.6, 0.25), pos + offset, "Tan", Enum.Material.SmoothPlastic, model)
		leg.Anchored = false
		weld(body, leg)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 3
	humanoid.MaxHealth = 30
	humanoid.Health = 30
	humanoid.Parent = model

	return model, body, humanoid
end

-- -------------------------------------------------------------------------
-- AI loops
-- -------------------------------------------------------------------------
local function startDogCatAI(model, root, humanoid, range)
	-- Server owns the physics so nearby clients cannot fling the animals
	ToolUtil.claimNetworkOwnership(root)
	local alive = true
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			alive = false
		end
	end)
	local home = root.Position
	local rng = Random.new()

	task.spawn(function()
		while alive do
			-- 70% chance to stay put (cats sit more, dogs slightly less)
			local pause = rng:NextNumber() < 0.4 and rng:NextNumber(3, 8) or rng:NextNumber(6, 14)
			task.wait(pause)
			if not alive then
				break
			end
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(2, range)
			local goal = home + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
			if humanoid and humanoid.Health > 0 then
				humanoid:MoveTo(goal)
			end
		end
	end)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function AmbientCreatures.init()
	-- No dependencies required
end

function AmbientCreatures.spawnAll()
	local parent = workspace

	-- Dog spawn positions (around map exterior, away from hotel centre)
	local dogPositions = {
		Vector3.new(-200, 1, 80),
		Vector3.new(-180, 1, -120),
		Vector3.new(120, 1, -200),
		Vector3.new(200, 1, 150),
		Vector3.new(300, 1, -80),
	}
	for _, pos in ipairs(dogPositions) do
		local model, root, humanoid = buildDog(pos, parent)
		startDogCatAI(model, root, humanoid, 18)
	end

	-- Cat spawn positions (quieter corners)
	local catPositions = {
		Vector3.new(-220, 1, 200),
		Vector3.new(100, 1, 220),
		Vector3.new(-100, 1, -220),
		Vector3.new(250, 1, 60),
		Vector3.new(-60, 1, 300),
	}
	for _, pos in ipairs(catPositions) do
		local model, root, humanoid = buildCat(pos, parent)
		startDogCatAI(model, root, humanoid, 10)
	end
end

return AmbientCreatures
