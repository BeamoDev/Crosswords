local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rbx = require("@lune/roblox")
local Config = require("../src/shared/config/ProgressionConfig")
local Contract = require("../src/shared/network/NetworkContract")
local checks = 0
local function check(value, reason) assert(value, reason) checks += 1 end
local function signal()
	local s = { callbacks = {} }
	function s:Connect(fn) table.insert(self.callbacks, fn) end
	function s:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
	return s
end
local function node(children, class)
	children = children or {}
	children.ClassName = class or "Frame"
	function children:WaitForChild(name) return assert(self[name], name) end
	function children:FindFirstChild(name) return self[name] end
	function children:GetChildren()
		local result = {}
		for _, value in pairs(self) do if type(value) == "table" and value.ClassName then table.insert(result, value) end end
		return result
	end
	function children:IsA(kind) return self.ClassName == kind or kind == "GuiObject" or (kind == "GuiButton" and self.ClassName == "TextButton") end
	return children
end
local function button() return node({ Activated = signal(), TextLabel = node({Text=""}, "TextLabel") }, "TextButton") end
local ui = { home = node({Visible=true}), game = node({Visible=false}), queue = node({Visible=false}), pause = node({Visible=false}),
	modes = node(), buttonBar = node(), play = button(), queueLeave = button(), queueSolo = button(), exit = button(), resume = button(), leaveRound = button(), hint = button(),
	waiting = node(), queueSubtitle = node(), subtitle = node(), hintCount = node(), hintBadge = node() }
ui.home.SelectModeLabel = node({Text=""})
ui.buttonBar.Duel = button()
for mode in pairs(Config.Experience.ModeLevels) do
	ui.modes[mode] = node({Play=button()})
	ui.modes[mode].Play.Locked = node({Visible=true}, "ImageLabel")
end
local hud = node({Parent=true}, "ScreenGui")
local groupIntro = node({}, "ScreenGui")
local player = node({UserId=1, PlayerGui=node({Main=hud, GroupIntro=groupIntro})})
local queueSignal, roundSignal, stateSignal = signal(), signal(), signal()
local requests, counter, activeRound = {}, 0, nil
local queueRevision = 0
local failExit, failReplay = false, false
local snapshot = {meta={snapshotVersion=1}, tutorial={completed=true}, progression={level=1}, hints=1}
local action = {InvokeServer=function(_, payload)
	table.insert(requests, payload)
	if failReplay and (payload.action == "Join" or payload.action == "StartSolo") then
		if failReplay == "network" then error("test replay network failure") end
		return { success = false }
	end
	if payload.action == "StartSolo" then
		counter += 1
		activeRound = {id="solo"..counter, mode=payload.mode, solo=true, puzzle={words={"CAT"}}, members={{userId=1}}, revision=0}
		return {success=true, round=activeRound}
	elseif payload.action == "Exit" then
		if failExit then return {success=false, message="Try again."} end
		activeRound=nil return {success=true}
	elseif payload.action == "LeaveQueue" then
		queueRevision += 1
		return {success=true,queue={revision=queueRevision,count=0,members={}}}
	elseif payload.action == "Word" and payload.word == "" then
		return {success=false, round={id=activeRound.id, mode="Hardcore", revision=1, members={{userId=1, failed=true}}}}
	elseif payload.action == "Join" then queueRevision += 1 return {success=true, queue={revision=queueRevision,count=1,deadline=15,members={{userId=1,name="Test",displayName="Test",level=20}}}}
	end
	return {success=true}
end}
local folder = node({[Contract.QueueAction]=action, [Contract.QueueUpdated]={OnClientEvent=queueSignal}, [Contract.RoundUpdated]={OnClientEvent=roundSignal},
	[Contract.StateUpdated]={OnClientEvent=stateSignal}, [Contract.GetBootstrap]={InvokeServer=function() return snapshot end},
	[Contract.UseHint]={}, [Contract.TutorialAction]={}})
