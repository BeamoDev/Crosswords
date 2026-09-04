local LeaderboardService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local utilFolder = script.Parent.Parent.Parent:WaitForChild("utils")
local InstanceUtils = require(utilFolder:WaitForChild("InstanceUtils"))
local SharedConfig = require(utilFolder:WaitForChild("SharedConfig"))

local DEFAULT_META_CONFIG = {
	LEADERBOARD = {
		SolvesStoreName = "WordSearchSolves_v1",
		RefreshInterval = 300,
		WriteInterval = 60,
	},
}

local MetaConfig = SharedConfig.Resolve("MetaConfig", DEFAULT_META_CONFIG)
local refreshInterval = math.max(60, math.floor(tonumber(MetaConfig.LEADERBOARD.RefreshInterval) or 300))
local writeInterval = math.max(30, math.floor(tonumber(MetaConfig.LEADERBOARD.WriteInterval) or 60))

local leaderboardDefinitions = {
	Solves = {
		title = "Wins",
		storeName = MetaConfig.LEADERBOARD.SolvesStoreName,
		legacyUpdateEvent = "LeaderboardUpdateSolves",
		legacyRequestEvent = "RequestLeaderboardUpdateSolves",
		getValueFromSnapshot = function(snapshot)
			return (((snapshot or {}).stats or {}).boardsCleared) or 0
		end,
		getLiveValue = function(player)
			local leaderstats = player:FindFirstChild("leaderstats")
			local winsValue = leaderstats and leaderstats:FindFirstChild("Wins") or nil
			return tonumber(winsValue and winsValue.Value) or 0
		end,
	},
}

local orderedStores = {}
local pendingWrites = {}
local caches = {}
local initialized = false

local legacyUpdateEvent = nil
local legacyRequestEvent = nil

local getOrCreate = InstanceUtils.GetOrCreate

local function getEventsFolder()
	local remotesFolder = getOrCreate(ReplicatedStorage, "Folder", "Remotes")
	return getOrCreate(remotesFolder, "Folder", "Events")
end

local function resolvePlayerDisplay(userId)
	local username = "Unknown"
	local thumbnail = ""

	pcall(function()
		username = Players:GetNameFromUserIdAsync(userId)
	end)
	pcall(function()
		thumbnail = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)

	return username, thumbnail
end

