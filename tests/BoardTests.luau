require("./TestSupport")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rbx = require("@lune/roblox")
local checks = 0
local function check(value, reason) assert(value, reason) checks += 1 end
local function signal()
	local signalValue = { callbacks = {} }
	function signalValue:Connect(fn)
		table.insert(self.callbacks, fn)
		return { Disconnect = function() end }
	end
	return signalValue
end
local Node = {}
local meta = {
	__index = function(self, key)
		if Node[key] then return Node[key] end
		return self.props[key] or Node.FindFirstChild(self,key)
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			local old = self.props.Parent
			if old then table.remove(old.children, table.find(old.children, self)) end
			if value then table.insert(value.children, self) end
		end
		local previous = self.props[key]
		self.props[key] = value
		local changed = self.propertySignals[key]
		if changed and previous ~= value then
			for _, callback in ipairs(changed.callbacks) do callback() end
		end
	end,
}
local function instance(class)
	return setmetatable({ children = {}, propertySignals = {}, props = {
		ClassName = class, Name = class, ZIndex = 1, Visible = true,
		Position = rbx.UDim2.fromScale(0, 0), BackgroundColor3 = rbx.Color3.new(1, 1, 1), Scale = 1,
		MouseEnter = signal(), MouseLeave = signal(), MouseButton1Down = signal(), MouseButton1Up = signal(), Destroying = signal(),
		AbsolutePosition = rbx.Vector2.new(0, 0), AbsoluteSize = rbx.Vector2.new(600, 400),
		Activated = signal(), SelectionGained = signal(), Focused = signal(), FocusLost = signal(), Size = rbx.UDim2.fromScale(1, 1),
	} }, meta)
end
function Node:IsFocused() return self.props.focused == true end
function Node:GetChildren() return table.clone(self.children) end
function Node:GetDescendants()
	local result = {}
	for _, child in ipairs(self.children) do
		table.insert(result, child)
		for _, descendant in ipairs(child:GetDescendants()) do table.insert(result, descendant) end
	end
	return result
end
function Node:SetAttribute(name, value) self.props["Attribute_" .. name] = value end
function Node:GetAttribute(name) return self.props["Attribute_" .. name] end
function Node:FindFirstChild(name)
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
	return nil
end
function Node:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
function Node:FindFirstChildOfClass(class)
	for _, child in ipairs(self.children) do if child.ClassName == class then return child end end
