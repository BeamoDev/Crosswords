require("../src/shared/puzzle/PuzzleTests.spec")
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
		return self.props[key]
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
		Activated = signal(), SelectionGained = signal(), Size = rbx.UDim2.fromScale(1, 1),
	} }, meta)
end
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
local shared = { puzzle = { PuzzleEngine = engine }, ui = { WaitForChild = waitForChild },
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
	Instance = { new = instance }, Vector2 = rbx.Vector2, Vector3 = rbx.Vector3, UDim2 = rbx.UDim2, UDim = rbx.UDim, Color3 = rbx.Color3,
	Random = { new = function()
		local index = 0
		return { NextNumber = function(_, minimum, maximum)
			index += 1
			minimum, maximum = minimum or 0, maximum or 1
			return minimum + (maximum - minimum) * ((index * 0.61803398875) % 1)
		end }
	end },
	Enum = rbx.Enum, task = { spawn = function(fn) fn() end, delay = delay },
	TweenInfo = { new = function(time, style, direction, repeats, reverses, delayTime) return { Time = time, DelayTime = delayTime or 0, RepeatCount = repeats, Reverses = reverses } end },
}
shared.ui.UIEffects = luau.load(fs.readFile("src/shared/ui/UIEffects.luau"), { environment = environment })()
local Board = luau.load(fs.readFile("src/client/controllers/BoardController.luau"), { environment = environment })()
local ui = { game = instance("Frame"), screenGui = { IgnoreGuiInset = true }, boardPanel = instance("Frame"),
	wordPanel = instance("Frame"), words = instance("TextLabel"), wordList = instance("ScrollingFrame"),
	title = instance("TextLabel"), subtitle = instance("TextLabel"), duel = instance("Frame"), timed = instance("Frame") }
