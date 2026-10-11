-- HunterAI.lua
-- Spawns uniformed guard NPCs on Floor 1 of the restaurant.
-- Guards react to the FoodStolenServer BindableEvent (fired by FoodSystem),
-- chase the thief using PathfindingService, and catch them on close approach.
-- Catch consequence: food confiscated, player teleported to entrance, short stun.
--
-- Guards differ from the creature AI (EnemyAI.lua):
--   • Triggered by theft events, not "player has food"
--   • Use PathfindingService to navigate around walls
--   • Named, uniformed humanoids — visually distinct
--
-- Movement model: ONE controller loop per guard owns all MoveTo calls.
-- Paths are cached and only recomputed when stale or when the target moved.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local ToolUtil = require(script.Parent.ToolUtil)

local HunterAI = {}

local Config = nil
local GameSystems = nil

local TICK = 0.3 -- controller loop interval
local PATH_MAX_AGE = 1.5 -- seconds before a chase path is recomputed
local PATH_TARGET_DRIFT = 8 -- studs the target may move before recomputing
local WAYPOINT_REACHED = 3 -- studs

-- Guard name pool
local GUARD_NAMES = { "Officer Rex", "Deputy Mal", "Constable Vex" }

-- guardData[model] = { state, target, chaseStartedAt, patrolGoal, path = { waypoints, index, target, computedAt } }
local guardData = {}

-- Per-player catch cooldowns to prevent double-catch by two guards simultaneously
local playerCatchCooldowns = {} -- [userId] = os.clock()

-- -------------------------------------------------------------------------
-- Geometry helpers
-- -------------------------------------------------------------------------
local function floorY()
	return Config.HOTEL_CENTER.Y + 2
end

local function insideHotelGroundFloor(position)
	local c = Config.HOTEL_CENTER
	local halfX = Config.HOTEL_SIZE.X / 2
	local halfZ = Config.HOTEL_SIZE.Z / 2
	return math.abs(position.X - c.X) < halfX
		and math.abs(position.Z - c.Z) < halfZ
		and position.Y < c.Y + Config.FLOOR_HEIGHT
end

-- -------------------------------------------------------------------------
-- Model construction
-- -------------------------------------------------------------------------
local function buildGuard(name, startPos)
	local model = Instance.new("Model")
	model.Name = "Guard_" .. name

	-- Torso (PrimaryPart)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.BrickColor = BrickColor.new("Bright blue")
	torso.Material = Enum.Material.SmoothPlastic
	torso.Position = startPos
	torso.Parent = model
	model.PrimaryPart = torso

	-- Uniform light
	local glow = Instance.new("PointLight")
	glow.Color = Color3.new(1, 1, 1)
	glow.Range = 10
	glow.Brightness = 1
	glow.Parent = torso

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.3, 1.3, 1.3)
	head.BrickColor = BrickColor.new("Light orange")
	head.Material = Enum.Material.SmoothPlastic
	head.Position = startPos + Vector3.new(0, 1.65, 0)
	head.Parent = model
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0, headWeld.Part1 = torso, head
	headWeld.Parent = torso

	-- Hat
	local hat = Instance.new("Part")
	hat.Name = "Hat"
	hat.Size = Vector3.new(1.8, 0.4, 1.8)
	hat.BrickColor = BrickColor.new("Dark blue")
	hat.Material = Enum.Material.SmoothPlastic
	hat.CanCollide = false
	hat.Position = startPos + Vector3.new(0, 2.5, 0)
	hat.Parent = model
	local hatWeld = Instance.new("WeldConstraint")
	hatWeld.Part0, hatWeld.Part1 = head, hat
	hatWeld.Parent = head

	-- Arms
	for _, side in ipairs({ -1.5, 1.5 }) do
		local arm = Instance.new("Part")
		arm.Size = Vector3.new(0.8, 2, 0.8)
		arm.BrickColor = BrickColor.new("Bright blue")
		arm.Material = Enum.Material.SmoothPlastic
		arm.Position = startPos + Vector3.new(side, 0, 0)
		arm.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, arm
		w.Parent = torso
	end

	-- Legs
	for _, side in ipairs({ -0.55, 0.55 }) do
		local leg = Instance.new("Part")
		leg.Size = Vector3.new(0.8, 2, 0.8)
		leg.BrickColor = BrickColor.new("Dark blue")
		leg.Material = Enum.Material.SmoothPlastic
		leg.Position = startPos + Vector3.new(side, -2, 0)
		leg.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, leg
		w.Parent = torso
	end

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = Config.GUARD_PATROL_SPEED
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Parent = model

	model.Parent = workspace
	ToolUtil.claimNetworkOwnership(torso)
	return model, torso, humanoid
