-- RestaurantBuilder.lua
-- Builds the world ground and the 3-floor Grand Hotel.
-- Returns: hotel (Model), floorFoodPositions (table[floor][i] = {position, foodType})

local TweenService = game:GetService("TweenService")

local RestaurantBuilder = {}

-- Door debounce timestamps (keyed by Part; cleaned up when door is destroyed)
local doorCooldowns = {}

-- Lift debounce timestamps (keyed by Platform Part)
local liftCooldowns = {}

-- Table colours per floor (module-level constant)
local TABLE_COLORS = {
	BrickColor.new("Dark orange"),    -- Floor 1
	BrickColor.new("Reddish brown"),  -- Floor 2
	BrickColor.new("Black"),          -- Floor 3
}

-- -------------------------------------------------------------------------
-- Ground / Baseplate
-- -------------------------------------------------------------------------
local function buildGround(Config)
	local ground = Instance.new("Part")
	ground.Name       = "Ground"
	ground.Size       = Config.GROUND_SIZE
	ground.Position   = Vector3.new(0, -Config.GROUND_SIZE.Y / 2, 0)
	ground.Anchored   = true
	ground.BrickColor = BrickColor.new("Bright green")
	ground.Material   = Enum.Material.Grass
	ground.Parent     = workspace
end

