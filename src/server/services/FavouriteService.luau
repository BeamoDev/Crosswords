local Players = game:GetService("Players")
local DataService = require(script.Parent.Parent.data.DataService)

local FavouriteService = {}
local sessions = {}
local promptRemote
local stateRemote

function FavouriteService.AddPlayer(player)
	if sessions[player] then return end
	local session = { ready = false }
	sessions[player] = session
	task.delay(15 * 60, function()
		while sessions[player] == session and player.Parent == Players do
			if session.ready and player:GetAttribute("ProfileReady") == true then
				local data = DataService.GetMutableData(player)
				if not session.reserved and data.account.favouritePrompted then return end
				session.reserved = true
				if DataService.MarkFavouritePrompted(player) then
					if sessions[player] == session and player.Parent == Players then
						promptRemote:FireClient(player)
						stateRemote:FireClient(player, DataService.GetSnapshot(player))
					end
					return
				end
			end
			task.wait(30)
		end
	end)
end

function FavouriteService.RemovePlayer(player)
	sessions[player] = nil
end

function FavouriteService.Init(remote, state)
	promptRemote, stateRemote = remote, state
	remote.OnServerEvent:Connect(function(player, ...)
		-- The client can only announce its listener. It cannot set the flag or timer.
		if player.Parent ~= Players or select("#", ...) ~= 0 then return end
		FavouriteService.AddPlayer(player)
		sessions[player].ready = true
	end)
end

function FavouriteService.Stop()
	table.clear(sessions)
end

return FavouriteService
