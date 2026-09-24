require("./TestSupport")
local fs, luau = require("@lune/fs"), require("@lune/luau")
local RealGenerator = require("../src/server/puzzle/PuzzleGenerator")
local canonical = {}
local Generator = table.clone(RealGenerator)
function Generator.generate(definition,seed)
    local puzzle = RealGenerator.Generate(definition,seed)
    table.insert(canonical,puzzle)
    return puzzle
end
local function answer(public,id)
    for index=#canonical,1,-1 do
        local entry=canonical[index].placedWordsByWord[id]
        if entry and entry.clue==public.placedWordsByWord[id].clue then return entry.answer end
    end
    error("Missing canonical test answer")
end
local Config = require("../src/shared/config/ProgressionConfig")
local Contract = require("../src/shared/network/NetworkContract")
local now, checks, pending, sent = 100, 0, {}, {}
local function check(value, reason) assert(value, reason) checks += 1 end
local function node(children)
	children = children or {}
	function children:WaitForChild(name) return assert(self[name], name) end
	return children
end
local function create(parent, _, name)
	if not parent[name] then parent[name] = node({OnServerEvent={Connect=function() end},FireClient=function(_, p, payload) table.insert(sent,{name=name,player=p,payload=payload}) end}) end
	return parent[name]
end
local players = {}
local function player(id)
	local p = {UserId=id,Name="User"..id,DisplayName="Test"..id,Parent=players,attributes={ProfileReady=true}}
	function p:GetAttribute(name) return self.attributes[name] end
	function p:SetAttribute(name,value) self.attributes[name]=value end
	return p
end
local a,b=player(1),player(2)
function players:GetPlayers() return {a,b} end
function players:GetPlayerByUserId(id) return id == 1 and a or id == 2 and b or nil end
local profiles = {[1]={hints=1,puzzlePieces=0,xp=0,progression={wordsFound=0,duel={wins=3,losses=1}}},[2]={hints=1,puzzlePieces=0,xp=0,progression={wordsFound=0,duel={wins=1,losses=3}}}}
local data = {
	GetMutableData=function(p) return profiles[p.UserId] end,
	GetSnapshot=function(p) return profiles[p.UserId] end,
	AddExperience=function(p,xp) profiles[p.UserId].xp+=xp end,
	RecordWordFound=function(profile) profile.progression.wordsFound+=1 end,
	RecordModeOutcome=function(profile,mode,won)
		profile.mode,profile.won=mode,won
		local key = won and "wins" or "losses"
		profile.progression.duel[key] += 1
	end,
}
local storage = node({shared=node({config=node({ProgressionConfig=Config,GameConfig=require("../src/shared/config/GameConfig")}),
	utility=node({Utility={GetOrCreate=create}}),network=node({NetworkContract=Contract}),puzzle=node({PuzzleGenerator=Generator,PuzzleValidator=require("../src/shared/puzzle/PuzzleValidator")})})})
local server = node({puzzle={PuzzleGenerator=Generator},data=node({DataService=data}),systems=node({Analytics=setmetatable({}, {__index=function() return function() end end})})})
local leaderboardSnapshots = {}
local social = { MarkSnapshotDirty = function(p, snapshot)
	leaderboardSnapshots[p.UserId] = { words = snapshot.progression.wordsFound, won = snapshot.won }
end }
local aggressive, populationChoice = false, "min"
local taskMock = {
	wait = function() end,
	delay = function(seconds, fn) table.insert(pending, { at = now + seconds, fn = fn }) end,
	spawn = function(fn) table.insert(pending, { at = now, fn = fn }) end,
}
local mockRandom = { new = function() return {
	NextInteger = function(_, low, high)
		if low == 2 and (high == 3 or high == 6) then
			if populationChoice == "max" then return high end
			if populationChoice == "mid" then return math.floor((low + high) / 2) end
		end
		return low
	end,
	NextNumber = function(_, low, high)
		if low == 0 and high == 1 then return aggressive and 0.5 or 0.8 end
		return (low + high) / 2
	end,
} end }
local playerCount = 2
function players:GetPlayers()
	local list = {a}
	if playerCount >= 2 then table.insert(list, b) end
	for i = 3, playerCount do table.insert(list, player(i)) end
	return list