end

-- -------------------------------------------------------------------------
-- Catch a thief: confiscate food, teleport, stun
-- -------------------------------------------------------------------------
local function stunPlayer(player, humanoid)
	humanoid:SetAttribute("Stunned", true)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	task.delay(Config.GUARD_STUN_TIME or 3, function()
		if humanoid.Parent then
			humanoid:SetAttribute("Stunned", nil)
		end
		-- Restore the player's saved (possibly upgraded) movement values,
		-- including any purchase made during the stun
		if GameSystems then
			GameSystems.applySettings(player)
		end
	end)
end

local function catchPlayer(guardModel, player)
	-- Per-player cooldown prevents two guards double-catching simultaneously
	local now = os.clock()
	local last = playerCatchCooldowns[player.UserId]
	if last and now - last < 5 then
		return
	end
	playerCatchCooldowns[player.UserId] = now

	local data = guardData[guardModel]
	if data then
		data.state = "RETURN"
		data.target = nil
		data.path = nil
	end

	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")

	-- 1. Confiscate food tools (bat, carpet and weapons are kept)
	ToolUtil.confiscateFood(player)

	-- 2. Teleport to restaurant entrance (south face of hotel, floor 1)
	local c = Config.HOTEL_CENTER
	local halfZ = Config.HOTEL_SIZE.Z / 2
	ToolUtil.teleport(player, CFrame.new(c.X, c.Y + 3, c.Z - halfZ + 12))

	-- 3. Stun
	if humanoid then
		stunPlayer(player, humanoid)
	end
end

-- -------------------------------------------------------------------------
-- Path following (non-blocking; called once per controller tick)
-- -------------------------------------------------------------------------
local function computePath(fromPos, toPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.5,
		AgentHeight = 5,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 2,
	})
	local ok = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return path:GetWaypoints()
end

local function followPath(data, humanoid, torso, targetPos)
	local now = os.clock()
	local p = data.path
	local stale = not p
		or now - p.computedAt > PATH_MAX_AGE
		or (targetPos - p.target).Magnitude > PATH_TARGET_DRIFT
		or p.index > #p.waypoints

	if stale then
		local waypoints = computePath(torso.Position, targetPos)
		if not waypoints or #waypoints < 2 then
			-- Fallback: direct move if pathfinding fails
			data.path = nil
			humanoid:MoveTo(targetPos)
			return
		end
		-- Waypoint 1 is the guard's own position
		p = { waypoints = waypoints, index = 2, target = targetPos, computedAt = now }
		data.path = p
	end

	-- Skip waypoints we've already reached
	while p.index <= #p.waypoints do
		local wp = p.waypoints[p.index]
		local flat = Vector3.new(wp.Position.X, torso.Position.Y, wp.Position.Z)
		if (flat - torso.Position).Magnitude > WAYPOINT_REACHED then
			break
		end
		p.index = p.index + 1
	end

	local wp = p.waypoints[p.index]
	if wp then
		humanoid:MoveTo(wp.Position)
	else
		humanoid:MoveTo(targetPos)
	end
end

-- -------------------------------------------------------------------------
-- Per-guard controller
-- -------------------------------------------------------------------------
local function endChase(data)
	data.state = "RETURN"
	data.target = nil
	data.path = nil
end

