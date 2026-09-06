local DuelService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local servicesFolder = script.Parent
local DuelBots = require(servicesFolder:WaitForChild("DuelBots"))
local bots, running
local SocialService = require(servicesFolder:WaitForChild("SocialService"))
local serverFolder = servicesFolder.Parent
local systemsFolder = serverFolder:WaitForChild("systems")
local AnalyticsService = require(systemsFolder:WaitForChild("Analytics"))
local ProgressionConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("shared").config.ProgressionConfig)
local DataService = require(serverFolder:WaitForChild("data"):WaitForChild("DataService"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Utility = require(sharedFolder:WaitForChild("utility"):WaitForChild("Utility"))
local GameConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("GameConfig"))
local NetworkContract = require(sharedFolder:WaitForChild("network"):WaitForChild("NetworkContract"))
local DuelRemotes = NetworkContract.Legacy.Duel
local PuzzleGenerator = require(sharedFolder:WaitForChild("puzzle"):WaitForChild("PuzzleGenerator"))
local PuzzleValidator = require(sharedFolder:WaitForChild("puzzle"):WaitForChild("PuzzleValidator"))
local PuzzleEconomy = GameConfig.Economy

local CHALLENGE_TIMEOUT = 90
local CHALLENGE_COOLDOWN = 5
local TARGET_CHALLENGE_COOLDOWN = 8
local COUNTDOWN_TIME = 3
local MATCH_START_DELAY = 6
local RESULT_CLEANUP_DELAY = 6
local MIN_DUEL_WORD_FOUND_INTERVAL = 0.12
local DUEL_BASE_PIECE_REWARDS = {
	WIN = 20,
	LOSE = 5,
	DRAW = 10,
}
local DUEL_REWARD_MULTIPLIER = math.max(1, tonumber(PuzzleEconomy.CompletionRewardMultiplier) or 1)
local DUEL_PIECE_REWARDS = {
	WIN = math.max(1, math.floor((DUEL_BASE_PIECE_REWARDS.WIN * DUEL_REWARD_MULTIPLIER) + 0.5)),
	LOSE = math.max(1, math.floor((DUEL_BASE_PIECE_REWARDS.LOSE * DUEL_REWARD_MULTIPLIER) + 0.5)),
	DRAW = math.max(1, math.floor((DUEL_BASE_PIECE_REWARDS.DRAW * DUEL_REWARD_MULTIPLIER) + 0.5)),
}
local stateUpdatedRemote = nil
local duelRemotes = nil
local activeMatches = {}
local pendingChallenges = {}
local playerMatches = {}
local rematchOffers = {}
local rematchAdmissions = {}
local challengeCooldowns = {}
local targetChallengeCooldowns = {}
local playerListRequestedAt = {}
local playerListCache = {}
local getOrCreate = Utility.GetOrCreate
local normalizeWord = PuzzleValidator.NormalizeWord
local pathsMatch = PuzzleValidator.PathsMatch

local function invitesEnabled(player)
	if not player or player:GetAttribute("ProfileReady") ~= true then return false end
	local data = DataService.GetMutableData(player)
	return type(data) == "table" and (not data.settings or data.settings.DuelInvites ~= false)
end

local function playerDuelStats(player)
	local data = player and player:GetAttribute("ProfileReady") == true and DataService.GetMutableData(player)
	local stats = data and data.progression and data.progression.duel or {}
	return { wins = stats.wins or 0, losses = stats.losses or 0 }
end

local function participantDuelStats(participant)
	return participant.isBot and table.clone(participant.duelStats) or playerDuelStats(participant.player)
end

local function makeChallengeKey(challengerUserId, targetUserId)
	return string.format("%d:%d", challengerUserId, targetUserId)
end

local function fireChallengeEvent(player, payload)
	if player and player.Parent and duelRemotes and duelRemotes.DuelChallenge then
		duelRemotes.DuelChallenge:FireClient(player, payload)
	end
end

local function fireMatchEvent(player, payload)
	if player and player.Parent and duelRemotes and duelRemotes.DuelMatch then
		duelRemotes.DuelMatch:FireClient(player, payload)
	end
end

local function fireProgressEvent(player, payload)
	if player and player.Parent and duelRemotes and duelRemotes.DuelProgress then
		duelRemotes.DuelProgress:FireClient(player, payload)
	end
end

local function getMatchGridSize(match)
	local numericGridSize = math.max(
		0,
		math.floor(
			tonumber(match and match.puzzleData and (match.puzzleData.gridSize or match.puzzleData.size))
				or 0
		)
	)
	if numericGridSize <= 0 then
		return "unknown"
	end

	return string.format("%dx%d", numericGridSize, numericGridSize)
end

local function applyDuelOutcome(player, didWin, rewardAmount, sourceType, details)
	if not (player and player.Parent) then
		return 0
	end

	local data = DataService.GetMutableData(player)
	if type(data) ~= "table" then
		return 0
	end

	DataService.RecordModeOutcome(data, "Duel", didWin == true)


	local grantedPieces = math.max(0, math.floor(tonumber(rewardAmount) or 0))
	if grantedPieces > 0 then
		data.puzzlePieces = math.max(0, math.floor((data.puzzlePieces or 0) + grantedPieces))
		AnalyticsService.TrackEconomySource(player, "pieces", sourceType, grantedPieces, details or {})
	end

	local snapshot = DataService.GetSnapshot(player)
	SocialService.MarkSnapshotDirty(player, snapshot)
	if stateUpdatedRemote then
		stateUpdatedRemote:FireClient(player, snapshot)
	end

	return grantedPieces
end

local function buildPuzzleData(modeName, player1, opponentId)
	local level = 1
	local seedBase = os.time() + (player1.UserId * 17) + (opponentId * 31)
	local seed = math.max(1, seedBase % 2147483647)
	local definition = PuzzleGenerator.BuildDefinition(level, modeName, seed)
	if not definition then
		return nil
	end
	definition.gridSize = math.max(11, math.floor(tonumber(definition.gridSize) or 11))

	local generated = PuzzleGenerator.generate(definition, seed)
	generated.level = generated.level or level
	generated.seed = seed
	generated.mode = modeName
	return generated
end

local function createBoardInfo(puzzleData)
	local words = {}
	local wordLookup = {}

	for _, word in ipairs(puzzleData.words or {}) do
		local normalized = normalizeWord(word)
		if normalized and not wordLookup[normalized] then
			wordLookup[normalized] = true
			table.insert(words, normalized)
		end
	end

	return {
		wordLookup = wordLookup,
		wordCount = #words,
		words = words,
	}
end

local function serializeWordSet(wordSet, orderedWords)
	local serialized = {}

	for _, word in ipairs(orderedWords or {}) do
		if type(wordSet) == "table" and wordSet[word] then
			table.insert(serialized, word)
		end
	end

	return serialized
end

local function buildDuelHintBoardState(match, participant)
	if not (match and participant and match.boardInfo) then
		return nil
	end

	return {
		mode = "Duel",
		level = match.level,
		seed = match.seed,
		foundWords = serializeWordSet(participant.foundWords, match.boardInfo.words),
		hintedWords = serializeWordSet(participant.hintedWords, match.boardInfo.words),
		hintUses = math.max(0, math.floor(tonumber(participant.hintUses) or 0)),
	}
end

local function resolveDuelHintWord(match, participant, claimedWord)
	if not (match and participant and match.boardInfo) then
		return nil
	end

	local normalizedClaimedWord = normalizeWord(claimedWord)
	if normalizedClaimedWord
		and match.boardInfo.wordLookup[normalizedClaimedWord]
		and not participant.foundWords[normalizedClaimedWord]
		and not participant.hintedWords[normalizedClaimedWord] then
		return normalizedClaimedWord
	end

	for _, word in ipairs(match.boardInfo.words or {}) do
		if not participant.foundWords[word] and not participant.hintedWords[word] then
			return word
		end
	end

	return nil
end

local function getParticipant(match, userId)
	if not match then
		return nil, nil
	end

	if match.player1.userId == userId then
		return match.player1, match.player2
	end
	if match.player2.userId == userId then
		return match.player2, match.player1
	end

	return nil, nil
end

local function broadcastProgress(match)
	if not match then
		return
	end

	fireProgressEvent(match.player1.player, {
		matchId = match.id,
		myProgress = match.player1.progress,
		opponentProgress = match.player2.progress,
		myFoundWords = table.clone(match.player1.foundWords),
		opponentFoundWords = table.clone(match.player2.foundWords),
	})
	fireProgressEvent(match.player2.player, {
		matchId = match.id,
		myProgress = match.player2.progress,
		opponentProgress = match.player1.progress,
		myFoundWords = table.clone(match.player2.foundWords),
		opponentFoundWords = table.clone(match.player1.foundWords),
	})
end

local function cleanupMatch(matchId)
	local match = activeMatches[matchId]
	if not match then
		return
	end

	if match.player2.isBot and not match.rematchOffer then bots:Release(match.player2) end
	playerMatches[match.player1.userId] = nil
	playerMatches[match.player2.userId] = nil
	activeMatches[matchId] = nil
	for _, member in ipairs({ match.player1, match.player2 }) do
		if member.player then member.player:SetAttribute("DuelBusy", false) end
	end
end

local function publishRematch(offer, available)
	local count = 0
	for _ in pairs(offer.votes) do count += 1 end
	for _, member in ipairs({offer.match.player1, offer.match.player2}) do
		fireMatchEvent(member.player, {action="rematch", matchId=offer.match.id, available=available, count=count})
	end
end

local function closeRematch(offer)
	if not offer or offer.closed then return end
	offer.closed = true
	local match = offer.match
	match.rematchOffer = nil
	for _, member in ipairs({match.player1, match.player2}) do
		if rematchOffers[member.userId] == offer then rematchOffers[member.userId] = nil end
	end
	cleanupMatch(match.id)
	if match.player2.isBot then bots:Release(match.player2) end
	publishRematch(offer, false)
end

local function rematchEligible(offer)
	if offer.closed then return false end
	for _, member in ipairs({offer.match.player1, offer.match.player2}) do
		local player = member.player
		if player and (not player.Parent or player:GetAttribute("ProfileReady") ~= true
			or player:GetAttribute("RoundBusy") or player:GetAttribute("TutorialBusy")
			or (playerMatches[member.userId] and playerMatches[member.userId] ~= offer.match.id)) then return false end
	end
	return true
end

local function completeMatch(matchId, quitterId)
	local match = activeMatches[matchId]
	if not match or match.state == "finished" then
		return
	end

	match.state = "finished"
	local winnerId = match.winner
	local participant1 = match.player1
	local participant2 = match.player2
	local winner = winnerId == participant1.userId and participant1 or participant2
	local loser = winnerId == participant1.userId and participant2 or participant1
	for _, participant in ipairs({ winner, loser }) do
		if participant.isBot then
			local key = participant == winner and "wins" or "losses"
			participant.duelStats[key] += 1
		end
	end
	local duration = match.startTime and math.max(0, os.clock() - match.startTime) or 0
	local opponentQuit = type(quitterId) == "number"
	if not opponentQuit then
		local offer = {match=match, votes={}}
		match.rematchOffer = offer
		rematchOffers[participant1.userId], rematchOffers[participant2.userId] = offer, offer
	end
	local rewardDetails = {
		mode = tostring(match.mode or "Duel"),
		level = math.max(1, math.floor(tonumber(match.level) or 1)),
		gridSize = getMatchGridSize(match),
	}
	local winnerReward = winner and applyDuelOutcome(winner.player, true, DUEL_PIECE_REWARDS.WIN, opponentQuit and "duel_forfeit_reward" or "duel_reward", {
		result = "win",
		mode = rewardDetails.mode,
		level = rewardDetails.level,
		gridSize = rewardDetails.gridSize,
	}) or 0
	local loserReward = loser and applyDuelOutcome(loser.player, false, opponentQuit and 0 or DUEL_PIECE_REWARDS.LOSE, opponentQuit and "duel_forfeit_reward" or "duel_reward", {
		result = opponentQuit and "forfeit_loss" or "lose",
		mode = rewardDetails.mode,
		level = rewardDetails.level,
		gridSize = rewardDetails.gridSize,
	}) or 0

	if winner and winner.player and winner.player.Parent then
		AnalyticsService.TrackDuelComplete(winner.player, true, match.mode, duration)
	end
	if loser and loser.player and loser.player.Parent then
		AnalyticsService.TrackDuelComplete(loser.player, false, match.mode, duration)
	end

	local resultPayload = {
		action = opponentQuit and "forfeit" or "result",
		matchId = match.id,
		mode = match.mode,
		level = match.level,
		winnerId = winner and winner.userId or 0,
		winnerName = winner and winner.displayName or "Winner",
		loserName = loser and loser.displayName or "Loser",
		duration = math.floor(duration * 10) / 10,
		opponentQuit = opponentQuit,
		rematchAvailable = not opponentQuit,
		theme = match.puzzleData.title or "Word Search",
		wordCount = match.boardInfo.wordCount,
	}

	if winner and winner.player and winner.player.Parent then
		local winnerPayload = table.clone(resultPayload)
		winnerPayload.myDuelStats, winnerPayload.opponentDuelStats = participantDuelStats(winner), participantDuelStats(loser)
		winnerPayload.isWinner = true
		winnerPayload.xpEarned = winner.xpEarned
		winnerPayload.myXP = winner.xpEarned
		winnerPayload.foundCount = winner.foundCount
		winnerPayload.myPuzzlePieces = winnerReward
		winnerPayload.myStars = 3
		fireMatchEvent(winner.player, winnerPayload)
	end
	if loser and loser.player and loser.player.Parent then
		local loserPayload = table.clone(resultPayload)
		loserPayload.myDuelStats, loserPayload.opponentDuelStats = participantDuelStats(loser), participantDuelStats(winner)
		loserPayload.isWinner = false
		loserPayload.xpEarned = loser.xpEarned
		loserPayload.myXP = loser.xpEarned
		loserPayload.foundCount = loser.foundCount
		loserPayload.myPuzzlePieces = loserReward
		loserPayload.myStars = 0
		loserPayload.youQuit = opponentQuit and loser.userId == quitterId or false
		fireMatchEvent(loser.player, loserPayload)
	end

	task.delay(RESULT_CLEANUP_DELAY, function()
		cleanupMatch(matchId)
	end)
end

local function createMatch(player1, player2, modeName, botMember, admissionValid)
	local opponentId = botMember and botMember.userId or player2.UserId
	closeRematch(rematchOffers[player1.UserId])
	closeRematch(rematchOffers[opponentId])
	local ok, puzzleData = pcall(buildPuzzleData, modeName, player1, opponentId)
	if not running or not ok or not puzzleData or (admissionValid and not admissionValid())
		or (not botMember and (not invitesEnabled(player2) or not player2.Parent
			or player2:GetAttribute("RoundBusy") or player2:GetAttribute("TutorialBusy")))
		or not player1.Parent or player1:GetAttribute("ProfileReady") ~= true
		or player1:GetAttribute("RoundBusy") or player1:GetAttribute("TutorialBusy") then
		return nil
	end

	local boardInfo = createBoardInfo(puzzleData)
	if boardInfo.wordCount <= 0 then
		return nil
	end

	local matchId = string.format("duel_%d_%d_%d", player1.UserId, opponentId, math.floor(os.clock() * 1000))
	local match = {
		id = matchId,
		mode = modeName,
		level = puzzleData.level,
		seed = puzzleData.seed,
		puzzleData = puzzleData,
		boardInfo = boardInfo,
		state = "countdown",
		startTime = nil,
		winner = nil,
		player1 = {
			userId = player1.UserId,
			player = player1,
			name = player1.Name,
			displayName = player1.DisplayName,
			progress = 0,
			foundWords = {},
			hintedWords = {},
			foundCount = 0,
			xpEarned = 0,
			hintUses = 0,
			lastWordFoundAt = -math.huge,
		},
		player2 = {
			userId = opponentId,
			player = player2,
			name = botMember and botMember.name or player2.Name,
			displayName = botMember and botMember.displayName or player2.DisplayName,
			isBot = botMember ~= nil,
			duelStats = botMember and botMember.duel,
			thumbnailImage = botMember and botMember.thumbnailImage,
			progress = 0,
			foundWords = {},
			hintedWords = {},
			foundCount = 0,
			xpEarned = 0,
			hintUses = 0,
			lastWordFoundAt = -math.huge,
		},
	}

	activeMatches[matchId] = match
	playerMatches[player1.UserId] = matchId
	playerMatches[opponentId] = matchId
	player1:SetAttribute("DuelBusy", true)
	if player2 then player2:SetAttribute("DuelBusy", true) end
	return match
end

local function startMatch(match)
	for _, recipient in ipairs({ match.player1, match.player2 }) do
		local _, opponent = getParticipant(match, recipient.userId)
		fireMatchEvent(recipient.player, {
			action = "countdown", matchId = match.id, opponentId = opponent.userId,
			opponentName = opponent.displayName, opponentIsBot = opponent.isBot == true,
			opponentThumbnailImage = opponent.thumbnailImage,
			myDuelStats = participantDuelStats(recipient), opponentDuelStats = participantDuelStats(opponent),
			mode = match.mode, level = match.level, countdownTime = COUNTDOWN_TIME, puzzleData = match.puzzleData,
		})
	end
	task.delay(MATCH_START_DELAY, function()
		if activeMatches[match.id] ~= match or match.state ~= "countdown" then return end
		match.state, match.startTime = "active", os.clock()
		if match.player2.isBot then bots:StartMatch(match) end
		fireMatchEvent(match.player1.player, { action = "start", matchId = match.id })
		fireMatchEvent(match.player2.player, { action = "start", matchId = match.id })
		broadcastProgress(match)
	end)
end

function DuelService:RequestRematch(player, matchId)
	if type(matchId) ~= "string" or #matchId > 100 then return false end
	local offer = rematchOffers[player.UserId]
	if not offer or offer.match.id ~= matchId or offer.starting or offer.votes[player.UserId] then return false end
	if not rematchEligible(offer) then closeRematch(offer) return false end
	offer.votes[player.UserId] = true
	publishRematch(offer, true)
	local function ready()
		if not rematchEligible(offer) then closeRematch(offer) return end
		local old = offer.match
		if not offer.votes[old.player1.userId] or not offer.votes[old.player2.userId] then return end
		offer.starting = true
		publishRematch(offer, true)
		task.delay(0.5, function()
			if not rematchEligible(offer) then closeRematch(offer) return end
			local botMember = old.player2.isBot and bots.pool.bots[old.player2.userId]
			botMember = botMember and botMember.member or nil
			closeRematch(offer)
			if old.player2.isBot and (not botMember or not bots:Reserve(botMember)) then return end
			-- Reserve both humans while puzzle generation yields.
			old.player1.player:SetAttribute("DuelBusy", true)
			if old.player2.player then old.player2.player:SetAttribute("DuelBusy", true) end
			local token = {}
			rematchAdmissions[old.player1.userId], rematchAdmissions[old.player2.userId] = token, token
			local function admitted()
				return rematchAdmissions[old.player1.userId] == token and rematchAdmissions[old.player2.userId] == token
			end
			local match = createMatch(old.player1.player, old.player2.player, old.mode, botMember, admitted)
			for _, member in ipairs({old.player1, old.player2}) do
				if rematchAdmissions[member.userId] == token then rematchAdmissions[member.userId] = nil end
			end
			if match then startMatch(match)
			else
				old.player1.player:SetAttribute("DuelBusy", false)
				if old.player2.player then old.player2.player:SetAttribute("DuelBusy", false) end
				if botMember then bots:Release(botMember) end
			end
		end)
	end
	if offer.match.player2.isBot then
		task.delay(0.8 + math.random() * 1.4, function()
			if offer.closed or offer.starting then return end
			offer.votes[offer.match.player2.userId] = true
			ready()
		end)
	else ready() end
	return true
end

function DuelService:GetPlayerList(requestingPlayer)
	local list = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= requestingPlayer then
			table.insert(list, {
				userId = otherPlayer.UserId,
				name = otherPlayer.DisplayName,
				username = otherPlayer.Name,
				duel = playerDuelStats(otherPlayer),
				inMatch = otherPlayer:GetAttribute("ProfileReady") ~= true or otherPlayer:GetAttribute("DuelBusy") == true or playerMatches[otherPlayer.UserId] ~= nil or otherPlayer:GetAttribute("RoundBusy") == true or otherPlayer:GetAttribute("TutorialBusy") == true,
				hasPending = pendingChallenges[otherPlayer.UserId] ~= nil,
				duelRequestsEnabled = invitesEnabled(otherPlayer),
			})
		end
	end

	if bots then
		for _, member in ipairs(bots:List()) do
			table.insert(list, { userId = member.userId, name = member.displayName, username = member.name,
				isBot = true, thumbnailImage = member.thumbnailImage, duel = table.clone(member.duel),
				inMatch = playerMatches[member.userId] ~= nil or rematchOffers[member.userId] ~= nil, hasPending = false, duelRequestsEnabled = true })
		end
	end
	table.sort(list, function(left, right)
		if (left.isBot == true) ~= (right.isBot == true) then return left.isBot ~= true end
		return string.lower(left.username or "") < string.lower(right.username or "")
	end)

	while #list > 8 do table.remove(list) end
	return list
end

function DuelService:SendChallenge(challenger, targetUserId, modeName)
	if not challenger then return false, "Invalid request." end
	if challenger:GetAttribute("RoundBusy") or challenger:GetAttribute("TutorialBusy") or challenger:GetAttribute("ProfileReady") ~= true then
		return false, "Leave your round or queue first."
	end
	if not challenger or type(targetUserId) ~= "number" or targetUserId ~= math.floor(targetUserId) or targetUserId == 0 or math.abs(targetUserId) > 9007199254740991 then
		return false, "Invalid request."
	end

	if challenger.UserId == targetUserId then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "You can't challenge yourself.",
			targetId = targetUserId,
		})
		return false, "You can't challenge yourself."
	end

	local botMember = targetUserId < 0 and bots and bots:Get(targetUserId) or nil
	local target = targetUserId > 0 and Players:GetPlayerByUserId(targetUserId) or nil
	if not target and not botMember then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "That player is no longer here.",
			targetId = targetUserId,
		})
		return false, "That player is no longer here."
	end

	if target and not invitesEnabled(target) then
		fireChallengeEvent(challenger, { action = "error", targetId = targetUserId, message = "That player has 1v1 invites turned off." })
		return false, "Invites disabled."
	end

	closeRematch(rematchOffers[challenger.UserId])
	if challenger:GetAttribute("DuelBusy") or (target and target:GetAttribute("DuelBusy"))
		or playerMatches[challenger.UserId] or playerMatches[targetUserId]
		or (target and (target:GetAttribute("RoundBusy") or target:GetAttribute("TutorialBusy") or target:GetAttribute("ProfileReady") ~= true)) then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "One of you is already playing.",
			targetId = targetUserId,
		})
		return false, "One of you is already playing."
	end

	local now = os.clock()
	local lastChallengeAt = challengeCooldowns[challenger.UserId]
	if lastChallengeAt and (now - lastChallengeAt) < CHALLENGE_COOLDOWN then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "Wait a moment before challenging again.",
			targetId = targetUserId,
		})
		return false, "Cooldown."
	end

	local challengeKey = makeChallengeKey(challenger.UserId, targetUserId)
	local targetedAt = targetChallengeCooldowns[challengeKey]
	if targetedAt and (now - targetedAt) < TARGET_CHALLENGE_COOLDOWN then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "Wait a moment before challenging that player again.",
			targetId = targetUserId,
		})
		return false, "Target cooldown."
	end

	for _, challengeData in pairs(pendingChallenges) do
		if challengeData.challengerId == challenger.UserId then
			fireChallengeEvent(challenger, {
				action = "error",
				message = "You already have a pending duel request.",
				targetId = challengeData.targetId,
			})
			return false, "Already pending."
		end
	end

	if pendingChallenges[targetUserId] then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "That player already has a pending duel request.",
			targetId = targetUserId,
		})
		return false, "Target pending."
	end

	if botMember then
		if pendingChallenges[challenger.UserId] or not bots:Reserve(botMember) then
			fireChallengeEvent(challenger, { action = "error", targetId = targetUserId, message = "A duel is already pending." })
			return false, "Already pending."
		end
		challengeCooldowns[challenger.UserId], targetChallengeCooldowns[challengeKey] = now, now
		playerMatches[challenger.UserId], playerMatches[targetUserId] = "preparing", "preparing"
		challenger:SetAttribute("DuelBusy", true)
		local match = createMatch(challenger, nil, "Duel", botMember)
		if not match then
			bots:Release(botMember)
			playerMatches[challenger.UserId], playerMatches[targetUserId] = nil, nil
			challenger:SetAttribute("DuelBusy", false)
			fireChallengeEvent(challenger, { action = "error", targetId = targetUserId, message = "Failed to create duel board." })
			return false, "Failed to create duel."
		end
		AnalyticsService.TrackDuelChallenge(challenger, "Duel")
		startMatch(match)
		return true, "Match starting."
	end

	local selectedMode = "Duel"
	challengeCooldowns[challenger.UserId] = now
	targetChallengeCooldowns[challengeKey] = now
	pendingChallenges[targetUserId] = {
		challengerId = challenger.UserId,
		challengerName = challenger.DisplayName,
		challengerUsername = challenger.Name,
		targetId = target.UserId,
		targetName = target.DisplayName,
		targetUsername = target.Name,
		mode = selectedMode,
		createdAt = now,
	}

	AnalyticsService.TrackDuelChallenge(challenger, selectedMode)

	fireChallengeEvent(target, {
		action = "received",
		challengerId = challenger.UserId,
		challengerName = challenger.DisplayName,
		challengerUsername = challenger.Name,
		mode = selectedMode,
	})
	fireChallengeEvent(challenger, {
		action = "sent",
		targetId = target.UserId,
		targetName = target.DisplayName,
		targetUsername = target.Name,
		mode = selectedMode,
	})

	local issuedChallenge = pendingChallenges[targetUserId]
	task.delay(CHALLENGE_TIMEOUT, function()
		local challengeData = pendingChallenges[targetUserId]
		if challengeData ~= issuedChallenge then
			return
		end

		pendingChallenges[targetUserId] = nil
		fireChallengeEvent(challenger, {
			action = "expired",
			targetId = target.UserId,
			targetName = target.DisplayName,
			targetUsername = target.Name,
		})
		if target.Parent then
			fireChallengeEvent(target, {
				action = "expired",
				challengerId = challenger.UserId,
				challengerName = challenger.DisplayName,
				challengerUsername = challenger.Name,
			})
		end
	end)

	return true, "Challenge sent."
