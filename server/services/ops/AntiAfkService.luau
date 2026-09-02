local AntiAfkService = {}

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local initialized = false

function AntiAfkService.Init(rejoinRemote)
	if initialized or not rejoinRemote then
		return
	end

	initialized = true

	rejoinRemote.OnServerEvent:Connect(function(player)
		if not player or player.Parent ~= Players then
			return
		end

		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ServerInstanceId = game.JobId
		teleportOptions:SetTeleportData({
			autoRejoin = true,
		})

		for _ = 1, 4 do
			local success = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { player }, teleportOptions)
			end)
			if success then
				return
			end

			task.wait(2)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		local joinData = player:GetJoinData()
		local teleportData = joinData and joinData.TeleportData
		if teleportData and teleportData.autoRejoin then
			warn(string.format("[AntiAFK] %s rejoined after idle protection", player.Name))
		end
	end)
end

return AntiAfkService
