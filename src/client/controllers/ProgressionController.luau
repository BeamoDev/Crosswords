-- Meta screens, rewards, settings, shop, and progression presentation.
local ProgressionController = {}
ProgressionController.__index = ProgressionController

local GuiService = game:GetService("GuiService")
local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Interface = require(script.Parent:WaitForChild("InterfaceController"))
local GuiUtils = Interface.Components.Gui

local DEFAULT_META_CONFIG = {
	GROUP = {
		Id = 34241464,
		RewardHints = 2,
		RewardXp = 0,
	},
	DEFAULTS = {
		StartingHints = 0,
		Settings = {
			SFX = true,
			Music = true,
			DuelInvites = true,
		},
	},
	HINT_PRODUCT_IDS = {
		[1] = 3573028208,
		[5] = 3573028342,
		[15] = 3573028459,
		[30] = 3711566945,
	},
	DAILY_REWARD = {
		BaseXp = 60,
		StepXp = 20,
		MaxXp = 180,
		HintEvery = 5,
		HintAmount = 1,
	},

}

local function cloneTable(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneTable(child)
	end
	return copy
end

local function mergeDefaults(target, defaults)
	if type(defaults) ~= "table" then
		return target
	end

	if type(target) ~= "table" then
		return cloneTable(defaults)
	end

	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = cloneTable(value)
		elseif type(target[key]) == "table" and type(value) == "table" then
			mergeDefaults(target[key], value)
		end
	end

	return target
end

local function resolveMetaConfig()
	local sharedFolder = ReplicatedStorage:FindFirstChild("shared")
	local sharedConfigFolder = sharedFolder and sharedFolder:FindFirstChild("config") or nil
	local configModule = sharedConfigFolder and sharedConfigFolder:FindFirstChild("GameConfig") or nil
	if configModule and configModule:IsA("ModuleScript") then
		local ok, result = pcall(require, configModule)
		if ok and type(result) == "table" and type(result.Meta) == "table" then
			return mergeDefaults(result.Meta, cloneTable(DEFAULT_META_CONFIG))
		end
	end

	return cloneTable(DEFAULT_META_CONFIG)
end

local MetaConfig = resolveMetaConfig()
local sharedRoot = ReplicatedStorage:WaitForChild("shared")
local Effects = require(sharedRoot:WaitForChild("ui"):WaitForChild("UIEffects"))
local LegacyRemotes = require(sharedRoot:WaitForChild("network"):WaitForChild("NetworkContract")).Legacy

local HINT_PRODUCT_IDS = MetaConfig.HINT_PRODUCT_IDS
local PUZZLE_PIECE_TEXT = utf8.char(0x1F9E9)
local MODAL_OPEN_SIZE = UDim2.fromScale(0.33, 0.33)
local MODAL_CLOSED_SIZE = UDim2.fromScale(0, 0)
local MODAL_OPEN_TWEEN = TweenInfo.new(0.44, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MODAL_CLOSE_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local STAT_ICONS = {
	wins = "rbxassetid://81185067037063",
	losses = "rbxassetid://99596774586509",
	other = "rbxassetid://118440568994812",
}
local SETTING_ON_COLOR = Color3.fromRGB(75, 202, 53)
local SETTING_OFF_COLOR = Color3.fromRGB(202, 61, 51)
local SETTING_ON_STROKE = Color3.fromRGB(31, 154, 31)
local SETTING_OFF_STROKE = Color3.fromRGB(154, 28, 28)
local SETTING_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local GENERAL_STAT_SPECS = {
	{ key = "level", title = "Level", icon = STAT_ICONS.other },
	{ key = "solves", title = "Solves", icon = STAT_ICONS.wins },
	{ key = "hints", title = "Hints", icon = STAT_ICONS.other },
	{ key = "duel_wins", title = "Duel Wins", icon = STAT_ICONS.wins },
	{ key = "duel_losses", title = "Duel Losses", icon = STAT_ICONS.losses },
	{ key = "duel_ratio", title = "Duel Win Ratio", icon = STAT_ICONS.other },
}
local statsRuntime = {
	container = nil,
	valueNodes = {},
}

local findDescendantByNames = GuiUtils.findDescendantByNames
local findPath = GuiUtils.findPath
local findFirstPath = GuiUtils.findFirstPath
local findButtonLike = GuiUtils.findButtonLike
local findTextObject = GuiUtils.findTextObject
local findImageObject = GuiUtils.findImageObject

local findBarContainer = GuiUtils.findBarContainer
local setText = GuiUtils.setText

local function setRichText(node, value)
	if not node then
		return
	end

	if node:IsA("TextLabel") or node:IsA("TextButton") then
		node.RichText = true
		node.Text = tostring(value or "")
		return
	end

	local label = node:FindFirstChild("TextLabel") or node:FindFirstChild("Label") or node:FindFirstChild("Data")
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.RichText = true
		label.Text = tostring(value or "")
	end
end

local function formatRewardInlineRichText(hints, xp)
	local parts = {}
	local hintCount = math.max(0, math.floor(tonumber(hints) or 0))
	local xpAmount = math.max(0, math.floor(tonumber(xp) or 0))

	if hintCount > 0 then
		table.insert(parts, string.format("<font color=\"#5ECCFF\">+%d Hint%s</font>", hintCount, hintCount == 1 and "" or "s"))
	end
	if xpAmount > 0 then
		table.insert(parts, string.format("<font color=\"#F6C14F\">+%d XP</font>", xpAmount))
	end

	return #parts > 0 and table.concat(parts, "  ") or "<font color=\"#5ECCFF\">+0 Hints</font>"
end

local function setVisible(node, visible)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

local function disconnectAllConnections(connections)
	for _, connection in ipairs(connections or {}) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function setCustomSectionVisible(node, visible)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

local function hideSettingElement(node)
	if not node then
		return
	end

	if node:IsA("GuiObject") then
		node.Visible = false
	end
end

local function formatClock(seconds)
	local whole = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(whole / 3600)
	local minutes = math.floor((whole % 3600) / 60)
	local remainingSeconds = whole % 60
	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
	end
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function getDataFolders()
	local data = player:FindFirstChild("Data")
	return { data = data, progression = data and data:FindFirstChild("Progression"),
		settings = data and data:FindFirstChild("Settings"), account = data and data:FindFirstChild("Account") }
end

local function getIntValue(folder, name, fallback)
	local valueObject = folder and folder:FindFirstChild(name)
	return valueObject and math.max(0, math.floor(tonumber(valueObject.Value) or 0)) or (fallback or 0)
end

local function getBoolValue(folder, name, fallback)
	local valueObject = folder and folder:FindFirstChild(name)
	if valueObject then
		return valueObject.Value == true
	end
	return fallback == true
end

local function setButtonStateColor(button, enabled)
	if not (button and button:IsA("GuiButton")) then return end
	local targetColor = enabled and SETTING_ON_COLOR or SETTING_OFF_COLOR
	local targetStroke = enabled and SETTING_ON_STROKE or SETTING_OFF_STROKE
	-- Hover/press feedback must settle to the new state, including its border.
	Effects.CancelHighlight(button)
	local previousColor = button.BackgroundColor3
	Effects.SetBaseColor(button, targetColor)
	button.BackgroundColor3 = previousColor
	button.AutoButtonColor, button.BackgroundTransparency = false, 0
	TweenService:Create(button, SETTING_TWEEN, { BackgroundColor3 = targetColor }):Play()
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name, stroke.Thickness, stroke.ApplyStrokeMode = "UIStroke", 2, Enum.ApplyStrokeMode.Border
		stroke.Parent = button
	end
	stroke.Enabled = true
	TweenService:Create(stroke, SETTING_TWEEN, { Color = targetStroke, Transparency = 0 }):Play()
	local label = button:FindFirstChild("TextLabel") or button:FindFirstChild("Textlabel")
	if label and label:IsA("TextLabel") then
		label.Text = enabled and "On" or "Off"
		if button:IsA("TextButton") then button.Text = "" end
	elseif button:IsA("TextButton") then
		button.Text = enabled and "On" or "Off"
	end
end

local function disableButtonUiStroke(button)
	if not (button and button:IsA("GuiObject")) then
		return
	end

	local directStroke = button:FindFirstChild("UIStroke")
	if directStroke and directStroke:IsA("UIStroke") then
		directStroke.Enabled = false
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("UIStroke") then
			descendant.Enabled = false
		end
	end
end

local function ensureListLayout(container)
	if not (container and container:IsA("GuiObject")) then
		return
	end

	local layout = container:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		return layout
	end

	layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container
	return layout
end

local function clearRuntimeEntries(container, prefix)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child.Name == prefix or string.sub(child.Name, 1, #prefix) == prefix then
			child:Destroy()
		end
	end
end



local function getTemplate(name)
	local templateRoots = {
		ReplicatedStorage:FindFirstChild("UIassets"),
		ReplicatedStorage:FindFirstChild("UIAssets"),
		ReplicatedStorage,
	}

	for _, root in ipairs(templateRoots) do
		if root then
			local template = root:FindFirstChild(name) or root:FindFirstChild(name, true)
			if template and template:IsA("GuiObject") then
				return template
			end
		end
	end

	return nil
end

local function formatPuzzlePiecesText(value)
	return string.format("Puzzle Pieces: %s %d", PUZZLE_PIECE_TEXT, math.max(0, math.floor(tonumber(value) or 0)))
end

local function flashTextTargets(targets)
	if #targets == 0 then
		return
	end

	local originals = {}
	for _, target in ipairs(targets) do
		originals[target] = target.TextColor3
		TweenService:Create(target, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextColor3 = Color3.fromRGB(236, 92, 92),
		}):Play()
	end

	task.delay(0.22, function()
		for target, originalColor in pairs(originals) do
			if target and target.Parent then
				TweenService:Create(target, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextColor3 = originalColor,
				}):Play()
			end
		end
	end)
end

local function formatWinRatio(wins, losses)
	local safeWins = math.max(0, math.floor(tonumber(wins) or 0))
	local safeLosses = math.max(0, math.floor(tonumber(losses) or 0))
	local total = safeWins + safeLosses
	if total <= 0 then
		return "0%"
	end

	return string.format("%d%%", math.floor(((safeWins / total) * 100) + 0.5))
end

local function clearStatsRuntime(container)
	statsRuntime.container = container
	statsRuntime.valueNodes = {}
	if not container then
		return
	end

	clearRuntimeEntries(container, "RuntimeStat")
	if container.Name == "Container" or container:IsA("ScrollingFrame") then
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("GuiObject") and string.sub(child.Name, 1, #"RuntimeStat") ~= "RuntimeStat" then
				child:Destroy()
			end
		end
	end
end

local function createStatsHeader(container, template, order, title, hideLabel)
	if not (container and template) then
		return
	end

	local clone = template:Clone()
	clone.Name = "RuntimeStatHeader"
	clone.Visible = true
	clone.LayoutOrder = order

	local label = findTextObject(clone, { "Label", "Title", "TextLabel" })
	if label then
		label.Visible = hideLabel ~= true
		if hideLabel ~= true then
			setText(label, title)
		end
	end

	clone.Parent = container
end

local function createStatsRow(container, template, order, key, title, iconId, iconColor)
	if not (container and template) then
		return
	end

	local clone = template:Clone()
	clone.Name = "RuntimeStat"
	clone.Visible = true
	clone.LayoutOrder = order

	local titleNode = findTextObject(clone, { "Title", "Label", "Name" })
	local valueNode = findTextObject(clone, { "Data", "Value", "Amount" })
	local iconNode = findImageObject(clone, { "Icon", "Image" })

	setText(titleNode, title)
	if iconNode then
		iconNode.Visible = true
		if type(iconId) == "string" and iconId ~= "" then
			iconNode.Image = iconId
		end
		if typeof(iconColor) == "Color3" then
			iconNode.ImageColor3 = iconColor
		else
			iconNode.ImageColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
	if valueNode then
		statsRuntime.valueNodes[key] = valueNode
	end

	clone.Parent = container
end

local function buildStatsLayout(elements)
	local container = elements and elements.statsContainer
	local headerTemplate = getTemplate("StatHeader")
	local statTemplate = getTemplate("StatTemplate")
	if not (container and headerTemplate and statTemplate) then
		return false
	end

	ensureListLayout(container)
	clearStatsRuntime(container)

	local layoutOrder = 1
	createStatsHeader(container, headerTemplate, layoutOrder, "GENERAL")
	layoutOrder += 1

	for _, statInfo in ipairs(GENERAL_STAT_SPECS) do
		createStatsRow(container, statTemplate, layoutOrder, statInfo.key, statInfo.title, statInfo.icon)
		layoutOrder += 1
	end


	createStatsHeader(container, headerTemplate, layoutOrder, "", true)
	layoutOrder += 1
	createStatsHeader(container, headerTemplate, layoutOrder, "", true)
	return true
end

local function ensureStatsLayout(elements)
	local container = elements and elements.statsContainer
	if not container then
		return false
	end

	if statsRuntime.container ~= container or next(statsRuntime.valueNodes) == nil then
		return buildStatsLayout(elements)
	end

	return true
end

function ProgressionController.new(ctx)
	local self = setmetatable({}, ProgressionController)
	self.ctx = ctx
	self.root = nil
	self.elements = {}
	self.connections = {}
	self.frameConnections = {}
	self.modalConnections = {}
	self.modalVisibilityConnections = {}
	self.dailyRewardState = nil
	self.dailyStateRevision = 0
	self.dailyRefreshing = false
	self.dailyClaimPending = false
	self.dailyNextRefreshAt = 0
	self.leaderboardEntries = {}
	self.leaderboardPersonal = {}
	self.leaderboardRevisions = {}
	self.leaderboardCategory = "WordsFound"
	self.verifyPromptShownThisSession = false
	self.verifyPromptQueued = false
	self.attemptedGroupInfoLookup = false
	self.cachedGroupInfo = nil
	self.groupJoinPollToken = 0
	self.groupClaimRequestPending = false
	self.groupJoinPromptPending = false
	self.customGiftBasePosition = nil
	self.customGiftBaseRotation = nil
	self.modalRevision = 0
	self.modalTokens = setmetatable({}, { __mode = "k" })
	self.modalTweens = setmetatable({}, { __mode = "k" })
	self.remotes = {}
	self.settingValues = {}
	self.dailyCountdownLoopStarted = false
	self.dailyCountdownToken = 0
	return self
end

function ProgressionController:resolveRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local eventsFolder = remotesFolder and remotesFolder:FindFirstChild("Events")
	local functionsFolder = remotesFolder and remotesFolder:FindFirstChild("Functions")

	self.remotes.purchaseHintsWithCoins = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.PurchaseHints) or nil
	self.remotes.getDailyRewardState = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.GetDailyRewardState) or nil
	self.remotes.claimDailyReward = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.ClaimDailyReward) or nil
	self.remotes.checkHints = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.CheckHints) or nil
	self.remotes.playerJoinedGroup = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.PlayerJoinedGroup) or nil
	self.remotes.groupHintAwarded = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.GroupHintAwarded) or nil
	self.remotes.updateSetting = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.UpdateSetting) or nil
	self.remotes.leaderboardUpdate = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.LeaderboardUpdate) or nil
	self.remotes.requestLeaderboardUpdate = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.LeaderboardRequest) or nil
