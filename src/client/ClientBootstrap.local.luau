local Players = game:GetService("Players")
local player = Players.LocalPlayer
-- Install the local fallback before waiting for the UI or controller modules.
local function protectCharacter(character)
	local function anchorRoot(part)
		if part.Name == "HumanoidRootPart" and part:IsA("BasePart") then
			part.Anchored = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	character.ChildAdded:Connect(anchorRoot)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then anchorRoot(root) end
end
player.CharacterAdded:Connect(protectCharacter)
if player.Character then protectCharacter(player.Character) end

-- StarterGui normally copies on character spawn. With no avatar, mount the
-- same authored screens once, after their descendants have replicated.
if not game:IsLoaded() then game.Loaded:Wait() end
local StarterGui = game:GetService("StarterGui")
local playerGui = player:WaitForChild("PlayerGui")
for _, name in ipairs({ "Main", "GroupIntro" }) do
	local screen = playerGui:FindFirstChild(name)
	if not screen then
		local template = StarterGui:WaitForChild(name, 15)
		assert(template and template:IsA("ScreenGui"), "Missing authored StarterGui." .. name)
		-- Recheck after the wait so an existing copy is never duplicated.
		screen = playerGui:FindFirstChild(name)
		if not screen then
			screen = template:Clone()
			screen.ResetOnSpawn = false
			screen.Enabled = name == "GroupIntro"
			screen.Parent = playerGui
		end
	end
	assert(screen:IsA("ScreenGui"), "PlayerGui." .. name .. " must be a ScreenGui")
	screen.ResetOnSpawn = false
	screen.Enabled = name == "GroupIntro"
end

local GameController = require(script.Parent:WaitForChild("controllers"):WaitForChild("GameController"))

GameController.Start()