local board = {tiles={{{}}}, callbacks=nil}
function board:Cancel() end
function board:Build(puzzle, mode) self.puzzle,self.mode,self.completed=puzzle,mode,false self.found,self.hinted={},{} end
function board:Progress(members) self.members=members end
function board:DuelPlayers(userId, _, _, mine, theirs) self.opponentId=userId self.myStats,self.opponentStats=mine,theirs end
function board:DuelWinRates(mine, theirs) self.myStats,self.opponentStats=mine,theirs end
function board:DuelScores(mine, theirs) self.scores={mine,theirs} end
local introDone, duelContext, lobbyOpened, pauseInput, tutorialCallbacks
local abandoned = 0
local shownDuelOutcomes = {}
local outcomeContext, shownOutcomes = nil, {}
local outcomeDelays = {}
local function finishOutcomeDelay()
	local callbacks = outcomeDelays
	outcomeDelays = {}
	for _, callback in ipairs(callbacks) do callback() end
end
local meta = {bind=function() end,applySnapshot=function() end,
	showGameOutcome=function(_, result, profile) table.insert(shownOutcomes, {result=result, profile=profile}) end}
local tutorial = {Start=function() end,IsActive=function() return false end}
local controllers = node({
	InterfaceController={Bind=function() return ui end,UpdateLevelBars=function() end,
		UpdateQueue=function(_, members) ui.queueMembers=members end,
		UpdateQueueTimer=function(_, seconds) ui.queueSubtitle.Text="Classic Mode ("..math.max(0,math.ceil(seconds)).."s)" end},
	BoardController={new=function(_, callbacks) board.callbacks=callbacks return board end},
	ProgressionController={new=function(context) outcomeContext=context return meta end},
})
local client = node({features=node({
	Duels={new=function(context) duelContext=context return {bind=function() end,updateOutcome=function() end,showOutcome=function(_, payload) table.insert(shownDuelOutcomes, payload) end,showLobby=function() lobbyOpened=true end,abandon=function() abandoned+=1 end} end},
	Tutorial={new=function(_, _, callbacks) tutorialCallbacks=callbacks return tutorial end},
	Social={AutoRejoin={Init=function() end},FavouritePrompt={Init=function() end},GroupIntro={Play=function(_, _, _, done) introDone=done end}},
}), systems=node({Audio={SetEnabled=function() end,Initialize=function() end}, Input={bind=function(_, pause) pauseInput=pause end}, Device={Init=function() end}, Camera={ApplyJoinCamera=function() end}})})
controllers.Parent=client
local transition, transitionCount = nil, 0
local homeTransition, homeTransitionCount = nil, 0
local effects = {TransitionToGame=function(_, covered, complete)
	transitionCount += 1
	transition={covered=covered,complete=complete,cancelled=false}
	local current=transition
	return function() current.cancelled=true end
end, TransitionToHome=function(_, gameFrame, covered, complete)
	homeTransitionCount += 1
	homeTransition={gameFrame=gameFrame,covered=covered,complete=complete,cancelled=false}
	local current=homeTransition
	return function() current.cancelled=true end
end}
effects.TransitionToQueue = effects.TransitionToGame
local shared = node({ui=node({UIEffects=effects}),config=node({ProgressionConfig=Config,GameConfig=require("../src/shared/config/GameConfig")}),network=node({NetworkContract=Contract})})
local purchasePrompts = {}
local services = {StarterPlayer=node({StarterPlayerScripts={}}),Players={LocalPlayer=player},ReplicatedStorage=node({shared=shared,[Contract.FolderName]=folder}),
	UserInputService={GetLastInputType=function() return "MouseButton1" end},RunService={Heartbeat=signal()},Workspace={GetServerTimeNow=function() return 0 end},
	SoundService=node(),GuiService={},MarketplaceService={PromptProductPurchase=function(_, _, id) table.insert(purchasePrompts, id) end}}