end

function ProgressionController:updateModalBackdrop(immediate)
	local frames = self.elements.frames
	if not (frames and frames:IsA("GuiObject")) then return end
	local target = 1
	if frames.Visible then
		for _, child in ipairs(frames:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then target = 0.6 break end
		end
	end
	if not immediate and self.backdropRoot == frames and self.backdropTarget == target then return end
	if self.backdropTween then self.backdropTween:Cancel() self.backdropTween = nil end
	self.backdropRoot, self.backdropTarget = frames, target
	if immediate then frames.BackgroundTransparency = target return end
	self.backdropTween = TweenService:Create(frames, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = target,
	})
	self.backdropTween:Play()
end

function ProgressionController:setModalFrameVisible(frame, visible, immediate)
	if not visible then Interface.CancelOutcome(frame) end
	if not (frame and frame:IsA("GuiObject")) then return end
	self.modalRevision += 1
	local token = self.modalRevision
	self.modalTokens[frame] = token
	local previous = self.modalTweens[frame]
	if previous then previous:Cancel() self.modalTweens[frame] = nil end
	if visible and self.elements and frame == self.elements.shopFrame then
		self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
	end
	if immediate or (not visible and not frame.Visible) then
		frame.Size = visible and MODAL_OPEN_SIZE or MODAL_CLOSED_SIZE
		frame.Visible = visible
		self:updateModalBackdrop()
		return
	end
	if visible then
		if not frame.Visible then frame.Size = MODAL_CLOSED_SIZE end
		frame.Visible = true
	end
	self:updateModalBackdrop()
	-- The authored modal itself owns its background, title, Quit and content.
	-- Never resize or hide its child Frame, or treat the modal as a dim overlay.
	local animation = TweenService:Create(frame, visible and MODAL_OPEN_TWEEN or MODAL_CLOSE_TWEEN, {
		Size = visible and MODAL_OPEN_SIZE or MODAL_CLOSED_SIZE,
	})
	self.modalTweens[frame] = animation
	animation:Play()
	task.delay((visible and MODAL_OPEN_TWEEN.Time or MODAL_CLOSE_TWEEN.Time) + 0.03, function()
		if self.modalTokens[frame] ~= token then return end
		self.modalTweens[frame] = nil
		if frame.Parent then
			frame.Size = visible and MODAL_OPEN_SIZE or MODAL_CLOSED_SIZE
			frame.Visible = visible
			self:updateModalBackdrop()
		end
	end)
