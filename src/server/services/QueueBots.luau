-- Session-only simulated opponents. No Player instances, profiles or rewards.
local QueueBots = {}
QueueBots.__index = QueueBots
local HANDLES = { "milo", "ava", "jax", "toby", "luna", "kai", "ellie", "leo", "ari", "max", "ruby", "finn",
	"noodle", "kiwi", "toast", "mochi", "boba", "riley", "ollie", "nova", "ash", "zara", "blake", "ivy",
	"waffles", "coco", "dino", "sky", "poppy", "remy", "bean", "jamie" }
local PREFIXES = { "its", "just", "hey", "not", "sleepy", "lil", "real", "im" }
local SUFFIXES = { "plays", "blox", "lol", "xd", "onrbx", "builds", "vibes", "ish" }

-- Roblox can report a known blank thumbnail as ready. Never cache or assign it.
function QueueBots.IsUsableAvatar(userId, image, ready)
	if ready ~= true or type(userId) ~= "number" or userId <= 0 or userId == 36149989
		or type(image) ~= "string" or image:match("^%s*$") then return false end
	local imageUserId = tonumber(string.lower(image):match("[?&]id=(%d+)"))
	return imageUserId ~= 36149989
end

local function makeName(random)
	local base = HANDLES[random:NextInteger(1, #HANDLES)]
	local style = random:NextInteger(1, 6)
	if style == 1 then return base end
	if style == 2 then return PREFIXES[random:NextInteger(1, #PREFIXES)] .. base end
	if style == 3 then return base .. SUFFIXES[random:NextInteger(1, #SUFFIXES)] end
	if style == 4 then return base .. tostring(random:NextInteger(2, 999)) end
	if style == 5 then return base .. "_" .. tostring(random:NextInteger(2, 99)) end
	return string.upper(string.sub(base, 1, 1)) .. string.sub(base, 2) .. SUFFIXES[random:NextInteger(1, #SUFFIXES)]
end

local function median(values)
	table.sort(values)
	local middle = math.ceil(#values / 2)
	return #values % 2 == 0 and (values[middle] + values[middle + 1]) / 2 or values[middle]
end

-- Observe only canonical human progress. A stalled player never makes the bots accelerate.
local function observeHumans(round, now)
	local state = round.botPacing
	local counts, paces = {}, {}
	local best, anyCompleted = 0, false
	for _, id in ipairs(round.order) do
		local member = round.members[id]
		if not member.isBot and not member.failed then
			local sample = state.humans[id]
			if not sample then sample = { count = 0, at = state.startedAt, pace = 30 } state.humans[id] = sample end
			if member.count > sample.count then
				local interval = math.max(8, (now - sample.at) / (member.count - sample.count))
				sample.pace = sample.count == 0 and interval or sample.pace * 0.4 + interval * 0.6
				sample.count, sample.at = member.count, now
			end
			anyCompleted = anyCompleted or member.completed
			if not member.completed then
				table.insert(counts, member.count)
				table.insert(paces, math.max(sample.pace, now - sample.at))
				best = math.max(best, member.count)
			end
		end
	end
	return { count = #counts > 0 and median(counts) or 0, best = best,
		pace = #paces > 0 and math.clamp(median(paces), 14, 180) or 45,
		completed = anyCompleted, active = #counts > 0 }
end

function QueueBots.new(config, random, prepareAvatar, firstId)
	return setmetatable({ config = config or {}, random = random, prepareAvatar = prepareAvatar,
		bots = {}, nextId = firstId or -1000000000, lastPlayers = nil }, QueueBots)
end

function QueueBots:Release(members, now, expectedRound)
	for _, member in ipairs(members) do
		local bot = self.bots[member.userId]
		if bot and (not expectedRound or bot.round == expectedRound) then
			bot.round, bot.words = nil, nil
			bot.nextAt = now + self.random:NextNumber(1, 3)
		end
	end
end

function QueueBots:StartRound(round, now)
	local botIds = {}
	for _, id in ipairs(round.order) do if self.bots[id] then table.insert(botIds, id) end end
	-- Most rounds let humans lead; only one opponent can edge ahead in the others.
	local challenger = not round.beginner and #botIds > 0 and self.random:NextNumber(0, 1) < 0.35
		and botIds[self.random:NextInteger(1, #botIds)] or nil
	round.botPacing = { startedAt = now, humans = {}, nextFindAt = now }
	for _, id in ipairs(botIds) do
		local bot = self.bots[id]
		bot.round = round
		bot.words = table.clone(round.puzzle.words)
		for i = #bot.words, 2, -1 do
			local j = self.random:NextInteger(1, i)
			bot.words[i], bot.words[j] = bot.words[j], bot.words[i]
		end
		bot.challenger = id == challenger
		bot.lag = self.random:NextInteger(0, 2)
		bot.pace = bot.challenger and self.random:NextNumber(0.72, 0.9) or self.random:NextNumber(1.05, 1.65)
		bot.variation = self.random:NextNumber(0.85, 1.25)
		bot.lastSolveAt = now
		bot.nextAt = now + self.random:NextNumber(18, 40)
	end
end

function QueueBots:Step(realCount, queue, now, freezeLobby)
	local queueChanged, changedRounds = false, {}
	local slots = self.config.Enabled == true and realCount > 0
		and math.max(0, (self.config.ServerSize or 12) - realCount) or 0
	if not freezeLobby and (self.lastPlayers ~= realCount or slots == 0 or now >= (self.nextPopulationAt or 0)) then
		self.lastPlayers = realCount
		self.nextPopulationAt = now + self.random:NextNumber(60, 120)
		self.target = slots > 0 and self.random:NextInteger(math.min(slots, self.config.MinBots or 2), slots) or 0
	end
	local ids = {}
	for id in pairs(self.bots) do table.insert(ids, id) end
	table.sort(ids)
	local remaining = #ids
	-- Capacity applies to new/queued bots. Never pull an opponent out of an active round.
	for _, id in ipairs(ids) do
		if freezeLobby or remaining <= self.target then break end
		if not self.bots[id].round then
			queueChanged = queue:Remove(id) or queueChanged
			self.bots[id] = nil
			remaining -= 1
		end
	end
	for _ = remaining + 1, (freezeLobby and remaining or self.target) do
		local id = self.nextId
		self.nextId -= 1
		local name = makeName(self.random)
		local used = {}
		for _, existing in pairs(self.bots) do used[string.lower(existing.member.name)] = true end
		for _ = 1, 6 do
			if not used[string.lower(name)] then break end
			name = makeName(self.random)
		end
		if used[string.lower(name)] then
			local base, suffix = name, self.random:NextInteger(2, 99)
			repeat name = base .. tostring(suffix) suffix += 1 until not used[string.lower(name)]
		end
		local member = { userId = id, name = name, displayName = name, isBot = true,
			level = self.random:NextInteger(1, self.config.MaxLevel or 80), avatarReady = self.prepareAvatar == nil }
		self.bots[id] = { member = member, nextAt = now + self.random:NextNumber(2, 6) }
		if self.prepareAvatar then self.prepareAvatar(member) end
	end
	local nextBot
	local observed = {}
	for _, id in ipairs(ids) do
		local bot = self.bots[id]
		if bot and bot.round and not observed[bot.round] then observed[bot.round] = observeHumans(bot.round, now) end
	end
	-- Sort by due time so table iteration cannot favour the same bot on every word.
	local due = {}
	for _, bot in pairs(self.bots) do table.insert(due, bot) end
	table.sort(due, function(a, b)
		if a.nextAt ~= b.nextAt then return a.nextAt < b.nextAt end
		return a.member.userId > b.member.userId
	end)
	for _, bot in ipairs(due) do
		local id = bot.member.userId
		if now >= bot.nextAt then
			if bot.round then
				local round = bot.round
				local human = observed[round]
				local member = round.members[id]
				local word = bot.words[#bot.words]
				if not word or not member then bot.nextAt = math.huge continue end
				local total = #round.puzzle.words
				local cap = math.max(1, math.floor(human.count) - bot.lag)
				if bot.challenger then cap = human.best > 0 and human.best + 1 or 1 end
				cap = math.min(cap, human.completed and total or total - 1)
				if bot.challenger and human.best >= total - 1 and human.best > 0 then cap = total end
				local delay = math.max(14, human.pace * bot.pace * bot.variation + (round.puzzle.placedWordsByWord[word].length or #word) * 0.35)
				if not human.active or member.count >= cap then
					bot.nextAt = now + self.random:NextNumber(8, 18)
				elseif now < round.botPacing.nextFindAt or now < bot.lastSolveAt + delay then
					bot.nextAt = math.max(round.botPacing.nextFindAt, bot.lastSolveAt + delay)
				else
					table.remove(bot.words)
					local placed = round.puzzle.placedWordsByWord[word]
					if round:FindWord(id, word, placed.answer) then changedRounds[round] = true end
					bot.lastSolveAt = now
					bot.variation = self.random:NextNumber(0.85, 1.25)
					local pauseChance = bot.challenger and 0.08 or 0.18
					local pause = self.random:NextNumber(0, 1) < pauseChance
						and (bot.challenger and self.random:NextNumber(8, 20) or self.random:NextNumber(20, 65)) or 0
					bot.nextAt = now + delay + pause
					round.botPacing.nextFindAt = now + self.random:NextNumber(2, 5)
				end
			elseif not freezeLobby and bot.member.avatarReady and not queue.members[id] then
				if not nextBot or bot.nextAt < nextBot.nextAt
					or (bot.nextAt == nextBot.nextAt and id > nextBot.member.userId) then nextBot = bot end
			end
		end
	end
	-- Admit at most one bot, with no catch-up burst after a slow tick or avatar batch.
	if nextBot and now >= (self.nextJoinAt or 0) and (not queue.deadline or now < queue.deadline) then
		queueChanged = queue:Add(nextBot.member, now) or queueChanged
		local pending = 0
		for id, bot in pairs(self.bots) do
			if not bot.round and not queue.members[id] then pending += 1 end
		end
		-- Budget the remaining joins into this countdown instead of capping every
		-- cohort at roughly four bots. Preserve a visible gap even after a slow tick.
		local budget = ((queue.deadline or (now + 15)) - now - 0.75) / math.max(1, pending + 1) - 0.1
		local gap = math.clamp(budget, 0.7, 4.5) * self.random:NextNumber(0.25, 1.65)
		self.nextJoinAt = now + math.max(0.45, gap)
	end
	return queueChanged, changedRounds
end

return QueueBots
