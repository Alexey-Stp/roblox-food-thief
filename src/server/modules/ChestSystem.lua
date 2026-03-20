-- ChestSystem.lua
-- Spawns loot chests around the map.  Each chest has a ProximityPrompt (E key).
-- When opened, a weighted-random item is given to the player:
--   HealingFood (50%) — restores 50 HP immediately (no tool)
--   Pistol       (25%) — hitscan ranged weapon, 15 dmg, 60-stud range
--   Rifle        (20%) — hitscan ranged weapon, 30 dmg, 120-stud range
--   MagicCarpet   (5%) — rare; grants a FlyingCarpet tool
-- Chests respawn 60 s after being opened.  Server validates all weapon shots
-- via the ShootWeapon RemoteEvent (fired by WeaponClient.client.lua).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ChestSystem = {}

local Config = nil
local RemoteEvents = nil

local CHEST_RESPAWN_TIME = 60 -- seconds

-- Weighted loot table
local LOOT_TABLE = {
	{ name = "HealingFood", weight = 50 },
	{ name = "Pistol",      weight = 25 },
	{ name = "Rifle",       weight = 20 },
	{ name = "MagicCarpet", weight = 5  },
}

-- Pre-compute total weight
local TOTAL_WEIGHT = 0
for _, entry in ipairs(LOOT_TABLE) do
	TOTAL_WEIGHT = TOTAL_WEIGHT + entry.weight
end

-- Per-player weapon shot cooldowns  [UserId] = { Pistol = tick, Rifle = tick }
local weaponCooldowns = {}

local WEAPON_COOLDOWN = { Pistol = 1, Rifle = 2 }
local WEAPON_DAMAGE   = { Pistol = 15, Rifle = 30 }
local WEAPON_RANGE    = { Pistol = 60, Rifle = 120 }

-- -------------------------------------------------------------------------
-- Weighted random roll
-- -------------------------------------------------------------------------
local function rollLoot()
	local roll = math.random() * TOTAL_WEIGHT
	local cumulative = 0
	for _, entry in ipairs(LOOT_TABLE) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.name
		end
	end
	return LOOT_TABLE[1].name -- fallback
end

-- -------------------------------------------------------------------------
-- Tool builders
-- -------------------------------------------------------------------------
local function buildPistol()
	local tool = Instance.new("Tool")
	tool.Name = "Pistol"
	tool.RequiresHandle = true
	tool.ToolTip = "Pistol — 15 dmg, 60 studs"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1, 0.8)
	handle.BrickColor = BrickColor.new("Dark stone grey")
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.2, 0.2, 1.2)
	barrel.BrickColor = BrickColor.new("Black")
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Position = handle.Position + Vector3.new(0, 0.2, -0.9)
	barrel.Parent = tool
	local bw = Instance.new("WeldConstraint")
	bw.Part0 = handle
	bw.Part1 = barrel
	bw.Parent = handle

	return tool
end

local function buildRifle()
	local tool = Instance.new("Tool")
	tool.Name = "Rifle"
	tool.RequiresHandle = true
	tool.ToolTip = "Rifle — 30 dmg, 120 studs"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1, 2.2)
	handle.BrickColor = BrickColor.new("Reddish brown")
	handle.Material = Enum.Material.Wood
	handle.Parent = tool

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.2, 0.2, 1.8)
	barrel.BrickColor = BrickColor.new("Black")
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Position = handle.Position + Vector3.new(0, 0.3, -1.8)
	barrel.Parent = tool
	local bw = Instance.new("WeldConstraint")
	bw.Part0 = handle
	bw.Part1 = barrel
	bw.Parent = handle

	return tool
end

local function buildCarpetTool()
	-- Minimal carpet tool — FlyingCarpetClient drives the actual flight
	local tool = Instance.new("Tool")
	tool.Name = "FlyingCarpet"
	tool.RequiresHandle = true
	tool.ToolTip = "Flying Carpet — equip to fly at night"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(4, 0.2, 6)
	handle.BrickColor = BrickColor.new("Bright red")
	handle.Material = Enum.Material.Fabric
	handle:SetAttribute("IsCarpet", true)
	handle.Parent = tool

	return tool
end

-- -------------------------------------------------------------------------
-- Give loot to player
-- -------------------------------------------------------------------------
local function giveLoot(player, lootName)
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")

	if lootName == "HealingFood" then
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.Health + 50, humanoid.MaxHealth)
		end

	elseif lootName == "Pistol" then
		local tool = buildPistol()
		tool.Parent = player.Backpack

	elseif lootName == "Rifle" then
		local tool = buildRifle()
		tool.Parent = player.Backpack

	elseif lootName == "MagicCarpet" then
		-- Only give if the player doesn't already have one
		if not player.Backpack:FindFirstChild("FlyingCarpet") then
			local carpetTool = char:FindFirstChild("FlyingCarpet")
			if not carpetTool then
				buildCarpetTool().Parent = player.Backpack
			end
		end
	end
end

