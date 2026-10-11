-- BatClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Fires BatSwing to the server whenever the local player activates the Bat tool.
-- The server (BatCombat.lua) performs spatial validation and applies damage
-- to other players, NPCs, and destructible Castle parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Wait for the shared RemoteEvents folder (populated by server on start)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local BatSwing = eventsFolder:WaitForChild("BatSwing")

local SWING_ANIMATION_ID = "rbxassetid://522635514"

-- Tools already wired. Activated only fires while equipped, so one connection
-- per tool lifetime is enough (weak keys: destroyed tools are collected).
local hookedTools = setmetatable({}, { __mode = "k" })

-- Swing animation track, loaded once per character
local animTrack = nil

local function loadSwingAnimation(character)
	animTrack = nil
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not animator then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = SWING_ANIMATION_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok then
		animTrack = track
	end
end

local function hookBatTool(tool)
	if tool.Name ~= "Bat" or not tool:IsA("Tool") or hookedTools[tool] then
		return
	end
	hookedTools[tool] = true

	tool.Activated:Connect(function()
		-- Restart the swing so rapid taps replay cleanly
		if animTrack then
			animTrack:Stop()
			animTrack:Play()
		end
		-- The server re-validates targets independently; the position is only a hint
		local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
		BatSwing:FireServer(hrp and hrp.Position or Vector3.zero)
	end)
end

-- -------------------------------------------------------------------------
-- An equipped Tool is parented to the character, and Activated only fires
-- while equipped — so watching the character is sufficient.
-- -------------------------------------------------------------------------
local function onCharacterAdded(character)
	for _, child in ipairs(character:GetChildren()) do
		hookBatTool(child)
	end
	character.ChildAdded:Connect(hookBatTool)
	task.spawn(loadSwingAnimation, character)
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
