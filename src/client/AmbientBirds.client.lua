-- AmbientBirds.client.lua  (LocalScript in StarterPlayerScripts)
-- Purely cosmetic birds circling at low altitude. They have no gameplay
-- effect, so they are built and animated locally on each client instead of
-- replicating 20 Hz CFrame updates from the server.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- { centre, altitude }
local BIRD_DEFS = {
	{ Vector3.new(-150, 0, 50), 18 },
	{ Vector3.new(80, 0, -150), 22 },
	{ Vector3.new(200, 0, 100), 16 },
	{ Vector3.new(-80, 0, 200), 20 },
	{ Vector3.new(0, 0, -180), 25 },
	{ Vector3.new(160, 0, -50), 19 },
	{ Vector3.new(-200, 0, -100), 23 },
	{ Vector3.new(300, 0, 200), 17 },
}

local FLAP_PERIOD = 0.3

local function makePart(name, size, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.BrickColor = BrickColor.new("White")
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local folder = Instance.new("Folder")
folder.Name = "AmbientBirds"
folder.Parent = Workspace

local rng = Random.new()
local birds = {}

for _, def in ipairs(BIRD_DEFS) do
	local model = Instance.new("Model")
	model.Name = "AmbientBird"
	model.Parent = folder

	table.insert(birds, {
		center = def[1],
		altitude = def[2],
		radius = rng:NextNumber(12, 25),
		speed = rng:NextNumber(0.4, 0.8), -- radians/sec
		angle = rng:NextNumber(0, math.pi * 2),
		body = makePart("Body", Vector3.new(0.6, 0.3, 0.9), model),
		wingL = makePart("WingL", Vector3.new(0.9, 0.1, 0.4), model),
		wingR = makePart("WingR", Vector3.new(0.9, 0.1, 0.4), model),
	})
end

RunService.RenderStepped:Connect(function(dt)
	local flapUp = (os.clock() % (FLAP_PERIOD * 2)) < FLAP_PERIOD
	local tilt = flapUp and math.rad(25) or math.rad(-10)

	for _, bird in ipairs(birds) do
		bird.angle = bird.angle + bird.speed * dt
		local a = bird.angle
		local x = bird.center.X + math.cos(a) * bird.radius
		local z = bird.center.Z + math.sin(a) * bird.radius
		local y = bird.altitude + math.sin(a * 3) * 1.5 -- gentle altitude bob

		local bodyCF = CFrame.new(x, y, z) * CFrame.Angles(0, a + math.pi / 2, 0)
		bird.body.CFrame = bodyCF
		-- Wings follow the body every frame (previously they lagged between flaps)
		bird.wingL.CFrame = bodyCF * CFrame.new(0.75, 0, 0) * CFrame.Angles(0, 0, tilt)
		bird.wingR.CFrame = bodyCF * CFrame.new(-0.75, 0, 0) * CFrame.Angles(0, 0, -tilt)
	end
end)
