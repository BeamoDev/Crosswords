local MetaService = {}

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local servicesFolder = script.Parent.Parent
local serverFolder = servicesFolder.Parent
local PlayerDataStore = require(serverFolder:WaitForChild("data"):WaitForChild("PlayerDataStore"))
local AnalyticsService = require(servicesFolder:WaitForChild("ops"):WaitForChild("AnalyticsService"))
local WebhookService = require(servicesFolder:WaitForChild("ops"):WaitForChild("WebhookService"))
local utilFolder = serverFolder:WaitForChild("utils")
local SharedConfig = require(utilFolder:WaitForChild("SharedConfig"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local PuzzleEconomy = require(sharedFolder:WaitForChild("config"):WaitForChild("PuzzleEconomy"))
local GiftProgress = require(sharedFolder:WaitForChild("progression"):WaitForChild("GiftProgress"))

local DEFAULT_META_CONFIG = {
	GROUP = {
		Id = 34241464,
		RewardHints = 2,
		RewardXp = 0,
	},
	DEFAULTS = {
		StartingHints = 0,
		Settings = {
			SFX = true,
			Music = true,
		},
	},
	HINT_PRODUCT_IDS = {
		[1] = 3573028208,
		[5] = 3573028342,
		[25] = 3573028459,
	},
	TIMED_PRODUCT_IDS = {
		TimeBoost = 3573028604,
		FreezeTime = 3573028785,
	},
	DAILY_REWARD = {
		BaseXp = 0,
		StepXp = 0,
		MaxXp = 0,
		HintEvery = 1,
		HintAmount = 1,
	},
	GIFT = {
		HintReward = 1,
	},
}

local MetaConfig = SharedConfig.Resolve("MetaConfig", DEFAULT_META_CONFIG)

local function getCurrentDay()
	return math.floor(os.time() / 86400)
end

local function clampInt(value, minimum)
	return math.max(minimum or 0, math.floor(tonumber(value) or 0))
end

local function normalizeReceiptId(receiptId)
	if receiptId == nil then
		return nil
	end

	local normalized = tostring(receiptId)
	if normalized == "" then
		return nil
	end

	return normalized
end

local function normalizeProcessedReceipts(processedReceipts)
	if type(processedReceipts) ~= "table" then
		return {}
	end

	local entries = {}
	for receiptId, receiptTimestamp in pairs(processedReceipts) do
		local normalizedId = normalizeReceiptId(receiptId)
		if normalizedId then
			table.insert(entries, {
				id = normalizedId,
				timestamp = clampInt(receiptTimestamp, 0),
			})
		end
	end

	table.sort(entries, function(left, right)
		if left.timestamp == right.timestamp then
			return left.id < right.id
		end
		return left.timestamp > right.timestamp
	end)

	local normalized = {}
	for index, entry in ipairs(entries) do
		if index > 150 then
			break
		end
		normalized[entry.id] = entry.timestamp
	end

	return normalized
end

local function hasProcessedReceipt(data, receiptId)
	local normalizedId = normalizeReceiptId(receiptId)
	if not normalizedId then
		return false
	end

	local processedReceipts = type(data.account and data.account.processedReceipts) == "table"
		and data.account.processedReceipts
		or nil
	return processedReceipts and processedReceipts[normalizedId] ~= nil or false
end

local function markProcessedReceipt(data, receiptId)
	local normalizedId = normalizeReceiptId(receiptId)
	if not normalizedId then
		return
	end

	data.account = data.account or {}
	data.account.processedReceipts = normalizeProcessedReceipts(data.account.processedReceipts)
	data.account.processedReceipts[normalizedId] = os.time()
	data.account.processedReceipts = normalizeProcessedReceipts(data.account.processedReceipts)
end

local function ensureActivityState(data)
	data.activity = data.activity or {}
	local activity = data.activity
	local currentDay = getCurrentDay()

	activity.dailyDayStamp = clampInt(activity.dailyDayStamp, -1)
	if activity.dailyDayStamp ~= currentDay then
		activity.dailyDayStamp = currentDay
		activity.dailyBoardsCleared = 0
		activity.dailyWordsFound = 0
	end

	activity.dailyBoardsCleared = clampInt(activity.dailyBoardsCleared)
	activity.dailyWordsFound = clampInt(activity.dailyWordsFound)
	activity.dailyClassicBoards = nil
	activity.dailyBackwardsBoards = nil
	activity.dailyFreeplayBoards = nil

	return activity
end

local function ensureMetaProgression(data)
	data.resources = data.resources or {}
	data.resources.hintsAvailable = clampInt(data.resources.hintsAvailable, 0)
	data.resources.timeBoostsAvailable = clampInt(data.resources.timeBoostsAvailable, 0)
	data.resources.freezeTimeAvailable = clampInt(data.resources.freezeTimeAvailable, 0)
	data.resources.puzzlePieces = clampInt(data.resources.puzzlePieces, 0)
	data.progression = data.progression or {}
	data.progression.giftClaimMilestone = clampInt(data.progression.giftClaimMilestone, 0)

	data.account = data.account or {}
	if data.account.groupRewardClaimed == nil then
		data.account.groupRewardClaimed = false
	end
	data.account.processedReceipts = normalizeProcessedReceipts(data.account.processedReceipts)
	data.account.newPlayer = nil
	data.account.tutorialCompleted = nil

	data.settings = data.settings or {}
	for key, value in pairs(MetaConfig.DEFAULTS.Settings) do
		if data.settings[key] == nil then
			data.settings[key] = value
		end
	end
	for key in pairs(data.settings) do
		if MetaConfig.DEFAULTS.Settings[key] == nil then
			data.settings[key] = nil
		end
	end

	data.dailyReward = data.dailyReward or {}
	if data.dailyReward.currentStreak == nil then
		data.dailyReward.currentStreak = 0
	end
	if data.dailyReward.bestStreak == nil then
		data.dailyReward.bestStreak = 0
	end
	if data.dailyReward.lastClaimDay == nil then
		data.dailyReward.lastClaimDay = -1
	end

	data.dailyMode = data.dailyMode or {}
	if data.dailyMode.completedDayStamp == nil then
		data.dailyMode.completedDayStamp = -1
	end
	data.questState = nil

	ensureActivityState(data)
end

function MetaService.NormalizeData(data)
	ensureMetaProgression(data)
	return data
end

local function getDailyRewardForStreak(streak)
	local config = MetaConfig.DAILY_REWARD
	local xp = 0
	local hints = math.max(1, clampInt(config.HintAmount, 1))
	if streak > 0 and streak % math.max(1, clampInt(config.HintEvery, 1)) == 0 then
		hints += 1
	end
	return {
		xp = xp,
		hints = hints,
	}
end

local function sendPurchaseWebhook(player, productName, productId, grantText, color)
	if not player then
		return
	end

	local report = string.format(
		"%s Purchased\nProduct ID: %d\nGranted: %s",
		tostring(productName or "Unknown Product"),
		math.max(0, math.floor(tonumber(productId) or 0)),
		tostring(grantText or "Unknown")
	)
	WebhookService.FireWebhook(player, report, false, color)
end

local function awardRewards(player, data, reward)
	local hintsGranted = clampInt(reward.rewardHints)
	local xpGranted = 0

	if hintsGranted > 0 then
		data.resources.hintsAvailable = clampInt(data.resources.hintsAvailable) + hintsGranted
	end

	return {
		hintsGranted = hintsGranted,
		xpGranted = xpGranted,
	}
end

function MetaService.OnPlayerLoaded(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)
	PlayerDataStore.GetSnapshot(player)
end

function MetaService.GetAvailableHints(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)
	PlayerDataStore.GetSnapshot(player)
	return clampInt(data.resources.hintsAvailable)
end

function MetaService.TryConsumeHint(player, mode)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)
	if clampInt(data.resources.hintsAvailable) <= 0 then
		return {
			success = false,
			message = "No hints available.",
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	data.resources.hintsAvailable -= 1
	AnalyticsService.TrackHintUsed(player, tostring(mode or "unknown"))

	return {
		success = true,
		snapshot = PlayerDataStore.GetSnapshot(player),
	}
end

function MetaService.PurchaseHintsWithStars(player, amount)
	local hintAmount = clampInt(amount, 0)
	local pieceCost = PuzzleEconomy.GetHintPackCost(hintAmount)
	if not pieceCost then
		return {
			success = false,
			code = "invalid_pack",
			message = "Hint pack purchase is unavailable right now.",
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)

	local currentPieces = clampInt(data.resources.puzzlePieces, 0)
	if currentPieces < pieceCost then
		return {
			success = false,
			code = "insufficient_pieces",
			message = "Not enough Puzzle Pieces!",
			cost = pieceCost,
			balance = currentPieces,
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	data.resources.puzzlePieces = currentPieces - pieceCost
	data.resources.hintsAvailable = clampInt(data.resources.hintsAvailable, 0) + hintAmount

	AnalyticsService.TrackEconomySink(player, "pieces", "hint_pack_purchase", pieceCost, {
		hints = hintAmount,
	})
	AnalyticsService.TrackEconomySource(player, "hints", "piece_shop_purchase", hintAmount, {
		cost = pieceCost,
	})
	AnalyticsService.TrackCriticalStep(player, "HintPackPurchasedWithPieces", {
		hints = hintAmount,
		cost = pieceCost,
	})

	return {
		success = true,
		amount = hintAmount,
		cost = pieceCost,
		balance = data.resources.puzzlePieces,
		snapshot = PlayerDataStore.GetSnapshot(player),
	}
end

function MetaService.GetDailyRewardState(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)

	local currentDay = getCurrentDay()
	local streakData = data.dailyReward
	local claimable = streakData.lastClaimDay < currentDay
	local projectedStreak
	if streakData.lastClaimDay == currentDay or streakData.lastClaimDay == currentDay - 1 then
		projectedStreak = clampInt(streakData.currentStreak) + 1
	else
		projectedStreak = 1
	end
	local nextReward = getDailyRewardForStreak(projectedStreak)

	return {
		success = true,
		claimable = claimable,
		currentStreak = clampInt(streakData.currentStreak),
		bestStreak = clampInt(streakData.bestStreak),
		nextRewardXp = nextReward.xp,
		nextRewardHints = nextReward.hints,
		secondsUntilReset = math.max(0, ((currentDay + 1) * 86400) - os.time()),
		alreadyClaimedToday = streakData.lastClaimDay == currentDay,
	}
end

function MetaService.ClaimDailyReward(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)

	local state = MetaService.GetDailyRewardState(player)
	if not state.success then
		return state
	end
	if not state.claimable then
		return {
			success = false,
			message = "Already claimed today.",
			state = state,
		}
	end

	local currentDay = getCurrentDay()
	local streakData = data.dailyReward
	if streakData.lastClaimDay == currentDay - 1 then
		streakData.currentStreak = clampInt(streakData.currentStreak) + 1
	else
		streakData.currentStreak = 1
	end
	streakData.bestStreak = math.max(clampInt(streakData.bestStreak), clampInt(streakData.currentStreak))
	streakData.lastClaimDay = currentDay

	local reward = getDailyRewardForStreak(streakData.currentStreak)
	awardRewards(player, data, {
		rewardXp = reward.xp,
		rewardHints = reward.hints,
	})

	if reward.hints > 0 then
		AnalyticsService.TrackEconomySource(player, "hints", "daily_reward", reward.hints, {
			streak = streakData.currentStreak,
		})
	end
	AnalyticsService.TrackCriticalStep(player, "DailyRewardClaimed", {
		streak = streakData.currentStreak,
	})

	return {
		success = true,
		rewardXp = reward.xp,
		rewardHints = reward.hints,
		state = MetaService.GetDailyRewardState(player),
		snapshot = PlayerDataStore.GetSnapshot(player),
	}
end

function MetaService.ClaimGiftReward(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)

	local stats = data.stats or {}
	local modeResults = type(stats.modeResults) == "table" and stats.modeResults or nil
	local totalWins = math.max(
		clampInt(stats.boardsCleared, 0),
		clampInt(modeResults and modeResults.Total and modeResults.Total.wins, 0)
	)
	local claimedMilestone = clampInt(data.progression and data.progression.giftClaimMilestone, 0)
	local giftState = GiftProgress.GetProgressState(totalWins, claimedMilestone)

	if giftState.ready ~= true then
		return {
			success = false,
			message = giftState.winsRemaining > 0
				and string.format("Win %d more to claim the gift.", giftState.winsRemaining)
				or "Gift is not ready yet.",
			state = giftState,
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	local rewardHints = math.max(1, clampInt(MetaConfig.GIFT.HintReward, 1))
	data.progression.giftClaimMilestone = giftState.nextMilestone
	data.resources.hintsAvailable = clampInt(data.resources.hintsAvailable, 0) + rewardHints

	AnalyticsService.TrackEconomySource(player, "hints", "gift_claim", rewardHints, {
		milestone = giftState.nextMilestone,
		totalWins = totalWins,
	})
	AnalyticsService.TrackCriticalStep(player, "OutcomeGiftClaimed", {
		milestone = giftState.nextMilestone,
		totalWins = totalWins,
	})

	return {
		success = true,
		rewardHints = rewardHints,
		milestone = giftState.nextMilestone,
		state = GiftProgress.GetProgressState(totalWins, data.progression.giftClaimMilestone),
		snapshot = PlayerDataStore.GetSnapshot(player),
	}
end

function MetaService.UpdateSetting(player, settingName, value)
	if type(settingName) ~= "string" or type(value) ~= "boolean" then
		return false
	end

	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)
	if data.settings[settingName] == nil then
		return false
	end

	data.settings[settingName] = value
	PlayerDataStore.GetSnapshot(player)
	return true
end

function MetaService.ClaimGroupReward(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)

	local ok = pcall(function()
		GroupService:GetGroupInfoAsync(MetaConfig.GROUP.Id)
	end)
	if not ok then
		return { success = false, message = "Group unavailable." }
	end

	local inGroup = false
	pcall(function()
		inGroup = player:IsInGroup(MetaConfig.GROUP.Id)
	end)
	if not inGroup then
		return { success = false, message = "Player is not in group." }
	end

	if data.account.groupRewardClaimed then
		return {
			success = true,
			rewardHints = 0,
			rewardXp = 0,
			alreadyClaimed = true,
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	data.account.groupRewardClaimed = true
	data.resources.hintsAvailable += MetaConfig.GROUP.RewardHints

	AnalyticsService.TrackEconomySource(player, "hints", "group_verify", MetaConfig.GROUP.RewardHints, {})
	AnalyticsService.TrackCriticalStep(player, "GroupVerifyClaimed", {})

	return {
		success = true,
		rewardHints = MetaConfig.GROUP.RewardHints,
		rewardXp = MetaConfig.GROUP.RewardXp,
		snapshot = PlayerDataStore.GetSnapshot(player),
	}
end

function MetaService.GrantProductPurchase(player, productId, receiptId)
	local normalizedReceiptId = normalizeReceiptId(receiptId)
	if not normalizedReceiptId then
		return nil
	end

	local data = PlayerDataStore.GetMutableData(player)
	ensureMetaProgression(data)
	if hasProcessedReceipt(data, normalizedReceiptId) then
		return {
			success = true,
			alreadyProcessed = true,
			kind = "duplicate_receipt",
			amount = 0,
		}
	end

	local hintAmount = nil
	for count, id in pairs(MetaConfig.HINT_PRODUCT_IDS) do
		if id == productId then
			hintAmount = count
			break
		end
	end

	if hintAmount then
		data.resources.hintsAvailable += hintAmount
		markProcessedReceipt(data, normalizedReceiptId)
		sendPurchaseWebhook(
			player,
			string.format("%d Hint%s", hintAmount, hintAmount == 1 and "" or "s"),
			productId,
			string.format("%d Hint%s", hintAmount, hintAmount == 1 and "" or "s"),
			hintAmount == 1 and 0x87CEEB or hintAmount == 5 and 0x7FFF00 or hintAmount == 25 and 0x00FF7F or 0xFFD700
		)
		AnalyticsService.TrackEconomySource(player, "hints", "dev_product", hintAmount, {
			productId = productId,
		})
		AnalyticsService.TrackCriticalStep(player, "HintProductPurchased", {
			productId = productId,
			hints = hintAmount,
		})
		return {
			success = true,
			kind = "hints",
			amount = hintAmount,
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	if MetaConfig.TIMED_PRODUCT_IDS.TimeBoost == productId then
		data.resources.timeBoostsAvailable += 1
		markProcessedReceipt(data, normalizedReceiptId)
		sendPurchaseWebhook(
			player,
			"+2 Minutes",
			productId,
			"1 Time Boost",
			0x5AA9FF
		)
		AnalyticsService.TrackEconomySource(player, "time_boost", "dev_product", 1, {
			productId = productId,
		})
		AnalyticsService.TrackCriticalStep(player, "TimeBoostProductPurchased", {
			productId = productId,
		})
		return {
			success = true,
			kind = "time_boost",
			amount = 1,
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	if MetaConfig.TIMED_PRODUCT_IDS.FreezeTime == productId then
		data.resources.freezeTimeAvailable += 1
		markProcessedReceipt(data, normalizedReceiptId)
		sendPurchaseWebhook(
			player,
			"Freeze Timer (30 Seconds)",
			productId,
			"1 Freeze Time",
			0xA8F0FF
		)
		AnalyticsService.TrackEconomySource(player, "freeze_time", "dev_product", 1, {
			productId = productId,
		})
		AnalyticsService.TrackCriticalStep(player, "FreezeTimeProductPurchased", {
			productId = productId,
		})
		return {
			success = true,
			kind = "freeze_time",
			amount = 1,
			snapshot = PlayerDataStore.GetSnapshot(player),
		}
	end

	return nil
end

function MetaService.GetMetaSnapshot(player)
	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)
	return PlayerDataStore.GetSnapshot(player)
end

return MetaService