end

function DuelService:OnInviteSettingChanged(player)
	if invitesEnabled(player) then return end
	local challenge = pendingChallenges[player.UserId]
	if not challenge then return end
	pendingChallenges[player.UserId] = nil
	fireChallengeEvent(player, { action = "expired", challengerId = challenge.challengerId })
	local challenger = Players:GetPlayerByUserId(challenge.challengerId)
	fireChallengeEvent(challenger, { action = "declined", targetId = player.UserId, targetName = player.DisplayName, targetUsername = player.Name })
end

function DuelService:RespondToChallenge(responder, accepted)
	local challengeData = pendingChallenges[responder.UserId]
	if not challengeData then
		fireChallengeEvent(responder, {
			action = "error",
			message = "That duel request expired.",
		})
		return false, "No pending challenge."
	end

	pendingChallenges[responder.UserId] = nil

	local challenger = Players:GetPlayerByUserId(challengeData.challengerId)
	if not challenger then
		fireChallengeEvent(responder, {
			action = "error",
			message = "That player left the game.",
		})
		return false, "Challenger missing."
	end

	if not accepted or not invitesEnabled(responder) then
		fireChallengeEvent(challenger, {
			action = "declined",
			targetId = responder.UserId,
			targetName = responder.DisplayName,
			targetUsername = responder.Name,
		})
		return not accepted, "Declined."
	end

	if playerMatches[challenger.UserId] or playerMatches[responder.UserId]
		or challenger:GetAttribute("RoundBusy") or responder:GetAttribute("RoundBusy")
		or challenger:GetAttribute("TutorialBusy") or responder:GetAttribute("TutorialBusy")
		or challenger:GetAttribute("ProfileReady") ~= true or responder:GetAttribute("ProfileReady") ~= true then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "One of you is already playing.",
			targetId = responder.UserId,
		})
		fireChallengeEvent(responder, {
			action = "error",
			message = "One of you is already playing.",
			targetId = challenger.UserId,
		})
		return false, "Already in duel."
	end

	local match = createMatch(challenger, responder, challengeData.mode)
	if not match then
		fireChallengeEvent(challenger, {
			action = "error",
			message = "Failed to create duel board.",
			targetId = responder.UserId,
		})
		fireChallengeEvent(responder, {
			action = "error",
			message = "Failed to create duel board.",
			targetId = challenger.UserId,
		})
		return false, "Failed to create duel."
	end

	startMatch(match)

	return true, "Match starting."