-- -------------------------------------------------------------------------
-- Chest model
-- -------------------------------------------------------------------------
local function buildChest(pos)
	local model = Instance.new("Model")
	model.Name = "LootChest"
	model.Parent = workspace

	-- Base
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 2, 2.5)
	body.Position = pos
	body.Anchored = true
	body.BrickColor = BrickColor.new("CGA brown")
	body.Material = Enum.Material.Wood
	body.Parent = model
	model.PrimaryPart = body

	-- Metal banding
	for _, yOff in ipairs({ 0.6, -0.6 }) do
		local band = Instance.new("Part")
		band.Size = Vector3.new(3.1, 0.2, 2.6)
		band.Position = pos + Vector3.new(0, yOff, 0)
		band.Anchored = true
		band.BrickColor = BrickColor.new("Dark stone grey")
		band.Material = Enum.Material.Metal
		band.CanCollide = false
		band.Parent = model
		local bw = Instance.new("WeldConstraint")
		bw.Part0 = body
		bw.Part1 = band
		bw.Parent = body
	end

	-- Lid
	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(3, 0.4, 2.5)
	lid.Position = pos + Vector3.new(0, 1.2, 0)
	lid.Anchored = true
	lid.BrickColor = BrickColor.new("Bright yellow")
	lid.Material = Enum.Material.Wood
	lid.CanCollide = false
	lid.Parent = model
	local lw = Instance.new("WeldConstraint")
	lw.Part0 = body
	lw.Part1 = lid
	lw.Parent = body

	-- Glow
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 60)
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = body

	-- ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Open"
	pp.ObjectText = "Loot Chest"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = body

	return model, body, lid, pp
end

-- -------------------------------------------------------------------------
-- Spawn one chest with respawn logic
-- -------------------------------------------------------------------------
local function spawnChest(pos)
	local model, body, lid, pp = buildChest(pos)

	pp.Triggered:Connect(function(player)
		-- Disable prompt immediately so only one player gets the reward
		pp.Enabled = false

		-- Animate lid open
		TweenService:Create(lid, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = body.Position + Vector3.new(0, 2.2, -0.8),
		}):Play()

		-- Roll and give loot
		local lootName = rollLoot()
		giveLoot(player, lootName)

		-- Destroy after short delay, respawn after CHEST_RESPAWN_TIME
		task.delay(1.5, function()
			if model and model.Parent then
				model:Destroy()
			end
		end)
		task.delay(CHEST_RESPAWN_TIME, function()
			spawnChest(pos)
		end)
	end)
end

-- -------------------------------------------------------------------------
-- Server-validated weapon shots
-- -------------------------------------------------------------------------
local function handleShot(player, toolName, aimDir)
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Confirm player has the weapon equipped
	local equipped = char:FindFirstChildOfClass("Tool")
	if not equipped or equipped.Name ~= toolName then
		return
	end

	-- Cooldown check
	local now = tick()
	if not weaponCooldowns[player.UserId] then
		weaponCooldowns[player.UserId] = {}
	end
	local cd = WEAPON_COOLDOWN[toolName] or 1
	if now - (weaponCooldowns[player.UserId][toolName] or 0) < cd then
		return
	end
	weaponCooldowns[player.UserId][toolName] = now

	-- Validate aim direction (must be a unit-ish vector)
	if typeof(aimDir) ~= "Vector3" or aimDir.Magnitude < 0.1 then
		return
	end
	aimDir = aimDir.Unit

	local range = WEAPON_RANGE[toolName] or 60
	local damage = WEAPON_DAMAGE[toolName] or 15

	-- Raycast from HRP
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(hrp.Position, aimDir * range, rayParams)
	if not result then
		return
	end

	local hitPart = result.Instance
	local hitChar = hitPart.Parent

	-- Try to damage a player
	local targetPlayer = Players:GetPlayerFromCharacter(hitChar)
	if targetPlayer and targetPlayer ~= player then
		local humanoid = hitChar:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(damage)
			RemoteEvents.HitFlash:FireClient(targetPlayer)
		end
		return
	end

	-- Try to damage a Guard NPC
	if hitChar and hitChar:IsA("Model") and hitChar.Name:sub(1, 6) == "Guard_" then
		local humanoid = hitChar:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(damage)
		end
	end
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function ChestSystem.init(remoteEvents, config)
	RemoteEvents = remoteEvents
	Config = config

	RemoteEvents.ShootWeapon.OnServerEvent:Connect(function(player, toolName, aimDir)
		if toolName == "Pistol" or toolName == "Rifle" then
			handleShot(player, toolName, aimDir)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		weaponCooldowns[player.UserId] = nil
	end)
end

function ChestSystem.spawnAll()
	-- 8 chest positions spread around the map exterior and base perimeter
	local positions = {
		Vector3.new(-230, 2, 0),
		Vector3.new(0, 2, -230),
		Vector3.new(230, 2, 0),
		Vector3.new(0, 2, 230),
		Vector3.new(-160, 2, -160),
		Vector3.new(160, 2, -160),
		Vector3.new(-160, 2, 160),
		Vector3.new(470, 2, 40), -- near safe base
	}
	for _, pos in ipairs(positions) do
		spawnChest(pos)
	end
end

return ChestSystem
