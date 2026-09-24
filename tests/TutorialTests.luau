require("../src/shared/puzzle/PuzzleTests.spec")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Generator = require("../src/shared/puzzle/PuzzleGenerator")
local QueueState = require("../src/server/services/QueueState")
local Contract = require("../src/shared/network/NetworkContract")
local checks, now, counter = 0, 100, 0
local function check(value, reason) assert(value, reason) checks += 1 end
local function folder(value)
	value.WaitForChild = function(self, name) return assert(self[name], name) end
	return value
end
local removed
local players = { PlayerRemoving = { Connect = function(_, callback) removed = callback end } }
local actor = { UserId = 12, Name = "Learner", DisplayName = "Learner", Parent = players,
	attributes = { ProfileReady = true, TutorialBusy = true } }
function actor:GetAttribute(name) return self.attributes[name] end
players.LocalPlayer = actor
local profiles, saves, saved = {}, 0, true
local function fresh()
	if removed then removed(actor) end
	profiles[actor.UserId] = { tutorial = { completed = false }, progression = { level = 1, xp = 0 }, hints = 0 }
end
fresh()
local data = {
	GetMutableData = function(p) return profiles[p.UserId] end,
	IsTutorialPending = function(p) return p:GetAttribute("TutorialReplayPending") == true or not profiles[p.UserId].tutorial.completed end,
	GetSnapshot = function(p) return profiles[p.UserId] end,
	CompleteTutorial = function(p, skipped)
		saves += 1
		p.attributes.TutorialReplayPending = false
		profiles[p.UserId].tutorial.completed = true
		profiles[p.UserId].tutorial.skipped = profiles[p.UserId].tutorial.skipped or skipped
		return saved
	end,
}
local services = {
	Players = players, Workspace = {GetServerTimeNow = function() return now end},
	ReplicatedStorage = folder({ shared = folder({ config = folder({ProgressionConfig = require("../src/shared/config/ProgressionConfig"), GameConfig = require("../src/shared/config/GameConfig")}), puzzle = { PuzzleGenerator = Generator }, network = { NetworkContract = Contract } }) }),
	HttpService = { GenerateGUID = function() counter += 1 return "tutorial_" .. counter end },
}
local server = luau.load(fs.readFile("src/server/services/TutorialService.luau"), { environment = {
	game = { GetService = function(_, name) return assert(services[name], name) end },
	script = { Parent = { QueueState = QueueState, Parent = { data = { DataService = data } } } },
	require = function(module) return module end,
	os = { clock = function() return now end },
} })()
local remote = {}
server.Init(remote)
local function request(payload)
	now += 1.1
	return remote.OnServerInvoke(actor, payload)
