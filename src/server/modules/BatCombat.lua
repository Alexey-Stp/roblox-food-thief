-- BatCombat.lua
-- Gives every player a bat on spawn and validates PvP melee hits on the server.
-- Design rationale: the client fires BatSwing when the tool activates; the server
-- performs its own spatial scan so exploiters cannot fake targets or bypass cooldowns.
--
-- Damage targets (all server-validated, all found by one spatial query):
--   1. Other players (PvP, when Config.PVP_ENABLED)
--   2. NPCs: Hunter guards (Models named "Guard_*") and floor creatures
--      (Models with the IsCreature attribute)
--   3. Parts named "Door" or "Wall" inside any Model named "Castle"
--      → health tracked via a "Health" attribute; at zero the part becomes
--        transparent and non-collidable (destroyed after a 2-second delay).

local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")

local BatCombat = {}

local Config = nil
local RemoteEvents = nil

-- Server-side swing cooldowns keyed by player UserId
local cooldowns = {} -- [UserId] = os.clock() of last accepted swing

-- -------------------------------------------------------------------------
-- Bat tool construction
-- -------------------------------------------------------------------------
-- True for NPC models the bat may damage
local function isDamageableNpc(model)
	if not model or not model:IsA("Model") then
		return false
	end
	if model.Name:sub(1, 6) == "Guard_" then
		return true
	end
	-- Player characters are handled (and gated by PVP_ENABLED) in the PvP pass
	if Players:GetPlayerFromCharacter(model) then
		return false
	end
	return model:GetAttribute("IsCreature") == true
end

local function damageCastlePart(part)
	local hp = (part:GetAttribute("Health") or Config.CASTLE_PART_HEALTH) - Config.BAT_DAMAGE
	if hp <= 0 then
		-- Part destroyed: make intangible, remove after a short delay
		part:SetAttribute("Health", 0)
		part.Transparency = 1
		part.CanCollide = false
		task.delay(Config.CASTLE_PART_DESTROY_DELAY, function()
			if part.Parent then
				part:Destroy()
			end
		end)
	else
		part:SetAttribute("Health", hp)
	end
end

local function isCastlePart(part)
	local parent = part.Parent
	return part:IsA("BasePart")
		and (part.Name == "Door" or part.Name == "Wall")
		and parent ~= nil
		and parent.Name == "Castle"
		and (part:GetAttribute("Health") or 1) > 0
end

local function buildBat()
	local tool = Instance.new("Tool")
	tool.Name = "Bat"
	tool.RequiresHandle = true
	tool.ToolTip = "Castle Defender Bat"
	tool.GripForward = Vector3.new(0, -1, 0)

	-- Handle (grip shaft)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 3, 0.5)
	handle.BrickColor = BrickColor.new("Reddish brown")
	handle.Material = Enum.Material.Wood
	-- Tag so EnemyAI and guards do NOT confiscate the bat
	handle:SetAttribute("IsBat", true)
	handle.Parent = tool

	-- Bat head (wider top)
	local head = Instance.new("Part")
	head.Name = "BatHead"
	head.Size = Vector3.new(1.2, 1.5, 1.2)
	head.BrickColor = BrickColor.new("Brown")
	head.Material = Enum.Material.Wood
	head.CanCollide = false
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle

	-- Offset head to the top of the handle
	head.CFrame = handle.CFrame * CFrame.new(0, 2, 0)

	-- Swing whoosh sound parented to handle (plays via client BatHit event)
	local sound = Instance.new("Sound")
	sound.Name = "SwingSound"
	sound.SoundId = "rbxassetid://5943191636"
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 30
	sound.Parent = handle

	return tool
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function BatCombat.init(remoteEvents, config)
	RemoteEvents = remoteEvents
	Config = config

	-- Place one bat in StarterPack — Roblox auto-distributes it to every player
	-- on spawn without any per-player code needed.
	buildBat().Parent = StarterPack

	-- Clean up cooldown entry when a player leaves
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player.UserId] = nil
	end)

	-- -----------------------------------------------------------------------
	-- Server-side hit validation
	-- Client fires BatSwing when the bat tool activates.
	-- -----------------------------------------------------------------------
	RemoteEvents.BatSwing.OnServerEvent:Connect(function(player, _aimPos)
		-- 1. Confirm the bat is currently equipped
		local char = player.Character
		if not char then
			return
		end
		local equipped = char:FindFirstChildWhichIsA("Tool")
		if not equipped or equipped.Name ~= "Bat" then
			return
		end

		-- 2. Cooldown check — stamp immediately so duplicate packets are rejected
		local now = os.clock()
		local last = cooldowns[player.UserId]
		if last and now - last < Config.BAT_COOLDOWN then
			return
		end
		cooldowns[player.UserId] = now

		-- 3. Server-side spatial scan — never trust the client's target hint
		local myHRP = char:FindFirstChild("HumanoidRootPart")
		if not myHRP then
			return
		end

		local hitConfirmed = false

		-- Spatial query — exclude the attacker's own character from results
		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = { char }
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		local nearbyParts = workspace:GetPartBoundsInRadius(myHRP.Position, Config.BAT_RANGE, overlapParams)

		-- ── 4a. PvP: check each nearby part for an enemy player character ─
		local hitPlayers = {} -- guard against hitting the same player twice
		for _, part in ipairs(nearbyParts) do
			if hitConfirmed or not Config.PVP_ENABLED then
				break
			end
			local otherChar = part.Parent
			if otherChar then
				local other = Players:GetPlayerFromCharacter(otherChar)
				if other and other ~= player and not hitPlayers[other] then
					local humanoid = otherChar:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						hitPlayers[other] = true
						humanoid:TakeDamage(Config.BAT_DAMAGE)
						RemoteEvents.HitFlash:FireClient(other)
						RemoteEvents.BatHit:FireClient(player)
						hitConfirmed = true
					end
				end
			end
		end

		-- ── 4b. Hunter NPC scan (Guard_ models) ──────────────────────────
		if not hitConfirmed then
			local hitModels = {}
			for _, part in ipairs(nearbyParts) do
				if hitConfirmed then
					break
				end
				local model = part.Parent
				if isDamageableNpc(model) and not hitModels[model] then
					local npcHumanoid = model:FindFirstChildOfClass("Humanoid")
					if npcHumanoid and npcHumanoid.Health > 0 then
						hitModels[model] = true
						npcHumanoid:TakeDamage(Config.BAT_DAMAGE)
						RemoteEvents.BatHit:FireClient(player)
						hitConfirmed = true
					end
				end
			end
		end

		-- ── 4c. Castle destructible parts (Door / Wall inside a "Castle" model) ─
		-- Uses the same spatial query (bounding boxes) — no workspace-wide scan.
		if not hitConfirmed then
			for _, part in ipairs(nearbyParts) do
				if isCastlePart(part) then
					damageCastlePart(part)
					RemoteEvents.BatHit:FireClient(player)
					break
				end
			end
		end
	end)
end

return BatCombat