local controller = luau.load(fs.readFile("src/client/controllers/GameController.luau"), {environment={
	Color3=rbx.Color3, UDim2=rbx.UDim2, Enum=rbx.Enum,
	game={GetService=function(_, name) return assert(services[name], name) end},
	script={Parent=controllers,IsDescendantOf=function() return false end},require=function(value) return value end,
	task={spawn=function(fn) fn() end,delay=function(_, callback) table.insert(outcomeDelays, callback) end},
}})()
controller.Start()
check(not hud.Enabled, "Main waits for intro")
introDone()
check(hud.Enabled, "Main enables after intro")
local before = #requests
ui.modes.Mini.Play.Activated:Fire()
check(#requests == before, "Locked Mini does not send a solo request")
snapshot.progression.level=20
snapshot.meta.snapshotVersion=2
stateSignal:Fire(snapshot)
local function finishExit()
	check(homeTransition.covered()==ui.home and ui.home.Visible and not ui.game.Visible and not ui.queue.Visible, "Home mounts under full white")
	local count=#requests
	ui.play.Activated:Fire()
	check(#requests==count, "Home Play waits for white to clear")
	homeTransition.complete(true)
end
for _, mode in ipairs({"Mini","Jumbo","Hardcore"}) do
	check(ui.modes[mode].Play.TextLabel.TextColor3 == rbx.Color3.new(1,1,1) and ui.modes[mode].Play.TextLabel.Text == "PLAY", "Unlocked button shows Play")
	local entries=transitionCount
	ui.modes[mode].Play.Activated:Fire()
	check(requests[#requests].action == "StartSolo" and requests[#requests].mode == mode, "Lobby sends direct solo request")
	check(transitionCount==entries+1 and ui.home.Visible and not ui.queue.Visible and not ui.game.Visible, "Solo starts white fade directly from Home without queue")
	local requestCount=#requests
	ui.modes.Jumbo.Play.Activated:Fire()
	check(#requests==requestCount, "Second solo click cannot interrupt entry")
	check(transition.covered()==ui.game and board.mode==mode and not ui.home.Visible, "Solo board mounts under white")
	check(not board.callbacks.canInteract(), "Solo reveal locks input")
	ui.exit.Activated:Fire()
	check(#requests==requestCount, "Exit cannot interrupt the entrance")
	transition.complete(true)
	check(board.callbacks.canInteract(), "Solo accepts input once reveal finishes")
	board.callbacks.submit("CAT", {{row=1,column=1},{row=1,column=2},{row=1,column=3}})
	check(requests[#requests].action == "Word" and requests[#requests].roundId == activeRound.id, "Solo word uses current round ID")
	ui.hint.Activated:Fire()
	check(requests[#requests].action == "Hint", "Solo hint uses round endpoint")
	local promptCount, beforeEmptyHint = #purchasePrompts, #requests
	snapshot.hints = 0
	ui.hint.Activated:Fire()
	check(#purchasePrompts == promptCount + 1 and purchasePrompts[#purchasePrompts] == 3573028208 and #requests == beforeEmptyHint, "Empty gameplay Hint prompts only the single-hint product")
	snapshot.hints = 1
	ui.hint.Activated:Fire()
	check(#purchasePrompts == promptCount + 1 and requests[#requests].action == "Hint", "Owned hints use gameplay validation without a purchase prompt")
	pauseInput()
	check(ui.pause.Visible and not board.callbacks.canInteract(), "Manual pause remains available")
	ui.resume.Activated:Fire()
	check(not ui.pause.Visible and board.callbacks.canInteract(), "Resume stays on current board")
	if mode == "Hardcore" then
		board.callbacks.invalidSelection({{row=1,column=1},{row=2,column=1}})
		check(board.completed and ui.subtitle.Text == "Wrong word! Leave to try again.", "Hardcore failure locks board and explains return")
	end
	local oldId = activeRound.id
	if mode == "Mini" then
		failExit=true
		local exits=homeTransitionCount
		ui.exit.Activated:Fire()
		check(homeTransitionCount==exits and ui.game.Visible and activeRound.id==oldId and board.callbacks.canInteract(), "Rejected Exit keeps the current board usable")
		failExit=false
	end
	if mode == "Hardcore" then pauseInput() ui.leaveRound.Activated:Fire()
	else ui.exit.Activated:Fire() end
	check(requests[#requests].action=="Exit" and requests[#requests].roundId==oldId and activeRound==nil, "Exit releases the exact server round")
	check(homeTransition.gameFrame==ui.game and ui.game.Visible and not ui.pause.Visible and not ui.home.Visible, "Exit reverses Game before switching to Home")
	check(not board.callbacks.canInteract(), "Outgoing board is locked")
	requestCount=#requests
	ui.exit.Activated:Fire()
	ui.leaveRound.Activated:Fire()
	ui.hint.Activated:Fire()
	check(#requests==requestCount, "Duplicate Exit and Hint cannot race outgoing animation")
	local entriesAfterExit=transitionCount
	roundSignal:Fire({id=oldId,mode=mode,revision=2,puzzle={},members={}})
	check(transitionCount==entriesAfterExit, "Late round packet cannot replace exit fade")
	finishExit()
	roundSignal:Fire({id=oldId, mode=mode, revision=3, puzzle={}, members={}})
	check(ui.home.Visible and transitionCount==entriesAfterExit, "Late progress cannot reopen exited solo round")
end
ui.buttonBar.Duel.Activated:Fire()
check(lobbyOpened and duelContext, "Duel lobby stays connected")
local duelPayload={matchId="duel1",opponentId=2,opponentName="Bob",puzzleData={words={"CAT"}},myDuelStats={wins=3,losses=1},opponentDuelStats={wins=1,losses=3}}
local entries=transitionCount
duelContext.onCountdown(duelPayload)
check(transitionCount==entries+1 and ui.home.Visible and not ui.game.Visible, "Duel countdown uses the same white entrance")
duelContext.onProgress({matchId="duel1",myFoundWords={CAT=true},opponentFoundWords={DOG=true}})
duelContext.onStart(duelPayload)
check(not board.callbacks.canInteract(), "Early Duel start does not unlock transition")
check(transition.covered()==ui.game and board.mode=="Duel" and board.opponentId==2, "Duel board and mugshots mount under white")
check(board.myStats.wins == 3 and board.opponentStats.losses == 3, "Countdown records reach the correct HUD labels")
check(board.members[1].foundWords.CAT and board.members[2].foundWords.DOG and board.scores[1]==1 and board.scores[2]==1, "Duel progress during fade is replayed with scores")
transition.complete(true)
check(board.callbacks.canInteract(), "Started Duel unlocks after entrance")
ui.exit.Activated:Fire()
check(abandoned==1 and homeTransition.gameFrame==ui.game, "Duel Exit abandons match and reverses Game")
local oldMembers=board.members
duelContext.onProgress({matchId="duel1",myFoundWords={},opponentFoundWords={}})
duelContext.onStart(duelPayload)
check(board.members==oldMembers and not board.callbacks.canInteract(), "Late Duel messages cannot restore abandoned game")
finishExit()

ui.play.Activated:Fire()
check(ui.home.Visible and not ui.queue.Visible, "Home stays visible while its outgoing animation runs")
transition.covered()
queueRevision += 1
queueSignal:Fire({revision=queueRevision,count=2,deadline=15,members={{userId=1,level=20},{userId=2,level=4}}})
transition.complete(true)
check(requests[#requests].action == "Join" and ui.queue.Visible and ui.waiting.Text == "2 Waiting" and #ui.queueMembers == 2, "Queue entrance applies the latest roster received during its fade")
check(ui.queueSubtitle.Text == "Classic Mode (15s)" and ui.queueMembers[1].level == 20, "Authored queue receives cards and countdown")
local firstQueuedRoster=ui.queueMembers
queueRevision += 1
queueSignal:Fire({revision=queueRevision,count=0,members={}})
check(ui.queueMembers==firstQueuedRoster, "Dispatch preserves visible cohort until white covers Queue")
entries=transitionCount
roundSignal:Fire({id="queueRound1",mode="Standard",puzzle={words={"CAT"}},revision=0,members={{userId=1}}})
check(transitionCount==entries+1 and ui.queue.Visible and not ui.game.Visible, "Queue stays visible throughout fade-in")
check(not board.callbacks.canInteract(), "Gameplay locked during white transition")
local requestCount=#requests
ui.queueLeave.Activated:Fire()
check(#requests==requestCount, "Queue exit cannot race a dispatched round during fade")
roundSignal:Fire({id="queueRound1",mode="Standard",revision=2,members={{userId=1,foundWords={CAT=true}}}})
check(transitionCount==entries+1, "Incoming progress does not restart fade")
check(transition.covered()==ui.game and ui.game.Visible and not ui.queue.Visible, "Game mounts only under full white")
check(board.members[1].foundWords.CAT and #ui.queueMembers==0, "Progress during fade is replayed and queue cards cleaned up")
check(not board.callbacks.canInteract(), "Gameplay waits for reveal to finish")
transition.complete(true)
check(board.callbacks.canInteract(), "Gameplay unlocks after panel reveal")
ui.exit.Activated:Fire()
check(homeTransition.gameFrame==ui.game and ui.game.Visible, "Standard Exit also reverses the game")
finishExit()
ui.play.Activated:Fire()
transition.covered()
transition.complete(true)
ui.queueLeave.Activated:Fire()
check(homeTransition.gameFrame==nil and ui.queue.Visible and requests[#requests].action=="LeaveQueue", "Queue Exit fades to Home without animating hidden game")
finishExit()
ui.play.Activated:Fire()
roundSignal:Fire({id="queueRound2",mode="Standard",puzzle={words={"CAT"}},revision=0,members={{userId=1}}})
local cancelledTransition=transition
roundSignal:Fire({error="Round unavailable"})
check(cancelledTransition.cancelled and ui.home.Visible, "Round failure cancels queued reveal")
check(cancelledTransition.covered()==nil, "Cancelled transition cannot mount stale game")
cancelledTransition.complete(true)
check(ui.home.Visible and not ui.game.Visible, "Late animation completion cannot reopen Game")

-- Changing views during an outgoing fade invalidates its delayed Home callback.
duelPayload.matchId="duel2"
duelContext.onCountdown(duelPayload)
duelContext.onResult({matchId="duel2",myDuelStats={wins=4,losses=1},opponentDuelStats={wins=1,losses=4}})
duelContext.onStart(duelPayload)
transition.covered()
transition.complete(true)
check(not board.callbacks.canInteract(), "Result during Duel entrance stays finished even with a late start")
check(board.myStats.wins == 4 and board.opponentStats.losses == 4, "A result under white preserves the updated records when the HUD mounts")
finishOutcomeDelay()
check(#shownDuelOutcomes == 1 and shownDuelOutcomes[1].matchId == "duel2", "Duel result opens after entry settles")
check(shownDuelOutcomes[1].beforeProgression and shownDuelOutcomes[1].beforeProgression ~= snapshot.progression, "Duel outcome carries its captured pre-match progression")
duelContext.onResult({matchId="duel2"})
finishOutcomeDelay()
check(#shownDuelOutcomes == 1, "Duplicate results do not reopen the outcome")
ui.exit.Activated:Fire()
local cancelledExit=homeTransition
duelPayload.matchId="duel3"
duelContext.onCountdown(duelPayload)
check(cancelledExit.cancelled and cancelledExit.covered()==nil, "New view cancels outgoing Home callback")
cancelledExit.complete(true)
transition.covered()
transition.complete(true)
duelContext.onStart(duelPayload)
check(ui.game.Visible and board.callbacks.canInteract(), "Cancelled exit completion cannot unlock or replace a later view")
duelContext.onResult({matchId="duel3"})
duelContext.onReturnHome()
finishExit()
finishOutcomeDelay()
check(#shownDuelOutcomes == 1, "A delayed result cannot reopen after returning Home")
local homeArrivals=0
tutorialCallbacks.openGame()
tutorialCallbacks.returnHomeAnimated(function() homeArrivals+=1 end)
check(homeTransition.gameFrame==ui.game and homeArrivals==0, "Tutorial exit uses the same animated Game panels")
homeTransition.covered()
check(ui.home.Visible and homeArrivals==0, "Tutorial congratulations wait through the white fade and Home reveal")
homeTransition.complete(true)
check(homeArrivals==1, "Tutorial receives completion only after the normal Home transition")
tutorialCallbacks.openGame()
tutorialCallbacks.returnHomeAnimated(function() homeArrivals+=1 end)
local skippedHome=homeTransition
tutorialCallbacks.showHome()
skippedHome.complete(true)
check(skippedHome.cancelled and homeArrivals==1, "Skip cancels animated Home completion without reopening congratulations")
-- Completed Standard/solo rounds display once and replay only after a successful exit.
local outcomeSerial = 0
local function launchOutcomeMode(mode)
	if mode == "Standard" then
		ui.play.Activated:Fire()
		transition.covered() transition.complete(true)
		outcomeSerial += 1
		activeRound = {id="outcomeClassic"..outcomeSerial,mode="Standard",puzzle={title="Animals",words={"CAT"}},revision=0,members={{userId=1}}}
		roundSignal:Fire(activeRound)
	else
		ui.modes[mode].Play.Activated:Fire()
		activeRound.puzzle.title = "Animals"
	end
	transition.covered()
end
local function completedPacket()
	return {id=activeRound.id,mode=activeRound.mode,revision=2,members={{userId=1,completed=true,count=1,xpEarned=180,foundWords={CAT=true}}}}
end
for _, mode in ipairs({"Standard", "Mini", "Jumbo", "Hardcore"}) do
	local beforeOutcome = #shownOutcomes
	launchOutcomeMode(mode)
	roundSignal:Fire(completedPacket())
	finishOutcomeDelay()
	check(#shownOutcomes == beforeOutcome, "Completion received under white waits for the game reveal")
	transition.complete(true)
	check(#shownOutcomes == beforeOutcome, "Completion leaves time for the final word feedback")
	finishOutcomeDelay()
	local result = shownOutcomes[#shownOutcomes].result
	check(result.beforeProgression and result.beforeProgression ~= snapshot.progression and result.beforeProgression.level == snapshot.progression.level, "Outcome carries a detached snapshot of progress captured at round entry")
	check(#shownOutcomes == beforeOutcome + 1 and result.mode == mode and result.theme == "Animals" and result.xpEarned == 180, "Outcome shows authoritative completion for each normal mode")
	roundSignal:Fire(completedPacket())
	finishOutcomeDelay()
	check(#shownOutcomes == beforeOutcome + 1, "Repeated round packets cannot reopen the dismissed outcome")
	failExit = true
	outcomeContext.onOutcomePlay(activeRound.id)
	check(not homeTransition or not ui.home.Visible, "Rejected exit keeps the completed board available")
	failExit = false
	local oldId, beforeReplay = activeRound.id, #requests
	local homeBefore, transitionsBefore = homeTransitionCount, transitionCount
	outcomeContext.onOutcomePlay(oldId)
	check(requests[beforeReplay + 1].action == "Exit" and #requests == beforeReplay + 2, "Play again releases the old round and requests the next view directly")
	outcomeContext.onOutcomePlay(oldId)
	check(#requests == beforeReplay + 2, "Repeated Play again cannot double-exit or create another round")
	check(homeTransitionCount == homeBefore and transitionCount == transitionsBefore + 1, "Replay uses exactly one entrance transition and never transitions through Home")
	check(ui.game.Visible and not ui.home.Visible, "Completed board remains visible until the direct transition reaches white")
	check(requests[#requests].action == (mode == "Standard" and "Join" or "StartSolo"), "Play again requeues Classic or starts the same solo mode")
	if mode ~= "Standard" then check(requests[#requests].mode == mode, "Solo replay preserves mode") end
	local afterReplay = #requests
	roundSignal:Fire({id=oldId,mode=mode,revision=999,puzzle={words={"OLD"}},members={}})
	check(transitionCount == transitionsBefore + 1 and homeTransitionCount == homeBefore, "Late packets from the exited board cannot interrupt direct replay")
	outcomeContext.onOutcomeHome(oldId)
	check(#requests == afterReplay, "A stale outcome button cannot exit the new round")
	transition.covered()
	check(not ui.home.Visible and (mode == "Standard" and ui.queue.Visible or mode ~= "Standard" and ui.game.Visible), "Replay mounts Queue or the next solo board without exposing Home")
	transition.complete(true)
	if mode == "Standard" then ui.queueLeave.Activated:Fire() else ui.exit.Activated:Fire() end
	finishExit()
end
launchOutcomeMode("Mini")
transition.complete(true)
local beforeDismissed = #shownOutcomes
roundSignal:Fire(completedPacket())
ui.exit.Activated:Fire()
finishOutcomeDelay()
check(#shownOutcomes == beforeDismissed, "Leaving during the final-word delay prevents a stale popup")
finishExit()
launchOutcomeMode("Mini")
transition.complete(true)
roundSignal:Fire({id=activeRound.id,mode="Mini",revision=1,members={{userId=1},{userId=2,completed=true,count=1,xpEarned=180}}})
finishOutcomeDelay()
check(#shownOutcomes == beforeDismissed, "Another player's completion never shows your outcome")
roundSignal:Fire(completedPacket())
finishOutcomeDelay()
outcomeContext.onOutcomeHome(activeRound.id)
finishExit()
check(ui.home.Visible and requests[#requests].action == "Exit", "Outcome Home returns without replaying")

for _, mode in ipairs({ "Standard", "Mini" }) do
	for _, failure in ipairs({ true, "network" }) do
		launchOutcomeMode(mode)
		transition.complete(true)
		roundSignal:Fire(completedPacket())
		finishOutcomeDelay()
		local failedId, previousHome = activeRound.id, homeTransitionCount
		failReplay = failure
		outcomeContext.onOutcomePlay(failedId)
		failReplay = false
		check(homeTransitionCount == previousHome + 1, "Failed replay admission starts one recoverable Home transition")
		finishExit()
		check(ui.home.Visible and not ui.game.Visible and not ui.queue.Visible, "Rejected or network-failed replay returns to usable Home")
		local afterFailure = #requests
		outcomeContext.onOutcomePlay(failedId)
		check(#requests == afterFailure, "Failed replay cannot reuse the exited outcome")
	end
end

ui.play.Activated:Fire()
transition.covered() transition.complete(true)
local soloTransitionCount = transitionCount
ui.queueSolo.Activated:Fire()
check(requests[#requests].action == "StartSolo" and requests[#requests].mode == "Standard" and transitionCount == soloTransitionCount + 1, "Queue Solo starts a direct Classic game transition")
transition.covered() transition.complete(true)
check(ui.game.Visible and not ui.queue.Visible and not ui.home.Visible, "Queue Solo enters Game without visiting Home")
ui.exit.Activated:Fire()
finishExit()

print("LOBBY_TESTS_PASSED=" .. checks)
