local DataService = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent.Parent
local SessionStore = {}

local sessionData = {}
local snapshotVersions = {}
function SessionStore.GetData(userId) return sessionData[userId] end
function SessionStore.SetData(userId, data) sessionData[userId] = data end
function SessionStore.ClearData(userId)
	sessionData[userId], snapshotVersions[userId] = nil, nil
end
local Utility = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("utility"):WaitForChild("Utility"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local ProgressionConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local GameConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("GameConfig"))
local cloneTable = Utility.CloneDeep
local getOrCreate = Utility.GetOrCreate

local DATA_STORE = DataStoreService:GetDataStore("WordHuntQueueData_v1")
local KEY_PREFIX = "player_"
local SESSION_TOKEN = HttpService:GenerateGUID(false)
local autosaveStarted = false
local loading = {}
local saving = {}
local pendingReleases = {}
local DataSchema = require(script.Parent:WaitForChild("DataSchema"))
local clampInt = DataSchema.ClampInt
local normalizeStoredData = DataSchema.Normalize

local function getKey(userId)
	return KEY_PREFIX .. tostring(userId)
end

local function decodeStoredValue(rawValue)
	if rawValue == nil then return nil end
	if type(rawValue) == "table" then return rawValue end
	assert(type(rawValue) == "string" and rawValue ~= "", "Stored profile is malformed")
	local decoded = HttpService:JSONDecode(rawValue)
	assert(type(decoded) == "table", "Stored profile is not an object")
	return decoded
end

local function prepareStoredData(decoded)
	return normalizeStoredData(type(decoded) == "table" and decoded or DataSchema.CreateDefault())
end

local function encodeStoredValue(data)
	return HttpService:JSONEncode(data)
end

local function setIntValue(parent, name, value, minimum)
	local intValue = getOrCreate(parent, "IntValue", name)
	intValue.Value = math.max(minimum or 0, math.floor(tonumber(value) or 0))
	return intValue
end

local function setBoolValue(parent, name, value)
	local boolValue = getOrCreate(parent, "BoolValue", name)
	boolValue.Value = value == true
	return boolValue
end

local function removeChildrenByName(parent, names)
	if not parent then
		return
	end

	for _, name in ipairs(names) do
		local child = parent:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

local function tutorialState(player, data)
	local state = cloneTable(data.tutorial)
	if player:GetAttribute("TutorialReplayPending") == true then
		-- Session presentation only: preserve the original saved completion history.
		state.completed, state.skipped, state.completedAt = false, false, 0
		state.replaying = true
	end
	return state
end

local function buildSnapshot(data, player)
	local progression = cloneTable(data.progression)
	progression.xpToNextLevel = ProgressionConfig.Experience.RequiredForLevel(progression.level)
	progression.nextLevel = progression.level + 1
	progression.nextLevelRewardHints = ProgressionConfig.Experience.HintsForLevel(progression.nextLevel)
	return {
		meta = { snapshotVersion = snapshotVersions[player.UserId] or 0 },
		progression = progression, hints = data.hints, puzzlePieces = data.puzzlePieces,
		tutorial = tutorialState(player, data), settings = cloneTable(data.settings),
		dailyReward = cloneTable(data.dailyReward), dailyPuzzle = cloneTable(data.dailyPuzzle),
		account = { favouritePrompted = data.account.favouritePrompted,
			groupRewardClaimed = data.account.groupRewardClaimed, giftClaimMilestone = data.account.giftClaimMilestone },
	}
end