end
check(not request({ action = "GrantXP" }).success, "Unknown tutorial action rejected")
actor.attributes.ProfileReady = false
check(not request({ action = "Start" }).success, "Unloaded player rejected")
actor.attributes.ProfileReady = true
actor.attributes.RoundBusy = true
check(not request({ action = "Start" }).success, "Cannot overlay an active real round")
actor.attributes.RoundBusy = false
local start = request({ action = "Start" })
local round = start.round
check(start.success and #round.puzzle.words == 3 and #round.puzzle.letters == 3 and #round.puzzle.letters[1] == 3, "Practice fills a 3x3 board with three words")
check(round.puzzle.placedWordsByWord.CAT and round.puzzle.placedWordsByWord.DOG, "Practice uses familiar CAT/DOG")
check(request({ action = "Start" }).round.id == round.id, "Repeated Start keeps the same session")
check(not request({ action = "Complete", roundId = round.id }).success and saves == 0, "Cannot fake tutorial win")
check(not request({ action = "Word", roundId = "stale", word = "CAT", path = round.puzzle.placedWordsByWord.CAT.path }).success, "Stale session rejected")
check(not request({ action = "Word", roundId = round.id, word = "CAT", path = round.puzzle.placedWordsByWord.DOG.path }).success, "Forged word path rejected")
check(request({ action = "Word", roundId = round.id, word = "CAT", path = round.puzzle.placedWordsByWord.CAT.path }).success, "First practice word validated")
check(not request({ action = "Word", roundId = round.id, word = "CAT", path = round.puzzle.placedWordsByWord.CAT.path }).success, "Duplicate word rejected")
local hint = request({ action = "Hint", roundId = round.id })
check(hint.success and hint.round.members[1].hintedWords.DOG, "Practice hint works at zero inventory")
check(request({ action = "Word", roundId = round.id, word = "DOG", path = round.puzzle.placedWordsByWord.DOG.path }).success, "Second practice word validates")
check(not request({ action = "Complete", roundId = round.id }).success, "Two words cannot finish a nine-tile practice board")
local foxPath = round.puzzle.placedWordsByWord.FOX.path
check(request({action="Word", roundId=round.id, word="FOX", path={foxPath[3],foxPath[2],foxPath[1]}}).success, "Backward FOX completes practice")
local finishedPractice = request({action="Sync",roundId=round.id}).round.members[1]
check(finishedPractice.score >= 750 and finishedPractice.score <= 1750, "Practice tracks 750 letter points plus completion speed without touching real XP")
check(profiles[12].hints == 0 and profiles[12].progression.xp == 0, "Practice leaves real hint/XP balance unchanged")
saved = false
check(request({ action = "Complete", roundId = round.id }).saved == false, "Failed durable save exposed to client")
saved = true
check(request({ action = "Complete", roundId = round.id }).saved, "Completion can retry after session cleanup")
local savesAfterComplete = saves
check(request({ action = "Complete", roundId = round.id }).saved and saves == savesAfterComplete, "Duplicate completion does not write another save")
check(request({ action = "Start" }).completed, "Completed players cannot restart tutorial")
removed(actor)
actor.attributes.TutorialReplayPending = true
local replay = request({ action = "Start" })
check(replay.success and replay.round, "A completed player gets practice again on a new testing join")
check(not request({ action = "Complete", roundId = replay.round.id }).success, "Replay still requires a validated practice win")
check(request({ action = "Skip" }).saved and not actor.attributes.TutorialReplayPending, "Skip ends replay for this session")

fresh()
check(request({ action = "Skip" }).saved and profiles[12].tutorial.skipped, "Skip works directly from Home")
fresh()
local departing = request({ action = "Start" }).round
removed(actor)
check(not request({ action = "Word", roundId = departing.id, word = "CAT", path = departing.puzzle.placedWordsByWord.CAT.path }).success, "Disconnect removes practice session")


do
 fresh()
 local timed = request({action="Start"}).round
 check(timed.timeLimit == 180 and timed.expiresAt == now+180, "Practice publishes its three-minute deadline")
 now = timed.expiresAt
 local expired = request({action="Sync",roundId=timed.id})
 check(expired.round.members[1].timedOut and not profiles[12].tutorial.completed, "Practice expiry does not complete onboarding")
 check(not request({action="Word",roundId=timed.id,word="CAT",path=timed.puzzle.placedWordsByWord.CAT.path}).success, "Expired practice rejects late words")
 local retry = request({action="Start"}).round
 check(retry.id ~= timed.id and retry.expiresAt > timed.expiresAt and not retry.members[1].failed, "Practice retry gets a fresh board and deadline")
 fresh()
end
-- Exercise the actual spotlight geometry independently of a Studio renderer.
local view = luau.load(fs.readFile("src/client/features/TutorialView.luau"), { environment = {
	game = { GetService = function() return {} end },
} })()
for _, viewport in ipairs({ { 390, 844 }, { 844, 390 }, { 1366, 768 }, { 1920, 1080 } }) do
	local width, height = table.unpack(viewport)
	local panels, hole = view.Mask(width, height, width * 0.32, height * 0.38, width * 0.3, height * 0.18, 8)
	local area = hole[3] * hole[4]
	for _, panel in ipairs(panels) do
		check(panel[1] >= 0 and panel[2] >= 0 and panel[3] >= 0 and panel[4] >= 0, "Mask dimensions stay valid")
		area += panel[3] * panel[4]
	end
	check(area == width * height, "Mask and opening partition the screen exactly")
end

-- Run the real client step controller against the real practice server.
local ui = {}
local function node(name, class)
	local item = roblox.Instance.new(class or "Frame") item.Name = name return item
end
for _, name in ipairs({ "standard", "play", "waiting", "boardPanel", "wordPanel", "subtitle", "hint", "game", "home" }) do
	ui[name] = node(name, (name == "waiting" or name == "subtitle") and "TextLabel" or "Frame")
end
local level = node("LevelBar") level.Parent = ui.game
local reward = node("NextLevelRewardTitle", "TextLabel") reward.Parent = level
local stubView = {}
function stubView.new(_, advance, skip)
	local value = { advance = advance, skip = skip }
	function value:Start() self.active = true end
	function value:SetDragGuide(grid, path, columns, rows, busy) self.guideGrid, self.guidePath, self.guideBusy = grid, path, busy end
	function value:Celebrate() self.celebrated = true end
	function value:Show(title, message, target, autoAdvance) self.title, self.message, self.target, self.autoAdvance, self.typing = title, message, target, autoAdvance, false end
	function value:Collapse(callback) self.collapsing, self.onCollapsed = true, callback end
	function value:Suspend() self.suspended = true end
	function value:Close() self.active, self.closed = false, true end
	function value:BlocksPointer() return false end
	return value
end
local board = { grid = node("Grid"), rows = {}, width = 4, height = 4 }
function board:Cancel() self.cancelled = true end
function board:PortraitColor() return roblox.Color3.fromRGB(173, 195, 204) end
function board:Build(puzzle)
	self.puzzle = puzzle
	self.height, self.width = #puzzle.letters, #puzzle.letters[1]
	for _, row in pairs(self.rows) do row:Destroy() end
	self.rows = {}
	for _, word in ipairs(puzzle.words) do
		local row = node(word)
		local panel = node("FoundPanel") panel.Parent = row
		local template = node("PlayerTemplate", "ImageLabel") template.Parent = row
		self.rows[word] = row
	end
end
function board:Progress(members)
	self.found, self.hinted = table.clone(members[1].foundWords), table.clone(members[1].hintedWords)
end
local jobs = {}
local client = luau.load(fs.readFile("src/client/features/Tutorial.luau"), { environment = {
	game = { GetService = function() return players end },
	script = { Parent = { TutorialView = stubView } }, require = function(module) return module end,
	Instance = roblox.Instance, UDim2 = roblox.UDim2, UDim = roblox.UDim, Color3 = roblox.Color3,
	task = { spawn = function(fn) table.insert(jobs, fn) end, wait = function() end },
} })()
local homeCount, gameCount, restores = 0, 0, 0
local homeFinished
local callbacks = {
	remote = { InvokeServer = function(_, payload) return request(payload) end },
	showHome = function() homeCount += 1 end, openGame = function() gameCount += 1 end,
	returnHomeAnimated = function(done) homeFinished = done end,
	restore = function() restores += 1 end, applySnapshot = function() end,
}
fresh()
local tutorial = client.new(ui, board, callbacks)
tutorial:Start(profiles[12])
check(tutorial.step == "FindCat" and gameCount == 1 and homeCount == 0 and board.grid.Visible and ui.exit == nil, "Tutorial opens practice directly in Game without visiting Home or requiring Play")
check(tutorial.view.message == "Make CAT!" and tutorial.view.guidePath == tutorial.round.puzzle.placedWordsByWord.CAT.path, "CAT uses short copy and the canonical drag demonstration")
tutorial.view.typing = true
check(not tutorial:CanUseBoard(), "Board waits until its short instruction is ready")
tutorial.view.typing = false
board.startCell = {row=1,column=1}
check(tutorial.view.guideBusy(), "Real player drag suppresses the demonstration")
board.startCell = nil
check(not tutorial.view.guideBusy(), "Demonstration resumes when the player is idle")
check(tutorial:CanUseBoard() and not tutorial.view.autoAdvance, "First practice step waits for a word")
tutorial.view.transitioning = true
check(not tutorial:CanUseBoard(), "Board input is locked during panel transitions")
tutorial.view.transitioning = false
tutorial:Submit("DOG", tutorial.round.puzzle.placedWordsByWord.DOG.path)
check(tutorial.step == "FindCat" and not board.found.DOG, "Practice keeps learner on first word")
tutorial:Submit("CAT", tutorial.round.puzzle.placedWordsByWord.CAT.path)
check(tutorial.step == "TryHint" and board.found.CAT, "CAT goes straight to the hint step")
check(not tutorial.view.guidePath, "Hint step clears the CAT demonstration")
check(not board.rows.DOG.FoundPanel:FindFirstChild("TutorialExample") and not board.found.DOG, "Tutorial never inserts an example portrait")
tutorial:Advance() tutorial:Hint()
check(tutorial.step == "FindDog" and board.hinted.DOG, "Free hint advances final practice task")
check(tutorial.view.message == "Make DOG!" and tutorial.view.guidePath == tutorial.round.puzzle.placedWordsByWord.DOG.path, "DOG uses its own canonical guide")
tutorial:Submit("DOG", tutorial.round.puzzle.placedWordsByWord.DOG.path)
check(tutorial.step == "FindFox" and tutorial:CanUseBoard(), "Last practice step permits either direction")
check(tutorial.view.message == "Make FOX!" and tutorial.view.guidePath == tutorial.round.puzzle.placedWordsByWord.FOX.path, "FOX uses short copy and its own guide")
local finalPath = tutorial.round.puzzle.placedWordsByWord.FOX.path
tutorial:Submit("FOX", {finalPath[3], finalPath[2], finalPath[1]})
check(tutorial.step == "Win" and board.found.FOX and tutorial.view.autoAdvance and tutorial.view.celebrated, "Win explanation will return home automatically")
tutorial:Advance()
check(tutorial.pending and tutorial.step == "Win" and tutorial.view.collapsing and homeCount == 0, "Win collapses guidance before starting the Home transition")
tutorial.view.onCollapsed()
check(tutorial.view.suspended and homeFinished and tutorial.step == "Win", "Congrats waits for animated Home completion")
homeCount += 1
homeFinished()
check(tutorial.step == "HomeCongrats" and homeCount == 1 and tutorial.active and not tutorial.finished, "Win returns Home before the final congratulations")
check(tutorial.view.title == "Tutorial done!" and tutorial.view.message == "Have fun finding words!" and tutorial.view.autoAdvance, "Final Home message advances automatically")
check(tutorial.view.target == nil, "Home congratulations do not spotlight any Home control")
tutorial:Advance()
check(tutorial.pending and tutorial.view.collapsing and not tutorial.finished and #jobs == 0, "Final message shrinks before completion cleanup")
tutorial.view.onCollapsed()
check(tutorial.finished and not tutorial.active and tutorial.view.closed and ui.exit == nil and restores == 1, "Finish cleans up after the final collapse")
local job = table.remove(jobs, 1) job()
check(profiles[12].tutorial.completed and not profiles[12].tutorial.skipped, "Practice win is saved as completion")
tutorial:Start({ tutorial = { completed = false } })
check(not tutorial.active, "Stale snapshot cannot reopen finished tutorial")

fresh()
local skipped = client.new(ui, board, callbacks)
skipped:Start(profiles[12]) skipped.view.typing = true skipped.pending = true
skipped:Finish(true)
check(not skipped.active and skipped.view.closed, "Skip immediately closes during typing or a pending request")
job = table.remove(jobs, 1) job()
check(profiles[12].tutorial.skipped, "Skip persists from initial explanation")
local returning = client.new(ui, board, callbacks)
returning:Start(profiles[12])
check(not returning.active, "Returning completed player bypasses tutorial")
-- A late Start response must not reopen the board after Skip.
fresh()
local lateTutorial
local lateCallbacks = table.clone(callbacks)
lateCallbacks.remote = { InvokeServer = function(_, payload)
	local result = request(payload)
	if payload.action == "Start" then lateTutorial:Finish(true) end
	return result
end }
lateTutorial = client.new(ui, board, lateCallbacks)
local openedBeforeLateReply = gameCount
lateTutorial:Start(profiles[12])
lateTutorial:Advance()
lateTutorial:Play()
check(not lateTutorial.active and gameCount == openedBeforeLateReply + 1 and not lateTutorial.round, "Delayed Start reply cannot reopen practice after Skip")
job = table.remove(jobs, 1) job()
check(profiles[12].tutorial.skipped, "Skip during Start still saves completion")

fresh()
local exitTutorial = client.new(ui,board,callbacks)
exitTutorial:Start(profiles[12])
exitTutorial:Show("Win")
exitTutorial:Advance()
exitTutorial.view.onCollapsed()
local delayedHome = homeFinished
exitTutorial:Finish(true)
delayedHome()
check(exitTutorial.finished and not exitTutorial.active and exitTutorial.step~="HomeCongrats", "Skip during Home transition invalidates its pending congratulations")
job=table.remove(jobs,1) job()
check(profiles[12].tutorial.skipped, "Skip during Home transition still persists")


do
 fresh()
 local timedTutorial = client.new(ui,board,callbacks)
 timedTutorial:Start(profiles[12])
 local oldId = timedTutorial.round.id
 now = timedTutorial.round.expiresAt
 timedTutorial:Tick(now)
 check(timedTutorial.pending and #jobs == 1, "Expired practice asks the server once while a timeout sync is pending")
 timedTutorial:Tick(now)
 check(#jobs == 1, "Repeated frames cannot duplicate the pending timeout request")
 table.remove(jobs,1)()
 check(timedTutorial.step == "Retry" and not timedTutorial:CanUseBoard() and not profiles[12].tutorial.completed, "Server timeout replaces guidance with retry without completing practice")
 local homesBeforeRetry = homeCount
 timedTutorial:Advance()
 check(timedTutorial.round.id ~= oldId and timedTutorial.step == "FindCat" and homeCount == homesBeforeRetry, "Retry opens fresh practice directly within Game")
 timedTutorial:Finish(true) table.remove(jobs,1)()
end
do
 fresh()
 local attempts = 0
 local retryCallbacks = table.clone(callbacks)
 retryCallbacks.remote = {InvokeServer = function(_, payload)
  if payload.action == "Start" then
   attempts += 1
   if attempts <= 2 then return nil end
  end
  return request(payload)
 end}
 local loading = client.new(ui,board,retryCallbacks)
 local homesBeforeLoading = homeCount
 loading:Start(profiles[12])
 check(loading.step == "Loading" and not loading:CanUseBoard() and not loading.view.guidePath, "Failed initial request stays in Game with input blocked")
 loading:Tick(now)
 loading:Tick(now + 0.5)
 check(attempts == 2 and loading.step == "Loading", "Loading retry does not repeat every frame")
 loading:Tick(now + 2)
 check(attempts == 3 and loading.step == "FindCat" and homeCount == homesBeforeLoading, "Loading recovers automatically without a Home detour")
 loading:Finish(true) table.remove(jobs,1)()
 fresh()
 local emptyBoard = {rows={}, Cancel=function() end}
 local skipLoading
 retryCallbacks.remote = {InvokeServer=function(_,payload)
  if payload.action == "Start" then skipLoading:Finish(true) return nil end
  return request(payload)
 end}
 skipLoading=client.new(ui,emptyBoard,retryCallbacks)
 skipLoading:Start(profiles[12])
 check(skipLoading.finished and not skipLoading.active, "Skip before a grid exists safely closes initial loading")
 table.remove(jobs,1)()
end
-- Exercise typewriter cancellation, actual view teardown without assigning UI focus.
local function signal()
	local value = { callbacks = {} }
	function value:Connect(callback)
		local connection = { connected = true, callback = callback }
		function connection:Disconnect() self.connected = false end
		table.insert(self.callbacks, connection)
		return connection
	end
	function value:Fire(...)
		for _, connection in ipairs(self.callbacks) do if connection.connected then connection.callback(...) end end
	end
	return value
end
local mockNodes = {}
local function mockNode(class, name)
	local item = { ClassName = class, Name = name or class, Visible = true, ZIndex = 1, Selectable = true,
		AbsoluteSize = roblox.Vector2.new(200, 100), AbsolutePosition = roblox.Vector2.new(0, 0),
		Size = roblox.UDim2.fromScale(0.3, 0.2), Position = roblox.UDim2.fromOffset(20, 30), AnchorPoint = roblox.Vector2.new(0.5, 0.5),
		Activated = signal(), Changed = signal() }
	function item:IsA(kind) return self.ClassName == kind or kind == "GuiObject"
		or (kind == "GuiButton" and self.ClassName == "TextButton") end
	function item:IsDescendantOf(parent)
		local current = self.Parent
		while current do if current == parent then return true end current = current.Parent end
		return false
	end
	function item:GetDescendants()
		local children = {}
		for _, candidate in ipairs(mockNodes) do if candidate:IsDescendantOf(self) then table.insert(children, candidate) end end
		return children
	end
	function item:FindFirstChild(childName)
		for _, candidate in ipairs(mockNodes) do if candidate.Parent == self and candidate.Name == childName then return candidate end end
	end
	function item:Destroy() self.Parent = nil self.destroyed = true end
	table.insert(mockNodes, item)
	return item
end
local screen = mockNode("ScreenGui") screen.IgnoreGuiInset = true
local tutorialFrame = mockNode("Frame", "Tutorial") tutorialFrame.Parent = screen
local content = mockNode("Frame", "Content") content.Parent = tutorialFrame
local paragraph = mockNode("TextLabel", "Paragraph") paragraph.Parent = content
local heading = mockNode("TextLabel", "Title") heading.Parent = content
local icon = mockNode("ImageLabel", "Icon") icon.Parent = tutorialFrame
local skipButton = mockNode("TextButton", "Skip") skipButton.Parent = tutorialFrame
local playButton = mockNode("TextButton", "Play") playButton.Parent = screen
playButton.AbsolutePosition = roblox.Vector2.new(350, 250)
local popScale = mockNode("UIScale", "PopScale") popScale.Scale, popScale.Parent = 1, tutorialFrame
local originalIconPosition, originalFrameSize = icon.Position, tutorialFrame.Size
local tweens, scheduled = {}, {}
local viewTime = 0
local function schedule(seconds, fn) table.insert(scheduled, { at = viewTime + seconds, callback = fn }) end
local function resumeJob(thread)
	local ok, delay = coroutine.resume(thread)
	assert(ok, delay)
	if coroutine.status(thread) ~= "dead" and type(delay) == "number" then
		schedule(delay, function() resumeJob(thread) end)
	end
end
local function advanceViewTime(seconds)
	local deadline = viewTime + seconds
	while true do
		table.sort(scheduled, function(a, b) return a.at < b.at end)
		if not scheduled[1] or scheduled[1].at > deadline then break end
		local event = table.remove(scheduled, 1)
		viewTime = event.at
		event.callback()
	end
	viewTime = deadline
end
local guiService = setmetatable({}, { __newindex = function(self, key, value)
	assert(key ~= "SelectedObject", "Game code must never set UI focus")
	rawset(self, key, value)
end })
local renderSignal = signal()
local viewServices = { GuiService = guiService, RunService = { RenderStepped = renderSignal },
	TweenService = { Create = function(_, target, info, goal)
		local tween = { goal = goal, target = target, info = info, cancelled = false }
		local waiting
		tween.Completed = { Wait = function() waiting = coroutine.running() coroutine.yield("tween") end }
		function tween:Play()
			self.played = true
			if info.repeats == -1 then return end
			schedule(info.duration, function()
				if self.cancelled then return end
				for key, value in pairs(goal) do
					target[key] = value
					if key == "Value" then target.Changed:Fire(value) end
				end
				if waiting then local thread = waiting waiting = nil resumeJob(thread) end
			end)
		end
		function tween:Cancel()
			self.cancelled = true
			if waiting then local thread = waiting waiting = nil resumeJob(thread) end
		end
		table.insert(tweens, tween)
		return tween
	end } }
local viewModule = luau.load(fs.readFile("src/client/features/TutorialView.luau"), { environment = {
	game = { GetService = function(_, name) return viewServices[name] end },
	Instance = { new = mockNode }, Vector2 = roblox.Vector2, UDim2 = roblox.UDim2, Color3 = roblox.Color3, Enum = roblox.Enum,
	TweenInfo = { new = function(duration, _, _, repeats) return { duration = duration, repeats = repeats } end },
	task = { spawn = function(fn) resumeJob(coroutine.create(fn)) end, wait = function(seconds) coroutine.yield(seconds) end, delay = schedule },
} })()
local advances, actualView = 0, nil
local function createView()
	local value
	value = viewModule.new({ screenGui = screen, game = {Visible=true} }, function() advances += 1 end, function() value:Close() end)
	value:Start()
	value.root.AbsoluteSize = roblox.Vector2.new(2000, 1500)
	value.root.AbsolutePosition = roblox.Vector2.new(-600, -450)
	return value
end
actualView = createView()
actualView:Show("Welcome", "Hello", playButton, true, false)
check(actualView.transitioning and tutorialFrame.Size == roblox.UDim2.fromScale(0, 0), "First step grows from zero size")
check(actualView.panels[1].BackgroundTransparency==1 and actualView.maskTween.goal.Value==1, "Spotlight begins transparent and fades in alongside its first panel")
check(not playButton.Selectable and skipButton.Selectable, "Only Skip is selectable during transitions")
check(not content:FindFirstChild("TutorialContinue") and paragraph.Text == "Hello", "No continuation control or prompt")
advanceViewTime(0.22)
check(not actualView.transitioning and actualView.typing and tutorialFrame.Size == originalFrameSize and popScale.Scale == 1, "Panel reaches original size before typing starts")
check(actualView.maskOpacity==1 and math.abs(actualView.panels[1].BackgroundTransparency-0.32)<0.00001, "Spotlight reaches its original dim opacity at reveal completion")
for _, viewport in ipairs({ {390, 844}, {844, 390}, {1366, 768}, {1920, 1080} }) do
	local width, height = table.unpack(viewport)
	actualView.root.AbsoluteSize = roblox.Vector2.new(width * 2, height * 2)
	actualView.root.AbsolutePosition = roblox.Vector2.new(-width / 2, -height / 2)
	playButton.AbsolutePosition = roblox.Vector2.new(width * 0.32, height * 0.38)
	playButton.AbsoluteSize = roblox.Vector2.new(width * 0.15, height * 0.1)
	renderSignal:Fire()
	check(tutorialFrame.Position == roblox.UDim2.fromScale(0.5, 0.862) and tutorialFrame.AnchorPoint == roblox.Vector2.new(0.5, 0.5), "Default tutorial position stays scaled across viewports and preserves authored anchor")
end
actualView.root.AbsoluteSize = roblox.Vector2.new(2000, 1500)
actualView.root.AbsolutePosition = roblox.Vector2.new(-600, -450)
playButton.AbsolutePosition, playButton.AbsoluteSize = roblox.Vector2.new(350, 250), roblox.Vector2.new(200, 100)
local talking = tweens[#tweens]
check(talking.target == icon and talking.played and paragraph.MaxVisibleGraphemes == 1, "Icon talks only when text starts")
advanceViewTime(0.12)
check(not actualView.typing and paragraph.MaxVisibleGraphemes == -1 and talking.cancelled, "Text completes and icon stops naturally")
advanceViewTime(1.98)
check(advances == 0, "Automatic step waits for full reading time")
advanceViewTime(0.02)
check(advances == 1, "Information automatically advances after reading")

local oldPosition, oldTarget = tutorialFrame.Position, actualView.target
local nextTarget = mockNode("TextButton", "Hint") nextTarget.Parent = screen
nextTarget.AbsolutePosition = roblox.Vector2.new(40, 30)
actualView.ui.hint = nextTarget
actualView:Show("Hint", "Press Hint.", nextTarget, false, true)
check(actualView.transitioning and actualView.frameTween.goal.Size == roblox.UDim2.fromScale(0, 0), "Changing steps first tweens Size to zero")
renderSignal:Fire()
check(tutorialFrame.Position == oldPosition and actualView.target == oldTarget and heading.Text == "Welcome", "Position, spotlight and text stay put while closing")
advanceViewTime(0.139)
check(tutorialFrame.Position == oldPosition, "Panel cannot move before shrink completes")
advanceViewTime(0.0011)
check(tutorialFrame.Size == roblox.UDim2.fromScale(0, 0) and actualView.target == nextTarget and heading.Text == "Hint", "Spotlight and content change only at zero size")
check(tutorialFrame.Position == oldPosition and actualView.frameTween.goal.Position == roblox.UDim2.fromScale(0.5, 0.2), "Hint tweens toward top center instead of jumping or covering the bulb")
local newPosition = tutorialFrame.Position
renderSignal:Fire()
check(tutorialFrame.Position == newPosition and actualView.frameTween.goal.Size == originalFrameSize, "Per-frame layout cannot override the active position tween")
advanceViewTime(0.23)
check(not actualView.transitioning and tutorialFrame.Size == originalFrameSize and tutorialFrame.Position == roblox.UDim2.fromScale(0.5,0.2), "Hint finishes at requested top-center position and authored size")
advanceViewTime(0.3)
check(nextTarget.Selectable and guiService.SelectedObject == nil, "Action step becomes selectable without assigning UI focus")
advanceViewTime(30)
check(advances == 1, "Action steps never advance on a timer")

actualView:Show("Old", "Read this.", playButton, true, false)
advanceViewTime(0.7)
check(tutorialFrame.Position == roblox.UDim2.fromScale(0.5, 0.862), "Tutorial returns to default position after Hint")
actualView:Show("New", "Press Hint.", nextTarget, false, true)
advanceViewTime(10)
check(advances == 1 and heading.Text == "New", "New step invalidates previous reading timer")
actualView:Show("Before Skip", "Read this.", playButton, true, false)
advanceViewTime(0.7)
skipButton.Activated:Fire()
advanceViewTime(10)
check(advances == 1 and not actualView.active, "Skip cancels pending read timer")

actualView = createView()
actualView:Show("First", "Hello", playButton, false, true)
advanceViewTime(0.5)
actualView:Show("Closing", "Read this.", nextTarget, true, false)
local closingTween = actualView.frameTween
skipButton.Activated:Fire()
advanceViewTime(10)
check(closingTween.cancelled and not actualView.active and not tutorialFrame.Visible and not actualView.root, "Skip during shrinking cancels transition and removes spotlight")
check(tutorialFrame.Size == originalFrameSize and tutorialFrame.Position == roblox.UDim2.fromScale(0.5, 0.862) and popScale.Scale == 1, "Skip restores authored size/scale and default bottom position")

actualView = createView()
actualView:Show("Opening", "Read this.", playButton, true, false)
local openingTween = actualView.frameTween
skipButton.Activated:Fire()
advanceViewTime(10)
check(openingTween.cancelled and not tutorialFrame.Visible and tutorialFrame.Size == originalFrameSize and advances == 1, "Skip during opening cannot later reopen or advance tutorial")

actualView = createView()
actualView:Show("First", "Old text", playButton, true, false)
local replacedTween = actualView.frameTween
actualView:Show("Replacement", "New text", nextTarget, false, true)
advanceViewTime(1)
check(replacedTween.cancelled and heading.Text == "Replacement" and not actualView.transitioning, "Rapid step replacement cancels stale tween callbacks")
actualView:Show("Talking", "Still typing", playButton, true, false)
advanceViewTime(0.37)
local activeBob = tweens[#tweens]
skipButton.Activated:Fire()
advanceViewTime(10)
check(activeBob.cancelled and icon.Position == originalIconPosition, "Skip cancels talking motion")
check(playButton.Selectable and #actualView.connections == 0, "Skip restores selectable controls and removes listeners")
check(not tutorialFrame.Visible and not actualView.typing and advances == 1, "Stale jobs cannot reopen tutorial")
local endings = 0
actualView = createView()
actualView:Show("Congrats!", "You finished the tutorial!", nil, false, false)
advanceViewTime(1)
local endingPosition = tutorialFrame.Position
check(actualView.target == nil and endingPosition == roblox.UDim2.fromScale(0.5, 0.862), "Final congratulations stay at the default position without a target")
for _, panel in ipairs(actualView.panels) do check(not panel.Visible, "Final congratulations leave Home undimmed") end
check(actualView.cover.Visible and actualView.cover.BackgroundTransparency == 1 and actualView.cover.Size == roblox.UDim2.fromScale(1, 1), "Final step uses only an invisible full-screen input blocker")
check(actualView:BlocksPointer(roblox.Vector2.new(500, 300)) and skipButton.Selectable, "Untargeted ending still blocks gameplay and permits Skip")
actualView:Collapse(function()
	check(tutorialFrame.Size == roblox.UDim2.fromScale(0, 0) and popScale.Scale == 0, "Final panel reaches zero before cleanup")
	endings += 1
	actualView:Close()
end)
check(actualView.transitioning and actualView.frameTween.goal.Size == roblox.UDim2.fromScale(0, 0), "Ending requests a shrink-to-zero tween")
advanceViewTime(0.13)
renderSignal:Fire()
check(endings == 0 and tutorialFrame.Visible and tutorialFrame.Position == endingPosition, "Ending remains visible in place while shrinking")
advanceViewTime(0.02)
check(endings == 1 and not tutorialFrame.Visible and not actualView.root, "Ending closes panel and spotlight after shrink")
advanceViewTime(10)
check(endings == 1, "Final callback runs once")
actualView = createView()
actualView:Show("Congrats!", "You finished the tutorial!", nil, false, false)
advanceViewTime(1)
actualView:Collapse(function() endings += 1 end)
skipButton.Activated:Fire()
advanceViewTime(10)
check(endings == 1 and not actualView.active and not tutorialFrame.Visible, "Skip during final shrink cancels late completion callback")
-- Rounded dimming stays in the padding, with no overlapping alpha or covered letters.
local opening = { 30, 40, 100, 70 }
local corners = view.CornerMask(opening, 16)
local function overlap(a,b)
	return a[1]<b[1]+b[3] and a[1]+a[3]>b[1] and a[2]<b[2]+b[4] and a[2]+a[4]>b[2]
end
local clearTarget, disjoint, bounded, soft = true, true, true, false
for i,piece in ipairs(corners) do
	clearTarget = clearTarget and not overlap(piece,{38,48,84,54})
	bounded = bounded and piece[1]>=30 and piece[2]>=40 and piece[1]+piece[3]<=130 and piece[2]+piece[4]<=110
		and piece[5]>0 and piece[5]<=1
	soft = soft or piece[5]<1
	for j=i+1,#corners do disjoint = disjoint and not overlap(piece,corners[j]) end
end
check(#corners>0 and clearTarget and bounded, "Curved corners stay inside the opening padding without covering the target")
check(disjoint and soft, "Curved edges blend coverage without darker overlapping strips")
check(#view.CornerMask({0,0,1,1},24)==0, "Tiny clipped openings cannot produce overlapping corners")
actualView = createView()
actualView:Show("Find", "CAT", playButton, false, true)
advanceViewTime(1)
check(#actualView.cornerPanels>0 and actualView.cornerPanels[1].Visible, "A highlighted target renders its rounded mask")
local count=#mockNodes
actualView:Layout()
check(#mockNodes==count, "Unchanged spotlight geometry reuses its corner objects")
actualView:Show("Congrats!", "Done", nil, false, false)
advanceViewTime(1)
local hidden=true
for _,panel in ipairs(actualView.cornerPanels) do hidden=hidden and not panel.Visible end
check(hidden and actualView.cover.Visible, "Congratulations hide all curved dimming while retaining the input blocker")
actualView:Close()

actualView=createView()
actualView:Show("Find", "CAT", playButton, false, true)
advanceViewTime(1)
actualView.maskDriver.Value=0.5
actualView.maskDriver.Changed:Fire(0.5)
local matching=true
for index,panel in ipairs(actualView.cornerPanels) do
	matching=matching and math.abs(panel.BackgroundTransparency-(1-0.68*0.5*actualView.cornerCoverage[index]))<0.00001
end
check(matching and math.abs(actualView.panels[1].BackgroundTransparency-0.66)<0.00001,"Main mask and curved edges share the same fading opacity")
actualView:Close()
local fade=screen:FindFirstChild("TutorialSpotlightFade")
local passive=fade~=nil and not fade.Active
if fade then for _,piece in ipairs(fade:GetDescendants()) do passive=passive and piece.ClassName=="Frame" and not piece.Active end end
check(passive and not actualView:BlocksPointer(roblox.Vector2.new(10,10)),"Skip immediately releases input while a passive spotlight copy fades away")
advanceViewTime(0.15)
check(not screen:FindFirstChild("TutorialSpotlightFade"),"Faded spotlight copy is removed after closing")

-- Passive pointer motion follows the actual cell geometry and never submits input.
do
 local guideView = createView()
 local grid = mockNode("Frame", "PracticeGrid") grid.Parent = screen
 grid.AbsolutePosition, grid.AbsoluteSize = roblox.Vector2.new(100, 120), roblox.Vector2.new(300,300)
 local path = {{row=1,column=1},{row=1,column=2},{row=2,column=2}}
 local dragging = false
 guideView:SetDragGuide(grid,path,3,3,function() return dragging end)
 local pointer = guideView.dragImage
 check(pointer.Image == "rbxassetid://130798161958633" and not pointer.Active and not pointer.Selectable, "Requested image is passive and cannot steal pointer or controller input")
 guideView:UpdateDragGuide(0.1)
 check(pointer.Visible and pointer.Position == roblox.UDim2.fromOffset(750,620), "Pointer starts at C with spotlight overscan offset accounted for")
 for _=1,10 do guideView:UpdateDragGuide(0.1) end
 check(math.abs(pointer.Position.X.Offset-850)<0.01 and pointer.Position.Y.Offset>620 and pointer.Position.Y.Offset<625, "Pointer reaches A before turning toward T")
 for _=1,7 do guideView:UpdateDragGuide(0.1) end
 check(pointer.Position == roblox.UDim2.fromOffset(850,720), "Pointer reaches T along the bending path")
 for _=1,8 do guideView:UpdateDragGuide(0.1) end
 check(not pointer.Visible, "Demonstration fades away before looping")
 dragging=true guideView:UpdateDragGuide(0.1)
 check(not pointer.Visible and guideView.dragGuide.elapsed==0, "Player drag hides and resets the demonstration")
 dragging=false guideView.typing=true guideView:UpdateDragGuide(0.1)
 check(not pointer.Visible, "Typing hides the demonstration")
 guideView.typing=false guideView.transitioning=true guideView:UpdateDragGuide(0.1)
 check(not pointer.Visible, "Step animation hides the demonstration")
 guideView.transitioning=false
 grid.AbsolutePosition, grid.AbsoluteSize = roblox.Vector2.new(10,20),roblox.Vector2.new(150,150)
 guideView:UpdateDragGuide(0.1)
 check(pointer.Position == roblox.UDim2.fromOffset(635,495) and pointer.Size==roblox.UDim2.fromOffset(27.5,27.5), "Resizing or moving the board keeps the pointer aligned and scaled")
 guideView.ui.game.Visible=false guideView:UpdateDragGuide(0.1)
 check(not pointer.Visible, "Pointer stops when Game is hidden")
 guideView:Show("Hint", "Tap the bulb.",nextTarget,false,true)
 check(pointer.destroyed and not guideView.dragImage and not guideView.dragGuide, "Changing steps destroys the old guide")
 guideView:SetDragGuide(grid,path,3,3)
 local closingPointer=guideView.dragImage
 guideView:Close()
 check(closingPointer.destroyed and not guideView.dragGuide, "Closing or skipping removes the pointer and animation state")
end

print("TUTORIAL_TESTS_PASSED=" .. checks)