end

function ProgressionController:initializeModalFrames()
	local frames = self.elements.frames
	if not frames then return end
	local function initialize(frame)
		if not frame:IsA("GuiObject") then return end
		self:setModalFrameVisible(frame, false, true)
		if self.modalVisibilityConnections[frame] then self.modalVisibilityConnections[frame]:Disconnect() end
		self.modalVisibilityConnections[frame] = frame:GetPropertyChangedSignal("Visible"):Connect(function()
			if self.elements.frames == frames then self:updateModalBackdrop() end
		end)
	end
	for _, frame in ipairs(frames:GetChildren()) do initialize(frame) end
	self:updateModalBackdrop(true)
	-- Keep these observers separate from the temporary CustomFrame button connections.
	table.insert(self.modalConnections, frames.ChildAdded:Connect(initialize))
	table.insert(self.modalConnections, frames.ChildRemoved:Connect(function(frame)
		local connection = self.modalVisibilityConnections[frame]
		if connection then connection:Disconnect() self.modalVisibilityConnections[frame] = nil end
		self:updateModalBackdrop()
	end))
	table.insert(self.modalConnections, frames:GetPropertyChangedSignal("Visible"):Connect(function()
		self:updateModalBackdrop()
	end))
end

function ProgressionController:hideAllFrames(exceptFrame)
	local framesRoot = self.elements.frames
	if not framesRoot then
		return
	end

	for _, child in ipairs(framesRoot:GetChildren()) do
		if child:IsA("GuiObject") and child ~= exceptFrame then
			self:setModalFrameVisible(child, false)
		end
	end
end

function ProgressionController:showFrame(frame)
	if not frame then
		return
	end

	self:hideAllFrames(frame)
	self:setModalFrameVisible(frame, true)
	if self.ctx.playSound then
		self.ctx.playSound("OpenFrame")
	end
	if self.ctx.trackFunnelStep and self.elements then
		local stepName = nil
		if frame == self.elements.shopFrame then
			stepName = "ShopOpened"
		elseif frame == self.elements.dailyFrame then
			stepName = "DailyRewardOpened"
		elseif frame == self.elements.verifyFrame then
			stepName = "VerifyOpened"
		elseif frame == self.elements.leaderboardFrame then
			stepName = "LeaderboardOpened"
		elseif frame == self.elements.settingsFrame then
			stepName = "SettingsOpened"
		elseif frame == self.elements.statsFrame then
			stepName = "ProfileOpened"
		end
		if stepName then
			self.ctx.trackFunnelStep(stepName, {})
		end
	end
end

function ProgressionController:hideFrame(frame)
	if not frame then
		return
	end

	self:setModalFrameVisible(frame, false)
	if self.ctx.playSound then
		self.ctx.playSound("CloseFrame")
	end
end

function ProgressionController:getModalOpenSize(_frame)
	return MODAL_OPEN_SIZE
end

function ProgressionController:isPlayerInGroup()
	local success, inGroup = pcall(function()
		return player:IsInGroup(MetaConfig.GROUP.Id)
	end)
	return success and inGroup == true
end

function ProgressionController:getVerifiedGroupInfo()
	if self.attemptedGroupInfoLookup then
		return self.cachedGroupInfo
	end

	self.attemptedGroupInfoLookup = true
	local success, info = pcall(function()
		return GroupService:GetGroupInfoAsync(MetaConfig.GROUP.Id)
	end)
	if success and type(info) == "table" then
		self.cachedGroupInfo = info
	end

	return self.cachedGroupInfo
end

function ProgressionController:hasClaimedGroupReward()
	local account = getDataFolders().account
	return getBoolValue(account, "GroupRewardClaimed", false)
end

function ProgressionController:startGroupJoinVerificationPoll()
	self.groupJoinPollToken += 1
	local pollToken = self.groupJoinPollToken

	task.spawn(function()
		local startedAt = tick()
		local nextWait = 0.5
		while pollToken == self.groupJoinPollToken and (tick() - startedAt) <= 120 do
			task.wait(nextWait)
			if pollToken ~= self.groupJoinPollToken then
				return
			end

			if self:isPlayerInGroup() then
				if self.remotes.playerJoinedGroup and self.groupClaimRequestPending ~= true then
					self.groupClaimRequestPending = true
					self.remotes.playerJoinedGroup:FireServer()
				end
				return
			end

			nextWait = 2
		end
	end)
end

function ProgressionController:shouldAutoShowVerifyPrompt(snapshot, requireCompletedCount)
	if self.verifyPromptShownThisSession or self.verifyPromptQueued then
		return false
	end
	if not (self.elements and self.elements.verifyFrame) then
		return false
	end
	if self:isPlayerInGroup() then
		return false
	end
	if not self:getVerifiedGroupInfo() then
		return false
	end
	if self:hasClaimedGroupReward() then
		return false
	end
	if requireCompletedCount == true then
		local boardsCleared = snapshot and snapshot.progression and snapshot.progression.solves or 0
		return math.max(0, math.floor(tonumber(boardsCleared) or 0)) >= 1
	end

	return true
end

function ProgressionController:canShowVerifyPromptNow()
	if self.ctx and self.ctx.isTutorialActive and self.ctx.isTutorialActive() then
		return false
	end
	if self.ctx and self.ctx.isGameViewActive and self.ctx.isGameViewActive() then
		return false
	end

	return true
end

function ProgressionController:showCustomPrompt(config)
	local elements = self.elements
	local frame = elements.customFrame
	if not frame then
		return false
	end

	self:showFrame(frame)
	setCustomSectionVisible(elements.customFrameDuelList, false)
	setCustomSectionVisible(elements.customFrameDuelRequest, false)
	setCustomSectionVisible(elements.customFrameGift, config and config.gift == true)
	setText(elements.customFrameTitle, config and config.title or "")
	setText(elements.customFrameSub, config and config.sub or "")
	setVisible(elements.customFrameTitle, config == nil or config.showTitle ~= false)
	setVisible(elements.customFrameSub, config and config.showSub == true)
	if config and config.duelList then
		setCustomSectionVisible(elements.customFrameDuelList, true)
	end
	if config and config.duelRequest then
		setCustomSectionVisible(elements.customFrameDuelRequest, true)
	end

	local greenVisible = config and config.green and config.green.visible == true
	local redVisible = config and config.red and config.red.visible == true

	setVisible(elements.customFrameGreen, greenVisible)
	setVisible(elements.customFrameRed, redVisible)

	setText(elements.customFrameGreenLabel, greenVisible and (config.green.label or "") or "")
	setText(elements.customFrameRedLabel, redVisible and (config.red.label or "") or "")

	for _, connection in ipairs(self.frameConnections) do
		connection:Disconnect()
	end
	table.clear(self.frameConnections)

	if greenVisible and elements.customFrameGreenButton and config.green.onClick then
		table.insert(self.frameConnections, elements.customFrameGreenButton.Activated:Connect(function()
			config.green.onClick()
		end))
	end
	if redVisible and elements.customFrameRedButton and config.red.onClick then
		table.insert(self.frameConnections, elements.customFrameRedButton.Activated:Connect(function()
			config.red.onClick()
		end))
	end

	return true
end

