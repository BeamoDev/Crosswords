require("./TestSupport") -- supplies the existing Lune Random shim
local Queue = require("../src/server/services/QueueState")
local Config = require("../src/shared/config/ProgressionConfig")
local n = 0
local function check(value, message) assert(value, message) n += 1 end
local a = { userId = 1, name = "A", displayName = "A" }
local b = { userId = 2, name = "B", displayName = "B" }
local c = { userId = 3, name = "C", displayName = "C" }
local queue = Queue.new(15)
check(queue:Snapshot().count == 0, "New queue must be empty")
check(queue:Add(a, 100), "First join")
check(queue.deadline == 115, "Countdown begins on first join")
check(not queue:Add(a, 104), "Duplicate join")
check(queue:Add(b, 110) and queue.deadline == 115, "Later joins must not reset countdown")
check(queue:Drain(114.99) == nil, "Early start")
check(queue:Remove(a.userId) and queue.deadline == 115, "First player leaving must not reset others' wait")
local cohort = queue:Drain(115)
check(#cohort == 1 and cohort[1].userId == 2, "Drain exact remaining cohort")
check(queue:Snapshot().count == 0 and queue.deadline == nil, "Empty home count after dispatch")
queue:Add(c, 115)
check(queue.deadline == 130, "New cohort gets its own countdown")
queue:Remove(c.userId)
check(queue.deadline == nil and queue:Drain(131) == nil, "Empty queues cancel")
queue:Add(a, 140)
queue:Add(b, 150)
cohort = queue:Drain(155)
local puzzle = {
	words = { "CAT", "DOG" },
	letters = { { "C", "A", "T" }, { "D", "O", "G" } },
	placedWordsByWord = {
		CAT = { answer="CAT", length=3, path = { { row = 1, column = 1 }, { row = 1, column = 2 }, { row = 1, column = 3 } } },
		DOG = { answer="DOG", length=3, path = { { row = 2, column = 1 }, { row = 2, column = 2 }, { row = 2, column = 3 } } },
	},
}
local round = Queue.NewRound("one", puzzle, cohort)
check(round:Snapshot(true).puzzle ~= puzzle and round:Snapshot(true).puzzle.letters[1][1] == " ", "Snapshot hides canonical answers")
check(not round:FindWord(3, "CAT", puzzle.placedWordsByWord.CAT.answer), "Nonmember cannot find words")
check(not round:FindWord(1, "CAT", puzzle.placedWordsByWord.DOG.answer), "Wrong path cannot find word")
check(not round:FindWord(1, "BIRD", {}), "Unknown word")
local accepted, completed = round:FindWord(1, "CAT", puzzle.placedWordsByWord.CAT.answer)
check(accepted and not completed, "Valid first word")
check(round.members[1].score == 300 and round.members[2].score == 0, "Only the finder receives 100 score per canonical letter")
check(not round:FindWord(1, "CAT", puzzle.placedWordsByWord.CAT.answer), "Duplicate word cannot award XP")
check(round.members[2].count == 0, "Solves are independent")
check(round:NextHint(1) == "DOG", "Hint skips solved words")
check(round:MarkHint(1, "DOG"), "First hint accepted")
check(not round:MarkHint(1, "DOG") and round.members[1].hintUses == 1, "Duplicate hint never spends twice")
accepted, completed = round:FindWord(1, "DOG", puzzle.placedWordsByWord.DOG.answer)
check(accepted and completed, "Last word completes once")
check(round.members[1].score == 450, "Hinted answer earns half score and previous duplicate adds nothing")
check(not round:FindWord(1, "DOG", puzzle.placedWordsByWord.DOG.answer), "Cannot award completion twice")
check(round:NextHint(1) == nil, "Completed member cannot spend hint")
local snapshot = round:Snapshot(false)
check(snapshot.members[1].foundWords.CAT and not snapshot.members[2].foundWords.CAT, "Finder roster is individual")
snapshot.members[1].foundWords.CAT = nil
check(round.members[1].foundWords.CAT, "Snapshots cannot mutate authoritative progress")
check(round:Remove(1) and round.members[2].count == 0, "Leaving does not end others' round")
check(not round:FindWord(1, "CAT", puzzle.placedWordsByWord.CAT.answer), "Departed players cannot submit")
accepted = round:FindWord(2, "CAT", "cat")
check(accepted, "Lowercase answers normalize")
local second = Queue.NewRound("two", puzzle, { c })
check(second.members[3].count == 0 and second.members[2] == nil, "Later round is isolated")
local level, xp, needed = Config.Experience.Resolve(0)
check(level == 1 and xp == 0 and needed == 1000, "Fresh XP defaults")
level, xp = Config.Experience.Resolve(999)
check(level == 1 and xp == 999, "XP below level threshold")
level, xp = Config.Experience.Resolve(1000)
check(level == 2 and xp == 0, "XP crossing level threshold")
level, xp, needed = Config.Experience.Resolve(3680)
check(level == 4 and xp == 80 and needed == 1600, "XP supports multiple levels with increasing requirements")
local Bots = require("../src/server/services/QueueBots")
local highRandom = {
	NextInteger = function(_, _, high) return high end,
	NextNumber = function(_, low) return low or 0 end,
}
local function botCount(manager)
	local count = 0
	for _ in pairs(manager.bots) do count += 1 end
	return count
end
for humans = 0, 14 do
	local lobby = Queue.new(15)
	local manager = Bots.new({ Enabled = true, ServerSize = 12 }, highRandom)
	manager:Step(humans, lobby, 0)
	check(botCount(manager) == (humans == 0 and 0 or math.max(0, 12 - humans)), "Global bot capacity respects real player count " .. humans)
	manager:Step(humans, lobby, 2)
	check(lobby:Snapshot().count == math.min(1, botCount(manager)), "A batch of ready bots admits only one member")
	manager:Step(humans, lobby, 2.1)
	check(lobby:Snapshot().count == math.min(1, botCount(manager)), "Shared join delay prevents a near-simultaneous burst")
end
local lobby, manager = Queue.new(15), Bots.new({ Enabled = true, ServerSize = 12 }, highRandom)
manager:Step(10, lobby, 0)
lobby:Add(a, 0)
manager:Step(10, lobby, 15)
check(lobby:Snapshot().count == 1 and lobby.deadline == 15, "Bots due after the queue deadline cannot slip into an expired cohort")
lobby:Drain(15)
manager:Step(10, lobby, 16)
lobby:Add(a, 16)
manager:Step(10, lobby, 19)
local mixed = lobby:Drain(31)
local simulated = Queue.NewRound("bots", puzzle, mixed)
manager:StartRound(simulated, 31)
manager:Step(10, lobby, 37)
check(simulated.revision == 0, "Bots wait through the game entrance")
manager:Step(10, lobby, 38)
check(simulated.revision == 0, "Bots no longer rush a find immediately after entry")
manager:Step(10, lobby, 70)
check(simulated.revision <= 1 and simulated.members[1].count == 0, "A delayed tick permits at most one bot find in the round")
local priorRevision = simulated.revision
manager:Step(10, lobby, 70)
check(simulated.revision == priorRevision, "Repeated ticks cannot burst more bot finds")
for now = 71, 200 do manager:Step(10, lobby, now) end
for _, member in pairs(simulated.members) do
	if member.isBot then check(member.count <= 1 and not member.completed, "Idle human cannot be abandoned by a completed bot") end
end
local _, changedRounds = manager:Step(12, lobby, 201)
check(botCount(manager) == 2 and #simulated.order == 3 and not changedRounds[simulated], "Real arrivals never remove active bots or their portraits")
manager.config.Enabled = false
manager:Step(10, lobby, 205)
check(botCount(manager) == 2 and #simulated.order == 3, "Disabling future bots also preserves current opponents")
manager:Release(simulated:Snapshot(false).members, 205, simulated)
manager:Step(10, lobby, 206)
check(botCount(manager) == 0 and #lobby.order == 0, "Bots retire to the new capacity once the humans finish")
local returning = Bots.new({Enabled = true, ServerSize = 12}, highRandom)
returning:Step(11, lobby, 300)
returning:Step(11, lobby, 302)
local former = Queue.NewRound("former", puzzle, lobby:Drain(317))
returning:StartRound(former, 317)
returning:Release(former:Snapshot(false).members, 318, former)
returning:Step(11, lobby, 324)
local newer = Queue.NewRound("newer", puzzle, lobby:Drain(339))
returning:StartRound(newer, 339)
returning:Release(former:Snapshot(false).members, 340, former)
check(returning.bots[newer.order[1]].round == newer, "Exiting an old completed board cannot release bots from their next round")
local lowRandom = { NextInteger = function(_, low) return low end, NextNumber = function(_, low) return low or 0 end }
local emptyBots = Bots.new({ Enabled = true, ServerSize = 12 }, lowRandom)
emptyBots:Step(1, Queue.new(15), 0)
check(botCount(emptyBots) == 2, "A lone player always has a target of at least two bots")
local pendingAvatar
local avatarLobby = Queue.new(15)
local waitingForAvatar = Bots.new({Enabled = true, ServerSize = 12}, highRandom, function(member) pendingAvatar = member end)
waitingForAvatar:Step(11, avatarLobby, 0)
waitingForAvatar:Step(11, avatarLobby, 30)
check(#avatarLobby.order == 0, "A bot with an unresolved avatar never enters the queue")
pendingAvatar.thumbnailImage, pendingAvatar.avatarReady = "verified-headshot", true
waitingForAvatar:Step(11, avatarLobby, 31)
check(#avatarLobby.order == 1 and avatarLobby:Snapshot().members[1].thumbnailImage == "verified-headshot", "The ready headshot travels with the newly admitted bot")
local ordered = Queue.NewRound("ordered", puzzle, {a, b, c})
ordered:MarkHint(1, "CAT")
ordered:FindWord(3, "CAT", puzzle.placedWordsByWord.CAT.answer)
ordered:FindWord(1, "CAT", puzzle.placedWordsByWord.CAT.answer)
ordered:FindWord(2, "DOG", puzzle.placedWordsByWord.DOG.answer)
ordered:FindWord(3, "DOG", puzzle.placedWordsByWord.DOG.answer)
check(ordered.members[3].foundOrder.CAT < ordered.members[1].foundOrder.CAT, "CAT order reflects accepted solves rather than join order")
check(ordered.members[2].foundOrder.DOG < ordered.members[3].foundOrder.DOG, "DOG has its own solve ordering")
local firstOrder = ordered.members[3].foundOrder.CAT
ordered:FindWord(3, "CAT", puzzle.placedWordsByWord.CAT.answer)
check(ordered.members[3].foundOrder.CAT == firstOrder, "Duplicate find cannot change ordering")
local copiedOrder = ordered:Snapshot(false).members[3].foundOrder
copiedOrder.CAT = 999
check(ordered.members[3].foundOrder.CAT == firstOrder, "Snapshot cannot mutate server order")
local function seeded(seed)
	local state = seed
	local r = {}
	function r:NextNumber(low, high)
		state = state * 48271 % 2147483647
		return (low or 0) + state / 2147483647 * ((high or 1) - (low or 0))
	end
	function r:NextInteger(low, high) return math.min(high, math.floor(self:NextNumber(low, high + 1))) end
	return r
end
-- Test the actual dispatched roster across the complete 2-11 range, not just pool size.
local populationsSeen = {}
for seed = 1, 120 do
	local random = seeded(seed * 11731)
	local fillManager, fillQueue = Bots.new({ Enabled = true, ServerSize = 12, MinBots = 2 }, random), Queue.new(15)
	fillQueue:Add(a, 0)
	local lastCount, lastJoin = 1, -math.huge
	for tick = 0, 149 do
		local time = tick / 10
		fillManager:Step(1, fillQueue, time)
		local count = #fillQueue.order
		check(count - lastCount <= 1, "Large cohorts never batch bot arrivals")
		if count > lastCount then
			check(time - lastJoin >= 0.449, "Large cohorts retain a visible join gap")
			lastJoin = time
		end
		lastCount = count
	end
	local target = fillManager.target
	check(target >= 2 and target <= 11, "Solo-human bot target stays in 2-11 range")
	local cohort = fillQueue:Drain(15)
	check(#cohort == target + 1, "The full randomly selected bot population joins before the 15-second deadline")
	populationsSeen[target] = true
end
for count = 2, 11 do check(populationsSeen[count], "Random dispatched rosters include " .. count .. " bots") end
for humans = 1, 12 do
	local minimum = Bots.new({ Enabled = true, ServerSize = 12, MinBots = 2 }, lowRandom)
	minimum:Step(humans, Queue.new(15), 0)
	check(botCount(minimum) == math.min(2, 12 - humans), "Minimum count respects remaining real-player slots")
end

local longPuzzle = { words = {}, placedWordsByWord = {} }
for i = 1, 10 do
	local word = "WORD" .. tostring(i)
	table.insert(longPuzzle.words, word)
	longPuzzle.placedWordsByWord[word] = {answer="CAT", length=3, path = puzzle.placedWordsByWord.CAT.path}
end
local wins, losses = 0, 0
for seed = 1, 60 do
	local random = seeded(seed * 997)
	local adaptive = Bots.new({Enabled = true, ServerSize = 12}, random)
	local members = {a}
	for i = 1, 6 do
		local member = {userId = -1000000000 - i, isBot = true}
		table.insert(members, member)
		adaptive.bots[member.userId] = {member = member, nextAt = 0}
	end
	local gameRound = Queue.NewRound("adaptive", longPuzzle, members)
	adaptive:StartRound(gameRound, 0)
	local lobby = Queue.new(15)
	local interval = seed % 3 == 0 and 90 or seed % 3 == 1 and 30 or 10
	local botWon = false
	for t = 1, interval * 10 do
		if t % interval == 0 then
			local word = longPuzzle.words[t / interval]
			gameRound:FindWord(1, word, longPuzzle.placedWordsByWord[word].answer)
		end
		local before = gameRound.revision
		adaptive:Step(6, lobby, t)
		check(gameRound.revision - before <= 1, "Bot finds are staggered across the whole cohort")
		for id, bot in pairs(adaptive.bots) do
			local member = gameRound.members[id]
			if member then
				check(member.count <= math.max(1, gameRound.members[1].count + (bot.challenger and 1 or 0)), "No bot runs far ahead of actual progress")
				if member.completed and not gameRound.members[1].completed then botWon = true end
			end
		end
	end
	if botWon then losses += 1 else wins += 1 end
end
print("ADAPTIVE_ROUNDS humanFirst=" .. wins .. " botFirst=" .. losses)
check(wins > 0 and losses > 0, "Seeded rounds include human wins and occasional close bot wins")
-- A player can slow down partway through a round, and peers must not pull their opponents far ahead.
local stalled = Bots.new({Enabled = true, ServerSize = 12}, seeded(72))
local member = {userId = -1000000010, name = "testcompanion", isBot = true}
stalled.bots[member.userId] = {member = member, nextAt = 0}
local stalledRound = Queue.NewRound("stall", longPuzzle, {a, b, member})
stalled:StartRound(stalledRound, 0)
stalled.bots[member.userId].challenger = false -- This case specifically exercises a follower.
local idleLobby = Queue.new(15)
for t = 1, 900 do
	if t <= 90 and t % 30 == 0 then
		local word = longPuzzle.words[t / 30]
		stalledRound:FindWord(1, word, longPuzzle.placedWordsByWord[word].answer)
	end
	if t <= 270 and t % 30 == 0 then
		local word = longPuzzle.words[t / 30]
		stalledRound:FindWord(2, word, longPuzzle.placedWordsByWord[word].answer)
	end
	stalled:Step(2, idleLobby, t)
end
check(stalledRound.botPacing.humans[1].count == 3 and stalledRound.botPacing.humans[2].count == 9, "Adaptive observation tracks both humans separately")
check(not stalledRound.members[member.userId].completed and stalledRound.members[member.userId].count <= 6, "Follower uses the cohort median instead of racing the fastest human during a stall")
local botCountBeforeExit = stalledRound.members[member.userId].count
stalledRound:Remove(2)
for t = 901, 1200 do stalled:Step(1, idleLobby, t) end
check(stalledRound.members[member.userId].count == botCountBeforeExit, "Fast human departure does not keep driving bot progress")
local nameManager = Bots.new({Enabled = true, ServerSize = 12}, seeded(21231))
local seenNames = {}
for time = 1, 400 do
	nameManager:Step(1, Queue.new(15), time * 121)
	local unique = {}
	for _, bot in pairs(nameManager.bots) do
		local name = bot.member.name
		check(not unique[name:lower()] and #name <= 20 and name:match("^[%w_]+$"), "Generated handles fit Roblox-style names and are unique within the pool")
		unique[name:lower()], seenNames[name] = true, true
	end
end
local nameCount, plain = 0, false
for name in pairs(seenNames) do nameCount += 1 if not name:match("%d") then plain = true end end
check(nameCount > 100 and plain, "Names vary naturally and do not always append a serial number")
do
	local avatars = require("../src/server/services/QueueBots")
	check(not avatars.IsUsableAvatar(36149989, "rbxassetid://123", true), "Blocked source account cannot be assigned even through a CDN image")
	check(not avatars.IsUsableAvatar(123, "rbxthumb://type=AvatarHeadShot&id=36149989&w=150&h=150", true), "Known blank returned for another account is rejected")
	check(not avatars.IsUsableAvatar(123, "rbxthumb://type=AvatarHeadShot&w=420&ID=36149989&h=420", true), "Blocked ID checks ignore query order, case and size")
	check(not avatars.IsUsableAvatar(123, "   ", true), "Whitespace image is not usable")
	check(not avatars.IsUsableAvatar(123, "rbxassetid://123", false), "Pending image is not usable")
	check(avatars.IsUsableAvatar(123, "rbxthumb://type=AvatarHeadShot&id=123&w=150&h=150", true), "Other ready avatars remain usable")
end

do
 local timed = Queue.NewRound("timed", puzzle, {a,b})
 timed:SetTimer(100,180)
 for _, word in ipairs(puzzle.words) do timed:FindWord(a.userId,word,puzzle.placedWordsByWord[word].answer) end
 check(#timed:Expire(279.99) == 0, "Round stays live before exact deadline")
 local expired = timed:Expire(280)
 check(#expired == 1 and expired[1] == b.userId and timed.members[a.userId].completed and not timed.members[a.userId].failed, "Shared expiry affects unfinished members only")
 local revision = timed.revision
 check(#timed:Expire(900) == 0 and timed.revision == revision, "Repeated expiry has no further state changes")
end

do
 check(Config.Score.Level(0)==1 and Config.Score.Level(499)==1 and Config.Score.Level(500)==2, "Score levels start at one and advance every 500 points")
 check(Config.Score.Level(2499)==5 and Config.Score.Level(2500)==6 and Config.Score.Level(5000)==11 and Config.Score.Level(7500)==16, "Five-level crown bands have exact score boundaries")
 check(Config.Score.Completion(0,180)==1000 and Config.Score.Completion(90,180)==500 and Config.Score.Completion(180,180)==0, "Completion score scales only with remaining round fraction")
end
print("QUEUE_TESTS_PASSED=" .. n)
