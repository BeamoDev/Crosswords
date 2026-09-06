local BadgeService = game:GetService("BadgeService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent
local servicesFolder = serverFolder:WaitForChild("services")
local dataFolder = serverFolder:WaitForChild("data")
local systemsFolder = serverFolder:WaitForChild("systems")
local sharedFolder = ReplicatedStorage:WaitForChild("shared")

local Analytics = require(systemsFolder:WaitForChild("Analytics"))
local Utility = require(sharedFolder:WaitForChild("utility"):WaitForChild("Utility"))
local DataService = require(dataFolder:WaitForChild("DataService"))
local DuelService = require(servicesFolder:WaitForChild("DuelService"))
local ProgressionService = require(servicesFolder:WaitForChild("ProgressionService"))
local RewardService = require(servicesFolder:WaitForChild("RewardService"))
local SocialService = require(servicesFolder:WaitForChild("SocialService"))
local Moderation = require(systemsFolder:WaitForChild("Moderation"))
local Operations = require(systemsFolder:WaitForChild("Operations"))
local NetworkContract = require(sharedFolder:WaitForChild("network"):WaitForChild("NetworkContract"))

local WELCOME_BADGE_ID = 819292117677808
local actionRateState = {}
local remoteRateState = {}
local loadedPlayers = {}
local closing = false
local getOrCreate = Utility.GetOrCreate
local legacy = NetworkContract.Legacy

local function safeStart(name, callback)
	local ok, err = pcall(callback)
	if not ok then
		warn(string.format("[ServerBootstrap] %s failed to initialize: %s", name, tostring(err)))
	end
	return ok
end

local function consumeRemoteRate(player, actionName, interval, payload)
	if not player or player.Parent ~= Players then
		return false
	end
	if payload ~= nil and not NetworkContract.IsBoundedValue(payload) then
		return false
	end

	local now = os.clock()
	local userRates = remoteRateState[player.UserId]
	if not userRates then
		userRates = {}
		remoteRateState[player.UserId] = userRates
	end
	local lastAt = tonumber(userRates[actionName]) or -math.huge
	if now - lastAt < interval then
		return false
	end
	userRates[actionName] = now
	return true
end

local function awardWelcomeBadge(player)
	if not (player and player.Parent) then
		return
	end

	task.spawn(function()
		local hasBadge = false
		local checked, result = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, WELCOME_BADGE_ID)
		if checked then
			hasBadge = result == true
		end
		if not hasBadge then
			pcall(BadgeService.AwardBadge, BadgeService, player.UserId, WELCOME_BADGE_ID)
		end
	end)
end

local remotesFolder = getOrCreate(ReplicatedStorage, "Folder", NetworkContract.FolderName)
local getBootstrapRemote = getOrCreate(remotesFolder, "RemoteFunction", NetworkContract.GetBootstrap)
local trackActionRemote = getOrCreate(remotesFolder, "RemoteEvent", NetworkContract.TrackAction)
local stateUpdatedRemote = getOrCreate(remotesFolder, "RemoteEvent", NetworkContract.StateUpdated)
local useHintRemote = getOrCreate(remotesFolder, "RemoteFunction", NetworkContract.UseHint)

local retiredTimedProductRemote = remotesFolder:FindFirstChild("UseTimedProduct")
if retiredTimedProductRemote then
	retiredTimedProductRemote:Destroy()
end

local sharedRemotesFolder = getOrCreate(ReplicatedStorage, "Folder", legacy.Folder)
local sharedEventsFolder = getOrCreate(sharedRemotesFolder, "Folder", legacy.Events)
local sharedFunctionsFolder = getOrCreate(sharedRemotesFolder, "Folder", legacy.Functions)

for _, retiredName in ipairs({ "GetQuestState", "ClaimQuest" }) do
	local staleRemote = sharedFunctionsFolder:FindFirstChild(retiredName)
	if staleRemote then
		staleRemote:Destroy()
	end
end

local purchaseHintsRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", legacy.PurchaseHints)
local getDailyRewardStateRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", legacy.GetDailyRewardState)
local claimDailyRewardRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", legacy.ClaimDailyReward)
local checkHintsRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", legacy.CheckHints)
local claimTimedRewardRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", legacy.ClaimTimedReward)
local adminActionRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", legacy.AdminAction)

local purchaseSuccessEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.PurchaseSuccess)
local claimGiftEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.ClaimGift)
local playerJoinedGroupEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.PlayerJoinedGroup)
local groupHintAwardedEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.GroupHintAwarded)
local updateSettingEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.UpdateSetting)
local rejoinRemote = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.Rejoin)
local adminMessageEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.AdminMessage)
local adminBoardResetEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", legacy.AdminBoardReset)

getBootstrapRemote.OnServerInvoke = function(player)
	if not consumeRemoteRate(player, "bootstrap", 0.25) then
		return nil
	end
	return DataService.GetSnapshot(player)
end

trackActionRemote.OnServerEvent:Connect(function(player, actionName, payload)
	if not NetworkContract.ValidateTrackAction(actionName, payload)
		or not NetworkContract.ConsumeRateLimit(actionRateState, player.UserId, actionName, os.clock()) then
		return
	end

	local snapshot = ProgressionService.RecordAction(player, actionName, payload)
	if snapshot then
		stateUpdatedRemote:FireClient(player, snapshot)
	end
end)