end
local avatarAttempts, randomAvatarsUnavailable, connectedAvatarCalls = 0, false, 0
function players:GetUserThumbnailAsync(id)
	if randomAvatarsUnavailable then
		if id >= 10000 then return "", false end
		connectedAvatarCalls += 1
		return "rbxassetid://connected-fallback", true
	end
	avatarAttempts += 1
	if avatarAttempts == 1 then return "rbxthumb://type=AvatarHeadShot&id=36149989&w=150&h=150", true end
	if avatarAttempts == 2 then return "   ", true end
	if avatarAttempts == 3 then return "rbxassetid://pending", false end
	return "rbxassetid://verified-headshot", true
end
local botModule = luau.load(fs.readFile("src/server/services/DuelBots.luau"), {environment={
	game={GetService=function() return players end}, script={Parent={QueueBots=require("../src/server/services/QueueBots")}},
	require=function(value) return value end, Random=mockRandom, task=taskMock,
	Enum={ThumbnailType={HeadShot="HeadShot"},ThumbnailSize={Size150x150="150"}},
	os={clock=function() return now end},
}})()
local duel = luau.load(fs.readFile("src/server/services/DuelService.luau"), {environment={
	game={GetService=function(_, name) return name == "Players" and players or name == "Workspace" and {GetServerTimeNow=function() return now end} or storage end},
	script={Parent=node({Parent=server,SocialService=social,DuelBots=botModule})},require=function(value) return value end,
	os={clock=function() return now end,time=function() return 12345 end},
	task=taskMock,
}})()
local function advance(seconds)
	local target=now+seconds
	while true do
		table.sort(pending,function(left,right) return left.at<right.at end)
		if not pending[1] or pending[1].at>target then break end
		local item=table.remove(pending,1) now=item.at item.fn()
	end
	now=target
end
local function last(name,p,action)
	for i=#sent,1,-1 do local item=sent[i] if item.name==name and item.player==p and (not action or item.payload.action==action) then return item.payload end end