-- -------------------------------------------------------------------------
-- SurfaceGui label helper
-- -------------------------------------------------------------------------
local function addLabel(part, face, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face   = face
	gui.Parent = part
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, 0, 1, 0)
	lbl.Text                   = text
	lbl.TextColor3             = textColor or Color3.new(1, 1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.SourceSansBold
	lbl.Parent                 = gui
	return lbl
end

-- -------------------------------------------------------------------------
-- Hotel doors (ground floor entry)
-- -------------------------------------------------------------------------
local function createHotelDoor(position, rotation, parent, doorName, debounceTime)
	local door = Instance.new("Part")
	door.Name       = doorName
	door.Size       = Vector3.new(20, 22, 1)
	door.Anchored   = true
	door.BrickColor = BrickColor.new("Dark orange")
	door.Material   = Enum.Material.WoodPlanks
	door.CFrame     = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	door.Parent     = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Open Door"
	prompt.ObjectText            = "Hotel Door"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.MaxActivationDistance = 15
	prompt.Parent                = door

	local doorOpen = false
	doorCooldowns[door] = 0
	door.Destroying:Connect(function()
		doorCooldowns[door] = nil
	end)

	prompt.Triggered:Connect(function()
		local now = tick()
		if now - doorCooldowns[door] < debounceTime then return end
		doorCooldowns[door] = now

		doorOpen          = not doorOpen
		door.CanCollide   = not doorOpen
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
	door.Name       = doorName
	door.Size       = Vector3.new(14, 20, 1)
	door.Anchored   = true
	door.BrickColor = BrickColor.new("Medium stone grey")
	door.Material   = Enum.Material.Metal
	door.CFrame     = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	door.Parent     = parent

	addLabel(door, Enum.NormalId.Front, "LIFT", Color3.new(1, 1, 0))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Open Lift Door"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.Parent                = door

	local doorOpen = false
	doorCooldowns[door] = 0
	door.Destroying:Connect(function()
		doorCooldowns[door] = nil
	end)

	prompt.Triggered:Connect(function()
		local now = tick()
		if now - doorCooldowns[door] < debounceTime then return end
		doorCooldowns[door] = now

		doorOpen          = not doorOpen
		door.CanCollide   = not doorOpen
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
	local spacing     = wallLength / (windowCount + 1)

	for i = 1, windowCount do
		local offset = -wallLength / 2 + spacing * i

		local win = Instance.new("Part")
		win.Name         = "Window"
		win.Anchored     = true
		win.BrickColor   = BrickColor.new("Cyan")
		win.Material     = Enum.Material.Glass
		win.Transparency = 0.4
		win.CanCollide   = false
		win.Parent       = parent

		if isNS then
			win.Size     = Vector3.new(10, 8, 0.3)
			win.Position = Vector3.new(wallCenterX + offset, windowY, wallCenterZ)
		else
			win.Size     = Vector3.new(0.3, 8, 10)
			win.Position = Vector3.new(wallCenterX, windowY, wallCenterZ + offset)
		end
	end
end

-- -------------------------------------------------------------------------
-- Lift system: TweenService Platform moving between two floors
-- side: "east" (F1↔F2) or "west" (F2↔F3)
-- -------------------------------------------------------------------------
local function buildLift(parent, Config, side)
	local cx  = Config.HOTEL_CENTER.X
	local cz  = Config.HOTEL_CENTER.Z
	local cy  = Config.HOTEL_CENTER.Y
	local fh  = Config.FLOOR_HEIGHT
	local hw  = Config.HOTEL_SIZE.X / 2

	local liftX = (side == "east") and (cx + hw - 25) or (cx - hw + 25)
	local liftZ = cz

	local yLow  = side == "east" and cy           or (cy + fh)
	local yHigh = side == "east" and (cy + fh)    or (cy + fh * 2)

	local shaftSize = 16

	-- Shaft walls (4 thin enclosing Parts)
	local midY   = (yLow + yHigh) / 2
	local height = yHigh - yLow + 2
	local shaftWalls = {
		{ size = Vector3.new(shaftSize + 2, height, 1), dx = 0,                 dz = shaftSize / 2 + 0.5 },
		{ size = Vector3.new(shaftSize + 2, height, 1), dx = 0,                 dz = -(shaftSize / 2 + 0.5) },
		{ size = Vector3.new(1, height, shaftSize),     dx = shaftSize / 2 + 0.5, dz = 0 },
		{ size = Vector3.new(1, height, shaftSize),     dx = -(shaftSize / 2 + 0.5), dz = 0 },
	}
	for _, sw in ipairs(shaftWalls) do
		local w = Instance.new("Part")
		w.Name      = "LiftShaft_" .. side
		w.Size      = sw.size
		w.Position  = Vector3.new(liftX + sw.dx, midY, liftZ + sw.dz)
		w.Anchored  = true
		w.BrickColor = BrickColor.new("Dark stone grey")
		w.Material  = Enum.Material.Concrete
		w.Parent    = parent
	end

	-- Moving platform
	local platform = Instance.new("Part")
	platform.Name      = "LiftPlatform_" .. side
	platform.Size      = Vector3.new(shaftSize - 1, 1, shaftSize - 1)
	platform.Position  = Vector3.new(liftX, yLow + 0.5, liftZ)
	platform.Anchored  = true
	platform.BrickColor = BrickColor.new("Dark grey")
	platform.Material  = Enum.Material.SmoothPlastic
	platform.Parent    = parent

	addLabel(platform, Enum.NormalId.Top,
		side == "east" and "LIFT F1 ↔ F2" or "LIFT F2 ↔ F3",
		Color3.new(1, 1, 0))

	liftCooldowns[platform] = 0
	platform.Destroying:Connect(function()
		liftCooldowns[platform] = nil
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = side == "east" and "Ride to Floor 2 ↑" or "Ride to Floor 3 ↑"
	prompt.ObjectText            = "Hotel Lift"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.Parent                = platform

	local isAtBottom = true
	local isMoving   = false

	prompt.Triggered:Connect(function()
		if isMoving then return end
		local now = tick()
		if now - liftCooldowns[platform] < Config.LIFT_DEBOUNCE then return end
		liftCooldowns[platform] = now
		isMoving = true

		local targetY = isAtBottom and (yHigh + 0.5) or (yLow + 0.5)
		local tween = TweenService:Create(
			platform,
			TweenInfo.new(2, Enum.EasingStyle.Linear),
			{ Position = Vector3.new(liftX, targetY, liftZ) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			isAtBottom = not isAtBottom
			isMoving   = false
			if side == "east" then
				prompt.ActionText = isAtBottom and "Ride to Floor 2 ↑" or "Ride to Floor 1 ↓"
			else
				prompt.ActionText = isAtBottom and "Ride to Floor 3 ↑" or "Ride to Floor 2 ↓"
			end
		end)
	end)
end

-- -------------------------------------------------------------------------
-- Floor slab with lift shaft hole (3-Part arrangement around 18×18 opening)
-- -------------------------------------------------------------------------
local function buildFloorSlab(parent, floorIndex, Config, liftSide)
	local cx       = Config.HOTEL_CENTER.X
	local cz       = Config.HOTEL_CENTER.Z
	local slabY    = Config.HOTEL_CENTER.Y + floorIndex * Config.FLOOR_HEIGHT
	local interior = Config.HOTEL_SIZE.X - 2 * Config.WALL_THICKNESS  -- 340
	local hw       = Config.HOTEL_SIZE.X / 2
	local shaftW   = 18

	local liftX      = (liftSide == "east") and (cx + hw - 25) or (cx - hw + 25)
	local shaftCX    = liftX   -- world X center of shaft
	local shaftCZ    = cz

	-- Slab as 3 rows: left strip (full Z), right strip (full Z), middle column minus shaft hole
	local leftEdge  = cx - interior / 2
	local rightEdge = cx + interior / 2
	local leftW  = shaftCX - shaftW / 2 - leftEdge
	local rightW = rightEdge - (shaftCX + shaftW / 2)
	local midW   = shaftW

	local function makeSlab(name, size, wx, wz)
		local s = Instance.new("Part")
		s.Name      = name
		s.Size      = size
		s.Position  = Vector3.new(wx, slabY, wz)
		s.Anchored  = true
		s.BrickColor = BrickColor.new("Dark stone grey")
		s.Material  = Enum.Material.Concrete
		s.Parent    = parent
	end

	-- Left column (all Z)
	makeSlab("Slab"..floorIndex.."_Left",
		Vector3.new(leftW, 1, interior),
		leftEdge + leftW / 2, cz)

	-- Right column (all Z)
	makeSlab("Slab"..floorIndex.."_Right",
		Vector3.new(rightW, 1, interior),
		rightEdge - rightW / 2, cz)

	-- Middle column: two halves in Z (gap = shaftW wide in Z, centred on shaftCZ)
	local halfZ = (interior - shaftW) / 2
	makeSlab("Slab"..floorIndex.."_MidS",
		Vector3.new(midW, 1, halfZ),
		shaftCX, shaftCZ - shaftW / 2 - halfZ / 2)
	makeSlab("Slab"..floorIndex.."_MidN",
		Vector3.new(midW, 1, halfZ),
		shaftCX, shaftCZ + shaftW / 2 + halfZ / 2)
end

-- -------------------------------------------------------------------------
-- Tables with food positions for one floor
-- -------------------------------------------------------------------------
local function buildTablesForFloor(parent, floorIndex, Config)
	local cx         = Config.HOTEL_CENTER.X
	local cz         = Config.HOTEL_CENTER.Z
	local floorY     = Config.HOTEL_CENTER.Y + (floorIndex - 1) * Config.FLOOR_HEIGHT
	local tableCount = Config.TABLES_PER_FLOOR[floorIndex]
	local radius     = 80

	local foodPositions = {}

	for i = 1, tableCount do
		local angle     = (math.pi * 2 / tableCount) * i
		local tx        = cx + math.cos(angle) * radius
		local tz        = cz + math.sin(angle) * radius
		local tableTopY = floorY + 3.5

		local tbl = Instance.new("Part")
		tbl.Name      = "Table_F" .. floorIndex .. "_" .. i
		tbl.Size      = Vector3.new(6, 3, 6)
		tbl.Position  = Vector3.new(tx, floorY + 2, tz)
		tbl.Anchored  = true
		tbl.BrickColor = TABLE_COLORS[floorIndex]
		tbl.Material  = Enum.Material.Wood
		tbl.Parent    = parent

		local foodType = Config.FOOD_TYPES[((i - 1) % #Config.FOOD_TYPES) + 1]
		local foodPos  = Vector3.new(tx, tableTopY + foodType.size.Y / 2 + 0.1, tz)
		table.insert(foodPositions, { position = foodPos, foodType = foodType })
	end

	return foodPositions
end

-- -------------------------------------------------------------------------
-- Ground floor lobby
-- -------------------------------------------------------------------------
local function buildLobby(parent, cx, cy, cz)
	local carpet = Instance.new("Part")
	carpet.Name         = "Carpet"
	carpet.Size         = Vector3.new(200, 0.2, 200)
	carpet.Position     = Vector3.new(cx, cy + 0.6, cz)
	carpet.Anchored     = true
	carpet.BrickColor   = BrickColor.new("Bright red")
	carpet.Material     = Enum.Material.Fabric
	carpet.Transparency = 0.1
	carpet.CanCollide   = false
	carpet.Parent       = parent

	local desk = Instance.new("Part")
	desk.Name      = "ReceptionDesk"
	desk.Size      = Vector3.new(20, 3, 8)
	desk.Position  = Vector3.new(cx, cy + 2, cz + 40)
	desk.Anchored  = true
	desk.BrickColor = BrickColor.new("Dark orange")
	desk.Material  = Enum.Material.Wood
	desk.Parent    = parent
	addLabel(desk, Enum.NormalId.Front, "RECEPTION", Color3.new(1, 1, 1))

	local plantCorners = {
		Vector3.new(cx - 60, cy, cz - 60),
		Vector3.new(cx + 60, cy, cz - 60),
		Vector3.new(cx - 60, cy, cz + 60),
		Vector3.new(cx + 60, cy, cz + 60),
	}
	for _, pos in ipairs(plantCorners) do
		local pot = Instance.new("Part")
		pot.Shape     = Enum.PartType.Cylinder
		pot.Size      = Vector3.new(3, 3, 3)
		pot.Position  = pos + Vector3.new(0, 1.5, 0)
		pot.Anchored  = true
		pot.BrickColor = BrickColor.new("Reddish brown")
		pot.Material  = Enum.Material.SmoothPlastic
		pot.Parent    = parent

		local plant = Instance.new("Part")
		plant.Shape     = Enum.PartType.Ball
		plant.Size      = Vector3.new(5, 5, 5)
		plant.Position  = pos + Vector3.new(0, 5.5, 0)
		plant.Anchored  = true
		plant.BrickColor = BrickColor.new("Bright green")
		plant.Material  = Enum.Material.Grass
		plant.Parent    = parent
	end
end

-- -------------------------------------------------------------------------
-- Decorative tree at a given world position
-- -------------------------------------------------------------------------
local function buildTree(parent, position)
	local trunk = Instance.new("Part")
	trunk.Name      = "TreeTrunk"
	trunk.Shape     = Enum.PartType.Cylinder
	trunk.Size      = Vector3.new(8, 3, 3)
	trunk.CFrame    = CFrame.new(position + Vector3.new(0, 4, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored  = true
	trunk.BrickColor = BrickColor.new("Reddish brown")
	trunk.Material  = Enum.Material.Wood
	trunk.Parent    = parent

	local foliage = Instance.new("Part")
	foliage.Name     = "TreeFoliage"
	foliage.Shape    = Enum.PartType.Ball
	foliage.Size     = Vector3.new(14, 14, 14)
	foliage.Position = position + Vector3.new(0, 12, 0)
	foliage.Anchored = true
	foliage.BrickColor = BrickColor.new("Bright green")
	foliage.Material = Enum.Material.Grass
	foliage.Parent   = parent
end

-- -------------------------------------------------------------------------
-- Trees scattered around the outside of the restaurant
-- -------------------------------------------------------------------------
local function buildRestaurantTrees(parent, Config)
	local cx  = Config.HOTEL_CENTER.X
	local cz  = Config.HOTEL_CENTER.Z
	local hw  = Config.HOTEL_SIZE.X / 2 + 30  -- outside the walls

	-- 12 trees evenly spaced in a ring around the restaurant
	for i = 1, 12 do
		local angle = (math.pi * 2 / 12) * i
		local tx    = cx + math.cos(angle) * hw
		local tz    = cz + math.sin(angle) * hw
		buildTree(parent, Vector3.new(tx, 0.5, tz))
	end
end

-- -------------------------------------------------------------------------
-- Main build entry point
-- -------------------------------------------------------------------------
function RestaurantBuilder.build(Config)
	buildGround(Config)

	local cx     = Config.HOTEL_CENTER.X
	local cy     = Config.HOTEL_CENTER.Y
	local cz     = Config.HOTEL_CENTER.Z
	local rx     = Config.HOTEL_SIZE.X      -- 350
	local rz     = Config.HOTEL_SIZE.Z      -- 350
	local wt     = Config.WALL_THICKNESS    -- 5
	local fh     = Config.FLOOR_HEIGHT      -- 25
	local totalH = fh * Config.FLOOR_COUNT  -- 75

	local hotel = Instance.new("Model")
	hotel.Name   = "GrandHotel"
	hotel.Parent = workspace

	-- Ground floor slab
	local groundFloor = Instance.new("Part")
	groundFloor.Name      = "GroundFloor"
	groundFloor.Size      = Vector3.new(rx, 1, rz)
	groundFloor.Position  = Vector3.new(cx, cy, cz)
	groundFloor.Anchored  = true
	groundFloor.BrickColor = BrickColor.new("Light stone grey")
	groundFloor.Material  = Enum.Material.Concrete
	groundFloor.Parent    = hotel

	local function makeWall(name, size, pos)
		local w = Instance.new("Part")
		w.Name      = name
		w.Size      = size
		w.Position  = Vector3.new(cx + pos.X, cy + pos.Y, cz + pos.Z)
		w.Anchored  = true
		w.BrickColor = BrickColor.new("White")
		w.Material  = Enum.Material.Concrete
		w.Parent    = hotel
		return w
	end

	-- Perimeter walls (full hotel height)
	makeWall("NorthWall", Vector3.new(rx, totalH, wt),
		Vector3.new(0, totalH / 2, rz / 2))

	local doorW   = 20
	local sideLen = (rx - doorW) / 2
	makeWall("SouthWallLeft", Vector3.new(sideLen, totalH, wt),
		Vector3.new(-(rx / 2 - sideLen / 2), totalH / 2, -rz / 2))
	makeWall("SouthWallRight", Vector3.new(sideLen, totalH, wt),
		Vector3.new(rx / 2 - sideLen / 2, totalH / 2, -rz / 2))
	makeWall("SouthDoorLintel", Vector3.new(doorW, totalH - 22, wt),
		Vector3.new(0, (totalH + 22) / 2, -rz / 2))

	local sideZ = (rz - doorW) / 2
	makeWall("EastWallN", Vector3.new(wt, totalH, sideZ),
		Vector3.new(rx / 2, totalH / 2, rz / 2 - sideZ / 2))
	makeWall("EastWallS", Vector3.new(wt, totalH, sideZ),
		Vector3.new(rx / 2, totalH / 2, -(rz / 2 - sideZ / 2)))
	makeWall("EastDoorLintel", Vector3.new(wt, totalH - 22, doorW),
		Vector3.new(rx / 2, (totalH + 22) / 2, 0))

	makeWall("WestWallN", Vector3.new(wt, totalH, sideZ),
		Vector3.new(-rx / 2, totalH / 2, rz / 2 - sideZ / 2))
	makeWall("WestWallS", Vector3.new(wt, totalH, sideZ),
		Vector3.new(-rx / 2, totalH / 2, -(rz / 2 - sideZ / 2)))
	makeWall("WestDoorLintel", Vector3.new(wt, totalH - 22, doorW),
		Vector3.new(-rx / 2, (totalH + 22) / 2, 0))

	-- Windows: one row per floor per wall
	for f = 1, Config.FLOOR_COUNT do
		local windowY = cy + (f - 1) * fh + fh * 0.6
		buildWindowRow(hotel, cx,        cz + rz / 2, rx, windowY, true)   -- north
		buildWindowRow(hotel, cx,        cz - rz / 2, rx, windowY, true)   -- south
		buildWindowRow(hotel, cx + rx/2, cz,          rz, windowY, false)  -- east
		buildWindowRow(hotel, cx - rx/2, cz,          rz, windowY, false)  -- west
	end

	-- Ground floor entry doors
	createHotelDoor(Vector3.new(cx, cy + 11, cz - rz / 2),    0,   hotel, "MainDoor",  Config.DOOR_DEBOUNCE)
	createHotelDoor(Vector3.new(cx + rx / 2, cy + 11, cz),    90,  hotel, "EastDoor",  Config.DOOR_DEBOUNCE)
	createHotelDoor(Vector3.new(cx - rx / 2, cy + 11, cz),    270, hotel, "WestDoor",  Config.DOOR_DEBOUNCE)

	-- Hotel sign
	local sign = Instance.new("Part")
	sign.Name      = "HotelSign"
	sign.Size      = Vector3.new(60, 14, 1)
	sign.Position  = Vector3.new(cx, cy + totalH - 8, cz - rz / 2 - 3)
	sign.Anchored  = true
	sign.BrickColor = BrickColor.new("Bright yellow")
	sign.Material  = Enum.Material.Neon
	sign.Parent    = hotel
	addLabel(sign, Enum.NormalId.Front, "GRAND HOTEL\nSteal the Food!", Color3.new(0, 0, 0))

	-- Floor difficulty signs (exterior south wall)
	local floorLabels  = { "FLOOR 1 — EASY", "FLOOR 2 — MEDIUM", "FLOOR 3 — HARD" }
	local floorColors  = { Color3.new(0.2, 1, 0.2), Color3.new(1, 1, 0), Color3.new(1, 0.2, 0.2) }
	for f = 1, Config.FLOOR_COUNT do
		local fs = Instance.new("Part")
		fs.Size      = Vector3.new(22, 4, 0.3)
		fs.Position  = Vector3.new(cx, cy + (f - 1) * fh + fh / 2, cz - rz / 2 - 1)
		fs.Anchored  = true
		fs.BrickColor = BrickColor.new("Black")
		fs.Material  = Enum.Material.SmoothPlastic
		fs.Parent    = hotel
		addLabel(fs, Enum.NormalId.Front, floorLabels[f], floorColors[f])
	end

	-- Lobby
	buildLobby(hotel, cx, cy + 0.5, cz)

	-- Interior floor slabs with lift shaft holes
	buildFloorSlab(hotel, 1, Config, "east")   -- F1→F2 slab (east lift)
	buildFloorSlab(hotel, 2, Config, "west")   -- F2→F3 slab (west lift)

	-- Lifts
	buildLift(hotel, Config, "east")   -- F1 ↔ F2
	buildLift(hotel, Config, "west")   -- F2 ↔ F3

	-- Lift entrance corridor doors
	local hw      = rx / 2
	local liftEX  = cx + hw - 25
	local liftWX  = cx - hw + 25
	createFloorDoor(Vector3.new(liftEX, cy + fh + 10, cz - 8),      0, hotel, "LiftDoor_F1E", Config.DOOR_DEBOUNCE)
	createFloorDoor(Vector3.new(liftWX, cy + fh * 2 + 10, cz - 8),  0, hotel, "LiftDoor_F2W", Config.DOOR_DEBOUNCE)

	-- Decorative trees around the restaurant exterior
	buildRestaurantTrees(hotel, Config)

	-- Tables and food spawn positions per floor
	local floorFoodPositions = {}
	for f = 1, Config.FLOOR_COUNT do
		floorFoodPositions[f] = buildTablesForFloor(hotel, f, Config)
	end

	return hotel, floorFoodPositions
end

return RestaurantBuilder
