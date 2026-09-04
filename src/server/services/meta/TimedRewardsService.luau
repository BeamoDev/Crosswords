local TimedRewardsService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local servicesFolder = script.Parent.Parent
local serverFolder = servicesFolder.Parent
local PlayerDataStore = require(serverFolder:WaitForChild("data"):WaitForChild("PlayerDataStore"))
local AnalyticsService = require(servicesFolder:WaitForChild("ops"):WaitForChild("AnalyticsService"))
local TimedRewards = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("config"):WaitForChild("TimedRewards"))

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

function TimedRewardsService.GetState(player)
	local data = PlayerDataStore.GetMutableData(player)
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

function TimedRewardsService.ClaimNextReward(player)
	local data = PlayerDataStore.GetMutableData(player)
	if not data then
		return {
			success = false,
			message = "Timed rewards data missing",
		}
	end

	local state = TimedRewardsService.GetState(player)
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
	local snapshot = PlayerDataStore.GetSnapshot(player)
	AnalyticsService.TrackEconomySource(player, getRewardCurrencyName(reward.rewardType), "timed_reward", reward.amount, {
		rewardIndex = rewardIndex,
	})

	return {
		success = true,
		message = "Reward claimed",
		rewardType = reward.rewardType,
		rewardAmount = reward.amount,
		state = TimedRewardsService.GetState(player),
		snapshot = snapshot,
	}
end

function TimedRewardsService.StartTracking()
	if trackingStarted then
		return
	end

	trackingStarted = true

	task.spawn(function()
		while true do
			task.wait(1)

			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataStore.GetMutableData(player)
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

return TimedRewardsService