end
duel.Init({})
check(#duel:GetPlayerList(a) == 1, "Bots are hidden until a thumbnail is verified")
profiles[2].settings = {DuelInvites=false}
check(not duel:GetPlayerList(a)[1].duelRequestsEnabled, "Lobby publishes saved invites-Off preference")
check(not duel:SendChallenge(a,2,"Duel"), "Server rejects invitations to an opted-out player")
profiles[2].settings.DuelInvites = true
check(duel:SendChallenge(a,2,"Duel"), "Re-enabling invites allows challenges")
profiles[2].settings.DuelInvites = false
duel:OnInviteSettingChanged(b)
check(last("DuelChallenge",b,"expired") and last("DuelChallenge",a,"declined"), "Turning invites Off cancels the pending request on both clients")
check(not duel:RespondToChallenge(b,true), "Cancelled incoming invitation cannot be accepted")
advance(9)
profiles[2].settings.DuelInvites = true
check(duel:SendChallenge(a,2,"Duel"), "Invite can be sent again after opting in")
profiles[2].settings.DuelInvites = false
check(not duel:RespondToChallenge(b,true) and not b:GetAttribute("DuelBusy"), "Acceptance rechecks the saved preference even without a cancellation callback")
profiles[2].settings.DuelInvites = true
advance(9)
b:SetAttribute("ProfileReady",false)
check(duel:GetPlayerList(a)[1].inMatch, "Duel lobby marks unloaded profiles unavailable")
b:SetAttribute("ProfileReady",true)
b:SetAttribute("DuelBusy",true)
check(duel:GetPlayerList(a)[1].inMatch and not duel:SendChallenge(a,2,"Duel"), "Reserved Duel admission is unavailable in both roster and server invite checks")
b:SetAttribute("DuelBusy",false)
b:SetAttribute("TutorialBusy",true)
check(duel:GetPlayerList(a)[1].inMatch and not duel:SendChallenge(a,2,"Duel"), "Tutorial players cannot receive Duel requests")
b:SetAttribute("TutorialBusy",false)
a:SetAttribute("RoundBusy",true)
check(not duel:SendChallenge(a,2,"Duel"), "Solo player cannot challenge")
a:SetAttribute("RoundBusy",false)
b:SetAttribute("RoundBusy",true)
check(duel:GetPlayerList(a)[1].inMatch, "Solo players appear busy in Duel lobby")
check(not duel:SendChallenge(a,2,"Duel"), "Cannot challenge solo player")
b:SetAttribute("RoundBusy",false)
check(duel:SendChallenge(a,2,"Classic"), "Duel invitation is still available")
b:SetAttribute("RoundBusy",true)
check(not duel:RespondToChallenge(b,true), "Invitation cannot be accepted after entering solo")
b:SetAttribute("RoundBusy",false)
advance(9)
check(duel:SendChallenge(a,2,"Freeplay"), "New invitation after busy rejection")
check(duel:RespondToChallenge(b,true), "Duel starts without retired generator modes")
local left,right=last("DuelMatch",a,"countdown"),last("DuelMatch",b,"countdown")
check(left.mode=="Duel" and right.mode=="Duel" and left.puzzleData.placedWordsByWord[left.puzzleData.words[1]].clue==right.puzzleData.placedWordsByWord[right.puzzleData.words[1]].clue, "Both Duel players share one supported board")
check(left.myDuelStats.wins == 3 and left.myDuelStats.losses == 1 and left.opponentDuelStats.wins == 1 and left.opponentDuelStats.losses == 3, "Duel countdown carries actual saved wins and losses")
check(right.myDuelStats.wins == left.opponentDuelStats.wins and right.opponentDuelStats.wins == left.myDuelStats.wins, "Both HUD recipients get the correct side's record")
check(a:GetAttribute("DuelBusy") and b:GetAttribute("DuelBusy"), "Duel blocks concurrent solo/queue joins")
local puzzle=left.puzzleData
local word=puzzle.words[1]
duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,answer=answer(puzzle,word)})
check(profiles[1].xp==0 and profiles[1].progression.wordsFound==0, "Countdown gates XP and word counting")
advance(6)
check(last("DuelMatch",a,"start")~=nil, "Existing Duel start delay preserved")
profiles[2].settings.DuelInvites = false
duel:OnInviteSettingChanged(b)
check(b:GetAttribute("DuelBusy") and a:GetAttribute("DuelBusy"), "Opting out does not abandon an active Duel")
profiles[2].settings.DuelInvites = true
local beforeStale=profiles[1].xp
duel:ReportProgress(a,{matchId="previous-match",word=word,answer=answer(puzzle,word)})
check(profiles[1].xp==beforeStale,"An old match packet cannot answer the new crossword")
check(puzzle.placedWordsByWord[word].answer==nil and puzzle.seed==nil,"Duel countdown omits canonical solution and seed")
duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,path={}})
check(profiles[1].xp==0 and profiles[1].progression.wordsFound==0, "Forged Duel path cannot count a word")
local hint=duel:UseHint(b)
check(hint.success and profiles[2].hints==0 and profiles[2].progression.wordsFound==0, "Duel hint alone does not count as a find")
check(hint.boardState.revealedAnswers[word]==answer(puzzle,word),"Duel hint reveals the selected answer to its owner")
do
	local originalLetters = puzzle.letters
	puzzle.letters = {{"C","A","T"},{"D","O","G"}}
	local bonusPath = {{row=1,column=1},{row=2,column=2},{row=1,column=3}}
	duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word="FAKE",path=bonusPath,xp=99999})
	check(profiles[1].xp==0 and profiles[1].progression.wordsFound==0, "Duel validates extra words without XP or race score")
	advance(0.2)
	duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word="COT",path={bonusPath[3],bonusPath[2],bonusPath[1]}})
	check(profiles[1].xp==0, "Reversed repeated Duel bonus grants no further XP")
	puzzle.letters = originalLetters
	advance(0.2)
end
local xp=120
for _, current in ipairs(puzzle.words) do
	xp+=puzzle.placedWordsByWord[current].length*20
	duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=current,answer=answer(puzzle,current)})
	duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=current,answer=answer(puzzle,current)}) -- Duplicate request.
	advance(0.2)
