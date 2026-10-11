-- WeaponClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Fires ShootWeapon to the server whenever the local player activates a
-- Pistol or Rifle tool.  The server (ChestSystem.lua) performs raycast
-- validation, range checks, cooldowns, and applies damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local ShootWeapon = eventsFolder:WaitForChild("ShootWeapon")

local WEAPON_NAMES = { Pistol = true, Rifle = true }

-- One Activated connection per tool lifetime (Activated only fires while equipped)
local hookedTools = setmetatable({}, { __mode = "k" })

local function hookWeaponTool(tool)
	if not tool:IsA("Tool") or not WEAPON_NAMES[tool.Name] or hookedTools[tool] then
		return
	end
	hookedTools[tool] = true

	tool.Activated:Connect(function()
		-- Send tool name + camera look vector; server re-validates everything
		local cam = workspace.CurrentCamera
		local aimDir = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
		ShootWeapon:FireServer(tool.Name, aimDir)
	end)
end

-- An equipped Tool is parented to the character; Activated only fires while
-- equipped, so watching the character is sufficient.
local function onCharacterAdded(character)
	for _, child in ipairs(character:GetChildren()) do
		hookWeaponTool(child)
	end
	character.ChildAdded:Connect(hookWeaponTool)
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
