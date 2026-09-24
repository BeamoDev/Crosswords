local NetworkContract = {
	FolderName = "WordSearchBackendRemotes",
	GetBootstrap = "GetBootstrap",
	TrackAction = "TrackAction",
	StateUpdated = "StateUpdated",
	UseHint = "UseHint",
	QueueAction = "QueueAction",
	TutorialAction = "TutorialAction",
	QueueUpdated = "QueueUpdated",
	RoundUpdated = "RoundUpdated",
	FavouritePrompt = "FavouritePrompt",
	Limits = {
		MaximumDepth = 4,
		MaximumEntries = 96,
		MaximumWordLength = 32,
		MaximumEntryIdLength = 8,
		MaximumFunnelStepLength = 96,
	},
}

NetworkContract.TrackActions = { ClientFunnel = { throttle = 0.25 } }

NetworkContract.Legacy = {
	Folder = "Remotes",
	Events = "Events",
	Functions = "Functions",
	PurchaseHints = "PurchaseHintsWithCoins",
	GetDailyRewardState = "GetDailyRewardState",
	ClaimDailyReward = "ClaimDailyReward",
	CheckHints = "CheckHints",
	ClaimGift = "ClaimGift",
	PlayerJoinedGroup = "PlayerJoinedGroup",
	GroupHintAwarded = "GroupHintAwarded",
	UpdateSetting = "UpdateSetting",
	Rejoin = "RejoinRemote",
	-- Update: category (WordsFound/1v1Wins/Level), top-20 entries, updatedAt, revision, personal.
	-- personal: UserId, Username, Score, Rank (when known), RankText (#N / 100+ / --).
	-- Request: no arguments; sends both cached categories using the retained event names.
	LeaderboardUpdate = "LeaderboardUpdateSolves",
	LeaderboardRequest = "RequestLeaderboardUpdateSolves",
	-- Word requests send word (entry ID), answer (A-Z text), and roundId / matchId.
	-- Result/forfeit includes title, wordCount, personal foundCount and xpEarned.
	-- myXP mirrors earned XP; myPuzzlePieces remains a separate reward.
	Duel = {
		Folder = "Duel",
		RequestPlayerList = "RequestPlayerList",
		SendChallenge = "SendChallenge",
		RespondChallenge = "RespondChallenge",
		ReportProgress = "ReportDuelProgress",
		ReportCompletion = "ReportDuelCompletion",
		Abandon = "AbandonDuel",
		Rematch = "RequestDuelRematch", -- matchId; server broadcasts rematch availability/count via Match
		Challenge = "DuelChallenge",
		Match = "DuelMatch",
		Progress = "DuelProgress",
	},
}

local function countEntries(value, limit)
	local count = 0
	for _ in pairs(value) do
		count += 1
		if count > limit then
			break
		end
	end
	return count
end

function NetworkContract.IsBoundedValue(value, depth, seen)
	local valueType = typeof(value)
	if valueType == "nil" or valueType == "boolean" then
		return true
	elseif valueType == "number" then
		return value == value and value > -math.huge and value < math.huge
	elseif valueType == "string" then
		return #value <= 256
	end
	if valueType ~= "table" then
		return false
	end

	local currentDepth = math.max(0, math.floor(tonumber(depth) or 0))
	if currentDepth >= NetworkContract.Limits.MaximumDepth
		or countEntries(value, NetworkContract.Limits.MaximumEntries) > NetworkContract.Limits.MaximumEntries then
		return false
	end
	seen = seen or {}
	if seen[value] then
		return false
	end
	seen[value] = true
	for key, child in pairs(value) do
		if (type(key) ~= "string" and type(key) ~= "number")
			or (type(key) == "number" and (key ~= key or key <= -math.huge or key >= math.huge))
			or not NetworkContract.IsBoundedValue(child, currentDepth + 1, seen) then
			seen[value] = nil
			return false
		end
	end
	seen[value] = nil
	return true
end

function NetworkContract.ValidateTrackAction(actionName, payload)
	if type(actionName) ~= "string" or NetworkContract.TrackActions[actionName] == nil then
		return false
	end
	payload = payload == nil and {} or payload
	if type(payload) ~= "table" or not NetworkContract.IsBoundedValue(payload) then
		return false
	end

	local step = payload.step or payload.name
	return type(step) == "string" and #step >= 1 and #step <= NetworkContract.Limits.MaximumFunnelStepLength
		and string.match(step, "^[%w_]+$") ~= nil
end

function NetworkContract.ConsumeRateLimit(rateState, userId, actionName, now)
	local action = NetworkContract.TrackActions[actionName]
	if not action then
		return false
	end
	local playerRates = rateState[userId]
	if not playerRates then
		playerRates = {}
		rateState[userId] = playerRates
	end
	local currentTime = tonumber(now) or os.clock()
	local lastAt = tonumber(playerRates[actionName]) or -math.huge
	if currentTime - lastAt < action.throttle then
		return false
	end
	playerRates[actionName] = currentTime
	return true
end

return NetworkContract