useHintRemote.OnServerInvoke = function(player, payload)
	if type(payload) ~= "table" or not consumeRemoteRate(player, "use_hint", 0.1, payload) then
		return { success = false, accepted = false, message = "Invalid hint request." }
	end
	if payload.boardState ~= nil and not NetworkContract.ValidateBoardState(payload.boardState) then
		return { success = false, accepted = false, message = "Invalid board state." }
	end
	if payload.word ~= nil and (type(payload.word) ~= "string" or #payload.word > NetworkContract.Limits.MaximumWordLength) then
		return { success = false, accepted = false, message = "Invalid hint word." }
	end
	return ProgressionService.UseHint(player, payload)
end

purchaseHintsRemote.OnServerInvoke = function(player, amount)
	if not consumeRemoteRate(player, "purchase_hints", 0.25) then
		return { success = false, message = "Please wait." }
	end
	return RewardService.PurchaseHintsWithStars(player, amount)
end

getDailyRewardStateRemote.OnServerInvoke = function(player)
	if not consumeRemoteRate(player, "daily_state", 0.25) then
		return { success = false, message = "Please wait." }
	end
	return RewardService.GetDailyRewardState(player)
end

claimDailyRewardRemote.OnServerInvoke = function(player)
	if not consumeRemoteRate(player, "daily_claim", 0.5) then
		return { success = false, message = "Please wait." }
	end
	return RewardService.ClaimDailyReward(player)
end

checkHintsRemote.OnServerInvoke = function(player)
	if not consumeRemoteRate(player, "check_hints", 0.2) then
		return 0
	end
	return RewardService.GetAvailableHints(player)
end

claimTimedRewardRemote.OnServerInvoke = function(player)
	if not consumeRemoteRate(player, "timed_reward_claim", 0.5) then
		return { success = false, message = "Please wait." }
	end
	return RewardService.ClaimNextReward(player)
end

adminActionRemote.OnServerInvoke = function(player, payload)
	if type(payload) ~= "table" or not consumeRemoteRate(player, "admin_action", 0.2, payload) then
		return { success = false, allowed = false, message = "Invalid request." }
	end
	return Moderation.HandleMenuRequest(player, payload)
end

claimGiftEvent.OnServerEvent:Connect(function(player)
	if not consumeRemoteRate(player, "gift_claim", 0.5) then
		return
	end
	local result = RewardService.ClaimGiftReward(player)
	if not result then
		return
	end
	if result.snapshot then
		stateUpdatedRemote:FireClient(player, result.snapshot)
	end
	claimGiftEvent:FireClient(player, result)
end)

updateSettingEvent.OnServerEvent:Connect(function(player, settingName, value)
	if type(settingName) ~= "string" or #settingName > 32
		or type(value) ~= "boolean"
		or not consumeRemoteRate(player, "update_setting", 0.1) then
		return
	end
	if RewardService.UpdateSetting(player, settingName, value) then
		stateUpdatedRemote:FireClient(player, DataService.GetSnapshot(player))
	end
end)

playerJoinedGroupEvent.OnServerEvent:Connect(function(player)
	if not consumeRemoteRate(player, "group_claim", 1) then
		return
	end
	local result = RewardService.ClaimGroupReward(player)
	if not result then
		return
	end
	if result.snapshot then
		stateUpdatedRemote:FireClient(player, result.snapshot)
	end
	groupHintAwardedEvent:FireClient(player, {
		success = result.success == true,
		rewardHints = result.rewardHints or 0,
		rewardXp = result.rewardXp or 0,
		alreadyClaimed = result.alreadyClaimed == true,
		message = result.message,
	})
end)

local function onPlayerAdded(player)
	if closing or loadedPlayers[player.UserId] then
		return
	end
	loadedPlayers[player.UserId] = true
	Analytics.InitPlayer(player)
	ProgressionService.ClearPlayer(player)
	DataService.LoadPlayer(player)
	RewardService.OnPlayerLoaded(player)
	awardWelcomeBadge(player)
	task.defer(function()
		if player.Parent then
			local snapshot = DataService.GetSnapshot(player)
			SocialService.MarkSnapshotDirty(player, snapshot)
			stateUpdatedRemote:FireClient(player, snapshot)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	loadedPlayers[player.UserId] = nil
	actionRateState[player.UserId] = nil
	remoteRateState[player.UserId] = nil
	Analytics.PlayerLeft(player)
	SocialService.FlushPlayer(player)
	ProgressionService.ClearPlayer(player)
	DataService.ReleasePlayer(player)
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local result = RewardService.GrantProductPurchase(player, receiptInfo.ProductId, receiptInfo.PurchaseId)
	if not result then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result.snapshot and result.alreadyProcessed ~= true then
		stateUpdatedRemote:FireClient(player, result.snapshot)
	end
	if result.alreadyProcessed ~= true then
		purchaseSuccessEvent:FireClient(player, result.kind, result.amount)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

safeStart("DataService autosave", function()
	DataService.StartAutosave(60)
end)
safeStart("SocialService", SocialService.Initialize)
safeStart("DuelService", function()
	DuelService.Init({
		StateUpdatedRemote = stateUpdatedRemote,
	})
end)
safeStart("RewardService timed rewards", RewardService.StartTracking)
safeStart("Operations", function()
	Operations.InitAutoRejoin(rejoinRemote)
	Operations.InitDayNight()
end)
safeStart("Moderation", function()
	Moderation.Init({
		Players = Players,
		AnalyticsService = Analytics,
		SocialService = SocialService,
		MetaService = RewardService,
		PlayerDataStore = DataService,
		StateUpdatedRemote = stateUpdatedRemote,
		AdminMessageEvent = adminMessageEvent,
		AdminBoardResetEvent = adminBoardResetEvent,
	})
end)

game:BindToClose(function()
	closing = true
	DataService.StopAutosave()
	pcall(SocialService.FlushAll)
	pcall(DataService.SaveAll)
end)