end

function DuelService:ReportProgress(player, payload)
	if type(payload) ~= "table" or not NetworkContract.IsBoundedValue(payload) then
		return
	end

	local matchId = playerMatches[player.UserId]
	local match = matchId and activeMatches[matchId] or nil
	if not match or match.state ~= "active" then
		return
	end

	local participant, opponent = getParticipant(match, player.UserId)
	if not participant then
		return
	end
	local now = os.clock()

	local word = normalizeWord(payload.word)
	if word and match.boardInfo.wordLookup[word] and not participant.foundWords[word] then
		local expectedPath = match.puzzleData
			and match.puzzleData.placedWordsByWord
			and match.puzzleData.placedWordsByWord[word]
			and match.puzzleData.placedWordsByWord[word].path
		if now - (participant.lastWordFoundAt or -math.huge) < MIN_DUEL_WORD_FOUND_INTERVAL then
			return
		end
		if not pathsMatch(expectedPath, payload.path) then
			return
		end

		participant.lastWordFoundAt = now
		participant.foundWords[word] = true
		participant.foundCount += 1
		DataService.RecordWordFound(DataService.GetMutableData(player))
		local earnedXp = #word * ProgressionConfig.Experience.PerLetter
		if participant.foundCount == match.boardInfo.wordCount then
			earnedXp += ProgressionConfig.Experience.CompletionBonus
		end
		DataService.AddExperience(player, earnedXp)
		participant.xpEarned += earnedXp
		local snapshot = DataService.GetSnapshot(player)
		SocialService.MarkSnapshotDirty(player, snapshot)
		if stateUpdatedRemote then stateUpdatedRemote:FireClient(player, snapshot) end
		participant.progress = math.max(
			participant.progress,
			math.clamp((participant.foundCount / math.max(1, match.boardInfo.wordCount)) * 100, 0, 100)
		)

		if participant.foundCount >= match.boardInfo.wordCount and not match.winner then
			match.winner = participant.userId
			participant.progress = 100
			if opponent then
				opponent.progress = math.clamp(opponent.progress or 0, 0, 99.9)
			end
			broadcastProgress(match)
			completeMatch(match.id)
			return
		end
	end

	broadcastProgress(match)
