local RewardService = {}

local GroupService = game:GetService("GroupService")
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

	data.account.processedReceipts[normalizedId] = os.time()
end

local function getDailyRewardForStreak(streak)
	local config = MetaConfig.DAILY_REWARD
	local xp = 0
	local hints = math.max(1, clampInt(config.HintAmount, 1))
	local bonusEvery = clampInt(config.HintEvery)
	if bonusEvery > 0 and streak > 0 and streak % bonusEvery == 0 then
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
		data.hints = clampInt(data.hints) + hintsGranted
	end

	return {
		hintsGranted = hintsGranted,
		xpGranted = xpGranted,
	}
end

function RewardService.OnPlayerLoaded(player)
	local data = DataService.GetMutableData(player)
	DataService.GetSnapshot(player)
end

function RewardService.GetAvailableHints(player)
	local data = DataService.GetMutableData(player)
	DataService.GetSnapshot(player)
	return clampInt(data.hints)
end

function RewardService.TryConsumeHint(player, mode)
	local data = DataService.GetMutableData(player)
	if clampInt(data.hints) <= 0 then
		return {
			success = false,
			message = "No hints available.",
			snapshot = DataService.GetSnapshot(player),
		}
	end

	data.hints -= 1
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

	local currentPieces = clampInt(data.puzzlePieces, 0)
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

	data.puzzlePieces = currentPieces - pieceCost
	data.hints = clampInt(data.hints, 0) + hintAmount

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
		balance = data.puzzlePieces,
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.GetDailyRewardState(player)
	local data = DataService.GetMutableData(player)

	local currentDay = getCurrentDay()
	local streakData = data.dailyReward
	local claimable = streakData.lastClaimDay < currentDay
	local projectedStreak
	if streakData.lastClaimDay == currentDay or streakData.lastClaimDay == currentDay - 1 then
		projectedStreak = clampInt(streakData.streak) + 1
	else
		projectedStreak = 1
	end
	local nextReward = getDailyRewardForStreak(projectedStreak)

	return {
		success = true,
		claimable = claimable,
		streak = clampInt(streakData.streak),
		nextRewardXp = nextReward.xp,
		nextRewardHints = nextReward.hints,
		secondsUntilReset = math.max(0, ((currentDay + 1) * 86400) - os.time()),
		alreadyClaimedToday = streakData.lastClaimDay == currentDay,
	}
end

function RewardService.ClaimDailyReward(player)
	local data = DataService.GetMutableData(player)

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
		streakData.streak = clampInt(streakData.streak) + 1
	else
		streakData.streak = 1
	end
	streakData.lastClaimDay = currentDay

	local reward = getDailyRewardForStreak(streakData.streak)
	awardRewards(player, data, {
		rewardXp = reward.xp,
		rewardHints = reward.hints,
	})

	if reward.hints > 0 then
		AnalyticsService.TrackEconomySource(player, "hints", "daily_reward", reward.hints, {
			streak = streakData.streak,
		})
	end
	AnalyticsService.TrackCriticalStep(player, "DailyRewardClaimed", {
		streak = streakData.streak,
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

	local totalWins = data.progression.solves
	local claimedMilestone = clampInt(data.account and data.account.giftClaimMilestone, 0)
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
	data.account.giftClaimMilestone = giftState.nextMilestone
	data.hints = clampInt(data.hints, 0) + rewardHints

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
		state = GiftProgress.GetProgressState(totalWins, data.account.giftClaimMilestone),
		snapshot = DataService.GetSnapshot(player),
	}
end

function RewardService.UpdateSetting(player, settingName, value)
	if type(settingName) ~= "string" or type(value) ~= "boolean" then
		return false
	end

	local data = DataService.GetMutableData(player)
	if data.settings[settingName] == nil then
		return false
	end

	data.settings[settingName] = value
	DataService.GetSnapshot(player)
	return true
end

function RewardService.ClaimGroupReward(player)
	local data = DataService.GetMutableData(player)

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
	data.hints += MetaConfig.GROUP.RewardHints

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
	if hasProcessedReceipt(data, normalizedReceiptId) then
		return {
			success = true,
			alreadyProcessed = true,
			kind = "duplicate_receipt",
			amount = 0,
		}
	end

	local directHintProduct = MetaConfig.DIRECT_HINT_PRODUCT
	local hintAmount = directHintProduct and productId == directHintProduct.Id and directHintProduct.Amount or nil
	for count, id in pairs(MetaConfig.HINT_PRODUCT_IDS) do
		if id == productId then
			hintAmount = count
			break
		end
	end

	if hintAmount then
		data.hints += hintAmount
		markProcessedReceipt(data, normalizedReceiptId)
		sendPurchaseWebhook(
			player,
			string.format("%d Hint%s", hintAmount, hintAmount == 1 and "" or "s"),
			productId,
			string.format("%d Hint%s", hintAmount, hintAmount == 1 and "" or "s"),
			hintAmount == 1 and 0x87CEEB or hintAmount == 5 and 0x7FFF00 or hintAmount == 15 and 0x00FF7F or 0xFFD700
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
		data.hints += retiredHintGrant
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
	return DataService.GetSnapshot(player)
end


return RewardService
