local SocialService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Utility = require(sharedFolder:WaitForChild("utility"):WaitForChild("Utility"))
local LegacyRemotes = require(sharedFolder:WaitForChild("network"):WaitForChild("NetworkContract")).Legacy

local DEFAULT_META_CONFIG = {
	LEADERBOARD = {
		WordsFoundStoreName = "WordHuntQueueWordsFound_v1",
		DuelWinsStoreName = "WordHuntQueueDuelWins_v1",
		RefreshInterval = 120,
		WriteInterval = 60,
	},
}

local MetaConfig = Utility.Resolve("GameConfig", {
	Meta = DEFAULT_META_CONFIG,
}).Meta
local refreshInterval = math.max(60, math.floor(tonumber(MetaConfig.LEADERBOARD.RefreshInterval) or 120))
local writeInterval = math.max(30, math.floor(tonumber(MetaConfig.LEADERBOARD.WriteInterval) or 60))

local leaderboardDefinitions = {
	WordsFound = {
		title = "Words Found",
		storeName = MetaConfig.LEADERBOARD.WordsFoundStoreName,
		getValueFromSnapshot = function(snapshot)
			return ((snapshot or {}).progression or {}).wordsFound or 0
		end,
	},
	["1v1Wins"] = {
		title = "1v1 Wins",
		storeName = MetaConfig.LEADERBOARD.DuelWinsStoreName,
		getValueFromSnapshot = function(snapshot)
			return (((snapshot or {}).progression or {}).duel or {}).wins or 0
		end,
	},
}
local liveSnapshots = {}
local identities = {}
local inFlight = {}

local orderedStores = {}
local pendingWrites = {}
local caches = {}
local initialized = false

local legacyUpdateEvent = nil
local legacyRequestEvent = nil

local getOrCreate = Utility.GetOrCreate

local function getEventsFolder()
	local remotesFolder = getOrCreate(ReplicatedStorage, "Folder", "Remotes")
	return getOrCreate(remotesFolder, "Folder", "Events")
end

local function resolvePlayerDisplay(userId)
	local cached = identities[userId]
	if cached and os.time() - cached.at < 600 then return cached.username, cached.thumbnail end
	local username = "Unknown"
	local thumbnail = ""

	pcall(function()
		username = Players:GetNameFromUserIdAsync(userId)
	end)
	pcall(function()
		local image, ready = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ready then thumbnail = image end
	end)

	if username ~= "Unknown" and thumbnail ~= "" then
		identities[userId] = { username = username, thumbnail = thumbnail, at = os.time() }
	end
	return username, thumbnail
end

