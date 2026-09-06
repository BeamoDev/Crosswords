require("../src/shared/puzzle/PuzzleTests.spec")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local QueueState = require("../src/server/services/QueueState")
local Config = require("../src/shared/config/ProgressionConfig")
local Contract = require("../src/shared/network/NetworkContract")
local checks, now, generated = 0, 100, 0
local function check(value, reason) assert(value, reason) checks += 1 end
local function signal()
	return { Connect = function(self, fn) self.callback = fn end }
end
local players = { PlayerRemoving = signal(), members = {} }
function players:GetPlayerByUserId(id) return self.members[id] end
function players:GetPlayers()
	local result = {}
	for _, member in pairs(self.members) do table.insert(result, member) end
	return result
end
local thumbnailCalls, failThumbnails = 0, false
function players:GetUserThumbnailAsync(id)
	thumbnailCalls += 1
	assert(id > 0, "Bot IDs must not be used for Roblox thumbnail lookup")
	if failThumbnails then
		return "rbxthumb://type=AvatarHeadShot&id=36149989&w=150&h=150", thumbnailCalls % 2 == 0
	end
	return "headshot:" .. id, true
end
local function player(id)
	local value = { UserId = id, Name = "User" .. id, DisplayName = "Player" .. id, attributes = { ProfileReady = true } }
	function value:GetAttribute(name) return self.attributes[name] end
	function value:SetAttribute(name, setting) self.attributes[name] = setting end
	players.members[id] = value
	return value
end
local a, b, c = player(1), player(2), player(3)
local profiles = {}
for _, p in ipairs({ a, b, c }) do
	profiles[p.UserId] = { hints = 2, puzzlePieces = 0, progression = {level = 1, xp = 0, solves = 10, wordsFound = 0} }
end
local data = {}
function data.GetMutableData(p)
	assert(p:GetAttribute("ProfileReady") == true, "Queue broadcasting must never trigger an unloaded profile read")
	return profiles[p.UserId]
end
function data.RecordWordFound(profile) profile.progression.wordsFound += 1 end
function data.AddExperience(p, amount) profiles[p.UserId].progression.xp += amount end
function data.RecordModeOutcome(profile, mode, won)
	profile.lastOutcome = { mode = mode, won = won }
	if won then profile.progression.solves += 1 else profile.testLosses = (profile.testLosses or 0) + 1 end
end
function data.GetSnapshot(p) return profiles[p.UserId] end
local expected = {
	gridSize = 3, words = { "CAT", "DOG" },
	letters = { { "C", "A", "T" }, { "D", "O", "G" } },
	placedWordsByWord = {
		CAT = { path = { { row = 1, column = 1 }, { row = 1, column = 2 }, { row = 1, column = 3 } } },
		DOG = { path = { { row = 2, column = 1 }, { row = 2, column = 2 }, { row = 2, column = 3 } } },
	},
}
local failGeneration = false
local classicCalls = {}
local generator = {
	BeginnerSolves = 10,
	BuildClassicDefinition = function(members, seed, beginnerSolves)
		table.insert(classicCalls, { members = members, beginnerSolves = beginnerSolves })
		return expected
	end,
	BuildDefinition = function() return expected end,
	Generate = function() if failGeneration then error("test generation failure") end generated += 1 return expected end,
}
local botConfig = { Enabled = false, ServerSize = 12 }
local shared = { puzzle = { PuzzleGenerator = generator },
	config = { ProgressionConfig = Config, GameConfig = { Bots = botConfig, Economy = { CalculateCompletionPieces = function() return 16 end } } },
	network = { NetworkContract = Contract } }
local function wait(self, name) return assert(self[name], name) end
shared.WaitForChild = wait
shared.config.WaitForChild = wait
shared.puzzle.WaitForChild = wait
shared.network.WaitForChild = wait
local storage = { WaitForChild = function(_, name) assert(name == "shared") return shared end }
local services = { Players = players, ReplicatedStorage = storage,
	Workspace = { GetServerTimeNow = function() return now end },
	HttpService = { GenerateGUID = function() return "round" .. generated end } }
