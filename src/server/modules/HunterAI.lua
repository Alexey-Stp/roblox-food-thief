-- HunterAI.lua
-- Spawns uniformed guard NPCs on Floor 1 of the restaurant.
-- Guards react to the FoodStolenServer BindableEvent (fired by FoodSystem),
-- chase the thief using PathfindingService, and catch them on close approach.
-- Catch consequence: food confiscated, player teleported to entrance, 3 s stun.
--
-- Guards differ from the creature AI (EnemyAI.lua):
--   • Triggered by theft events, not "player has food"
--   • Use PathfindingService to navigate around walls
--   • Named, uniformed humanoids — visually distinct

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local HunterAI = {}

local Config = nil

-- Guard name pool
local GUARD_NAMES = { "Officer Rex", "Deputy Mal", "Constable Vex" }

-- guardData[model] = { state, target, targetLostAt, lastCatch, patrolGoal }
local guardData = {}

-- Per-player catch cooldowns to prevent double-catch by two guards simultaneously
local playerCatchCooldowns = {} -- [userId] = tick()

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

	-- Name BillboardGui so players can see the guard
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 160, 0, 28)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = name
	lbl.TextColor3 = Color3.new(1, 0.2, 0.2)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.SourceSansBold
	lbl.Parent = bb

	model.Parent = workspace
	return model, torso, humanoid
end

-- -------------------------------------------------------------------------
-- Catch a thief: confiscate food, teleport, stun
-- -------------------------------------------------------------------------
local function isProtectedTool(item)
	if not item or not item:IsA("Tool") then
		return true
	end
	local h = item:FindFirstChild("Handle")
	return h and (h:GetAttribute("IsBat") == true or h:GetAttribute("IsCarpet") == true)
end

local function catchPlayer(guardModel, player)
	-- Per-player cooldown prevents two guards double-catching simultaneously
	local now = tick()
	if now - (playerCatchCooldowns[player.UserId] or 0) < 5 then
		return
	end
	playerCatchCooldowns[player.UserId] = now

	local data = guardData[guardModel]
	if data then
		data.state = "RETURN"
		data.target = nil
	end

	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")

	-- 1. Confiscate food tools (spare bat and carpet)
	local equipped = char:FindFirstChildOfClass("Tool")
	if equipped and not isProtectedTool(equipped) then
		equipped:Destroy()
	end
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") and not isProtectedTool(item) then
			item:Destroy()
		end
	end

	-- 2. Teleport to restaurant entrance (south face of hotel, floor 1)
	if hrp then
		local cx = Config.HOTEL_CENTER.X
		local cy = Config.HOTEL_CENTER.Y
		local cz = Config.HOTEL_CENTER.Z
		local halfZ = Config.HOTEL_SIZE.Z / 2
		hrp.CFrame = CFrame.new(cx, cy + 3, cz - halfZ + 12)
	end

	-- 3. Stun for 3 seconds (zero speed; restore after delay)
	if humanoid then
		local savedSpeed = humanoid.WalkSpeed
		local savedJump = humanoid.JumpPower
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		task.delay(3, function()
			-- Re-read character in case player respawned during stun
			local c2 = player.Character
			if c2 then
				local h2 = c2:FindFirstChildOfClass("Humanoid")
				if h2 then
					h2.WalkSpeed = savedSpeed
					h2.JumpPower = savedJump
				end
			end
		end)
	end
end

-- -------------------------------------------------------------------------
-- Pathfinding chase step
-- -------------------------------------------------------------------------
local function chaseStep(humanoid, fromPos, toPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	})

	local ok = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		-- Fallback: direct move if pathfinding fails
		humanoid:MoveTo(toPos)
		return
	end

	for _, wp in ipairs(path:GetWaypoints()) do
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(wp.Position)
		-- MoveToFinished has a built-in 4-second timeout
		humanoid.MoveToFinished:Wait()
	end
end

