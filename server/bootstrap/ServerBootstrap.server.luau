local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BadgeService = game:GetService("BadgeService")

local serverFolder = script.Parent.Parent
local servicesFolder = serverFolder:WaitForChild("services")
local gameplayServicesFolder = servicesFolder:WaitForChild("gameplay")
local metaServicesFolder = servicesFolder:WaitForChild("meta")
local opsServicesFolder = servicesFolder:WaitForChild("ops")
local dataFolder = serverFolder:WaitForChild("data")
local utilFolder = serverFolder:WaitForChild("utils")

local AdminCommandService = require(opsServicesFolder:WaitForChild("AdminCommandService"))
local AnalyticsService = require(opsServicesFolder:WaitForChild("AnalyticsService"))
local AntiAfkService = require(opsServicesFolder:WaitForChild("AntiAfkService"))
local DayNightCycleService = require(opsServicesFolder:WaitForChild("DayNightCycleService"))
local LeaderboardService = require(metaServicesFolder:WaitForChild("LeaderboardService"))
local MetaService = require(metaServicesFolder:WaitForChild("MetaService"))
local PlayerDataStore = require(dataFolder:WaitForChild("PlayerDataStore"))
local ProgressionService = require(gameplayServicesFolder:WaitForChild("ProgressionService"))
local InstanceUtils = require(utilFolder:WaitForChild("InstanceUtils"))
local SharedConfig = require(utilFolder:WaitForChild("SharedConfig"))

local DEFAULT_REMOTE_CONFIG = {
	FolderName = "WordSearchBackendRemotes",
	GetBootstrap = "GetBootstrap",
	TrackAction = "TrackAction",
	StateUpdated = "StateUpdated",
	UseHint = "UseHint",
	UseTimedProduct = "UseTimedProduct",
}

local RemoteConfig = SharedConfig.Resolve("RemoteConfig", DEFAULT_REMOTE_CONFIG)
local WELCOME_BADGE_ID = 819292117677808
local VALID_TRACK_ACTIONS = {
	WordFound = true,
	BoardStateUpdated = true,
	BoardStateCleared = true,
	BoardCleared = true,
	BoardLost = true,
	HintUsed = true,
	ClientFunnel = true,
}
local ACTION_THROTTLES = {
	WordFound = 0.05,
	BoardStateUpdated = 0.1,
	BoardStateCleared = 0.05,
	BoardCleared = 0.1,
	BoardLost = 0.1,
	HintUsed = 0.1,
	ClientFunnel = 0.25,
}
local actionRateState = {}

local getOrCreate = InstanceUtils.GetOrCreate

local function awardWelcomeBadge(player)
	if not (player and player.Parent) then
		return
	end

	task.spawn(function()
		local hasBadge = false
		local hasBadgeOk, hasBadgeResult = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, WELCOME_BADGE_ID)
		end)
		if hasBadgeOk then
			hasBadge = hasBadgeResult == true
		end

		if hasBadge then
			return
		end

		pcall(function()
			BadgeService:AwardBadge(player.UserId, WELCOME_BADGE_ID)
		end)
	end)
end

local remotesFolder = getOrCreate(ReplicatedStorage, "Folder", RemoteConfig.FolderName)
local getBootstrapRemote = getOrCreate(remotesFolder, "RemoteFunction", RemoteConfig.GetBootstrap)
local trackActionRemote = getOrCreate(remotesFolder, "RemoteEvent", RemoteConfig.TrackAction)
local stateUpdatedRemote = getOrCreate(remotesFolder, "RemoteEvent", RemoteConfig.StateUpdated)
local useHintRemote = getOrCreate(remotesFolder, "RemoteFunction", RemoteConfig.UseHint)
local useTimedProductRemote = getOrCreate(remotesFolder, "RemoteFunction", RemoteConfig.UseTimedProduct)
local sharedRemotesFolder = getOrCreate(ReplicatedStorage, "Folder", "Remotes")
local sharedEventsFolder = getOrCreate(sharedRemotesFolder, "Folder", "Events")
local sharedFunctionsFolder = getOrCreate(sharedRemotesFolder, "Folder", "Functions")

local staleGetQuestStateRemote = sharedFunctionsFolder:FindFirstChild("GetQuestState")
if staleGetQuestStateRemote then
	staleGetQuestStateRemote:Destroy()
end
local staleClaimQuestRemote = sharedFunctionsFolder:FindFirstChild("ClaimQuest")
if staleClaimQuestRemote then
	staleClaimQuestRemote:Destroy()
end

local purchaseHintsRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", "PurchaseHintsWithCoins")
local getDailyRewardStateRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", "GetDailyRewardState")
local claimDailyRewardRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", "ClaimDailyReward")
local checkHintsRemote = getOrCreate(sharedFunctionsFolder, "RemoteFunction", "CheckHints")
local staleClaimTimedRewardRemote = sharedFunctionsFolder:FindFirstChild("ClaimTimedReward")
if staleClaimTimedRewardRemote then
	staleClaimTimedRewardRemote:Destroy()
end

local purchaseSuccessEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "PurchaseSuccess")
local claimGiftEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "ClaimGift")
local playerJoinedGroupEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "PlayerJoinedGroup")
local groupHintAwardedEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "GroupHintAwarded")
local updateSettingEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "UpdateSetting")
local rejoinRemote = getOrCreate(sharedEventsFolder, "RemoteEvent", "RejoinRemote")
local adminMessageEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "AdminMessage")
local adminBoardResetEvent = getOrCreate(sharedEventsFolder, "RemoteEvent", "AdminBoardReset")

AntiAfkService.Init(rejoinRemote)
DayNightCycleService.Init()
AdminCommandService.Init({
	Players = Players,
	AnalyticsService = AnalyticsService,
	LeaderboardService = LeaderboardService,
	MetaService = MetaService,
	PlayerDataStore = PlayerDataStore,
	StateUpdatedRemote = stateUpdatedRemote,
	AdminMessageEvent = adminMessageEvent,
	AdminBoardResetEvent = adminBoardResetEvent,
})

getBootstrapRemote.OnServerInvoke = function(player)
	return PlayerDataStore.GetSnapshot(player)
end

trackActionRemote.OnServerEvent:Connect(function(player, actionName, payload)
	if type(actionName) ~= "string" or VALID_TRACK_ACTIONS[actionName] ~= true then
		return
	end

	local now = os.clock()
	local playerRates = actionRateState[player.UserId]
	if not playerRates then
		playerRates = {}
		actionRateState[player.UserId] = playerRates
	end
	local throttleSeconds = ACTION_THROTTLES[actionName] or 0
	local lastAt = tonumber(playerRates[actionName]) or 0
	if throttleSeconds > 0 and (now - lastAt) < throttleSeconds then
		return
	end
	playerRates[actionName] = now

	local snapshot = ProgressionService.RecordAction(player, actionName, payload)
	if snapshot then
		stateUpdatedRemote:FireClient(player, snapshot)
	end
end)

useHintRemote.OnServerInvoke = function(player, payload)
	return ProgressionService.UseHint(player, payload)
end

useTimedProductRemote.OnServerInvoke = function(player, payload)
	return ProgressionService.UseTimedProduct(player, payload)
end

purchaseHintsRemote.OnServerInvoke = function(player, amount)
	return MetaService.PurchaseHintsWithStars(player, amount)
end

getDailyRewardStateRemote.OnServerInvoke = function(player)
	return MetaService.GetDailyRewardState(player)
end

claimDailyRewardRemote.OnServerInvoke = function(player)
	return MetaService.ClaimDailyReward(player)
end

checkHintsRemote.OnServerInvoke = function(player)
	return MetaService.GetAvailableHints(player)
end

claimGiftEvent.OnServerEvent:Connect(function(player)
	local result = MetaService.ClaimGiftReward(player)
	if not result then
		return
	end

	if result.snapshot then
		stateUpdatedRemote:FireClient(player, result.snapshot)
	end

	claimGiftEvent:FireClient(player, result)
end)

updateSettingEvent.OnServerEvent:Connect(function(player, settingName, value)
	if MetaService.UpdateSetting(player, settingName, value) then
		stateUpdatedRemote:FireClient(player, PlayerDataStore.GetSnapshot(player))
	end
end)

playerJoinedGroupEvent.OnServerEvent:Connect(function(player)
	local result = MetaService.ClaimGroupReward(player)
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
	AnalyticsService.InitPlayer(player)
	ProgressionService.ClearPlayer(player)
	PlayerDataStore.LoadPlayer(player)
	MetaService.OnPlayerLoaded(player)
	awardWelcomeBadge(player)
	task.defer(function()
		if player.Parent then
			local snapshot = PlayerDataStore.GetSnapshot(player)
			LeaderboardService.MarkSnapshotDirty(player, snapshot)
			stateUpdatedRemote:FireClient(player, snapshot)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	actionRateState[player.UserId] = nil
	AnalyticsService.PlayerLeft(player)
	LeaderboardService.FlushPlayer(player)
	ProgressionService.ClearPlayer(player)
	PlayerDataStore.ReleasePlayer(player)
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local result = MetaService.GrantProductPurchase(player, receiptInfo.ProductId, receiptInfo.PurchaseId)
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

LeaderboardService.Initialize()
