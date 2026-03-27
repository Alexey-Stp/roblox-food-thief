-- WeaponClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Fires ShootWeapon to the server whenever the local player activates a
-- Pistol or Rifle tool.  The server (ChestSystem.lua) performs raycast
-- validation, range checks, cooldowns, and applies damage.
-- Also shows a crosshair overlay when a weapon is equipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local ShootWeapon = eventsFolder:WaitForChild("ShootWeapon")

local WEAPON_NAMES = { Pistol = true, Rifle = true }

local activatedConn = nil

-- -------------------------------------------------------------------------
-- Crosshair UI
-- -------------------------------------------------------------------------

-- Returns (or creates) the WeaponHUD ScreenGui
local function getHud()
	local gui = localPlayer.PlayerGui:FindFirstChild("WeaponHUD")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "WeaponHUD"
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = localPlayer.PlayerGui
	end
	return gui
end

-- Removes any existing crosshair children from the HUD
local function clearCrosshair(gui)
	for _, child in ipairs(gui:GetChildren()) do
		child:Destroy()
	end
end

-- Builds a standard '+' crosshair (Pistol style)
local function buildPistolCrosshair(gui)
	local SIZE = 20 -- half-length of each arm in px
	local THICK = 2 -- line thickness in px
	local COLOR = Color3.new(1, 1, 1)

	local function makeLine(sizeX, sizeY, offsetX, offsetY)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = COLOR
		f.BorderSizePixel = 0
		f.Size = UDim2.fromOffset(sizeX, sizeY)
		f.Position = UDim2.new(0.5, offsetX - sizeX / 2, 0.5, offsetY - sizeY / 2)
		f.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Parent = f
	end

	makeLine(SIZE * 2, THICK, 0, 0) -- horizontal
	makeLine(THICK, SIZE * 2, 0, 0) -- vertical
end

-- Builds a tighter scope crosshair (Rifle style)
local function buildRifleCrosshair(gui)
	local SIZE = 12
	local THICK = 1
	local GAP = 4 -- gap in centre for scope feel
	local COLOR = Color3.new(1, 1, 1)

	local function makeLine(sizeX, sizeY, offsetX, offsetY)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = COLOR
		f.BorderSizePixel = 0
		f.Size = UDim2.fromOffset(sizeX, sizeY)
		f.Position = UDim2.new(0.5, offsetX - sizeX / 2, 0.5, offsetY - sizeY / 2)
		f.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Parent = f
	end

	-- Four arms with a centre gap
	makeLine(SIZE, THICK, -(SIZE + GAP) / 2, 0) -- left
	makeLine(SIZE, THICK, (SIZE + GAP) / 2, 0) -- right
	makeLine(THICK, SIZE, 0, -(SIZE + GAP) / 2) -- top
	makeLine(THICK, SIZE, 0, (SIZE + GAP) / 2) -- bottom

	-- Centre dot
	local dot = Instance.new("Frame")
	dot.BackgroundColor3 = COLOR
	dot.BorderSizePixel = 0
	dot.Size = UDim2.fromOffset(3, 3)
	dot.Position = UDim2.new(0.5, -1, 0.5, -1)
	dot.Parent = gui
end

local function showCrosshair(weaponName)
	local gui = getHud()
	clearCrosshair(gui)
	gui.Enabled = true
	if weaponName == "Rifle" then
		buildRifleCrosshair(gui)
	else
		buildPistolCrosshair(gui)
	end
end

local function hideCrosshair()
	local gui = localPlayer.PlayerGui:FindFirstChild("WeaponHUD")
	if gui then
		gui.Enabled = false
	end
end

-- -------------------------------------------------------------------------
-- Hook a weapon tool's Activated event
-- -------------------------------------------------------------------------
local function hookWeaponTool(tool)
	if not WEAPON_NAMES[tool.Name] then
		return
	end

	if activatedConn then
		activatedConn:Disconnect()
		activatedConn = nil
	end

	tool.Equipped:Connect(function()
		showCrosshair(tool.Name)
	end)

	tool.Unequipped:Connect(function()
		hideCrosshair()
		if activatedConn then
			activatedConn:Disconnect()
			activatedConn = nil
		end
	end)

	activatedConn = tool.Activated:Connect(function()
		-- Send tool name + camera look vector; server re-validates everything
		local cam = workspace.CurrentCamera
		local aimDir = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
		ShootWeapon:FireServer(tool.Name, aimDir)
	end)
end

-- -------------------------------------------------------------------------
-- Watch the character for weapon tools being equipped
-- -------------------------------------------------------------------------
local function onCharacterAdded(character)
	local existing = character:FindFirstChildOfClass("Tool")
	if existing then
		hookWeaponTool(existing)
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookWeaponTool(child)
		end
	end)
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
