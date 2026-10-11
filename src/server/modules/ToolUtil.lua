-- ToolUtil.lua
-- Shared helpers for tool classification, food-tool construction and
-- server-initiated teleports. Stateless — safe to require from any module.
--
-- Food tools are identified POSITIVELY by the handle attribute IsFood=true.
-- Never classify food by "is not a bat / carpet" — weapons and future tools
-- would be treated as food.

local ToolUtil = {}

-- -------------------------------------------------------------------------
-- Classification
-- -------------------------------------------------------------------------

local function handleAttr(item, attr)
	if not item or type(item) ~= "table" and typeof(item) ~= "Instance" then
		return nil
	end
	if not item:IsA("Tool") then
		return nil
	end
	local h = item:FindFirstChild("Handle")
	return h and h:GetAttribute(attr)
end

function ToolUtil.isFood(item)
	return handleAttr(item, "IsFood") == true
end

function ToolUtil.isCarpet(item)
	return handleAttr(item, "IsCarpet") == true
end

-- Every food tool the player holds: equipped first, then backpack.
function ToolUtil.getFoodTools(player)
	local result = {}
	local char = player.Character
	if char then
		for _, item in ipairs(char:GetChildren()) do
			if ToolUtil.isFood(item) then
				table.insert(result, item)
			end
		end
	end
	local backpack = player.Backpack
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if ToolUtil.isFood(item) then
				table.insert(result, item)
			end
		end
	end
	return result
end

-- First food tool matching an optional predicate (equipped tool preferred).
function ToolUtil.findFoodTool(player, predicate)
	for _, tool in ipairs(ToolUtil.getFoodTools(player)) do
		if not predicate or predicate(tool) then
			return tool
		end
	end
	return nil
end

function ToolUtil.hasFood(player)
	return ToolUtil.findFoodTool(player) ~= nil
end

function ToolUtil.countFood(player)
	return #ToolUtil.getFoodTools(player)
end

-- Destroys every food tool the player holds; bats, carpets and weapons are kept.
function ToolUtil.confiscateFood(player)
	local tools = ToolUtil.getFoodTools(player)
	for _, tool in ipairs(tools) do
		tool:Destroy()
	end
	return #tools
end

function ToolUtil.hasCarpet(player)
	local containers = { player.Character, player.Backpack }
	for _, container in ipairs(containers) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if ToolUtil.isCarpet(item) then
					return true
				end
			end
		end
	end
	return false
end

-- -------------------------------------------------------------------------
-- Food tool construction
-- -------------------------------------------------------------------------

function ToolUtil.findFoodType(foodTypes, name)
	for _, ft in ipairs(foodTypes or {}) do
		if ft.name == name then
			return ft
		end
	end
	return nil
end

function ToolUtil.addFoodDecals(part, foodType)
	if foodType.texture then
		local d = Instance.new("Decal")
		d.Texture = foodType.texture
		d.Face = Enum.NormalId.Top
		d.Parent = part
	end
	if foodType.sideTexture then
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local d = Instance.new("Decal")
			d.Texture = foodType.sideTexture
			d.Face = face
			d.Parent = part
		end
	end
end

-- Builds a food Tool with all metadata attributes on its Handle.
-- opts (all optional):
--   currentPrice  — CurrentSellPrice (defaults to foodType.sellPrice)
--   storedAtLevel — fridge level the item was last stored at (default 0)
--   multiplied    — true for Food Multiplier output (cannot be re-multiplied)
function ToolUtil.makeFoodTool(foodType, opts)
	opts = opts or {}

	local tool = Instance.new("Tool")
	tool.Name = foodType.name
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = foodType.size * 0.7
	handle.BrickColor = foodType.color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	ToolUtil.addFoodDecals(handle, foodType)

	handle:SetAttribute("IsFood", true)
	handle:SetAttribute("FoodId", foodType.name)
	handle:SetAttribute("BaseSellPrice", foodType.sellPrice)
	handle:SetAttribute("CurrentSellPrice", opts.currentPrice or foodType.sellPrice)
	handle:SetAttribute("Rarity", foodType.rarity or "Common")
	handle:SetAttribute("StoredAtLevel", opts.storedAtLevel or 0)
	handle:SetAttribute("Multiplied", opts.multiplied == true)

	handle.Parent = tool
	return tool
end

-- Reads a food tool's metadata into a plain table (for saving / dropping).
function ToolUtil.readFoodData(tool)
	local h = tool:FindFirstChild("Handle")
	if not h then
		return nil
	end
	return {
		id = h:GetAttribute("FoodId") or tool.Name,
		price = h:GetAttribute("CurrentSellPrice"),
		stored = h:GetAttribute("StoredAtLevel") or 0,
		multiplied = h:GetAttribute("Multiplied") == true,
	}
end

-- -------------------------------------------------------------------------
-- Server-initiated teleports
-- -------------------------------------------------------------------------

-- Moves a player's character and stamps "LastServerTeleport" so movement
-- validators (FlyingCarpet) reset their baseline instead of rubber-banding.
function ToolUtil.teleport(player, cframe)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	player:SetAttribute("LastServerTeleport", os.clock())
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	hrp.CFrame = cframe
	return true
end

-- Gives server physics ownership of an unanchored assembly so clients
-- cannot move NPCs or loot. Safe to call on anchored parts (no-op).
function ToolUtil.claimNetworkOwnership(part)
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

return ToolUtil
