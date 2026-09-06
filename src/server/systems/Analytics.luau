--!strict
local Analytics = {}

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local DataService = require(script.Parent.Parent:WaitForChild("data"):WaitForChild("DataService"))

type SessionState = {
	joinTime: number,
	sessionId: string,
	maxBoardMilestone: number,
	criticalStepCount: number,
	criticalSteps: { [string]: boolean },
}

local playerSessions: { [number]: SessionState } = {}
local MAX_BOARD_FUNNEL = 25
local MAX_CRITICAL_STEPS = 160

local function ensureSession(player: Player): SessionState
	local session = playerSessions[player.UserId]
	if session then
		return session
	end

	session = {
		joinTime = tick(),
		sessionId = HttpService:GenerateGUID(false),
		maxBoardMilestone = 0,
		criticalStepCount = 0,
		criticalSteps = {},
	}
	playerSessions[player.UserId] = session
	return session
end

local function serializeFields(fields: { [string]: any }?): { [string]: any }
	if type(fields) ~= "table" then
		return {}
	end

	local serialized = {}
	for key, value in pairs(fields) do
		local valueType = typeof(value)
		local keyName = tostring(key)
		if valueType == "string" or valueType == "number" or valueType == "boolean" then
			serialized[keyName] = value
		elseif value ~= nil then
			local ok, encoded = pcall(function()
				return HttpService:JSONEncode(value)
			end)
			serialized[keyName] = ok and encoded or tostring(value)
		end
	end

	return serialized
end

local function logCustomEvent(player: Player, eventName: string, value: number?, customFields: { [string]: any }?)
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, serializeFields(customFields))
	end)
	if not ok then
		warn("[WordSearch.Analytics] Custom event failed", eventName, err)
	end
end

local function logFunnelStep(player: Player, step: number, stepName: string, customFields: { [string]: any }?)
	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, serializeFields(customFields))
	end)
	if not ok then
		warn("[WordSearch.Analytics] Funnel step failed", stepName, err)
	end
end

local function getCurrencyBalance(player: Player, currency: string): number
	local mutableData = nil
	pcall(function()
		mutableData = DataService.GetMutableData(player)
	end)

	local normalized = string.lower(currency)
	if type(mutableData) == "table" then
		if normalized == "hints" then
			return math.max(0, math.floor(mutableData.hints or 0))
		elseif normalized == "pieces" or normalized == "puzzle_pieces" then
			return math.max(0, math.floor(mutableData.puzzlePieces or 0))
		end
		return 0
	end

	local data = player:FindFirstChild("Data")
	if not data then
		return 0
	end

	if normalized == "hints" then
		local hintsFolder = data:FindFirstChild("Hints")
		local availableValue = hintsFolder and hintsFolder:FindFirstChild("Available")
		return (availableValue and tonumber((availableValue :: any).Value)) or 0
	elseif normalized == "pieces" or normalized == "puzzle_pieces" then
		local puzzlePieces = data:FindFirstChild("PuzzlePieces")
		return (puzzlePieces and tonumber((puzzlePieces :: any).Value)) or 0
	end

	return 0
end

local function logEconomyEvent(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	customFields: { [string]: any }?
)
	local ok, err = pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currencyType,
			amount,
			endingBalance,
			transactionType,
			itemSku or "",
			serializeFields(customFields)
		)
	end)
	if not ok then
		warn("[WordSearch.Analytics] Economy event failed", transactionType, err)
	end
end

function Analytics.InitPlayer(player: Player)
	local session = ensureSession(player)
	logCustomEvent(player, "PlayerJoined", 1, {
		sessionId = session.sessionId,
	})
end

function Analytics.PlayerLeft(player: Player)
	local session = playerSessions[player.UserId]
	if not session then
		return
	end

	logCustomEvent(player, "SessionEnd", math.floor(tick() - session.joinTime), {
		sessionId = session.sessionId,
		duration = math.floor(tick() - session.joinTime),
		maxBoardMilestone = session.maxBoardMilestone,
	})
	playerSessions[player.UserId] = nil
end