-- -------------------------------------------------------------------------
-- AI loop for one guard
-- -------------------------------------------------------------------------
local function startAI(model, torso, humanoid)
	local alive = true
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			alive = false
		end
	end)

	guardData[model] = {
		state = "PATROL",
		target = nil,
		targetLostAt = nil,
		patrolGoal = torso.Position,
	}

	task.spawn(function()
		while alive do
			task.wait(0.5)
			if not (model.Parent and humanoid) then
				break
			end

			local data = guardData[model]
			if not data then
				break
			end

			-- ── PATROL ──────────────────────────────────────────────────
			if data.state == "PATROL" then
				humanoid.WalkSpeed = Config.GUARD_PATROL_SPEED
				-- Pick a new wander goal when close to current one
				local dist = (torso.Position - data.patrolGoal).Magnitude
				if dist < 4 then
					local cx = Config.HOTEL_CENTER.X
					local cz = Config.HOTEL_CENTER.Z
					local floorY = Config.HOTEL_CENTER.Y + 2
					local angle = math.random() * math.pi * 2
					local radius = math.random(10, 50)
					data.patrolGoal = Vector3.new(cx + math.cos(angle) * radius, floorY, cz + math.sin(angle) * radius)
				end
				humanoid:MoveTo(data.patrolGoal)

			-- ── CHASE ────────────────────────────────────────────────────
			elseif data.state == "CHASE" then
				humanoid.WalkSpeed = Config.GUARD_CHASE_SPEED

				local target = data.target
				if not target or not target.Character then
					-- Lost the target
					data.state = "RETURN"
					data.target = nil
				else
					local targetChar = target.Character
					local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
					if targetHRP then
						local d = (targetHRP.Position - torso.Position).Magnitude
						if d <= Config.GUARD_CATCH_RANGE then
							catchPlayer(model, target)
						else
							-- Pathfind toward target; update lose timer
							task.spawn(function()
								chaseStep(humanoid, torso.Position, targetHRP.Position)
							end)
							data.targetLostAt = nil
						end
					else
						-- Target respawned / no HRP
						if not data.targetLostAt then
							data.targetLostAt = tick()
						elseif tick() - data.targetLostAt > Config.GUARD_CHASE_TIMEOUT then
							data.state = "RETURN"
							data.target = nil
						end
					end
				end

			-- ── RETURN ───────────────────────────────────────────────────
			elseif data.state == "RETURN" then
				humanoid.WalkSpeed = Config.GUARD_PATROL_SPEED
				-- Return to a central patrol area then switch back to PATROL
				local cx = Config.HOTEL_CENTER.X
				local cz = Config.HOTEL_CENTER.Z
				local floorY = Config.HOTEL_CENTER.Y + 2
				humanoid:MoveTo(Vector3.new(cx, floorY, cz))
				local dist = (torso.Position - Vector3.new(cx, floorY, cz)).Magnitude
				if dist < 10 then
					data.state = "PATROL"
				end
			end
		end

		-- Cleanup when guard is destroyed
		guardData[model] = nil
	end)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function HunterAI.init(remoteEvents, config)
	Config = config

	-- Listen for theft events from FoodSystem
	remoteEvents.FoodStolenServer.Event:Connect(function(player, foodPos)
		for model, data in pairs(guardData) do
			if data.state == "PATROL" then
				local torso = model.PrimaryPart
				if torso then
					local dist = (torso.Position - foodPos).Magnitude
					if dist <= Config.GUARD_ALERT_RANGE then
						data.state = "CHASE"
						data.target = player
						data.targetLostAt = nil
					end
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
	local floorY = Config.HOTEL_CENTER.Y + 2

	for i = 1, Config.GUARD_COUNT do
		local angle = (math.pi * 2 / Config.GUARD_COUNT) * i
		local pos = Vector3.new(
			Config.HOTEL_CENTER.X + math.cos(angle) * 40,
			floorY,
			Config.HOTEL_CENTER.Z + math.sin(angle) * 40
		)
		local name = GUARD_NAMES[((i - 1) % #GUARD_NAMES) + 1]
		local model, torso, humanoid = buildGuard(name, pos)
		startAI(model, torso, humanoid)
	end
end

return HunterAI
