local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AutoRejoin = {}

local player = Players.LocalPlayer
local started = false
local requestedForCurrentIdle = false

local REMOTE_WAIT_SECONDS = 5
local REJOIN_IDLE_THRESHOLD = 17 * 60

local function resetIdleRequest()
	requestedForCurrentIdle = false
end

local function requestRejoin(rejoinRemote)
	local ok, err = pcall(function()
		rejoinRemote:FireServer()
	end)
	if not ok then
		warn("[AutoRejoin] Failed to request rejoin:", err)
		requestedForCurrentIdle = false
	end
end

function AutoRejoin.Init()
	if started then
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_SECONDS)
	local events = remotes and remotes:WaitForChild("Events", REMOTE_WAIT_SECONDS)
	local rejoinRemote = events and events:WaitForChild("RejoinRemote", REMOTE_WAIT_SECONDS)
	if not rejoinRemote then
		warn("[AutoRejoin] RejoinRemote was not found")
		return
	end

	started = true

	player.Idled:Connect(function(idleSeconds)
		local idleTime = tonumber(idleSeconds) or 0
		if requestedForCurrentIdle or idleTime < REJOIN_IDLE_THRESHOLD then
			return
		end

		requestedForCurrentIdle = true
		requestRejoin(rejoinRemote)
	end)

	UserInputService.InputBegan:Connect(resetIdleRequest)
	UserInputService.TouchTap:Connect(resetIdleRequest)
	UserInputService.WindowFocused:Connect(resetIdleRequest)
end

return AutoRejoin