function ProgressionController:showGiftReward(_message, onClaim)
	local elements = self.elements
	local giftRoot = elements and elements.customFrameGift
	if not (elements and elements.customFrame and giftRoot and giftRoot:IsA("GuiObject")) then
		if type(onClaim) == "function" then
			onClaim()
		end
		return false
	end

	self:showCustomPrompt({
		reason = "gift_reward",
		showTitle = false,
		showSub = false,
		gift = true,
		green = { visible = false },
		red = { visible = false },
	})

	local giftVisual = findImageObject(giftRoot, { "ImageLabel", "Gift" }) or giftRoot
	self.customGiftBasePosition = self.customGiftBasePosition or giftRoot.Position
	self.customGiftBaseRotation = self.customGiftBaseRotation or giftRoot.Rotation

	giftRoot.Visible = true
	giftRoot.Position = self.customGiftBasePosition + UDim2.fromScale(0, 0.08)
	giftRoot.Rotation = self.customGiftBaseRotation or 0
	if giftVisual and (giftVisual:IsA("ImageLabel") or giftVisual:IsA("ImageButton")) then
		giftVisual.BackgroundTransparency = 1
	end

	TweenService:Create(
		giftRoot,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = self.customGiftBasePosition }
	):Play()

	for index = 1, 6 do
		task.delay(0.08 + ((index - 1) * 0.14), function()
			if not (giftRoot and giftRoot.Parent) then
				return
			end

			local offset = index % 2 == 0 and -5 or 5
			TweenService:Create(
				giftRoot,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Rotation = offset }
			):Play()
		end)
	end

	task.delay(0.76, function()
		if not (giftRoot and giftRoot.Parent) then
			return
		end

		TweenService:Create(
			giftRoot,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = self.customGiftBasePosition + UDim2.fromScale(0, -0.03),
				Rotation = 0,
			}
		):Play()

		task.delay(0.48, function()
			if giftRoot and giftRoot.Parent then
				giftRoot.Position = self.customGiftBasePosition
				giftRoot.Rotation = self.customGiftBaseRotation or 0
			end
			self:hideFrame(elements.customFrame)
			if type(onClaim) == "function" then
				onClaim()
			end
		end)
	end)

	return true
end