local parent = { QueueState = QueueState, QueueBots = require("../src/server/services/QueueBots"), SocialService = { MarkSnapshotDirty = function() end }, Parent = { data = { DataService = data } } }
local pendingLoop
local queueService = luau.load(fs.readFile("src/server/services/QueueService.luau"), {
	debugName = "QueueServiceTest",
	environment = {
		game = { GetService = function(_, name) return assert(services[name], name) end },
		script = { Parent = parent }, require = function(module) return module end,
		Random = { new = function() return {
			NextInteger = function(_, _, high) return high end,
			NextNumber = function(_, low) return low or 0 end,
		} end },
		Enum = { ThumbnailType = { HeadShot = "HeadShot" }, ThumbnailSize = { Size150x150 = "150" } },
		os = { clock = function() return now end },
		task = { spawn = function(fn) if pendingLoop then fn() else pendingLoop = fn end end, wait = function() end },
	},
})()
local queues, events, queueMessages = {}, {}, {}
local remotes = {
	action = {},
	queue = { FireClient = function(_, recipient, payload)
		table.insert(queueMessages, { userId = recipient.UserId, payload = payload })
		if recipient == a then table.insert(queues, payload) end
	end },
	round = { FireClient = function(_, recipient, payload) table.insert(events, { userId = recipient.UserId, payload = payload }) end },
	state = { FireClient = function() end },
}
queueService.Init(remotes)
local function request(p, payload)
	now += 0.2
	return remotes.action.OnServerInvoke(p, payload)