function Analytics.TrackBoardMilestone(player: Player, boardsCleared: number)
	local session = ensureSession(player)
	local count = math.max(0, math.floor(tonumber(boardsCleared) or 0))
	if count <= session.maxBoardMilestone then
		return
	end

	for milestone = session.maxBoardMilestone + 1, math.min(count, MAX_BOARD_FUNNEL) do
		local ok, err = pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, milestone, string.format("Board %d", milestone), {
				sessionId = session.sessionId,
				boardsCleared = milestone,
			})
		end)
		if not ok then
			warn("[WordSearch.Analytics] Funnel step failed", milestone, err)
		end
	end

	session.maxBoardMilestone = math.max(session.maxBoardMilestone, math.min(count, MAX_BOARD_FUNNEL))
	logCustomEvent(player, "BoardMilestone", count, {
		sessionId = session.sessionId,
		boardsCleared = count,
	})
end

function Analytics.TrackCriticalStep(player: Player, stepName: string, details: { [string]: any }?)
	local session = ensureSession(player)
	local key = tostring(stepName or "Unknown")
	if session.criticalSteps[key] then
		return
	end
	if session.criticalStepCount >= MAX_CRITICAL_STEPS then
		return
	end

	session.criticalSteps[key] = true
	session.criticalStepCount += 1
	local fields = serializeFields(details)
	fields.step = key
	fields.sessionId = session.sessionId
	logCustomEvent(player, "FunnelStep", 1, fields)
end

function Analytics.TrackModeComplete(player: Player, mode: string, details: { [string]: any }?)
	local fields = serializeFields(details)
	fields.mode = tostring(mode or "unknown")
	logCustomEvent(player, "ModeComplete", 1, fields)
end

function Analytics.TrackHintUsed(player: Player, mode: string)
	logCustomEvent(player, "HintUsed", 1, {
		mode = tostring(mode or "unknown"),
	})
end

function Analytics.TrackDuelChallenge(player: Player, mode: string)
	logCustomEvent(player, "DuelChallenge", 1, {
		mode = tostring(mode or "unknown"),
	})
end

function Analytics.TrackDuelComplete(player: Player, isWinner: boolean, mode: string, duration: number?)
	logCustomEvent(player, "DuelComplete", isWinner and 1 or 0, {
		mode = tostring(mode or "unknown"),
		isWinner = isWinner == true,
		duration = math.max(0, math.floor(tonumber(duration) or 0)),
	})
end

function Analytics.TrackCustomEvent(player: Player, eventName: string, value: number?, details: { [string]: any }?)
	logCustomEvent(player, eventName, value, details)
end

function Analytics.TrackEconomySource(
	player: Player,
	currency: string,
	sourceType: string,
	amount: number,
	details: { [string]: any }?
)
	local numericAmount = math.max(0, math.floor(tonumber(amount) or 0))
	local currencyName = tostring(currency or "unknown")
	local balance = getCurrencyBalance(player, currencyName)
	local fields = serializeFields(details)
	fields.currency = currencyName
	fields.sourceType = tostring(sourceType or "unknown")
	fields.amount = numericAmount
	fields.endingBalance = balance

	logEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		currencyName,
		numericAmount,
		balance,
		fields.sourceType,
		fields.itemSku,
		fields
	)
	logCustomEvent(player, "EconomySource", numericAmount, fields)
end

function Analytics.TrackEconomySink(
	player: Player,
	currency: string,
	sinkType: string,
	amount: number,
	details: { [string]: any }?
)
	local numericAmount = math.max(0, math.floor(tonumber(amount) or 0))
	local currencyName = tostring(currency or "unknown")
	local balance = getCurrencyBalance(player, currencyName)
	local fields = serializeFields(details)
	fields.currency = currencyName
	fields.sinkType = tostring(sinkType or "unknown")
	fields.amount = numericAmount
	fields.endingBalance = balance

	logEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		currencyName,
		numericAmount,
		balance,
		fields.sinkType,
		fields.itemSku,
		fields
	)
	logCustomEvent(player, "EconomySink", numericAmount, fields)
end

return Analytics