end

function DuelService:ReportCompletion(player)
	local matchId = playerMatches[player.UserId]
	local match = matchId and activeMatches[matchId] or nil
	if not match or match.state ~= "active" then
		return
	end

	local participant, opponent = getParticipant(match, player.UserId)
	if not participant then
		return
	end

	if participant.foundCount < match.boardInfo.wordCount or match.winner then
		return
	end

	match.winner = participant.userId
	participant.progress = 100
	if opponent then
		opponent.progress = math.clamp(opponent.progress or 0, 0, 99.9)
	end
	broadcastProgress(match)
	completeMatch(match.id)
end

function DuelService:UseHint(player, claimedWord)
	local matchId = playerMatches[player.UserId]
	local match = matchId and activeMatches[matchId] or nil
	if not match or match.state ~= "active" then
		return {
			success = false,
			accepted = false,
			message = "Start the duel first.",
			snapshot = DataService.GetSnapshot(player),
			boardState = nil,
		}
	end

	local participant = getParticipant(match, player.UserId)
	if not participant then
		return {
			success = false,
			accepted = false,
			message = "Duel player not found.",
			snapshot = DataService.GetSnapshot(player),
			boardState = nil,
		}
	end

	local hintWord = resolveDuelHintWord(match, participant, claimedWord)
	if not hintWord then
		return {
			success = false,
			accepted = false,
			message = "All remaining words already have hints.",
			snapshot = DataService.GetSnapshot(player),
			boardState = buildDuelHintBoardState(match, participant),
		}
	end

	local data = DataService.GetMutableData(player)
	if type(data) ~= "table" then
		return {
			success = false,
			accepted = false,
			message = "Hint service unavailable.",
			snapshot = DataService.GetSnapshot(player),
			boardState = buildDuelHintBoardState(match, participant),
		}
	end

	local availableHints = math.max(0, math.floor(tonumber(data.hints) or 0))
	if availableHints <= 0 then
		return {
			success = false,
			accepted = false,
			message = "No hints available.",
			snapshot = DataService.GetSnapshot(player),
			boardState = buildDuelHintBoardState(match, participant),
		}
	end

	data.hints = availableHints - 1
	participant.hintedWords[hintWord] = true
	participant.hintUses = math.max(0, math.floor(tonumber(participant.hintUses) or 0) + 1)

	AnalyticsService.TrackHintUsed(player, "Duel")

	return {
		success = true,
		accepted = true,
		message = nil,
		snapshot = DataService.GetSnapshot(player),
		boardState = buildDuelHintBoardState(match, participant),
	}
