-- Versioned, whitelisted profile. Migration is the only reader of retired fields.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local config = ReplicatedStorage:WaitForChild("shared"):WaitForChild("config")
local Experience = require(config:WaitForChild("ProgressionConfig")).Experience
local Defaults = require(config:WaitForChild("GameConfig")).Meta.DEFAULTS
local DataSchema = { Version = 19 }
local function object(value) return type(value) == "table" and value or {} end
local function integer(value, minimum)
	local number = tonumber(value) or (minimum or 0)
	if number ~= number or math.abs(number) == math.huge then number = minimum or 0 end
	return math.max(minimum or 0, math.floor(number))
end
DataSchema.ClampInt = integer

function DataSchema.CreateDefault()
	return {
		version = 19,
		progression = { level = 1, xp = 0, solves = 0, wordsFound = 0, duel = { wins = 0, losses = 0 } },
		hints = Defaults.StartingHints,
		dailyReward = { lastClaimDay = -1, streak = 0 },
		dailyPuzzle = { day = -1, completed = false, foundWords = {} },
		-- Still used by the shop, settings, onboarding and once-only account rewards.
		puzzlePieces = 0,
		settings = { SFX = true, Music = true, DuelInvites = true },
		tutorial = { completed = false, skipped = false, completedAt = 0 },
		account = { favouritePrompted = false, groupRewardClaimed = false, giftClaimMilestone = 0, processedReceipts = {} },
		-- Server-only persistence protection; snapshot revisions live in the session.
		persistence = { sessionToken = "", saveRevision = 0, lastSavedAt = 0 },
	}
end

function DataSchema.Normalize(data, currentDay)
	data = object(data)
	local oldVersion = integer(data.version)
	assert(oldVersion <= DataSchema.Version, "Profile schema is newer than this server")
	local clean = DataSchema.CreateDefault()
	local progress, resources, stats = object(data.progression), object(data.resources), object(data.stats)
	local account, tutorial = object(data.account), object(data.tutorial)
	local persistence, daily = object(data.persistence), object(data.dailyReward)
	local level, xp
	if oldVersion < 17 then
		local total = integer(progress.totalXp)
		if oldVersion < 13 then
			level = 1 + math.floor(total / 500)
			xp = math.floor((total % 500) / 500 * (500 + (level - 1) * 100))
		else
			local completed = math.floor((math.sqrt(900 * 900 + 800 * total) - 900) / 200)
			level = completed + 1
			xp = total - (completed * 500 + 100 * completed * (completed - 1) / 2)
		end
		local results = object(stats.modeResults)
		clean.progression.solves = math.max(integer(stats.boardsCleared), integer(object(results.Total).wins))
		clean.progression.duel = { wins = integer(object(results.Duel).wins), losses = integer(object(results.Duel).losses) }
		clean.hints = integer(resources.hintsAvailable)
		if oldVersion < 15 then clean.hints += integer(resources.timeBoostsAvailable) + integer(resources.freezeTimeAvailable) end
		clean.puzzlePieces = integer(resources.puzzlePieces)
		clean.dailyReward.streak = integer(daily.currentStreak)
		clean.account.giftClaimMilestone = integer(progress.giftClaimMilestone)
	else
		level, xp = Experience.Resolve(Experience.TotalForLevel(integer(progress.level, 1)) + integer(progress.xp))
		clean.progression.solves = integer(progress.solves)
		clean.progression.duel = { wins = integer(object(progress.duel).wins), losses = integer(object(progress.duel).losses) }
		clean.hints, clean.puzzlePieces = integer(data.hints), integer(data.puzzlePieces)
		clean.dailyReward.streak = integer(daily.streak)
		clean.account.giftClaimMilestone = integer(account.giftClaimMilestone)
	end
	-- Missing historical word counts start at zero; never estimate from board solves.
	clean.progression.wordsFound = integer(progress.wordsFound)
	clean.progression.level, clean.progression.xp = level, xp
	clean.dailyReward.lastClaimDay = integer(daily.lastClaimDay, -1)
	clean.settings.SFX, clean.settings.Music = object(data.settings).SFX ~= false, object(data.settings).Music ~= false
	clean.settings.DuelInvites = object(data.settings).DuelInvites ~= false
	clean.tutorial = { completed = oldVersion < 14 or tutorial.completed == true,
		skipped = tutorial.skipped == true, completedAt = integer(tutorial.completedAt) }
	clean.account.favouritePrompted = account.favouritePrompted == true
	clean.account.groupRewardClaimed = account.groupRewardClaimed == true
	local receipts = {}
	for id, timestamp in pairs(object(account.processedReceipts)) do
		if type(id) == "string" and id ~= "" then table.insert(receipts, {id = id, at = integer(timestamp)}) end
	end
	table.sort(receipts, function(a, b) return a.at == b.at and a.id < b.id or a.at > b.at end)
	for i = 1, math.min(150, #receipts) do clean.account.processedReceipts[receipts[i].id] = receipts[i].at end
	clean.persistence = { sessionToken = tostring(persistence.sessionToken or ""),
		saveRevision = integer(persistence.saveRevision), lastSavedAt = integer(persistence.lastSavedAt) }
	local puzzle = object(data.dailyPuzzle)
	local day = integer(puzzle.day, -1)
	local today = currentDay or math.floor(os.time() / 86400)
	if day == today then
		clean.dailyPuzzle.day, clean.dailyPuzzle.completed = day, puzzle.completed == true
		local count = 0
		for word, found in pairs(object(puzzle.foundWords)) do
			if count >= 32 then break end
			if found == true and type(word) == "string" and #word <= 32 and word:match("^[A-Z]+$") then
				clean.dailyPuzzle.foundWords[word] = true
				count += 1
			end
		end
	end
	table.clear(data)
	for key, value in pairs(clean) do data[key] = value end
	return data
end
return DataSchema