end
check(not request(a, { action = "BoardCleared" }).success, "Unknown actions rejected")
a:SetAttribute("ProfileReady", false)
check(not request(a, { action = "Join" }).success, "Unloaded profiles cannot queue")
a:SetAttribute("ProfileReady", true)
a:SetAttribute("TutorialBusy", true)
check(not request(a, { action = "Join" }).success, "Tutorial players cannot enter real queue")
a:SetAttribute("TutorialBusy", false)
local joined = request(a, { action = "Join" })
check(joined.success and joined.queue.count == 1, "First player queued")
check(joined.queue.members[1].level == 1, "Queue cards receive the server-derived level")
local deadline = joined.queue.deadline
check(request(a, { action = "Join" }).queue.count == 1, "Duplicate membership")
check(request(b, { action = "Join" }).queue.deadline == deadline, "Second join shares deadline")
check(generated == 0, "Puzzle not generated before expiry")
now = deadline
local late = request(c, { action = "Join" })
check(generated == 1, "Exactly one generation per cohort")
check(late.queue.count == 1 and late.queue.members[1].userId == 3, "Late join starts another queue")
check(#events == 2 and events[1].payload.puzzle == events[2].payload.puzzle, "Same puzzle sent to cohort only")
check(queues[#queues - 1].count == 0, "Home count reset at dispatch")
local id = events[1].payload.id
check(not request(c, { action = "Word", roundId = id, word = "CAT", path = expected.placedWordsByWord.CAT.path }).success, "Outsider cannot submit to cohort")
check(not request(a, { action = "Word", roundId = "other", word = "CAT", path = expected.placedWordsByWord.CAT.path }).success, "Wrong round rejected")
check(not request(a, { action = "Word", roundId = id, word = "CAT", path = expected.placedWordsByWord.DOG.path,
	foundWords = { "CAT", "DOG" }, stars = 3 }).success, "Client claims cannot bypass path validation")
check(profiles[1].progression.xp == 0 and profiles[1].progression.wordsFound == 0, "Invalid claim awards no XP or word count")
local first = request(a, { action = "Word", roundId = id, word = "CAT", path = expected.placedWordsByWord.CAT.path })
check(first.success and profiles[1].progression.xp == 60 and profiles[1].progression.wordsFound == 1, "Validated word awards agreed XP and one found word")
check(not request(a, { action = "Word", roundId = id, word = "CAT", path = expected.placedWordsByWord.CAT.path }).success, "Duplicate word rejected")
check(profiles[1].progression.xp == 60 and profiles[2].progression.xp == 0, "Awards isolated and idempotent")
local hint = request(a, { action = "Hint", roundId = id, word = "CAT" })
check(hint.success and hint.word == "DOG" and profiles[1].hints == 1, "Server selects and spends hint")
check(not request(a, { action = "Hint", roundId = id }).success and profiles[1].hints == 1, "No repeated hint spending")
check(profiles[1].progression.wordsFound == 1 and profiles[2].progression.wordsFound == 0, "Duplicates and hints cannot increase the word count or credit another player")
check(request(a, { action = "Word", roundId = id, word = "DOG", path = expected.placedWordsByWord.DOG.path }).success, "Completion accepted")
check(profiles[1].progression.xp == 240 and profiles[1].progression.solves == 11, "Completion XP awarded exactly once")
local outcomeSnapshot = request(a, { action = "Sync" }).round
for _, member in ipairs(outcomeSnapshot.members) do
	check(member.xpEarned == (member.userId == a.UserId and 240 or 0), "Outcome snapshot reports only each member's server-awarded round XP")
end
check(not request(a, { action = "Word", roundId = id, word = "DOG", path = expected.placedWordsByWord.DOG.path }).success, "Repeated completion rejected")
check(profiles[1].puzzlePieces == 16, "Completion pieces not duplicated")
check(profiles[1].progression.wordsFound == 2, "Completion and repeated completion add no extra words")
for _, member in ipairs(request(a, { action = "Sync" }).round.members) do
	if member.userId == a.UserId then check(member.xpEarned == 240, "Duplicate completion cannot increase displayed round XP") end
end
check(request(a, { action = "Exit", roundId = id }).success and not queueService.IsBusy(a), "Exit clears membership")
local resumed = request(b, { action = "Sync" })
check(resumed.round and #resumed.round.members == 1, "Other player keeps round after exit")
check(request(a, { action = "Join" }).queue.count == 2, "Departed player can enter next queue")
request(a, { action = "Exit", roundId = id })
check(queueService.IsBusy(a), "Delayed old exit cannot remove new queue membership")
players.PlayerRemoving.callback(a)
check(not queueService.IsBusy(a), "Disconnect removes queued player")
request(c, { action = "LeaveQueue" })
check(queues[#queues].count == 0, "Last departure clears waiting count")
players.PlayerRemoving.callback(b)
check(not queueService.IsBusy(b), "Disconnect removes active player")
c:SetAttribute("DuelBusy", true)
check(not request(c, { action = "Join" }).success, "Cannot join queue during duel")
c:SetAttribute("DuelBusy", false)
local invalid = { { row = 1, column = 1 }, { row = 2, column = 1 } }
local generatedBefore = generated
check(not request(c, { action = "StartSolo", mode = "Mini" }).success and generated == generatedBefore, "Solo unlock enforced server-side before generation")
profiles[3].progression.level = 20
for _, mode in ipairs({ "Classic", "Themed", "Freeplay", "Backwards", "Fog", "OneLife", "Mega", "Daily", "Duel", "Timed" }) do
	check(not request(c, { action = "StartSolo", mode = mode }).success, "Unsupported solo mode: " .. mode)
	now += 1
end
c:SetAttribute("TutorialBusy", true)
check(not request(c, { action = "StartSolo", mode = "Mini" }).success, "Tutorial cannot start a solo round")
now += 1
c:SetAttribute("TutorialBusy", false)
c:SetAttribute("DuelBusy", true)
check(not request(c, { action = "StartSolo", mode = "Mini" }).success, "Duel cannot overlap solo")
now += 1
c:SetAttribute("DuelBusy", false)
request(c, { action = "Join" })
check(not request(c, { action = "StartSolo", mode = "Mini" }).success, "Queued player must leave before solo")
request(c, { action = "LeaveQueue" })
now += 1
failGeneration = true
check(not request(c, { action = "StartSolo", mode = "Mini" }).success and not queueService.IsBusy(c), "Generation failure leaves player free to retry")
failGeneration = false
now += 1
for _, mode in ipairs({ "Mini", "Jumbo", "Hardcore" }) do
	local queueEvents, roundEvents = #queues, #events
	local started = request(c, { action = "StartSolo", mode = mode })
	check(started.success and started.round.mode == mode and started.round.puzzle == expected, "Solo starts immediately: " .. mode)
	local soloId = started.round.id
	check(#started.round.members == 1 and started.round.members[1].userId == 3, "Solo roster contains only the owner")
	check(#queues == queueEvents and #events == roundEvents and request(c, { action = "Sync" }).queue.count == 0, "Solo start never broadcasts a queue or board to others")
	check(c:GetAttribute("RoundBusy") == true, "Solo marks player busy for Duel and tutorial")
	local prior = generated
	now += 1
	check(request(c, { action = "StartSolo", mode = mode }).round.id == soloId and generated == prior, "Duplicate start keeps active solo board")
	check(request(c, { action = "Join" }).round.id == soloId and #queues == queueEvents, "Cannot join Standard during solo")
	check(not request(a, { action = "Word", roundId = soloId, word = "CAT", path = expected.placedWordsByWord.CAT.path }).success, "Other player cannot solve solo board")
	local startWords = profiles[3].progression.wordsFound
	local startXp, pieces, losses = profiles[3].progression.xp, profiles[3].puzzlePieces, profiles[3].testLosses or 0
	local wrong = request(c, { action = "Word", roundId = soloId, word = "", path = invalid })
	check(not wrong.success and profiles[3].progression.xp == startXp, "Wrong selection awards no XP")
	check(profiles[3].progression.wordsFound == startWords, "Invalid solo/Hardcore selection never counts as a word")
	if mode == "Hardcore" then
		check(wrong.round.members[1].failed and profiles[3].testLosses == losses + 1, "Hardcore loses exactly once")
		request(c, { action = "Word", roundId = soloId, word = "", path = invalid })
		check(profiles[3].testLosses == losses + 1 and profiles[3].puzzlePieces == pieces, "Repeated loss does not repeat outcome or completion reward")
		check(not request(c, { action = "Word", roundId = soloId, word = "CAT", path = expected.placedWordsByWord.CAT.path }).success, "Failed Hardcore cannot continue finding words")
		check(not request(c, { action = "Hint", roundId = soloId }).success, "Failed Hardcore cannot spend hints")
	else
		check(not wrong.round.members[1].failed, "Mini/Jumbo allow mistakes")
		profiles[3].hints = 1
		check(request(c, { action = "Hint", roundId = soloId }).success and profiles[3].hints == 0, "Solo hint consumes one hint")
		request(c, { action = "Word", roundId = soloId, word = "CAT", path = expected.placedWordsByWord.CAT.path })
		local won = request(c, { action = "Word", roundId = soloId, word = "DOG", path = expected.placedWordsByWord.DOG.path })
		check(won.success and won.round.members[1].completed and profiles[3].progression.xp == startXp + 240, "Solo completion awards word XP plus completion XP")
		check(profiles[3].lastOutcome.mode == mode and profiles[3].lastOutcome.won, "Solo outcome belongs to chosen mode")
		check(profiles[3].progression.wordsFound == startWords + 2, "Each accepted solo word counts, including a hinted word solved afterward")
	end
	request(c, { action = "Exit", roundId = soloId })
	check(not queueService.IsBusy(c) and c:GetAttribute("RoundBusy") == false, "Solo exit releases busy state")
	now += 1
end
for _, p in ipairs({a, b, c}) do queueService.Remove(p) end
players.members = {[1] = a, [2] = b, [3] = c}
botConfig.ServerSize = 4 -- One available bot makes lifecycle timing deterministic.
botConfig.Enabled = true
now += 100
request(a, {action = "Sync"})
now += 3
local waitingBots = request(a, {action = "Sync"}).queue
check(waitingBots.count == 1 and thumbnailCalls == 1, "One spare slot admits one bot with a resolved avatar")
for _, member in ipairs(waitingBots.members) do
	check(member.isBot and member.userId < -999999999 and member.thumbnailImage == "headshot:100000000", "Bot identity is separate from its public avatar")
end
local beforeBotOnly = generated
now = waitingBots.deadline
check(request(a, {action = "Sync"}).queue.count == 0 and generated == beforeBotOnly, "Bot-only queue expires without generating a board")
local realQueue = request(a, {action = "Join"})
now += 6
local mixed = request(a, {action = "Sync"}).queue
check(mixed.count == 2 and mixed.deadline == realQueue.queue.deadline, "Returning bots share the real player's deadline")
local beforeEvents = #events
now = mixed.deadline
local botRound = request(a, {action = "Sync"}).round
check(#botRound.members == 2 and #events == beforeEvents + 1, "Mixed cohort publishes a board only to its real player")
local wordsBeforeBots = profiles[1].progression.wordsFound
local xpBefore, piecesBefore = profiles[1].progression.xp, profiles[1].puzzlePieces
now += 28
local advanced = request(a, {action = "Sync"}).round
local solved = 0
for _, member in ipairs(advanced.members) do if member.isBot then solved += member.count end end
check(solved == 1 and advanced.revision > botRound.revision, "Bots find one canonical word each after their initial delay")
check(profiles[1].progression.xp == xpBefore and profiles[1].puzzlePieces == piecesBefore, "Simulated finds grant no real XP or pieces")
check(profiles[1].progression.wordsFound == wordsBeforeBots, "Bot finds never increase a human word counter")
check(not request(b, {action = "Word", roundId = botRound.id, userId = botRound.members[2].userId, word = "CAT", path = expected.placedWordsByWord.CAT.path}).success, "Client cannot submit as a bot")
request(a, {action="Word",roundId=botRound.id,word="CAT",path=expected.placedWordsByWord.CAT.path})
request(a, {action = "Exit", roundId = botRound.id})
check(profiles[1].progression.wordsFound == wordsBeforeBots + 1, "Leaving an unfinished round retains accepted words")
now += 6
check(request(a, {action = "Sync"}).queue.count == 1, "Last real exit releases every bot to requeue")
for id = 4, 12 do player(id) end
check(request(a, {action = "Sync"}).queue.count == 0, "Full real server immediately clears simulated queue members")
players.members = {[1] = a, [2] = b, [3] = c}
failThumbnails = true
local previousCalls = thumbnailCalls
request(a, {action = "Sync"})
now += 3
local fallbackBots = request(a, {action = "Sync"}).queue
check(fallbackBots.count == 1 and thumbnailCalls - previousCalls == 4, "Blocked and unready thumbnails have bounded retries and do not block admission")
check(fallbackBots.members[1].thumbnailImage == "headshot:100000000", "Ready-but-blank avatars never poison the fallback cache; bots reuse an accepted headshot")
-- Bot joins never restart a real deadline, including generation-failure recovery.
request(a, {action = "Join"})
failGeneration = true
now = fallbackBots.deadline
local failedBots = request(a, {action = "Sync"})
check(failedBots.round == nil and not a:GetAttribute("RoundBusy"), "Mixed-cohort generation failure releases the real player")
failGeneration = false
now += 6
check(request(a, {action = "Sync"}).queue.count == 1, "Generation failure releases bots for another queue")
local finalQueue = request(a, {action = "Join"}).queue
request(b, {action = "Join"})
now = finalQueue.deadline
local finalRound = request(a, {action = "Sync"}).round
request(a, {action = "Word", roundId = finalRound.id, word = "CAT", path = expected.placedWordsByWord.CAT.path})
request(a, {action = "Word", roundId = finalRound.id, word = "DOG", path = expected.placedWordsByWord.DOG.path})
now += 6
local whileOtherPlays = request(a, {action = "Sync"})
check(whileOtherPlays.queue.count == 0 and #whileOtherPlays.round.members == 3, "One human finishing never releases bots while another human is playing")
request(b, {action = "Word", roundId = finalRound.id, word = "CAT", path = expected.placedWordsByWord.CAT.path})
request(b, {action = "Word", roundId = finalRound.id, word = "DOG", path = expected.placedWordsByWord.DOG.path})
now += 6
local afterCompletion = request(a, {action = "Sync"})
check(afterCompletion.queue.count == 1 and #afterCompletion.round.members == 3, "Finishing releases bots while preserving the completed board's final portraits")
-- Private onboarding remains available even when every real server slot is full.
botConfig.ServerSize, botConfig.MinBots = 12, 2
for _, p in ipairs({a,b,c}) do queueService.Remove(p) end
for id=4,12 do
	local p=player(id)
	profiles[id]={hints=0,puzzlePieces=0,progression={level=1,xp=0,solves=10,wordsFound=0}}
end
profiles[1].progression.solves, profiles[1].progression.level = 0, 5
profiles[2].progression.solves = 0
profiles[3].progression.solves, profiles[3].progression.level = 80, 30
local privateMessagesStart, privateEventsStart = #queueMessages+1, #events+1
local publicQueue = request(c,{action="Join"}).queue
local firstPrivate = request(a,{action="Join",solves=100,level=500}).queue
local secondPrivate = request(b,{action="Join"}).queue
check(firstPrivate.count==1 and firstPrivate.members[1].userId==1 and secondPrivate.count==1 and secondPrivate.members[1].userId==2, "Beginners never see or join another human's queue")
check(request(c,{action="Sync"}).queue.count==1, "Public waiting count excludes private beginners")
check(request(a,{action="Join"}).queue.deadline==firstPrivate.deadline, "Duplicate beginner Join preserves its private countdown")
check(not request(a,{action="StartSolo",mode="Mini"}).success and queueService.IsBusy(a), "Private queue keeps solo and other admission gates locked")
now += 2.1
local oneBot = request(a,{action="Sync"}).queue
check(oneBot.count==2 and oneBot.members[2].isBot and oneBot.members[2].thumbnailImage, "Verified private companion joins naturally even in a full real server")
local sameTick = request(a,{action="Sync"}).queue
check(sameTick.count==2 and sameTick.deadline==firstPrivate.deadline, "Private companions never arrive in a burst or restart the deadline")
now += 3
local nextBot = request(a,{action="Sync"}).queue
check(nextBot.count==3, "A second private companion arrives after the shared join gap")
local secondRoster = request(b,{action="Sync"}).queue
check(nextBot.members[2].userId ~= secondRoster.members[2].userId, "Private bot IDs do not collide across owners")
while now + 0.2 < math.min(publicQueue.deadline, firstPrivate.deadline, secondPrivate.deadline) do
	request(a, {action="Sync"})
end
local priorCalls=#classicCalls
now=math.max(publicQueue.deadline,firstPrivate.deadline,secondPrivate.deadline)
local firstBoard=request(a,{action="Sync"}).round
local secondBoard=request(b,{action="Sync"}).round
local publicBoard=request(c,{action="Sync"}).round
check(#firstBoard.members == 12 and #secondBoard.members == 12, "Beginner cohorts can each admit eleven bots before their unchanged deadline")
check(#classicCalls==priorCalls+3 and firstBoard.id~=secondBoard.id and firstBoard.id~=publicBoard.id, "Each private owner and public cohort gets one independent canonical round")
local beginnerCalls=0
for index=priorCalls+1,#classicCalls do
	local call=classicCalls[index]
	check(#call.members==1, "Difficulty calculation receives real profiles only")
	if call.beginnerSolves~=nil then
		beginnerCalls+=1
		check(call.beginnerSolves==0, "Client-supplied experience cannot skip onboarding")
	else check(call.members[1].solves==80 and call.members[1].level==30, "Shared difficulty uses authoritative current level and solves") end
end
check(beginnerCalls==2, "Both beginner cohorts request the first difficulty stage")
local function privateRoster(round,owner)
	local humans=0
	for _,member in ipairs(round.members) do
		if not member.isBot then humans+=1 check(member.userId==owner,"Private round never contains another human") end
	end
	check(humans==1 and #round.members>=2,"Private round contains its owner and ready companions")
end
privateRoster(firstBoard,1)
privateRoster(secondBoard,2)
check(not request(b,{action="Word",roundId=firstBoard.id,word="CAT",path=expected.placedWordsByWord.CAT.path}).success,"Another beginner cannot score inside a private round")
check(not request(c,{action="Word",roundId=firstBoard.id,word="CAT",path=expected.placedWordsByWord.CAT.path}).success,"Public player cannot enter a private round through word requests")
check(request(a,{action="LeaveQueue"}).round.id==firstBoard.id and a:GetAttribute("RoundBusy"),"Late LeaveQueue cannot discard an already-started private round")
request(a,{action="Word",roundId=firstBoard.id,word="CAT",path=expected.placedWordsByWord.CAT.path})
now+=180
local slowed=request(a,{action="Sync"})
check(slowed.queue.count==0 and #slowed.round.members==#firstBoard.members,"Active private round neither requeues bots nor removes its portraits")
for _,member in ipairs(slowed.round.members) do if member.isBot then check(not member.completed,"Beginner companions cannot finish ahead even at the last word") end end
local privateWin=request(a,{action="Word",roundId=firstBoard.id,word="DOG",path=expected.placedWordsByWord.DOG.path})
check(type(privateWin.round.members[1].duration) == "number" and privateWin.round.members[1].duration >= 0, "Completion carries server-measured round duration")
check(privateWin.success and profiles[1].progression.solves==1,"Only completing the canonical board advances onboarding")
now+=180
check(#request(a,{action="Sync"}).round.members==#firstBoard.members,"Completed private board retains companion portraits until exit")
request(a,{action="Exit",roundId=firstBoard.id})
check(not queueService.IsBusy(a),"Exiting disposes private queue, round and bot ownership")
request(b,{action="Exit",roundId=secondBoard.id})
check(profiles[2].progression.solves==0,"Leaving unfinished puzzles never skips onboarding stages")
for index=privateMessagesStart,#queueMessages do
	local message=queueMessages[index]
	for _,member in ipairs(message.payload.members) do
		if not member.isBot then
			if message.userId==1 or message.userId==2 then
				check(member.userId==message.userId,"Queue events never reveal another human to a private beginner")
			else check(member.userId~=1 and member.userId~=2,"Public queue events exclude private owners") end
		end
	end
end
for index=privateEventsStart,#events do
	local event=events[index]
	if event.payload.id==firstBoard.id then check(event.userId==1,"Private round events only reach their owner") end
	if event.payload.id==secondBoard.id then check(event.userId==2,"Second private round cannot leak to the first owner") end
end
-- Returning players continue from persisted solves; the tenth completion graduates.
profiles[1].progression.solves=9
local finalPrivate=request(a,{action="Join"}).queue
local publicBefore=request(c,{action="Sync"}).queue.revision
now=finalPrivate.deadline
local tenth=request(a,{action="Sync"}).round
check(classicCalls[#classicCalls].beginnerSolves==9,"Saved solve count selects the tenth beginner board on re-entry")
request(a,{action="Word",roundId=tenth.id,word="CAT",path=expected.placedWordsByWord.CAT.path})
request(a,{action="Word",roundId=tenth.id,word="DOG",path=expected.placedWordsByWord.DOG.path})
check(profiles[1].progression.solves==10,"Tenth completion reaches the public admission threshold")
local privateRevision=request(a,{action="Sync"}).queue.revision
request(a,{action="Exit",roundId=tenth.id})
request(c,{action="Exit",roundId=publicBoard.id})
local graduateQueue=request(a,{action="Join"}).queue
local sharedAgain=request(c,{action="Join"}).queue
check(sharedAgain.count==2 and graduateQueue.revision>privateRevision and graduateQueue.revision>publicBefore,"Graduates join real players with increasing queue revisions")
now=sharedAgain.deadline
local graduateRound=request(a,{action="Sync"}).round
local sharedCall=classicCalls[#classicCalls]
check(sharedCall.beginnerSolves==nil and #sharedCall.members==2 and #graduateRound.members==2,"Public cohort difficulty combines both graduated human profiles")
-- Cancelling, disconnecting and retrying a private queue leave no hidden membership.
local cancelled=request(b,{action="Join"}).queue
request(b,{action="LeaveQueue"})
check(not queueService.IsBusy(b) and request(b,{action="Sync"}).queue.count==0,"Cancelling a private wait clears only its own roster")
local retried=request(b,{action="Join"}).queue
check(retried.deadline>cancelled.deadline and retried.count==1,"Re-entering creates a fresh private countdown")
players.PlayerRemoving.callback(b)
check(not queueService.IsBusy(b),"Disconnect disposes a pending private session")
failGeneration=true
local retryFailure=request(b,{action="Join"}).queue
now=retryFailure.deadline
local failedPrivate=request(b,{action="Sync"})
check(not failedPrivate.round and not queueService.IsBusy(b) and not b:GetAttribute("RoundBusy"),"Private generation failure releases all admission state")
failGeneration=false
request(b,{action="Join"})
check(queueService.IsBusy(b),"Private generation failure remains retryable")

b:SetAttribute("ProfileReady",false)
check(request(players.members[4],{action="Join"}).success,"Queue publication does not load unready spectators' profiles")
b:SetAttribute("ProfileReady",true)
queueService.Remove(a)
queueService.Remove(b)
local waiting = request(a,{action="Join"}).queue
failGeneration = true
check(not request(a,{action="StartSolo",mode="Standard"}).success and queueService.IsBusy(a), "Failed Classic solo generation retains queue membership")
failGeneration = false
now += 1.1
local solo = request(a,{action="StartSolo",mode="Standard"}).round
check(solo and solo.solo and solo.mode == "Standard" and #solo.members == 1 and solo.members[1].userId == a.UserId, "Queue Solo starts a private Classic immediately without bots")
check(solo.puzzle and now < waiting.deadline, "Solo bypasses the remaining queue countdown")
for _, member in ipairs(request(a,{action="Sync"}).queue.members) do check(member.userId ~= a.UserId, "Solo removes player from waiting roster") end
print("QUEUE_SERVICE_TESTS_PASSED=" .. checks)
