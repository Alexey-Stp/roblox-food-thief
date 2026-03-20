-- RestaurantBuilder.lua
-- Builds the world ground and the 3-floor Grand Hotel.
-- Returns: hotel (Model), floorFoodPositions (table[floor][i] = {position, foodType})

local RestaurantBuilder = {}

-- Door debounce timestamps (keyed by Part; cleaned up when door is destroyed)
local doorCooldowns = {}

-- Lift debounce timestamps (keyed by Platform Part)
local liftCooldowns = {}

-- All indoor PointLight instances — toggled by the light switch in the lobby
local indoorLights = {}

-- Table colours per floor (module-level constant)
local TABLE_COLORS = {
	BrickColor.new("Dark orange"), -- Floor 1
	BrickColor.new("Reddish brown"), -- Floor 2
	BrickColor.new("Black"), -- Floor 3
}

-- -------------------------------------------------------------------------
-- SurfaceGui label helper  (declared early so later helpers can use it)
-- -------------------------------------------------------------------------
local function addLabel(part, face, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.Parent = part
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = text
	lbl.TextColor3 = textColor or Color3.new(1, 1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.SourceSansBold
	lbl.Parent = gui
	return lbl
end

-- -------------------------------------------------------------------------
-- Indoor ceiling lighting
-- Creates a 3×3 grid of PointLights per floor so the interior stays bright
-- regardless of the outdoor Lighting settings (ClockTime/ambient changes).
-- All lights are registered in the module-level `indoorLights` table so the
-- lobby light-switch can toggle them at runtime.
-- -------------------------------------------------------------------------
local function buildIndoorLighting(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local cy = Config.HOTEL_CENTER.Y
	local fh = Config.FLOOR_HEIGHT

	-- Spread 3 lights evenly per axis across the 340-stud interior
	local offsets = { -70, 0, 70 }

	for f = 1, Config.FLOOR_COUNT do
		-- Hang lights just below the ceiling slab of the floor above
		local ceilY = cy + f * fh - 2

		for _, dx in ipairs(offsets) do
			for _, dz in ipairs(offsets) do
				local anchor = Instance.new("Part")
				anchor.Name = "CeilingLight_F" .. f
				anchor.Size = Vector3.new(2, 0.4, 2)
				anchor.Position = Vector3.new(cx + dx, ceilY, cz + dz)
				anchor.Anchored = true
				anchor.CanCollide = false
				anchor.BrickColor = BrickColor.new("Bright yellow")
				anchor.Material = Enum.Material.Neon
				anchor.Transparency = 0.4
				anchor.Parent = parent

				local light = Instance.new("PointLight")
				light.Brightness = 12
				light.Range = 90 -- wide enough to overlap with adjacent lights
				light.Color = Color3.fromRGB(255, 245, 215) -- warm white
				light.Parent = anchor

				table.insert(indoorLights, light)
			end
		end
	end
end

-- -------------------------------------------------------------------------
-- Lobby light-switch: ProximityPrompt that toggles all indoor lights on/off.
-- Default = on (lights always bright).
-- -------------------------------------------------------------------------
local function buildLightSwitch(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cy = Config.HOTEL_CENTER.Y
	local rz = Config.HOTEL_SIZE.Z

	-- Place the switch on the south interior wall near the main entrance
	local switch = Instance.new("Part")
	switch.Name = "LightSwitch"
	switch.Size = Vector3.new(1.5, 2, 0.5)
	switch.Position = Vector3.new(cx - 18, cy + 5, -rz / 2 + 4)
	switch.Anchored = true
	switch.BrickColor = BrickColor.new("Bright green")
	switch.Material = Enum.Material.Neon
	switch.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = switch
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = "💡"
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Turn Off Lights"
	prompt.ObjectText = "Light Switch"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.Parent = switch

	local lightsOn = true
	prompt.Triggered:Connect(function()
		lightsOn = not lightsOn
		for _, light in ipairs(indoorLights) do
			light.Enabled = lightsOn
		end
		switch.BrickColor = lightsOn and BrickColor.new("Bright green") or BrickColor.new("Dark grey")
		prompt.ActionText = lightsOn and "Turn Off Lights" or "Turn On Lights"
	end)
end

-- -------------------------------------------------------------------------
-- Staircase between two floor levels
-- Builds 13 steps (each 2 studs tall × 2 studs deep) climbing ~26 studs while
-- advancing in the X direction.  Neon railings mark edges for visibility.
--   parent     : Model to parent all parts into
--   name       : prefix for part names
--   startX     : world X of first (lowest) step
--   startY     : world Y of the bottom of the first step
--   startZ     : world Z centre of the staircase (constant)
--   dirX       : +1 → steps advance eastward, -1 → westward
--   stepWidth  : Z extent of each step (the "width" perpendicular to travel)
-- -------------------------------------------------------------------------
-- STEP_COUNT × STEP_HEIGHT must not exceed Config.FLOOR_HEIGHT (25).
-- 12 × 2 = 24 studs — fits cleanly with 1 stud clearance below the ceiling slab.
local STAIR_STEP_COUNT = 12
local STAIR_STEP_HEIGHT = 2
local STAIR_STEP_DEPTH = 2
-- Horizontal distance the staircase travels (used externally to compute slab openings)
local STAIR_TRAVEL = STAIR_STEP_COUNT * STAIR_STEP_DEPTH -- 24 studs

local function buildStaircase(parent, name, startX, startY, startZ, dirX, stepWidth)
	local STEP_COUNT = STAIR_STEP_COUNT
	local STEP_HEIGHT = STAIR_STEP_HEIGHT -- studs per step vertically
	local STEP_DEPTH = STAIR_STEP_DEPTH -- studs per step horizontally
	local STEP_MAT = Enum.Material.Metal
	local STEP_COLOR = BrickColor.new("Medium stone grey")
	local GLOW_COLOR = Color3.fromRGB(80, 190, 255)
	local RAIL_COLOR = BrickColor.new("Bright yellow")

	-- Build individual steps
	for i = 0, STEP_COUNT - 1 do
		local step = Instance.new("Part")
		step.Name = name .. "_Step" .. (i + 1)
		step.Size = Vector3.new(STEP_DEPTH, STEP_HEIGHT, stepWidth)
		step.Position = Vector3.new(
			startX + dirX * (i * STEP_DEPTH + STEP_DEPTH / 2),
			startY + i * STEP_HEIGHT + STEP_HEIGHT / 2,
			startZ
		)
		step.Anchored = true
		step.BrickColor = STEP_COLOR
		step.Material = STEP_MAT
		step.Parent = parent

		-- Subtle neon glow on the front face for visibility at night
		local glow = Instance.new("SurfaceLight")
		glow.Face = dirX > 0 and Enum.NormalId.Left or Enum.NormalId.Right
		glow.Brightness = 2
		glow.Range = 6
		glow.Color = GLOW_COLOR
		glow.Parent = step
	end

	-- Helper to build a diagonal rail along one Z edge of the staircase
	local function makeRail(zOffset)
		local railStartPos = Vector3.new(startX, startY + STEP_COUNT * STEP_HEIGHT + 2, startZ + zOffset)
		local railEndPos = Vector3.new(
			startX + dirX * STEP_COUNT * STEP_DEPTH,
			startY + STEP_COUNT * STEP_HEIGHT + 2,
			startZ + zOffset
		)
		local midPos = (railStartPos + railEndPos) * 0.5
		local len = (railEndPos - railStartPos).Magnitude

		local rail = Instance.new("Part")
		rail.Name = name .. "_Rail_" .. tostring(zOffset)
		rail.Size = Vector3.new(0.3, 0.3, len)
		rail.CFrame = CFrame.new(midPos, railEndPos)
		rail.Anchored = true
		rail.BrickColor = RAIL_COLOR
		rail.Material = Enum.Material.Neon
		rail.Parent = parent

		-- Vertical posts every 3 steps
		for i = 0, STEP_COUNT - 1, 3 do
			local post = Instance.new("Part")
			post.Name = name .. "_Post" .. i .. "_" .. tostring(zOffset)
			post.Size = Vector3.new(0.4, 4, 0.4)
			post.Position = Vector3.new(startX + dirX * i * STEP_DEPTH, startY + i * STEP_HEIGHT + 2, startZ + zOffset)
			post.Anchored = true
			post.BrickColor = BrickColor.new("Dark stone grey")
			post.Material = Enum.Material.Metal
			post.Parent = parent
		end
	end

	makeRail(-(stepWidth / 2 + 0.5))
	makeRail((stepWidth / 2 + 0.5))

	-- Landing platform at the top — bridges the gap between the last step
	-- and the upper-floor surface so the player can step off smoothly.
	local topStepTopY = startY + STEP_COUNT * STEP_HEIGHT -- top face of the final step
	local landingDepth = STEP_DEPTH * 2
	local landing = Instance.new("Part")
	landing.Name = name .. "_Landing"
	landing.Size = Vector3.new(landingDepth, STEP_HEIGHT, stepWidth)
	landing.Position = Vector3.new(
		startX + dirX * (STEP_COUNT * STEP_DEPTH + landingDepth / 2),
		topStepTopY - STEP_HEIGHT / 2, -- flush with top step surface
		startZ
	)
	landing.Anchored = true
	landing.BrickColor = BrickColor.new("Medium stone grey")
	landing.Material = Enum.Material.Metal
	landing.Parent = parent
end

-- -------------------------------------------------------------------------
-- Parkour platforms and jump pads between floors
-- Adds floating platforms at intermediate heights plus neon jump pads that
-- launch players upward by one floor.
-- -------------------------------------------------------------------------
local function buildParkourElements(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local cy = Config.HOTEL_CENTER.Y
	local fh = Config.FLOOR_HEIGHT

	-- Helper: create a floating platform
	local function makePlatform(px, py, pz, sx, sz, color)
		local plat = Instance.new("Part")
		plat.Name = "ParkourPlatform"
		plat.Size = Vector3.new(sx, 1, sz)
		plat.Position = Vector3.new(px, py, pz)
		plat.Anchored = true
		plat.BrickColor = color or BrickColor.new("Dark stone grey")
		plat.Material = Enum.Material.SmoothPlastic
		plat.Parent = parent
	end

	-- Helper: create a neon jump pad that launches players vertically
	-- launchVelocity: upward studs/sec (≈ 100 reaches one floor up)
	local function makeJumpPad(px, py, pz, launchVelocity)
		local pad = Instance.new("Part")
		pad.Name = "JumpPad"
		pad.Size = Vector3.new(5, 0.5, 5)
		pad.Position = Vector3.new(px, py, pz)
		pad.Anchored = true
		pad.BrickColor = BrickColor.new("Bright green")
		pad.Material = Enum.Material.Neon
		pad.Parent = parent

		addLabel(pad, Enum.NormalId.Top, "⬆ JUMP", Color3.new(0, 0, 0))

		-- Apply upward velocity to any player that touches the pad
		pad.Touched:Connect(function(hit)
			local char = hit.Parent
			if not char then
				return
			end
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			if not root then
				return
			end
			-- Use AssemblyLinearVelocity to launch the player upward
			root.AssemblyLinearVelocity =
				Vector3.new(root.AssemblyLinearVelocity.X, launchVelocity, root.AssemblyLinearVelocity.Z)
		end)
	end

	-- ── Platforms + jump pads between Floor 1 and Floor 2 ────────────────
	-- Heights: F1 floor ≈ cy+0.5, F2 floor ≈ cy+25.5
	local f1Base = cy + 0.5
	local f2Base = cy + fh + 0.5

	-- Platforms in the western interior area
	makePlatform(cx - 60, f1Base + 7, cz - 40, 10, 8)
	makePlatform(cx - 80, f1Base + 14, cz - 10, 8, 8)
	makePlatform(cx - 55, f1Base + 21, cz + 30, 10, 8)

	-- Jump pad on the F1 ground that launches to the first platform
	makeJumpPad(cx - 60, f1Base + 1, cz - 40, 50)

	-- ── Platforms + jump pads between Floor 2 and Floor 3 ────────────────
	local f3Base = cy + 2 * fh + 0.5

	-- Platforms in the eastern interior area
	makePlatform(cx + 60, f2Base + 7, cz + 40, 10, 8)
	makePlatform(cx + 80, f2Base + 14, cz + 10, 8, 8)
	makePlatform(cx + 55, f2Base + 21, cz - 30, 10, 8)

	-- Jump pad on the F2 slab that launches to the first platform
	makeJumpPad(cx + 60, f2Base + 1, cz + 40, 50)

	-- Crates as decorative obstacles / stepping stones (F1 area)
	local CRATE_COLOR = BrickColor.new("Reddish brown")
	for i = 1, 4 do
		local angle = (math.pi / 2) * i + math.pi / 4
		local cx2 = cx + math.cos(angle) * 110
		local cz2 = cz + math.sin(angle) * 110
		local crate = Instance.new("Part")
		crate.Name = "Crate_F1_" .. i
		crate.Size = Vector3.new(3, 3, 3)
		crate.Position = Vector3.new(cx2, f1Base + 2, cz2)
		crate.Anchored = true
		crate.BrickColor = CRATE_COLOR
		crate.Material = Enum.Material.Wood
		crate.Parent = parent
	end
end

-- -------------------------------------------------------------------------
-- Ground / Baseplate
-- -------------------------------------------------------------------------
local function buildGround(Config)
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Config.GROUND_SIZE
	ground.Position = Vector3.new(0, -Config.GROUND_SIZE.Y / 2, 0)
	ground.Anchored = true
	ground.BrickColor = BrickColor.new("Bright green")
	ground.Material = Enum.Material.Grass
	ground.Parent = workspace
end

-- -------------------------------------------------------------------------
-- Hotel doors (ground floor entry)
-- -------------------------------------------------------------------------
local function createHotelDoor(position, rotation, parent, doorName, debounceTime)
	local door = Instance.new("Part")
	door.Name = doorName
	door.Size = Vector3.new(20, 22, 1)
	door.Anchored = true
	door.BrickColor = BrickColor.new("Dark orange")
	door.Material = Enum.Material.WoodPlanks
	door.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	door.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Door"
	prompt.ObjectText = "Hotel Door"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 15
	prompt.Parent = door

	local doorOpen = false
	doorCooldowns[door] = 0
	door.Destroying:Connect(function()
		doorCooldowns[door] = nil
	end)

	prompt.Triggered:Connect(function()
		local now = tick()
		if now - doorCooldowns[door] < debounceTime then
			return
		end
		doorCooldowns[door] = now

		doorOpen = not doorOpen
		door.CanCollide = not doorOpen
		door.Transparency = doorOpen and 0.7 or 0
		prompt.ActionText = doorOpen and "Close Door" or "Open Door"
	end)

	return door
end

-- -------------------------------------------------------------------------
-- Floor isolation doors (at lift entrances)
-- -------------------------------------------------------------------------
local function createFloorDoor(position, rotation, parent, doorName, debounceTime)
	local door = Instance.new("Part")
	door.Name = doorName
	door.Size = Vector3.new(14, 20, 1)
	door.Anchored = true
	door.BrickColor = BrickColor.new("Medium stone grey")
	door.Material = Enum.Material.Metal
	door.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	door.Parent = parent

	addLabel(door, Enum.NormalId.Front, "LIFT", Color3.new(1, 1, 0))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Lift Door"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.Parent = door

	local doorOpen = false
	doorCooldowns[door] = 0
	door.Destroying:Connect(function()
		doorCooldowns[door] = nil
	end)

	prompt.Triggered:Connect(function()
		local now = tick()
		if now - doorCooldowns[door] < debounceTime then
			return
		end
		doorCooldowns[door] = now

		doorOpen = not doorOpen
		door.CanCollide = not doorOpen
		door.Transparency = doorOpen and 0.7 or 0
		prompt.ActionText = doorOpen and "Close Lift Door" or "Open Lift Door"
	end)

	return door
end

-- -------------------------------------------------------------------------
-- Window row: 8 evenly spaced panes along a wall
-- wallCenterX/Z: world X/Z of wall center; wallLength: span; isNS: N/S wall (true) or E/W wall
-- -------------------------------------------------------------------------
local function buildWindowRow(parent, wallCenterX, wallCenterZ, wallLength, windowY, isNS)
	local windowCount = 8
	local spacing = wallLength / (windowCount + 1)

	for i = 1, windowCount do
		local offset = -wallLength / 2 + spacing * i

		local win = Instance.new("Part")
		win.Name = "Window"
		win.Anchored = true
		win.BrickColor = BrickColor.new("Cyan")
		win.Material = Enum.Material.Glass
		win.Transparency = 0.4
		win.CanCollide = false
		win.Parent = parent

		if isNS then
			win.Size = Vector3.new(10, 8, 0.3)
			win.Position = Vector3.new(wallCenterX + offset, windowY, wallCenterZ)
		else
			win.Size = Vector3.new(0.3, 8, 10)
			win.Position = Vector3.new(wallCenterX, windowY, wallCenterZ + offset)
		end
	end
end

-- -------------------------------------------------------------------------
-- Lift system: TweenService Platform moving between two floors
-- side: "east" (F1↔F2) or "west" (F2↔F3)
-- -------------------------------------------------------------------------
local function buildLift(parent, Config, side)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local cy = Config.HOTEL_CENTER.Y
	local fh = Config.FLOOR_HEIGHT
	local hw = Config.HOTEL_SIZE.X / 2

	local liftX = (side == "east") and (cx + hw - 25) or (cx - hw + 25)
	local liftZ = cz

	local yLow = side == "east" and cy or (cy + fh)
	local yHigh = side == "east" and (cy + fh) or (cy + fh * 2)

	local shaftSize = 16

	-- Shaft walls (4 thin enclosing Parts)
	local midY = (yLow + yHigh) / 2
	local height = yHigh - yLow + 2
	local shaftWalls = {
		{ size = Vector3.new(shaftSize + 2, height, 1), dx = 0, dz = shaftSize / 2 + 0.5 },
		{ size = Vector3.new(shaftSize + 2, height, 1), dx = 0, dz = -(shaftSize / 2 + 0.5) },
		{ size = Vector3.new(1, height, shaftSize), dx = shaftSize / 2 + 0.5, dz = 0 },
		{ size = Vector3.new(1, height, shaftSize), dx = -(shaftSize / 2 + 0.5), dz = 0 },
	}
	for _, sw in ipairs(shaftWalls) do
		local w = Instance.new("Part")
		w.Name = "LiftShaft_" .. side
		w.Size = sw.size
		w.Position = Vector3.new(liftX + sw.dx, midY, liftZ + sw.dz)
		w.Anchored = true
		w.BrickColor = BrickColor.new("Dark stone grey")
		w.Material = Enum.Material.Concrete
		w.Parent = parent
	end

	-- Moving platform
	local platform = Instance.new("Part")
	platform.Name = "LiftPlatform_" .. side
	platform.Size = Vector3.new(shaftSize - 1, 1, shaftSize - 1)
	platform.Position = Vector3.new(liftX, yLow + 0.5, liftZ)
	platform.Anchored = true
	platform.BrickColor = BrickColor.new("Dark grey")
	platform.Material = Enum.Material.SmoothPlastic
	platform.Parent = parent

	addLabel(platform, Enum.NormalId.Top, side == "east" and "LIFT F1 ↔ F2" or "LIFT F2 ↔ F3", Color3.new(1, 1, 0))

	liftCooldowns[platform] = 0
	platform.Destroying:Connect(function()
		liftCooldowns[platform] = nil
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = side == "east" and "Ride to Floor 2 ↑" or "Ride to Floor 3 ↑"
	prompt.ObjectText = "Hotel Lift"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.Parent = platform

	local isAtBottom = true
	local isMoving = false

	-- Shared move logic: moves the platform to the target Y position.
	-- Uses a manual step loop instead of TweenService so that players
	-- standing on the platform are co-moved each frame (TweenService on
	-- an Anchored part does NOT carry passengers).
	local function moveLift(targetIsBottom)
		if isMoving then
			return
		end
		local now = tick()
		if now - liftCooldowns[platform] < Config.LIFT_DEBOUNCE then
			return
		end
		liftCooldowns[platform] = now
		isMoving = true

		local targetY = targetIsBottom and (yLow + 0.5) or (yHigh + 0.5)
		local startY = platform.Position.Y
		local duration = 2 -- seconds (same feel as before)
		local elapsed = 0
		local STEP = 0.05 -- 20 Hz update

		task.spawn(function()
			while elapsed < duration do
				task.wait(STEP)
				elapsed = math.min(elapsed + STEP, duration)
				local t = elapsed / duration
				local newY = startY + (targetY - startY) * t
				local delta = newY - platform.Position.Y
				platform.Position = Vector3.new(liftX, newY, liftZ)

				-- Co-move any players standing on the platform
				for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
					local char = plr.Character
					if char then
						local hrp = char:FindFirstChild("HumanoidRootPart")
						if hrp then
							local rel = hrp.Position - platform.Position
							-- Player is "on" the platform when within the shaft
							-- XZ footprint and within 0–6 studs above the surface.
							if
								math.abs(rel.X) < (shaftSize / 2 - 1)
								and math.abs(rel.Z) < (shaftSize / 2 - 1)
								and rel.Y >= 0
								and rel.Y < 6
							then
								hrp.CFrame = hrp.CFrame + Vector3.new(0, delta, 0)
							end
						end
					end
				end
			end

			-- Final snap to exact position
			platform.Position = Vector3.new(liftX, targetY, liftZ)
			isAtBottom = targetIsBottom
			isMoving = false
			if side == "east" then
				prompt.ActionText = isAtBottom and "Ride to Floor 2 ↑" or "Ride to Floor 1 ↓"
			else
				prompt.ActionText = isAtBottom and "Ride to Floor 3 ↑" or "Ride to Floor 2 ↓"
			end
		end)
	end

	prompt.Triggered:Connect(function()
		moveLift(not isAtBottom)
	end)

	-- -----------------------------------------------------------------------
	-- Call buttons — one per served floor, placed on the shaft's south face
	-- so players can summon the lift without boarding it first.
	-- -----------------------------------------------------------------------
	local floorYs = { yLow, yHigh }
	local floorLabels
	if side == "east" then
		floorLabels = { "CALL ↑ F2", "CALL ↓ F1" }
	else
		floorLabels = { "CALL ↑ F3", "CALL ↓ F2" }
	end

	for fi, floorY in ipairs(floorYs) do
		local btnX = liftX
		local btnZ = liftZ - shaftSize / 2 - 2 -- just outside the south shaft wall
		local btnY = floorY + 1.5

		local btn = Instance.new("Part")
		btn.Name = "LiftCallBtn_" .. side .. "_" .. fi
		btn.Size = Vector3.new(3, 3, 0.5)
		btn.Position = Vector3.new(btnX, btnY, btnZ)
		btn.Anchored = true
		btn.BrickColor = BrickColor.new("Bright yellow")
		btn.Material = Enum.Material.Neon
		btn.CanCollide = false
		btn.Parent = parent
		addLabel(btn, Enum.NormalId.Front, floorLabels[fi], Color3.new(0, 0, 0))

		local callPrompt = Instance.new("ProximityPrompt")
		callPrompt.ActionText = "Call Lift"
		callPrompt.ObjectText = "Elevator"
		callPrompt.MaxActivationDistance = 12
		callPrompt.Parent = btn

		-- Capture fi at closure creation time
		local wantBottom = (fi == 1)
		callPrompt.Triggered:Connect(function()
			if isMoving then
				return -- lift is in transit; ignore until it arrives
			end
			if isAtBottom == wantBottom then
				return -- lift is already at this floor
			end
			moveLift(wantBottom)
		end)
	end
end

-- -------------------------------------------------------------------------
-- Floor slab with arbitrary rectangular openings.
-- openings: array of { xMin, xMax, zMin, zMax } world-space exclusion zones.
-- The function tiles the interior floor area with concrete Parts, skipping
-- any cell that falls entirely within an opening rectangle.
-- -------------------------------------------------------------------------
local function buildSlabWithOpenings(parent, floorIndex, Config, openings)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local slabY = Config.HOTEL_CENTER.Y + floorIndex * Config.FLOOR_HEIGHT
	local interior = Config.HOTEL_SIZE.X - 2 * Config.WALL_THICKNESS -- 340

	local xBound0 = cx - interior / 2
	local xBound1 = cx + interior / 2
	local zBound0 = cz - interior / 2
	local zBound1 = cz + interior / 2

	-- Collect unique X and Z split points from interior bounds + all opening edges
	local xSplits = { xBound0, xBound1 }
	local zSplits = { zBound0, zBound1 }
	for _, o in ipairs(openings) do
		table.insert(xSplits, math.max(xBound0, math.min(xBound1, o.xMin)))
		table.insert(xSplits, math.max(xBound0, math.min(xBound1, o.xMax)))
		table.insert(zSplits, math.max(zBound0, math.min(zBound1, o.zMin)))
		table.insert(zSplits, math.max(zBound0, math.min(zBound1, o.zMax)))
	end

	table.sort(xSplits)
	table.sort(zSplits)

	-- Remove duplicate values within floating-point tolerance
	local function dedup(t)
		local result = { t[1] }
		for i = 2, #t do
			if t[i] - result[#result] > 0.01 then
				table.insert(result, t[i])
			end
		end
		return result
	end
	xSplits = dedup(xSplits)
	zSplits = dedup(zSplits)

	-- Build one concrete Part per non-blocked cell
	for ix = 1, #xSplits - 1 do
		for iz = 1, #zSplits - 1 do
			local cellXMin = xSplits[ix]
			local cellXMax = xSplits[ix + 1]
			local cellZMin = zSplits[iz]
			local cellZMax = zSplits[iz + 1]

			local w = cellXMax - cellXMin
			local d = cellZMax - cellZMin
			if w >= 0.01 and d >= 0.01 then
				local blocked = false
				for _, o in ipairs(openings) do
					if cellXMin >= o.xMin and cellXMax <= o.xMax and cellZMin >= o.zMin and cellZMax <= o.zMax then
						blocked = true
						break
					end
				end

				if not blocked then
					local s = Instance.new("Part")
					s.Name = "Slab" .. floorIndex
					s.Size = Vector3.new(w, 1, d)
					s.Position = Vector3.new((cellXMin + cellXMax) / 2, slabY, (cellZMin + cellZMax) / 2)
					s.Anchored = true
					s.BrickColor = BrickColor.new("Dark stone grey")
					s.Material = Enum.Material.Concrete
					s.Parent = parent
				end
			end
		end
	end
end

-- -------------------------------------------------------------------------
-- Tables with food positions for one floor
-- -------------------------------------------------------------------------
local function buildTablesForFloor(parent, floorIndex, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local floorY = Config.HOTEL_CENTER.Y + (floorIndex - 1) * Config.FLOOR_HEIGHT
	local tableCount = Config.TABLES_PER_FLOOR[floorIndex]
	local radius = 80

	local foodPositions = {}

	-- Chair colours per floor
	local chairColors = {
		BrickColor.new("Bright red"), -- F1
		BrickColor.new("Sand blue"), -- F2
		BrickColor.new("Dark grey"), -- F3
	}
	local chairColor = chairColors[floorIndex]

	for i = 1, tableCount do
		local angle = (math.pi * 2 / tableCount) * i
		local tx = cx + math.cos(angle) * radius
		local tz = cz + math.sin(angle) * radius
		local tableTopY = floorY + 3.5

		local tbl = Instance.new("Part")
		tbl.Name = "Table_F" .. floorIndex .. "_" .. i
		tbl.Size = Vector3.new(6, 3, 6)
		tbl.Position = Vector3.new(tx, floorY + 2, tz)
		tbl.Anchored = true
		tbl.BrickColor = TABLE_COLORS[floorIndex]
		tbl.Material = Enum.Material.Wood
		tbl.Parent = parent

		-- Four chairs around the table (N/S/E/W at 5-stud offset from centre)
		local chairOffsets = {
			Vector3.new(0, 0, 5),
			Vector3.new(0, 0, -5),
			Vector3.new(5, 0, 0),
			Vector3.new(-5, 0, 0),
		}
		for ci, offset in ipairs(chairOffsets) do
			-- Seat
			local seat = Instance.new("Part")
			seat.Name = "Chair_F" .. floorIndex .. "_" .. i .. "_" .. ci
			seat.Size = Vector3.new(2.5, 0.4, 2.5)
			seat.Position = Vector3.new(tx + offset.X, floorY + 2.2, tz + offset.Z)
			seat.Anchored = true
			seat.BrickColor = chairColor
			seat.Material = Enum.Material.SmoothPlastic
			seat.Parent = parent
			-- Back — pushed 1.1 studs further from the table centre
			-- The offset vector points away from the table; we push the back
			-- in the same direction so it sits behind the seat.
			local backOffsetX = offset.X ~= 0 and (offset.X / math.abs(offset.X) * 1.1) or 0
			local backOffsetZ = offset.Z ~= 0 and (offset.Z / math.abs(offset.Z) * 1.1) or 0
			local back = Instance.new("Part")
			back.Name = "ChairBack_F" .. floorIndex .. "_" .. i .. "_" .. ci
			back.Size = Vector3.new(2.5, 2.5, 0.3)
			back.Position = Vector3.new(tx + offset.X + backOffsetX, floorY + 3.45, tz + offset.Z + backOffsetZ)
			back.Anchored = true
			back.BrickColor = chairColor
			back.Material = Enum.Material.SmoothPlastic
			back.Parent = parent
		end

		local foodType = Config.FOOD_TYPES[((i - 1) % #Config.FOOD_TYPES) + 1]
		local foodPos = Vector3.new(tx, tableTopY + foodType.size.Y / 2 + 0.1, tz)
		table.insert(foodPositions, { position = foodPos, foodType = foodType })
	end

	return foodPositions
end

-- -------------------------------------------------------------------------
-- Bar counter — a long L-shaped counter for the restaurant feel.
-- Placed on each floor near the east interior wall.
-- -------------------------------------------------------------------------
local function buildBarCounter(parent, floorIndex, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local floorY = Config.HOTEL_CENTER.Y + (floorIndex - 1) * Config.FLOOR_HEIGHT
	local hw = Config.HOTEL_SIZE.X / 2 - Config.WALL_THICKNESS -- inner edge

	-- Main bar (runs north–south)
	local barX = cx + hw - 20
	local barZ = cz
	local barMain = Instance.new("Part")
	barMain.Name = "BarCounter_F" .. floorIndex
	barMain.Size = Vector3.new(4, 4, 60)
	barMain.Position = Vector3.new(barX, floorY + 2.5, barZ)
	barMain.Anchored = true
	barMain.BrickColor = BrickColor.new("Dark orange")
	barMain.Material = Enum.Material.Wood
	barMain.Parent = parent
	addLabel(barMain, Enum.NormalId.Left, "BAR", Color3.new(1, 1, 1))

	-- Bar top surface (slightly lighter)
	local top = Instance.new("Part")
	top.Name = "BarTop_F" .. floorIndex
	top.Size = Vector3.new(4.2, 0.4, 60.2)
	top.Position = Vector3.new(barX, floorY + 4.7, barZ)
	top.Anchored = true
	top.BrickColor = BrickColor.new("Reddish brown")
	top.Material = Enum.Material.Wood
	top.Parent = parent
end

-- -------------------------------------------------------------------------
-- Wall paintings — adds decorative picture frames on the interior walls.
-- -------------------------------------------------------------------------
local function buildWallPaintings(parent, floorIndex, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local floorY = Config.HOTEL_CENTER.Y + (floorIndex - 1) * Config.FLOOR_HEIGHT
	local rz = Config.HOTEL_SIZE.Z
	local paintingY = floorY + Config.FLOOR_HEIGHT * 0.6

	-- Painting colours by floor theme
	local paintColors = {
		{ BrickColor.new("Bright blue"), BrickColor.new("Bright green"), BrickColor.new("Bright yellow") },
		{ BrickColor.new("Sand red"), BrickColor.new("Medium orange"), BrickColor.new("Pastel blue") },
		{ BrickColor.new("Dark purple"), BrickColor.new("Sand blue"), BrickColor.new("Dark red") },
	}
	local colors = paintColors[floorIndex]

	local paintings = {
		{ x = cx - 80, z = cz + rz / 2 - 3, rotY = 0 },
		{ x = cx, z = cz + rz / 2 - 3, rotY = 0 },
		{ x = cx + 80, z = cz + rz / 2 - 3, rotY = 0 },
	}

	for pi, p in ipairs(paintings) do
		-- Frame
		local frame = Instance.new("Part")
		frame.Name = "Painting_F" .. floorIndex .. "_" .. pi
		frame.Size = Vector3.new(12, 8, 0.4)
		frame.Position = Vector3.new(p.x, paintingY, p.z)
		frame.Anchored = true
		frame.BrickColor = BrickColor.new("Dark grey")
		frame.Material = Enum.Material.Wood
		frame.Parent = parent
		-- Canvas
		local canvas = Instance.new("Part")
		canvas.Name = "Canvas_F" .. floorIndex .. "_" .. pi
		canvas.Size = Vector3.new(10, 6, 0.3)
		canvas.Position = Vector3.new(p.x, paintingY, p.z - 0.1)
		canvas.Anchored = true
		canvas.BrickColor = colors[pi] or colors[1]
		canvas.Material = Enum.Material.SmoothPlastic
		canvas.Parent = parent
	end
end

-- -------------------------------------------------------------------------
-- Entrance path — a stone walkway leading south from the main door.
-- -------------------------------------------------------------------------
local function buildEntrancePath(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local rz = Config.HOTEL_SIZE.Z

	local startZ = cz - rz / 2 - 5
	local endZ = startZ - 80
	local segCount = 8
	local segLen = (startZ - endZ) / segCount

	for i = 0, segCount - 1 do
		local seg = Instance.new("Part")
		seg.Name = "EntrancePath_" .. i
		seg.Size = Vector3.new(18, 0.5, segLen - 0.5)
		seg.Position = Vector3.new(cx, 0.25, startZ - i * segLen - segLen / 2)
		seg.Anchored = true
		seg.BrickColor = BrickColor.new("Light stone grey")
		seg.Material = Enum.Material.Cobblestone
		seg.Parent = parent
	end
end

-- -------------------------------------------------------------------------
-- Decorative river — a wide blue Part running east–west to the south.
-- -------------------------------------------------------------------------
local function buildRiver(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local rz = Config.HOTEL_SIZE.Z

	local river = Instance.new("Part")
	river.Name = "River"
	river.Size = Vector3.new(1000, 0.4, 30)
	river.Position = Vector3.new(cx, 0.2, cz - rz / 2 - 150)
	river.Anchored = true
	river.BrickColor = BrickColor.new("Bright blue")
	river.Material = Enum.Material.Foil
	river.Transparency = 0.35
	river.CanCollide = false
	river.Parent = parent
end

-- -------------------------------------------------------------------------
-- Gentle hill ramps — pairs of wedge-shaped Parts on both sides of the
-- entrance path to give the terrain a sculpted feel.
-- -------------------------------------------------------------------------
local function buildHills(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local rz = Config.HOTEL_SIZE.Z
	local baseZ = cz - rz / 2 - 40

	local hillData = {
		{ dx = -140, dz = 0, sx = 60, sz = 80, h = 18 },
		{ dx = 140, dz = 0, sx = 60, sz = 80, h = 18 },
		{ dx = -200, dz = -50, sx = 80, sz = 60, h = 12 },
		{ dx = 200, dz = -50, sx = 80, sz = 60, h = 12 },
	}

	for _, hd in ipairs(hillData) do
		local hill = Instance.new("Part")
		hill.Name = "Hill"
		hill.Size = Vector3.new(hd.sx, hd.h, hd.sz)
		hill.Position = Vector3.new(cx + hd.dx, hd.h / 2, baseZ + hd.dz)
		hill.Anchored = true
		hill.BrickColor = BrickColor.new("Earth green")
		hill.Material = Enum.Material.Grass
		hill.Parent = parent
	end
end
local function buildLobby(parent, cx, cy, cz)
	local carpet = Instance.new("Part")
	carpet.Name = "Carpet"
	carpet.Size = Vector3.new(200, 0.2, 200)
	carpet.Position = Vector3.new(cx, cy + 0.6, cz)
	carpet.Anchored = true
	carpet.BrickColor = BrickColor.new("Bright red")
	carpet.Material = Enum.Material.Fabric
	carpet.Transparency = 0.1
	carpet.CanCollide = false
	carpet.Parent = parent

	local desk = Instance.new("Part")
	desk.Name = "ReceptionDesk"
	desk.Size = Vector3.new(20, 3, 8)
	desk.Position = Vector3.new(cx, cy + 2, cz + 40)
	desk.Anchored = true
	desk.BrickColor = BrickColor.new("Dark orange")
	desk.Material = Enum.Material.Wood
	desk.Parent = parent
	addLabel(desk, Enum.NormalId.Front, "RECEPTION", Color3.new(1, 1, 1))

	local plantCorners = {
		Vector3.new(cx - 60, cy, cz - 60),
		Vector3.new(cx + 60, cy, cz - 60),
		Vector3.new(cx - 60, cy, cz + 60),
		Vector3.new(cx + 60, cy, cz + 60),
	}
	for _, pos in ipairs(plantCorners) do
		local pot = Instance.new("Part")
		pot.Shape = Enum.PartType.Cylinder
		pot.Size = Vector3.new(3, 3, 3)
		pot.Position = pos + Vector3.new(0, 1.5, 0)
		pot.Anchored = true
		pot.BrickColor = BrickColor.new("Reddish brown")
		pot.Material = Enum.Material.SmoothPlastic
		pot.Parent = parent

		local plant = Instance.new("Part")
		plant.Shape = Enum.PartType.Ball
		plant.Size = Vector3.new(5, 5, 5)
		plant.Position = pos + Vector3.new(0, 5.5, 0)
		plant.Anchored = true
		plant.BrickColor = BrickColor.new("Bright green")
		plant.Material = Enum.Material.Grass
		plant.Parent = parent
	end
end

-- -------------------------------------------------------------------------
-- Decorative tree at a given world position
-- -------------------------------------------------------------------------
local function buildTree(parent, position)
	local trunk = Instance.new("Part")
	trunk.Name = "TreeTrunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(8, 3, 3)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored = true
	trunk.BrickColor = BrickColor.new("Reddish brown")
	trunk.Material = Enum.Material.Wood
	trunk.Parent = parent

	local foliage = Instance.new("Part")
	foliage.Name = "TreeFoliage"
	foliage.Shape = Enum.PartType.Ball
	foliage.Size = Vector3.new(14, 14, 14)
	foliage.Position = position + Vector3.new(0, 12, 0)
	foliage.Anchored = true
	foliage.BrickColor = BrickColor.new("Bright green")
	foliage.Material = Enum.Material.Grass
	foliage.Parent = parent
end

-- -------------------------------------------------------------------------
-- Exterior staircase on the east wall — 16 stone steps from ground to F2
-- -------------------------------------------------------------------------
local function buildExteriorStaircase(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cy = Config.HOTEL_CENTER.Y
	local cz = Config.HOTEL_CENTER.Z
	local hw = Config.HOTEL_SIZE.X / 2 -- 175; east wall world X = cx + hw

	local STEP_COUNT = 16
	local STEP_HEIGHT = 1.6 -- 16 × 1.6 = 25.6 ≈ one floor height
	local STEP_DEPTH = 3 -- each step protrudes 3 studs outward (east)
	local STEP_WIDTH = 8 -- staircase width (Z axis)
	local STAIR_Z = cz - 40 -- south side of east wall

	-- Stone steps, each one deeper and higher than the last
	for i = 1, STEP_COUNT do
		local step = Instance.new("Part")
		step.Name = "ExtStep_" .. i
		step.Size = Vector3.new(STEP_DEPTH, STEP_HEIGHT, STEP_WIDTH)
		step.Anchored = true
		step.CanCollide = true
		step.BrickColor = BrickColor.new("Medium stone grey")
		step.Material = Enum.Material.SmoothPlastic
		-- Each step is one STEP_DEPTH east of the wall and rises STEP_HEIGHT per step.
		-- Positioning: centre X = wall face + i * STEP_DEPTH - STEP_DEPTH/2
		step.Position = Vector3.new(cx + hw + (i - 0.5) * STEP_DEPTH, cy + (i - 0.5) * STEP_HEIGHT, STAIR_Z)
		step.Parent = parent

		-- Subtle step light for night visibility
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Top
		light.Brightness = 0.8
		light.Range = 5
		light.Parent = step
	end

	-- Landing platform at the top, flush with the east wall at Floor 2 height
	local landing = Instance.new("Part")
	landing.Name = "ExtStairLanding"
	landing.Size = Vector3.new(STEP_DEPTH * 2, 1, STEP_WIDTH)
	landing.Anchored = true
	landing.CanCollide = true
	landing.BrickColor = BrickColor.new("Medium stone grey")
	landing.Material = Enum.Material.Concrete
	landing.Position = Vector3.new(cx + hw + STEP_DEPTH, cy + Config.FLOOR_HEIGHT + 0.5, STAIR_Z)
	landing.Parent = parent

	-- Neon yellow railings on both Z sides (matches interior staircase style)
	local totalLength = STEP_DEPTH * STEP_COUNT
	for _, zOff in ipairs({ -STEP_WIDTH / 2 + 0.3, STEP_WIDTH / 2 - 0.3 }) do
		local rail = Instance.new("Part")
		rail.Name = "ExtRail"
		rail.Size = Vector3.new(totalLength, 0.3, 0.3)
		rail.Anchored = true
		rail.CanCollide = false
		rail.BrickColor = BrickColor.new("Bright yellow")
		rail.Material = Enum.Material.Neon
		-- Centre the railing horizontally along the staircase and tilt to match slope
		rail.CFrame = CFrame.new(cx + hw + totalLength / 2, cy + Config.FLOOR_HEIGHT / 2 + 1.5, STAIR_Z + zOff)
			* CFrame.Angles(0, 0, -math.atan(STEP_HEIGHT / STEP_DEPTH))
		rail.Parent = parent
	end
end

-- -------------------------------------------------------------------------
-- Trees scattered around the outside of the restaurant
-- -------------------------------------------------------------------------
local function buildRestaurantTrees(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	local hw = Config.HOTEL_SIZE.X / 2 + 30 -- outside the walls

	-- 12 trees evenly spaced in a ring around the restaurant
	for i = 1, 12 do
		local angle = (math.pi * 2 / 12) * i
		local tx = cx + math.cos(angle) * hw
		local tz = cz + math.sin(angle) * hw
		buildTree(parent, Vector3.new(tx, 0.5, tz))
	end
end

-- -------------------------------------------------------------------------
-- World-wide tree scatter — avoids hotel footprint and safe base area
-- -------------------------------------------------------------------------
local function buildWorldTrees(parent, Config)
	local cx = Config.HOTEL_CENTER.X
	local cz = Config.HOTEL_CENTER.Z
	-- Hotel half-extents with a buffer
	local hotelHalfX = Config.HOTEL_SIZE.X / 2 + 20
	local hotelHalfZ = Config.HOTEL_SIZE.Z / 2 + 20
	-- Safe base X starts at 450; keep trees away from it
	local baseMinX = 430

	local MAP_HALF = 450 -- place trees within this square

	local rng = Random.new(12345) -- fixed seed for deterministic placement
	local placed = 0
	local attempts = 0
	while placed < 40 and attempts < 500 do
		attempts = attempts + 1
		local tx = rng:NextNumber(-MAP_HALF, MAP_HALF)
		local tz = rng:NextNumber(-MAP_HALF, MAP_HALF)
		-- Skip hotel footprint and base area
		local inHotel = math.abs(tx - cx) < hotelHalfX and math.abs(tz - cz) < hotelHalfZ
		if not inHotel and tx <= baseMinX then
			buildTree(parent, Vector3.new(tx, 0.5, tz))
			placed = placed + 1
		end
	end
end

-- -------------------------------------------------------------------------
-- Main build entry point
-- -------------------------------------------------------------------------
function RestaurantBuilder.build(Config)
	buildGround(Config)

	local cx = Config.HOTEL_CENTER.X
	local cy = Config.HOTEL_CENTER.Y
	local cz = Config.HOTEL_CENTER.Z
	local rx = Config.HOTEL_SIZE.X -- 350
	local rz = Config.HOTEL_SIZE.Z -- 350
	local wt = Config.WALL_THICKNESS -- 5
	local fh = Config.FLOOR_HEIGHT -- 25
	local totalH = fh * Config.FLOOR_COUNT -- 75

	local hotel = Instance.new("Model")
	hotel.Name = "GrandHotel"
	hotel.Parent = workspace

	-- Ground floor slab
	local groundFloor = Instance.new("Part")
	groundFloor.Name = "GroundFloor"
	groundFloor.Size = Vector3.new(rx, 1, rz)
	groundFloor.Position = Vector3.new(cx, cy, cz)
	groundFloor.Anchored = true
	groundFloor.BrickColor = BrickColor.new("Light stone grey")
	groundFloor.Material = Enum.Material.Concrete
	groundFloor.Parent = hotel

	local function makeWall(name, size, pos)
		local w = Instance.new("Part")
		w.Name = name
		w.Size = size
		w.Position = Vector3.new(cx + pos.X, cy + pos.Y, cz + pos.Z)
		w.Anchored = true
		w.BrickColor = BrickColor.new("White")
		w.Material = Enum.Material.Concrete
		w.Parent = hotel
		return w
	end

	-- Perimeter walls (full hotel height)
	makeWall("NorthWall", Vector3.new(rx, totalH, wt), Vector3.new(0, totalH / 2, rz / 2))

	local doorW = 20
	local sideLen = (rx - doorW) / 2
	makeWall(
		"SouthWallLeft",
		Vector3.new(sideLen, totalH, wt),
		Vector3.new(-(rx / 2 - sideLen / 2), totalH / 2, -rz / 2)
	)
	makeWall("SouthWallRight", Vector3.new(sideLen, totalH, wt), Vector3.new(rx / 2 - sideLen / 2, totalH / 2, -rz / 2))
	makeWall("SouthDoorLintel", Vector3.new(doorW, totalH - 22, wt), Vector3.new(0, (totalH + 22) / 2, -rz / 2))

	local sideZ = (rz - doorW) / 2
	makeWall("EastWallN", Vector3.new(wt, totalH, sideZ), Vector3.new(rx / 2, totalH / 2, rz / 2 - sideZ / 2))
	makeWall("EastWallS", Vector3.new(wt, totalH, sideZ), Vector3.new(rx / 2, totalH / 2, -(rz / 2 - sideZ / 2)))
	makeWall("EastDoorLintel", Vector3.new(wt, totalH - 22, doorW), Vector3.new(rx / 2, (totalH + 22) / 2, 0))

	makeWall("WestWallN", Vector3.new(wt, totalH, sideZ), Vector3.new(-rx / 2, totalH / 2, rz / 2 - sideZ / 2))
	makeWall("WestWallS", Vector3.new(wt, totalH, sideZ), Vector3.new(-rx / 2, totalH / 2, -(rz / 2 - sideZ / 2)))
	makeWall("WestDoorLintel", Vector3.new(wt, totalH - 22, doorW), Vector3.new(-rx / 2, (totalH + 22) / 2, 0))

	-- Windows: one row per floor per wall
	for f = 1, Config.FLOOR_COUNT do
		local windowY = cy + (f - 1) * fh + fh * 0.6
		buildWindowRow(hotel, cx, cz + rz / 2, rx, windowY, true) -- north
		buildWindowRow(hotel, cx, cz - rz / 2, rx, windowY, true) -- south
		buildWindowRow(hotel, cx + rx / 2, cz, rz, windowY, false) -- east
		buildWindowRow(hotel, cx - rx / 2, cz, rz, windowY, false) -- west
	end

	-- Ground floor entry doors
	createHotelDoor(Vector3.new(cx, cy + 11, cz - rz / 2), 0, hotel, "MainDoor", Config.DOOR_DEBOUNCE)
	createHotelDoor(Vector3.new(cx + rx / 2, cy + 11, cz), 90, hotel, "EastDoor", Config.DOOR_DEBOUNCE)
	createHotelDoor(Vector3.new(cx - rx / 2, cy + 11, cz), 270, hotel, "WestDoor", Config.DOOR_DEBOUNCE)

	-- Hotel sign
	local sign = Instance.new("Part")
	sign.Name = "HotelSign"
	sign.Size = Vector3.new(60, 14, 1)
	sign.Position = Vector3.new(cx, cy + totalH - 8, cz - rz / 2 - 3)
	sign.Anchored = true
	sign.BrickColor = BrickColor.new("Bright yellow")
	sign.Material = Enum.Material.Neon
	sign.Parent = hotel
	addLabel(sign, Enum.NormalId.Front, "GRAND HOTEL\nSteal the Food!", Color3.new(0, 0, 0))

	-- Floor difficulty signs (exterior south wall)
	local floorLabels = { "FLOOR 1 — EASY", "FLOOR 2 — MEDIUM", "FLOOR 3 — HARD" }
	local floorColors = { Color3.new(0.2, 1, 0.2), Color3.new(1, 1, 0), Color3.new(1, 0.2, 0.2) }
	for f = 1, Config.FLOOR_COUNT do
		local fs = Instance.new("Part")
		fs.Size = Vector3.new(22, 4, 0.3)
		fs.Position = Vector3.new(cx, cy + (f - 1) * fh + fh / 2, cz - rz / 2 - 1)
		fs.Anchored = true
		fs.BrickColor = BrickColor.new("Black")
		fs.Material = Enum.Material.SmoothPlastic
		fs.Parent = hotel
		addLabel(fs, Enum.NormalId.Front, floorLabels[f], floorColors[f])
	end

	-- Lobby
	buildLobby(hotel, cx, cy + 0.5, cz)

	-- -----------------------------------------------------------------------
	-- Interior floor slabs with openings for the lift shaft AND the staircase.
	-- The staircase constants must match the buildStaircase calls below.
	-- -----------------------------------------------------------------------
	local liftShaftHW = 9 -- half-width of shaft opening (shaftSize/2 + 1 = 9)
	local hw = rx / 2
	local liftEX = cx + hw - 25 -- east lift world X
	local liftWX = cx - hw + 25 -- west lift world X
	local stairStepWidth = 12
	local stairMargin = 2 -- slab cutout margin beyond the step footprint

	-- F1→F2 staircase: starts at (cx-50, cz+130) heading east, travels STAIR_TRAVEL studs
	local s12xMin = cx - 50 - stairMargin
	local s12xMax = cx - 50 + STAIR_TRAVEL + stairMargin
	local s12zMin = cz + 130 - stairStepWidth / 2 - stairMargin
	local s12zMax = cz + 130 + stairStepWidth / 2 + stairMargin

	-- F2→F3 staircase: starts at (cx+50, cz-130) heading west, travels STAIR_TRAVEL studs
	local s23xMin = cx + 50 - STAIR_TRAVEL - stairMargin
	local s23xMax = cx + 50 + stairMargin
	local s23zMin = cz - 130 - stairStepWidth / 2 - stairMargin
	local s23zMax = cz - 130 + stairStepWidth / 2 + stairMargin

	buildSlabWithOpenings(hotel, 1, Config, {
		-- Lift shaft (east, F1↔F2)
		{ xMin = liftEX - liftShaftHW, xMax = liftEX + liftShaftHW, zMin = cz - liftShaftHW, zMax = cz + liftShaftHW },
		-- Staircase opening (F1→F2)
		{ xMin = s12xMin, xMax = s12xMax, zMin = s12zMin, zMax = s12zMax },
	})
	buildSlabWithOpenings(hotel, 2, Config, {
		-- Lift shaft (west, F2↔F3)
		{ xMin = liftWX - liftShaftHW, xMax = liftWX + liftShaftHW, zMin = cz - liftShaftHW, zMax = cz + liftShaftHW },
		-- Staircase opening (F2→F3)
		{ xMin = s23xMin, xMax = s23xMax, zMin = s23zMin, zMax = s23zMax },
	})

	-- Lifts
	buildLift(hotel, Config, "east") -- F1 ↔ F2
	buildLift(hotel, Config, "west") -- F2 ↔ F3

	-- Lift entrance corridor doors
	createFloorDoor(Vector3.new(liftEX, cy + fh + 10, cz - 8), 0, hotel, "LiftDoor_F1E", Config.DOOR_DEBOUNCE)
	createFloorDoor(Vector3.new(liftWX, cy + fh * 2 + 10, cz - 8), 0, hotel, "LiftDoor_F2W", Config.DOOR_DEBOUNCE)

	-- Decorative trees around the restaurant exterior
	buildRestaurantTrees(hotel, Config)

	-- Exterior staircase on the east wall (ground → Floor 2)
	buildExteriorStaircase(hotel, Config)

	-- Tables and food spawn positions per floor
	local floorFoodPositions = {}
	for f = 1, Config.FLOOR_COUNT do
		floorFoodPositions[f] = buildTablesForFloor(hotel, f, Config)
	end

	-- Per-floor restaurant decoration: bar counter + wall paintings
	for f = 1, Config.FLOOR_COUNT do
		buildBarCounter(hotel, f, Config)
		buildWallPaintings(hotel, f, Config)
	end

	-- Indoor ceiling lighting (keeps interior bright at night)
	buildIndoorLighting(hotel, Config)

	-- Lobby light-switch (toggles all indoor lights on/off)
	buildLightSwitch(hotel, Config)

	-- Staircases along interior walls between floors.
	-- STEP_COUNT=12, STEP_HEIGHT=2 → 24-stud climb; fits within FLOOR_HEIGHT=25.
	-- The floor slabs above have matching cutouts so players can pass through.

	-- F1 → F2: north interior area, heading east (+X direction)
	buildStaircase(
		hotel,
		"Stairs_F1_F2",
		cx - 50, -- startX (west end)
		cy + 0.5, -- startY (F1 floor surface)
		cz + 130, -- startZ (near north interior wall)
		1, -- dirX = +1 → ascending eastward
		stairStepWidth -- step width in Z
	)

	-- F2 → F3: south interior area, heading west (−X direction)
	buildStaircase(
		hotel,
		"Stairs_F2_F3",
		cx + 50, -- startX (east end)
		cy + fh + 0.5, -- startY (F2 floor surface)
		cz - 130, -- startZ (near south interior wall)
		-1, -- dirX = −1 → ascending westward
		stairStepWidth -- step width in Z
	)

	-- Parkour platforms and jump pads between floors
	buildParkourElements(hotel, Config)

	-- Exterior: entrance path, river, hills
	buildEntrancePath(hotel, Config)
	buildRiver(hotel, Config)
	buildHills(hotel, Config)

	-- Trees: ring around hotel + scattered across the wider map
	buildRestaurantTrees(hotel, Config)
	buildWorldTrees(hotel, Config)

	return hotel, floorFoodPositions
end

return RestaurantBuilder
