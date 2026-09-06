local NetworkContract = {
	FolderName = "WordSearchBackendRemotes",
	GetBootstrap = "GetBootstrap",
	TrackAction = "TrackAction",
	StateUpdated = "StateUpdated",
	UseHint = "UseHint",
	Limits = {
		MaximumDepth = 4,
		MaximumEntries = 96,
		MaximumWordLength = 32,
		MaximumPathLength = 32,
		MaximumFunnelStepLength = 96,
		MaximumAdminMessageLength = 180,
	},
}

NetworkContract.TrackActions = {
	WordFound = { throttle = 0.05 },
	BoardStateUpdated = { throttle = 0.1 },
	BoardStateCleared = { throttle = 0.05 },
	BoardCleared = { throttle = 0.1 },
	BoardLost = { throttle = 0.1 },
	HintUsed = { throttle = 0.1 },
	ClientFunnel = { throttle = 0.25 },
}

NetworkContract.Legacy = {
	Folder = "Remotes",
	Events = "Events",
	Functions = "Functions",
	PurchaseHints = "PurchaseHintsWithCoins",
	GetDailyRewardState = "GetDailyRewardState",
	ClaimDailyReward = "ClaimDailyReward",
	CheckHints = "CheckHints",
	ClaimTimedReward = "ClaimTimedReward",
	AdminAction = "AdminAction",
	PurchaseSuccess = "PurchaseSuccess",
	ClaimGift = "ClaimGift",
	PlayerJoinedGroup = "PlayerJoinedGroup",
	GroupHintAwarded = "GroupHintAwarded",
	UpdateSetting = "UpdateSetting",
	Rejoin = "RejoinRemote",
	AdminMessage = "AdminMessage",
	AdminBoardReset = "AdminBoardReset",
	LeaderboardUpdate = "LeaderboardUpdateSolves",
	LeaderboardRequest = "RequestLeaderboardUpdateSolves",
	Duel = {
		Folder = "Duel",
		RequestPlayerList = "RequestPlayerList",
		SendChallenge = "SendChallenge",
		RespondChallenge = "RespondChallenge",
		ReportProgress = "ReportDuelProgress",
		ReportCompletion = "ReportDuelCompletion",
		Abandon = "AbandonDuel",
		Challenge = "DuelChallenge",
		Match = "DuelMatch",
		Progress = "DuelProgress",
	},
}

local VALID_MODES = {
	Classic = true,
	Themed = true,
	Freeplay = true,
	Backwards = true,
	Fog = true,
	OneLife = true,
	Mega = true,
	Daily = true,
	Duel = true,
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

local function isIntegerInRange(value, minimum, maximum)
	local numeric = tonumber(value)
	return numeric ~= nil and numeric == math.floor(numeric) and numeric >= minimum and numeric <= maximum
end

local function validateWord(word)
	return type(word) == "string" and #word >= 1 and #word <= NetworkContract.Limits.MaximumWordLength
end

local function validateWordArray(words)
	if type(words) ~= "table" or #words > 24 then
		return false
	end
	for _, word in ipairs(words) do
		if not validateWord(word) then
			return false
		end
	end
	return true
end

local function validatePath(path)
	if type(path) ~= "table" or #path < 1 or #path > NetworkContract.Limits.MaximumPathLength then
		return false
	end
	for _, point in ipairs(path) do
		if type(point) ~= "table" or not isIntegerInRange(point.row, 1, 32) or not isIntegerInRange(point.column, 1, 32) then
			return false
		end
	end
	return true
end

function NetworkContract.ValidateBoardState(boardState)
	if type(boardState) ~= "table" or not NetworkContract.IsBoundedValue(boardState) then
		return false
	end
	if VALID_MODES[boardState.mode] ~= true or boardState.mode == "Duel" then
		return false
	end
	if not isIntegerInRange(boardState.level, 1, 10000)
		or not isIntegerInRange(boardState.seed, 1, 2147483647)
		or not validateWordArray(boardState.foundWords or {})
		or not validateWordArray(boardState.hintedWords or {}) then
		return false
	end
	for _, fieldName in ipairs({ "sessionScore", "puzzlesCleared", "streak", "hintUses" }) do
		if boardState[fieldName] ~= nil and not isIntegerInRange(boardState[fieldName], 0, 1000000000) then
			return false
		end
	end
	return boardState.startedAtServerTime == nil
		or (type(boardState.startedAtServerTime) == "number" and boardState.startedAtServerTime >= 0)
end

function NetworkContract.ValidateTrackAction(actionName, payload)
	if type(actionName) ~= "string" or NetworkContract.TrackActions[actionName] == nil then
		return false
	end
	payload = payload == nil and {} or payload
	if type(payload) ~= "table" or not NetworkContract.IsBoundedValue(payload) then
		return false
	end

	local boardState = payload.boardState
	if boardState and not NetworkContract.ValidateBoardState(boardState) then
		return false
	end
	if actionName == "WordFound" then
		return validateWord(payload.word) and validatePath(payload.path)
	elseif actionName == "HintUsed" then
		return validateWord(payload.word)
	elseif actionName == "ClientFunnel" then
		local step = payload.step or payload.name
		return type(step) == "string"
			and #step >= 1
			and #step <= NetworkContract.Limits.MaximumFunnelStepLength
			and string.match(step, "^[%w_]+$") ~= nil
	end
	return true
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