end

function DuelService:AbandonMatch(player)
	if rematchAdmissions[player.UserId] then
		rematchAdmissions[player.UserId] = nil
		player:SetAttribute("DuelBusy", false)
	end
	closeRematch(rematchOffers[player.UserId])
	local matchId = playerMatches[player.UserId]
	local match = matchId and activeMatches[matchId] or nil
	if not match or match.state == "finished" then
		return
	end

	local _, opponent = getParticipant(match, player.UserId)
	if not opponent then
		return
	end

	match.winner = opponent.userId
	completeMatch(match.id, player.UserId)
end

function DuelService:OnPlayerRemoving(player)
	pendingChallenges[player.UserId] = nil
	challengeCooldowns[player.UserId] = nil
	playerListRequestedAt[player.UserId] = nil
	playerListCache[player.UserId] = nil

	for targetUserId, challengeData in pairs(pendingChallenges) do
		if challengeData.challengerId == player.UserId then
			pendingChallenges[targetUserId] = nil
			local target = Players:GetPlayerByUserId(targetUserId)
			if target then
				fireChallengeEvent(target, {
					action = "expired",
					challengerId = player.UserId,
					challengerName = player.DisplayName,
					challengerUsername = player.Name,
				})
			end
		end
	end

	self:AbandonMatch(player)