local function sortAndRankEntries(entries)
	table.sort(entries, function(a, b)
		if (a.Score or 0) ~= (b.Score or 0) then
			return (a.Score or 0) > (b.Score or 0)
		end
		return tostring(a.Username or "") < tostring(b.Username or "")
	end)

	local ranked = {}
	for index = 1, math.min(10, #entries) do
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
	return leaderboardDefinitions[categoryKey or "Solves"]
end

local function getCacheState(categoryKey)
	categoryKey = categoryKey or "Solves"
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
	categoryKey = categoryKey or "Solves"
	local bucket = pendingWrites[categoryKey]
	if bucket then
		return bucket
	end

	bucket = {}
	pendingWrites[categoryKey] = bucket
	return bucket
end

local function getStore(categoryKey)
	categoryKey = categoryKey or "Solves"
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
		local score = math.max(0, math.floor(tonumber(definition.getLiveValue(player)) or 0))
		if score > 0 then
			table.insert(entries, {
				UserId = player.UserId,
				Username = player.DisplayName ~= "" and player.DisplayName or player.Name,
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

	if categoryKey == "Solves" and legacyUpdateEvent then
		legacyUpdateEvent:FireAllClients(cache.entries, cache.updatedAt)
	end

end

local function refreshCategory(categoryKey)
	local definition = getDefinition(categoryKey)
	if not definition then
		return {}, 0, ""
	end

	local entries = {}
	local store = getStore(categoryKey)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)

	if ok and pages then
		for _, item in ipairs(pages:GetCurrentPage()) do
			local userId = tonumber(item.key)
			if userId then
				local username, thumbnail = resolvePlayerDisplay(userId)
				table.insert(entries, {
					UserId = userId,
					Username = username,
					Thumbnail = thumbnail,
					Score = math.max(0, math.floor(tonumber(item.value) or 0)),
				})
			end
		end
	else
		warn("[LeaderboardService] Failed to refresh leaderboard", categoryKey, tostring(pages))
	end

	local cache = getCacheState(categoryKey)
	cache.entries = mergeEntries(entries, getLiveEntries(categoryKey))
	cache.updatedAt = os.time()
	broadcastCategory(categoryKey)
	return cache.entries, cache.updatedAt, definition.title
end

local function maybeMergeLiveEntries(categoryKey)
	local cache = getCacheState(categoryKey)
	local liveEntries = getLiveEntries(categoryKey)
	if #cache.entries == 0 then
		cache.entries = mergeEntries(nil, liveEntries)
		broadcastCategory(categoryKey)
	elseif #liveEntries > 0 then
		cache.entries = mergeEntries(cache.entries, liveEntries)
	end
end

function LeaderboardService.Refresh()
	return refreshCategory("Solves")
end

function LeaderboardService.RefreshCategory(categoryKey)
	return refreshCategory(categoryKey)
end

function LeaderboardService.GetCache()
	return LeaderboardService.GetCategoryCache("Solves")
end

function LeaderboardService.GetCategoryCache(categoryKey)
	categoryKey = categoryKey or "Solves"
	local cache = getCacheState(categoryKey)
	local definition = getDefinition(categoryKey)
	if not definition then
		return {}, 0, ""
	end

	if os.time() - (cache.updatedAt or 0) >= refreshInterval then
		return refreshCategory(categoryKey)
	end

	maybeMergeLiveEntries(categoryKey)
	return cache.entries, cache.updatedAt, definition.title
end

function LeaderboardService.MarkDirty(player, solves)
	if not player then
		return
	end

	local value = math.max(0, math.floor(tonumber(solves) or 0))
	if value > 0 then
		getPendingBucket("Solves")[player.UserId] = value
	end
end

function LeaderboardService.MarkSnapshotDirty(player, snapshot)
	if not player or type(snapshot) ~= "table" then
		return
	end

	for categoryKey, definition in pairs(leaderboardDefinitions) do
		local value = math.max(0, math.floor(tonumber(definition.getValueFromSnapshot(snapshot)) or 0))
		if value > 0 then
			getPendingBucket(categoryKey)[player.UserId] = value
		end
	end
end

function LeaderboardService.FlushPlayer(player)
	if not player then
		return
	end

	for categoryKey in pairs(leaderboardDefinitions) do
		local bucket = getPendingBucket(categoryKey)
		local value = bucket[player.UserId]
		if value ~= nil then
			bucket[player.UserId] = nil
			local ok, err = pcall(function()
				getStore(categoryKey):SetAsync(tostring(player.UserId), value)
			end)
			if not ok then
				warn("[LeaderboardService] Failed to flush leaderboard entry", categoryKey, player.Name, err)
				bucket[player.UserId] = value
			end
		end
	end
end

function LeaderboardService.FlushAll()
	for _, player in ipairs(Players:GetPlayers()) do
		LeaderboardService.FlushPlayer(player)
	end
end

function LeaderboardService.Initialize()
	if initialized then
		return
	end
	initialized = true

	local eventsFolder = getEventsFolder()
	legacyUpdateEvent = getOrCreate(eventsFolder, "RemoteEvent", "LeaderboardUpdateSolves")
	legacyRequestEvent = getOrCreate(eventsFolder, "RemoteEvent", "RequestLeaderboardUpdateSolves")

	legacyRequestEvent.OnServerEvent:Connect(function(player)
		local entries, updatedAt = LeaderboardService.GetCategoryCache("Solves")
		legacyUpdateEvent:FireClient(player, entries, updatedAt)
	end)

	task.spawn(function()
		while true do
			task.wait(writeInterval)
			LeaderboardService.FlushAll()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(refreshInterval)
			for categoryKey in pairs(leaderboardDefinitions) do
				refreshCategory(categoryKey)
			end
		end
	end)

	for categoryKey in pairs(leaderboardDefinitions) do
		refreshCategory(categoryKey)
	end
end

return LeaderboardService