function ProgressionController:resolveElements(root)
	local frames = root:FindFirstChild("Frames") or findDescendantByNames(root, { "Frames" }, nil)
	local menu = root:FindFirstChild("Home")
	local game = root:FindFirstChild("Game") or findDescendantByNames(root, { "Game" }, nil)
	for _, owner in pairs({ game, frames }) do
		local retired = owner:FindFirstChild("TimedRewards")
		if retired and retired:IsA("GuiObject") then retired.Visible = false end
	end
	local menuBottomBar = menu and findPath(menu, { "ButtonBar" }, nil)
	local menuMainRow = menu and (menu:FindFirstChild("MainRow") or findDescendantByNames(menu, { "MainRow" }, nil)) or nil
	local gameTopBar = game and (game:FindFirstChild("TopBar") or findDescendantByNames(game, { "TopBar" }, nil)) or nil
	local gameTopBarContainer = gameTopBar and (gameTopBar:FindFirstChild("Container") or findDescendantByNames(gameTopBar, { "Container" }, nil)) or gameTopBar
	local gameBottomBar = game and (
		game:FindFirstChild("BottomBar")
			or game:FindFirstChild("BottomBarShell")
			or findDescendantByNames(game, { "BottomBar", "BottomBarShell" }, nil)
	) or nil

	local shopFrame = frames and frames:FindFirstChild("Shop") or nil
	local shopRoot = shopFrame
	local shopCards = shopFrame and shopFrame:FindFirstChild("Frame")
	local shopPacks = {}
	for _, spec in ipairs({ { name = "One", amount = 5 }, { name = "Two", amount = 15 }, { name = "Three", amount = 30 } }) do
		local card = shopCards and shopCards:FindFirstChild(spec.name)
		local buy = card and card:FindFirstChild("Buy")
		if card and buy and buy:IsA("GuiButton") then
			table.insert(shopPacks, { amount = spec.amount, card = card, buy = buy,
				title = card:FindFirstChild("Title") })
		end
	end

	local leaderboardFrame = frames and (frames:FindFirstChild("Leaderboards") or frames:FindFirstChild("Leaderboard")) or nil
	local leaderboardRoot = leaderboardFrame
	local leaderboardAssets = ReplicatedStorage:FindFirstChild("Assets") or ReplicatedStorage:FindFirstChild("assets")
	local dailyFrame = frames and (frames:FindFirstChild("DailyRewards") or frames:FindFirstChild("DailyReward") or frames:FindFirstChild("Daily")) or nil
	local dailyRoot = dailyFrame
	local settingsFrame = frames and frames:FindFirstChild("Settings") or nil
	local settingsRoot = settingsFrame
	local settingsContainer = settingsRoot and settingsRoot:FindFirstChild("Frame")
	local statsFrame = frames and (frames:FindFirstChild("Statistics") or frames:FindFirstChild("Stats")) or nil
	local statsRoot = statsFrame
	local statsContainer = statsRoot
		and (
			findFirstPath(statsRoot, {
				{ "Container", "ScrollingFrame" },
				{ "StatsContainer", "ScrollingFrame" },
				{ "Container", "StatsContainer" },
				{ "ScrollingFrame" },
				{ "Container" },
				{ "StatsContainer" },
			}, nil)
			or statsRoot:FindFirstChildWhichIsA("ScrollingFrame", true)
			or statsRoot:FindFirstChild("Frame")
			or statsRoot
		)
		or nil
	local verifyFrame = frames and frames:FindFirstChild("Verify") or nil
	local verifyRoot = verifyFrame
	local customFrame = frames and frames:FindFirstChild("CustomFrame") or nil
	local customRoot = customFrame
	local menuDailyRoot = findFirstPath(menuBottomBar, { { "Daily" }, { "DailyRewards" } }, nil)
		or (menuBottomBar and findDescendantByNames(menuBottomBar, { "Daily", "DailyRewards" }, nil) or nil)
	local gameHintRoot = findFirstPath(game, {
		{ "TopBar", "Container", "Hint" },
		{ "TopBar", "Hint" },
		{ "Hint" },
	}, nil)
		or (gameTopBarContainer and findFirstPath(gameTopBarContainer, { { "Hint" } }, nil) or nil)

	local settingsButtonRoot = findFirstPath(menuBottomBar, {
		{ "Settings" },
		{ "Container", "Settings" },
	}, nil)
		or findButtonLike(menuBottomBar and findDescendantByNames(menuBottomBar, { "Settings" }, nil) or nil)
		or findFirstPath(gameBottomBar, {
			{ "Settings" },
			{ "Container", "Settings" },
		}, nil)
		or findButtonLike(gameBottomBar and findDescendantByNames(gameBottomBar, { "Settings" }, nil) or nil)
	local statsButtonRoot = findFirstPath(menuBottomBar, {
		{ "Stats" },
		{ "Statistics" },
		{ "Profile" },
		{ "Container", "Stats" },
		{ "Container", "Statistics" },
		{ "Container", "Profile" },
	}, nil)
		or findButtonLike(menuBottomBar and findDescendantByNames(menuBottomBar, { "Stats", "Statistics", "Profile" }, nil) or nil)
		or findFirstPath(gameBottomBar, {
			{ "Stats" },
			{ "Statistics" },
			{ "Profile" },
			{ "Container", "Stats" },
			{ "Container", "Statistics" },
			{ "Container", "Profile" },
		}, nil)
		or findButtonLike(gameBottomBar and findDescendantByNames(gameBottomBar, { "Stats", "Statistics", "Profile" }, nil) or nil)
	local customFrameGreenRoot = customRoot and (
		findFirstPath(customRoot, {
			{ "Buttons", "Green" },
			{ "Green" },
		}, nil)
			or findDescendantByNames(customRoot, { "Green" }, nil)
	) or nil
	local customFrameRedRoot = customRoot and (
		findFirstPath(customRoot, {
			{ "Buttons", "Red" },
			{ "Red" },
		}, nil)
			or findDescendantByNames(customRoot, { "Red" }, nil)
	) or nil

	self.elements = {
		root = root,
		frames = frames,
		gameOutcome = frames and frames:FindFirstChild("GameOutcome"),
		menuDailyButton = findButtonLike(menuDailyRoot),
		menuDailyAlert = findDescendantByNames(menuDailyRoot, { "Alert", "alert", "Aelrt" }, nil),
		menuLeaderboardButton = findButtonLike(findFirstPath(menuBottomBar, { { "Leaderboard" }, { "Leaderboards" } }, nil)) or findButtonLike(menuBottomBar and findDescendantByNames(menuBottomBar, { "Leaderboard", "Leaderboards" }, nil) or nil),
		menuSettingsButton = findButtonLike(settingsButtonRoot),
		menuStatsButton = findButtonLike(statsButtonRoot),
		menuShopButton = findButtonLike(menuBottomBar and menuBottomBar:FindFirstChild("Shop")),
		topBarShopButton = findButtonLike(findPath(gameTopBarContainer, { "Shop" }, nil)) or findButtonLike(gameTopBarContainer and findDescendantByNames(gameTopBarContainer, { "Shop" }, nil) or nil),
		hintAvailableLabel = gameHintRoot and findFirstPath(gameHintRoot, { { "Available" } }, nil) or nil,
		hintNotification = gameHintRoot and findFirstPath(gameHintRoot, { { "Notification" } }, nil) or nil,
		hintNotificationAmount = gameHintRoot and findFirstPath(gameHintRoot, { { "Notification", "Amount" } }, nil) or nil,
		shopFrame = shopFrame,
		shopBulb = shopFrame and shopFrame:FindFirstChild("Bulb"),
		shopHintsOwned = shopFrame and shopFrame:FindFirstChild("HintsOwned"),
		shopBack = findButtonLike(findFirstPath(shopFrame, { { "Quit" }, { "Exit" }, { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(shopFrame and findDescendantByNames(shopFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		shopTitleDisplay = shopRoot and findTextObject(shopRoot, { "Display", "Title" }) or nil,
		shopPacks = shopPacks,
		dailyFrame = dailyFrame,
		dailyBack = dailyRoot and findButtonLike(dailyRoot:FindFirstChild("Quit")),
		dailyBody = findPath(dailyRoot, { "Requirements", "Title" }, nil),
		dailyStatus = dailyRoot and dailyRoot:FindFirstChild("Timer"),
		dailyClaim = dailyRoot and findButtonLike(dailyRoot:FindFirstChild("Claim")),
		dailyClaimLabel = findPath(dailyRoot, { "Claim", "TextLabel" }, nil),
		settingsFrame = settingsFrame,
		settingsBack = findButtonLike(findFirstPath(settingsFrame, { { "Quit" }, { "Exit" }, { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(settingsFrame and findDescendantByNames(settingsFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		settingsSFX = findButtonLike(findPath(settingsContainer, { "SFX", "Toggle" }, nil)),
		settingsDuelInvites = findButtonLike(findPath(settingsContainer, { "1v1", "Toggle" }, nil)),
		settingsMusic = findButtonLike(findPath(settingsContainer, { "Music", "Toggle" }, nil)),
		settingsNumbers = findButtonLike(settingsContainer and findDescendantByNames(settingsContainer, { "DotNumbers", "DotNumber", "Numbers" }, nil) or nil),
		settingsColorblind = findButtonLike(settingsContainer and findDescendantByNames(settingsContainer, { "ColorBlind", "Colorblind" }, nil) or nil),
		statsFrame = statsFrame,
		statsRoot = statsRoot,
		statsContainer = statsContainer,
		statsBack = findButtonLike(findFirstPath(statsFrame, { { "Quit" }, { "Exit" }, { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(statsFrame and findDescendantByNames(statsFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		statsWinRatioRow = statsContainer and (findDescendantByNames(statsContainer, { "TimedSolve", "WinRatio" }, nil) or nil) or nil,
		statsDailySolve = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "DailySolve" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsFastest = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "Fastest" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsHints = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "Hints" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsPlaytime = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "Playtime" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsRank = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "Rank" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsSolves = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "Solves" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsTimedSolve = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "TimedSolve" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		statsXP = statsContainer and findTextObject(findDescendantByNames(statsContainer, { "XP" }, nil) or statsContainer, { "Data", "TextLabel" }) or nil,
		leaderboardFrame = leaderboardFrame,
		leaderboardTemplate = leaderboardAssets and leaderboardAssets:FindFirstChild("LeaderboardTemplate"),
		leaderboardYou = leaderboardRoot and leaderboardRoot:FindFirstChild("You"),
		leaderboardPanels = {
			WordsFound = leaderboardRoot and leaderboardRoot:FindFirstChild("WordsFound") or nil,
			["1v1Wins"] = leaderboardRoot and leaderboardRoot:FindFirstChild("1v1Wins") or nil,
		},
		verifyFrame = verifyFrame,
		verifyExit = findButtonLike(verifyRoot and verifyRoot:FindFirstChild("Quit")),
		verifyJoin = findButtonLike(verifyRoot and verifyRoot:FindFirstChild("Okay")),
		verifyFill = verifyRoot and (findDescendantByNames((findBarContainer(verifyRoot) or verifyRoot), { "Fill" }, nil) or nil) or nil,
		customFrame = customFrame,
		customFrameTitle = customRoot and findTextObject(customRoot, { "Title" }) or nil,
		customFrameSub = customRoot and findTextObject(customRoot, { "Sub" }) or nil,
		customFrameDuelList = customRoot and findDescendantByNames(customRoot, { "DuelList" }, nil) or nil,
		customFrameDuelSample = customRoot and findDescendantByNames(customRoot, { "DuelSample" }, nil) or nil,
		customFrameDuelRequest = customRoot and findDescendantByNames(customRoot, { "DuelRequest" }, nil) or nil,
		customFrameGift = customRoot and findDescendantByNames(customRoot, { "Gift" }, nil) or nil,
		customFrameGreen = customFrameGreenRoot,
		customFrameGreenButton = findButtonLike(findFirstPath(customRoot, {
			{ "Buttons", "Green", "Button" },
			{ "Green", "Button" },
			{ "Buttons", "Green" },
			{ "Green" },
		}, nil) or customFrameGreenRoot),
		customFrameGreenLabel = customRoot and findTextObject(findFirstPath(customRoot, {
			{ "Buttons", "Green", "Label" },
			{ "Green", "Label" },
		}, nil) or customFrameGreenRoot or customRoot, { "Label", "TextLabel" }) or nil,
		customFrameRed = customFrameRedRoot,
		customFrameRedButton = findButtonLike(findFirstPath(customRoot, {
			{ "Buttons", "Red", "Button" },
			{ "Red", "Button" },
			{ "Buttons", "Red" },
			{ "Red" },
		}, nil) or customFrameRedRoot),
		customFrameRedLabel = customRoot and findTextObject(findFirstPath(customRoot, {
			{ "Buttons", "Red", "Label" },
			{ "Red", "Label" },
		}, nil) or customFrameRedRoot or customRoot, { "Label", "TextLabel" }) or nil,
	}
	do
		local winRatioTitle = self.elements.statsWinRatioRow and findDescendantByNames(self.elements.statsWinRatioRow, { "Title", "Label", "Name" }, nil) or nil
		if winRatioTitle and (winRatioTitle:IsA("TextLabel") or winRatioTitle:IsA("TextButton")) then
			self.elements.statsWinRatioTitle = winRatioTitle
		else
			self.elements.statsWinRatioTitle = nil
		end
	end

	self:renderLeaderboard()
	self:renderDailyRewardState()
	ensureListLayout(self.elements.statsContainer)
	if self.elements.statsContainer and self.elements.statsContainer:IsA("ScrollingFrame") then
		self.elements.statsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
		self.elements.statsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
		self.elements.statsContainer.ScrollBarThickness = math.max(8, self.elements.statsContainer.ScrollBarThickness)
	end
	if menuBottomBar then
		local hiddenRewardsRoot = findFirstPath(menuBottomBar, { { "Quests" }, { "Rewards" } }, nil)
			or findDescendantByNames(menuBottomBar, { "Quests", "Rewards" }, nil)
		setVisible(hiddenRewardsRoot, false)
	end
	if frames then
		setVisible(frames:FindFirstChild("Quests") or findDescendantByNames(frames, { "Quests" }, nil), false)
		setVisible(frames:FindFirstChild("Rewards") or findDescendantByNames(frames, { "Rewards" }, nil), false)
	end
	setVisible(self.elements.customFrameGift, false)
	self:updateBottomBarAlerts()
end

function ProgressionController:updateHintText(snapshot)
	local hintsAvailable = snapshot and snapshot.hints or getIntValue(getDataFolders().data, "Hints", 0)
	local showHintCount = hintsAvailable > 0
	if self.elements.hintAvailableLabel and self.elements.hintAvailableLabel ~= self.elements.hintNotificationAmount then
		setVisible(self.elements.hintAvailableLabel, false)
	end
	if self.elements.hintNotification then
		setVisible(self.elements.hintNotification, showHintCount)
	end
	if self.elements.hintNotificationAmount then
		setVisible(self.elements.hintNotificationAmount, showHintCount)
		setText(self.elements.hintNotificationAmount, showHintCount and tostring(math.max(0, math.floor(tonumber(hintsAvailable) or 0))) or "")
	end
end

function ProgressionController:getPuzzlePiecesBalance(snapshot)
	local folders = getDataFolders()
	return snapshot and math.max(0, math.floor(tonumber(snapshot.puzzlePieces) or 0))
		or getIntValue(folders.data, "PuzzlePieces", 0)
end

function ProgressionController:updatePuzzlePiecesDisplay(snapshot)
	if not self.elements.shopPuzzlePiecesDisplay then
		return
	end

	setText(self.elements.shopPuzzlePiecesDisplay, formatPuzzlePiecesText(self:getPuzzlePiecesBalance(snapshot)))
end

function ProgressionController:flashPuzzlePiecesDisplay()
	local display = self.elements.shopPuzzlePiecesDisplay
	if not display then
		return
	end

	local targets = {}
	if display:IsA("TextLabel") or display:IsA("TextButton") then
		table.insert(targets, display)
	end
	for _, descendant in ipairs(display:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			table.insert(targets, descendant)
		end
	end

	flashTextTargets(targets)
end

function ProgressionController:showPuzzlePieceSpendFloat(amount)
	local display = self.elements.shopPuzzlePiecesDisplay
	local numericAmount = math.max(0, math.floor(tonumber(amount) or 0))
	if not (display and display:IsA("GuiObject") and numericAmount > 0) then
		return
	end

	local parent = display.Parent
	if not (parent and parent:IsA("GuiObject")) then
		return
	end

	local parentSize = parent.AbsoluteSize
	if parentSize.X <= 0 or parentSize.Y <= 0 then
		return
	end

	local center = display.AbsolutePosition + (display.AbsoluteSize * 0.5)
	local relativeX = (center.X - parent.AbsolutePosition.X) / parentSize.X
	local relativeY = (center.Y - parent.AbsolutePosition.Y) / parentSize.Y

	local label = Instance.new("TextLabel")
	label.Name = "PuzzlePieceSpendFloat"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(170, 34)
	label.Position = UDim2.fromScale(relativeX, relativeY)
	label.Text = string.format("-%s %d", PUZZLE_PIECE_TEXT, numericAmount)
	label.TextColor3 = Color3.fromRGB(255, 124, 124)
	label.TextTransparency = 0.02
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.ZIndex = math.max(display.ZIndex + 3, 12)
	label.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(88, 24, 24)
	stroke.Thickness = 1.4
	stroke.Transparency = 0.18
	stroke.Parent = label

	TweenService:Create(label, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = label.Position - UDim2.fromScale(0, 0.055),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	}):Play()

	task.delay(0.46, function()
		if label and label.Parent then
			label:Destroy()
		end
	end)
end

function ProgressionController:updateShopTexts(snapshot)
	local hints = snapshot and snapshot.hints or getIntValue(getDataFolders().data, "Hints", 0)
	hints = math.max(0, math.floor(tonumber(hints) or 0))
	local ownsHints = hints >= 1
	local color = ownsHints and Color3.fromRGB(43, 225, 58) or Color3.fromRGB(3, 36, 66)
	local transparency = ownsHints and 0 or 0.5
	local bulb, owned = self.elements.shopBulb, self.elements.shopHintsOwned
	if bulb and (bulb:IsA("ImageLabel") or bulb:IsA("ImageButton")) then
		bulb.ImageColor3, bulb.ImageTransparency = color, transparency
	end
	if owned and (owned:IsA("TextLabel") or owned:IsA("TextButton")) then
		owned.Text = tostring(hints)
		owned.TextColor3, owned.TextTransparency = color, transparency
	end
	setText(self.elements.shopTitleDisplay, "Hint Shop")
	for _, pack in ipairs(self.elements.shopPacks or {}) do
		setText(pack.title, string.format("%d Hints", pack.amount))
	end
end

function ProgressionController:updateStats(snapshot)
	local folders = getDataFolders()
	local progression = snapshot and snapshot.progression or {}
	local duelFolder = folders.progression and folders.progression:FindFirstChild("Duel")
	local duel = progression.duel or {}
	local wins, losses = duel.wins or getIntValue(duelFolder, "Wins"), duel.losses or getIntValue(duelFolder, "Losses")
	local values = {
		level = progression.level or getIntValue(folders.progression, "Level", 1),
		solves = progression.solves or getIntValue(folders.progression, "Solves"),
		hints = snapshot and snapshot.hints or getIntValue(folders.data, "Hints"),
		duel_wins = wins, duel_losses = losses, duel_ratio = formatWinRatio(wins, losses),
	}
	if ensureStatsLayout(self.elements) then
		for key, value in pairs(values) do setText(statsRuntime.valueNodes[key], tostring(value)) end
	else
		setText(self.elements.statsSolves, tostring(values.solves))
		setText(self.elements.statsHints, tostring(values.hints))
		for _, key in ipairs({ "statsDailySolve", "statsFastest", "statsPlaytime", "statsTimedSolve", "statsWinRatioTitle", "statsRank", "statsXP" }) do
			setVisible(self.elements[key] and self.elements[key].Parent, false)
		end
	end
end

function ProgressionController:updateGameOutcome(snapshot)
	local result, frame = self.gameOutcomeResult, self.elements.gameOutcome
	if not result or not frame then return end
	setText(frame:FindFirstChild("Title"), "Complete!")
	local modeTitle = result.mode == "Standard" and "Themes" or result.mode
	setText(frame:FindFirstChild("LevelTheme"), string.format("%s | %s", result.theme or "Word Search", modeTitle or "Themes"))
	if Interface.UpdateOutcome(frame, snapshot and snapshot.progression) then return end
	setText(frame:FindFirstChild("Words"), Interface.OutcomeWords(result.words, result.total, result.duration))
	setText(frame:FindFirstChild("XPWon"), string.format("+%d XP", result.xpEarned))
	local level, xp, required = Interface.UpdateProgressFill(self, frame, snapshot and snapshot.progression)
	setText(frame:FindFirstChild("CurrentXP"), string.format("Level %d | %d / %d XP", level, xp, required))
end

function ProgressionController:showGameOutcome(result, snapshot)
	local frame = self.elements.gameOutcome
	if not frame then return end
	self.gameOutcomeResult = result
	Interface.PlayOutcome(self, frame, result, snapshot and snapshot.progression)
	self:updateGameOutcome(snapshot)
	self:showFrame(frame)
end

function ProgressionController:updateSettings(snapshot)
	snapshot = snapshot or (self.ctx.getSnapshot and self.ctx.getSnapshot())
	local settings = snapshot and snapshot.settings
	local mirrors
	for _, name in ipairs({ "SFX", "Music", "DuelInvites" }) do
		local enabled = settings and settings[name]
		if type(enabled) ~= "boolean" then
			mirrors = mirrors or getDataFolders().settings
			enabled = getBoolValue(mirrors, name, true)
		end
		self.settingValues[name] = enabled
		setButtonStateColor(self.elements["settings" .. name], enabled)
	end
	hideSettingElement(self.elements.settingsNumbers)
	hideSettingElement(self.elements.settingsColorblind)
end

function ProgressionController:toggleSetting(name)
	if not self.remotes.updateSetting or (name ~= "SFX" and name ~= "Music" and name ~= "DuelInvites") then return end
	local enabled = not (self.settingValues[name] ~= false)
	self.settingValues[name] = enabled
	local snapshot = self.ctx.getSnapshot and self.ctx.getSnapshot()
	if snapshot then
		snapshot.settings = snapshot.settings or {}
		snapshot.settings[name] = enabled
		if self.ctx.applySnapshot then self.ctx.applySnapshot(snapshot) end
	end
	setButtonStateColor(self.elements["settings" .. name], enabled)
	self.remotes.updateSetting:FireServer(name, enabled)
end

function ProgressionController:updateBottomBarAlerts()
	local dailyClaimable = type(self.dailyRewardState) == "table" and self.dailyRewardState.claimable == true

	setVisible(self.elements.menuDailyAlert, dailyClaimable)
end

local DAILY_READY_COLOR = Color3.fromRGB(75, 170, 95)
local DAILY_WAIT_COLOR = Color3.fromRGB(202, 100, 100)

function ProgressionController:dailySecondsRemaining()
	if self.dailyResetAt then return math.max(0, math.ceil(self.dailyResetAt - os.clock() - 1e-6)) end
	return math.max(0, math.ceil(tonumber(self.dailyRewardState and self.dailyRewardState.secondsUntilReset) or 0))
end

function ProgressionController:setDailyRewardState(state)
	if type(state) ~= "table" or state.success ~= true then return end
	self.dailyRewardState = state
	self.dailyResetAt = os.clock() + math.max(0, tonumber(state.secondsUntilReset) or 0)
	self:renderDailyRewardState()
end

function ProgressionController:renderDailyRewardState()
	local state = self.dailyRewardState
	local claimable = state and state.claimable == true
	local timer = self.elements.dailyStatus
	if timer then
		timer.RichText = false
		timer.Text = not state and "--:--" or claimable and "00:00" or formatClock(self:dailySecondsRemaining())
		timer.TextColor3 = claimable and DAILY_READY_COLOR or DAILY_WAIT_COLOR
	end
	if state then
		local streak = math.max(0, math.floor(tonumber(state.streak) or 0))
		local reward = formatRewardInlineRichText(state.nextRewardHints or 0, state.nextRewardXp or 0)
		setRichText(self.elements.dailyBody, string.format("Daily Streak: %d day%s\nNext Reward: %s", streak, streak == 1 and "" or "s", reward))
	end
	local canClaim = claimable and not self.dailyClaimPending
	setText(self.elements.dailyClaimLabel, self.dailyClaimPending and "CLAIMING..." or not state and "LOADING..." or claimable and "CLAIM" or "CLAIMED")
	local button = self.elements.dailyClaim
	if button then
		button.Active = canClaim == true
		button.Selectable = canClaim == true
	end
	self:updateBottomBarAlerts()
end

function ProgressionController:refreshDailyRewardState()
	local remote = self.remotes.getDailyRewardState
	if not remote or self.dailyRefreshing or self.dailyClaimPending then return end
	self.dailyRefreshing = true
	self.dailyStateRevision += 1
	local revision, lifetime = self.dailyStateRevision, self.dailyCountdownToken
	self.dailyNextRefreshAt = os.clock() + 10
	local ok, result = pcall(function() return remote:InvokeServer() end)
	if lifetime ~= self.dailyCountdownToken then return end
	self.dailyRefreshing = false
	if revision ~= self.dailyStateRevision then return end
	if ok then self:setDailyRewardState(result) end
	self:renderDailyRewardState()
end

function ProgressionController:tickDailyReward()
	self:renderDailyRewardState()
	if (not self.dailyRewardState or self:dailySecondsRemaining() <= 0) and os.clock() >= self.dailyNextRefreshAt then
		self:refreshDailyRewardState()
	end
end

function ProgressionController:claimDailyReward()
	local remote = self.remotes.claimDailyReward
	if not remote or self.dailyClaimPending or not (self.dailyRewardState and self.dailyRewardState.claimable == true) then return end
	self.dailyClaimPending = true
	self.dailyStateRevision += 1
	local revision, lifetime = self.dailyStateRevision, self.dailyCountdownToken
	self:renderDailyRewardState()
	local ok, result = pcall(function() return remote:InvokeServer() end)
	if lifetime ~= self.dailyCountdownToken or revision ~= self.dailyStateRevision then return end
	self.dailyClaimPending = false
	if ok and type(result) == "table" then
		-- Rejected duplicate claims also return the current authoritative waiting state.
		self:setDailyRewardState(result.state)
		if result.snapshot and self.ctx.applySnapshot then self.ctx.applySnapshot(result.snapshot) end
		if result.success and type(result.state) ~= "table" then self:refreshDailyRewardState() end
	end
	self:renderDailyRewardState()
end

local LEADERBOARD_MEDALS = {
	{ name = "One", color = Color3.fromRGB(255, 214, 92), stroke = Color3.fromRGB(177, 128, 24) },
	{ name = "Two", color = Color3.fromRGB(208, 220, 233), stroke = Color3.fromRGB(109, 124, 145) },
	{ name = "Three", color = Color3.fromRGB(211, 147, 93), stroke = Color3.fromRGB(137, 81, 42) },
}

function ProgressionController:selectLeaderboard(category)
	if category ~= "WordsFound" and category ~= "1v1Wins" then return end
	self.leaderboardCategory = category
	self:renderLeaderboard()
end

function ProgressionController:applyLeaderboardUpdate(category, entries, revision, personal)
	if category ~= "WordsFound" and category ~= "1v1Wins" then return end
	if type(entries) ~= "table" or type(revision) ~= "number" then return end
	if revision <= (self.leaderboardRevisions[category] or -1) then return end
	self.leaderboardRevisions[category] = revision
	self.leaderboardEntries[category] = entries
	if type(personal) == "table" and personal.UserId == player.UserId then self.leaderboardPersonal[category] = personal end
	self:renderLeaderboard()
end

function ProgressionController:renderLeaderboard()
	local you = self.elements.leaderboardYou
	if you then
		local snapshot = self.ctx.getSnapshot and self.ctx.getSnapshot()
		local progression = snapshot and snapshot.progression
		local personal = self.leaderboardPersonal[self.leaderboardCategory]
		local score = progression and (self.leaderboardCategory == "1v1Wins" and (progression.duel or {}).wins or progression.wordsFound)
		score = score or (personal and personal.Score) or 0
		you.Visible = true
		setText(you:FindFirstChild("Username"), player.Name)
		setText(you:FindFirstChild("Data"), tostring(score))
		setText(you:FindFirstChild("Place"), personal and personal.Score == score and personal.RankText or "--")
		local mugshot = you:FindFirstChild("Mugshot")
		if mugshot then Effects.SetPortraitImage(mugshot, string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",player.UserId)) end
	end
	for category, panel in pairs(self.elements.leaderboardPanels or {}) do
		setVisible(panel, category == self.leaderboardCategory)
		local entries = self.leaderboardEntries[category] or {}
		local container = panel:FindFirstChild("Container")
		-- Bottom is authored list padding, not a disposable leaderboard entry.
		local bottom = container and container:FindFirstChild("Bottom")
		if bottom and bottom:IsA("GuiObject") then bottom.LayoutOrder = math.max(21, bottom.LayoutOrder) end
		if container and container:IsA("ScrollingFrame") then
			container.AutomaticCanvasSize = Enum.AutomaticSize.Y
			local layout = container:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
		for index = 1, container and 20 or 3 do
			local medal = LEADERBOARD_MEDALS[index]
			local entry = entries[index]
			local slot
			if container then
				local name = "LeaderboardRank_" .. index
				slot = container:FindFirstChild(name)
				if not entry then
					if slot then slot:Destroy() end
					continue
				end
				if not slot and self.elements.leaderboardTemplate then
					slot = self.elements.leaderboardTemplate:Clone()
					slot.Name, slot.Parent = name, container
				end
				if slot then slot.Visible, slot.LayoutOrder = true, index end
			else slot = panel:FindFirstChild(medal.name) end
			if not slot then continue end
			setText(slot:FindFirstChild("Username"), entry and entry.Username or "No player yet")
			setText(slot:FindFirstChild("Data"), tostring(entry and entry.Score or 0))
			local place = slot:FindFirstChild("Place")
			setText(place, "#" .. tostring(index))
			if medal and place and place:IsA("TextLabel") then
				place.TextColor3 = medal.color
				place.TextStrokeColor3 = medal.stroke
				local stroke = place:FindFirstChildWhichIsA("UIStroke")
				if stroke then stroke.Color = medal.stroke end
			end
			local mugshot = slot:FindFirstChild("Mugshot")
			if mugshot and (mugshot:IsA("ImageLabel") or mugshot:IsA("ImageButton")) then
				if medal then mugshot.BackgroundColor3 = medal.color end
				mugshot.BackgroundTransparency = 0
				local stroke = mugshot:FindFirstChildWhichIsA("UIStroke")
				if not stroke then
					stroke = Instance.new("UIStroke")
					stroke.Name = "UIStroke"
					stroke.Thickness = 2
					stroke.Parent = mugshot
				end
				if medal then stroke.Color = medal.stroke end
				local image = entry and entry.Thumbnail or ""
				if image == "" and entry and (tonumber(entry.UserId) or 0) > 0 then
					image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId)
				end
				mugshot.Image = image
				local placeholder = mugshot:FindFirstChild("Profile")
				if placeholder and placeholder:IsA("GuiObject") then placeholder.Visible = false end
				Effects.SetPortraitImage(mugshot, image)
				mugshot.ImageTransparency = image == "" and 1 or 0
			end
		end
	end
end

function ProgressionController:requestLeaderboardRefresh()
	if self.remotes.requestLeaderboardUpdate then
		self.remotes.requestLeaderboardUpdate:FireServer()
	end
end

function ProgressionController:promptProductPurchase(productId)
	if type(productId) ~= "number" then
		return
	end

	pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
end

function ProgressionController:handleHintPurchase(amount)
	-- The single-hint product is prompted only by Game.Hint at zero inventory.
	if amount ~= 5 and amount ~= 15 and amount ~= 30 then return end
	self:promptProductPurchase(HINT_PRODUCT_IDS[amount])
end

function ProgressionController:connectButton(button, callback)
	if not (button and button:IsA("GuiButton")) then
		return
	end

	table.insert(self.connections, button.Activated:Connect(callback))
end

function ProgressionController:connectButtons()
	local elements = self.elements
	local function canOpenShopFromCurrentState()
		if self.ctx and self.ctx.isGameplayInteractionBlocked and self.ctx.isGameViewActive and self.ctx.isGameViewActive() then
			return self.ctx.isGameplayInteractionBlocked() ~= true
		end

		return true
	end

	local function canUseGameplayTopBarActions()
		if self.ctx and self.ctx.isGameViewActive and self.ctx.isGameViewActive() then
			return self.ctx.isGameplayInteractionBlocked and self.ctx.isGameplayInteractionBlocked() ~= true or false
		end

		return true
	end

	self:connectButton(elements.menuShopButton, function()
		if not canOpenShopFromCurrentState() then
			return
		end
		self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
		self:showFrame(elements.shopFrame)
	end)
	self:connectButton(elements.topBarShopButton, function()
		if not canOpenShopFromCurrentState() then
			return
		end
		self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
		self:showFrame(elements.shopFrame)
	end)
	self:connectButton(elements.menuDailyButton, function()
		self:showFrame(elements.dailyFrame)
		self:refreshDailyRewardState()
	end)
	self:connectButton(elements.menuLeaderboardButton, function()
		self:requestLeaderboardRefresh()
		self:renderLeaderboard()
		self:showFrame(elements.leaderboardFrame)
	end)
	self:connectButton(elements.menuSettingsButton, function()
		self:updateSettings()
		self:showFrame(elements.settingsFrame)
	end)
	self:connectButton(elements.menuStatsButton, function()
		self:updateStats(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
		self:showFrame(elements.statsFrame)
	end)

	self:connectButton(elements.shopBack, function()
		self:hideFrame(elements.shopFrame)
	end)
	self:connectButton(elements.dailyBack, function()
		self:hideFrame(elements.dailyFrame)
	end)
	self:connectButton(elements.settingsBack, function()
		self:hideFrame(elements.settingsFrame)
	end)
	self:connectButton(elements.statsBack, function()
		self:hideFrame(elements.statsFrame)
	end)
	for _, panel in pairs(elements.leaderboardPanels or {}) do
		for _, category in ipairs({ "WordsFound", "1v1Wins" }) do
			self:connectButton(findButtonLike(panel:FindFirstChild(category)), function()
				self:selectLeaderboard(category)
			end)
		end
	end
	self:connectButton(findButtonLike(elements.leaderboardFrame and elements.leaderboardFrame:FindFirstChild("Quit")), function()
		self:hideFrame(elements.leaderboardFrame)
	end)
	self:connectButton(elements.verifyExit, function()
		self:hideFrame(elements.verifyFrame)
	end)

	self:connectButton(elements.dailyClaim, function() self:claimDailyReward() end)

	self:connectButton(elements.settingsSFX, function() self:toggleSetting("SFX") end)
	self:connectButton(elements.settingsMusic, function() self:toggleSetting("Music") end)
	self:connectButton(elements.settingsDuelInvites, function() self:toggleSetting("DuelInvites") end)

	local outcome = elements.gameOutcome
	self:connectButton(outcome and outcome:FindFirstChild("Play"), function()
		if Interface.OutcomeButtonsReady(self.elements.gameOutcome) and self.gameOutcomeResult and self.ctx.onOutcomePlay then self.ctx.onOutcomePlay(self.gameOutcomeResult.roundId) end
	end)
	self:connectButton(outcome and outcome:FindFirstChild("Home"), function()
		if Interface.OutcomeButtonsReady(self.elements.gameOutcome) and self.gameOutcomeResult and self.ctx.onOutcomeHome then self.ctx.onOutcomeHome(self.gameOutcomeResult.roundId) end
	end)

	for _, pack in ipairs(elements.shopPacks or {}) do
		self:connectButton(pack.buy, function() self:handleHintPurchase(pack.amount) end)
	end

	self:connectButton(elements.verifyJoin, function()
		if self.groupJoinPromptPending then return end
		self.groupJoinPromptPending = true
		local prompted = pcall(function()
			GroupService:PromptJoinAsync(MetaConfig.GROUP.Id)
		end)
		self.groupJoinPromptPending = false
		if not prompted then return end

		if self:isPlayerInGroup() and self.remotes.playerJoinedGroup and self.groupClaimRequestPending ~= true then
			self.groupClaimRequestPending = true
			self.remotes.playerJoinedGroup:FireServer()
			return
		end

		self:startGroupJoinVerificationPoll()
	end)
end

function ProgressionController:connectRemoteEvents()
	if self.remotes.groupHintAwarded then
		table.insert(self.connections, self.remotes.groupHintAwarded.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			self.groupClaimRequestPending = false
			self.verifyPromptQueued = false
			self.verifyPromptShownThisSession = true
			self.groupJoinPollToken += 1
			self:hideFrame(self.elements.verifyFrame)
		end))
	end

	if self.remotes.leaderboardUpdate then
		table.insert(self.connections, self.remotes.leaderboardUpdate.OnClientEvent:Connect(function(category, entries, _updatedAt, revision, personal)
			self:applyLeaderboardUpdate(category, entries, revision, personal)
		end))
	end

	table.insert(self.connections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
		if userId ~= player.UserId then
			return
		end

		if purchased then
			self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
		end
	end))
end

function ProgressionController:queueVerifyPrompt(snapshot, delaySeconds, requireCompletedCount)
	if self:isPlayerInGroup() and not self:hasClaimedGroupReward() then
		if self.remotes.playerJoinedGroup and self.groupClaimRequestPending ~= true then
			self.groupClaimRequestPending = true
			self.remotes.playerJoinedGroup:FireServer()
		end
		return
	end

	if not self:shouldAutoShowVerifyPrompt(snapshot, requireCompletedCount == true) then
		return
	end

	self.verifyPromptQueued = true
	task.delay(math.max(0, tonumber(delaySeconds) or 1.2), function()
		local success, err = xpcall(function()
			while self.verifyPromptQueued do
				if self.verifyPromptShownThisSession or self:isPlayerInGroup() then
					self.verifyPromptQueued = false
					return
				end
				if self:hasClaimedGroupReward() then
					self.verifyPromptQueued = false
					return
				end
				if not (self.elements and self.elements.verifyFrame) then
					self.verifyPromptQueued = false
					return
				end
				if not self:canShowVerifyPromptNow() then
					task.wait(1)
					continue
				end
				self.verifyPromptQueued = false
				break
			end

			if self.verifyPromptShownThisSession or self.verifyPromptQueued then
				return
			end

			self.verifyPromptShownThisSession = true
			self:showFrame(self.elements.verifyFrame)
		end, debug.traceback)
		if not success then
			self.verifyPromptQueued = false
			warn("[ProgressionController] Verify prompt callback failed:", err)
		end
	end)
end

function ProgressionController:applySnapshot(snapshot)
	self:renderLeaderboard()
	self:updateHintText(snapshot)
	self:updateShopTexts(snapshot)
	self:updateStats(snapshot)
	self:updateSettings(snapshot)
	self:updateGameOutcome(snapshot)
	self:queueVerifyPrompt(snapshot, nil, true)
end

function ProgressionController:bind(root)
	if self.root then
		self:destroy()
	end
	self.root = root
	self:resolveRemotes()
	self:resolveElements(root)
	self:initializeModalFrames()
	self:connectButtons()
	self:connectRemoteEvents()
	if not self.dailyCountdownLoopStarted then
		self.dailyCountdownLoopStarted = true
		self.dailyCountdownToken += 1
		local dailyCountdownToken = self.dailyCountdownToken
		task.spawn(function()
			while self.dailyCountdownToken == dailyCountdownToken and self.root and self.root.Parent do
				task.wait(1)
				if self.dailyCountdownToken ~= dailyCountdownToken then break end
				self:tickDailyReward()
			end
			if self.dailyCountdownToken == dailyCountdownToken then
				self.dailyCountdownLoopStarted = false
			end
		end)
	end
	self:refreshDailyRewardState()
	self:requestLeaderboardRefresh()
	self:applySnapshot(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
end

function ProgressionController:destroy()
	Interface.CancelOutcome(self.elements.gameOutcome)
	disconnectAllConnections(self.modalConnections)
	for frame, connection in pairs(self.modalVisibilityConnections) do
		connection:Disconnect()
		self.modalVisibilityConnections[frame] = nil
	end
	for frame, animation in pairs(self.modalTweens) do
		animation:Cancel()
		if frame.Parent then frame.Size, frame.Visible = MODAL_CLOSED_SIZE, false end
	end
	if self.backdropTween then self.backdropTween:Cancel() self.backdropTween = nil end
	if self.backdropRoot then self.backdropRoot.BackgroundTransparency = 1 end
	self.backdropRoot, self.backdropTarget = nil, nil
	self.root = nil
	self.gameOutcomeResult = nil
	self.dailyCountdownLoopStarted = false
	self.dailyCountdownToken += 1
	self.dailyRewardState, self.dailyResetAt = nil, nil
	self.dailyRefreshing, self.dailyClaimPending = false, false
	self.dailyNextRefreshAt = 0
	self.verifyPromptQueued = false
	self.groupJoinPollToken += 1
	disconnectAllConnections(self.connections)
	disconnectAllConnections(self.frameConnections)


	self.elements = {}
	self.remotes = {}
	self.modalTokens = setmetatable({}, { __mode = "k" })
	self.modalTweens = setmetatable({}, { __mode = "k" })
end

return ProgressionController