end

function DuelService.Init(options)
	if duelRemotes then
		return
	end
	options = type(options) == "table" and options or {}
	stateUpdatedRemote = options.StateUpdatedRemote

	local sharedRemotesFolder = getOrCreate(ReplicatedStorage, "Folder", "Remotes")
	local sharedEventsFolder = getOrCreate(sharedRemotesFolder, "Folder", "Events")
	local sharedFunctionsFolder = getOrCreate(sharedRemotesFolder, "Folder", "Functions")
	local duelFolder = getOrCreate(sharedEventsFolder, "Folder", DuelRemotes.Folder)

	duelRemotes = {
		RequestPlayerList = getOrCreate(sharedFunctionsFolder, "RemoteFunction", DuelRemotes.RequestPlayerList),
		SendChallenge = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.SendChallenge),
		RespondChallenge = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.RespondChallenge),
		ReportDuelProgress = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.ReportProgress),
		ReportDuelCompletion = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.ReportCompletion),
		AbandonDuel = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.Abandon),
		Rematch = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.Rematch),
		DuelChallenge = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.Challenge),
		DuelMatch = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.Match),
		DuelProgress = getOrCreate(duelFolder, "RemoteEvent", DuelRemotes.Progress),
	}

	duelRemotes.RequestPlayerList.OnServerInvoke = function(player)
		local now = os.clock()
		local lastRequestedAt = tonumber(playerListRequestedAt[player.UserId]) or -math.huge
		if now - lastRequestedAt < 0.5 then
			-- An empty rate-limit response used to erase a successfully loaded roster.
			return playerListCache[player.UserId] or {}
		end
		playerListRequestedAt[player.UserId] = now
		local list = DuelService:GetPlayerList(player)
		playerListCache[player.UserId] = list
		return list
	end

	duelRemotes.SendChallenge.OnServerEvent:Connect(function(player, targetUserId, modeName)
		DuelService:SendChallenge(player, targetUserId, modeName)
	end)

	duelRemotes.RespondChallenge.OnServerEvent:Connect(function(player, accepted)
		if type(accepted) ~= "boolean" then
			return
		end
		DuelService:RespondToChallenge(player, accepted)
	end)

	duelRemotes.ReportDuelProgress.OnServerEvent:Connect(function(player, payload)
		DuelService:ReportProgress(player, payload)
	end)

	duelRemotes.ReportDuelCompletion.OnServerEvent:Connect(function(player)
		DuelService:ReportCompletion(player)
	end)

	duelRemotes.Rematch.OnServerEvent:Connect(function(player, matchId)
		DuelService:RequestRematch(player, matchId)
	end)

	duelRemotes.AbandonDuel.OnServerEvent:Connect(function(player)
		DuelService:AbandonMatch(player)
	end)

	bots = DuelBots.new(GameConfig.Bots)
	running = true
	bots:Refresh()
	local function tick()
		if not running then return end
		for _, offer in pairs(rematchOffers) do
			if not rematchEligible(offer) then closeRematch(offer) end
		end
		bots:Step(function(match)
			if match.state ~= "active" then return end
			broadcastProgress(match)
			if match.player2.foundCount >= match.boardInfo.wordCount then
				match.winner = match.player2.userId
				completeMatch(match.id)
			end
		end)
		task.delay(1, tick)
	end
	task.delay(1, tick)
	-- ServerBootstrap resolves departures before saving/releasing profiles.
end

function DuelService.Stop()
	running = false
	for _, offer in pairs(rematchOffers) do closeRematch(offer) end
	for matchId in pairs(activeMatches) do cleanupMatch(matchId) end
	if bots then bots:Stop() end
end

return DuelService
