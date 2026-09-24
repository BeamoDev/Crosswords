require("./TestSupport")
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local Config = require("../src/shared/config/ProgressionConfig")
local GameConfig = require("../src/shared/config/GameConfig")
local checks = 0
local function check(ok, why) assert(ok, why) checks += 1 end
local function folder(t)
	function t:WaitForChild(name) return assert(self[name], name) end
	return t
end
local shared = folder({config = folder({GameConfig = GameConfig, ProgressionConfig = Config})})
local storage = folder({shared = shared})
local schema = luau.load(fs.readFile("src/server/data/DataSchema.luau"), {environment = {
	game = {GetService = function() return storage end}, require = function(m) return m end,
}})()
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {} for k,v in pairs(value) do result[k] = copy(v) end return result
end
local defaults = schema.CreateDefault()
check(defaults.version == 19 and defaults.progression.level == 1 and defaults.progression.xp == 0 and defaults.hints == 0, "Clean new-player defaults")
check(not defaults.tutorial.completed and not defaults.account.favouritePrompted, "New accounts retain onboarding and once-only prompt state")
check(defaults.settings.DuelInvites == true, "New profiles default to accepting Duel invites")
check(defaults.progression.wordsFound == 0, "New word counter starts at zero")
local v17 = schema.CreateDefault()
v17.version, v17.progression.wordsFound = 17, nil
v17.progression.level, v17.progression.xp, v17.progression.solves = 9, 80, 120
schema.Normalize(v17)
check(v17.version == 19 and v17.progression.wordsFound == 0 and v17.progression.level == 9 and v17.progression.xp == 80 and v17.progression.solves == 120, "Version 17 migration adds no invented word history and preserves progression")
for _, invalid in ipairs({-9, 0/0, math.huge, "invalid"}) do
	local malformed = schema.CreateDefault()
	malformed.progression.wordsFound = invalid
	check(schema.Normalize(malformed).progression.wordsFound == 0, "Invalid word counts normalize safely")
end
local counted = schema.CreateDefault()
counted.progression.wordsFound = 123.9
check(schema.Normalize(counted).progression.wordsFound == 123, "Existing word counts persist as nonnegative integers")
local v18 = schema.CreateDefault()
v18.version = 18
v18.settings.DuelInvites = nil
v18.settings.Music = false
check(schema.Normalize(v18).settings.DuelInvites and not v18.settings.Music, "Version 18 adds default-On invites without resetting audio settings")

do
 local current = schema.CreateDefault()
 current.progression.level, current.progression.xp, current.hints = 20, 1800, 37
 schema.Normalize(current)
 schema.Normalize(current)
 check(current.progression.level == 20 and current.progression.xp == 1800 and current.hints == 37, "Repeated normalization preserves saved level, XP and hints under the doubled curve")
 check(Config.Experience.RequiredForLevel(20) == 4800 and Config.Experience.HintsForLevel(20) == 1 and Config.Experience.HintsForLevel(21) == 0, "Doubled costs and alternating rewards continue beyond early levels")
end
local legacy = {version = 16, progression = {totalXp = 1840, giftClaimMilestone = 8, levelRewardsThrough = 4},
	resources = {hintsAvailable = 7, puzzlePieces = 61}, stats = {boardsCleared = 20, modeResults = {Total = {wins = 22}, Duel = {wins = 4, losses = 3}}},
	dailyReward = {currentStreak = 9, bestStreak = 20, lastClaimDay = 100}, settings = {SFX = false, Music = true},
	tutorial = {completed = true, skipped = true, completedAt = 123}, account = {favouritePrompted = true, groupRewardClaimed = true, processedReceipts = {abc = 123}},
	persistence = {sessionToken = "old", saveRevision = 6, lastSavedAt = 234, snapshotVersion = 42},
	timedRewards = {playtimeSeconds = 900}, retiredModes = {anything = true}, dailyMode = {}, arbitrary = true}
