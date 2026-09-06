-- Session-only Duel opponents. Reuses Classic's adaptive pacing, without bot profiles.
local Players = game:GetService("Players")
local QueueBots = require(script.Parent.QueueBots)
local DuelBots = {}
DuelBots.__index = DuelBots

function DuelBots.new(config)
	local self = setmetatable({ running = true, matches = {}, images = {}, random = Random.new() }, DuelBots)
	local poolConfig = table.clone(config or {})
	-- A random subset of the available seats, refreshed by the shared scheduler.
	poolConfig.MinBots = 2
	self.capacity = poolConfig.ServerSize or 12
	self.pool = QueueBots.new(poolConfig, self.random, function(member)
		local games = self.random:NextInteger(12, 240)
		local wins = math.floor(games * self.random:NextNumber(0.25, 0.85) + 0.5)
		member.duel = { wins = wins, losses = games - wins }
		task.spawn(function()
			local function alive()
				return self.running and self.pool.bots[member.userId] ~= nil
			end
			local function tryAvatar(avatarId)
				local ok, image, ready = pcall(Players.GetUserThumbnailAsync, Players,
					avatarId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				if not alive() then return false end
				if not ok or not QueueBots.IsUsableAvatar(avatarId, image, ready) then return false end
				if not table.find(self.images, image) then
					table.insert(self.images, image)
					if #self.images > 64 then table.remove(self.images, 1) end
				end
				member.thumbnailImage, member.avatarReady = image, true
				return true
			end
			while alive() do
				for _ = 1, 4 do
					if not alive() then return end
					if tryAvatar(self.random:NextInteger(10000, 100000000)) then return end
					task.wait(0.5)
				end
				if not alive() then return end
				if #self.images > 0 then
					member.thumbnailImage = self.images[self.random:NextInteger(1, #self.images)]
					member.avatarReady = true
					return
				end
				-- Random IDs may not have usable thumbnails. Known connected accounts
				-- seed a verified fallback instead of leaving the entire lobby invisible.
				for _, player in ipairs(Players:GetPlayers()) do
					if not alive() then return end
					if tryAvatar(player.UserId) then return end
				end
				-- Keep the blank-avatar guard even during a Roblox thumbnail outage.
				task.wait(3)
			end
		end)
	end, -3000000000)
	-- Duel opponents are chosen in the list, never admitted to a Classic queue.
	self.lobby = { members = {}, deadline = -math.huge, Remove = function() return false end }
	return self
end

-- Small companion groups taper as real opponents become available.
function DuelBots.PopulationRange(realCount)
	if realCount <= 0 or realCount >= 8 then return 0, 0 end
	if realCount == 1 then return 2, 6 end
	if realCount == 2 then return 2, 3 end
	if realCount <= 4 then return 1, 2 end
	return 0, 1
end

function DuelBots:Refresh()
	local realCount = #Players:GetPlayers()
	local minimum, maximum = DuelBots.PopulationRange(realCount)
	self.pool.config.MinBots = minimum
	self.pool.config.ServerSize = realCount + math.min(maximum, math.max(0, self.capacity - realCount))
	return self.pool:Step(realCount, self.lobby, os.clock())
end

function DuelBots:List()
	local list = {}
	for _, bot in pairs(self.pool.bots) do
		if bot.member.avatarReady then table.insert(list, bot.member) end
	end
	table.sort(list, function(a, b) return a.userId > b.userId end)
	local realCount = #Players:GetPlayers()
	local _, maximum = DuelBots.PopulationRange(realCount)
	local limit = math.min(maximum, math.max(0, self.capacity - realCount), math.max(0, 8 - (realCount - 1)))
	while #list > limit do table.remove(list) end
	return list
end

function DuelBots:Get(id)
	-- Only currently advertised identities may receive new challenges.
	for _, member in ipairs(self:List()) do if member.userId == id then return member end end
	return nil
end

function DuelBots:Reserve(member)
	local bot = self.pool.bots[member.userId]
	if not bot or bot.round then return false end
	-- Reserve before puzzle generation can yield; population changes must not evict it.
	bot.round = { order = {}, members = {}, botPacing = { humans = {} } }
	bot.nextAt = math.huge
	return true
end

function DuelBots:Release(member)
	self.pool:Release({ member }, os.clock())
	self.matches[member.userId] = nil
end

function DuelBots:StartMatch(match)
	local human, opponent = match.player1, match.player2
	local round = { puzzle = match.puzzleData, order = { human.userId, opponent.userId }, members = {
		[human.userId] = { count = human.foundCount, completed = false },
		[opponent.userId] = { count = 0, isBot = true },
	} }
	function round:FindWord(id, word)
		if match.state ~= "active" or id ~= opponent.userId or opponent.foundWords[word] then return false end
		opponent.foundWords[word] = true
		opponent.foundCount += 1
		opponent.progress = 100 * opponent.foundCount / match.boardInfo.wordCount
		self.members[id].count = opponent.foundCount
		return true
	end
	self.matches[opponent.userId] = { match = match, round = round }
	self.pool:StartRound(round, os.clock())
	-- Duels are more competitive than Classic, but retain the human-progress caps.
	local bot = self.pool.bots[opponent.userId]
	bot.challenger = self.random:NextNumber(0, 1) < 0.60
	bot.lag = self.random:NextInteger(0, 1)
	bot.pace = bot.challenger and self.random:NextNumber(0.65, 0.85) or self.random:NextNumber(0.85, 1.15)
	bot.nextAt = os.clock() + self.random:NextNumber(14, 26)
end

function DuelBots:Step(onProgress)
	for id, entry in pairs(self.matches) do
		local match = entry.match
		if match.state ~= "active" then
			if match.rematchOffer then self.matches[id] = nil
			else self:Release({ userId = id }) end
		else
			local human = entry.round.members[match.player1.userId]
			human.count = match.player1.foundCount
			human.completed = human.count >= match.boardInfo.wordCount
		end
	end
	local _, changed = self:Refresh()
	for _, entry in pairs(self.matches) do
		if changed[entry.round] then onProgress(entry.match) end
	end
end

function DuelBots:Stop()
	self.running = false
	self.matches, self.pool.bots = {}, {}
end

return DuelBots
