local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local shared = ReplicatedStorage:WaitForChild("shared")
local Generator = require(script.Parent.Parent.puzzle.PuzzleGenerator)
local Config = require(shared:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local GameConfig = require(shared:WaitForChild("config"):WaitForChild("GameConfig"))
local Economy = GameConfig.Economy
local Contract = require(shared:WaitForChild("network"):WaitForChild("NetworkContract"))
local QueueState = require(script.Parent.QueueState)
local QueueBots = require(script.Parent.QueueBots)
local DataService = require(script.Parent.Parent.data.DataService)
local SocialService = require(script.Parent.SocialService)
local QueueService = {}
local queue = QueueState.new(15)
local rounds, playerRounds, rates = {}, {}, {}
local privateQueues = {}
local privateSerial, queueRevision = 0, 0
local remotes
local running, removingConnection = false, nil
local avatarRandom = Random.new()
local verifiedAvatars = {}
local function createBots(config, firstId)
	local manager
	manager = QueueBots.new(config, Random.new(), function(member)
		task.spawn(function()
			while running and manager.bots[member.userId] do
				for _ = 1, 4 do
					if not running or not manager.bots[member.userId] then return end
					local avatarId = avatarRandom:NextInteger(10000, 100000000)
					local ok, image, ready = pcall(Players.GetUserThumbnailAsync, Players, avatarId,
						Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
					if not running or not manager.bots[member.userId] then return end
					if ok and QueueBots.IsUsableAvatar(avatarId, image, ready) then
						if not table.find(verifiedAvatars, image) then
							table.insert(verifiedAvatars, image)
							if #verifiedAvatars > 64 then table.remove(verifiedAvatars, 1) end
						end
						member.thumbnailImage, member.avatarReady = image, true
						return
					end
					task.wait(0.5)
				end
				if #verifiedAvatars > 0 then
					member.thumbnailImage = verifiedAvatars[avatarRandom:NextInteger(1, #verifiedAvatars)]
					member.avatarReady = true
					return
				end
				-- With no verified fallback yet, retry before admitting this bot to a queue.
				task.wait(avatarRandom:NextNumber(10, 20))
			end
		end)
	end, firstId)
	return manager
end
local bots = createBots(GameConfig.Bots)

local function isBeginner(player)
	if player:GetAttribute("ProfileReady") ~= true then return true end
	local data = DataService.GetMutableData(player)
	return data ~= nil and data.progression.solves < Generator.BeginnerSolves
end

-- A monotonic publication revision survives changing from private to public queues.
local function queueSnapshot(player)
	local private = privateQueues[player.UserId]
	local snapshot
	if private then snapshot = private.queue:Snapshot()
	elseif isBeginner(player) then snapshot = { members = {}, count = 0 }
	else snapshot = queue:Snapshot() end
	queueRevision += 1
	snapshot.revision = queueRevision
	return snapshot
end

local function createPrivateQueue(player)
	privateSerial += 1
	local private = {
		queue = QueueState.new(15),
		-- Private companions are outside the public server's 12-slot filler budget.
		bots = createBots({ Enabled = GameConfig.Bots.Enabled, ServerSize = GameConfig.Bots.ServerSize, MinBots = GameConfig.Bots.MinBots or 2,
			MaxLevel = math.max(2, DataService.GetMutableData(player).progression.level + 2) },
			-2000000000 - privateSerial * 100),
	}
	privateQueues[player.UserId] = private
	return private
end

local function discardPrivate(userId)
	local private = privateQueues[userId]
	if private then
		private.bots.bots = {} -- Also cancels pending avatar preparation.
		privateQueues[userId] = nil
	end
end

local function hasHuman(members)
	for _, member in pairs(members) do
		if not member.isBot then return true end
	end
	return false
end

local function hasUnfinishedHuman(members)
	for _, member in pairs(members) do
		if not member.isBot and not member.completed and not member.failed then return true end
	end
	return false
end

local function sendQueue()
	for _, player in ipairs(Players:GetPlayers()) do
		remotes.queue:FireClient(player, queueSnapshot(player))
	end
end

local function sendRound(round, includePuzzle)
	for _, userId in ipairs(round.order) do
		local player = not round.members[userId].isBot and Players:GetPlayerByUserId(userId)
		if player then remotes.round:FireClient(player, round:Snapshot(includePuzzle, player.UserId)) end
	end
end

local function publishProfile(player)
	local snapshot = DataService.GetSnapshot(player)
	remotes.state:FireClient(player, snapshot)
	SocialService.MarkSnapshotDirty(player, snapshot)
	return snapshot
end

function QueueService.IsBusy(player)
	return queue.members[player.UserId] ~= nil or privateQueues[player.UserId] ~= nil or playerRounds[player.UserId] ~= nil
end

function QueueService.Remove(player)
	local userId = player.UserId
	local queueChanged = queue:Remove(userId) or privateQueues[userId] ~= nil
	local round = playerRounds[userId]
	playerRounds[userId] = nil
	if round then
		round:Remove(userId)
		if not hasHuman(round.members) then
			round.botOwner:Release(round:Snapshot(false).members, Workspace:GetServerTimeNow(), round)
			rounds[round.id] = nil
		else
			if not hasUnfinishedHuman(round.members) then
				round.botOwner:Release(round:Snapshot(false).members, Workspace:GetServerTimeNow(), round)
			end
			sendRound(round, false)
		end
	end
	discardPrivate(userId)
	if queueChanged then sendQueue() end
	player:SetAttribute("RoundBusy", false)
end

local function startCohort(members, manager, privateOwner)
	-- An unattended bot queue simply cycles back into the lobby.
	if not hasHuman(members) then
		manager:Release(members, Workspace:GetServerTimeNow())
		return
	end
	local seed = Random.new():NextInteger(1, 2147483646)
	-- Read authoritative human profiles at the deadline; bot levels are cosmetic.
	local skillMembers, beginnerSolves = {}, nil
	for _, member in ipairs(members) do
		local player = not member.isBot and Players:GetPlayerByUserId(member.userId)
		local data = player and player:GetAttribute("ProfileReady") == true and DataService.GetMutableData(player)
		if data then
			table.insert(skillMembers, { level = data.progression.level, solves = data.progression.solves })
			if privateOwner == member.userId then beginnerSolves = data.progression.solves end
		end
	end
	local ok, puzzle = pcall(function()
		return Generator.Generate(Generator.BuildClassicDefinition(skillMembers, seed, beginnerSolves), seed)
	end)
	if not ok then
		manager:Release(members, Workspace:GetServerTimeNow())
		if privateOwner then discardPrivate(privateOwner) end
		warn("[QueueService] Board generation failed:", puzzle)
		for _, member in ipairs(members) do
			local player = not member.isBot and Players:GetPlayerByUserId(member.userId)
			if player then
				player:SetAttribute("RoundBusy", false)
				remotes.round:FireClient(player, { error = "Couldn't start this round. Please queue again." })
			end
		end
		return
	end
	local present = {}
	for _, member in ipairs(members) do
		if (member.isBot and manager.bots[member.userId]) or (not member.isBot and Players:GetPlayerByUserId(member.userId)) then
			table.insert(present, member)
		end
	end
	if not hasHuman(present) then manager:Release(present, Workspace:GetServerTimeNow()) return end
	local round = QueueState.NewRound(HttpService:GenerateGUID(false), puzzle, present)
	round.startedAt = os.clock()
	round:SetTimer(Workspace:GetServerTimeNow(), GameConfig.RoundSeconds[round.mode])
	round.botOwner, round.beginner = manager, privateOwner ~= nil
	if privateOwner and privateQueues[privateOwner] then privateQueues[privateOwner].round = round end
	rounds[round.id] = round
	for _, member in ipairs(present) do
		if not member.isBot then playerRounds[member.userId] = round end
	end
	manager:StartRound(round, Workspace:GetServerTimeNow())
	sendRound(round, true)
end

local function expireRound(round, now)
	local expired = round:Expire(now)
	if #expired == 0 then return end
	for _, userId in ipairs(expired) do
		local member = round.members[userId]
		local player = not member.isBot and Players:GetPlayerByUserId(userId)
		if player then
			DataService.RecordModeOutcome(DataService.GetMutableData(player), round.mode, false)
			publishProfile(player)
		end
	end
	if not hasUnfinishedHuman(round.members) then round.botOwner:Release(round:Snapshot(false).members, now, round) end
	sendRound(round, false)
end

local function drainDue()
	local now = Workspace:GetServerTimeNow()
	for _, round in pairs(rounds) do expireRound(round, now) end
	local changed, changedRounds = bots:Step(#Players:GetPlayers(), queue, now)
	if changed then sendQueue() end
	for round in pairs(changedRounds) do
		if rounds[round.id] == round then sendRound(round, false) end
	end
	local members = queue:Drain(now)
	if members then
		bots.nextPopulationAt = 0 -- Roll a fresh population for the next cohort.
		sendQueue()
		startCohort(members, bots)
	end
	for userId, private in pairs(privateQueues) do
		if not private.round then
			local privateChanged = private.bots:Step(1, private.queue, now)
			if privateChanged then sendQueue() end
			local privateMembers = private.queue:Drain(now)
			if privateMembers then
				sendQueue()
				startCohort(privateMembers, private.bots, userId)
			end
		elseif hasUnfinishedHuman(private.round.members) then
			local _, updates = private.bots:Step(1, private.queue, now, true)
			for round in pairs(updates) do
				if rounds[round.id] == round then sendRound(round, false) end
			end
		end
	end
end

local function handle(player, payload)
	if type(payload) ~= "table" or not Contract.IsBoundedValue(payload) then return { success = false } end
	local action = payload.action
	if action ~= "Sync" and action ~= "Join" and action ~= "LeaveQueue" and action ~= "Exit"
		and action ~= "Word" and action ~= "Hint" and action ~= "StartSolo" then return { success = false } end
	local now = os.clock()
	local userRates = rates[player.UserId] or {}
	rates[player.UserId] = userRates
	local interval = action == "StartSolo" and 1 or (action == "Word" and 0.06 or 0.15)
	if now - (userRates[action] or -math.huge) < interval then return { success = false } end
	userRates[action] = now
	if player:GetAttribute("ProfileReady") ~= true then
		return { success = false, message = "Your data is still loading." }
	end
	drainDue()
	local round = playerRounds[player.UserId]
	if action == "Sync" then
		return { success = true, queue = queueSnapshot(player), round = round and round:Snapshot(true, player.UserId) }
	elseif action == "Join" then
		if player:GetAttribute("TutorialBusy") then return { success = false, message = "Finish or skip the tutorial first." } end
		if round then return { success = true, round = round:Snapshot(true, player.UserId), queue = queueSnapshot(player) } end
		if player:GetAttribute("DuelBusy") then return { success = false, message = "Leave your duel first." } end
		local data = DataService.GetMutableData(player)
		local level = data.progression.level
		local targetQueue = queue
		if isBeginner(player) then
			local private = privateQueues[player.UserId] or createPrivateQueue(player)
			targetQueue = private.queue
		end
		targetQueue:Add({ userId = player.UserId, name = player.Name, displayName = player.DisplayName, level = level }, Workspace:GetServerTimeNow())
		player:SetAttribute("RoundBusy", true)
		sendQueue()
		return { success = true, queue = queueSnapshot(player) }
	elseif action == "StartSolo" then
		local required = payload.mode == "Standard" and 1 or Config.Experience.ModeLevels[payload.mode]
		if not required then return { success = false, message = "That solo mode is unavailable." } end
		if player:GetAttribute("TutorialBusy") then return { success = false, message = "Finish or skip the tutorial first." } end
		if player:GetAttribute("DuelBusy") then return { success = false, message = "Leave your duel first." } end
		if round then return { success = true, round = round:Snapshot(true, player.UserId) } end
		if payload.mode ~= "Standard" and (queue.members[player.UserId] or privateQueues[player.UserId]) then return { success = false, message = "Leave the queue first." } end
		local data = DataService.GetMutableData(player)
		local level = data.progression.level
		if level < required then return { success = false, message = "Unlocks at Level " .. required .. "." } end
		local seed = Random.new():NextInteger(1, 2147483646)
		local ok, puzzle = pcall(function()
			local definition
			if payload.mode == "Standard" then
				definition = Generator.BuildClassicDefinition({data.progression}, seed, data.progression.solves)
			else definition = Generator.BuildDefinition(level, payload.mode, seed) end
			return Generator.Generate(definition, seed)
		end)
		if not ok then
			warn("[QueueService] Solo generation failed:", puzzle)
			return { success = false, message = "Couldn't start this round. Please try again." }
		end
		-- Detach only after successful generation, preserving the queue on failure.
		local leftQueue = queue:Remove(player.UserId) or privateQueues[player.UserId] ~= nil
		discardPrivate(player.UserId)
		round = QueueState.NewRound(HttpService:GenerateGUID(false), puzzle, {
			{ userId = player.UserId, name = player.Name, displayName = player.DisplayName },
		}, payload.mode)
		round.startedAt = os.clock()
		round:SetTimer(Workspace:GetServerTimeNow(), GameConfig.RoundSeconds[round.mode])
		round.botOwner, round.solo = bots, true
		if leftQueue then sendQueue() end
		rounds[round.id], playerRounds[player.UserId] = round, round
		player:SetAttribute("RoundBusy", true)
		return { success = true, round = round:Snapshot(true, player.UserId) }
	elseif action == "LeaveQueue" then
		if not round then
			local changed = queue:Remove(player.UserId) or privateQueues[player.UserId] ~= nil
			discardPrivate(player.UserId)
			if changed then player:SetAttribute("RoundBusy", false) sendQueue() end
		end
		return { success = true, queue = queueSnapshot(player), round = round and round:Snapshot(true, player.UserId) }
	elseif action == "Exit" then
		-- A delayed exit from an old round must not remove a new membership.
		if round and payload.roundId == round.id then QueueService.Remove(player) end
		return { success = true }
	end
	if not round or payload.roundId ~= round.id then return { success = false, message = "This round has ended." } end
	local data = DataService.GetMutableData(player)
	local member = round.members[player.UserId]
	if action == "Word" then
		local accepted, completed = round:FindWord(player.UserId, payload.word, payload.answer)
		if not accepted then
			if round:FailSelection(player.UserId, payload.word, payload.answer) then
				member.duration = math.max(0, os.clock() - round.startedAt)
				DataService.RecordModeOutcome(data, round.mode, false)
				sendRound(round, false)
				return { success = false, round = round:Snapshot(false, player.UserId), snapshot = publishProfile(player) }
			end
			return { success = false, round = round:Snapshot(false, player.UserId) }
		end
		DataService.RecordWordFound(data)
		local wordXp = round.puzzle.placedWordsByWord[payload.word].length * Config.Experience.PerLetter
		DataService.AddExperience(player, wordXp)
		member.xpEarned += wordXp
		if completed then
			member.duration = math.max(0, os.clock() - round.startedAt)
			member.score += Config.Score.Completion(member.duration, round.timeLimit)
			DataService.RecordModeOutcome(data, round.mode, true)
			DataService.AddExperience(player, Config.Experience.CompletionBonus)
			member.xpEarned += Config.Experience.CompletionBonus
			data.puzzlePieces += Economy.CalculateCompletionPieces({
				mode = round.mode, gridSize = round.puzzle.gridSize, hints = member.hintUses, resets = 0,
			})
		end
		if completed and not hasUnfinishedHuman(round.members) then
			-- Preserve final results on screen; only the scheduler releases the bots.
			round.botOwner:Release(round:Snapshot(false).members, Workspace:GetServerTimeNow(), round)
		end
		sendRound(round, false)
		return { success = true, round = round:Snapshot(false, player.UserId), snapshot = publishProfile(player) }
	elseif action == "Hint" then
		local word = round:NextHint(player.UserId)
		if not word then return { success = false, message = "All remaining words already have hints." } end
		if data.hints < 1 then return { success = false, noHints = true } end
		round:MarkHint(player.UserId, word)
		data.hints -= 1
		sendRound(round, false)
		return { success = true, word = word, round = round:Snapshot(false, player.UserId), snapshot = publishProfile(player) }
	end
	return { success = false }
end

function QueueService.Init(options)
	if running then return end
	running = true
	remotes = options
	remotes.action.OnServerInvoke = handle
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		QueueService.Remove(player)
		rates[player.UserId] = nil
	end)
	task.spawn(function()
		while running do
			task.wait(0.1)
			if running then drainDue() end
		end
	end)
end

function QueueService.Stop()
	running = false
	for userId in pairs(privateQueues) do discardPrivate(userId) end
	if removingConnection then removingConnection:Disconnect() removingConnection = nil end
end

return QueueService
