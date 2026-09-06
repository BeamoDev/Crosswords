local RewardService = {}

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent.Parent
local systemsFolder = serverFolder:WaitForChild("systems")
local AnalyticsService = require(systemsFolder:WaitForChild("Analytics"))
local Operations = require(systemsFolder:WaitForChild("Operations"))
local DataService = require(serverFolder:WaitForChild("data"):WaitForChild("DataService"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local GameConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("GameConfig"))
local ProgressionConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local PuzzleEconomy = GameConfig.Economy
local MetaConfig = GameConfig.Meta
local GiftProgress = ProgressionConfig.Gift
local TimedRewards = ProgressionConfig.TimedRewards

-- Account rewards, settings, purchases, and receipt compatibility.
local RETIRED_PRODUCT_HINT_GRANTS = {
	[3573028604] = 1,
	[3573028785] = 1,
}

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
	data.resources.timeBoostsAvailable = nil
	data.resources.freezeTimeAvailable = nil
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

function RewardService.NormalizeData(data)
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
	Operations.FireWebhook(player, report, false, color)
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

function RewardService.OnPlayerLoaded(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	DataService.GetSnapshot(player)
end

function RewardService.GetAvailableHints(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	DataService.GetSnapshot(player)
	return clampInt(data.resources.hintsAvailable)
end

function RewardService.TryConsumeHint(player, mode)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	if clampInt(data.resources.hintsAvailable) <= 0 then
		return {
			success = false,
			message = "No hints available.",
			snapshot = DataService.GetSnapshot(player),
		}
	end

	data.resources.hintsAvailable -= 1
	AnalyticsService.TrackHintUsed(player, tostring(mode or "unknown"))

	return {
		success = true,
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.PurchaseHintsWithStars(player, amount)
	local hintAmount = clampInt(amount, 0)
	local pieceCost = PuzzleEconomy.GetHintPackCost(hintAmount)
	if not pieceCost then
		return {
			success = false,
			code = "invalid_pack",
			message = "Hint pack purchase is unavailable right now.",
			snapshot = DataService.GetSnapshot(player),
		}
	end

	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)

	local currentPieces = clampInt(data.resources.puzzlePieces, 0)
	if currentPieces < pieceCost then
		return {
			success = false,
			code = "insufficient_pieces",
			message = "Not enough Puzzle Pieces!",
			cost = pieceCost,
			balance = currentPieces,
			snapshot = DataService.GetSnapshot(player),
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
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.GetDailyRewardState(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)

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

function RewardService.ClaimDailyReward(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)

	local state = RewardService.GetDailyRewardState(player)
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
		state = RewardService.GetDailyRewardState(player),
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.ClaimGiftReward(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)

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
			snapshot = DataService.GetSnapshot(player),
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
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.UpdateSetting(player, settingName, value)
	if type(settingName) ~= "string" or type(value) ~= "boolean" then
		return false
	end

	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	if data.settings[settingName] == nil then
		return false
	end

	data.settings[settingName] = value
	DataService.GetSnapshot(player)
	return true
end

function RewardService.ClaimGroupReward(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)

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
			snapshot = DataService.GetSnapshot(player),
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
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.GrantProductPurchase(player, productId, receiptId)
	local normalizedReceiptId = normalizeReceiptId(receiptId)
	if not normalizedReceiptId then
		return nil
	end

	local data = DataService.GetMutableData(player)
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
			snapshot = DataService.GetSnapshot(player),
		}
	end

	local retiredHintGrant = RETIRED_PRODUCT_HINT_GRANTS[productId]
	if retiredHintGrant then
		data.resources.hintsAvailable += retiredHintGrant
		markProcessedReceipt(data, normalizedReceiptId)
		sendPurchaseWebhook(
			player,
			"Retired Gameplay Product",
			productId,
			string.format("%d Hint", retiredHintGrant),
			0x87CEEB
		)
		AnalyticsService.TrackEconomySource(player, "hints", "retired_product_conversion", retiredHintGrant, {
			productId = productId,
		})
		AnalyticsService.TrackCriticalStep(player, "RetiredProductConverted", {
			productId = productId,
			hints = retiredHintGrant,
		})
		return {
			success = true,
			kind = "hints",
			amount = retiredHintGrant,
			snapshot = DataService.GetSnapshot(player),
		}
	end

	return nil
end

function RewardService.GetMetaSnapshot(player)
	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	return DataService.GetSnapshot(player)
end


-- Session playtime rewards.
local trackingStarted = false

local function ensureTimedRewardsData(data)
	data = type(data) == "table" and data or {}
	data.timedRewards = type(data.timedRewards) == "table" and data.timedRewards or {}
	data.timedRewards.playtimeSeconds = math.max(0, math.floor(tonumber(data.timedRewards.playtimeSeconds or data.timedRewards.Playtime) or 0))
	data.timedRewards.rewardClaims = type(data.timedRewards.rewardClaims) == "table" and data.timedRewards.rewardClaims or {}

	for index = 1, TimedRewards.GetRewardCount() do
		local rewardName = TimedRewards.GetRewardValueName(index)
		data.timedRewards.rewardClaims[rewardName] = data.timedRewards.rewardClaims[rewardName] == true
			or data.timedRewards[rewardName] == true
	end

	return data.timedRewards
end

local function getTimedRewardsFolder(player)
	local data = player:FindFirstChild("Data")
	return data and data:FindFirstChild("TimedRewards") or nil
end

local function getNextRewardIndex(timedRewardsData)
	if type(timedRewardsData) ~= "table" then
		return nil
	end

	for index = 1, TimedRewards.GetRewardCount() do
		if timedRewardsData.rewardClaims[TimedRewards.GetRewardValueName(index)] ~= true then
			return index
		end
	end

	return nil
end

local function getLastClaimedRewardIndex(timedRewardsData)
	local lastClaimed = 0

	for index = 1, TimedRewards.GetRewardCount() do
		if timedRewardsData.rewardClaims[TimedRewards.GetRewardValueName(index)] == true then
			lastClaimed = index
		else
			break
		end
	end

	return lastClaimed
end

local function getRewardThreshold(index)
	local reward = TimedRewards.GetReward(index)
	return math.max(0, math.floor(tonumber(reward and reward.playtimeSeconds) or 0))
end

local function getEffectivePlaytimeSeconds(timedRewardsData)
	if type(timedRewardsData) ~= "table" then
		return 0
	end

	local storedPlaytime = math.max(0, math.floor(tonumber(timedRewardsData.playtimeSeconds) or 0))
	local lastClaimedIndex = getLastClaimedRewardIndex(timedRewardsData)
	if lastClaimedIndex <= 0 then
		local nextRewardIndex = getNextRewardIndex(timedRewardsData)
		if nextRewardIndex then
			local nextThreshold = getRewardThreshold(nextRewardIndex)
			if storedPlaytime > nextThreshold then
				storedPlaytime = nextThreshold
				timedRewardsData.playtimeSeconds = storedPlaytime
			end
		end
		return storedPlaytime
	end

	local claimedThreshold = getRewardThreshold(lastClaimedIndex)
	if claimedThreshold > storedPlaytime then
		storedPlaytime = claimedThreshold
		timedRewardsData.playtimeSeconds = storedPlaytime
	end

	local nextRewardIndex = getNextRewardIndex(timedRewardsData)
	if nextRewardIndex then
		local nextThreshold = getRewardThreshold(nextRewardIndex)
		if storedPlaytime > nextThreshold then
			storedPlaytime = nextThreshold
			timedRewardsData.playtimeSeconds = storedPlaytime
		end
	end

	return math.max(storedPlaytime, claimedThreshold)
end

local function getRewardCurrencyName(rewardType)
	if rewardType == "hints" then
		return "hints"
	end
	if rewardType == "pieces" then
		return "pieces"
	end
	return "unknown"
end

local function grantReward(player, data, reward)
	if reward.rewardType == "hints" then
		data.resources.hintsAvailable = math.max(0, math.floor(tonumber(data.resources.hintsAvailable) or 0)) + reward.amount
		return true
	end

	if reward.rewardType == "pieces" then
		data.resources.puzzlePieces = math.max(0, math.floor(tonumber(data.resources.puzzlePieces) or 0)) + reward.amount
		return true
	end

	return false, "Unsupported reward type"
end

function RewardService.GetState(player)
	local data = DataService.GetMutableData(player)
	if not data then
		return nil
	end

	local timedRewardsData = ensureTimedRewardsData(data)
	local playtimeSeconds = getEffectivePlaytimeSeconds(timedRewardsData)
	local nextRewardIndex = getNextRewardIndex(timedRewardsData)

	if not nextRewardIndex then
		return {
			allClaimed = true,
			canClaim = false,
			nextRewardIndex = nil,
			remainingSeconds = 0,
			playtimeSeconds = playtimeSeconds,
		}
	end

	local reward = TimedRewards.GetReward(nextRewardIndex)
	local remainingSeconds = math.max(0, math.floor((reward and reward.playtimeSeconds) or 0) - playtimeSeconds)

	return {
		allClaimed = false,
		canClaim = remainingSeconds <= 0,
		nextRewardIndex = nextRewardIndex,
		remainingSeconds = remainingSeconds,
		playtimeSeconds = playtimeSeconds,
		rewardType = reward and reward.rewardType or nil,
		rewardAmount = reward and reward.amount or nil,
	}
end

function RewardService.ClaimNextReward(player)
	local data = DataService.GetMutableData(player)
	if not data then
		return {
			success = false,
			message = "Timed rewards data missing",
		}
	end

	local state = RewardService.GetState(player)
	if not state then
		return {
			success = false,
			message = "Timed rewards data missing",
		}
	end

	if state.allClaimed then
		return {
			success = false,
			message = "All rewards already claimed",
			state = state,
		}
	end

	if not state.canClaim then
		return {
			success = false,
			message = "Reward not ready yet",
			state = state,
		}
	end

	local timedRewardsData = ensureTimedRewardsData(data)
	local rewardIndex = state.nextRewardIndex
	local rewardName = TimedRewards.GetRewardValueName(rewardIndex)
	local reward = TimedRewards.GetReward(rewardIndex)
	if not reward then
		return {
			success = false,
			message = "Reward data missing",
			state = state,
		}
	end

	local success, errorMessage = grantReward(player, data, reward)
	if not success then
		return {
			success = false,
			message = errorMessage,
			state = state,
		}
	end

	timedRewardsData.rewardClaims[rewardName] = true
	local snapshot = DataService.GetSnapshot(player)
	AnalyticsService.TrackEconomySource(player, getRewardCurrencyName(reward.rewardType), "timed_reward", reward.amount, {
		rewardIndex = rewardIndex,
	})

	return {
		success = true,
		message = "Reward claimed",
		rewardType = reward.rewardType,
		rewardAmount = reward.amount,
		state = RewardService.GetState(player),
		snapshot = snapshot,
	}
end

function RewardService.StartTracking()
	if trackingStarted then
		return
	end

	trackingStarted = true

	task.spawn(function()
		while true do
			task.wait(1)

			for _, player in ipairs(Players:GetPlayers()) do
				local data = DataService.GetMutableData(player)
				if not data then
					continue
				end

				local timedRewardsData = ensureTimedRewardsData(data)
				local nextRewardIndex = getNextRewardIndex(timedRewardsData)
				if not nextRewardIndex then
					continue
				end

				local nextThreshold = getRewardThreshold(nextRewardIndex)
				local currentPlaytime = getEffectivePlaytimeSeconds(timedRewardsData)
				if currentPlaytime >= nextThreshold then
					timedRewardsData.playtimeSeconds = nextThreshold
				else
					timedRewardsData.playtimeSeconds = math.min(nextThreshold, currentPlaytime + 1)
				end

				local timedRewardsFolder = getTimedRewardsFolder(player)
				local playtimeValue = timedRewardsFolder and timedRewardsFolder:FindFirstChild("Playtime")
				if playtimeValue and playtimeValue:IsA("IntValue") then
					playtimeValue.Value = timedRewardsData.playtimeSeconds
				end
			end
		end
	end)
end


return RewardService