local migrated = schema.Normalize(copy(legacy))
check(migrated.progression.level == 4 and migrated.progression.xp == 40, "Cumulative XP migrates to level plus in-level XP")
check(migrated.progression.solves == 22 and migrated.progression.duel.wins == 4 and migrated.progression.duel.losses == 3, "Solves and Duel history migrate")
check(migrated.hints == 7 and migrated.puzzlePieces == 61 and migrated.account.giftClaimMilestone == 8, "Working inventory and claimed gifts preserved")
check(migrated.dailyReward.streak == 9 and migrated.dailyReward.lastClaimDay == 100, "Daily claim history preserved")
check(migrated.tutorial.skipped and migrated.account.favouritePrompted and migrated.account.groupRewardClaimed and migrated.account.processedReceipts.abc == 123, "Once-only flags and paid receipts preserved")
for key in pairs(migrated) do check(defaults[key] ~= nil, "Only whitelisted roots are serialized") end
check(migrated.stats == nil and migrated.resources == nil and migrated.timedRewards == nil and migrated.retiredModes == nil and migrated.progression.totalXp == nil and migrated.persistence.snapshotVersion == nil, "Retired and redundant profile data are removed")
local encoded = serde.encode("json", migrated)
schema.Normalize(migrated)
check(serde.encode("json", migrated) == encoded, "Migration and normalization are idempotent")
local old = {version = 12, progression = {totalXp = 1540}, resources = {hintsAvailable = 7, timeBoostsAvailable = 2, freezeTimeAvailable = 1}}
schema.Normalize(old)
check(old.progression.level == 4 and old.progression.xp == 64 and old.hints == 10 and old.tutorial.completed, "Older XP curve, retired paid items and tutorial exemption migrate once")
schema.Normalize(old)
check(old.hints == 10 and old.progression.xp == 64, "Legacy conversion never repeats")
local bad = schema.CreateDefault()
bad.progression.level, bad.progression.xp, bad.hints = 0/0, math.huge, -10
bad.account.favouritePrompted = "true"
schema.Normalize(bad)
check(bad.progression.level == 1 and bad.progression.xp == 0 and bad.hints == 0 and not bad.account.favouritePrompted, "Invalid numbers and booleans are sanitized")
check(not pcall(schema.Normalize, {version = schema.Version + 1}), "Older server must not downgrade a future profile")
local daily = schema.CreateDefault()
daily.dailyPuzzle = {day = 10, completed = true, foundWords = {CAT = true, DOG = true, INVALID = false, ["bad word"] = true}}
schema.Normalize(daily, 10)
check(daily.dailyPuzzle.completed and daily.dailyPuzzle.foundWords.CAT and not daily.dailyPuzzle.foundWords.INVALID and not daily.dailyPuzzle.foundWords["bad word"], "Today's puzzle progress is bounded and retained")
schema.Normalize(daily, 11)
check(daily.dailyPuzzle.day == -1 and not daily.dailyPuzzle.completed and next(daily.dailyPuzzle.foundWords) == nil, "UTC rollover drops only expired puzzle progress")
local experience = Config.Experience
check(experience.LevelCount == 500 and #experience.Levels == 500 and experience.Levels[501] == nil, "500-entry XP dictionary retained")
for level = 1, 501 do
	local total = experience.TotalForLevel(level)
	local reached, xp = experience.Resolve(total)
	check(reached == level and xp == 0, "Level thresholds retain existing curve")
	if level > 1 then
		local previous, remaining = experience.Resolve(total - 1)
		check(previous == level - 1 and remaining == experience.RequiredForLevel(previous) - 1, "Level boundary retains correct fractional XP")
	end
end
local earnedHints = 0
for level = 1, 510 do
	local reward = experience.HintsForLevel(level)
	check(reward == (level % 2 == 0 and 1 or 0), "Level rewards give one hint on even levels, including beyond the dictionary")
	earnedHints += reward
	check(experience.TotalHintRewards(level) == earnedHints, "Cumulative rewards match individual grants across all level boundaries")
end
check(experience.TotalHintRewards(10) == 5 and experience.TotalHintRewards(20) == 10, "New players earn five hints by level ten and ten by level twenty")
-- Exercise the actual DataService against a mock serialized DataStore and Player hierarchy.
local function node(class, name, parent)
	local n = {ClassName = class, Name = name, Parent = parent, children = {}, attributes = {}}
	function n:FindFirstChild(key) return self.children[key] end
	function n:GetChildren() local result = {} for _,v in pairs(self.children) do table.insert(result,v) end return result end
	function n:IsA(kind) return self.ClassName == kind end
	function n:Destroy() if self.Parent and self.Parent.children then self.Parent.children[self.Name] = nil end self.Parent = nil end
	function n:GetAttribute(key) return self.attributes[key] end
	function n:SetAttribute(key,value) self.attributes[key] = value end
	function n:Kick(message) self.kicked = message end
	function n:IsInGroup() return true end
	if parent and parent.children then parent.children[name] = n end
	return n
end
local utility = {CloneDeep = copy, GetOrCreate = function(parent,class,name)
	return parent:FindFirstChild(name) or node(class,name,parent)
end}
shared.utility = folder({Utility = utility})
local records, failStore, writes = {}, false, 0
local store = {}
function store:UpdateAsync(key, transform)
	if failStore then error("simulated unavailable store") end
	local result = transform(records[key])
	if result ~= nil then records[key] = result writes += 1 end
	return result
end
local players = {members = {}}
function players:GetPlayers() return self.members end
local services = {Players = players, ReplicatedStorage = storage,
	DataStoreService = {GetDataStore = function(_,name) check(name == "WordHuntQueueData_v1", "Keep existing store namespace") return store end},
	HttpService = {GenerateGUID = function() return "session-test" end,
		JSONEncode = function(_,v) return serde.encode("json",v) end, JSONDecode = function(_,v) return serde.decode("json",v) end}}
local retryNow, retryTasks = 0, {}
local function advanceRetries(seconds)
 local target = retryNow + seconds
 while true do
  table.sort(retryTasks, function(a,b) return a.at < b.at end)
  if not retryTasks[1] or retryTasks[1].at > target then break end
  local item = table.remove(retryTasks,1)
  retryNow = item.at
  item.fn()
 end
 retryNow = target
end
local dataService = luau.load(fs.readFile("src/server/data/DataService.luau"), {environment = {
	game = {GetService = function(_,name) return assert(services[name],name) end},
	script = {Parent = folder({Parent = {}, DataSchema = schema})}, require = function(m) return m end,
	warn = function() end,
	task = {delay=function(seconds,fn) table.insert(retryTasks,{at=retryNow+seconds,fn=fn}) end, wait=function() error("Unexpected concurrent save") end},
}})()
local actor = node("Player","Test",players) actor.UserId = 1 table.insert(players.members, actor)
records.player_1 = serde.encode("json",legacy)
local data = dataService.LoadPlayer(actor)
check(data.version == 19 and data.progression.level == 4 and data.progression.xp == 40, "Load migrates old record in the same key")
local mirror = actor:FindFirstChild("Data")
check(mirror:FindFirstChild("Hints"):IsA("IntValue") and mirror:FindFirstChild("Hints").Value == 7, "Hints is one replicated integer")
check(#actor:FindFirstChild("leaderstats"):GetChildren() == 1 and actor:FindFirstChild("leaderstats"):FindFirstChild("Level").Value == 4, "Level is the only leaderstat")
local gained = dataService.AddExperience(actor, 3460)
check(data.progression.level == 6 and data.progression.xp == 100 and gained == 1 and data.hints == 8, "XP rolls over multiple levels and grants each reduced hint reward once without reclaiming existing hints")
check(dataService.AddExperience(actor, 0) == 0 and data.hints == 8, "Repeated snapshot/no XP cannot regrant hints")
dataService.RecordModeOutcome(data, "Standard", true)
dataService.RecordModeOutcome(data, "Hardcore", false)
dataService.RecordModeOutcome(data, "Duel", true)
dataService.RecordModeOutcome(data, "Duel", false)
check(data.progression.solves == 24 and data.progression.duel.wins == 5 and data.progression.duel.losses == 4, "Only solves and Duel outcomes are retained")
dataService.RecordWordFound(data)
dataService.RecordWordFound(data)
local snapshot = dataService.GetSnapshot(actor)
check(snapshot.hints == 8 and snapshot.inventory == nil and snapshot.stats == nil and snapshot.progression.xpToNextLevel == 2000, "Snapshot uses compact fields plus derived XP preview")
check(snapshot.persistence == nil and snapshot.account.processedReceipts == nil, "Client snapshot excludes receipt/session internals")
check(snapshot.progression.wordsFound == 2 and mirror:FindFirstChild("Progression"):FindFirstChild("WordsFound").Value == 2, "Word count appears in snapshots and Player.Data.Progression")
snapshot.progression.wordsFound = 999
check(data.progression.wordsFound == 2, "Client snapshots cannot mutate lifetime word count")
snapshot.progression.duel.wins = 999
check(data.progression.duel.wins == 5, "Client snapshots are isolated copies")
check(dataService.SavePlayer(actor), "Save succeeds")
local saved = serde.decode("json",records.player_1)
check(saved.version == 19 and saved.hints == 8 and saved.persistence.snapshotVersion == nil and saved.stats == nil, "Serialized save stays compact")
failStore = true
check(not dataService.SavePlayer(actor), "Save failure stays retryable")
failStore = false
check(dataService.SavePlayer(actor), "Failed save can recover")
check(dataService.CompleteTutorial(actor, true) and not actor:GetAttribute("TutorialReplayPending"), "Tutorial still saves and clears session replay")
check(dataService.MarkFavouritePrompted(actor), "Favourite flag still persists")
dataService.ReleasePlayer(actor)
local reloaded = dataService.LoadPlayer(actor)
check(reloaded.progression.level == 6 and reloaded.progression.xp == 100 and reloaded.hints == 8 and reloaded.account.favouritePrompted, "Rejoin preserves progression/rewards/flags without regranting")
check(saved.progression.wordsFound == 2 and reloaded.progression.wordsFound == 2, "Word count survives serialized save and rejoin")
local newer = serde.decode("json",records.player_1) newer.persistence.sessionToken = "other-server"
records.player_1 = serde.encode("json",newer)
check(not dataService.SavePlayer(actor), "Stale session cannot overwrite a newer server")
local broken = node("Player","Broken",players) broken.UserId = 2
records.player_2 = "not-json"
local before = writes
check(not pcall(dataService.LoadPlayer,broken) and broken.kicked and writes == before, "Corrupt records never become writable defaults")
local future = node("Player","Future",players) future.UserId = 3 records.player_3 = {version = schema.Version + 1}
check(not pcall(dataService.LoadPlayer,future) and future.kicked, "Future records are protected")
-- Real reward paths against the compact profile, including duplicate paid receipts.
services.GroupService = {GetGroupInfoAsync = function() return {} end}
local quiet = setmetatable({}, {__index = function() return function() end end})
local server = folder({data = folder({DataService = dataService}), systems = folder({Analytics = quiet, Operations = quiet})})
local rewards = luau.load(fs.readFile("src/server/services/RewardService.luau"), {environment = {
	game = {GetService = function(_,name) return assert(services[name],name) end}, script = {Parent = {Parent = server}}, require = function(m) return m end,
}})()
-- Restore ownership after the stale-session test, then simulate paid-receipt save retry.
newer.persistence.sessionToken = "session-test"
records.player_1 = serde.encode("json", newer)
local beforeHints = reloaded.hints
local purchase = rewards.GrantProductPurchase(actor, GameConfig.Meta.HINT_PRODUCT_IDS[5], "receipt-new")
check(purchase.success and dataService.GetMutableData(actor).hints == beforeHints + 5, "Supported purchase adds hints")
check(rewards.GrantProductPurchase(actor, GameConfig.Meta.HINT_PRODUCT_IDS[5], "receipt-new").alreadyProcessed and dataService.GetMutableData(actor).hints == beforeHints + 5, "Duplicate receipt never grants twice")
check(rewards.GrantProductPurchase(actor, -1, "unknown") == nil, "Unknown product stays unprocessed")
failStore = true
check(not dataService.SavePlayer(actor), "Paid receipt remains pending when its save fails")
failStore = false
check(dataService.SavePlayer(actor), "Paid receipt retries persist both grant and ID")
dataService.ReleasePlayer(actor)
reloaded = dataService.LoadPlayer(actor)
check(rewards.GrantProductPurchase(actor, GameConfig.Meta.HINT_PRODUCT_IDS[5], "receipt-new").alreadyProcessed and reloaded.hints == beforeHints + 5, "Receipt remains idempotent after actual serialized reload")
for _, pack in ipairs({ {15, 3573028459}, {30, 3711566945} }) do
	local amount, productId = pack[1], pack[2]
	check(GameConfig.Meta.HINT_PRODUCT_IDS[amount] == productId, "Shop product mapping matches the authored pack")
	local hintCount = dataService.GetMutableData(actor).hints
	local receipt = "new-pack-" .. amount
	check(rewards.GrantProductPurchase(actor, productId, receipt).success and dataService.GetMutableData(actor).hints == hintCount + amount, "Receipt grants exactly the displayed pack amount")
	check(dataService.SavePlayer(actor), "New hint pack grant and receipt persist")
	dataService.ReleasePlayer(actor)
	dataService.LoadPlayer(actor)
	check(rewards.GrantProductPurchase(actor, productId, receipt).alreadyProcessed and dataService.GetMutableData(actor).hints == hintCount + amount, "New hint pack receipt stays idempotent after reload")
end
do
 local product=GameConfig.Meta.DIRECT_HINT_PRODUCT
 check(product.Id==3714515983 and product.Amount==1,"Direct Hint product is configured to grant one hint")
 local before=dataService.GetMutableData(actor).hints
 local receipt="direct-hint-receipt"
 local result=rewards.GrantProductPurchase(actor,product.Id,receipt)
 check(result.success and result.amount==1 and dataService.GetMutableData(actor).hints==before+1,"New direct product grants exactly one hint")
 failStore=true
 check(not dataService.SavePlayer(actor),"Unsaved direct hint receipt remains pending")
 check(rewards.GrantProductPurchase(actor,product.Id,receipt).alreadyProcessed and dataService.GetMutableData(actor).hints==before+1,"Retried direct receipt cannot grant twice before save")
 failStore=false
 check(dataService.SavePlayer(actor),"Direct receipt and hint persist together after retry")
 dataService.ReleasePlayer(actor) dataService.LoadPlayer(actor)
 check(rewards.GrantProductPurchase(actor,product.Id,receipt).alreadyProcessed and dataService.GetMutableData(actor).hints==before+1,"Direct hint receipt stays idempotent after reload")
 local legacy=rewards.GrantProductPurchase(actor,3573028208,"delayed-legacy-single-hint")
 check(legacy.success and legacy.amount==1,"Older single-hint receipts still grant their original reward")
end
check(GameConfig.Meta.HINT_PRODUCT_IDS[25] == nil, "The repurposed fifteen-hint product cannot grant twenty-five")
local beforeDaily = dataService.GetMutableData(actor).hints
check(rewards.GetDailyRewardState(actor).nextRewardHints == 1, "Daily preview offers one hint")
local firstDaily = rewards.ClaimDailyReward(actor)
check(firstDaily.success and not rewards.ClaimDailyReward(actor).success, "Daily claim is once per UTC day")
check(firstDaily.rewardHints == 1 and dataService.GetMutableData(actor).hints == beforeDaily + 1, "Daily claim grants exactly one hint without a duplicate grant")
check(dataService.GetMutableData(actor).dailyReward.streak == 1 and firstDaily.state.streak == 1, "Daily streak uses the new field and resets after a missed day")
local current = dataService.GetMutableData(actor)
for _, streak in ipairs({4, 9, 29}) do
	current.dailyReward.lastClaimDay, current.dailyReward.streak = math.floor(os.time() / 86400) - 1, streak
	local beforeClaim = current.hints
	local result = rewards.ClaimDailyReward(actor)
	check(result.success and result.rewardHints == 1 and current.hints == beforeClaim + 1 and current.dailyReward.streak == streak + 1, "Long daily streaks still grant exactly one hint")
end
local pieceCost = GameConfig.Economy.GetHintPackCost(1)
current.puzzlePieces = pieceCost
local purchaseHintsBefore = current.hints
check(rewards.PurchaseHintsWithStars(actor, 1).success and current.hints == purchaseHintsBefore + 1 and current.puzzlePieces == 0, "Piece shop consumes compact currency and grants hints")
check(not rewards.PurchaseHintsWithStars(actor, 1).success, "Insufficient pieces cannot buy hints")
current = dataService.GetMutableData(actor)
current.progression.solves, current.account.giftClaimMilestone = 3, 0
check(rewards.ClaimGiftReward(actor).success and not rewards.ClaimGiftReward(actor).success, "Gift claim marker preserves once-only milestone rewards")
check(rewards.UpdateSetting(actor,"DuelInvites",false) and not dataService.GetSnapshot(actor).settings.DuelInvites, "Invite setting uses the existing saved-setting endpoint")
check(not actor:FindFirstChild("Data"):FindFirstChild("Settings"):FindFirstChild("DuelInvites").Value, "Invite preference mirrors as a BoolValue")
check(rewards.UpdateSetting(actor,"Music",false) and not dataService.GetSnapshot(actor).settings.Music, "Settings still persist in clean profile")
check(not rewards.UpdateSetting(actor,"unused",true), "Settings remain allowlisted")
check(rewards.UpdateSetting(actor, "SFX", false) and dataService.SavePlayer(actor), "Both audio preferences can be saved")
dataService.ReleasePlayer(actor)
local savedSettings = dataService.LoadPlayer(actor).settings
check(savedSettings.DuelInvites == false, "Invites Off survives a serialized rejoin")
check(savedSettings.Music == false and savedSettings.SFX == false, "Off preferences persist through a serialized rejoin")
check(rewards.ClaimGroupReward(actor).alreadyClaimed, "Migrated group claim cannot grant twice")
do
	local newcomer = node("Player", "NewGroupMember", players) newcomer.UserId = 80
	local profile = dataService.LoadPlayer(newcomer)
	local result = rewards.ClaimGroupReward(newcomer)
	check(result.success and result.rewardHints == 1 and profile.hints == 1, "New group claim grants one hint")
	check(rewards.ClaimGroupReward(newcomer).alreadyClaimed and profile.hints == 1, "Group claim remains once-only")
	dataService.ReleasePlayer(newcomer)
end
do
	local milestonePlayer = node("Player", "MilestonePlayer", players) milestonePlayer.UserId = 81
	local profile = dataService.LoadPlayer(milestonePlayer)
	profile.progression.level, profile.progression.xp, profile.hints = 9, 0, 37
	check(dataService.GetSnapshot(milestonePlayer).progression.nextLevelRewardHints == 1, "Snapshot previews one hint at level ten")
	check(dataService.AddExperience(milestonePlayer, experience.TotalForLevel(11) - experience.TotalForLevel(9)) == 1 and profile.hints == 38, "Crossing an even level grants one hint and preserves old inventory")
	check(dataService.AddExperience(milestonePlayer, 0) == 0 and profile.hints == 38, "Milestone reward cannot repeat without advancing")
	check(dataService.GetSnapshot(milestonePlayer).progression.nextLevelRewardHints == 1, "Snapshot returns to one hint after the milestone")
	dataService.ReleasePlayer(milestonePlayer)
	check(dataService.LoadPlayer(milestonePlayer).hints == 38, "Milestone grants survive rejoin without recalculating old inventory")
	dataService.ReleasePlayer(milestonePlayer)
end
check(rewards.StartTracking == nil and rewards.ClaimNextReward == nil, "Timed rewards are fully removed")

-- Failed departures retain progress, retry with backoff and join shutdown saves.
do
 local departed = node("Player","Departed",players) departed.UserId = 70
 local profile = dataService.LoadPlayer(departed)
 profile.hints = 123
 departed.Parent = nil
 failStore = true
 check(not dataService.ReleasePlayer(departed), "Failed exit reports unsaved status")
 check(dataService.GetMutableData(departed) == profile and profile.hints == 123, "Failed exit retains unsaved profile")
 check(not dataService.ReleasePlayer(departed) and #retryTasks == 1, "Duplicate departures cannot create duplicate retry workers")
 advanceRetries(2)
 check(#retryTasks == 1 and retryTasks[1].at == retryNow + 4, "Failed retry backs off")
 failStore = false
 advanceRetries(4)
 check(serde.decode("json", records.player_70).hints == 123 and #retryTasks == 0, "Automatic retry persists departed progress and stops")
 departed.Parent = players
 local loaded = dataService.LoadPlayer(departed)
 check(loaded ~= profile and loaded.hints == 123, "Successful exit retry releases the cached profile")
 loaded.hints = 124
 failStore = true
 dataService.ReleasePlayer(departed)
 failStore = false
 check(dataService.SaveAll() and serde.decode("json",records.player_70).hints == 124, "Shutdown SaveAll includes pending players absent from GetPlayers")
 advanceRetries(40)
 loaded = dataService.LoadPlayer(departed)
 loaded.hints = 125
 failStore = true
 dataService.ReleasePlayer(departed)
 local rejoin = node("Player","Rejoined",players) rejoin.UserId = 70
 check(dataService.LoadPlayer(rejoin) == loaded and rejoin:GetAttribute("ProfileReady"), "Same-server rejoin adopts retained unsaved progress")
 failStore = false
 advanceRetries(40)
 check(dataService.GetMutableData(rejoin) == loaded, "Old retry cannot clear a rejoined profile")
 dataService.ReleasePlayer(rejoin)
 loaded = dataService.LoadPlayer(rejoin)
 loaded.hints = 126
 failStore = true
 dataService.ReleasePlayer(rejoin)
 local ownedElsewhere = serde.decode("json",records.player_70)
 ownedElsewhere.persistence.sessionToken = "new-owner"
 ownedElsewhere.hints = 500
 records.player_70 = serde.encode("json",ownedElsewhere)
 failStore = false
 advanceRetries(40)
 check(serde.decode("json",records.player_70).hints == 500 and #retryTasks == 0, "Exit retries stop without overwriting a newer session")
end

do
 local owner = node("Player","Owner",players) owner.UserId = 1790165114
 local original = schema.CreateDefault()
 original.tutorial.completed = true
 records.player_1790165114 = serde.encode("json",original)
 local ownerData = dataService.LoadPlayer(owner)
 check(owner:GetAttribute("TutorialReplayPending") and dataService.IsTutorialPending(owner) and ownerData.tutorial.completed, "Owner replays without erasing saved completion")
 check(dataService.CompleteTutorial(owner,true) and not dataService.IsTutorialPending(owner), "Owner Skip clears replay for the current join")
 dataService.ReleasePlayer(owner)
 dataService.LoadPlayer(owner)
 check(dataService.IsTutorialPending(owner), "Owner replay returns on the next join")
 dataService.ReleasePlayer(owner)
 check(not actor:GetAttribute("TutorialReplayPending") and not dataService.IsTutorialPending(actor), "Completed non-owner still skips onboarding")
end

-- Smoke-test the actual meta controller against the new snapshot and mirrored hints.
local rbx = require("@lune/roblox")
local Contract = require("../src/shared/network/NetworkContract")
shared.network = folder({NetworkContract = Contract})
shared.ui = folder({UIEffects = {}})
storage.FindFirstChild = function() return nil end -- no authored templates in this mock
players.LocalPlayer = actor
local gui = {setText = function(n,v) if n then n.Text = tostring(v) end end}
local controllerParent = folder({InterfaceController = {Components = {Gui = gui}}})
local clientServices = {Players = players, ReplicatedStorage = storage}
local controller = luau.load(fs.readFile("src/client/controllers/ProgressionController.luau"), {environment = {
	game = {GetService = function(_,name) return clientServices[name] or {} end},
	script = {Parent = controllerParent}, require = function(m) return m end,
	UDim2 = rbx.UDim2, Color3 = rbx.Color3, Enum = rbx.Enum, TweenInfo = {new = function() return {} end},
}})()
local meta = controller.new({})
local hintLabel, dailyLabel = rbx.Instance.new("TextLabel"), rbx.Instance.new("TextLabel")
meta.elements = {hintNotificationAmount = hintLabel, dailyBody = dailyLabel, statsSolves = rbx.Instance.new("TextLabel"), statsHints = rbx.Instance.new("TextLabel")}
meta:updateHintText({hints = 3})
check(hintLabel.Text == "3" and hintLabel.Visible, "Hint UI reads the single hints number")
meta:updateHintText({hints = 0})
check(hintLabel.Text == "" and not hintLabel.Visible, "Zero hints hides the count")
check(meta:getPuzzlePiecesBalance({puzzlePieces = 17}) == 17, "Shop reads compact puzzlePieces")
meta:updateStats({hints = 2, progression = {level = 5, solves = 7, duel = {wins = 2, losses = 1}}})
check(meta.elements.statsSolves.Text == "7" and meta.elements.statsHints.Text == "2", "Retained stats read compact solves/hints")
meta.dailyRewardState = {streak = 4, nextRewardHints = 1, nextRewardXp = 0, secondsUntilReset = 10}
meta:renderDailyRewardState()
check(dailyLabel.Text:find("Daily Streak: 4 days",1,true) and not dailyLabel.Text:find("Best Streak",1,true), "Daily UI uses streak without retired best-streak data")
check(controller.setupTimedRewards == nil and controller.claimTimedReward == nil, "No timed rewards can be started by the client controller")

local generator = require("../src/server/puzzle/PuzzleGenerator")
local validator = require("../src/shared/puzzle/PuzzleValidator")
local bank = require("../src/server/content/CrosswordBank")
check(#bank == 986, "Original crossword vocabulary retained")
for seed = 1, 40 do
	local definition = generator.BuildDefinition(5, "Standard", seed * 7919)
	local puzzle = generator.Generate(definition, seed * 7919)
	check(#puzzle.words > 0 and #puzzle.letters == puzzle.gridSize, "Standard themed puzzle generated")
	for _, word in ipairs(puzzle.words) do
		local placed = puzzle.placedWordsByWord[word]
		check(placed and #placed.path == placed.length, "Generated path has the word length")
		for index, cell in ipairs(placed.path) do
			check(puzzle.letters[cell.row][cell.column] == string.sub(placed.answer, index, index), "Generated letters match the expected word path")
		end
	end
end
print("PROFILE_AND_GENERATION_TESTS_PASSED=" .. checks)