local function refreshPlayerDataFolder(player, data)
	local root = getOrCreate(player, "Folder", "Data")
	-- Remove only retired mirrors. The current hierarchy reflects the compact profile.
	removeChildrenByName(root, { "Currency", "Coins", "Powerups", "Stars", "Progress", "Stats", "Activity", "TimedRewards" })
	local oldHints = root:FindFirstChild("Hints")
	if oldHints and not oldHints:IsA("IntValue") then oldHints:Destroy() end
	setIntValue(root, "Hints", data.hints)
	setIntValue(root, "PuzzlePieces", data.puzzlePieces)
	local progression = getOrCreate(root, "Folder", "Progression")
	removeChildrenByName(progression, { "PlayerLevel", "PlayerXp", "XpToNextLevel", "NextLevel", "NextLevelRewardHints", "LastClassicLevel", "HighestClassicLevel" })
	setIntValue(progression, "Level", data.progression.level)
	setIntValue(progression, "Xp", data.progression.xp)
	setIntValue(progression, "Solves", data.progression.solves)
	setIntValue(progression, "WordsFound", data.progression.wordsFound)
	local duel = getOrCreate(progression, "Folder", "Duel")
	setIntValue(duel, "Wins", data.progression.duel.wins)
	setIntValue(duel, "Losses", data.progression.duel.losses)
	local account = getOrCreate(root, "Folder", "Account")
	removeChildrenByName(account, { "NewPlayer", "TutorialCompleted", "TutorialSkipped" })
	setBoolValue(account, "FavouritePrompted", data.account.favouritePrompted)
	setBoolValue(account, "GroupRewardClaimed", data.account.groupRewardClaimed)
	setIntValue(account, "GiftClaimMilestone", data.account.giftClaimMilestone)
	local tutorial = tutorialState(player, data)
	local tutorialFolder = getOrCreate(root, "Folder", "Tutorial")
	setBoolValue(tutorialFolder, "Completed", tutorial.completed)
	setBoolValue(tutorialFolder, "Skipped", tutorial.skipped)
	setIntValue(tutorialFolder, "CompletedAt", tutorial.completedAt)
	player:SetAttribute("TutorialBusy", not tutorial.completed)
	local settings = getOrCreate(root, "Folder", "Settings")
	removeChildrenByName(settings, { "Numbers", "Colorblind" })
	setBoolValue(settings, "SFX", data.settings.SFX)
	setBoolValue(settings, "Music", data.settings.Music)
	setBoolValue(settings, "DuelInvites", data.settings.DuelInvites)
	local daily = getOrCreate(root, "Folder", "DailyReward")
	setIntValue(daily, "Streak", data.dailyReward.streak)
	setIntValue(daily, "LastClaimDay", data.dailyReward.lastClaimDay, -1)
	local puzzle = getOrCreate(root, "Folder", "DailyPuzzle")
	setIntValue(puzzle, "Day", data.dailyPuzzle.day, -1)
	setBoolValue(puzzle, "Completed", data.dailyPuzzle.completed)
	local found = getOrCreate(puzzle, "Folder", "FoundWords")
	for _, child in ipairs(found:GetChildren()) do
		if not data.dailyPuzzle.foundWords[child.Name] then child:Destroy() end
	end
	for word in pairs(data.dailyPuzzle.foundWords) do setBoolValue(found, word, true) end
	local leaderstats = getOrCreate(player, "Folder", "leaderstats")
	for _, child in ipairs(leaderstats:GetChildren()) do if child.Name ~= "Level" then child:Destroy() end end
	setIntValue(leaderstats, "Level", data.progression.level)
end

function DataService.LoadPlayer(player)
	while loading[player.UserId] do task.wait() end
	local existing = SessionStore.GetData(player.UserId)
	if existing then
		-- A same-server rejoin adopts the retained profile and cancels its exit worker.
		if pendingReleases[player.UserId] then
			pendingReleases[player.UserId] = nil
			player:SetAttribute("TutorialReplayPending", GameConfig.Tutorial.ReplayEveryJoin == true
			or player.UserId == GameConfig.Tutorial.ReplayUserId)
			player:SetAttribute("ProfileReady", true)
			refreshPlayerDataFolder(player, existing)
		end
		return existing
	end
	loading[player.UserId] = true
	player:SetAttribute("ProfileReady", false)
	local claimedData = nil
	local success, result = pcall(function()
		return DATA_STORE:UpdateAsync(getKey(player.UserId), function(rawValue)
			local data = prepareStoredData(decodeStoredValue(rawValue))
			data.persistence.sessionToken = SESSION_TOKEN
			claimedData = data
			return encodeStoredValue(data)
		end)
	end)

	loading[player.UserId] = nil
	if not success then
		player:Kick("Your data could not be loaded. Please rejoin.")
		error(string.format("[DataService] Failed to load %s: %s", player.Name, tostring(result)))
	end
	if not player.Parent then error("Player left while loading data") end

	local data = claimedData or prepareStoredData(decodeStoredValue(result))
	player:SetAttribute("TutorialReplayPending", GameConfig.Tutorial.ReplayEveryJoin == true
			or player.UserId == GameConfig.Tutorial.ReplayUserId)
	SessionStore.SetData(player.UserId, data)
	player:SetAttribute("ProfileReady", true)
	refreshPlayerDataFolder(player, data)
	return data
end

-- Call only after the owning round accepts a new canonical word.
function DataService.RecordWordFound(data)
	data.progression.wordsFound += 1
end

function DataService.RecordModeOutcome(data, modeName, didWin)
	if didWin then data.progression.solves += 1 end
	if modeName == "Duel" then
		local key = didWin and "wins" or "losses"
		data.progression.duel[key] += 1
	end
end

function DataService.GetMutableData(player)
	local data = SessionStore.GetData(player.UserId)
	if data then
		return data
	end

	return DataService.LoadPlayer(player)
end

function DataService.AddExperience(player, amount)
	local data = DataService.GetMutableData(player)
	local experience = ProgressionConfig.Experience
	local oldLevel = data.progression.level
	local total = experience.TotalForLevel(oldLevel) + data.progression.xp + clampInt(amount)
	local level, xp = experience.Resolve(total)
	local hints = experience.TotalHintRewards(level) - experience.TotalHintRewards(oldLevel)
	data.progression.level, data.progression.xp = level, xp
	data.hints += hints
	return hints
end