end
function Node:IsA(class)
	return self.ClassName == class or (class == "GuiButton" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton")) or (class == "GuiObject" and table.find({ "Frame", "ImageLabel", "TextButton", "TextLabel", "ImageButton" }, self.ClassName) ~= nil)
end
function Node:GetPropertyChangedSignal(name)
	self.propertySignals[name] = self.propertySignals[name] or signal()
	return self.propertySignals[name]
end
function Node:Destroy()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent = nil
end
function Node:Clone()
	local cloned = instance(self.ClassName)
	for key, value in pairs(self.props) do
		if key ~= "Parent" and key ~= "Activated" and key ~= "SelectionGained" then cloned[key] = value end
	end
	for _, child in ipairs(self.children) do child:Clone().Parent = cloned end
	return cloned
end
local function add(root, class, name)
	local item = instance(class)
	item.Name, item.Parent = name, root
	return item
end
local assets = instance("Folder")
local exceedsTemplate = add(assets, "Frame", "Exceeds")
add(exceedsTemplate, "TextLabel", "TextLabel")
local template = add(assets, "Frame", "WordPanelTemplate")
add(template, "TextLabel", "Word")
add(template, "Frame", "BreakLine")
local foundPanel = add(template, "Frame", "FoundPanel")
add(foundPanel, "UIListLayout", "UIListLayout")
local playerTemplate = add(template, "ImageLabel", "PlayerTemplate")
add(playerTemplate, "UIStroke", "UIStroke")
local engine = require("../src/shared/puzzle/PuzzleEngine")
local function waitForChild(self, name) return assert(self[name], name) end
local config = require("../src/shared/config/ProgressionConfig")
local shared = { puzzle = { PuzzleEngine = engine, CrosswordInput=require("../src/shared/puzzle/CrosswordInput") }, ui = { WaitForChild = waitForChild },
	config = { ProgressionConfig = config, WaitForChild = waitForChild }, WaitForChild = waitForChild }
local storage = { WaitForChild = function(_, name) return name == "shared" and shared or assets end }
local players = { LocalPlayer = { UserId = 1, DisplayName = "Alice" },
	GetUserThumbnailAsync = function(_, userId) return "headshot:" .. userId end }
local focus = setmetatable({}, { __newindex = function(self, key, value)
	assert(key ~= "SelectedObject", "Game code must never set UI focus")
	rawset(self, key, value)
end })
local now, pending = 0, {}
local function delay(seconds, fn)
	table.insert(pending, { at = now + seconds, fn = fn })
end
local function advance(seconds)
	local target = now + seconds
	while true do
		table.sort(pending, function(a, b) return a.at < b.at end)
		if not pending[1] or pending[1].at > target then break end
		local item = table.remove(pending, 1)
		now = item.at
		item.fn()
	end
	now = target
end
local tweenService = { created = {} }
function tweenService:Create(node, info, properties)
	local cancelled = false
	local tween = { node = node, info = info, properties = properties,
		Play = function()
			delay(info.Time + info.DelayTime, function()
				if cancelled or not node.Parent then return end
				for key, value in pairs(properties) do node[key] = value end
			end)
		end,
		Cancel = function() cancelled = true end,
	}
	table.insert(self.created, tween)
	return tween
end
local services = { Players = players, ReplicatedStorage = storage, GuiService = focus, TweenService = tweenService,
	UserInputService = { GetLastInputType = function() return "Gamepad1" end } }
local environment = {
	game = { GetService = function(_, name) return services[name] end },
	require = function(value) return value end,
	Font = { new = function(family, weight, style) return { Family = family, Weight = weight, Style = style } end },
	Instance = { new = instance }, Vector2 = rbx.Vector2, Vector3 = rbx.Vector3, UDim2 = rbx.UDim2, UDim = rbx.UDim, Color3 = rbx.Color3,
	Random = { new = function()
		local index = 0
		return { NextNumber = function(_, minimum, maximum)
			index += 1
			minimum, maximum = minimum or 0, maximum or 1
			return minimum + (maximum - minimum) * ((index * 0.61803398875) % 1)
		end }
	end },
	ColorSequence = rbx.ColorSequence, Enum = rbx.Enum, task = { spawn = function(fn) fn() end, delay = delay },
	TweenInfo = { new = function(time, style, direction, repeats, reverses, delayTime) return { Time = time, DelayTime = delayTime or 0, RepeatCount = repeats, Reverses = reverses } end },
}
shared.ui.UIEffects = luau.load(fs.readFile("src/shared/ui/UIEffects.luau"), { environment = environment })()
local Board = luau.load(fs.readFile("src/client/controllers/BoardController.luau"), { environment = environment })()
local ui = { game = instance("Frame"), screenGui = { IgnoreGuiInset = true }, boardPanel = instance("Frame"),
	wordPanel = instance("Frame"), words = instance("TextLabel"), wordList = instance("ScrollingFrame"),
	title = instance("TextLabel"), subtitle = instance("TextLabel"), duel = instance("Frame"), timed = instance("Frame") }
ui.timed.Position = rbx.UDim2.new(0.47, 8, 0.11, -3)
local allowed, submissions, sounds = true, {}, {}
local board = Board.new(ui, {
	canInteract = function() return allowed end, playSound = function(name) table.insert(sounds, name) end,
	submit = function(word, answer) table.insert(submissions, { word = word, answer = answer }) return {success=true} end,
})
local Generator = require("../src/server/puzzle/PuzzleGenerator")
local private = Generator.Generate(Generator.BuildTutorialDefinition(51),51)
local puzzle = engine.PublicPuzzle(private)
local function countChildren(root,name)
    local count=0 for _,child in ipairs(root:GetChildren()) do if child.Name==name then count+=1 end end return count
end
board:Build(puzzle,"Standard")
check(not board:Interactive(),"Entrance locks typing")
advance(0.6)
check(board:Interactive(),"Entrance unlocks typing")
check(board.tiles[1][1].Text=="" and not board.tiles[2][2],"Blank playable cells and blocked squares render separately")
check(board.tiles[1][1]:FindFirstChild("Number").Text=="1","Shared starting cell has its clue number")
check(board.rows["1A"]:FindFirstChild("Word").Text:find("pet that says meow",1,true),"Clue text is visible before solving")
check(not board.rows["1A"]:FindFirstChild("Word").Text:find("CAT",1,true),"Unsolved answer is not printed in clue list")
check(board.keyboard:FindFirstChild("Key_CHECK") and board.keyboard:FindFirstChild("Key_Z"),"Touch/gamepad keyboard has every letter and Check")
board:Key("C") board:Key("A") board:Key("T")
check(board.editing:Answer()=="CAT" and #submissions==0,"Full answer waits for explicit Check")
board:Finish()
check(#submissions==1 and submissions[1].answer=="CAT" and submissions[1].word=="1A","Check sends entry ID and typed answer")
board:Progress({{userId=1,foundWords={},revealedAnswers={}},{userId=2,foundWords={["1A"]=true}}})
check(not board.found["1A"] and ui.words.Text=="0/3","Opponent does not solve local clue")
local row=board.rows["1A"]
check(row.FoundPanel:FindFirstChild("Finder_2")~=nil,"Opponent finder portrait remains supported")
board:Progress({{userId=1,foundWords={["1A"]=true},revealedAnswers={["1A"]="CAT"},score=300}})
check(board.editing.locked["1:1"]=="C" and board.editing.selected=="1D","Accepted answer locks crossing and advances clue")
local soundCount=#sounds
board:Progress({{userId=1,foundWords={["1A"]=true},revealedAnswers={["1A"]="CAT"},score=300}})
check(#sounds==soundCount,"Repeated progress does not replay success")
board:Key("A") board:Key("R")
check(board.editing:Answer()=="CAR","Typing skips locked crossing")
board:Progress({{userId=1,foundWords={["1A"]=true},hintedWords={["1D"]=true},revealedAnswers={["1A"]="CAT",["1D"]="CAR"}}})
check(board.editing.locked["3:1"]=="R" and not board.found["1D"],"Hint reveals letters but does not complete entry")
board:Reject("1D")
check(board.feedback and sounds[#sounds]=="Error2","Server rejection shows feedback")
allowed=false
local prior=board.editing:Answer() board:Key("Z")
check(board.editing:Answer()==prior,"Modal/transition lock blocks typing")
allowed=true
board:Build(puzzle,"Duel") advance(0.6)
check(ui.timed.Position==rbx.UDim2.fromScale(0.5,0.03),"Duel timer moves to authored Duel slot")
board:Build(puzzle,"Standard") advance(0.6)
check(ui.timed.Position==rbx.UDim2.new(0.47,8,0.11,-3),"Other modes restore timer including offsets")
local box=board.keyboard:FindFirstChild("TypeAnswer")
box.focused=true
for _,fn in ipairs(box.Focused.callbacks) do fn() end
box.Text="cat"
check(board.editing:Answer()=="CAT","User-focused native keyboard fills the selected entry")
local beforeNative=#submissions
box.focused=false
for _,fn in ipairs(box.FocusLost.callbacks) do fn(true) end
check(#submissions==beforeNative+1,"Native keyboard Enter submits the full answer")
local ownPortraitColor=board:PortraitColor(1)
local input={UserInputType="MouseButton1"}
local Interface = luau.load(fs.readFile("src/client/controllers/InterfaceController.luau"), { environment = environment })();
(function()
	local panel = add(assets, "Frame", "TimedModeTest")
	local label = add(panel, "TextLabel", "TimeLeft")
	local icon = add(panel, "ImageLabel", "Icon")
	icon.Image = "authored-timer-icon"
	local timerUi = { timedTimeLeft = label }
	Interface.UpdateTimedTimer(timerUi, nil, nil)
	check(label.Text == "--:--", "Unconnected timer clears stale time")
	Interface.UpdateTimedTimer(timerUi, 120, 120)
	check(label.Text == "02:00", "Text-only timer formats minutes and seconds")
	Interface.UpdateTimedTimer(timerUi, 59.2, 120)
	check(label.Text == "01:00", "Timer rounds remaining partial seconds upward")
	Interface.UpdateTimedTimer(timerUi, 30, 120)
	check(label.Text == "00:30", "Text-only timer updates without a FillBar")
	Interface.UpdateTimedTimer(timerUi, 0, 120)
	check(label.Text == "00:00", "Expired time displays zero")
	Interface.UpdateTimedTimer(timerUi, -5, 120)
	check(label.Text == "00:00", "Negative remaining time cannot display a negative countdown")
	Interface.UpdateTimedTimer(timerUi, nil, nil)
	check(label.Text == "--:--" and icon.Image == "authored-timer-icon" and not panel:FindFirstChild("FillBar"), "Reset preserves the authored icon and never generates a timer bar")
	Interface.UpdateTimedTimer(timerUi, 30, 0)
	check(label.Text == "--:--", "Invalid duration cannot start a fake timer")
	Interface.UpdateTimedTimer({}, 30, 60)
end)()

local bars = { home = instance("Frame"), game = instance("Frame") }
local function createLevelBar(parent)
	local root = add(parent, "Frame", "LevelBar")
	add(root, "TextLabel", "XP")
	add(add(root, "ImageLabel", "Star"), "TextLabel", "Level")
	add(add(root, "Frame", "FillBar"), "Frame", "Fill").BackgroundColor3 = rbx.Color3.fromRGB(75, 205, 132)
	return root
end
local homeBar, gameBar = createLevelBar(bars.home), createLevelBar(bars.game)
for _, name in ipairs({ "NextLevelTitle", "NextLevelRewardTitle" }) do add(gameBar, "TextLabel", name).Visible = false end
local rewardIcon = add(gameBar, "ImageLabel", "NextLevelRewardIcon")
rewardIcon.Visible, rewardIcon.Image = false, "authored-hint-icon"
Interface.UpdateLevelBars(bars, { level = 1, xp = 0, xpToNextLevel = 500 })
check(gameBar:FindFirstChild("NextLevelTitle").Text == "LEVEL 2 REWARD" and gameBar:FindFirstChild("NextLevelRewardTitle").Text == "+1 Hint", "Game bar previews the reduced one-hint reward for level 2")
check(not rewardIcon.Visible and rewardIcon.Image == "authored-hint-icon", "Simplified Game bar hides retired reward decorations")
Interface.UpdateLevelBars(bars, { level = 2, xp = 300, xpToNextLevel = 600, nextLevelRewardHints = 1 })
check(not gameBar:FindFirstChild("NextLevelTitle").Visible and gameBar:FindFirstChild("NextLevelTitle").Text == "LEVEL 4 REWARD" and gameBar:FindFirstChild("NextLevelRewardTitle").Text == "+1 Hint", "Reward preview updates after leveling up")
advance(0.36)
for _, root in ipairs({ homeBar, gameBar }) do
	local fill = root:FindFirstChild("FillBar"):FindFirstChild("Fill")
	check(fill.Size == rbx.UDim2.fromScale(1, 1) and fill.BackgroundColor3 == rbx.Color3.fromRGB(255, 211, 92), "Both level bars complete the final stretch in gold")
end
advance(0.52)
for _, root in ipairs({ homeBar, gameBar }) do
	local fill = root:FindFirstChild("FillBar"):FindFirstChild("Fill")
	check(fill.Size == rbx.UDim2.fromScale(0.1, 1) and fill.BackgroundColor3 == rbx.Color3.fromRGB(75, 205, 132), "Both gold bars reset to minimum and authored green before leftover XP")
end
advance(0.51)
check(homeBar:FindFirstChild("XP").Text == "300 / 600 XP" and gameBar:FindFirstChild("XP").Text == "300 / 600 XP", "Both XP bars show the increasing requirement")
check(gameBar:FindFirstChild("FillBar"):FindFirstChild("Fill").Size.X.Scale == 0.5, "XP bar fill uses the current requirement")
-- New XP and additional crossed levels must not interrupt the gold/reset sequence.
local liveBars = { home = instance("Frame"), game = instance("Frame") }
local liveHome, liveGame = createLevelBar(liveBars.home), createLevelBar(liveBars.game)
add(liveGame, "TextLabel", "NextLevelRewardTitle")
Interface.UpdateLevelBars(liveBars, { level = 8, xp = 100, xpToNextLevel = 1200 })
advance(0.51)
check(not liveBars.levelBarFeedback[liveGame].celebrating, "Initial loaded level does not replay old level-ups")
Interface.UpdateLevelBars(liveBars, { level = 9, xp = 0, xpToNextLevel = 1300 })
check(not liveGame:FindFirstChild("NextLevelRewardTitle").Visible and liveGame:FindFirstChild("NextLevelRewardTitle").Text == "+1 Hint", "Simplified Game bar keeps the old reward label hidden")
local celebration = liveBars.levelBarFeedback[liveGame]
advance(0.2)
Interface.UpdateLevelBars(liveBars, { level = 10, xp = 700, xpToNextLevel = 1400 })
check(liveGame:FindFirstChild("NextLevelRewardTitle").Text == "+1 Hint", "Reward preview stays at one hint per even level")
check(liveBars.levelBarFeedback[liveGame] == celebration and celebration.celebrating, "XP and another level during gold update the destination without restarting")
advance(0.7)
check(liveGame:FindFirstChild("FillBar"):FindFirstChild("Fill").Size == rbx.UDim2.fromScale(0.1, 1), "Coalesced level gains still pass through the minimum fill")
advance(0.51)
check(liveGame:FindFirstChild("FillBar"):FindFirstChild("Fill").Size.X.Scale == 0.5, "Gold sequence finishes at the latest XP fraction")
Interface.UpdateLevelBars(liveBars, { level = 11, xp = 100, xpToNextLevel = 1500 })
advance(0.2)
Interface.UpdateLevelBars(liveBars, { level = 1, xp = 200, xpToNextLevel = 500 })
advance(1.5)
local liveFill = liveGame:FindFirstChild("FillBar"):FindFirstChild("Fill")
check(math.abs(liveFill.Size.X.Scale - 0.4) < 0.00001 and liveFill.BackgroundColor3 == rbx.Color3.fromRGB(75, 205, 132), "Cancelled gold callbacks cannot overwrite a replacement progression state")

-- Authored queue hierarchy and reusable roster cards.
local queueTemplate=add(assets,"Frame","PlayerTemplate")
queueTemplate.Visible=false
add(queueTemplate,"TextLabel","Title")
add(queueTemplate,"ImageLabel","YouMugshot")
add(add(queueTemplate,"ImageLabel","Star"),"TextLabel","Level")
add(queueTemplate:FindFirstChild("YouMugshot"),"UIStroke","UIStroke")
local hud=instance("ScreenGui")
local home=add(hud,"Frame","Home")
local gameFrame=add(hud,"Frame","Game")
local tutorialPanel=add(hud,"Frame","Tutorial")
local standard=add(add(home,"Frame","Gamemodes"),"Frame","Standard")
 ;(function()
 local modes = standard.Parent
 for _, entry in ipairs({{standard,25},{add(modes,"Frame","Mini"),9},{add(modes,"Frame","Jumbo"),9}}) do
  local frame = add(add(entry[1],"Frame","CanvasGroup"),"Frame","Frame1")
  for index=1,entry[2] do add(frame,"Frame","tile"..index) end
  if entry[1].Name == "Jumbo" then
   local grid = add(frame,"UIGridLayout","UIGridLayout")
   grid.CellSize, grid.CellPadding = rbx.UDim2.fromScale(0.3,0.3), rbx.UDim2.fromScale(0.03,0.03)
   grid.FillDirection, grid.FillDirectionMaxCells, grid.SortOrder = rbx.Enum.FillDirection.Horizontal,0,rbx.Enum.SortOrder.Name
  end
 end
end)()
add(standard,"TextButton","Play")
add(standard,"TextLabel","Waiting")
add(home,"Frame","ButtonBar")
local boardPanel=add(gameFrame,"Frame","BoardPanel")
local wordsPanel=add(gameFrame,"Frame","WordPanel")
add(wordsPanel,"TextLabel","Words")
add(add(wordsPanel,"Frame","Container"),"ScrollingFrame","ScrollingFrame")
add(gameFrame,"TextButton","Hint")
local scorePanel=add(gameFrame,"Frame","Score")
add(scorePanel,"TextLabel","Score")
add(add(scorePanel,"Frame","Level"),"TextLabel","Label")
local levelPanel=add(gameFrame,"Frame","LevelBar")
local levelScale=add(levelPanel,"UIScale","AuthoredScale") levelScale.Scale=0.85
local background=add(gameFrame,"ImageLabel","Background")
local hiddenMode=add(gameFrame,"Frame","TimedMode") hiddenMode.Visible=false
local queuePanel=add(hud,"Frame","Queue")
local container=add(queuePanel,"Frame","Container")
local layout=add(container,"UIGridLayout","UIGridLayout")
local aspect=add(container,"UIAspectRatioConstraint","UIAspectRatioConstraint")
add(queuePanel,"TextButton","Exit")
add(queuePanel,"TextLabel","Subtitle")
local bindings=Interface.Bind(hud)
check(#bindings.homeTilePreviews == 3, "Home binds Standard, Mini and Jumbo authored preview grids")
check(not bindings.exit and not bindings.title and not bindings.subtitle, "Current Game binds without retired Exit, Title or Subtitle children")
check(bindings.queue==queuePanel and not hud:FindFirstChild("StandardQueue"), "Uses authored Queue without generating a replacement")
check(not tutorialPanel.Visible and not queuePanel.Visible, "Renamed Tutorial and Queue start hidden")
check(bindings.queueLeave==queuePanel:FindFirstChild("Exit"), "Queue uses authored Exit")
Interface.UpdateQueue(bindings, {{userId=1,displayName="Alice",name="A",level=7},{userId=2,displayName="Bob",name="B",level=12}})
local alice=bindings.queueEntries[1]
local queuePortrait=alice:FindFirstChild("YouMugshot")
local queueColor=queuePortrait.BackgroundColor3
local _, queueSaturation, queueValue=queueColor:ToHSV()
check(queueSaturation>=0.75 and queueSaturation<=0.85 and queueValue>=0.85 and queueValue<=0.95, "Queue portrait uses about 80 percent saturation")
check(queuePortrait:FindFirstChildOfClass("UIStroke").Color==queueColor:Lerp(rbx.Color3.new(),0.3), "Queue portrait keeps its darker matching stroke")
check(alice.Visible and alice:FindFirstChild("Title").Text=="Alice" and alice:FindFirstChild("YouMugshot").Image=="headshot:1", "Queue template shows name and headshot")
check(alice:FindFirstChild("Star"):FindFirstChild("Level").Text=="7" and bindings.queueEntries[2].LayoutOrder==2, "Queue cards show levels in join order")
Interface.UpdateQueue(bindings, {{userId=1,displayName="Alice",level=8}})
check(queuePortrait.BackgroundColor3==queueColor, "Queue roster updates retain chosen portrait color")
check(bindings.queueEntries[1]==alice and bindings.queueEntries[2]==nil and #container:GetChildren()==3, "Roster updates reuse cards and remove departures")
check(alice:FindFirstChild("Star"):FindFirstChild("Level").Text=="8", "Repeated roster refreshes level")
Interface.UpdateQueueTimer(bindings, 14.2)
check(bindings.queueSubtitle.Text=="Standard Mode (15s)", "Countdown uses Standard Mode label and ceiling")
Interface.UpdateQueueTimer(bindings, -1)
check(bindings.queueSubtitle.Text=="Standard Mode (0s)", "Countdown never becomes negative")
Interface.UpdateQueue(bindings, {})
check(#container:GetChildren()==2 and layout.Parent==container and aspect.Parent==container and not queueTemplate.Visible, "Queue cleanup preserves authored layout and source template")

local jobs={}
local spawn=environment.task.spawn
environment.task.spawn=function(fn) table.insert(jobs,fn) end
Interface.UpdateQueue(bindings, {{userId=9,displayName="Old",level=3}})
local oldPortrait=bindings.queueEntries[9]:FindFirstChild("YouMugshot")
Interface.UpdateQueue(bindings, {})
Interface.UpdateQueue(bindings, {{userId=9,displayName="New",level=4}})
local newPortrait=bindings.queueEntries[9]:FindFirstChild("YouMugshot")
jobs[1]()
check(oldPortrait.Image=="" and newPortrait.Image=="", "Late thumbnail cannot populate removed/replaced card")
jobs[2]()
check(newPortrait.Image=="headshot:9", "Current card receives its thumbnail")
environment.task.spawn=spawn
Interface.UpdateQueue(bindings, {})
Interface.UpdateQueue(bindings, {{userId=-1000000000,isBot=true,thumbnailImage="bot-avatar",displayName="PixelPanda",level=12}})
local botCard = bindings.queueEntries[-1000000000]
check(botCard:FindFirstChild("YouMugshot").Image == "bot-avatar" and botCard:FindFirstChild("Title").Text == "PixelPanda", "Queue bot uses its generated name and resolved Roblox headshot")
Interface.UpdateQueue(bindings, {})
check(bindings.queueEntries[-1000000000] == nil, "Bot removal cleans up the queue card")

-- White transition and authored game geometry restoration, including cancellation.
local originalPositions={}
for _, child in ipairs(gameFrame:GetChildren()) do
	child.Position=rbx.UDim2.fromScale(0.4,0.5)
	originalPositions[child]=child.Position
end
local covered,completed=0,0
queuePanel.Visible,gameFrame.Visible=true,false
local effects=shared.ui.UIEffects
local function onCovered()
	check(hud:FindFirstChild("GameTransition").BackgroundTransparency==0, "Switch occurs at full white")
	covered+=1
	queuePanel.Visible,gameFrame.Visible=false,true
	return gameFrame
end
local cancel=effects.TransitionToGame(hud,onCovered,function(ok) check(ok,"Transition succeeds") completed+=1 end)
local overlay=hud:FindFirstChild("GameTransition")
check(overlay.Active and overlay.ZIndex>gameFrame.ZIndex and overlay.Size.X.Scale==2, "White overlay covers inset edges and blocks pointers")
advance(0.69)
check(covered==0 and queuePanel.Visible and not gameFrame.Visible, "Queue remains visible before full white")
advance(0.02)
check(covered==1 and gameFrame.Visible and boardPanel.Position~=originalPositions[boardPanel], "Board slides into position as white recedes")
check(gameFrame:FindFirstChild("Hint"):FindFirstChildOfClass("UIScale").Scale==0, "Hint enters from zero scale")
check(levelScale.Scale<0.85 and background.Position==originalPositions[background] and hiddenMode.Visible, "Entrance respects authored scales and background while showing the timer")
advance(0.91)
check(completed==1 and not hud:FindFirstChild("GameTransition") and boardPanel.Position==originalPositions[boardPanel], "Transition finishes at exact authored position")
check(levelScale.Parent==levelPanel and levelScale.Scale==0.85 and not boardPanel:FindFirstChild("GameEntranceScale"), "Temporary scales removed and authored scale restored")
cancel()
check(completed==1,"Completed transition cannot finish twice")
local early=effects.TransitionToGame(hud,onCovered,function() completed+=1 end)
early()
advance(2)
check(covered==1 and completed==1 and not hud:FindFirstChild("GameTransition"), "Cancelling before white prevents stale screen switch")
local late=effects.TransitionToGame(hud,onCovered,function() completed+=1 end)
advance(0.71)
late()
check(boardPanel.Position==originalPositions[boardPanel] and levelScale.Scale==0.85, "Cancellation during reveal restores layout")
advance(2)
check(covered==2 and completed==1 and not hud:FindFirstChild("GameTransition"), "Cancelled animations stay cancelled")
local failed=0
effects.TransitionToGame(hud,function() error("test mount failure") end,function(ok) if not ok then failed+=1 end end)
advance(2)
check(failed==1 and not hud:FindFirstChild("GameTransition"), "Failed mount removes white input blocker and reports failure")
-- Reverse the exact game poses before Home replaces them under white.
local homeCovered,homeCompleted=0,0
local function coverHome()
	check(hud:FindFirstChild("GameTransition").BackgroundTransparency==0, "Home switch occurs at full white")
	homeCovered+=1
	check(boardPanel.Position~=originalPositions[boardPanel] and gameFrame:FindFirstChild("Hint"):FindFirstChildOfClass("UIScale").Scale==0, "Outgoing elements stay collapsed until Home mounts")
	gameFrame.Visible,home.Visible=false,true
	return home
end
home.Visible,gameFrame.Visible=false,true
local exitCancel=effects.TransitionToHome(hud,gameFrame,coverHome,function(ok) check(ok,"Exit succeeds") homeCompleted+=1 end)
advance(0.66)
check(gameFrame.Visible and not home.Visible and gameFrame:FindFirstChild("Hint"):FindFirstChildOfClass("UIScale").Scale==0, "Hint shrinks during the reverse transition without an Exit button")
check(boardPanel.Position==originalPositions[boardPanel], "Board leaves after controls in reversed stagger")
advance(0.19)
check(homeCovered==0 and gameFrame.Visible and boardPanel.Position~=originalPositions[boardPanel], "Game reverses before screen switches")
check(levelScale.Scale<0.85 and background.Position==originalPositions[background] and hiddenMode.Visible, "Exit preserves background and hidden mode geometry")
advance(0.06)
check(homeCovered==1 and home.Visible and not gameFrame.Visible and homeCompleted==0, "Home reveals while white still blocks input")
check(boardPanel.Position==originalPositions[boardPanel] and levelScale.Scale==0.85 and not boardPanel:FindFirstChild("GameEntranceScale"), "Exit restores authored layout after switching screens")
advance(0.81)
check(homeCompleted==1 and not hud:FindFirstChild("GameTransition"), "Exit finishes and removes white input blocker")
exitCancel()
check(homeCompleted==1, "Completed exit cannot finish twice")

home.Visible,gameFrame.Visible=false,true
local cancelledExit=effects.TransitionToHome(hud,gameFrame,coverHome,function() homeCompleted+=1 end)
advance(0.85)
cancelledExit()
check(boardPanel.Position==originalPositions[boardPanel] and levelScale.Scale==0.85 and not boardPanel:FindFirstChild("GameEntranceScale"), "Cancelling reversed motion restores exact game geometry")
advance(2)
check(homeCovered==1 and homeCompleted==1 and gameFrame.Visible and not hud:FindFirstChild("GameTransition"), "Cancelled exit cannot switch Home later")
local cancelledUnfade=effects.TransitionToHome(hud,gameFrame,coverHome,function() homeCompleted+=1 end)
advance(0.91)
cancelledUnfade()
advance(2)
check(homeCovered==2 and homeCompleted==1 and not hud:FindFirstChild("GameTransition"), "Cancelling Home unfade cannot invoke late completion")

effects.TransitionToHome(hud,gameFrame,function() error("test Home mount failure") end,function(ok) if not ok then failed+=1 end end)
advance(2)
check(failed==2 and not hud:FindFirstChild("GameTransition") and boardPanel.Position==originalPositions[boardPanel] and levelScale.Scale==0.85, "Failed Home switch cleans overlay and restores geometry")
local queueCovered=false
effects.TransitionToHome(hud,nil,function() queueCovered=true return home end)
advance(0.69)
check(not queueCovered, "Queue exit waits for full white")
advance(0.02)
check(queueCovered, "Queue exit uses white fade without a game panel animation")
advance(0.81)
check(not hud:FindFirstChild("GameTransition"), "Queue exit removes the white overlay")
board:Build(puzzle, "Standard")
local crowd = { { userId = 1, foundWords = {} } }
local function checkFinders(expectedCount, expectedExtra)
	board:Progress(crowd)
	local panel = board.rows["1A"]:FindFirstChild("FoundPanel")
	local count = 0
	for _, child in ipairs(panel:GetChildren()) do
		if child.Name:sub(1, 7) == "Finder_" then count += 1 end
	end
	check(count == expectedCount, "Finder portraits never exceed three")
	local extra = panel:FindFirstChild("Exceeds")
	check(expectedExtra == 0 and extra == nil or expectedExtra > 0 and extra and extra:FindFirstChild("TextLabel").Text == "+" .. expectedExtra, "Exceeds shows the exact additional finder count")
	check(ui.words.Text == "0/3", "Overflow finders do not solve the local word")
	return extra
end
checkFinders(0, 0)
for id = 2, 13 do
	table.insert(crowd, {userId = id, foundWords = {["1A"] = true}, isBot = id % 2 == 0, thumbnailImage = "test-avatar"})
	checkFinders(math.min(id - 1, 3), math.max(0, id - 4))
end
local overflow = checkFinders(3, 9)
check(checkFinders(3, 9) == overflow, "Repeated snapshots reuse the Exceeds clone")
while #crowd > 1 do
	table.remove(crowd)
	checkFinders(math.min(#crowd - 1, 3), math.max(0, #crowd - 4))
end
local finishers = {
	{userId = 1, foundWords = {["1A"] = true, ["1D"] = true}, foundOrder = {["1A"] = 40, ["1D"] = 5}},
	{userId = 2, foundWords = {["1A"] = true, ["1D"] = true}, foundOrder = {["1A"] = 30, ["1D"] = 15}},
	{userId = 3, foundWords = {["1A"] = true, ["1D"] = true}, foundOrder = {["1A"] = 10, ["1D"] = 25}},
	{userId = 4, foundWords = {["1A"] = true, ["1D"] = true}, foundOrder = {["1A"] = 20, ["1D"] = 35}},
}
board:Progress(finishers)
local catPanel, dogPanel = board.rows["1A"]:FindFirstChild("FoundPanel"), board.rows["1D"]:FindFirstChild("FoundPanel")
check(catPanel:FindFirstChild("Finder_3").LayoutOrder == 1 and catPanel:FindFirstChild("Finder_4").LayoutOrder == 2 and catPanel:FindFirstChild("Finder_2").LayoutOrder == 3 and not catPanel:FindFirstChild("Finder_1"), "CAT shows its earliest three solvers, even when local player is fourth")
check(dogPanel:FindFirstChild("Finder_1").LayoutOrder == 1 and dogPanel:FindFirstChild("Finder_2").LayoutOrder == 2 and dogPanel:FindFirstChild("Finder_3").LayoutOrder == 3, "DOG has a different chronological portrait order")
check(catPanel:FindFirstChild("Exceeds").LayoutOrder == 4 and catPanel:FindFirstChild("Exceeds"):FindFirstChild("TextLabel").Text == "+1", "Overflow follows the first three solvers")
board:Progress({finishers[4], finishers[3], finishers[2], finishers[1]})
check(catPanel:FindFirstChild("Finder_3").LayoutOrder == 1 and catPanel:FindFirstChild("Finder_4").LayoutOrder == 2, "Roster reordering cannot change solve order")
board:Progress({finishers[1], finishers[2], finishers[4]})
check(catPanel:FindFirstChild("Finder_4").LayoutOrder == 1 and catPanel:FindFirstChild("Finder_2").LayoutOrder == 2 and catPanel:FindFirstChild("Finder_1").LayoutOrder == 3 and not catPanel:FindFirstChild("Exceeds"), "Departure promotes the next chronological solver out of overflow")
local palette = effects.NewPortraitPalette(environment.Random.new())
local seen, lastColor = {}, nil
for _ = 1, 30 do
	local colour = palette.Next()
	check(not seen[tostring(colour)], "All 30 palette colours are unique before a repeat")
	seen[tostring(colour)] = true
	local _, s, v = colour:ToHSV()
	check(s >= 0.75 and s <= 0.85 and v >= 0.85 and v <= 0.95, "Expanded palette retains the authored saturation and brightness range")
	lastColor = colour
end
check(palette.Next() ~= lastColor, "Shuffling the next deck cannot immediately repeat the last colour")
local avatar = add(assets, "ImageLabel", "AvatarTest")
avatar.ImageTransparency = 1
local profilePlaceholder = add(avatar, "ImageLabel", "Profile")
effects.SetPortraitImage(avatar, "verified-avatar")
check(avatar.Image == "verified-avatar" and avatar.ImageTransparency == 0 and not profilePlaceholder.Visible, "Verified portraits are opaque and hide the authored Profile overlay")
effects.SetPortraitImage(avatar, "rbxthumb://type=AvatarHeadShot&id=36149989&w=150&h=150")
check(avatar.Image == "verified-avatar", "Known blank portrait cannot replace the displayed usable headshot")
avatar.Image = "rbxthumb://type=AvatarHeadShot&id=36149989&w=150&h=150"
effects.SetPortraitImage(avatar, avatar.Image)
check(avatar.Image == "", "Stale authored blank headshot is cleared rather than retained")

local menuGui = add(assets, "ScreenGui", "MenuTest")
local homeTest = add(menuGui, "Frame", "Home")
local menuIcon = add(homeTest, "ImageLabel", "GameIcon")
menuIcon.Position = rbx.UDim2.fromScale(0.5, 0.2)
local modeGroup = add(homeTest, "Frame", "Gamemodes")
modeGroup.Position = rbx.UDim2.fromScale(0.5, 0.6)
local authoredScale = add(modeGroup, "UIScale", "AuthoredScale")
authoredScale.Scale = 0.85
local menuPattern = add(homeTest, "ImageLabel", "Pattern")
local iconPosition, modesPosition, patternPosition = menuIcon.Position, modeGroup.Position, menuPattern.Position
local cancelMenu = effects.RevealHome(homeTest)
check(menuIcon.Position ~= iconPosition and authoredScale.Scale < 0.85, "Home enters with displaced and shrunken contents")
check(menuPattern.Position == patternPosition and not menuPattern:FindFirstChildOfClass("UIScale"), "Home effects leave the pattern out of panel movement")
advance(0.8)
check(menuIcon.Position == iconPosition and authoredScale.Scale == 0.85 and not menuIcon:FindFirstChild("MenuEntranceScale"), "Home settles to its authored positions and scales")
cancelMenu()
cancelMenu = effects.RevealHome(homeTest)
cancelMenu()
menuIcon.Position = rbx.UDim2.fromScale(0.2, 0.3)
advance(1)
check(menuIcon.Position == rbx.UDim2.fromScale(0.2, 0.3) and modeGroup.Position == modesPosition, "Cancelled Home animation cannot overwrite a later layout")
menuIcon.Position = iconPosition
local queueTest = add(menuGui, "Frame", "Queue")
queueTest.Visible = false
add(queueTest, "Frame", "Container")
local queueFinished = false
effects.TransitionToQueue(menuGui, function() homeTest.Visible, queueTest.Visible = false, true return queueTest end, function(ok) queueFinished = ok end)
advance(0.69)
check(homeTest.Visible and menuIcon.Position ~= iconPosition and not queueTest.Visible, "Home shrinks and moves before the Queue switch")
advance(0.02)
check(queueTest.Visible and not homeTest.Visible and menuIcon.Position == iconPosition, "Hidden Home geometry restores under white")
advance(0.81)
check(queueFinished and not menuGui:FindFirstChild("GameTransition"), "Queue reveal releases input only after white clears")
local feedback = add(assets, "TextButton", "FeedbackTest")
local feedbackScale = add(feedback, "UIScale", "AuthoredScale")
feedbackScale.Scale = 0.8
effects.Init(feedback)
for _, fn in ipairs(feedback.Activated.callbacks) do fn() end
advance(0.31)
check(feedbackScale.Scale == 0.8 and not feedback:FindFirstChildOfClass("UIStroke"), "Cross-device button pulse restores its authored scale without adding a click stroke")
-- Repeated effects preserve authored geometry and clean up their temporary objects.
effects.Pulse(feedback, 1.1)
advance(0.1)
effects.Pulse(feedback, 1.1)
advance(0.31)
check(feedbackScale.Scale == 0.8, "Overlapping pulses restore the original non-unit authored scale")
local quietAccent = add(assets, "Frame", "QuietAccent")
effects.Pulse(quietAccent)
advance(0.31)
check(not quietAccent:FindFirstChildOfClass("UIScale"), "A transient pulse removes its temporary scale")
effects.SoftHighlight(quietAccent, rbx.Color3.new(1, 1, 1))
advance(0.1)
effects.SoftHighlight(quietAccent, rbx.Color3.new(0, 1, 1))
check(#quietAccent:GetChildren() == 1, "Rapid accents reuse one border without stacking")
advance(0.8)
check(#quietAccent:GetChildren() == 0, "A transient accent removes its border")
local authoredBorder = add(quietAccent, "UIStroke", "AuthoredBorder")
authoredBorder.Color, authoredBorder.Transparency, authoredBorder.Thickness = rbx.Color3.new(0.2, 0.3, 0.4), 0.2, 3
local borderColor = authoredBorder.Color
effects.SoftHighlight(quietAccent, rbx.Color3.new(1, 1, 1))
advance(0.8)
check(authoredBorder.Parent == quietAccent and authoredBorder.Color == borderColor and authoredBorder.Transparency == 0.2 and authoredBorder.Thickness == 3, "Accents restore the authored border exactly")
local fillState = bars.levelBarFeedback[gameBar]
Interface.UpdateLevelBars(bars, { level = 2, xp = 300, xpToNextLevel = 600, nextLevelRewardHints = 1 })
check(bars.levelBarFeedback[gameBar] == fillState, "Identical snapshots do not restart XP feedback")

-- Resolve requests after a portrait has been reused or removed.
local immediateSpawn = environment.task.spawn
local headshotJobs = {}
environment.task.spawn = function(fn) table.insert(headshotJobs, fn) end
local reusedPortrait = add(ui.duel, "ImageLabel", "ReusedPortrait")
Board.Portrait(reusedPortrait, 99001)
Board.Portrait(reusedPortrait, 99002)
local latestImage = reusedPortrait.Image
headshotJobs[1]()
check(reusedPortrait.Image == latestImage, "Old headshot request cannot overwrite a reused portrait")
headshotJobs[2]()
check(reusedPortrait.Image == "headshot:99002", "Latest headshot request still resolves")
Board.Portrait(reusedPortrait, 99003)
local removedImage = reusedPortrait.Image
reusedPortrait:Destroy()
headshotJobs[3]()
check(reusedPortrait.Image == removedImage, "Removed portrait ignores its delayed headshot")
environment.task.spawn = immediateSpawn

-- The new authored modal root owns the animation; Shop.Frame is only its card container.
function Node:FindFirstChildWhichIsA(class, recursive)
	for _, child in ipairs(recursive and self:GetDescendants() or self:GetChildren()) do
		if child:IsA(class) then return child end
	end
end
local plainFindChild = Node.FindFirstChild
function Node:FindFirstChild(name, recursive)
	local direct = plainFindChild(self, name)
	if direct or not recursive then return direct end
	for _, child in ipairs(self:GetDescendants()) do if child.Name == name then return child end end
end
local prompts, productRequests = {}, {}
local products = { [3573028342] = 19, [3573028459] = 49, [3711566945] = 89 }
services.MarketplaceService = {
	GetProductInfo = function(_, id) table.insert(productRequests, id) return { PriceInRobux = assert(products[id]) } end,
	PromptProductPurchase = function(_, _, id) table.insert(prompts, id) end,
}
storage.FindFirstChild = function() return nil end
shared.config.GameConfig = require("../src/shared/config/GameConfig")
shared.network = { NetworkContract = require("../src/shared/network/NetworkContract"), WaitForChild = waitForChild }
environment.script = { Parent = { InterfaceController = Interface, WaitForChild = waitForChild } }
environment.task.defer = function(fn) delay(0, fn) end
local groupPrompts, groupPromptFailed, groupPromptReentry = {}, false, nil
services.GroupService = {
	GetGroupInfoAsync = function() error("Okay must not depend on a group-info lookup") end,
	PromptJoinAsync = function(_, groupId)
		table.insert(groupPrompts, groupId)
		if groupPromptReentry then local callback = groupPromptReentry groupPromptReentry = nil callback() end
		if groupPromptFailed then error("Mock group prompt unavailable") end
	end,
}
environment.os = { clock=function() return now end, time=os.time }
local MetaController = luau.load(fs.readFile("src/client/controllers/ProgressionController.luau"), { environment = environment })()
local modalMain = add(assets, "ScreenGui", "NewModalMain")
local modalFrames = add(modalMain, "Frame", "Frames")
modalFrames.ChildAdded = signal()
modalFrames.ChildRemoved = signal()
add(modalMain, "Frame", "Game")
local modalHome = add(modalMain, "Frame", "Home")
local shopLauncher = add(add(modalHome, "Frame", "ButtonBar"), "TextButton", "Shop")
local shop = add(modalFrames, "Frame", "Shop")
shop.BackgroundTransparency, shop.AnchorPoint, shop.Position = 0.12, rbx.Vector2.new(0.5, 0.5), rbx.UDim2.fromScale(0.5, 0.5)
local cardHolder = add(shop, "Frame", "Frame")
cardHolder.Size = rbx.UDim2.fromScale(0.92, 0.7)
local contentSize = cardHolder.Size
add(shop, "TextLabel", "Title")
local shopQuit = add(shop, "TextButton", "Quit")
local newCards = {}
for _, name in ipairs({"One", "Two", "Three"}) do
	local card = add(cardHolder, "Frame", name)
	add(card, "TextLabel", "Title")
	local buy = add(card, "TextButton", "Buy")
	buy.Text = "Authored button " .. name
	add(buy, "TextLabel", "TextLabel").Text = "Authored label " .. name
	table.insert(newCards, card)
end
for _, name in ipairs({"Countdown", "CustomFrame", "DailyReward", "DuelOutcome", "DuelRequest", "GameOutcome", "Leaderboards", "Levels", "PurchaseFrame", "Settings", "Statistics", "Verify"}) do
	local modal = add(modalFrames, "Frame", name)
	add(modal, "Frame", "Frame")
	add(modal, "TextLabel", "Title")
	add(modal, "TextButton", "Quit")
end
local leaderboardLauncher = add(shopLauncher.Parent, "TextButton", "Leaderboard")
local leaderboardFrame = modalFrames:FindFirstChild("Leaderboards")
do
 local you = add(leaderboardFrame,"Frame","You")
 for _, name in ipairs({"Username","Data","Place"}) do add(you,"TextLabel",name) end
 add(you,"ImageLabel","Mugshot")
end
leaderboardFrame:FindFirstChild("Frame"):Destroy()
local leaderboardPanels = {}
for _, category in ipairs({ "WordsFound", "1v1Wins", "Level" }) do
	local panel = add(leaderboardFrame, "Frame", category)
	leaderboardPanels[category] = panel
	for _, slotName in ipairs({ "One", "Three", "Two" }) do
		local slot = add(panel, "Frame", slotName)
		local cardStroke = add(slot, "UIStroke", "UIStroke")
		cardStroke.Color = rbx.Color3.fromRGB(1, 2, 3)
		local mugshot = add(slot, "ImageLabel", "Mugshot")
		add(mugshot, "ImageLabel", "Profile")
		add(mugshot, "UIStroke", "UIStroke")
		for _, label in ipairs({ "Data", "Place", "Username" }) do add(slot, "TextLabel", label) end
	end
	for _, name in ipairs({ "WordsFound", "1v1Wins", "Level" }) do add(panel, "TextButton", name) end
end
do
	local daily = modalFrames:FindFirstChild("DailyReward")
	daily.Name = "DailyRewards"
	daily:FindFirstChild("Frame"):Destroy()
	daily:FindFirstChild("Title").Text = "Daily Rewards"
	add(add(daily,"Frame","Requirements"),"TextLabel","Title").Text = "Authored requirements"
	add(add(daily,"TextButton","Claim"),"TextLabel","TextLabel")
	add(daily,"TextLabel","Timer")
	add(shopLauncher.Parent,"TextButton","Daily")
end
do
	local lobby = add(modalFrames,"Frame","DuelLobby")
	add(lobby,"TextLabel","Title").Text = "1V1"
	add(lobby,"TextButton","Quit")
	local list = add(add(lobby,"Frame","Container"),"ScrollingFrame","ScrollingFrame")
	add(list,"UIListLayout","UIListLayout").Padding = rbx.UDim.new(0,12)
	local sample = add(assets,"Frame","1v1Template")
	sample.Visible = false
	sample.Size = rbx.UDim2.fromScale(0.9,0.16)
	add(sample,"UICorner","UICorner")
	add(sample,"UIStroke","UIStroke").Color = rbx.Color3.fromRGB(15,30,45)
	add(sample,"TextButton","Request").Text = "Request"
	add(sample,"TextLabel","Username")
	local mugshot = add(sample,"ImageLabel","Mugshot")
	add(mugshot,"UIStroke","UIStroke")
	add(mugshot,"ImageLabel","Profile")
end
local duelRequestFrame = modalFrames:FindFirstChild("DuelRequest")
duelRequestFrame:FindFirstChild("Frame"):Destroy()
duelRequestFrame:FindFirstChild("Quit"):Destroy()
add(duelRequestFrame, "ImageLabel", "Mugshot")
add(duelRequestFrame, "TextLabel", "UserName")
for _, name in ipairs({ "Green", "Red" }) do
	local button = add(duelRequestFrame, "TextButton", name)
	add(button, "ImageLabel", "Icon").Image = "authored:" .. name
end
local duelOutcomeFrame = modalFrames:FindFirstChild("DuelOutcome")
duelOutcomeFrame:FindFirstChild("Frame"):Destroy()
duelOutcomeFrame:FindFirstChild("Quit"):Destroy()
for _, name in ipairs({ "CurrentXP", "LevelTheme", "Words", "XPWon" }) do add(duelOutcomeFrame, "TextLabel", name) end
for _, name in ipairs({ "WinnerIcon", "LoserIcon" }) do add(duelOutcomeFrame, "ImageLabel", name).Image = "authored:" .. name end
add(duelOutcomeFrame, "TextButton", "Home").Text = "authored-home"
add(add(duelOutcomeFrame, "TextButton", "Rematch"), "TextLabel", "TextLabel")
local duelFill = add(add(duelOutcomeFrame, "Frame", "FillBar"), "Frame", "Fill")
duelFill.Size, duelFill.BackgroundColor3 = rbx.UDim2.fromScale(0,1),rbx.Color3.fromRGB(75,202,53)
local gameOutcome = modalFrames:FindFirstChild("GameOutcome")
gameOutcome:FindFirstChild("Frame"):Destroy()
for _, name in ipairs({ "LevelTheme", "Words", "XPWon", "CurrentXP" }) do add(gameOutcome, "TextLabel", name) end
add(gameOutcome, "TextButton", "Play")
add(gameOutcome, "TextButton", "Home")
local outcomeIcon = add(gameOutcome, "ImageLabel", "Icon2")
outcomeIcon.Image = "authored-thumbs-up"
local outcomeFill = add(add(gameOutcome, "Frame", "FillBar"), "Frame", "Fill")
outcomeFill.Size, outcomeFill.BackgroundColor3 = rbx.UDim2.fromScale(0, 1), rbx.Color3.fromRGB(75, 202, 53)
local outcomeActions = {}
local verifyFrame = modalFrames:FindFirstChild("Verify")
local verifyOkay = add(verifyFrame, "TextButton", "Okay")
add(verifyOkay, "TextLabel", "TextLabel")
local settingsFrame = modalFrames:FindFirstChild("Settings")
local settingsRows = settingsFrame:FindFirstChild("Frame")
local toggles, labelStrokes = {}, {}
for _, name in ipairs({ "Music", "SFX", "DuelInvites" }) do
	local row = add(settingsRows, "Frame", name == "DuelInvites" and "1v1" or name)
	row.BackgroundColor3 = rbx.Color3.fromRGB(12, 34, 56)
	add(row, "TextLabel", "Title").Text = name
	local toggle = add(row, "TextButton", "Toggle")
	local label = add(toggle, "TextLabel", name == "Music" and "TextLabel" or "Textlabel")
	local labelStroke = add(label, "UIStroke", "UIStroke")
	labelStroke.Color = rbx.Color3.fromRGB(4, 5, 6)
	labelStrokes[name] = labelStroke
	if name == "Music" then
		local border = add(toggle, "UIStroke", "UIStroke")
		border.Color, border.Transparency, border.Thickness = rbx.Color3.new(), 0, 2
	end -- SFX verifies that a missing toggle border is created.
	toggles[name] = toggle
	effects.Init(toggle)
end
local settingsSnapshot = { hints = 0 }
local appliedSettings, settingRequests = {}, {}
players.LocalPlayer.FindFirstChild = function() return nil end
local modalUi = MetaController.new({
	getSnapshot = function() return settingsSnapshot end,
	applySnapshot = function(snapshot) table.insert(appliedSettings, table.clone(snapshot.settings)) end,
	onOutcomePlay = function(id) table.insert(outcomeActions, "play:" .. id) end,
	onOutcomeHome = function(id) table.insert(outcomeActions, "home:" .. id) end,
})
modalUi.remotes.updateSetting = { FireServer = function(_, name, enabled) table.insert(settingRequests, { name = name, enabled = enabled }) end }
modalUi:resolveElements(modalMain)
modalUi:initializeModalFrames()
modalUi:connectButtons()
modalUi:updateSettings()
advance(0.2)
for _, name in ipairs({ "Music", "SFX", "DuelInvites" }) do
	local toggle = toggles[name]
	local label = toggle:FindFirstChild("TextLabel") or toggle:FindFirstChild("Textlabel")
	check(label.Text == "On" and toggle.BackgroundColor3 == rbx.Color3.fromRGB(75, 202, 53), "Missing settings default to On with the requested green")
	check(toggle:FindFirstChild("UIStroke").Color == rbx.Color3.fromRGB(31, 154, 31), "On toggle has the requested green stroke")
	check(modalUi.elements["settings" .. name] == toggle, "Settings binds the authored row's Toggle button")
end
for _, frame in ipairs(modalFrames:GetChildren()) do
	check(not frame.Visible and frame.Size == rbx.UDim2.fromScale(0, 0), "Every authored modal starts hidden at zero size")
end
check(cardHolder.Visible and cardHolder.Size == contentSize, "Modal initialization preserves its inner card container")
for _, fn in ipairs(shopLauncher.Activated.callbacks) do fn() end
check(shop.Visible and shop.Size == rbx.UDim2.fromScale(0, 0), "Shop becomes visible before growing from zero")
advance(0.5)
check(shop.Size == rbx.UDim2.fromScale(0.33, 0.33) and shop.BackgroundTransparency == 0.12, "Outer Shop grows to 0.33 without becoming a dim overlay")
check(cardHolder.Size == contentSize and cardHolder.Visible, "Opening leaves inner Frame geometry and visibility intact")
local counts, ids = {5,15,30}, {3573028342,3573028459,3711566945}
for i, card in ipairs(newCards) do
	check(card:FindFirstChild("Title").Text == counts[i] .. " Hints", "Shop card title shows its exact grant")
	local buy = card:FindFirstChild("Buy")
	check(buy.Text == "Authored button " .. card.Name and buy:FindFirstChild("TextLabel").Text == "Authored label " .. card.Name, "Shop preserves authored Buy text and child labels")
	for _, fn in ipairs(buy.Activated.callbacks) do fn() end
	check(prompts[#prompts] == ids[i], "Authored Buy prompts its exact product through Activated")
end
check(#productRequests == 0 and #prompts == 3, "Shop prompts the three products without fetching or rewriting prices")
modalUi:handleHintPurchase(1)
check(#prompts == 3 and not shop:FindFirstChild("HintCurrencyToggle", true), "Shop never prompts one hint or fabricates a currency switch")
for _, fn in ipairs(shopQuit.Activated.callbacks) do fn() end
advance(0.36)
check(not shop.Visible and shop.Size == rbx.UDim2.fromScale(0, 0), "Outer Quit closes Shop back to hidden zero size")
modalUi:showFrame(shop)
advance(0.1)
modalUi:hideFrame(shop)
advance(0.1)
modalUi:showFrame(shop)
advance(0.5)
check(shop.Visible and shop.Size == rbx.UDim2.fromScale(0.33, 0.33), "A stale close cannot hide a reopened modal")
services.UserInputService.TouchEnabled, services.UserInputService.KeyboardEnabled = true, false
check(modalUi:getModalOpenSize(shop) == rbx.UDim2.fromScale(0.33, 0.33), "Touch uses the same requested modal size")
local lateModal = add(modalFrames, "Frame", "LateModal")
for _, fn in ipairs(modalFrames.ChildAdded.callbacks) do fn(lateModal) end
check(not lateModal.Visible and lateModal.Size == rbx.UDim2.fromScale(0, 0), "Late-added modals initialize hidden at zero too")
-- Outcome binds the authored root and shares the real XP fill animation.
modalUi:showGameOutcome({roundId="finished",mode="Standard",theme="Countries",words=10,total=10,xpEarned=220},
	{progression={level=6,xp=400,xpToNextLevel=2000}})
check(gameOutcome.Visible and outcomeFill.Size.X.Scale >= 0.1, "Outcome opens through the modal system and never has an empty sliver")
check(not gameOutcome:FindFirstChild("Words").Visible and not gameOutcome:FindFirstChild("XPWon").Visible and not outcomeFill.Parent.Visible and not gameOutcome:FindFirstChild("Play").Visible, "Outcome starts with count-up stages and bottom actions hidden")
for _, fn in ipairs(gameOutcome:FindFirstChild("Play").Activated.callbacks) do fn() end
check(#outcomeActions == 0, "Hidden bottom action cannot interrupt the reveal")
advance(0.51)
check(gameOutcome:FindFirstChild("Words").Text == "2/10 Words" and not gameOutcome:FindFirstChild("XPWon").Visible, "Word count advances before XP is shown")
advance(0.80)
check(gameOutcome:FindFirstChild("Words").Text == "10/10 Words" and gameOutcome:FindFirstChild("XPWon").Visible and gameOutcome:FindFirstChild("XPWon").Text ~= "+220 XP" and not outcomeFill.Parent.Visible, "XP reveals and rapidly counts only after the words finish")
advance(0.91)
check(outcomeFill.Parent.Visible and math.abs(outcomeFill.Size.X.Scale - 0.1) < 0.00001 and gameOutcome:FindFirstChild("CurrentXP").Text == "Level 6 | 180 / 2000 XP", "Progress bar reveals at pre-award XP before filling")
check(not gameOutcome:FindFirstChild("Home").Visible, "Bottom buttons wait until the bar has filled")
advance(1.5)
check(gameOutcome:FindFirstChild("Play").Visible and gameOutcome:FindFirstChild("Home").Visible and Interface.OutcomeButtonsReady(gameOutcome), "Bottom actions pop in last and become ready")
check(gameOutcome:FindFirstChild("Title").Text == "Complete!" and gameOutcome:FindFirstChild("LevelTheme").Text == "Theme: Countries", "GameOutcome displays only the prefixed theme without a mode name")
check(gameOutcome:FindFirstChild("Words").Text == "10/10 Words" and gameOutcome:FindFirstChild("XPWon").Text == "+220 XP", "Outcome displays round words and server-earned XP")
check(gameOutcome:FindFirstChild("CurrentXP").Text == "Level 6 | 400 / 2000 XP" and math.abs(outcomeFill.Size.X.Scale - 0.2) < 0.00001, "Outcome shows the current saved level progress")
check(outcomeIcon.Image == "authored-thumbs-up" and gameOutcome.Size == rbx.UDim2.fromScale(0.33, 0.33), "Outcome preserves its authored icon and uses the new modal size")
modalUi:updateGameOutcome({progression={level=7,xp=220,xpToNextLevel=2200}})
advance(0.36)
check(outcomeFill.Size == rbx.UDim2.fromScale(1, 1) and outcomeFill.BackgroundColor3 == rbx.Color3.fromRGB(255, 211, 92), "Outcome XP fill shares the gold level-up effect")
advance(1.02)
check(math.abs(outcomeFill.Size.X.Scale - 0.1) < 0.00001 and gameOutcome:FindFirstChild("XPWon").Text == "+220 XP", "Late profile updates refresh progress without changing earned round XP")
for _, fn in ipairs(gameOutcome:FindFirstChild("Play").Activated.callbacks) do fn() end
for _, fn in ipairs(gameOutcome:FindFirstChild("Home").Activated.callbacks) do fn() end
check(outcomeActions[1] == "play:finished" and outcomeActions[2] == "home:finished", "Outcome buttons route the exact completed round to the flow controller")
for _, fn in ipairs(gameOutcome:FindFirstChild("Quit").Activated.callbacks) do fn() end
advance(0.36)
check(gameOutcome.Visible and #outcomeActions == 2, "GameOutcome never binds a dismiss-only Quit action")
modalUi:hideFrame(gameOutcome)
advance(0.36)

check(Interface.OutcomeWords(7,10,155.9) == "7/10 Words in 02:35", "Outcome formats elapsed minutes and seconds")
check(Interface.OutcomeWords(10,10,1800) == "10/10 Words in 30:00", "Exactly thirty minutes keeps the elapsed timer")
check(Interface.OutcomeWords(10,10,1801) == "10/10 Words: Scenic route!", "Over thirty minutes uses a four-word playful line")
check(Interface.OutcomeWords(0,10,0) == "0/10 Words in 00:00", "Zero-duration outcome formats correctly")

;(function()
 local owned = add(shop,"TextLabel","HintsOwned")
 modalUi.elements.shopHintsOwned = owned
 modalUi:updateShopTexts({hints=0})
 check(owned.Text == "0" and owned.TextTransparency == 0.5, "Shop displays zero owned hints with empty styling")
 modalUi:updateShopTexts({hints=30})
 check(owned.Text == "30" and owned.TextTransparency == 0, "Shop displays the actual owned hint total")
end)()

-- Closing/reopening invalidates every queued stage and retains real pre-round progress.
;(function()
	local result = {roundId="sequence-cancel",mode="Standard",theme="Animals",words=3,total=7,xpEarned=100,
		beforeProgression={level=1,xp=950}}
	modalUi:showGameOutcome(result, {progression={level=1,xp=950}})
	advance(0.35)
	modalUi:updateGameOutcome({progression={level=2,xp=120}})
	check(math.abs(outcomeFill.Size.X.Scale-0.95)<0.00001 and not outcomeFill.Parent.Visible, "Profile packets during count-up cannot skip the pre-round bar stage")
	modalUi:hideFrame(gameOutcome)
	advance(5)
	check(not gameOutcome.Visible and not gameOutcome:FindFirstChild("XPWon"):FindFirstChild("OutcomeScale"), "Closing mid-sequence cancels delayed stages and removes temporary scales")
	result.roundId = "sequence-reopen"
	modalUi:showGameOutcome(result, {progression={level=1,xp=950}})
	advance(1.9)
	check(outcomeFill.Parent.Visible and math.abs(outcomeFill.Size.X.Scale-0.95)<0.00001 and not gameOutcome:FindFirstChild("Play").Visible, "Reopened outcome starts from its captured pre-round XP")
	advance(0.6)
	check(outcomeFill.Size.X.Scale == 1 and outcomeFill.BackgroundColor3 == rbx.Color3.fromRGB(255,211,92), "Award crossing a level plays the gold full-bar stretch")
	check(not gameOutcome:FindFirstChild("Home").Visible, "Bottom actions wait through the gold level-up stage")
	advance(2)
	check(gameOutcome:FindFirstChild("Words").Text == "3/7 Words" and gameOutcome:FindFirstChild("XPWon").Text == "+100 XP", "Partial completion counts only actual found words and awarded XP")
	check(gameOutcome:FindFirstChild("CurrentXP").Text == "Level 2 | 50 / 1200 XP" and Interface.OutcomeButtonsReady(gameOutcome), "Awarded XP supplies the final bar even if its profile snapshot arrived late")
	modalUi:hideFrame(gameOutcome)
	advance(0.4)
	modalUi:showGameOutcome({roundId="zero-award",words=0,total=7,xpEarned=0,beforeProgression={level=2,xp=50}}, {progression={level=2,xp=50}})
	advance(4)
	check(gameOutcome:FindFirstChild("Words").Text == "0/7 Words" and gameOutcome:FindFirstChild("XPWon").Text == "+0 XP" and Interface.OutcomeButtonsReady(gameOutcome), "Zero-word and zero-XP outcomes finish the sequence without division errors")
	modalUi:hideFrame(gameOutcome)
	advance(0.4)
end)()


;(function()
 local hint = add(hud, "ImageButton", "WobbleTest")
 hint.Rotation = 4
 local scale = add(hint, "UIScale", "AuthoredScale") scale.Scale = 0.8
 local wobble = shared.ui.UIEffects.CreateHintWobble(hint)
 local moved = false
 for _=1,420 do wobble:Step(1/60,true) moved = moved or hint.Rotation ~= 4 end
 check(moved and scale.Scale == 0.8, "Hint periodically wobbles without taking over its authored scale")
 wobble:Step(1/60,false)
 check(hint.Rotation == 4, "Input lock cancels hint motion and restores authored rotation")
 wobble:Destroy() hint:Destroy()
 modalUi:showGameOutcome({roundId="timeout",timedOut=true,words=1,total=7,xpEarned=60}, {progression={level=2,xp=60}})
 advance(4)
 check(gameOutcome:FindFirstChild("Title").Text == "Time's up!" and Interface.OutcomeButtonsReady(gameOutcome), "Timeout displays partial results with normal replay and Home actions")
 modalUi:hideFrame(gameOutcome)
end)()

-- Verify uses its outer Okay button and the native async group prompt.
local groupChecks, groupClaims = 0, 0
modalUi.startGroupJoinVerificationPoll = function() groupChecks += 1 end
modalUi.remotes.playerJoinedGroup = { FireServer = function() groupClaims += 1 end }
players.LocalPlayer.IsInGroup = function() return false end
check(modalUi.elements.verifyJoin == verifyOkay and modalUi.elements.verifyExit == verifyFrame:FindFirstChild("Quit"), "Verify resolves the authored Okay and Quit controls")
local function pressOkay() for _, fn in ipairs(verifyOkay.Activated.callbacks) do fn() end end
groupPromptReentry = pressOkay
pressOkay()
check(#groupPrompts == 1 and groupPrompts[1] == 34241464 and groupChecks == 1, "Okay prompts the configured Roblox group directly and suppresses overlapping prompts")
groupPromptFailed = true
pressOkay()
check(#groupPrompts == 2 and groupChecks == 1 and not modalUi.groupJoinPromptPending, "Failed native prompts release the button for retry")
groupPromptFailed = false
players.LocalPlayer.IsInGroup = function() return true end
pressOkay()
check(#groupPrompts == 3 and groupClaims == 1, "Successful join retains the server-verified group reward request")
modalUi:showFrame(verifyFrame)
advance(0.5)
for _, fn in ipairs(verifyFrame:FindFirstChild("Quit").Activated.callbacks) do fn() end
advance(0.36)
check(not verifyFrame.Visible, "Verify Quit closes the outer modal")

-- Automatic Verify waits for the first normal completion and an unobstructed Home.
do
	local ready, firstPuzzle, ownerTest, inGroup = false, false, false, false
	local profile = {tutorial={completed=false}, progression={solves=0}, account={groupRewardClaimed=false}}
	local root = add(assets, "ScreenGui", "VerifyFlowTest")
	local frames = add(root, "Frame", "Frames")
	frames.ChildAdded, frames.ChildRemoved = signal(), signal()
	local verify = add(frames, "Frame", "Verify")
	local controller = MetaController.new({
		getSnapshot=function() return profile end,
		canShowVerifyPrompt=function() return ready end,
		hasCompletedFirstPuzzle=function() return firstPuzzle end,
		isVerifyPromptTestUser=function() return ownerTest end,
	})
	controller.root, controller.elements = root, {frames=frames, verifyFrame=verify}
	controller.isPlayerInGroup = function() return inGroup end
	controller:initializeModalFrames()
	controller:queueVerifyPrompt(profile)
	check(not controller.verifyPromptQueued, "Verify never queues during unfinished onboarding")
	profile.tutorial.completed = true
	controller:queueVerifyPrompt(profile)
	check(not controller.verifyPromptQueued, "Finishing tutorial alone cannot queue Verify for a normal player")
	profile.progression.solves = 10
	controller:queueVerifyPrompt(profile)
	check(not controller.verifyPromptQueued, "Returning veteran is not treated as a first puzzle completion")
	profile.progression.solves, firstPuzzle = 1, true
	controller:queueVerifyPrompt(profile)
	local token = controller.verifyPromptToken
	controller:queueVerifyPrompt(profile)
	check(controller.verifyPromptQueued and controller.verifyPromptToken == token, "First normal completion queues only one Verify prompt")
	advance(1.3)
	check(not verify.Visible and controller.verifyPromptQueued, "Outcome, tutorial, queue and transition blockers defer Verify")
	ready = true
	advance(1.1)
	check(verify.Visible and controller.verifyPromptShownThisSession, "Verify opens once Home is ready after the first normal puzzle")
	controller:hideFrame(verify)
	advance(0.4)
	controller:queueVerifyPrompt(profile)
	advance(1.3)
	check(not verify.Visible and not controller.verifyPromptQueued, "Closing Verify prevents repeated profile updates from reopening it")
	controller.verifyPromptShownThisSession = false
	inGroup = true
	check(not controller:shouldAutoShowVerifyPrompt(profile), "Ordinary group members do not receive join invitations")
	inGroup, profile.account.groupRewardClaimed = false, true
	check(not controller:shouldAutoShowVerifyPrompt(profile), "Previously claimed group rewards suppress ordinary invitations")
	ownerTest, inGroup, firstPuzzle, profile.progression.solves = true, true, false, 0
	controller:queueVerifyPrompt(profile)
	advance(1.3)
	check(verify.Visible, "Owner testing bypasses membership, prior reward and normal-puzzle requirements after tutorial")
	controller:hideFrame(verify)
	advance(0.4)
	controller.verifyPromptShownThisSession = false
	controller:queueVerifyPrompt(profile)
	controller:destroy()
	advance(1.3)
	check(not verify.Visible and not controller.verifyPromptQueued, "Destroyed controllers cannot reopen delayed Verify prompts")
	root:Destroy()
end

-- Settings update the real snapshot/remote and survive click/highlight callbacks.
for _, name in ipairs({ "Music", "SFX", "DuelInvites" }) do
	local toggle = toggles[name]
	for _, fn in ipairs(toggle.Activated.callbacks) do fn() end
	advance(0.9)
	local label = toggle:FindFirstChild("TextLabel") or toggle:FindFirstChild("Textlabel")
	check(label.Text == "Off" and toggle.BackgroundColor3 == rbx.Color3.fromRGB(202, 61, 51), "Toggle switches to Off and its exact red background")
	check(toggle:FindFirstChild("UIStroke").Color == rbx.Color3.fromRGB(154, 28, 28), "Click highlight cannot restore the old On stroke")
	check(settingRequests[#settingRequests].name == name and settingRequests[#settingRequests].enabled == false and settingsSnapshot.settings[name] == false, "Toggle sends and immediately applies the saved setting")
	check(appliedSettings[#appliedSettings][name] == false, "Local snapshot callback receives the audio preference immediately")
	for _, fn in ipairs(toggle.MouseEnter.callbacks) do fn() end
	advance(0.15)
	for _, fn in ipairs(toggle.MouseLeave.callbacks) do fn() end
	advance(0.15)
	check(toggle.BackgroundColor3 == rbx.Color3.fromRGB(202, 61, 51), "Mouse leave restores the current Off color instead of stale authored color")
	for _, fn in ipairs(toggle.Activated.callbacks) do fn() end
	advance(0.2)
	check(label.Text == "On" and settingRequests[#settingRequests].enabled == true, "Second click turns On using current state without waiting for mirrors")
	check(toggle.Parent.BackgroundColor3 == rbx.Color3.fromRGB(12, 34, 56) and labelStrokes[name].Color == rbx.Color3.fromRGB(4, 5, 6), "Only the toggle background and toggle stroke change")
end
modalUi:updateSettings({ settings = { Music = false, SFX = false, DuelInvites = false } })
advance(0.2)
check(not modalUi.settingValues.Music and not modalUi.settingValues.SFX and not modalUi.settingValues.DuelInvites, "Saved Off preferences override new-player On defaults")
modalUi:showFrame(settingsFrame)
advance(0.5)
for _, fn in ipairs(settingsFrame:FindFirstChild("Quit").Activated.callbacks) do fn() end
advance(0.36)
check(not settingsFrame.Visible and settingsRows.Size == rbx.UDim2.fromScale(1, 1), "Settings Quit closes the outer modal while preserving its rows")
-- Three authored podiums: exact slot names, independent data and exclusive tabs.
check(leaderboardPanels.WordsFound.Visible and not leaderboardPanels["1v1Wins"].Visible and not leaderboardPanels.Level.Visible, "Words Found is the only default leaderboard panel")
local wordsRanking = {
	{ UserId=55, Username="WordWinner", Score=900, Thumbnail="headshot:55" },
	{ UserId=66, Username="Second", Score=800, Thumbnail="" },
	{ UserId=77, Username="Third", Score=700, Thumbnail="headshot:77" },
	{ UserId=88, Username="Fourth", Score=600 },
}
local winsRanking = { { UserId=99, Username="DuelWinner", Score=42, Thumbnail="headshot:99" } }
modalUi:applyLeaderboardUpdate("WordsFound", wordsRanking, 10, {UserId=1,Score=23,RankText="#18"})
modalUi:applyLeaderboardUpdate("1v1Wins", winsRanking, 11, {UserId=1,Score=4,RankText="100+"})
;(function()
 local you = leaderboardFrame:FindFirstChild("You")
 check(you.Visible and you:FindFirstChild("Data").Text == "23" and you:FindFirstChild("Place").Text == "#18", "You row shows personal Words Found score and rank")
 modalUi:selectLeaderboard("1v1Wins")
 check(you:FindFirstChild("Data").Text == "4" and you:FindFirstChild("Place").Text == "100+", "You row follows the selected Duel wins tab")
 check(you:FindFirstChild("Mugshot").Image == "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150", "You row always displays the local account headshot")
 local originalSnapshot = modalUi.ctx.getSnapshot
 modalUi.ctx.getSnapshot = function() return {progression={wordsFound=24,duel={wins=5}}} end
 modalUi:renderLeaderboard()
 check(you:FindFirstChild("Data").Text == "5" and you:FindFirstChild("Place").Text == "--", "Changed personal totals cannot display a stale rank")
 modalUi.ctx.getSnapshot = originalSnapshot
 modalUi:selectLeaderboard("WordsFound")
end)()
local medals = {
	{ "One", rbx.Color3.fromRGB(255,214,92), rbx.Color3.fromRGB(177,128,24) },
	{ "Two", rbx.Color3.fromRGB(208,220,233), rbx.Color3.fromRGB(109,124,145) },
	{ "Three", rbx.Color3.fromRGB(211,147,93), rbx.Color3.fromRGB(137,81,42) },
}
for rank, medal in ipairs(medals) do
	local slot = leaderboardPanels.WordsFound:FindFirstChild(medal[1])
	local mugshot = slot:FindFirstChild("Mugshot")
	check(slot:FindFirstChild("Username").Text == wordsRanking[rank].Username and slot:FindFirstChild("Data").Text == tostring(wordsRanking[rank].Score), "Authored slot names determine rank despite unordered children")
	check(slot:FindFirstChild("Place").Text == "#" .. rank and slot:FindFirstChild("Place").TextColor3 == medal[2], "Rank text uses gold, silver, bronze")
	check(mugshot.BackgroundColor3 == medal[2] and mugshot:FindFirstChild("UIStroke").Color == medal[3], "Mugshot uses medal background and darker outline")
	check(not mugshot:FindFirstChild("Profile").Visible and slot:FindFirstChild("UIStroke").Color == rbx.Color3.fromRGB(1,2,3), "Portrait placeholder hides without recoloring the authored card")
end
check(#leaderboardPanels.WordsFound:GetChildren() == 6, "Leaderboard never clones a fourth slot or adds a layout")
check(leaderboardPanels.WordsFound:FindFirstChild("Two"):FindFirstChild("Mugshot").Image == "rbxthumb://type=AvatarHeadShot&id=66&w=150&h=150", "A missing cached image requests the actual ranked user's headshot")
local function pressLeaderboard(panel, name)
	for _, callback in ipairs(panel:FindFirstChild(name).Activated.callbacks) do callback() end
end
for _, callback in ipairs(leaderboardLauncher.Activated.callbacks) do callback() end
advance(0.5)
check(leaderboardFrame.Visible and leaderboardFrame.Size == rbx.UDim2.fromScale(0.33,0.33), "Home opens the outer leaderboard modal")
pressLeaderboard(leaderboardPanels.WordsFound, "1v1Wins")
check(not leaderboardPanels.WordsFound.Visible and leaderboardPanels["1v1Wins"].Visible, "Wins tab exclusively shows its panel")
check(leaderboardPanels["1v1Wins"]:FindFirstChild("One"):FindFirstChild("Data").Text == "42", "Duel wins have their own ranking values")
modalUi:applyLeaderboardUpdate("WordsFound", wordsRanking, 12)
check(leaderboardPanels["1v1Wins"].Visible and not leaderboardPanels.WordsFound.Visible, "Incoming refresh preserves selected tab")
modalUi:applyLeaderboardUpdate("1v1Wins", {}, 9)
check(leaderboardPanels["1v1Wins"]:FindFirstChild("One"):FindFirstChild("Data").Text == "42", "Stale category packets cannot erase newer rankings")
modalUi:applyLeaderboardUpdate("1v1Wins", {}, 13)
local emptySlot = leaderboardPanels["1v1Wins"]:FindFirstChild("One")
check(emptySlot:FindFirstChild("Username").Text == "No player yet" and emptySlot:FindFirstChild("Mugshot").Image == "" and emptySlot:FindFirstChild("Mugshot").ImageTransparency == 1, "Empty results clear previous username and headshot")
pressLeaderboard(leaderboardPanels["1v1Wins"], "WordsFound")
check(leaderboardPanels.WordsFound.Visible and not leaderboardPanels["1v1Wins"].Visible and not leaderboardPanels.Level.Visible, "Words Found button switches back")
;(function()
 local ranking={{UserId=44,Username="TopLevel",Score=87,Thumbnail="headshot:44"},{UserId=45,Username="NextLevel",Score=65}}
 modalUi:applyLeaderboardUpdate("Level",ranking,10,{UserId=1,Score=12,RankText="#8"})
 pressLeaderboard(leaderboardPanels.WordsFound,"Level")
 check(leaderboardPanels.Level.Visible and not leaderboardPanels.WordsFound.Visible and not leaderboardPanels["1v1Wins"].Visible,"Level button exclusively opens the authored Level panel")
 local winner=leaderboardPanels.Level:FindFirstChild("One")
 check(winner:FindFirstChild("Username").Text=="TopLevel" and winner:FindFirstChild("Data").Text=="87" and winner:FindFirstChild("Place").Text=="#1","Level podium shows authoritative saved XP levels and rank")
 local you=leaderboardFrame:FindFirstChild("You")
 local originalSnapshot=modalUi.ctx.getSnapshot
 modalUi.ctx.getSnapshot=function() return {score=100000,progression={level=12,wordsFound=999,duel={wins=88}}} end
 modalUi:renderLeaderboard()
 check(you:FindFirstChild("Data").Text=="12" and you:FindFirstChild("Place").Text=="#8","Level You row uses saved XP level instead of word count or round score")
 modalUi.ctx.getSnapshot=function() return {progression={level=13}} end
 modalUi:renderLeaderboard()
 check(you:FindFirstChild("Data").Text=="13" and you:FindFirstChild("Place").Text=="--","A new level clears the stale personal rank until matching rankings arrive")
 modalUi:applyLeaderboardUpdate("Level",ranking,11,{UserId=1,Score=13,RankText="#7"})
 check(you:FindFirstChild("Place").Text=="#7","Matching Level personal update restores the rank")
 modalUi:applyLeaderboardUpdate("WordsFound",wordsRanking,14)
 check(leaderboardPanels.Level.Visible,"Refreshing another category preserves the Level tab")
 modalUi:applyLeaderboardUpdate("Level",{},9)
 check(winner:FindFirstChild("Data").Text=="87","Stale Level packets cannot replace current rankings")
 pressLeaderboard(leaderboardPanels.Level,"1v1Wins")
 check(not leaderboardPanels.Level.Visible and leaderboardPanels["1v1Wins"].Visible,"Level panel can switch directly to Wins")
 pressLeaderboard(leaderboardPanels["1v1Wins"],"Level")
 check(leaderboardPanels.Level.Visible and not leaderboardPanels["1v1Wins"].Visible,"Wins panel can switch back to Level")
 pressLeaderboard(leaderboardPanels.Level,"WordsFound")
 modalUi.ctx.getSnapshot=originalSnapshot
end)()
for category in pairs(leaderboardPanels) do
	modalUi:selectLeaderboard(category)
	modalUi:showFrame(leaderboardFrame)
	advance(0.5)
	pressLeaderboard(leaderboardFrame, "Quit")
	advance(0.36)
	check(not leaderboardFrame.Visible, "Direct Leaderboards.Quit closes the whole modal from every tab")
end
;(function()
 local template = add(assets,"Frame","LeaderboardTemplate")
 for _, name in ipairs({"Username","Data","Place"}) do add(template,"TextLabel",name) end
 local portrait = add(template,"ImageLabel","Mugshot")
 portrait.BackgroundColor3 = rbx.Color3.fromRGB(80,150,220)
 add(portrait,"UIStroke","UIStroke").Color = rbx.Color3.fromRGB(20,80,120)
 modalUi.elements.leaderboardTemplate = template
 local entries = {}
 for i=1,25 do entries[i]={UserId=100+i,Username="Rank"..i,Score=1000-i} end
 for _, category in ipairs({"WordsFound","1v1Wins","Level"}) do
  local container = add(leaderboardPanels[category],"ScrollingFrame","Container")
  add(container,"UIListLayout","UIListLayout")
  local bottom = add(container,"Frame","Bottom")
  bottom.LayoutOrder = 0
  local bottomSize = bottom.Size
  modalUi:applyLeaderboardUpdate(category,entries,50)
  check(#container:GetChildren() == 22 and container.AutomaticCanvasSize == rbx.Enum.AutomaticSize.Y, "Leaderboard clones twenty rows and preserves the scrolling layout")
  local last = container:FindFirstChild("LeaderboardRank_20")
  check(last.LayoutOrder == 20 and last:FindFirstChild("Place").Text == "#20" and last:FindFirstChild("Username").Text == "Rank20", "Twentieth row displays its correct rank and identity")
  check(last:FindFirstChild("Mugshot").BackgroundColor3 == portrait.BackgroundColor3, "Ranks below third preserve the template colors")
  modalUi:renderLeaderboard()
  check(container:FindFirstChild("LeaderboardRank_20") == last and #container:GetChildren() == 22, "Refresh reuses rows without duplicates")
  modalUi:applyLeaderboardUpdate(category,{entries[2]},51)
  check(#container:GetChildren() == 3 and container:FindFirstChild("LeaderboardRank_1"):FindFirstChild("Username").Text == "Rank2", "Shrinking rankings remove stale rows and update retained identities")
  modalUi:applyLeaderboardUpdate(category,{},52)
  check(#container:GetChildren() == 2 and container:FindFirstChild("Bottom") == bottom and bottom.Size == bottomSize and bottom.LayoutOrder > 20, "Every leaderboard tab preserves authored Bottom padding after refresh and empty rankings")
 end
end)()
-- One shared backdrop follows real direct-child visibility, including external changes.
;(function()
	modalUi:hideAllFrames()
	advance(0.7)
	check(modalFrames.BackgroundTransparency == 1, "Backdrop is fully transparent with every modal closed")
	modalUi:showFrame(shop)
	check(modalFrames.BackgroundTransparency == 1, "Backdrop starts a tween rather than snapping on open")
	advance(0.23)
	check(modalFrames.BackgroundTransparency == 0.6, "Opening any modal dims Main.Frames to 0.6")
	modalUi:showFrame(settingsFrame)
	advance(0.7)
	check(modalFrames.BackgroundTransparency == 0.6 and settingsFrame.Visible, "Switching modals keeps the shared dim backdrop")
	modalUi:hideFrame(settingsFrame)
	advance(0.2)
	check(modalFrames.BackgroundTransparency == 0.6, "Backdrop remains dim while the last modal is shrinking")
	advance(0.4)
	check(modalFrames.BackgroundTransparency == 1, "Last modal closing fades the backdrop back to 1")
	shop.Visible = true
	settingsFrame.Visible = true
	advance(0.23)
	shop.Visible = false
	advance(0.23)
	check(modalFrames.BackgroundTransparency == 0.6, "External visibility changes count all visible siblings")
	settingsFrame.Visible = false
	advance(0.1)
	shop.Visible = true
	advance(0.23)
	check(modalFrames.BackgroundTransparency == 0.6, "Reopening cancels an unfinished clearing tween")
	shop.Visible = false
	advance(0.23)
	local late = add(modalFrames,"Frame","BackdropLateModal")
	for _, callback in ipairs(modalFrames.ChildAdded.callbacks) do callback(late) end
	check(not late.Visible and late.Size == rbx.UDim2.fromScale(0,0), "Late modals retain closed initialization")
	late.Visible = true
	advance(0.23)
	check(modalFrames.BackgroundTransparency == 0.6, "Late-added modal visibility is observed")
	late.Parent = nil
	for _, callback in ipairs(modalFrames.ChildRemoved.callbacks) do callback(late) end
	advance(0.23)
	check(modalFrames.BackgroundTransparency == 1, "Removing the last visible modal clears the backdrop")
end)();

-- Daily reward exact hierarchy, server synchronization, elapsed time and request races.
(function()
	local daily = modalFrames:FindFirstChild("DailyRewards")
	local timer, claim = daily:FindFirstChild("Timer"), daily:FindFirstChild("Claim")
	local red, green = rbx.Color3.fromRGB(202,100,100), rbx.Color3.fromRGB(75,170,95)
	local function state(ready, seconds) return {success=true,claimable=ready,secondsUntilReset=seconds,streak=4,nextRewardHints=1,nextRewardXp=0} end
	local function press(button) for _, fn in ipairs(button.Activated.callbacks) do fn() end end
	check(modalUi.elements.dailyFrame == daily and modalUi.elements.dailyClaim == claim and modalUi.elements.dailyClaimLabel == claim:FindFirstChild("TextLabel"), "DailyRewards binds the exact Claim.TextLabel hierarchy")
	check(timer.Text == "--:--" and timer.TextColor3 == red and not claim.Active, "Loading state does not imply the reward can be claimed")
	local reads, grants, shouldFail, lastApplied = 0, 0, false, nil
	local remoteState = state(true,86400)
	modalUi.remotes.getDailyRewardState = {InvokeServer=function() reads+=1 return remoteState end}
	local oldApply = modalUi.ctx.applySnapshot
	modalUi.ctx.applySnapshot = function(snapshot) lastApplied=snapshot end
	modalUi.remotes.claimDailyReward = {InvokeServer=function()
		grants+=1
		press(claim)
		if shouldFail then error("Mock daily claim unavailable") end
		remoteState=state(false,3661)
		return {success=true,state=remoteState,snapshot={hints=8}}
	end}
	press(shopLauncher.Parent:FindFirstChild("Daily"))
	advance(0.5)
	check(daily.Visible and daily.Size == rbx.UDim2.fromScale(0.33,0.33), "Daily launcher opens the new outer frame")
	check(timer.Text == "00:00" and timer.TextColor3 == green and claim.Active and claim:FindFirstChild("TextLabel").Text == "CLAIM", "Claimable daily reward shows green 00:00")
	check(daily:FindFirstChild("Title").Text == "Daily Rewards" and daily:FindFirstChild("Requirements"):FindFirstChild("Title").Text:find("Daily Streak: 4 days",1,true), "Requirements receives reward details without overwriting the frame title")
	press(claim)
	check(grants == 1 and lastApplied.hints == 8 and not modalUi.dailyClaimPending, "Claim submits once despite repeated clicks and applies granted hints snapshot")
	check(timer.Text == "01:01:01" and timer.TextColor3 == red and not claim.Active and daily.Visible, "Successful claim displays waiting countdown in mild red without dismissing the frame")
	advance(62)
	modalUi:tickDailyReward()
	check(timer.Text == "59:59", "Countdown uses elapsed time rather than losing one second per delayed tick")
	press(claim)
	check(grants == 1 and daily.Visible, "Waiting Claim cannot grant or act as Quit")
	modalUi:setDailyRewardState(state(false,2))
	remoteState=state(true,86400)
	advance(2.1)
	modalUi:tickDailyReward()
	check(timer.Text == "00:00" and timer.TextColor3 == green and claim.Active and reads == 2, "UTC reset refreshes availability without reopening the frame")
	shouldFail=true
	press(claim)
	check(not modalUi.dailyClaimPending and claim.Active, "Failed claim releases the pending lock for retry")
	shouldFail=false
	modalUi.remotes.claimDailyReward = {InvokeServer=function() return {success=false,state=state(false,90)} end}
	press(claim)
	check(timer.Text == "01:30" and not claim.Active, "Already-claimed server rejection reconciles waiting state: " .. timer.Text)
	modalUi:setDailyRewardState(state(true,100))
	modalUi.remotes.claimDailyReward = {InvokeServer=function() return {success=true,state=state(false,7200)} end}
	modalUi.remotes.getDailyRewardState = {InvokeServer=function()
		modalUi:claimDailyReward()
		return state(true,100)
	end}
	modalUi:refreshDailyRewardState()
	check(not claim.Active and timer.Text == "02:00:00", "An older state request cannot overwrite a newer successful claim")
	local failures=0
	modalUi.remotes.getDailyRewardState = {InvokeServer=function() failures+=1 error("Mock daily reset offline") end}
	modalUi:setDailyRewardState(state(false,0))
	advance(10.1)
	modalUi:tickDailyReward()
	modalUi:tickDailyReward()
	check(failures == 1 and timer.TextColor3 == red and not claim.Active, "Failed reset checks back off and never invent claimability")
	advance(10.1)
	modalUi:tickDailyReward()
	check(failures == 2, "Reset synchronization retries after the backoff")
	press(daily:FindFirstChild("Quit"))
	advance(0.36)
	check(not daily.Visible and daily.Size == rbx.UDim2.fromScale(0,0), "Daily Quit closes using the shared modal transition")
	modalUi.ctx.applySnapshot = oldApply
end)();

-- Bind the actual Duel feature to the new direct-child request/outcome hierarchy.
(function()
environment.script = { Parent = { Parent = { controllers = { InterfaceController=Interface, WaitForChild=waitForChild }, WaitForChild=waitForChild } } }
services.TextChatService = { ChatVersion=rbx.Enum.ChatVersion.TextChatService, FindFirstChild=function() return nil end }
services.StarterGui = { SetCore=function() end }
players.PlayerAdded, players.PlayerRemoving = signal(), signal()
environment.task.defer = function(fn) fn() end
storage.FindFirstChild = function(_, name) return (name == "assets" or name == "Assets") and assets or name == "shared" and shared or nil end
local DuelFeature = luau.load(fs.readFile("src/client/features/Duels.luau"), {environment=environment})()
local duelReplies, duelHomes = {}, {}
local duelSnapshot = {progression={level=3,xp=70,xpToNextLevel=700}}
local duelUi = DuelFeature.new({getSnapshot=function() return duelSnapshot end,onReturnHome=function(id) table.insert(duelHomes,id) end})
duelUi.metaUi = modalUi
duelUi:resolveElements(modalMain)
duelUi:bindRequestButtons()
duelUi:bindResultButton()
local challengeSignal, matchSignal = signal(), signal()
duelUi.remotes = {
	respondChallenge={FireServer=function(_,accepted) table.insert(duelReplies,accepted) end},
	challengeEvent={OnClientEvent=challengeSignal},matchEvent={OnClientEvent=matchSignal},
}
duelUi:connectRemotes()
local function fireDuel(s, payload) for _, fn in ipairs(s.callbacks) do fn(payload) end end
local function pressDuel(frame, name) for _, fn in ipairs(frame:FindFirstChild(name).Activated.callbacks) do fn() end end
(function()
	local lobby = modalFrames:FindFirstChild("DuelLobby")
	local list = lobby:FindFirstChild("Container"):FindFirstChild("ScrollingFrame")
	local sample = assets:FindFirstChild("1v1Template")
	local roster = {
		{userId=11,username="Alpha",inMatch=false,hasPending=false},
		{userId=22,username="Bravo",inMatch=true,hasPending=false},
		{userId=33,username="Charlie",inMatch=false,hasPending=true},
		{userId=1,username="Me"},{userId=-44,username="Bot"},
	}
	local requests, reads = {}, 0
	duelUi.remotes.requestPlayerList = {InvokeServer=function() reads+=1 return roster end}
	duelUi.remotes.sendChallenge = {FireServer=function(_,id,mode) table.insert(requests,{id=id,mode=mode}) end}
	check(duelUi:showLobby(), "Duel launcher opens its dedicated lobby instead of CustomFrame")
	advance(0.5)
	check(lobby.Visible and lobby.Size == rbx.UDim2.fromScale(0.33,0.33) and modalFrames.BackgroundTransparency == 0.6, "DuelLobby uses outer modal size and shared backdrop")
	check(#list:GetChildren() == 4 and list:FindFirstChild("UIListLayout").Padding == rbx.UDim.new(0,12), "Three eligible real-player rows preserve the authored layout and omit self and undeclared negative IDs")
	check(list.AutomaticCanvasSize == rbx.Enum.AutomaticSize.Y, "Duel list scrolls automatically to fit its entries")
	local first = duelUi.renderedEntries[11]
	check(first:FindFirstChild("Request").Visible, "Missing invite preference defaults to a visible Request button")
	local portrait, color = first:FindFirstChild("Mugshot"), first:FindFirstChild("Mugshot").BackgroundColor3
	check(first.Size == sample.Size and first:FindFirstChild("Username").Text == "Alpha", "Duel rows clone the supplied template and bind Username exactly")
	check(portrait.Image == "rbxthumb://type=AvatarHeadShot&id=11&w=150&h=150" and not portrait:FindFirstChild("Profile").Visible, "Duel mugshot uses the correct Roblox headshot without placeholder overlay")
	check(portrait.BackgroundTransparency == 0 and portrait:FindFirstChild("UIStroke").Color == color:Lerp(rbx.Color3.new(0,0,0),0.3), "Duel mugshot uses the queue palette and matching darker border")
	check(color ~= duelUi.renderedEntries[22]:FindFirstChild("Mugshot").BackgroundColor3 and first:FindFirstChild("UIStroke").Color == sample:FindFirstChild("UIStroke").Color, "Players receive distinct palette colors without changing the authored row border")
	roster[1].duelRequestsEnabled = false
	duelUi:requestPlayerListUpdate(true)
	pressDuel(first,"Request")
	check(not first:FindFirstChild("Request").Visible and not first:FindFirstChild("Request").Active and #requests == 0, "Invites-Off opponents disable Request and cannot be challenged by the click handler")
	roster[1].duelRequestsEnabled = true
	duelUi:requestPlayerListUpdate(true)
	check(first:FindFirstChild("Request").Visible and duelUi.renderedEntries[22]:FindFirstChild("Request").Visible and duelUi.renderedEntries[33]:FindFirstChild("Request").Visible and first:FindFirstChild("Request").Active and not duelUi.renderedEntries[22]:FindFirstChild("Request").Active and not duelUi.renderedEntries[33]:FindFirstChild("Request").Active, "Busy and pending opponents retain visible Request buttons but only available opponents enable them")
	pressDuel(duelUi.renderedEntries[22],"Request")
	check(#requests == 0, "Busy Request cannot send even if Activated fires")
	duelUi:requestPlayerListUpdate(true)
	check(duelUi.renderedEntries[11] == first and portrait.BackgroundColor3 == color and #list:GetChildren() == 4, "Refresh reuses rows/colors and never duplicates players")
	pressDuel(first,"Request")
	pressDuel(first,"Request")
	check(first:FindFirstChild("Request").Visible and duelUi.renderedEntries[22]:FindFirstChild("Request").Visible and duelUi.renderedEntries[33]:FindFirstChild("Request").Visible, "An outgoing invitation does not hide the list's Request buttons")
	check(#requests == 1 and requests[1].id == 11 and requests[1].mode == "Duel" and not first:FindFirstChild("Request").Active, "Request challenges the exact user once and disables pending actions immediately")
	fireDuel(challengeSignal,{action="sent",targetId=11})
	fireDuel(challengeSignal,{action="declined",targetId=11})
	advance(8.1)
	roster = {{userId=11,username="Renamed",inMatch=false,hasPending=false},{userId=55,username="Delta",inMatch=false,hasPending=false}}
	duelUi:requestPlayerListUpdate(true)
	check(not duelUi.renderedEntries[22] and not duelUi.renderedEntries[33] and duelUi.renderedEntries[55], "Departed rows are removed and new players are added")
	check(first:FindFirstChild("Username").Text == "Renamed" and portrait.BackgroundColor3 == color and first:FindFirstChild("Request").Active, "Name/availability refresh retains the same portrait color and releases cooldown")
	pressDuel(lobby,"Quit")
	advance(0.7)
	check(not lobby.Visible and modalFrames.BackgroundTransparency == 1, "DuelLobby Quit closes its frame and clears the shared backdrop")
	local oldReads = reads
	duelUi:requestPlayerListUpdate(true)
	check(reads == oldReads, "Hidden Duel lobby does not poll for players")
	duelUi:showLobby()
	check(duelUi.renderedEntries[11] ~= first and not sample.Visible and sample.Parent == assets, "Reopening starts new row colors without moving or displaying the source template")
	duelUi:renderLobby({ { userId = -3000000000, username = "milo", isBot = true, thumbnailImage = "rbxassetid://verified-bot" } })
	local botRow = duelUi.renderedEntries[-3000000000]
	check(botRow and botRow:FindFirstChild("Username").Text == "milo" and botRow:FindFirstChild("Request").Active, "Declared bots fill Duel list rows with enabled challenges")
	check(botRow:FindFirstChild("Mugshot").Image == "rbxassetid://verified-bot" and not botRow:FindFirstChild("Mugshot"):FindFirstChild("Profile").Visible, "Bot list mugshots show the verified image without the tutorial placeholder")
	local rate = add(botRow, "TextLabel", "WinRate")
	duelUi:renderLobby({ { userId = -3000000000, username = "milo", isBot = true, thumbnailImage = "rbxassetid://verified-bot", duel = { wins = 2, losses = 1 } } })
	check(rate.Text == "67% Win Rate" and rate.Visible, "An authored lobby WinRate label uses the bot's server record")
	pressDuel(botRow, "Request")
	check(requests[#requests].id == -3000000000 and requests[#requests].mode == "Duel", "Bot Request forwards its exact server identity")
	fireDuel(challengeSignal,{action="error",targetId=-3000000000})

	duelUi:hideLobby()
	advance(0.7)
end)()

fireDuel(challengeSignal,{action="received",challengerId=66,challengerUsername="Challenger"})
advance(0.5)
check(duelRequestFrame.Visible and duelRequestFrame.Size == rbx.UDim2.fromScale(0.33,0.33), "New DuelRequest opens as an outer modal")
check(duelRequestFrame:FindFirstChild("Title").Text == "1V1 REQUEST" and duelRequestFrame:FindFirstChild("UserName").Text == "@Challenger", "Request writes its title and exact UserName without fallback labels")
check(duelRequestFrame:FindFirstChild("Mugshot").Image == "rbxthumb://type=AvatarHeadShot&id=66&w=150&h=150", "Request displays the current challenger's Roblox headshot")
pressDuel(duelRequestFrame,"Green")
pressDuel(duelRequestFrame,"Green")
pressDuel(duelRequestFrame,"Red")
check(#duelReplies == 1 and duelReplies[1] == true and not duelRequestFrame.Visible, "Green accepts once and closes; repeated or opposite clicks cannot resend")
fireDuel(challengeSignal,{action="received",challengerId=77,challengerUsername="Next"})
pressDuel(duelRequestFrame,"Red")
check(#duelReplies == 2 and duelReplies[2] == false, "Red declines the current request")
fireDuel(challengeSignal,{action="received",challengerId=88,challengerUsername="Newest"})
fireDuel(challengeSignal,{action="expired",challengerId=77})
check(duelRequestFrame.Visible, "Older challenger's expiry cannot hide the current request")
fireDuel(challengeSignal,{action="expired",challengerId=88})
check(not duelRequestFrame.Visible, "Expired incoming request closes automatically")
fireDuel(matchSignal,{action="countdown",matchId="first"})
fireDuel(matchSignal,{action="result",matchId="old",isWinner=true})
check(duelUi.inDuel and not duelOutcomeFrame.Visible, "Stale result cannot end a newer Duel or show its popup")
fireDuel(matchSignal,{action="result",matchId="first",isWinner=true,foundCount=10,wordCount=10,xpEarned=920,theme="Sports"})
advance(0.5)
check(duelOutcomeFrame.Visible and duelOutcomeFrame.Size == rbx.UDim2.fromScale(0.33,0.33), "Duel outcome stays visible instead of hiding its parent through the old XP lookup")
check(duelOutcomeFrame:FindFirstChild("Title").Text == "YOU WON!" and duelOutcomeFrame:FindFirstChild("WinnerIcon").Visible and not duelOutcomeFrame:FindFirstChild("LoserIcon").Visible, "Winning outcome shows only WinnerIcon")
advance(4)
check(duelOutcomeFrame:FindFirstChild("Words").Text == "10/10 Words" and duelOutcomeFrame:FindFirstChild("XPWon").Text == "+920 XP", "Duel outcome displays server counts and earned XP")
check(duelOutcomeFrame:FindFirstChild("LevelTheme").Text == "Sports | 1v1" and duelFill.Size.X.Scale >= 0.1, "Duel theme and current progress bar populate")
fireDuel(matchSignal,{action="result",matchId="first",isWinner=false})
check(duelOutcomeFrame:FindFirstChild("WinnerIcon").Visible, "Duplicate result cannot repaint a shown win as a loss")
duelUi:updateOutcome({progression={level=4,xp=160,xpToNextLevel=800}})
advance(0.36)
check(duelFill.BackgroundColor3 == rbx.Color3.fromRGB(255,211,92), "Duel XP fill shares the gold level-up effect")
advance(1.1)
check(math.abs(duelFill.Size.X.Scale-0.1)<0.00001 and duelOutcomeFrame:FindFirstChild("XPWon").Text == "+920 XP", "Late snapshots refresh progress without altering earned match XP")
pressDuel(duelOutcomeFrame,"Home")
pressDuel(duelOutcomeFrame,"Home")
check(#duelHomes == 1 and duelHomes[1] == "first" and not duelOutcomeFrame.Visible, "Home returns once with the completed match identity")
fireDuel(matchSignal,{action="countdown",matchId="second"})
fireDuel(matchSignal,{action="forfeit",matchId="second",isWinner=false,youQuit=true,foundCount=2,wordCount=10,xpEarned=140})
check(duelOutcomeFrame:FindFirstChild("Title").Text == "YOU LOST!" and not duelOutcomeFrame:FindFirstChild("WinnerIcon").Visible and duelOutcomeFrame:FindFirstChild("LoserIcon").Visible, "Loss and forfeit use LoserIcon and hide the previous winner icon")
check(duelOutcomeFrame:FindFirstChild("Home").Text == "authored-home" and duelOutcomeFrame:FindFirstChild("WinnerIcon").Image == "authored:WinnerIcon", "Duel rendering preserves authored buttons and icon images")
;(function()
 fireDuel(matchSignal,{action="countdown",matchId="rematch-ui"})
 fireDuel(matchSignal,{action="result",matchId="rematch-ui",isWinner=true,foundCount=3,wordCount=7,xpEarned=100,rematchAvailable=true})
 local button, home = duelOutcomeFrame:FindFirstChild("Rematch"), duelOutcomeFrame:FindFirstChild("Home")
 check(not button.Visible and home.Position == rbx.UDim2.fromScale(0.764,0.873), "Available rematch reserves the side-by-side Home position during reveal")
 advance(5)
 check(button.Visible and button:FindFirstChild("TextLabel").Text == "Rematch (0/2)", "Rematch pops in as a final outcome action")
 local votes = 0
 duelUi.remotes.rematch = {FireServer=function(_,id) check(id=="rematch-ui", "Rematch sends exact result identity") votes+=1 end}
 for _=1,2 do for _,fn in ipairs(button.Activated.callbacks) do fn() end end
 check(votes == 1, "Rapid Rematch clicks send only one vote")
 fireDuel(matchSignal,{action="rematch",matchId="rematch-ui",available=true,count=1})
 check(button:FindFirstChild("TextLabel").Text == "Rematch (1/2)", "Server vote updates Rematch text")
 fireDuel(matchSignal,{action="rematch",matchId="rematch-ui",available=false,count=1})
 check(not button.Visible and home.Position == rbx.UDim2.fromScale(0.5,0.873), "Opponent leaving hides Rematch and centers Home")
end)()
duelUi.remotes.requestPlayerList = {InvokeServer=function() duelUi:destroy() return {{userId=999,username="Stale"}} end}
check(duelUi:requestLatestPlayerList() == nil and next(duelUi.renderedEntries) == nil, "A roster response after teardown cannot recreate old entries");
(function()
	local previousFind = storage.FindFirstChild
	local names = require("../src/shared/network/NetworkContract").Legacy.Duel
	local remoteRoot = add(assets, "Folder", "LateDuelRemotes")
	local functions = add(remoteRoot, "Folder", "Functions")
	local events = add(add(remoteRoot, "Folder", "Events"), "Folder", "Duel")
	local replicated, starts, requests = false, 0, 0
	storage.FindFirstChild = function(self, name)
		if name == "Remotes" then return replicated and remoteRoot or nil end
		return previousFind(self, name)
	end
	local match = add(events, "RemoteEvent", names.Match)
	match.OnClientEvent = signal()
	add(events, "RemoteEvent", names.Challenge).OnClientEvent = signal()
	add(events, "RemoteEvent", names.Progress).OnClientEvent = signal()
	local listRemote = add(functions, "RemoteFunction", names.RequestPlayerList)
	function listRemote:InvokeServer()
		return {{userId=-3000000000,isBot=true,username="milo",thumbnailImage="rbxassetid://verified-bot"}}
	end
	local request = add(events, "RemoteEvent", names.SendChallenge)
	function request:FireServer(id)
		requests += 1
		check(id == -3000000000, "Recovered Request sends the bot identity")
		fireDuel(match.OnClientEvent, {action="countdown",matchId="late-remote-bot"})
	end
	local late = DuelFeature.new({onCountdown=function() starts += 1 end})
	late.metaUi = modalUi
	late:resolveElements(modalMain)
	late:resolveRemotes()
	late:connectRemotes()
	late:showLobby()
	check(next(late.renderedEntries) == nil and late.remotes.requestPlayerList == nil, "Lobby can bind before Duel remotes replicate")
	replicated = true
	late:requestPlayerListUpdate(true)
	local botRow = late.renderedEntries[-3000000000]
	check(botRow and botRow:FindFirstChild("Request").Active, "A later refresh discovers remotes and displays requestable bots")
	late:connectRemotes()
	late:connectRemotes()
	check(#match.OnClientEvent.callbacks == 1, "Retrying remote binding never duplicates match listeners")
	pressDuel(botRow, "Request")
	check(requests == 1 and starts == 1, "Recovered bot row starts its match exactly once")
	late:destroy()
	check(next(late.boundRemotes) == nil and not late.lobbyConnectionsBound, "Teardown clears remote binding guards for future binds")
	storage.FindFirstChild = previousFind
	remoteRoot:Destroy()
end)()

end)()
modalUi:hideFrame(shop)
modalUi:destroy()
advance(1)
check(not shop.Visible and shop.Size == rbx.UDim2.fromScale(0, 0), "Destroy cancels modal tweens and their delayed callbacks")
check(modalFrames.BackgroundTransparency == 1, "Destroy cancels backdrop tween and clears dimming")
modalUi.elements = { frames = modalFrames }
modalUi:showFrame(shop)
advance(0.1)
modalUi:hideFrame(shop)
modalUi:destroy()
modalUi.elements = { frames = modalFrames }
modalUi:showFrame(shop)
advance(0.5)
check(shop.Visible and shop.Size == rbx.UDim2.fromScale(0.33, 0.33), "Rebinding the same authored modal cannot revive a previous controller lifetime's close callback")


;(function()
 ui.title, ui.subtitle = nil, nil
 board:Build(puzzle, "Standard", true)
 check(board.grid and ui.timed.Visible, "Board builds with optional game headings absent")
 board:Build(puzzle, "Hardcore", true)
 check(board.mode == "Hardcore" and board.grid, "Hardcore board supports the simplified authored Game hierarchy")
end)()

;(function()
 ui.scoreText, ui.scoreLevel = bindings.scoreText, bindings.scoreLevel
 check(ui.scoreText == scorePanel:FindFirstChild("Score") and ui.scoreLevel == scorePanel:FindFirstChild("Level"):FindFirstChild("Label"), "Score binds the exact authored Score.Score and Score.Level.Label")
 board:Build(puzzle,"Standard",true)
 check(ui.scoreText.Text == "Score: 0" and ui.scoreLevel.Text == "\u{1F451} Level 1", "New board resets the score and crown label")
 board:Progress({{userId=1,foundWords={["1A"]=true},score=2400},{userId=2,foundWords={["1D"]=true},score=9999}})
 local bronze = ui.scoreLevel.TextColor3
 check(ui.scoreText.Text == "Score: 2400" and ui.scoreLevel.Text == "\u{1F451} Level 5", "Only the local server score controls the HUD")
 board:Progress({{userId=1,foundWords={["1A"]=true},score=2500}})
 check(ui.scoreLevel.Text == "\u{1F451} Level 6" and ui.scoreLevel.TextColor3 ~= bronze, "Level six changes the crown colour band")
 board:UpdateScore(5000)
 check(ui.scoreLevel.Text == "\u{1F451} Level 11", "Higher score advances the crown level")
 board:Build(puzzle,"Mini",true)
 check(ui.scoreText.Text == "Score: 0" and ui.scoreLevel.Text == "\u{1F451} Level 1", "Switching modes resets both score labels")
end)()

;(function()
 local effects = shared.ui.UIEffects
 for _, preview in ipairs({{5,rbx.Color3.fromRGB(88,224,255)},{3,rbx.Color3.fromRGB(119,222,176)}}) do
  local width, color = preview[1], preview[2]
  local host = add(assets,"Frame","PreviewHome")
  local frame = add(host,"Frame","Frame1")
  local tiles = {}
  for index=1,width*width do
   tiles[index] = add(frame,index == 1 and "ImageLabel" or "Frame",index%2==0 and tostring(index) or "tile"..index)
   add(tiles[index],"TextLabel","Letter").Text = "A"
  end
  local animation = effects.CreateHomeTilePreview(frame,width,color,0)
  local seen, previous, paths, colored, faded = {}, "", 0, false, false
  local idleFrames, longestIdle = 0, 0
  for tick=1,2400 do
   animation:Step(1/60,true) advance(1/60)
   if #animation.path > 0 then
    idleFrames = 0
    local signature = table.concat(animation.path,":")
    if signature ~= previous then
     paths += 1 previous = signature seen[signature] = true
     check(width==3 and #animation.path==3 or width==5 and #animation.path==5,"Mini sweeps three cells; Standard sweeps five cells")
     local visited = {}
     for index,cell in ipairs(animation.path) do
      check(cell>=1 and cell<=width*width and not visited[cell],"Preview path uses unique in-bounds cells")
      visited[cell] = true
      if index > 1 then
       local prior = animation.path[index-1]
       check((cell-prior==1 or cell-prior==width) and cell-prior==animation.path[2]-animation.path[1],"Preview is one straight Across/Down entry")
      end
     end
    end
   else
    idleFrames += 1 longestIdle = math.max(longestIdle,idleFrames)
    local white = true
    for _,tile in ipairs(tiles) do white = white and tile.BackgroundColor3 == rbx.Color3.new(1,1,1) end
    faded = faded or (paths>0 and white)
   end
   for _,tile in ipairs(tiles) do colored = colored or tile.BackgroundColor3 == color end
  end
  check(paths>=10 and colored and faded and longestIdle<=1,"Each preview continuously loops without a long rest after fading white")
  host.Visible = false
  animation:Step(1/60,true) advance(1)
  for _,tile in ipairs(tiles) do check(tile.BackgroundColor3==rbx.Color3.new(1,1,1) and tile:FindFirstChild("Letter").Text=="A","Hidden Home cancels color tweens without changing tile letters") end
  host.Visible = true
  animation:Step(1/60,true)
  check(#animation.path>0,"Returning Home immediately resumes the path animation")
  local replacement = effects.CreateHomeTilePreview(frame,width,color,0)
  animation:Step(1,true)
  check(#animation.path==0,"Rebinding stops the old preview controller")
  replacement:Step(0.1,true) replacement:Destroy() advance(1)
  replacement:Step(0.1,true)
  check(#replacement.path==0 and tiles[1].ImageColor3==rbx.Color3.new(1,1,1),"Destroyed preview cannot restart or leave tinted images")
  host:Destroy()
 end
 check(effects.CreateHomeTilePreview(nil,5,rbx.Color3.new(1,1,1))==nil,"Missing optional preview does not block Home")
end)()

;(function()
 local effects = shared.ui.UIEffects
 local host = add(assets,"Frame","JumboHome")
 local frame = add(host,"Frame","Frame1")
 local grid = add(frame,"UIGridLayout","UIGridLayout")
 grid.CellSize, grid.CellPadding = rbx.UDim2.fromScale(0.3,0.3), rbx.UDim2.fromScale(0.03,0.03)
 grid.FillDirection, grid.FillDirectionMaxCells, grid.SortOrder = rbx.Enum.FillDirection.Horizontal,0,rbx.Enum.SortOrder.Name
 for i=1,9 do
  local tile = add(frame,"Frame","Tile"..i) tile.LayoutOrder = 50+i
  add(tile,"UICorner","UICorner")
  add(tile,"UIStroke","UIStroke")
 end
 local firstTile=frame:FindFirstChild("Tile1")
 firstTile.AnchorPoint,firstTile.Position,firstTile.Size=rbx.Vector2.new(0.2,0.3),rbx.UDim2.fromOffset(7,9),rbx.UDim2.fromScale(0.24,0.25)
 local authoredScale=add(firstTile,"UIScale","AuthoredScale") authoredScale.Scale=0.93
 local originalAnchor,originalPosition,originalTileSize=firstTile.AnchorPoint,firstTile.Position,firstTile.Size
 local originalSize,originalPadding = grid.CellSize,grid.CellPadding
 local function visibleCount()
  local count=0
  for _,tile in ipairs(frame:GetChildren()) do if tile:IsA("GuiObject") and tile.Visible then count+=1 end end
  return count
 end
 local animation = effects.CreateJumboPreview(frame)
 check(visibleCount()==9 and grid.FillDirectionMaxCells==3,"Jumbo starts with the authored nine tiles in a three-column grid")
 check(frame:FindFirstChild("Tile36"):FindFirstChildOfClass("UIStroke") and frame:FindFirstChild("Tile36"):FindFirstChildOfClass("UICorner"),"Extra Jumbo tiles clone authored decoration")
 local observed, morphs = {}, 0
 local wasMorphing = false
 for tick=1,2700 do
  animation:Step(1/60,true) advance(1/60)
  local count = visibleCount()
  observed[count] = true
  if tick<=700 then check(count==9 and grid.CellSize==originalSize,"Jumbo remains still during its long initial pause") end
  check(count==9 or count==36,"Jumbo morphs directly between three-by-three and six-by-six")
  local morphing = grid.Parent ~= frame
  if morphing and not wasMorphing then
   morphs += 1
   check(grid.Parent.Name=="JumboLayoutParking","Grid layout is temporarily parked to avoid snapping moving tiles")
   local moving = false
   for _,tween in ipairs(tweenService.created) do
    if tween.node==frame:FindFirstChild("Tile2") and tween.properties.Position and tween.info.Time==1.6 then moving=true end
   end
   check(moving,"Existing tiles glide to their next positions over a smooth 1.6-second tween")
  end
  wasMorphing=morphing
  if count==36 and not morphing then
   check(grid.FillDirectionMaxCells==6 and math.abs(grid.CellSize.X.Scale-0.1475)<0.00001 and math.abs(grid.CellPadding.X.Scale-0.015)<0.00001,"Settled six-by-six keeps the original footprint and restores layout ownership")
   check(not frame:FindFirstChild("Tile35"):FindFirstChildOfClass("UIScale") and authoredScale.Scale==0.93,"Temporary scales are removed and authored scale is restored when tiles settle")
  end
 end
 check(observed[9] and observed[36] and morphs>=2,"Jumbo smoothly grows and shrinks without intermediate layout snaps")
 -- Interrupt an active morph, rather than only testing cleanup during a rest.
 for _=1,1600 do
  animation:Step(1/60,true) advance(1/60)
  if grid.Parent~=frame then break end
 end
 check(grid.Parent~=frame,"Cleanup fixture reaches a moving grid")
 host.Visible=false
 animation:Step(1/60,true) advance(1)
 check(visibleCount()==9 and grid.Parent==frame and grid.CellSize==originalSize and grid.CellPadding==originalPadding,"Hidden Home cancels active tile tweens, reattaches layout and resets Jumbo")
 host.Visible=true
 local replacement = effects.CreateJumboPreview(frame)
 local tiles=0
 for _,tile in ipairs(frame:GetChildren()) do if tile:IsA("GuiObject") then tiles+=1 end end
 check(tiles==36,"Rebinding cannot accumulate extra Jumbo clones")
 animation:Step(1,true)
 replacement:Destroy() advance(1)
 check(visibleCount()==9 and not frame:FindFirstChild("Tile10") and frame:FindFirstChild("Tile1").LayoutOrder==51,"Cleanup removes generated tiles and restores authored ordering")
 check(firstTile.AnchorPoint==originalAnchor and firstTile.Position==originalPosition and firstTile.Size==originalTileSize and authoredScale.Parent==firstTile and authoredScale.Scale==0.93,"Jumbo teardown restores authored geometry and scale")
 check(grid.Parent==frame and grid.CellSize==originalSize and grid.CellPadding==originalPadding and grid.FillDirectionMaxCells==0 and grid.SortOrder==rbx.Enum.SortOrder.Name and not frame:FindFirstChild("JumboLayoutParking"),"Cleanup restores authored layout and removes temporary parking")
 host:Destroy()
 check(effects.CreateJumboPreview(nil)==nil,"Missing optional Jumbo preview leaves Home usable")
end)()
;(function()
 local controller=MetaController.new({getSnapshot=function() return {hints=0} end})
 controller.remotes={}
 local finished=signal()
 services.MarketplaceService.PromptProductPurchaseFinished=finished
 controller:connectRemoteEvents()
 local before=#prompts
 controller:promptHintPurchase()
 check(controller.hintPurchasePending and #prompts==before+1 and prompts[#prompts]==3714515983 and not controller.elements.shopFrame,"Hint prompts the new product without an authored Shop")
 controller:promptHintPurchase()
 check(#prompts==before+1,"Repeated taps cannot duplicate a pending hint prompt")
 for _,fn in ipairs(finished.callbacks) do fn(999,3714515983,false) fn(players.LocalPlayer.UserId,3573028208,false) end
 check(controller.hintPurchasePending,"Other players and products cannot clear the active hint prompt")
 for _,fn in ipairs(finished.callbacks) do fn(players.LocalPlayer.UserId,3714515983,false) end
 check(not controller.hintPurchasePending,"Cancelling the matching prompt releases input")
 controller:promptHintPurchase()
 for _,fn in ipairs(finished.callbacks) do fn(players.LocalPlayer.UserId,3714515983,true) end
 check(#prompts==before+2 and not controller.hintPurchasePending,"Successful prompt closes without granting hints on the client")
 local prompt=services.MarketplaceService.PromptProductPurchase
 services.MarketplaceService.PromptProductPurchase=function() error("Prompt unavailable") end
 controller:promptHintPurchase()
 check(not controller.hintPurchasePending,"Prompt errors release the guard so a later click can retry")
 services.MarketplaceService.PromptProductPurchase=prompt
 controller:promptHintPurchase()
 check(controller.hintPurchasePending and #prompts==before+3,"Native prompt recovers after an error")
 controller:destroy()
 check(not controller.hintPurchasePending,"Controller teardown cannot leave the purchase input lock behind")
end)()
;(function()
 for _,mode in ipairs({"Standard","Mini","Jumbo","Hardcore","Timed","Tutorial"}) do
  board:Build(puzzle,"Duel")
  check(ui.timed.Position==rbx.UDim2.fromScale(0.5,0.03),"Repeated Duel entry keeps the requested timer position")
  board:Build(puzzle,mode)
  check(ui.timed.Visible and ui.timed.Position==rbx.UDim2.new(0.47,8,0.11,-3),"Leaving Duel restores the authored timer position, including offsets, in "..mode)
 end
end)()
print("BOARD_PRESENTATION_TESTS_PASSED=" .. checks)
