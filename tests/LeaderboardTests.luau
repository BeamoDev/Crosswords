local fs, luau = require("@lune/fs"), require("@lune/luau")
local config = require("../src/shared/config/GameConfig")
local contract = require("../src/shared/network/NetworkContract")
local now, checks, reads, writes = 1000, 0, 0, 0
local function check(value, reason) assert(value, reason) checks += 1 end
local function signal()
	return { callbacks = {}, Connect = function(self, callback) table.insert(self.callbacks, callback) end }
end
local function node(children)
	children = children or {}
	function children:WaitForChild(name) return assert(self[name], name) end
	return children
end
local sent, loops, stores = {}, {}, {}
local failRead, failWrite, duringWrite = false, false, nil
local wordsStore, winsStore = config.Meta.LEADERBOARD.WordsFoundStoreName, config.Meta.LEADERBOARD.DuelWinsStoreName
local initial = {
	[wordsStore] = { ["101"]=500, ["102"]=300, ["103"]=200, ["104"]=100 },
	[winsStore] = { ["104"]=50, ["103"]=20, ["102"]=10 },
}
local dataStores = { GetOrderedDataStore = function(_, name)
	check(name ~= "WordHuntQueueLevels_v1", "Retired level index is never opened or overwritten")
	if not stores[name] then
		local store = { values = initial[name] or {} }
		function store:GetSortedAsync(ascending, limit)
			reads += 1
			check(not ascending and limit == 100, "One bounded global read supplies podium and personal ranks")
			if failRead then error("expected leaderboard read failure") end
			local page = {}
			for key, value in pairs(self.values) do table.insert(page, {key=key,value=value}) end
			table.sort(page, function(a,b) return a.value > b.value or (a.value == b.value and tonumber(a.key)<tonumber(b.key)) end)
			while #page > limit do table.remove(page) end
			return { GetCurrentPage = function() return page end }
		end
		function store:UpdateAsync(key, transform)
			writes += 1
			if duringWrite then local fn=duringWrite duringWrite=nil fn() end
			if failWrite then error("expected leaderboard write failure") end
			self.values[key] = transform(self.values[key])
		end
		stores[name] = store
	end
	return stores[name]
end }
local roster = {}
local players = { PlayerRemoving=signal(), GetPlayers=function() return roster end,
	GetNameFromUserIdAsync=function(_, id) return "User" .. id end,
	GetUserThumbnailAsync=function(_, id) return "headshot:" .. id, true end }
local function player(id, ready)
	return { UserId=id,Name="User"..id,GetAttribute=function() return ready ~= false end }
end
local a, b = player(1), player(2)
roster = {a,b}
local function create(parent, _, name)
	if not parent[name] then
		parent[name] = node({ OnServerEvent=signal(),
			FireAllClients=function(_, ...) table.insert(sent, {all=true,args={...}}) end,
			FireClient=function(_, p, ...) table.insert(sent, {player=p,args={...}}) end })
	end
	return parent[name]
end
local storage = node({ shared=node({ utility=node({ Utility={ GetOrCreate=create, Resolve=function() return config end } }),
	network=node({NetworkContract=contract}) }) })