local function stepGuard(model, data, torso, humanoid)
	if data.state == "PATROL" then
		humanoid.WalkSpeed = Config.GUARD_PATROL_SPEED
		-- Pick a new wander goal when the current one is reached or unreachable
		local now = os.clock()
		if (torso.Position - data.patrolGoal).Magnitude < 4 or now - (data.patrolSince or 0) > 10 then
			local c = Config.HOTEL_CENTER
			local angle = math.random() * math.pi * 2
			local radius = math.random(10, 50)
			data.patrolGoal = Vector3.new(c.X + math.cos(angle) * radius, floorY(), c.Z + math.sin(angle) * radius)
			data.patrolSince = now
		end
		-- Re-issuing the same goal is cheap and survives MoveTo's 8 s timeout
		humanoid:MoveTo(data.patrolGoal)
	elseif data.state == "CHASE" then
		humanoid.WalkSpeed = Config.GUARD_CHASE_SPEED

		local target = data.target
		local targetHRP = target
			and target.Parent
			and target.Character
			and target.Character:FindFirstChild("HumanoidRootPart")
		if not targetHRP then
			endChase(data)
			return
		end

		local targetPos = targetHRP.Position
		local dist = (targetPos - torso.Position).Magnitude
		local timedOut = os.clock() - data.chaseStartedAt > Config.GUARD_CHASE_TIMEOUT
		-- Give up when the thief escapes the ground floor, outruns the guard, or time runs out
		if timedOut or dist > Config.GUARD_LOSE_RANGE or not insideHotelGroundFloor(targetPos) then
			endChase(data)
			return
		end

		if dist <= Config.GUARD_CATCH_RANGE then
			catchPlayer(model, target)
		else
			followPath(data, humanoid, torso, targetPos)
		end
	elseif data.state == "RETURN" then
		humanoid.WalkSpeed = Config.GUARD_PATROL_SPEED
		local home = Vector3.new(Config.HOTEL_CENTER.X, floorY(), Config.HOTEL_CENTER.Z)
		if (torso.Position - home).Magnitude < 10 then
			data.state = "PATROL"
			data.patrolGoal = torso.Position
		else
			followPath(data, humanoid, torso, home)
		end
	end
end

local function spawnGuard(name, pos)
	local model, torso, humanoid = buildGuard(name, pos)

	local data = {
		state = "PATROL",
		target = nil,
		chaseStartedAt = 0,
		patrolGoal = torso.Position,
		path = nil,
	}
	guardData[model] = data

	local alive = true
	local function stop()
		if not alive then
			return
		end
		alive = false
		guardData[model] = nil
	end

	model.AncestryChanged:Connect(function()
		if not model.Parent then
			stop()
		end
	end)

	-- Defeated guards stop acting immediately and respawn later
	humanoid.Died:Connect(function()
		stop()
		task.delay(3, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		task.delay(Config.GUARD_RESPAWN_TIME, function()
			spawnGuard(name, pos)
		end)
	end)

	task.spawn(function()
		while alive do
			task.wait(TICK)
			if not alive or humanoid.Health <= 0 then
				break
			end
			stepGuard(model, data, torso, humanoid)
		end
	end)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function HunterAI.init(remoteEvents, config, gameSystems)
	Config = config
	GameSystems = gameSystems

	-- Listen for theft events from FoodSystem
	remoteEvents.FoodStolenServer.Event:Connect(function(player, foodPos)
		for model, data in pairs(guardData) do
			if data.state ~= "CHASE" then
				local torso = model.PrimaryPart
				if torso and (torso.Position - foodPos).Magnitude <= Config.GUARD_ALERT_RANGE then
					data.state = "CHASE"
					data.target = player
					data.chaseStartedAt = os.clock()
					data.path = nil
				end
			end
		end
	end)

	-- Clean up per-player catch cooldowns on leave
	Players.PlayerRemoving:Connect(function(player)
		playerCatchCooldowns[player.UserId] = nil
	end)
end

function HunterAI.spawnAll()
	for i = 1, Config.GUARD_COUNT do
		local angle = (math.pi * 2 / Config.GUARD_COUNT) * i
		local pos = Vector3.new(
			Config.HOTEL_CENTER.X + math.cos(angle) * 40,
			floorY(),
			Config.HOTEL_CENTER.Z + math.sin(angle) * 40
		)
		spawnGuard(GUARD_NAMES[((i - 1) % #GUARD_NAMES) + 1], pos)
	end
end

return HunterAI