function DataService.IsTutorialPending(player)
	local data = DataService.GetMutableData(player)
	return player:GetAttribute("TutorialReplayPending") == true or not data.tutorial.completed
end

-- Completion is idempotent, including retries after a failed save. No tutorial rewards.
function DataService.CompleteTutorial(player, skipped)
	local data = DataService.GetMutableData(player)
	player:SetAttribute("TutorialReplayPending", false)
	if not data.tutorial.completed then
		data.tutorial.completed = true
		data.tutorial.skipped = skipped == true
		data.tutorial.completedAt = os.time()
	end
	return DataService.SavePlayer(player)
end

-- Persist before dispatch so reconnects cannot repeatedly trigger the platform prompt.
function DataService.MarkFavouritePrompted(player)
	if player:GetAttribute("ProfileReady") ~= true then return false end
	local data = DataService.GetMutableData(player)
	data.account.favouritePrompted = true
	return DataService.SavePlayer(player)
end

function DataService.GetSnapshot(player)
	local data = normalizeStoredData(DataService.GetMutableData(player))
	snapshotVersions[player.UserId] = (snapshotVersions[player.UserId] or 0) + 1
	refreshPlayerDataFolder(player, data)
	return buildSnapshot(data, player)
end

function DataService.SavePlayer(player)
	while saving[player.UserId] do task.wait() end
	local data = SessionStore.GetData(player.UserId)
	if not data then
		return false
	end

	if not pendingReleases[player.UserId] then refreshPlayerDataFolder(player, data) end
	local savePayload = normalizeStoredData(cloneTable(data))
	savePayload.persistence.sessionToken = SESSION_TOKEN

	local savedData = nil
	saving[player.UserId] = true
	local success, result = pcall(function()
		return DATA_STORE:UpdateAsync(getKey(player.UserId), function(rawValue)
			savedData = nil
			local storedData = prepareStoredData(decodeStoredValue(rawValue))
			local storedSessionToken = tostring(storedData.persistence and storedData.persistence.sessionToken or "")
			if storedSessionToken ~= "" and storedSessionToken ~= SESSION_TOKEN then
				return nil
			end

			savePayload.persistence.saveRevision = math.max(
				clampInt(savePayload.persistence.saveRevision),
				clampInt(storedData.persistence and storedData.persistence.saveRevision or 0)
			) + 1
			savePayload.persistence.lastSavedAt = os.time()
			savePayload.persistence.sessionToken = SESSION_TOKEN
			savedData = savePayload
			return encodeStoredValue(savePayload)
		end)
	end)

	saving[player.UserId] = nil
	if not success then
		warn(string.format("[DataService] Failed to save %s: %s", player.Name, tostring(result)))
		return false
	end
	if not savedData or result == nil then
		warn(string.format("[DataService] Skipped stale save for %s because a newer session owns the record.", player.Name))
		return false, "SessionSuperseded"
	end

	data.persistence.saveRevision = savedData.persistence.saveRevision
	data.persistence.lastSavedAt = savedData.persistence.lastSavedAt
	return true
end

local function tryRelease(entry)
	local userId = entry.player.UserId
	if pendingReleases[userId] ~= entry then return true end
	local saved, reason = DataService.SavePlayer(entry.player)
	-- A rejoin may have adopted this profile while UpdateAsync yielded.
	if pendingReleases[userId] ~= entry then return saved end
	if saved or reason == "SessionSuperseded" then
		pendingReleases[userId] = nil
		SessionStore.ClearData(userId)
		return true
	end
	return false
end

function DataService.ReleasePlayer(player)
	local userId = player.UserId
	if not SessionStore.GetData(userId) then return true end
	if pendingReleases[userId] then return false end
	local entry = { player = player, delay = 2 }
	pendingReleases[userId] = entry
	if tryRelease(entry) then return true end
	local function retry()
		if pendingReleases[userId] ~= entry or tryRelease(entry) then return end
		entry.delay = math.min(30, entry.delay * 2)
		task.delay(entry.delay, retry)
	end
	task.delay(entry.delay, retry)
	return false
end

function DataService.SaveAll()
	local allSaved = true
	for _, player in ipairs(Players:GetPlayers()) do
		if not pendingReleases[player.UserId] and not DataService.SavePlayer(player) then
			allSaved = false
		end
	end
	-- Departed players no longer appear in GetPlayers, but still need shutdown/autosave retries.
	for _, entry in pairs(table.clone(pendingReleases)) do
		if not tryRelease(entry) then allSaved = false end
	end
	return allSaved
end

function DataService.StartAutosave(intervalSeconds)
	if autosaveStarted then
		return
	end
	autosaveStarted = true
	local interval = math.max(30, math.floor(tonumber(intervalSeconds) or 60))
	task.spawn(function()
		while autosaveStarted do
			task.wait(interval)
			if autosaveStarted then
				DataService.SaveAll()
			end
		end
	end)
end

function DataService.StopAutosave()
	autosaveStarted = false
end


return DataService