local function sortAndRankEntries(entries)
	table.sort(entries, function(a, b)
		if (a.Score or 0) ~= (b.Score or 0) then
			return (a.Score or 0) > (b.Score or 0)
		end
		return a.UserId < b.UserId
	end)

	local ranked = {}
	for index = 1, math.min(3, #entries) do
		local entry = entries[index]
		entry.Rank = index
		table.insert(ranked, entry)
	end

	return ranked
end

local function mergeEntries(storedEntries, liveEntries)
	local merged = {}
	local byUserId = {}

	for _, entry in ipairs(storedEntries or {}) do
		if type(entry) == "table" and tonumber(entry.UserId) then
			local userId = tonumber(entry.UserId)
			local normalized = {
				UserId = userId,
				Username = entry.Username or "Unknown",
				Thumbnail = entry.Thumbnail or "",
				Score = math.max(0, math.floor(tonumber(entry.Score) or 0)),
			}
			byUserId[userId] = normalized
			table.insert(merged, normalized)
		end
	end

	for _, entry in ipairs(liveEntries or {}) do
		if type(entry) == "table" and tonumber(entry.UserId) then
			local userId = tonumber(entry.UserId)
			local existing = byUserId[userId]
			if existing then
				existing.Score = math.max(existing.Score or 0, math.max(0, math.floor(tonumber(entry.Score) or 0)))
				if not existing.Username or existing.Username == "Unknown" then
					existing.Username = entry.Username or existing.Username
				end
				if (not existing.Thumbnail or existing.Thumbnail == "") and entry.Thumbnail and entry.Thumbnail ~= "" then
					existing.Thumbnail = entry.Thumbnail
				end
			else
				local normalized = {
					UserId = userId,
					Username = entry.Username or "Unknown",
					Thumbnail = entry.Thumbnail or "",
					Score = math.max(0, math.floor(tonumber(entry.Score) or 0)),
				}
				byUserId[userId] = normalized
				table.insert(merged, normalized)
			end
		end
	end

	return sortAndRankEntries(merged)
end

local function getDefinition(categoryKey)
	return leaderboardDefinitions[categoryKey or "WordsFound"]
end

local function getCacheState(categoryKey)
	categoryKey = categoryKey or "WordsFound"
	local cache = caches[categoryKey]
	if cache then
		return cache
	end

	cache = {
		entries = {},
		updatedAt = 0,
	}
	caches[categoryKey] = cache
	return cache
end

local function getPendingBucket(categoryKey)
	categoryKey = categoryKey or "WordsFound"
	local bucket = pendingWrites[categoryKey]
	if bucket then
		return bucket
	end

	bucket = {}
	pendingWrites[categoryKey] = bucket
	return bucket
end

local function getStore(categoryKey)
	categoryKey = categoryKey or "WordsFound"
	local store = orderedStores[categoryKey]
	if store then
		return store
	end

	local definition = getDefinition(categoryKey)
	if not definition then
		return nil
	end

	store = DataStoreService:GetOrderedDataStore(definition.storeName)
	orderedStores[categoryKey] = store
	return store
end

local function getLiveEntries(categoryKey)
	local definition = getDefinition(categoryKey)
	if not definition then
		return {}
	end

	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local score = math.max(0, math.floor(tonumber(definition.getValueFromSnapshot(liveSnapshots[player.UserId])) or 0))
		if score > 0 and player.UserId > 0 then
			table.insert(entries, {
				UserId = player.UserId,
				Username = player.Name,
				Thumbnail = "",
				Score = score,
			})
		end
	end

	return entries
end

local function broadcastCategory(categoryKey)
	local cache = getCacheState(categoryKey)
	local definition = getDefinition(categoryKey)
	if not definition then
		return
	end

	if legacyUpdateEvent then
		legacyUpdateEvent:FireAllClients(categoryKey, cache.entries, cache.updatedAt, cache.revision or 0)
	end

end

local function refreshCategory(categoryKey)
	local definition = getDefinition(categoryKey)
	if not definition then
		return {}, 0, ""
	end

	local cache = getCacheState(categoryKey)
	if cache.refreshing then return cache.entries, cache.updatedAt, definition.title end
	cache.refreshing = true
	local entries = {}
	local ok, page = pcall(function()
		return getStore(categoryKey):GetSortedAsync(false, 3):GetCurrentPage()
	end)

	if ok and page then
		for _, item in ipairs(page) do
			local userId = tonumber(item.key)
			if userId and userId > 0 and (tonumber(item.value) or 0) > 0 then
				local username, thumbnail = nil, ""
				table.insert(entries, {
					UserId = userId,
					Username = username,
					Thumbnail = thumbnail,
					Score = math.max(0, math.floor(tonumber(item.value) or 0)),
				})
			end
		end
	else
		warn("[SocialService] Failed to refresh leaderboard", categoryKey, tostring(page))
		entries = cache.entries
	end

	cache.entries = mergeEntries(entries, getLiveEntries(categoryKey))
	for _, entry in ipairs(cache.entries) do
		entry.Username, entry.Thumbnail = resolvePlayerDisplay(entry.UserId)
	end
	if ok then cache.updatedAt = os.time() end
	cache.revision = (cache.revision or 0) + 1
	cache.refreshing = false
	broadcastCategory(categoryKey)
	return cache.entries, cache.updatedAt, definition.title
end

function SocialService.Refresh()
	SocialService.FlushAll()
	for categoryKey in pairs(leaderboardDefinitions) do refreshCategory(categoryKey) end
end

function SocialService.RefreshCategory(categoryKey)
	return refreshCategory(categoryKey)
end

function SocialService.GetCache()
	return SocialService.GetCategoryCache("WordsFound")
end

function SocialService.GetCategoryCache(categoryKey)
	local definition = getDefinition(categoryKey)
	if not definition then return {}, 0, "" end
	local cache = getCacheState(categoryKey)
	-- Client requests use cached data and never trigger global DataStore reads.
	return mergeEntries(cache.entries, getLiveEntries(categoryKey)), cache.updatedAt, definition.title
end

function SocialService.MarkSnapshotDirty(player, snapshot)
	if not player or player.UserId <= 0 or player:GetAttribute("ProfileReady") ~= true or type(snapshot) ~= "table" then
		return
	end

	liveSnapshots[player.UserId] = snapshot
	for categoryKey, definition in pairs(leaderboardDefinitions) do
		local value = math.max(0, math.floor(tonumber(definition.getValueFromSnapshot(snapshot)) or 0))
		if value > 0 then
			local bucket = getPendingBucket(categoryKey)
			bucket[player.UserId] = math.max(bucket[player.UserId] or 0, value)
		end
	end
end

local function flushEntry(categoryKey, userId)
	local bucket = getPendingBucket(categoryKey)
	local value = bucket[userId]
	local key = categoryKey .. ":" .. tostring(userId)
	if value == nil or inFlight[key] then return end
	inFlight[key] = true
	bucket[userId] = nil
	local ok, err = pcall(function()
		getStore(categoryKey):UpdateAsync(tostring(userId), function(previous)
			return math.max(tonumber(previous) or 0, value)
		end)
	end)
	if not ok then
		bucket[userId] = math.max(bucket[userId] or 0, value)
		warn("[SocialService] Failed to flush leaderboard entry", categoryKey, userId, err)
	end
	inFlight[key] = nil
end

function SocialService.FlushPlayer(player)
	if not player then return end
	for categoryKey in pairs(leaderboardDefinitions) do flushEntry(categoryKey, player.UserId) end
end

function SocialService.FlushAll()
	-- Retry failed writes even after their player has disconnected.
	for categoryKey in pairs(leaderboardDefinitions) do
		local ids = {}
		for userId in pairs(getPendingBucket(categoryKey)) do table.insert(ids, userId) end
		for _, userId in ipairs(ids) do flushEntry(categoryKey, userId) end
	end
end

function SocialService.Initialize()
	if initialized then
		return
	end
	initialized = true

	local eventsFolder = getEventsFolder()
	legacyUpdateEvent = getOrCreate(eventsFolder, "RemoteEvent", LegacyRemotes.LeaderboardUpdate)
	legacyRequestEvent = getOrCreate(eventsFolder, "RemoteEvent", LegacyRemotes.LeaderboardRequest)
	local requestTimes = {}

	legacyRequestEvent.OnServerEvent:Connect(function(player)
		local now = os.clock()
		local lastRequestedAt = tonumber(requestTimes[player.UserId]) or -math.huge
		if now - lastRequestedAt < 1 then
			return
		end
		requestTimes[player.UserId] = now
		for categoryKey in pairs(leaderboardDefinitions) do
			local entries, updatedAt = SocialService.GetCategoryCache(categoryKey)
			local cache = getCacheState(categoryKey)
			cache.revision = (cache.revision or 0) + 1
			legacyUpdateEvent:FireClient(player, categoryKey, entries, updatedAt, cache.revision)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		requestTimes[player.UserId] = nil
		liveSnapshots[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(writeInterval)
			SocialService.FlushAll()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(refreshInterval)
			SocialService.Refresh()
		end
	end)

	for categoryKey in pairs(leaderboardDefinitions) do
		refreshCategory(categoryKey)
	end
end

return SocialService