local allowed, submissions, sounds = true, {}, {}
local board = Board.new(ui, {
	canInteract = function() return allowed end, playSound = function(name) table.insert(sounds, name) end,
	submit = function(word, path) table.insert(submissions, { word = word, path = path }) end,
})
local puzzle = {
	title = "Ocean", words = { "DOG", "CAT" },
	letters = { { "C", "A", "T" }, { "D", "O", "G" } },
	placedWordsByWord = {
		CAT = { path = { { row = 1, column = 1 }, { row = 1, column = 2 }, { row = 1, column = 3 } } },
		DOG = { path = { { row = 2, column = 1 }, { row = 2, column = 2 }, { row = 2, column = 3 } } },
	},
}
board:Build(puzzle, "Standard")
check(not board:Interactive() and board.tiles[1][1].TextTransparency == 1, "Entrance hides letters and locks input")
check(sounds[#sounds] == "Appear", "Entrance plays authored sound")
check(not board:Begin(rbx.Vector2.new(100, 100), { UserInputType = rbx.Enum.UserInputType.MouseButton1 }) and not board.startCell, "Locked board cannot begin pointer gesture during introduction")
advance(0.6)
check(board:Interactive() and board.tiles[1][1].TextTransparency == 0, "Entrance reveals letters and releases input")
check(not board.grid:FindFirstChild("BoardRevealScale"), "Entrance removes its temporary scale")
check(ui.boardPanel:FindFirstChildOfClass("UIAspectRatioConstraint").AspectRatio == 1.5, "Rectangular grid aspect")
check(ui.boardPanel.Position == rbx.UDim2.fromScale(0.39, 0.5), "Rectangular board position")
check(ui.wordPanel.Position == rbx.UDim2.fromScale(0.75, 0.5), "Rectangular word panel position")
check(ui.title.Text == "THEMES" and ui.subtitle.Text == "Ocean" and ui.subtitle.Visible, "Themed title")
check(ui.words.Text == "0/2" and #ui.wordList:GetChildren() == 2, "Authored word rows cloned")
local function countChildren(root, name)
	local count = 0
	for _, child in ipairs(root:GetChildren()) do if child.Name == name then count += 1 end end
	return count
end
local row = board.rows.CAT
check(row:FindFirstChild("BreakLine").Visible and row:FindFirstChild("Word").Text == "CAT" and not row:FindFirstChild("PlayerTemplate").Visible, "Unsolved row keeps its divider without a strike-through")
board:Progress({ { userId = 1, foundWords = {} }, { userId = 2, foundWords = { CAT = true } } })
check(ui.words.Text == "0/2" and row:FindFirstChild("BreakLine").Visible and row:FindFirstChild("Word").Text == "CAT" and row.LayoutOrder > board.rows.DOG.LayoutOrder, "Other finds keep the divider without striking or moving own word")
check(countChildren(board.grid, "WordSpark") == 0 and #sounds == 1, "Opponent finds do not trigger own success feedback")
local otherPortrait = row:FindFirstChild("FoundPanel"):FindFirstChild("Finder_2")
check(otherPortrait and otherPortrait.Image == "headshot:2" and otherPortrait.Visible, "Other finder gets a mugshot")
board:Progress({ { userId = 1, foundWords = {} }, { userId = 2, foundWords = { CAT = true } }, { userId = -1000000000, isBot = true, thumbnailImage = "bot-avatar", foundWords = { CAT = true } } })
check(row:FindFirstChild("FoundPanel"):FindFirstChild("Finder_-1000000000").Image == "bot-avatar", "Bot finder uses its resolved Roblox image instead of its simulated ID")
check(ui.words.Text == "0/2" and row:FindFirstChild("Word").Text == "CAT", "Bot solves never solve the local player's word")
board:Progress({ { userId = 1, foundWords = { CAT = true } }, { userId = 2, foundWords = { CAT = true } } })
check(ui.words.Text == "1/2" and row:FindFirstChild("BreakLine").Visible and row:FindFirstChild("Word").RichText and row:FindFirstChild("Word").Text == "<s>CAT</s>" and row.LayoutOrder < board.rows.DOG.LayoutOrder, "Own find strikes the word and moves it above an earlier unsolved row")
check(row:FindFirstChild("FoundPanel"):FindFirstChild("Finder_1") ~= nil, "Own mugshot is shown")
check(board.lines.Found_CAT and board.lines.Found_CAT.Visible, "Own found path persists on board")
check(countChildren(board.grid, "WordSpark") == 10 and sounds[#sounds] == "NotificationHigh", "Confirmed own word gets particles and success sound")
local soundsAfterFind = #sounds
board:Progress({ { userId = 1, foundWords = { CAT = true } }, { userId = 2, foundWords = { CAT = true } } })
check(#sounds == soundsAfterFind and countChildren(board.grid, "WordSpark") == 10, "Repeated snapshots do not replay success effects")
advance(0.5)
check(countChildren(board.grid, "WordSpark") == 0, "Success particles clean up")
local color = otherPortrait.BackgroundColor3
local _, saturation, value = color:ToHSV()
check(saturation >= 0.75 and saturation <= 0.85 and value >= 0.85 and value <= 0.95, "Portrait background uses about 80 percent saturation")
check(board:PortraitColor(2) == color, "Portrait color stays fixed within a round")
check(otherPortrait:FindFirstChildOfClass("UIStroke").Color == color:Lerp(rbx.Color3.new(), 0.3), "Portrait stroke is darker")
board:Progress({ { userId = 1, foundWords = { CAT = true }, hintedWords = { DOG = true } } })
check(row:FindFirstChild("FoundPanel"):FindFirstChild("Finder_2") == nil, "Departed finder removed")
check(board.lines.Hint_DOG and board.lines.Hint_DOG.Visible, "Hints preserve path visualization");
(function()
	local pulse = board.hintPulses.DOG
	check(type(pulse) == "function" and board.lines.Hint_DOG.BackgroundTransparency == 0.30, "Hint starts its own pulse")
	advance(0.85)
	check(board.lines.Hint_DOG.BackgroundTransparency == 0.78, "Hint fades away from the solid found-word appearance")
	board:RefreshLines()
	check(board.hintPulses.DOG == pulse and board.lines.Hint_DOG.BackgroundTransparency == 0.78, "Refresh/drag updates preserve the pulse instead of restarting it")
	local pulseTween
	for _, tween in ipairs(tweenService.created) do
		if tween.node == board.lines.Hint_DOG and tween.info.RepeatCount == -1 then pulseTween = tween end
	end
	check(pulseTween and pulseTween.info.Reverses == true, "Hint tween repeats in both directions continuously")
	ui.game.Visible = false
	check(board.hintPulses.DOG == nil, "Hiding Game cancels hint pulse work")
	ui.game.Visible = true
	check(board.hintPulses.DOG ~= nil and board.hintPulses.DOG ~= pulse, "Showing the same board starts a fresh hint pulse")

end)()

local input = { UserInputType = "MouseButton1" }
board:Begin(rbx.Vector2.new(100, 300), input)
local initialDragPosition = board.lines.Selection.Position
board:Move(rbx.Vector2.new(300, 300))
check(board.lines.Selection.Position == initialDragPosition and #board.selection == 2, "Logical target advances before the visual tween")
advance(0.03)
board:Move(rbx.Vector2.new(500, 300))
advance(0.055)
check(board.lines.Selection.Position == initialDragPosition, "Superseded drag tween cannot move the highlight")
board:Move(rbx.Vector2.new(500, 300))
advance(0.03)
check(board.lines.Selection.Position == rbx.UDim2.fromOffset(300, 300), "Same-cell events do not restart the tween")
board:Move(rbx.Vector2.new(300, 300))
board:Move(rbx.Vector2.new(500, 300))
local dragColor = board.lines.Selection.BackgroundColor3
check(dragColor ~= board.lines.Found_CAT.BackgroundColor3, "Next drag uses a different vibrant color")
check(board.lines.Selection.Size.Y.Offset == rbx.UDim2.fromOffset(0, 200 * 0.68 * 1.15 * 1.20 * 0.85).Y.Offset, "Selection thickness and rounded caps shrink by 15 percent")
board:Finish()
check(#submissions == 1 and submissions[1].word == "DOG", "Arithmetic pointer selection submits matching path")
check(not board.startCell and not board.activeInput, "Release clears gesture")
board:Begin(rbx.Vector2.new(500, 100), input)
local restartedPosition = board.lines.Selection.Position
advance(0.1)
check(board.lines.Selection.Position == restartedPosition, "Released drag tween cannot move a new gesture")
board:Cancel()
board:Progress({ { userId = 1, foundWords = { CAT = true, DOG = true } } })
check(board.lines.Found_DOG.BackgroundColor3 == dragColor, "Validated word preserves its drag color")
check(board.hintPulses.DOG == nil and not board.lines.Hint_DOG.Visible, "Solving the hinted word cancels its pulse and hides its hint path")
check(board.lines.Found_DOG.BackgroundColor3 ~= board.lines.Found_CAT.BackgroundColor3, "Found words keep distinct colors")
check(sounds[#sounds] == "Victory", "Completion plays victory sound")
local ownPortraitColor = row:FindFirstChild("FoundPanel"):FindFirstChild("Finder_1").BackgroundColor3
check(board.rows.DOG:FindFirstChild("FoundPanel"):FindFirstChild("Finder_1").BackgroundColor3 == ownPortraitColor, "Same player uses one portrait color across words")
allowed = false
check(not board:Begin(rbx.Vector2.new(100, 300), input), "Central interaction lock blocks drag")
allowed = true
local square = table.clone(puzzle)
square.letters = { { "C", "A", "T" }, { "D", "O", "G" }, { "X", "Y", "Z" } }
board:Build(square, "Duel")
check(board:PortraitColor(1) ~= ownPortraitColor, "New round chooses a new portrait color")
check(ui.boardPanel:FindFirstChildOfClass("UIAspectRatioConstraint").AspectRatio == 1, "Square aspect")
check(ui.boardPanel.Position == rbx.UDim2.fromScale(0.387, 0.5) and ui.wordPanel.Position == rbx.UDim2.fromScale(0.667, 0.5), "Square positions")
check(ui.title.Text == "1V1" and not ui.subtitle.Visible and ui.duel.Visible, "Duel header")
local youWinRate = add(ui.duel, "TextLabel", "YouWinRate")
local enemyWinRate = add(ui.duel, "TextLabel", "EnemyWinRate")
board:DuelPlayers(2, "Bob", nil, { wins = 3, losses = 1 }, { wins = 1, losses = 3 })
check(youWinRate.Visible and enemyWinRate.Visible and youWinRate.Text == "75% Win Rate" and enemyWinRate.Text == "25% Win Rate", "Duel HUD shows both saved win percentages");
(function()
	local mugshot = add(ui.duel, "ImageLabel", "EnemyMugshot")
	local placeholder = add(mugshot, "ImageLabel", "Profile")
	board:DuelPlayers(-3000000000, "milo", "rbxassetid://verified-bot", {wins=0,losses=0}, {wins=2,losses=1})
	check(youWinRate.Text == "0% Win Rate" and enemyWinRate.Text == "67% Win Rate", "Zero-match and bot records render finite rounded percentages")
	board:DuelWinRates({wins=1,losses=0}, {wins=2,losses=2})
	check(youWinRate.Text == "100% Win Rate" and enemyWinRate.Text == "50% Win Rate", "Completed matches refresh visible win-rate labels")
	check(mugshot.Image == "rbxassetid://verified-bot" and not placeholder.Visible, "Duel HUD uses the supplied bot portrait instead of a negative account ID")
 local score = add(ui.duel, "TextLabel", "YouScore")
 score.TextColor3, score.Rotation = rbx.Color3.fromRGB(3,36,66), 2
 local originalColor = score.TextColor3
 local scale = add(score, "UIScale", "AuthoredScale")
 scale.Scale = 0.9
 board:DuelScores(0,0)
 board:DuelScores(1,0)
 advance(0.17)
 check(score.Text == "1" and score.TextColor3 == rbx.Color3.fromRGB(43,225,58) and score.Rotation == 7 and scale.Scale > 0.9, "Duel score change flashes green, grows and tilts")
 local cancel = board.scoreEffects.YouScore
 board:DuelScores(1,0)
 check(board.scoreEffects.YouScore == cancel, "Duplicate progress does not restart the score effect")
 board:DuelScores(2,0)
 advance(0.5)
 check(score.TextColor3 == originalColor and score.Rotation == 2 and scale.Scale == 0.9, "Rapid Duel score changes restore authored color, rotation and scale")
 board:DuelScores(3,0)
 board:DuelPlayers(-3000000000, "milo", "rbxassetid://verified-bot")
 advance(0.5)
 check(score.Rotation == 2 and score.TextColor3 == originalColor and scale.Scale == 0.9, "New Duel cancels outstanding score effects")
	board:Progress({ { userId = -3000000000, isBot = true, thumbnailImage = "rbxassetid://verified-bot", foundWords = { CAT = true } } })
	local finder = board.rows.CAT:FindFirstChild("FoundPanel"):FindFirstChild("Finder_-3000000000")
	check(finder and finder.Image == "rbxassetid://verified-bot", "Duel bot finder portraits retain the verified avatar")
end)()

board:Build(square, "Standard", true)
board:Progress({{userId=1,foundWords={CAT=true}}})
check(not board.rows.CAT:FindFirstChild("FoundPanel"):FindFirstChild("Finder_1") and board.found.CAT, "Solo Classic retains solved words without finder portraits")
check(#ui.wordList:GetChildren() == 2, "Rebuilding does not duplicate word rows")
advance(0.3)
board:Build(square, "Timed")
advance(0.3)
check(not board:Interactive(), "Old reveal completion cannot unlock a newer board")
advance(0.3)
check(board:Interactive(), "New board unlocks after its own reveal")
local wrongSounds = #sounds
local inputCount = #submissions
board:Begin(rbx.Vector2.new(100, 330), input)
board:Move(rbx.Vector2.new(500, 330))
board:Finish()
check(#submissions == inputCount and #sounds == wrongSounds + 1 and sounds[#sounds] == "Error2", "Wrong word plays Error2 without submitting")
check(countChildren(board.grid, "WrongWordFeedback") == 1, "Wrong selection retains a red shaking line")
check(board:Begin(rbx.Vector2.new(100, 66), input), "Wrong feedback does not block next gesture")
local newDrag = board.lines.Selection.BackgroundColor3
advance(0.5)
check(countChildren(board.grid, "WrongWordFeedback") == 0 and board.startCell ~= nil, "Wrong effect cleans up without cancelling new drag")
check(board.lines.Selection.BackgroundColor3 == newDrag, "Old wrong effect cannot recolor the next gesture")
board:Cancel()
board:ActivateCell({ row = 1, column = 1 })
check(board.lines.Selection.BackgroundColor3 ~= newDrag, "Keyboard/gamepad selection advances the vibrant palette")
board:KeyboardMove(0, 1)
check(board.cursor.column == 2 and #board.selection == 2 and focus.SelectedObject == nil, "Keyboard movement extends the word path without setting UI focus")
board:Cancel()
check(ui.title.Text == "TIMED" and not ui.subtitle.Visible and ui.timed.Visible, "Timed header presentation")
board:Progress({ { userId = 1, foundWords = { CAT = true, DOG = true } } })
check(board.completed and not board:Interactive(), "Completion locks further selections")
local invalidPaths = {}
board.callbacks.invalidSelection = function(path) table.insert(invalidPaths, path) end
board:Build(square, "Hardcore")
advance(0.6)
check(ui.title.Text == "HARDCORE" and ui.subtitle.Text == "One wrong word ends the round", "Hardcore explains its loss rule")
board:Begin(rbx.Vector2.new(100, 330), input)
board:Move(rbx.Vector2.new(500, 330))
board:Finish()
check(#invalidPaths == 1 and #invalidPaths[1] == 3, "Hardcore sends full incorrect path for server validation")
check(sounds[#sounds] == "Error2" and not board.busy, "Hardcore retains wrong effects and releases pending request")
for _, mode in ipairs({ "Mini", "Jumbo" }) do
	board:Build(square, mode)
	advance(0.6)
	check(ui.title.Text == string.upper(mode) and ui.subtitle.Visible, "Solo mode header and theme")
	board:Begin(rbx.Vector2.new(100, 330), input)
	board:Move(rbx.Vector2.new(500, 330))
	board:Finish()
	check(#invalidPaths == 1, "Casual solo mistakes do not submit a loss")
end
local Interface = luau.load(fs.readFile("src/client/controllers/InterfaceController.luau"), { environment = environment })();
(function()
	local panel = add(assets, "Frame", "TimedModeTest")
	local bar = add(panel, "Frame", "FillBar")
	local fill = add(bar, "Frame", "Fill")
	local label = add(panel, "TextLabel", "TimeLeft")
	local icon = add(panel, "ImageLabel", "Icon")
	icon.Image = "authored-timer-icon"
	fill.Size = rbx.UDim2.new(0.7, 3, 0.8, 2)
	local timerUi = { timedTimeLeft = label, timedFill = fill }
	Interface.UpdateTimedTimer(timerUi, nil, nil, true)
	check(label.Text == "--:--" and fill.Size.X.Scale == 1 and fill.BackgroundColor3 == rbx.Color3.fromRGB(75,202,53), "Unconnected Timed UI resets to full green without inventing a countdown")
	Interface.UpdateTimedTimer(timerUi, 120, 120)
	check(label.Text == "02:00" and fill.Size.Y == rbx.UDim.new(0.8,2), "Timed label formats seconds and preserves authored fill height")
	Interface.UpdateTimedTimer(timerUi, 60, 120)
	advance(0.18)
	check(fill.Size.X.Scale == 0.5 and fill.BackgroundColor3 == rbx.Color3.fromRGB(255,196,54) and label.Text == "01:00", "Half time gives a half-width yellow fill")
	Interface.UpdateTimedTimer(timerUi, 30, 120)
	advance(0.18)
	check(fill.Size.X.Scale == 0.25 and fill.BackgroundColor3 == rbx.Color3.fromRGB(255,196,54):Lerp(rbx.Color3.fromRGB(202,61,51),0.5), "Low time blends smoothly toward red")
	Interface.UpdateTimedTimer(timerUi, 0, 120)
	advance(0.18)
	check(label.Text == "00:00" and fill.Size.X.Scale == 0 and fill.BackgroundColor3 == rbx.Color3.fromRGB(202,61,51), "Expired time empties the fill and reaches red")
	Interface.UpdateTimedTimer(timerUi, -5, 120)
	check(label.Text == "00:00", "Negative remaining time cannot display a negative countdown")
	Interface.UpdateTimedTimer(timerUi, 90, 120)
	Interface.UpdateTimedTimer(timerUi, nil, nil, true)
	advance(0.3)
	check(fill.Size.X.Scale == 1 and label.Text == "--:--" and icon.Image == "authored-timer-icon", "Reset cancels stale tweens and preserves the authored icon")
	Interface.UpdateTimedTimer(timerUi, 30, 0)
	check(label.Text == "--:--", "Invalid duration cannot divide by zero or start a fake timer")
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
Interface.UpdateLevelBars(bars, { level = 1, xp = 0, xpToNextLevel = 500, nextLevelRewardHints = 2 })
check(gameBar:FindFirstChild("NextLevelTitle").Text == "LEVEL 2 REWARD" and gameBar:FindFirstChild("NextLevelRewardTitle").Text == "+2 Hints", "Game bar previews level 2 and its two hints")
check(rewardIcon.Visible and rewardIcon.Image == "authored-hint-icon", "Reward shows the authored hint icon")
Interface.UpdateLevelBars(bars, { level = 2, xp = 300, xpToNextLevel = 600, nextLevelRewardHints = 1 })
check(gameBar:FindFirstChild("NextLevelTitle").Visible and gameBar:FindFirstChild("NextLevelTitle").Text == "LEVEL 3 REWARD" and gameBar:FindFirstChild("NextLevelRewardTitle").Text == "+1 Hint", "Reward preview updates after leveling up")
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
Interface.UpdateLevelBars(liveBars, { level = 8, xp = 100, xpToNextLevel = 1200 })
advance(0.51)
check(not liveBars.levelBarFeedback[liveGame].celebrating, "Initial loaded level does not replay old level-ups")
Interface.UpdateLevelBars(liveBars, { level = 9, xp = 0, xpToNextLevel = 1300 })
local celebration = liveBars.levelBarFeedback[liveGame]
advance(0.2)
Interface.UpdateLevelBars(liveBars, { level = 10, xp = 700, xpToNextLevel = 1400 })
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
add(standard,"TextButton","Play")
add(standard,"TextLabel","Waiting")
add(home,"Frame","ButtonBar")
local boardPanel=add(gameFrame,"Frame","BoardPanel")
local wordsPanel=add(gameFrame,"Frame","WordPanel")
add(wordsPanel,"TextLabel","Words")
add(add(wordsPanel,"Frame","Container"),"ScrollingFrame","ScrollingFrame")
for _, name in ipairs({"Title","Subtitle"}) do add(gameFrame,"TextLabel",name) end
for _, name in ipairs({"Hint","Exit"}) do add(gameFrame,"TextButton",name) end
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
check(bindings.queueSubtitle.Text=="Classic Mode (15s)", "Countdown uses Classic Mode label and ceiling")
Interface.UpdateQueueTimer(bindings, -1)
check(bindings.queueSubtitle.Text=="Classic Mode (0s)", "Countdown never becomes negative")
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
check(levelScale.Scale<0.85 and background.Position==originalPositions[background] and hiddenMode.Position==originalPositions[hiddenMode], "Entrance respects authored scales, background and hidden modes")
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
advance(0.61)
check(gameFrame.Visible and not home.Visible and gameFrame:FindFirstChild("Exit"):FindFirstChildOfClass("UIScale").Scale==0, "Exit control shrinks first in reversed stagger")
check(boardPanel.Position==originalPositions[boardPanel], "Board leaves after controls in reversed stagger")
advance(0.24)
check(homeCovered==0 and gameFrame.Visible and boardPanel.Position~=originalPositions[boardPanel], "Game reverses before screen switches")
check(levelScale.Scale<0.85 and background.Position==originalPositions[background] and hiddenMode.Position==originalPositions[hiddenMode], "Exit preserves background and hidden mode geometry")
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
	local panel = board.rows.CAT:FindFirstChild("FoundPanel")
	local count = 0
	for _, child in ipairs(panel:GetChildren()) do
		if child.Name:sub(1, 7) == "Finder_" then count += 1 end
	end
	check(count == expectedCount, "Finder portraits never exceed three")
	local extra = panel:FindFirstChild("Exceeds")
	check(expectedExtra == 0 and extra == nil or expectedExtra > 0 and extra and extra:FindFirstChild("TextLabel").Text == "+" .. expectedExtra, "Exceeds shows the exact additional finder count")
	check(ui.words.Text == "0/2", "Overflow finders do not solve the local word")
	return extra
end
checkFinders(0, 0)
for id = 2, 13 do
	table.insert(crowd, {userId = id, foundWords = {CAT = true}, isBot = id % 2 == 0, thumbnailImage = "test-avatar"})
	checkFinders(math.min(id - 1, 3), math.max(0, id - 4))
end
local overflow = checkFinders(3, 9)
check(checkFinders(3, 9) == overflow, "Repeated snapshots reuse the Exceeds clone")
while #crowd > 1 do
	table.remove(crowd)
	checkFinders(math.min(#crowd - 1, 3), math.max(0, #crowd - 4))
end
local finishers = {
	{userId = 1, foundWords = {CAT = true, DOG = true}, foundOrder = {CAT = 40, DOG = 5}},
	{userId = 2, foundWords = {CAT = true, DOG = true}, foundOrder = {CAT = 30, DOG = 15}},
	{userId = 3, foundWords = {CAT = true, DOG = true}, foundOrder = {CAT = 10, DOG = 25}},
	{userId = 4, foundWords = {CAT = true, DOG = true}, foundOrder = {CAT = 20, DOG = 35}},
}
board:Progress(finishers)
local catPanel, dogPanel = board.rows.CAT:FindFirstChild("FoundPanel"), board.rows.DOG:FindFirstChild("FoundPanel")
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
check(feedbackScale.Scale == 0.8, "Cross-device button pulse restores its authored scale")
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
for _, category in ipairs({ "WordsFound", "1v1Wins" }) do
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
	for _, name in ipairs({ "WordsFound", "1v1Wins" }) do add(panel, "TextButton", name) end
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
	{progression={level=6,xp=400,xpToNextLevel=1000}})
check(gameOutcome.Visible and outcomeFill.Size.X.Scale >= 0.1, "Outcome opens through the modal system and never has an empty sliver")
check(not gameOutcome:FindFirstChild("Words").Visible and not gameOutcome:FindFirstChild("XPWon").Visible and not outcomeFill.Parent.Visible and not gameOutcome:FindFirstChild("Play").Visible, "Outcome starts with count-up stages and bottom actions hidden")
for _, fn in ipairs(gameOutcome:FindFirstChild("Play").Activated.callbacks) do fn() end
check(#outcomeActions == 0, "Hidden bottom action cannot interrupt the reveal")
advance(0.51)
check(gameOutcome:FindFirstChild("Words").Text == "2/10 Words" and not gameOutcome:FindFirstChild("XPWon").Visible, "Word count advances before XP is shown")
advance(0.80)
check(gameOutcome:FindFirstChild("Words").Text == "10/10 Words" and gameOutcome:FindFirstChild("XPWon").Visible and gameOutcome:FindFirstChild("XPWon").Text ~= "+220 XP" and not outcomeFill.Parent.Visible, "XP reveals and rapidly counts only after the words finish")
advance(0.91)
check(outcomeFill.Parent.Visible and math.abs(outcomeFill.Size.X.Scale - 0.18) < 0.00001 and gameOutcome:FindFirstChild("CurrentXP").Text == "Level 6 | 180 / 1000 XP", "Progress bar reveals at pre-award XP before filling")
check(not gameOutcome:FindFirstChild("Home").Visible, "Bottom buttons wait until the bar has filled")
advance(1.5)
check(gameOutcome:FindFirstChild("Play").Visible and gameOutcome:FindFirstChild("Home").Visible and Interface.OutcomeButtonsReady(gameOutcome), "Bottom actions pop in last and become ready")
check(gameOutcome:FindFirstChild("Title").Text == "Complete!" and gameOutcome:FindFirstChild("LevelTheme").Text == "Countries | Themes", "Outcome displays the completed theme and mode")
check(gameOutcome:FindFirstChild("Words").Text == "10/10 Words" and gameOutcome:FindFirstChild("XPWon").Text == "+220 XP", "Outcome displays round words and server-earned XP")
check(gameOutcome:FindFirstChild("CurrentXP").Text == "Level 6 | 400 / 1000 XP" and math.abs(outcomeFill.Size.X.Scale - 0.4) < 0.00001, "Outcome shows the current saved level progress")
check(outcomeIcon.Image == "authored-thumbs-up" and gameOutcome.Size == rbx.UDim2.fromScale(0.33, 0.33), "Outcome preserves its authored icon and uses the new modal size")
modalUi:updateGameOutcome({progression={level=7,xp=220,xpToNextLevel=1100}})
advance(0.36)
check(outcomeFill.Size == rbx.UDim2.fromScale(1, 1) and outcomeFill.BackgroundColor3 == rbx.Color3.fromRGB(255, 211, 92), "Outcome XP fill shares the gold level-up effect")
advance(1.02)
check(math.abs(outcomeFill.Size.X.Scale - 0.2) < 0.00001 and gameOutcome:FindFirstChild("XPWon").Text == "+220 XP", "Late profile updates refresh progress without changing earned round XP")
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

-- Closing/reopening invalidates every queued stage and retains real pre-round progress.
;(function()
	local result = {roundId="sequence-cancel",mode="Standard",theme="Animals",words=3,total=7,xpEarned=100,
		beforeProgression={level=1,xp=450}}
	modalUi:showGameOutcome(result, {progression={level=1,xp=450}})
	advance(0.35)
	modalUi:updateGameOutcome({progression={level=2,xp=120}})
	check(math.abs(outcomeFill.Size.X.Scale-0.9)<0.00001 and not outcomeFill.Parent.Visible, "Profile packets during count-up cannot skip the pre-round bar stage")
	modalUi:hideFrame(gameOutcome)
	advance(5)
	check(not gameOutcome.Visible and not gameOutcome:FindFirstChild("XPWon"):FindFirstChild("OutcomeScale"), "Closing mid-sequence cancels delayed stages and removes temporary scales")
	result.roundId = "sequence-reopen"
	modalUi:showGameOutcome(result, {progression={level=1,xp=450}})
	advance(1.9)
	check(outcomeFill.Parent.Visible and math.abs(outcomeFill.Size.X.Scale-0.9)<0.00001 and not gameOutcome:FindFirstChild("Play").Visible, "Reopened outcome starts from its captured pre-round XP")
	advance(0.6)
	check(outcomeFill.Size.X.Scale == 1 and outcomeFill.BackgroundColor3 == rbx.Color3.fromRGB(255,211,92), "Award crossing a level plays the gold full-bar stretch")
	check(not gameOutcome:FindFirstChild("Home").Visible, "Bottom actions wait through the gold level-up stage")
	advance(2)
	check(gameOutcome:FindFirstChild("Words").Text == "3/7 Words" and gameOutcome:FindFirstChild("XPWon").Text == "+100 XP", "Partial completion counts only actual found words and awarded XP")
	check(gameOutcome:FindFirstChild("CurrentXP").Text == "Level 2 | 50 / 600 XP" and Interface.OutcomeButtonsReady(gameOutcome), "Awarded XP supplies the final bar even if its profile snapshot arrived late")
	modalUi:hideFrame(gameOutcome)
	advance(0.4)
	modalUi:showGameOutcome({roundId="zero-award",words=0,total=7,xpEarned=0,beforeProgression={level=2,xp=50}}, {progression={level=2,xp=50}})
	advance(4)
	check(gameOutcome:FindFirstChild("Words").Text == "0/7 Words" and gameOutcome:FindFirstChild("XPWon").Text == "+0 XP" and Interface.OutcomeButtonsReady(gameOutcome), "Zero-word and zero-XP outcomes finish the sequence without division errors")
	modalUi:hideFrame(gameOutcome)
	advance(0.4)
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
-- Two authored podiums: exact slot names, independent data and exclusive tabs.
check(leaderboardPanels.WordsFound.Visible and not leaderboardPanels["1v1Wins"].Visible, "Words Found is the only default leaderboard panel")
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
check(#leaderboardPanels.WordsFound:GetChildren() == 5, "Leaderboard never clones a fourth slot or adds a layout")
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
check(leaderboardPanels.WordsFound.Visible and not leaderboardPanels["1v1Wins"].Visible, "Words Found button switches back")
for category in pairs(leaderboardPanels) do
	modalUi:selectLeaderboard(category)
	modalUi:showFrame(leaderboardFrame)
	advance(0.5)
	pressLeaderboard(leaderboardFrame, "Quit")
	advance(0.36)
	check(not leaderboardFrame.Visible, "Direct Leaderboards.Quit closes the whole modal from either tab")
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
 for _, category in ipairs({"WordsFound","1v1Wins"}) do
  local container = add(leaderboardPanels[category],"ScrollingFrame","Container")
  add(container,"UIListLayout","UIListLayout")
  modalUi:applyLeaderboardUpdate(category,entries,50)
  check(#container:GetChildren() == 21 and container.AutomaticCanvasSize == rbx.Enum.AutomaticSize.Y, "Leaderboard clones twenty rows and preserves the scrolling layout")
  local last = container:FindFirstChild("LeaderboardRank_20")
  check(last.LayoutOrder == 20 and last:FindFirstChild("Place").Text == "#20" and last:FindFirstChild("Username").Text == "Rank20", "Twentieth row displays its correct rank and identity")
  check(last:FindFirstChild("Mugshot").BackgroundColor3 == portrait.BackgroundColor3, "Ranks below third preserve the template colors")
  modalUi:renderLeaderboard()
  check(container:FindFirstChild("LeaderboardRank_20") == last and #container:GetChildren() == 21, "Refresh reuses rows without duplicates")
  modalUi:applyLeaderboardUpdate(category,{entries[2]},51)
  check(#container:GetChildren() == 2 and container:FindFirstChild("LeaderboardRank_1"):FindFirstChild("Username").Text == "Rank2", "Shrinking rankings remove stale rows and update retained identities")
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
	check(first:FindFirstChild("Request").Visible and not duelUi.renderedEntries[22]:FindFirstChild("Request").Visible and not duelUi.renderedEntries[33]:FindFirstChild("Request").Visible and first:FindFirstChild("Request").Active and not duelUi.renderedEntries[22]:FindFirstChild("Request").Active and not duelUi.renderedEntries[33]:FindFirstChild("Request").Active, "Only available opponents enable Request")
	pressDuel(duelUi.renderedEntries[22],"Request")
	check(#requests == 0, "Busy Request cannot send even if Activated fires")
	duelUi:requestPlayerListUpdate(true)
	check(duelUi.renderedEntries[11] == first and portrait.BackgroundColor3 == color and #list:GetChildren() == 4, "Refresh reuses rows/colors and never duplicates players")
	pressDuel(first,"Request")
	pressDuel(first,"Request")
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
check(math.abs(duelFill.Size.X.Scale-0.2)<0.00001 and duelOutcomeFrame:FindFirstChild("XPWon").Text == "+920 XP", "Late snapshots refresh progress without altering earned match XP")
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


print("BOARD_PRESENTATION_TESTS_PASSED=" .. checks)