end
check(profiles[1].xp==xp and profiles[2].xp==0, "Duel word and completion XP remain independent")
check(last("DuelProgress",a).myRevealedAnswers[word]==answer(puzzle,word),"Accepted Duel answers return to their owner")
local opponentView=last("DuelProgress",b).myRevealedAnswers
local ownHintCount=0 for _ in pairs(opponentView) do ownHintCount+=1 end
check(ownHintCount==1,"Opponent receives only their own hint, not winner solutions")
check(profiles[1].progression.wordsFound==#puzzle.words and profiles[2].progression.wordsFound==0, "Duel word counts ignore duplicates, completion bonuses and the opponent")
check(last("DuelMatch",a,"result").isWinner and not last("DuelMatch",b,"result").isWinner, "Duel still chooses winner and loser")
check(profiles[1].mode=="Duel" and profiles[1].won and not profiles[2].won, "Duel outcomes use retained bucket")
check(leaderboardSnapshots[1].words == #puzzle.words and leaderboardSnapshots[1].won == true, "Winner publishes validated words and final wins to leaderboard")
check(leaderboardSnapshots[2].words == 0 and leaderboardSnapshots[2].won == false, "Loser publishes independently without gaining winner stats")
local winResult, loseResult = last("DuelMatch",a,"result"), last("DuelMatch",b,"result")
check(math.abs(winResult.score - ((xp-120)*5 + Config.Score.Completion(winResult.duration,180))) <= 1, "Duel score includes all letters and completion time rounded only for the result duration")
check(last("DuelProgress",a).myScore == winResult.score and loseResult.score == 0, "Progress and result agree on each player score")
check(winResult.xpEarned == xp and winResult.myXP == xp and winResult.myPuzzlePieces ~= xp, "Duel outcome XP is earned experience, not piece rewards")
check(winResult.foundCount == #puzzle.words and winResult.wordCount == #puzzle.words and winResult.theme == puzzle.title, "Winning result includes canonical board counts and theme")
check(loseResult.xpEarned == 0 and loseResult.foundCount == 0 and loseResult.wordCount == #puzzle.words, "Loser outcome retains only their own progress")
advance(6)
check(not a:GetAttribute("DuelBusy") and not b:GetAttribute("DuelBusy"), "Duel cleanup releases players")
advance(9)
check(duel:SendChallenge(a,2,"Duel") and duel:RespondToChallenge(b,true), "Second duel can start for forfeit validation")
local nextPuzzle = last("DuelMatch",b,"countdown").puzzleData
advance(6)
local nextWord = nextPuzzle.words[1]
profiles[2].hints = 1
check(duel:UseHint(b).success, "Partial Duel score fixture hints its first target")
duel:ReportProgress(b,{matchId=last("DuelMatch",b,"countdown").matchId,word=nextWord,answer=answer(nextPuzzle,nextWord)})
duel:AbandonMatch(b)
local quitResult, opponentResult = last("DuelMatch",b,"forfeit"),last("DuelMatch",a,"forfeit")
check(quitResult.youQuit and not quitResult.isWinner and quitResult.foundCount == 1 and quitResult.xpEarned == nextPuzzle.placedWordsByWord[nextWord].length * 20, "Forfeit loss still reports accepted partial words and XP")
check(quitResult.score == nextPuzzle.placedWordsByWord[nextWord].length*50 and opponentResult.score == 0, "Hint halves Duel letter score and forfeit preserves it without a completion bonus")
check(opponentResult.isWinner and opponentResult.foundCount == 0 and opponentResult.xpEarned == 0, "Opponent forfeit does not fabricate board completion XP")
advance(100)
check(duel:SendChallenge(a,2,"Duel"), "Invite starts before testing cancellation timeout")
advance(1)
profiles[2].settings.DuelInvites = false
duel:OnInviteSettingChanged(b)
profiles[2].settings.DuelInvites = true
advance(9)
check(duel:SendChallenge(a,2,"Duel"), "Same challenger can send a fresh invite after opt-in")
advance(80)
check(duel:RespondToChallenge(b,true), "Old cancelled invite timeout cannot expire its replacement")
-- Bot seats, actual server matches, adaptive pacing, rewards and cleanup.
duel:AbandonMatch(a)
advance(10)
local roster = duel:GetPlayerList(a)
check(avatarAttempts >= 5, "Duel avatars retry ready-but-blank, whitespace and pending images before admission")
for _, entry in ipairs(roster) do
	if entry.isBot then check(entry.thumbnailImage == "rbxassetid://verified-headshot", "Every listed bot has the accepted replacement headshot") end
end
check(#roster == 3 and roster[1].userId == 2, "Random minimum leaves two bots plus the real opponent instead of always filling the lobby")
local listRemote = storage.Remotes.Functions[Contract.Legacy.Duel.RequestPlayerList]
local stopFunction = duel.Stop
local firstRemoteList = listRemote.OnServerInvoke(a)
check(#firstRemoteList == #roster, "Actual list remote includes simulated opponents")
check(#listRemote.OnServerInvoke(a) == #firstRemoteList, "Rapid repeat list request retains the populated roster instead of clearing it")
check(duel.Stop == stopFunction, "Listing opponents cannot replace the server shutdown handler")
local botId = roster[2].userId
check(botId < 0 and roster[2].isBot and roster[2].thumbnailImage == "rbxassetid://verified-headshot", "Bots publish verified portraits and explicit identities")
check(not duel:SendChallenge(a, -99, "Duel"), "Forged negative bot IDs are rejected")
check(not duel:SendChallenge(a, math.huge, "Duel"), "Nonfinite opponent IDs are rejected")
check(duel:SendChallenge(a, botId, "Duel"), "Bot Request starts a playable server-owned Duel")
local botCountdown = last("DuelMatch", a, "countdown")
check(botCountdown.opponentIsBot and botCountdown.opponentId == botId and botCountdown.opponentThumbnailImage == roster[2].thumbnailImage, "Bot identity and portrait follow the countdown")
local initialBotStats = table.clone(botCountdown.opponentDuelStats)
check(initialBotStats.wins > 0 and initialBotStats.losses > 0, "Bots start with varied simulated win/loss records")
check(a:GetAttribute("DuelBusy") and not duel:SendChallenge(b, botId, "Duel"), "Bot cannot be claimed by two players")
local botPuzzle = botCountdown.puzzleData
local beforeWords, beforeXP = profiles[1].progression.wordsFound, profiles[1].xp
advance(6 + 60)
local botProgress = last("DuelProgress", a)
check(botProgress.opponentProgress <= 100 / #botPuzzle.words + 0.001 and profiles[1].xp == beforeXP, "Stalled human caps AI at one word without granting human XP")
check(profiles[1].progression.wordsFound == beforeWords and profiles[botId] == nil, "Bot solves create no profiles or human stats")
playerCount = 12
advance(2)
check(#duel:GetPlayerList(b) == 8, "Full human server shows at most eight real opponents")
check(a:GetAttribute("DuelBusy") and last("DuelMatch",a,"countdown").matchId == botCountdown.matchId, "Population changes do not remove an active bot opponent")
for _, current in ipairs(botPuzzle.words) do
	duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=current,answer=answer(botPuzzle,current)})
	advance(0.2)
end
check(last("DuelMatch",a,"result").isWinner and last("DuelMatch",a,"result").matchId == botCountdown.matchId, "Human can finish and win against the bot")
check(last("DuelMatch",a,"result").opponentDuelStats.losses == initialBotStats.losses + 1 and last("DuelMatch",a,"result").myDuelStats.wins == profiles[1].progression.duel.wins, "Results update both human saved records and bot session records")
advance(10)
check(not a:GetAttribute("DuelBusy"), "Bot match completion releases the human")
playerCount = 2
aggressive = true
advance(2)
roster = duel:GetPlayerList(a)
botId = roster[2].userId
check(duel:SendChallenge(a,botId,"Duel"), "New bot match can start after population returns")
botCountdown = last("DuelMatch",a,"countdown")
initialBotStats = table.clone(botCountdown.opponentDuelStats)
advance(6)
for index, current in ipairs(botCountdown.puzzleData.words) do
	if index == #botCountdown.puzzleData.words then break end
	duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=current,answer=answer(botCountdown.puzzleData,current)})
	advance(20)
end
advance(1200)
local botLoss = last("DuelMatch",a,"result")
check(botLoss.matchId == botCountdown.matchId and not botLoss.isWinner and botLoss.winnerId == botId, "Challenging AI can narrowly finish when the human reaches the final word")
check(botLoss.foundCount == #botPuzzle.words - 1 and botLoss.xpEarned > 0 and profiles[botId] == nil, "Bot victory preserves only human earned progress and has no bot profile")
check(botLoss.opponentDuelStats.wins == initialBotStats.wins + 1 and botLoss.opponentDuelStats.losses == initialBotStats.losses, "Competitive bot records its own win exactly once")
advance(10)
check(duel:SendChallenge(a,botId,"Duel"), "Bot can be requested again after match cleanup")
local abandoned = last("DuelMatch",a,"countdown").matchId
check(last("DuelMatch",a,"countdown").opponentDuelStats.wins == initialBotStats.wins + 1, "Rematching a bot preserves its session win history")
duel:AbandonMatch(a)
advance(10)
check(last("DuelMatch",a,"forfeit").matchId == abandoned and not a:GetAttribute("DuelBusy"), "Abandon during bot countdown cancels start and clears ownership")
check(last("DuelMatch",a,"forfeit").opponentDuelStats.wins == initialBotStats.wins + 2, "A forfeit adds exactly one win to the bot record")
duel:AbandonMatch(a)
for _, entry in ipairs(duel:GetPlayerList(a)) do
	if entry.userId == botId then check(entry.duel.wins == initialBotStats.wins + 2, "Lobby exposes retained bot results without duplicate awards") end
end
playerCount = 1
advance(2)
check(#duel:GetPlayerList(a) == 2, "A lone player can see only two bot opponents")
populationChoice = "max"
advance(121)
check(#duel:GetPlayerList(a) == 6, "Lone-player population can roll up to six companions")
populationChoice = "mid"
advance(121)
check(#duel:GetPlayerList(a) == 4, "Another population roll produces four bots")
populationChoice = "min"
advance(121)
check(#duel:GetPlayerList(a) == 2, "Population can shrink again without a player joining or leaving")
do
 playerCount = 2
 advance(10)
 check(duel:SendChallenge(a,2,"Duel") and duel:RespondToChallenge(b,true), "Human rematch fixture starts")
 local original = last("DuelMatch",a,"countdown")
 advance(6)
 for _, word in ipairs(original.puzzleData.words) do
  duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,answer=answer(original.puzzleData,word)})
  advance(0.2)
 end
 check(last("DuelMatch",a,"result").rematchAvailable, "Completed match advertises rematch")
 local xp = profiles[1].xp
 check(not duel:RequestRematch(a,"stale") and not duel:RequestRematch(player(50),original.matchId), "Stale and outsider rematch votes are rejected")
 check(duel:RequestRematch(a,original.matchId) and not duel:RequestRematch(a,original.matchId), "Rematch accepts one vote per participant")
 check(last("DuelMatch",b,"rematch").count == 1, "Both players see one rematch vote")
 check(duel:RequestRematch(b,original.matchId), "Opponent supplies second vote")
 check(last("DuelMatch",a,"rematch").count == 2, "Both votes publish 2/2")
 advance(0.49)
 check(last("DuelMatch",a,"countdown").matchId == original.matchId, "Rematch holds 2/2 for half a second")
 advance(0.02)
 local replay = last("DuelMatch",a,"countdown")
 check(replay.matchId ~= original.matchId and replay.puzzleData ~= original.puzzleData and profiles[1].xp == xp, "Rematch creates a fresh board without awarding duplicate XP")
 advance(6)
 check(last("DuelProgress",a).myProgress == 0, "Rematch resets score")
 for _, word in ipairs(replay.puzzleData.words) do
  duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,answer=answer(replay.puzzleData,word)})
  advance(0.2)
 end
 check(duel:RequestRematch(a,replay.matchId) and duel:RequestRematch(b,replay.matchId), "Another completed match can rematch")
 duel:AbandonMatch(b)
 advance(1)
 check(not last("DuelMatch",a,"rematch").available and last("DuelMatch",a,"countdown").matchId == replay.matchId, "Leaving during 2/2 cancels restart and hides rematch for opponent")
 playerCount = 1
 advance(10)
 local botId = duel:GetPlayerList(a)[1].userId
 check(duel:SendChallenge(a,botId,"Duel"), "Bot rematch fixture starts")
 local botMatch = last("DuelMatch",a,"countdown")
 advance(6)
 for _, word in ipairs(botMatch.puzzleData.words) do
  duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,answer=answer(botMatch.puzzleData,word)})
  advance(0.2)
 end
 advance(10)
 check(duel:RequestRematch(a,botMatch.matchId), "Bot remains available after result cleanup")
 check(last("DuelMatch",a,"rematch").count == 1, "Bot response is delayed")
 advance(3)
 check(last("DuelMatch",a,"countdown").opponentId == botId and last("DuelMatch",a,"countdown").matchId ~= botMatch.matchId, "Bot agrees and rematches with the same identity")
 duel:AbandonMatch(a)
 advance(10)
end
do
	playerCount = 6
	advance(2)
	local list = duel:GetPlayerList(a)
	local count = 0
	for _, entry in ipairs(list) do if entry.isBot then count += 1 end end
	check(count <= 1 and #list <= 6, "Six real players receive at most one bot")
	for realCount=1,12 do
		local minimum, maximum = botModule.PopulationRange(realCount)
		check(minimum <= maximum and maximum + math.min(8,realCount-1) <= 8, "Population range respects eight listed opponents")
	end
	playerCount = 1
	advance(10)
end

do
 playerCount = 2
 advance(10)
 check(duel:SendChallenge(a,2,"Duel") and duel:RespondToChallenge(b,true), "Timed human Duel starts")
 local countdown = last("DuelMatch",a,"countdown")
 advance(6)
 local start = last("DuelMatch",a,"start")
 check(start.timeLimit == 180 and start.expiresAt == now+180, "Duel deadline begins after countdown")
 local word = countdown.puzzleData.words[1]
 duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,answer=answer(countdown.puzzleData,word)})
 local xp, wins = profiles[1].xp, profiles[1].progression.duel.wins
 advance(180)
 duel:ReportCompletion(a,{})
 local result = last("DuelMatch",a,"result")
 check(result.matchId == countdown.matchId and result.timedOut and result.isWinner and result.duration == 180, "Highest theme count wins at time expiry")
 check(profiles[1].xp == xp and profiles[1].progression.duel.wins == wins+1, "Partial timed win grants no board-completion XP")
 duel:ReportProgress(a,{matchId=last("DuelMatch",a,"countdown").matchId,word=word,answer=answer(countdown.puzzleData,word)})
 advance(10)
 check(profiles[1].progression.duel.wins == wins+1, "Late requests cannot award a second Duel result")
 check(duel:SendChallenge(a,2,"Duel") and duel:RespondToChallenge(b,true), "Draw fixture starts")
 local drawId = last("DuelMatch",a,"countdown").matchId
 local losses = profiles[1].progression.duel.losses
 advance(187.1)
 result = last("DuelMatch",a,"result")
 check(result.matchId == drawId and result.isDraw and result.rematchAvailable and result.xpEarned == 0, "Equal timeout scores produce a rematchable draw")
 check(profiles[1].progression.duel.wins == wins+1 and profiles[1].progression.duel.losses == losses and profiles[1].xp == xp, "Draw changes neither win/loss statistics nor XP")
 advance(10)
 playerCount = 1
 advance(10)
end
local finalBot = duel:GetPlayerList(a)[1].userId
check(duel:SendChallenge(a, finalBot, "Duel"), "Bot countdown begins before shutdown")
local finalId = last("DuelMatch",a,"countdown").matchId
duel.Stop()
advance(10)
check(not a:GetAttribute("DuelBusy") and last("DuelMatch",a,"start").matchId ~= finalId, "Shutdown clears ownership and cancels pending bot starts")
do
	-- Reproduce a fresh server whose random avatar IDs all fail before any cache exists.
	randomAvatarsUnavailable = true
	local fallbackPool = botModule.new(storage.shared.config.GameConfig.Bots)
	fallbackPool:Refresh()
	check(#fallbackPool:List() == 0, "Unverified bots remain hidden while avatar jobs run")
	advance(0)
	local readyBots = fallbackPool:List()
	check(#readyBots == 2 and connectedAvatarCalls > 0, "Cold-cache Duel lobby recovers using a verified connected-account headshot")
	for _, member in ipairs(readyBots) do
		check(member.avatarReady and member.thumbnailImage == "rbxassetid://connected-fallback", "Recovered bots have an accepted portrait, never the blank tutorial image")
	end
	fallbackPool:Stop()
	randomAvatarsUnavailable = false
end
print("DUEL_TESTS_PASSED=" .. checks)