local warnings = 0
local social = luau.load(fs.readFile("src/server/services/SocialService.luau"), { environment={
	game={ GetService=function(_, name) return ({DataStoreService=dataStores,Players=players,ReplicatedStorage=storage})[name] end },
	require=function(value) return value end,
	Enum={ ThumbnailType={HeadShot=1},ThumbnailSize={Size150x150=1} },
	os={time=function() return now end,clock=function() return now end},
	warn=function() warnings += 1 end,
	task={spawn=function(fn) table.insert(loops, coroutine.create(fn)) end,wait=function(delay) return coroutine.yield(delay) end},
} })()
local function snapshot(words,wins) return { progression={level=999,wordsFound=words,duel={wins=wins}} } end
social.MarkSnapshotDirty(a,snapshot(700,5))
social.MarkSnapshotDirty(b,snapshot(300,60))
social.MarkSnapshotDirty(player(-10),snapshot(99999,99999))
social.MarkSnapshotDirty(player(3,false),snapshot(99999,99999))
social.Initialize()
check(#sent == 4, "Initialization sends both categories with personal ranks to each player")
local entries = social.GetCategoryCache("WordsFound")
check(#entries == 6 and entries[1].UserId == 1 and entries[1].Score == 700 and entries[2].UserId == 101 and entries[3].UserId == 2, "Words ranks combine trusted live stats with global top three and deterministic ties")
local wins = social.GetCategoryCache("1v1Wins")
check(wins[1].UserId == 2 and wins[1].Score == 60 and wins[2].UserId == 104, "Duel wins do not rank by level or words found")
check(entries[1].Thumbnail == "headshot:1" and entries[1].Username == "User1", "Ranked identities use the actual Roblox account")
check(#social.GetCategoryCache("Solves") == 0, "Unknown retired category returns no data")
check(social.GetPersonalEntry(a,"WordsFound").Rank == 1 and social.GetPersonalEntry(a,"1v1Wins").Rank == 5, "Personal ranks are global and category-specific beyond the podium")
local cachedReads = reads
for _=1,20 do social.GetPersonalEntry(a,"WordsFound") end
check(reads == cachedReads, "Personal rank lookups perform no DataStore reads")
local request = storage.Remotes.Events[contract.Legacy.LeaderboardRequest].OnServerEvent.callbacks[1]
local readsBefore, sentBefore = reads, #sent
request(a)
check(reads == readsBefore and #sent == sentBefore + 2, "Opening sends both caches without new global reads")
check(sent[#sent].args[1] == "WordsFound" or sent[#sent].args[1] == "1v1Wins", "Remote packets identify their category")
check(type(sent[#sent].args[4]) == "number", "Remote packets include independent ordering revisions")
request(a)
check(#sent == sentBefore + 2, "Repeated requests are throttled")
now += 1000
request(a)
check(reads == readsBefore, "Even stale cached requests cannot spam DataStore refreshes")
social.FlushAll()
check(stores[wordsStore].values["1"] == 700 and stores[winsStore].values["2"] == 60, "Flush writes exact authoritative totals to separate indexes")
check(stores[wordsStore].values["-10"] == nil and stores[wordsStore].values["3"] == nil, "Bots and unloaded profiles are never indexed")
social.MarkSnapshotDirty(a,snapshot(100,1))
social.FlushAll()
check(stores[wordsStore].values["1"] == 700 and stores[winsStore].values["1"] == 5, "An older session cannot lower an existing lifetime total")
social.MarkSnapshotDirty(a,snapshot(800,6))
failWrite = true
duringWrite = function() social.MarkSnapshotDirty(a,snapshot(900,7)) social.FlushPlayer(a) end
social.FlushPlayer(a)
roster = {b}
for _, callback in ipairs(players.PlayerRemoving.callbacks) do callback(a) end
failWrite = false
social.FlushAll()
check(stores[wordsStore].values["1"] == 900 and stores[winsStore].values["1"] == 7, "Failed concurrent writes retain the newer total and retry after disconnect")
social.Refresh()
local prior, priorAt = social.GetCategoryCache("WordsFound")
now += 120
failRead = true
social.RefreshCategory("WordsFound")
local retained, retainedAt = social.GetCategoryCache("WordsFound")
check(retained[1].UserId == prior[1].UserId and retained[1].Score == prior[1].Score and retainedAt == priorAt, "Read failure retains prior global rankings and last successful timestamp")
failRead = false
local delays = {}
for _, thread in ipairs(loops) do local ok,delay=coroutine.resume(thread) assert(ok,delay) delays[delay]=thread end
check(delays[300] ~= nil and delays[60] ~= nil, "Global refresh loop waits five minutes and writes run every minute")
readsBefore = reads
local ok, delay = coroutine.resume(delays[300])
check(ok and delay == 300 and reads == readsBefore + 2, "Each scheduled refresh reloads both global rankings and broadcasts")
check(warnings >= 3, "Failure and retry checks exercised real warning paths")
stores[wordsStore].values = {}
for index=1,120 do stores[wordsStore].values[tostring(1000+index)] = 1000-index end
social.MarkSnapshotDirty(b,snapshot(950,60))
social.RefreshCategory("WordsFound")
check(#social.GetCategoryCache("WordsFound") == 20, "Leaderboard publishes the top twenty entries")
check(social.GetPersonalEntry(b,"WordsFound").Rank == 50, "Top-100 scan resolves an exact personal rank below third place with deterministic ties")
social.MarkSnapshotDirty(b,snapshot(899,60))
check(social.GetPersonalEntry(b,"WordsFound").Rank == nil and social.GetPersonalEntry(b,"WordsFound").RankText == "100+", "Outside cached ranks show a lower bound instead of guessing")
social.MarkSnapshotDirty(b,snapshot(900,60))
check(social.GetPersonalEntry(b,"WordsFound").RankText == "--", "Ties at a truncated page boundary never invent an exact rank")
check(social.GetPersonalEntry(player(99),"WordsFound").RankText == "--", "Missing or zero scores have no fabricated placement")
print("LEADERBOARD_TESTS_PASSED=" .. checks)
