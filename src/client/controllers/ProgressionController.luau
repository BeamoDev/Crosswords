-- Meta screens, rewards, settings, shop, and progression presentation.
local ProgressionController = {}
ProgressionController.__index = ProgressionController

local GuiService = game:GetService("GuiService")
local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local GuiUtils = require(script.Parent:WaitForChild("InterfaceController")).Components.Gui
local Rewards = require(script.Parent.Parent:WaitForChild("features"):WaitForChild("Rewards"))
local TimedRewardsUIModule = Rewards.TimedRewards

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
		},
	},
	HINT_PRODUCT_IDS = {
		[1] = 3573028208,
		[5] = 3573028342,
		[25] = 3573028459,
	},
	DAILY_REWARD = {
		BaseXp = 60,
		StepXp = 20,
		MaxXp = 180,
		HintEvery = 5,
		HintAmount = 1,
	},
	LEADERBOARD = {
		SolvesStoreName = "WordSearchSolves_v1",
		RefreshInterval = 300,
		WriteInterval = 60,
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
local sharedConfig = sharedRoot:WaitForChild("config")
local LegacyRemotes = require(sharedRoot:WaitForChild("network"):WaitForChild("NetworkContract")).Legacy
local PuzzleEconomy = require(sharedConfig:WaitForChild("GameConfig")).Economy
local TimedRewards = require(sharedConfig:WaitForChild("ProgressionConfig")).TimedRewards

local HINT_PRODUCT_IDS = MetaConfig.HINT_PRODUCT_IDS
local PUZZLE_PIECE_TEXT = utf8.char(0x1F9E9)
local TIMED_REWARD_HINT_ICON = "rbxassetid://120861243695122"
local SHOP_HINT_CURRENCY_ROBUX = "robux"
local SHOP_HINT_CURRENCY_PIECES = "pieces"

local MODAL_CENTER_POSITION = UDim2.fromScale(0.5, 0.5)
local MODAL_OPEN_SIZE = UDim2.fromScale(0.6, 0.6)
local MODAL_OPEN_SIZE_MOBILE = UDim2.fromScale(0.8, 0.8)
local MODAL_OPEN_SIZE_MOBILE_SHOP = UDim2.fromScale(0.9, 1)
local MODAL_OPEN_SIZE_STATS_MOBILE = UDim2.fromScale(0.9, 0.85)
local MODAL_CLOSED_SIZE = UDim2.fromScale(0, 0)
local MODAL_OVERLAY_OPEN_TRANSPARENCY = 0.6
local MODAL_OPEN_TWEEN = TweenInfo.new(0.44, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MODAL_CLOSE_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local LEADERBOARD_BOTTOM_PADDING = 120
local STAT_ICONS = {
	streak = "rbxassetid://123852090905133",
	wins = "rbxassetid://81185067037063",
	losses = "rbxassetid://99596774586509",
	playtime = "rbxassetid://119687027975825",
	other = "rbxassetid://118440568994812",
}
local SETTING_ON_COLOR = Color3.fromRGB(80, 241, 80)
local SETTING_OFF_COLOR = Color3.fromRGB(241, 80, 80)
local SETTING_ON_STROKE = Color3.fromRGB(0, 199, 0)
local SETTING_OFF_STROKE = Color3.fromRGB(199, 0, 0)
local SETTING_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local GENERAL_STAT_SPECS = {
	{ key = "general_wins", title = "Wins", icon = STAT_ICONS.wins },
	{ key = "general_losses", title = "Losses", icon = STAT_ICONS.losses },
	{ key = "general_win_ratio", title = "Win Ratio", icon = STAT_ICONS.other },
	{ key = "general_highest_streak", title = "Highest Streak", icon = STAT_ICONS.streak },
	{ key = "general_current_streak", title = "Current Streak", icon = STAT_ICONS.streak },
	{ key = "general_words_found", title = "Words Found", icon = STAT_ICONS.other },
	{ key = "general_hints_used", title = "Hints Used", icon = STAT_ICONS.other },
	{ key = "general_daily_clears", title = "Daily Clears", icon = STAT_ICONS.other },
	{ key = "general_fastest_solve", title = "Fastest Solve", icon = STAT_ICONS.other },
	{ key = "general_playtime", title = "Playtime", icon = STAT_ICONS.playtime },
	{ key = "general_highest_classic", title = "Highest Classic", icon = STAT_ICONS.other },
}
local MODE_STAT_SPECS = {
	{ key = "best_streak", title = "Best Streak", icon = STAT_ICONS.streak },
	{ key = "current_streak", title = "Current Streak", icon = STAT_ICONS.streak },
	{ key = "wins", title = "Wins", icon = STAT_ICONS.wins },
	{ key = "losses", title = "Losses", icon = STAT_ICONS.losses },
	{ key = "win_ratio", title = "Win Ratio", icon = STAT_ICONS.other },
}
local MODE_SECTION_ORDER = {
	{ key = "Classic", title = "CLASSIC" },
	{ key = "Themed", title = "THEMED" },
	{ key = "Daily", title = "DAILY" },
	{ key = "Freeplay", title = "FREEPLAY" },
	{ key = "Backwards", title = "BACKWARDS" },
	{ key = "Fog", title = "FOG" },
	{ key = "OneLife", title = "ONE LIFE" },
	{ key = "Mega", title = "MEGA" },
}
local MODE_SECTION_ICON_COLORS = {
	Classic = Color3.fromRGB(246, 193, 79),
	Themed = Color3.fromRGB(120, 214, 255),
	Daily = Color3.fromRGB(255, 148, 96),
	Freeplay = Color3.fromRGB(111, 229, 171),
	Backwards = Color3.fromRGB(124, 169, 255),
	Fog = Color3.fromRGB(166, 197, 214),
	OneLife = Color3.fromRGB(255, 108, 108),
	Mega = Color3.fromRGB(191, 130, 255),
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

local function findShopPriceLabel(root)
	return findTextObject(root, { "PriceLabel", "Price2", "Amount", "Price" })
end

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

local function formatRewardParts(hints, xp)
	local parts = {}
	local hintCount = math.max(0, math.floor(tonumber(hints) or 0))
	local xpAmount = math.max(0, math.floor(tonumber(xp) or 0))

	if hintCount > 0 then
		table.insert(parts, string.format("%d Hint%s", hintCount, hintCount == 1 and "" or "s"))
	end
	if xpAmount > 0 then
		table.insert(parts, string.format("%d XP", xpAmount))
	end

	return parts
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

local function formatRewardAmountText(hints, xp)
	local parts = formatRewardParts(hints, xp)
	return #parts > 0 and table.concat(parts, " / ") or "0 Hints"
end

local function color3ToHex(color)
	local safeColor = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
	return string.format(
		"%02X%02X%02X",
		math.floor(safeColor.R * 255 + 0.5),
		math.floor(safeColor.G * 255 + 0.5),
		math.floor(safeColor.B * 255 + 0.5)
	)
end

local function escapeRichText(text)
	local safeText = tostring(text or "")
	safeText = safeText:gsub("&", "&amp;")
	safeText = safeText:gsub("<", "&lt;")
	safeText = safeText:gsub(">", "&gt;")
	return safeText
end

local function displayChatMessage(text, color)
	local safeColor = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
	local formattedText = string.format(
		"<font color=\"#%s\">%s</font>",
		color3ToHex(safeColor),
		escapeRichText(text)
	)
	local sent = false

	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local channels = TextChatService:FindFirstChild("TextChannels")
		local systemChannel = channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
		if systemChannel and systemChannel.DisplaySystemMessage then
			pcall(function()
				systemChannel:DisplaySystemMessage(formattedText)
				sent = true
			end)
		end
	end

	if not sent then
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = formattedText,
				Color = safeColor,
				Font = Enum.Font.Nunito,
				TextSize = 19,
			})
		end)
	end
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
	local progress = data and data:FindFirstChild("Progress") or nil
	return {
		data = data,
		progress = progress,
		progression = data and data:FindFirstChild("Progression") or nil,
		stats = data and data:FindFirstChild("Stats") or nil,
		activity = data and data:FindFirstChild("Activity") or nil,
		progressWins = progress and progress:FindFirstChild("Wins") or nil,
		progressLosses = progress and progress:FindFirstChild("Losses") or nil,
		progressWinRatio = progress and progress:FindFirstChild("WinRatio") or nil,
		progressStreaks = progress and progress:FindFirstChild("Streaks") or nil,
		puzzlePieces = data and data:FindFirstChild("PuzzlePieces") or nil,
		settings = data and data:FindFirstChild("Settings") or nil,
		hints = data and data:FindFirstChild("Hints") or nil,
		account = data and data:FindFirstChild("Account") or nil,
		coins = data and data:FindFirstChild("Coins") or nil,
		leaderstats = player:FindFirstChild("leaderstats"),
		timedRewards = data and data:FindFirstChild("TimedRewards") or nil,
	}
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
	if not (button and button:IsA("GuiObject")) then
		return
	end

	local targetColor = enabled and SETTING_ON_COLOR or SETTING_OFF_COLOR
	local targetStroke = enabled and SETTING_ON_STROKE or SETTING_OFF_STROKE

	if button:IsA("GuiButton") then
		button.AutoButtonColor = false
	end
	button.BackgroundTransparency = 0
	TweenService:Create(button, SETTING_TWEEN, {
		BackgroundColor3 = targetColor,
	}):Play()

	local seen = {}
	local function tweenStroke(stroke)
		if not (stroke and stroke:IsA("UIStroke")) or seen[stroke] then
			return
		end

		seen[stroke] = true
		stroke.Enabled = true
		stroke.Transparency = 0
		TweenService:Create(stroke, SETTING_TWEEN, {
			Color = targetStroke,
			Transparency = 0,
		}):Play()
	end

	tweenStroke(button:FindFirstChild("UIStroke"))
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("UIStroke") then
			tweenStroke(descendant)
		end
	end
	if button:IsA("TextButton") then
		button.Text = ""
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

local function getModalContentFrame(frame)
	if not (frame and frame:IsA("GuiObject")) then
		return nil
	end

	local direct = frame:FindFirstChild("Frame")
	if direct and direct:IsA("GuiObject") then
		return direct
	end

	return nil
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

local function ensureBottomPadding(container, paddingName, pixels)
	if not (container and container:IsA("GuiObject")) then
		return nil
	end

	local padding = container:FindFirstChild(paddingName)
	if padding and not padding:IsA("UIPadding") then
		padding:Destroy()
		padding = nil
	end
	if not padding then
		padding = Instance.new("UIPadding")
		padding.Name = paddingName
		padding.Parent = container
	end

	padding.PaddingBottom = UDim.new(0, math.max(0, math.floor(tonumber(pixels) or 0)))
	return padding
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

local function createRuntimeLeaderboardEntry(parent, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "RuntimeEntry"
	row.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
	row.BackgroundTransparency = 0.08
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -8, 0, 58)
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = row

	local rank = Instance.new("TextLabel")
	rank.Name = "Rank"
	rank.BackgroundTransparency = 1
	rank.Position = UDim2.fromOffset(12, 0)
	rank.Size = UDim2.fromOffset(42, 58)
	rank.Font = Enum.Font.GothamBold
	rank.TextColor3 = Color3.fromRGB(255, 255, 255)
	rank.TextSize = 18
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Text = ""
	rank.Parent = row

	local profile = Instance.new("ImageLabel")
	profile.Name = "Profile"
	profile.BackgroundTransparency = 1
	profile.Position = UDim2.fromOffset(54, 9)
	profile.Size = UDim2.fromOffset(40, 40)
	profile.Parent = row

	local username = Instance.new("TextLabel")
	username.Name = "Username"
	username.BackgroundTransparency = 1
	username.Position = UDim2.fromOffset(104, 8)
	username.Size = UDim2.new(1, -210, 0, 22)
	username.Font = Enum.Font.GothamBold
	username.TextColor3 = Color3.fromRGB(255, 255, 255)
	username.TextSize = 17
	username.TextXAlignment = Enum.TextXAlignment.Left
	username.Text = ""
	username.Parent = row

	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.BackgroundTransparency = 1
	score.AnchorPoint = Vector2.new(1, 0.5)
	score.Position = UDim2.new(1, -14, 0.5, 0)
	score.Size = UDim2.fromOffset(84, 22)
	score.Font = Enum.Font.GothamBold
	score.TextColor3 = Color3.fromRGB(255, 211, 100)
	score.TextSize = 17
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.Text = ""
	score.Parent = row

	return row, username, rank, score, profile
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

local function formatPuzzlePiecePrice(value)
	return string.format("%s %d", PUZZLE_PIECE_TEXT, math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatRobuxPrice(value)
	local price = tonumber(value)
	if not price then
		return "Robux ..."
	end

	return string.format("Ã®â‚¬â€š %d", math.max(0, math.floor(price + 0.5)))
end

local function applyHintPackPrice(primaryNode, labelNode, textValue)
	local resolvedText = tostring(textValue or "")
	if labelNode then
		setText(labelNode, resolvedText)
	elseif primaryNode then
		setText(primaryNode, resolvedText)
	end
end

local function ensureShopCurrencyToggle(shopRoot)
	if not (shopRoot and shopRoot:IsA("GuiObject")) then
		return nil
	end

	local existing = findButtonLike(findDescendantByNames(shopRoot, {
		"HintCurrencyToggle",
		"CurrencyToggle",
		"PuzzlePiecesToggle",
	}, nil))
	if existing then
		return existing
	end

	local button = Instance.new("TextButton")
	button.Name = "HintCurrencyToggle"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -18, 0, 18)
	button.Size = UDim2.fromOffset(178, 38)
	button.BackgroundColor3 = Color3.fromRGB(33, 42, 60)
	button.BackgroundTransparency = 0.04
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.TextWrapped = true
	button.ZIndex = 20
	button.Parent = shopRoot

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(118, 196, 255)
	stroke.Thickness = 1.4
	stroke.Transparency = 0.15
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button

	return button
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

local function setupFeaturedPackPulse(card)
	if not (card and card:IsA("GuiObject")) then
		return
	end
	if card:GetAttribute("WordSearchFeaturePulseBound") then
		return
	end

	card:SetAttribute("WordSearchFeaturePulseBound", true)

	local stroke = card:FindFirstChild("WordSearchFeaturePulseStroke")
	if not (stroke and stroke:IsA("UIStroke")) then
		stroke = Instance.new("UIStroke")
		stroke.Name = "WordSearchFeaturePulseStroke"
		stroke.Parent = card
	end

	stroke.Enabled = true
	stroke.Color = Color3.fromRGB(255, 108, 214)
	stroke.Transparency = 0.45
	stroke.Thickness = 2
	pcall(function()
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end)

	task.spawn(function()
		local highColor = Color3.fromRGB(255, 108, 214)
		local lowColor = Color3.fromRGB(182, 102, 255)
		local active = false

		while card.Parent and stroke.Parent == card do
			active = not active
			local tween = TweenService:Create(
				stroke,
				TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{
					Color = active and lowColor or highColor,
					Transparency = active and 0.18 or 0.48,
					Thickness = active and 3 or 2,
				}
			)
			tween:Play()
			tween.Completed:Wait()
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

	for _, modeInfo in ipairs(MODE_SECTION_ORDER) do
		createStatsHeader(container, headerTemplate, layoutOrder, modeInfo.title)
		layoutOrder += 1

		for _, statInfo in ipairs(MODE_STAT_SPECS) do
			createStatsRow(
				container,
				statTemplate,
				layoutOrder,
				string.format("mode_%s_%s", modeInfo.key, statInfo.key),
				statInfo.title,
				statInfo.icon,
				MODE_SECTION_ICON_COLORS[modeInfo.key]
			)
			layoutOrder += 1
		end
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

local function getSnapshotModeBucket(snapshot, modeName)
	local modeResults = snapshot and snapshot.stats and snapshot.stats.modeResults or nil
	local bucket = type(modeResults) == "table" and modeResults[modeName] or nil
	if type(bucket) ~= "table" then
		return 0, 0
	end

	return math.max(0, math.floor(tonumber(bucket.wins) or 0)), math.max(0, math.floor(tonumber(bucket.losses) or 0))
end

local function getSnapshotModeStreakBucket(snapshot, modeName)
	local modeStreaks = snapshot and snapshot.stats and snapshot.stats.modeStreaks or nil
	local bucket = type(modeStreaks) == "table" and modeStreaks[modeName] or nil
	if type(bucket) ~= "table" then
		return 0, 0
	end

	return math.max(0, math.floor(tonumber(bucket.current) or 0)), math.max(0, math.floor(tonumber(bucket.best) or 0))
end

local function getLiveSolvesFallbackEntries()
	local entries = {}
	for _, currentPlayer in ipairs(Players:GetPlayers()) do
		local leaderstats = currentPlayer:FindFirstChild("leaderstats")
		local solvesValue = leaderstats and leaderstats:FindFirstChild("Wins") or nil
		table.insert(entries, {
			UserId = currentPlayer.UserId,
			Username = currentPlayer.DisplayName ~= "" and currentPlayer.DisplayName or currentPlayer.Name,
			Thumbnail = "",
			Score = math.max(0, math.floor(tonumber(solvesValue and solvesValue.Value) or 0)),
		})
	end

	table.sort(entries, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return tostring(a.Username or "") < tostring(b.Username or "")
	end)

	for index, entry in ipairs(entries) do
		entry.Rank = index
	end

	return entries
end

function ProgressionController.new(ctx)
	local self = setmetatable({}, ProgressionController)
	self.ctx = ctx
	self.root = nil
	self.elements = {}
	self.connections = {}
	self.frameConnections = {}
	self.dailyRewardState = nil
	self.leaderboardEntries = {}
	self.leaderboardUpdatedAt = 0
	self.verifyPromptShownThisSession = false
	self.verifyPromptQueued = false
	self.attemptedGroupInfoLookup = false
	self.cachedGroupInfo = nil
	self.groupJoinPollToken = 0
	self.groupClaimRequestPending = false
	self.customGiftBasePosition = nil
	self.customGiftBaseRotation = nil
	self.modalTokens = setmetatable({}, { __mode = "k" })
	self.remotes = {}
	self.shopHintCurrency = SHOP_HINT_CURRENCY_ROBUX
	self.hintProductPrices = {}
	self.hintProductPriceRequests = {}
	self.dailyCountdownLoopStarted = false
	self.dailyCountdownToken = 0
	self.timedRewardsDataConnections = {}
	self.timedRewardsPulseState = {
		connection = nil,
		stroke = nil,
		scale = nil,
	}
	self.timedRewardsHeartbeat = nil
	return self
end

function ProgressionController:resolveRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local eventsFolder = remotesFolder and remotesFolder:FindFirstChild("Events")
	local functionsFolder = remotesFolder and remotesFolder:FindFirstChild("Functions")

	self.remotes.purchaseHintsWithCoins = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.PurchaseHints) or nil
	self.remotes.getDailyRewardState = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.GetDailyRewardState) or nil
	self.remotes.claimDailyReward = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.ClaimDailyReward) or nil
	self.remotes.claimTimedReward = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.ClaimTimedReward) or nil
	self.remotes.checkHints = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.CheckHints) or nil
	self.remotes.purchaseSuccess = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.PurchaseSuccess) or nil
	self.remotes.playerJoinedGroup = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.PlayerJoinedGroup) or nil
	self.remotes.groupHintAwarded = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.GroupHintAwarded) or nil
	self.remotes.adminMessage = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.AdminMessage) or nil
	self.remotes.updateSetting = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.UpdateSetting) or nil
	self.remotes.leaderboardUpdateSolves = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.LeaderboardUpdate) or nil
	self.remotes.requestLeaderboardUpdateSolves = eventsFolder and eventsFolder:FindFirstChild(LegacyRemotes.LeaderboardRequest) or nil
end

function ProgressionController:setModalFrameVisible(frame, visible, immediate)
	if not (frame and frame:IsA("GuiObject")) then
		return
	end

	if self.elements and frame == self.elements.shopFrame then
		self.shopHintCurrency = SHOP_HINT_CURRENCY_ROBUX
		self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
	end

	local token = (self.modalTokens[frame] or 0) + 1
	self.modalTokens[frame] = token
	local content = getModalContentFrame(frame)
	local openSize = self:getModalOpenSize(frame)

	if visible then
		frame.Visible = true
		frame.BackgroundTransparency = immediate and MODAL_OVERLAY_OPEN_TRANSPARENCY or 1
		if content then
			content.Visible = true
			content.AnchorPoint = Vector2.new(0.5, 0.5)
			content.Position = MODAL_CENTER_POSITION
			content.Size = immediate and openSize or MODAL_CLOSED_SIZE
		end

		if immediate then
			return
		end

		TweenService:Create(frame, MODAL_OPEN_TWEEN, { BackgroundTransparency = MODAL_OVERLAY_OPEN_TRANSPARENCY }):Play()
		if content then
			TweenService:Create(content, MODAL_OPEN_TWEEN, { Size = openSize }):Play()
		end
		return
	end

	if immediate then
		frame.Visible = false
		frame.BackgroundTransparency = 1
		if content then
			content.Visible = false
			content.AnchorPoint = Vector2.new(0.5, 0.5)
			content.Position = MODAL_CENTER_POSITION
			content.Size = MODAL_CLOSED_SIZE
		end
		return
	end

	TweenService:Create(frame, MODAL_CLOSE_TWEEN, { BackgroundTransparency = 1 }):Play()
	if content then
		TweenService:Create(content, MODAL_CLOSE_TWEEN, { Size = MODAL_CLOSED_SIZE }):Play()
	end

	task.delay(MODAL_CLOSE_TWEEN.Time + 0.03, function()
		if self.modalTokens[frame] ~= token then
			return
		end
		if content then
			content.Visible = false
		end
		frame.Visible = false
	end)
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
		elseif frame == self.elements.timedRewardsFrame then
			stepName = "TimedRewardsOpened"
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

function ProgressionController:showAlert(title, message, alertType, options)
	if self.ctx.showDesktopAlert then
		self.ctx.showDesktopAlert(title, message, alertType, options)
	end
end

function ProgressionController:isMobileUi()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function ProgressionController:getModalOpenSize(frame)
	if not self:isMobileUi() then
		return MODAL_OPEN_SIZE
	end

	if frame == self.elements.statsFrame then
		return MODAL_OPEN_SIZE_STATS_MOBILE
	end

	if frame == self.elements.timedRewardsFrame then
		return MODAL_OPEN_SIZE
	end

	if frame == self.elements.shopFrame then
		return MODAL_OPEN_SIZE_MOBILE_SHOP
	end

	return MODAL_OPEN_SIZE_MOBILE
end

function ProgressionController:canShowTimedRewards()
	if self.ctx and self.ctx.canShowTimedRewards then
		return self.ctx.canShowTimedRewards() == true
	end

	return false
end

function ProgressionController:getTimedRewardsContext()
	return {
		player = player,
		elements = self.elements,
		runService = RunService,
		timedRewardsConfig = TimedRewards,
		hintIconId = TIMED_REWARD_HINT_ICON,
		pulseState = self.timedRewardsPulseState,
		runtimeState = self.timedRewardsRuntimeState,
		dataConnections = self.timedRewardsDataConnections,
		disconnectAll = disconnectAllConnections,
		canShowTimedRewards = function()
			return self:canShowTimedRewards()
		end,
		isMobile = function()
			return self:isMobileUi()
		end,
		show = setVisible,
		setText = setText,
		onUpdate = function()
			self:updateTimedRewards()
		end,
		claimTimedRewardRemote = self.remotes.claimTimedReward,
		applySnapshot = self.ctx and self.ctx.applySnapshot or nil,
		showAlert = function(title, message, _, _, _, timedAlertType)
			self:showAlert(title, message, timedAlertType or "info", {
				duration = timedAlertType == "reward" and 2.3 or 2.1,
			})
		end,
	}
end

function ProgressionController:updateTimedRewards()
	local ctx = self:getTimedRewardsContext()
	TimedRewardsUIModule.ApplyState(ctx, TimedRewardsUIModule.GetState(ctx))
	self.timedRewardsPulseState = ctx.pulseState
	self.timedRewardsRuntimeState = ctx.runtimeState
end

function ProgressionController:setupTimedRewards()
	local ctx = self:getTimedRewardsContext()
	TimedRewardsUIModule.Setup(ctx)
	self.timedRewardsPulseState = ctx.pulseState
	self.timedRewardsRuntimeState = ctx.runtimeState
	self:updateTimedRewards()

	if self.timedRewardsHeartbeat then
		self.timedRewardsHeartbeat:Disconnect()
		self.timedRewardsHeartbeat = nil
	end

	local elapsed = 0
	self.timedRewardsHeartbeat = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		self:updateTimedRewards()
	end)
end

function ProgressionController:claimTimedReward()
	local ctx = self:getTimedRewardsContext()
	TimedRewardsUIModule.Claim(ctx)
	self.timedRewardsPulseState = ctx.pulseState
	self.timedRewardsRuntimeState = ctx.runtimeState
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
		local boardsCleared = snapshot and snapshot.stats and snapshot.stats.boardsCleared or 0
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
	local menu = root:FindFirstChild("Menu") or findDescendantByNames(root, { "Menu" }, nil)
	local game = root:FindFirstChild("Game") or findDescendantByNames(root, { "Game" }, nil)
	local menuBottomBar = menu and (menu:FindFirstChild("BottomBar") or findDescendantByNames(menu, { "BottomBar" }, nil)) or nil
	local menuMainRow = menu and (menu:FindFirstChild("MainRow") or findDescendantByNames(menu, { "MainRow" }, nil)) or nil
	local gameTopBar = game and (game:FindFirstChild("TopBar") or findDescendantByNames(game, { "TopBar" }, nil)) or nil
	local gameTopBarContainer = gameTopBar and (gameTopBar:FindFirstChild("Container") or findDescendantByNames(gameTopBar, { "Container" }, nil)) or gameTopBar
	local gameBottomBar = game and (
		game:FindFirstChild("BottomBar")
			or game:FindFirstChild("BottomBarShell")
			or findDescendantByNames(game, { "BottomBar", "BottomBarShell" }, nil)
	) or nil

	local shopFrame = frames and frames:FindFirstChild("Shop") or nil
	local shopRoot = shopFrame and (shopFrame:FindFirstChild("Frame") or findDescendantByNames(shopFrame, { "Frame" }, nil)) or shopFrame
	local shopCards = shopRoot and (shopRoot:FindFirstChild("ShopFrame") or shopRoot:FindFirstChild("Shopframe") or findDescendantByNames(shopRoot, { "ShopFrame", "Shopframe" }, nil)) or nil
	local shopCurrencyToggle = ensureShopCurrencyToggle(shopRoot)

	local leaderboardFrame = frames and (frames:FindFirstChild("Leaderboards") or frames:FindFirstChild("Leaderboard")) or nil
	local leaderboardRoot = leaderboardFrame and (leaderboardFrame:FindFirstChild("Frame") or findDescendantByNames(leaderboardFrame, { "Frame" }, nil)) or leaderboardFrame
	local dailyFrame = frames and (frames:FindFirstChild("DailyReward") or frames:FindFirstChild("DailyRewards") or frames:FindFirstChild("Daily")) or nil
	local dailyRoot = dailyFrame and (dailyFrame:FindFirstChild("Frame") or findDescendantByNames(dailyFrame, { "Frame" }, nil)) or dailyFrame
	local settingsFrame = frames and frames:FindFirstChild("Settings") or nil
	local settingsRoot = settingsFrame and (settingsFrame:FindFirstChild("Frame") or findDescendantByNames(settingsFrame, { "Frame" }, nil)) or settingsFrame
	local settingsContainer = settingsRoot and (findFirstPath(settingsRoot, { { "ScrollingFrame" }, { "Container" } }, nil) or settingsRoot) or nil
	local statsFrame = frames and (frames:FindFirstChild("Statistics") or frames:FindFirstChild("Stats")) or nil
	local statsRoot = statsFrame and (statsFrame:FindFirstChild("Frame") or findDescendantByNames(statsFrame, { "Frame" }, nil)) or statsFrame
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
			or statsRoot
		)
		or nil
	local verifyFrame = frames and frames:FindFirstChild("Verify") or nil
	local verifyRoot = verifyFrame and (verifyFrame:FindFirstChild("Frame") or findDescendantByNames(verifyFrame, { "Frame" }, nil)) or verifyFrame
	local customFrame = frames and frames:FindFirstChild("CustomFrame") or nil
	local customRoot = customFrame and (customFrame:FindFirstChild("Frame") or findDescendantByNames(customFrame, { "Frame" }, nil)) or customFrame
	local timedRewards = game and (game:FindFirstChild("TimedRewards") or findDescendantByNames(game, { "TimedRewards" }, nil)) or nil
	local timedRewardsFrame = frames and (frames:FindFirstChild("TimedRewards") or findDescendantByNames(frames, { "TimedRewards" }, nil)) or nil
	local timedRewardsFrameRoot = timedRewardsFrame and (timedRewardsFrame:FindFirstChild("Frame") or findDescendantByNames(timedRewardsFrame, { "Frame" }, nil)) or timedRewardsFrame
	local leaderboardButtonsRoot = leaderboardRoot and leaderboardRoot:FindFirstChild("Buttons") or nil
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
		menuDailyButton = findButtonLike(menuDailyRoot),
		menuDailyAlert = findDescendantByNames(menuDailyRoot, { "Alert", "alert", "Aelrt" }, nil),
		menuLeaderboardButton = findButtonLike(findFirstPath(menuBottomBar, { { "Leaderboard" }, { "Leaderboards" } }, nil)) or findButtonLike(menuBottomBar and findDescendantByNames(menuBottomBar, { "Leaderboard", "Leaderboards" }, nil) or nil),
		menuSettingsButton = findButtonLike(settingsButtonRoot),
		menuStatsButton = findButtonLike(statsButtonRoot),
		menuShopButton = findButtonLike(findPath(menuMainRow, { "Holder_Shop", "ShopButton" }, nil)) or findButtonLike(menuMainRow and findDescendantByNames(menuMainRow, { "Holder_Shop", "ShopButton" }, nil) or nil),
		topBarShopButton = findButtonLike(findPath(gameTopBarContainer, { "Shop" }, nil)) or findButtonLike(gameTopBarContainer and findDescendantByNames(gameTopBarContainer, { "Shop" }, nil) or nil),
		timedRewards = timedRewards,
		timedRewardsTimer = timedRewards and (findFirstPath(timedRewards, { { "Timer", "Timer" }, { "Timer" } }, nil) or findTextObject(timedRewards, { "Timer" })) or nil,
		timedRewardsReward = findButtonLike(timedRewards and findFirstPath(timedRewards, { { "Reward" } }, nil) or nil)
			or (timedRewards and findFirstPath(timedRewards, { { "Reward" } }, nil) or nil),
		timedRewardsRewardPrimary = timedRewards and findFirstPath(timedRewards, { { "Reward", "Primary" } }, nil) or nil,
		timedRewardsRewardSecondary = timedRewards and findFirstPath(timedRewards, { { "Reward", "Secondary" } }, nil) or nil,
		timedRewardsRewardPrimaryLabel = timedRewards and findFirstPath(timedRewards, { { "Reward", "PrimaryLabel" } }, nil) or nil,
		timedRewardsRewardSecondaryLabel = timedRewards and findFirstPath(timedRewards, { { "Reward", "SecondaryLabel" } }, nil) or nil,
		timedRewardsRewardDescription = timedRewards and findFirstPath(timedRewards, { { "Reward", "Description" } }, nil) or nil,
		timedRewardsButton = findButtonLike(findFirstPath(timedRewards, { { "Button" } }, nil) or timedRewards),
		timedRewardsButtonAlert = timedRewards and (
			findFirstPath(timedRewards, { { "Button", "Alert" }, { "Button", "Notification" }, { "Button", "Notifcation" }, { "Button", "Badge" } }, nil)
			or findDescendantByNames(findFirstPath(timedRewards, { { "Button" } }, nil) or timedRewards, { "Alert", "Notification", "Notifcation", "Badge" }, nil)
		) or nil,
		timedRewardsFrame = timedRewardsFrame,
		timedRewardsFrameRoot = timedRewardsFrameRoot,
		timedRewardsFrameQuit = findButtonLike(findFirstPath(timedRewardsFrame, { { "Frame", "Quit" }, { "Frame", "Exit" }, { "Frame", "Back", "Button" } }, nil))
			or findButtonLike(timedRewardsFrame and findDescendantByNames(timedRewardsFrame, { "Quit", "Exit", "Back" }, nil) or nil),
		timedRewardsFrameTimer = timedRewardsFrameRoot and (findFirstPath(timedRewardsFrameRoot, { { "Timer", "Timer" }, { "Timer" } }, nil) or findTextObject(timedRewardsFrameRoot, { "Timer" })) or nil,
		timedRewardsFrameReward = findButtonLike(timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward" } }, nil) or nil)
			or (timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward" } }, nil) or nil),
		timedRewardsFrameRewardPrimary = timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward", "Primary" } }, nil) or nil,
		timedRewardsFrameRewardSecondary = timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward", "Secondary" } }, nil) or nil,
		timedRewardsFrameRewardPrimaryLabel = timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward", "PrimaryLabel" } }, nil) or nil,
		timedRewardsFrameRewardSecondaryLabel = timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward", "SecondaryLabel" } }, nil) or nil,
		timedRewardsFrameRewardDescription = timedRewardsFrameRoot and findFirstPath(timedRewardsFrameRoot, { { "Reward", "Description" } }, nil) or nil,
		hintAvailableLabel = gameHintRoot and findFirstPath(gameHintRoot, { { "Available" } }, nil) or nil,
		hintNotification = gameHintRoot and findFirstPath(gameHintRoot, { { "Notification" } }, nil) or nil,
		hintNotificationAmount = gameHintRoot and findFirstPath(gameHintRoot, { { "Notification", "Amount" } }, nil) or nil,
		shopFrame = shopFrame,
		shopBack = findButtonLike(findFirstPath(shopFrame, { { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(shopFrame and findDescendantByNames(shopFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		shopTitleDisplay = shopRoot and findTextObject(shopRoot, { "Display", "Title" }) or nil,
		shopCurrencyToggle = shopCurrencyToggle,
		shopPuzzlePiecesDisplay = shopRoot and (
			findFirstPath(shopRoot, { { "PuzzlePieces" }, { "PuzzlePiecesDisplay" }, { "Title", "PuzzlePieces" } }, nil)
			or findDescendantByNames(shopRoot, { "PuzzlePieces", "PuzzlePiecesDisplay" }, nil)
		) or nil,
		shopOneHintCard = shopCards and (findDescendantByNames(shopCards, { "OneHint", "OneHints" }, nil) or nil) or nil,
		shopFiveHintCard = shopCards and (findDescendantByNames(shopCards, { "FiveHint", "FiveHints" }, nil) or nil) or nil,
		shopTwentyFiveHintCard = shopCards and (findDescendantByNames(shopCards, { "TwentyFiveHint", "TwentyFiveHints" }, nil) or nil) or nil,
		shopOneHintButton = findButtonLike(shopCards and findDescendantByNames(shopCards, { "OneHint", "OneHints" }, nil) or nil),
		shopFiveHintButton = findButtonLike(shopCards and findDescendantByNames(shopCards, { "FiveHint", "FiveHints" }, nil) or nil),
		shopTwentyFiveHintButton = findButtonLike(shopCards and findDescendantByNames(shopCards, { "TwentyFiveHint", "TwentyFiveHints" }, nil) or nil),
		shopOneHintPrice = shopCards and findDescendantByNames(findDescendantByNames(shopCards, { "OneHint", "OneHints" }, nil) or shopCards, { "Price", "Price2", "Amount" }, nil) or nil,
		shopFiveHintPrice = shopCards and findDescendantByNames(findDescendantByNames(shopCards, { "FiveHint", "FiveHints" }, nil) or shopCards, { "Price", "Price2", "Amount" }, nil) or nil,
		shopTwentyFiveHintPrice = shopCards and findDescendantByNames(findDescendantByNames(shopCards, { "TwentyFiveHint", "TwentyFiveHints" }, nil) or shopCards, { "Price", "Price2", "Amount" }, nil) or nil,
		shopOneHintPriceLabel = shopCards and findDescendantByNames(findDescendantByNames(shopCards, { "OneHint", "OneHints" }, nil) or shopCards, { "PriceLabel" }, nil) or nil,
		shopFiveHintPriceLabel = shopCards and findDescendantByNames(findDescendantByNames(shopCards, { "FiveHint", "FiveHints" }, nil) or shopCards, { "PriceLabel" }, nil) or nil,
		shopTwentyFiveHintPriceLabel = shopCards and findDescendantByNames(findDescendantByNames(shopCards, { "TwentyFiveHint", "TwentyFiveHints" }, nil) or shopCards, { "PriceLabel" }, nil) or nil,
		shopCoinsOneButton = findButtonLike(shopRoot and findDescendantByNames(shopRoot, { "CoinsOne" }, nil) or nil),
		shopCoinsTwoButton = findButtonLike(shopRoot and findDescendantByNames(shopRoot, { "CoinsTwo" }, nil) or nil),
		shopCoinsThreeButton = findButtonLike(shopRoot and findDescendantByNames(shopRoot, { "CoinsThree" }, nil) or nil),
		shopCoinsOnePrice = shopRoot and findShopPriceLabel(findDescendantByNames(shopRoot, { "CoinsOne" }, nil) or nil) or nil,
		shopCoinsTwoPrice = shopRoot and findShopPriceLabel(findDescendantByNames(shopRoot, { "CoinsTwo" }, nil) or nil) or nil,
		shopCoinsThreePrice = shopRoot and findShopPriceLabel(findDescendantByNames(shopRoot, { "CoinsThree" }, nil) or nil) or nil,
		dailyFrame = dailyFrame,
		dailyBack = findButtonLike(findFirstPath(dailyFrame, { { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(dailyFrame and findDescendantByNames(dailyFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		dailyBody = dailyRoot and (findTextObject(findFirstPath(dailyRoot, { { "Body" }, { "Description" }, { "Desc" }, { "Container", "Body" }, { "Container", "Description" } }, nil) or dailyRoot, { "Body", "Description", "Desc", "Sub", "Status" })) or nil,
		dailyStatus = dailyRoot and (findTextObject(findFirstPath(dailyRoot, { { "Sub" }, { "Status" }, { "Timer" }, { "Reset" }, { "Countdown" } }, nil) or dailyRoot, { "Status", "Sub", "Timer", "Reset", "Countdown" })) or nil,
		dailyClaim = findButtonLike(findFirstPath(dailyRoot, {
			{ "Buttons", "Green", "Button" },
			{ "Buttons", "Claim", "Button" },
			{ "Green", "Button" },
			{ "Claim", "Button" },
			{ "Buttons", "Green" },
			{ "Buttons", "Claim" },
			{ "Green" },
			{ "Claim" },
		}, nil))
			or findButtonLike(dailyRoot and findDescendantByNames(dailyRoot, { "DailyClaim", "ClaimButton", "Claim", "Green", "Collect", "Redeem" }, nil) or nil)
			or findButtonLike(dailyFrame and findDescendantByNames(dailyFrame, { "DailyClaim", "ClaimButton", "Claim", "Green", "Collect", "Redeem" }, nil) or nil),
		dailyClaimLabel = dailyRoot and findTextObject(
			findFirstPath(dailyRoot, {
				{ "Buttons", "Green", "Label" },
				{ "Buttons", "Claim", "Label" },
			{ "Green", "Label" },
			{ "Claim", "Label" },
		}, nil) or dailyRoot,
			{ "Label", "TextLabel" }
		) or nil,
		settingsFrame = settingsFrame,
		settingsBack = findButtonLike(findFirstPath(settingsFrame, { { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(settingsFrame and findDescendantByNames(settingsFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		settingsSFX = findButtonLike(settingsContainer and findDescendantByNames(settingsContainer, { "SFX" }, nil) or nil),
		settingsMusic = findButtonLike(settingsContainer and findDescendantByNames(settingsContainer, { "Music" }, nil) or nil),
		settingsNumbers = findButtonLike(settingsContainer and findDescendantByNames(settingsContainer, { "DotNumbers", "DotNumber", "Numbers" }, nil) or nil),
		settingsColorblind = findButtonLike(settingsContainer and findDescendantByNames(settingsContainer, { "ColorBlind", "Colorblind" }, nil) or nil),
		statsFrame = statsFrame,
		statsRoot = statsRoot,
		statsContainer = statsContainer,
		statsBack = findButtonLike(findFirstPath(statsFrame, { { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(statsFrame and findDescendantByNames(statsFrame, { "Back", "Quit", "Exit" }, nil) or nil),
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
		leaderboardBack = findButtonLike(findFirstPath(leaderboardFrame, { { "Back", "Button" }, { "Frame", "Quit" }, { "Frame", "Exit" } }, nil)) or findButtonLike(leaderboardFrame and findDescendantByNames(leaderboardFrame, { "Back", "Quit", "Exit" }, nil) or nil),
		leaderboardTitle = leaderboardRoot and findTextObject(leaderboardRoot, { "Title" }) or nil,
		leaderboardUpdateTime = leaderboardRoot and findTextObject(leaderboardRoot, { "UpdateTime" }) or nil,
		leaderboardRanksButton = findButtonLike(findFirstPath(leaderboardFrame, { { "Frame", "Buttons", "Ranks", "Button" }, { "Frame", "Buttons", "Ranks" } }, nil)) or findButtonLike(leaderboardButtonsRoot and leaderboardButtonsRoot:FindFirstChild("Ranks") or nil),
		leaderboardSolvesButton = findButtonLike(findFirstPath(leaderboardFrame, { { "Frame", "Buttons", "Solves", "Button" }, { "Frame", "Buttons", "Solves" } }, nil)) or findButtonLike(leaderboardButtonsRoot and leaderboardButtonsRoot:FindFirstChild("Solves") or nil),
		leaderboardRanksStroke = findFirstPath(leaderboardFrame, { { "Frame", "Buttons", "Ranks", "Button", "UIStroke" }, { "Frame", "Buttons", "Ranks", "UIStroke" } }, "UIStroke"),
		leaderboardSolvesStroke = findFirstPath(leaderboardFrame, { { "Frame", "Buttons", "Solves", "Button", "UIStroke" }, { "Frame", "Buttons", "Solves", "UIStroke" } }, "UIStroke"),
		leaderboardRanksContainer = findFirstPath(leaderboardFrame, { { "Frame", "ContainerRanks" }, { "ContainerRanks" } }, nil),
		leaderboardSolvesContainer = findFirstPath(leaderboardFrame, { { "Frame", "ContainerSolves" }, { "ContainerSolves" }, { "Frame", "Container" }, { "Container" } }, nil),
		verifyFrame = verifyFrame,
		verifyExit = findButtonLike(verifyRoot and findDescendantByNames(verifyRoot, { "Exit", "Quit", "Close" }, nil) or nil),
		verifyJoin = findButtonLike(verifyRoot and findDescendantByNames(verifyRoot, { "Join" }, nil) or nil),
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

	ensureListLayout(self.elements.leaderboardSolvesContainer)
	ensureBottomPadding(self.elements.leaderboardSolvesContainer, "WordSearchLeaderboardBottomPadding", LEADERBOARD_BOTTOM_PADDING)
	ensureBottomPadding(self.elements.leaderboardRanksContainer, "WordSearchLeaderboardBottomPadding", LEADERBOARD_BOTTOM_PADDING)
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
	local hintsAvailable = snapshot and snapshot.inventory and snapshot.inventory.hintsAvailable or getIntValue(getDataFolders().hints, "Available", 0)
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
	return snapshot and snapshot.inventory and math.max(0, math.floor(tonumber(snapshot.inventory.puzzlePieces) or 0))
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

function ProgressionController:getHintProductPrice(amount)
	local hintAmount = math.max(0, math.floor(tonumber(amount) or 0))
	local cachedPrice = self.hintProductPrices[hintAmount]
	if cachedPrice ~= nil then
		return cachedPrice
	end

	local productId = HINT_PRODUCT_IDS[hintAmount]
	if type(productId) ~= "number" then
		return nil
	end

	if self.hintProductPriceRequests[hintAmount] then
		return nil
	end

	self.hintProductPriceRequests[hintAmount] = true
	task.spawn(function()
		local resolvedPrice = nil
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" then
			resolvedPrice = tonumber(info.PriceInRobux)
		end

		self.hintProductPrices[hintAmount] = resolvedPrice or false
		task.defer(function()
			self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
		end)
	end)

	return nil
end

function ProgressionController:getHintPackPriceText(amount)
	if self.shopHintCurrency == SHOP_HINT_CURRENCY_PIECES then
		return formatPuzzlePiecePrice(PuzzleEconomy.GetHintPackCost(amount))
	end

	local price = self:getHintProductPrice(amount)
	if price == false then
		return "Robux"
	end

	return formatRobuxPrice(price)
end

function ProgressionController:updateShopCurrencyToggle()
	local toggleRoot = self.elements.shopCurrencyToggle
	local toggle = toggleRoot and (toggleRoot:FindFirstChild("TextLabel") or toggleRoot)
	if not toggle then
		return
	end

	if self.shopHintCurrency == SHOP_HINT_CURRENCY_PIECES then
		setText(toggle, "Use Robux")
	--	toggle.BackgroundColor3 = Color3.fromRGB(72, 92, 60)
	else
		setText(toggle, "Use Puzzle Pieces")
	--	toggle.BackgroundColor3 = Color3.fromRGB(33, 42, 60)
	end
end

function ProgressionController:updateShopTexts(snapshot)
	local function hideShopEntry(button)
		setVisible(button, false)
		if button and button.Parent and button.Parent:IsA("GuiObject") then
			setVisible(button.Parent, false)
		end
	end

	if self.elements.shopTitleDisplay then
		setText(self.elements.shopTitleDisplay, "Hint Shop")
	end
	self:updatePuzzlePiecesDisplay(snapshot)
	self:updateShopCurrencyToggle()
	applyHintPackPrice(self.elements.shopOneHintPrice, self.elements.shopOneHintPriceLabel, self:getHintPackPriceText(1))
	applyHintPackPrice(self.elements.shopFiveHintPrice, self.elements.shopFiveHintPriceLabel, self:getHintPackPriceText(5))
	applyHintPackPrice(
		self.elements.shopTwentyFiveHintPrice,
		self.elements.shopTwentyFiveHintPriceLabel,
		self:getHintPackPriceText(25)
	)
	setupFeaturedPackPulse(self.elements.shopTwentyFiveHintCard)
	hideShopEntry(self.elements.shopCoinsOneButton)
	hideShopEntry(self.elements.shopCoinsTwoButton)
	hideShopEntry(self.elements.shopCoinsThreeButton)
	setVisible(self.elements.shopCoinsOnePrice, false)
	setVisible(self.elements.shopCoinsTwoPrice, false)
	setVisible(self.elements.shopCoinsThreePrice, false)
end

function ProgressionController:updateStats(snapshot)
	local folders = getDataFolders()
	local progress = folders.progress
	local progressionFolder = folders.progression
	local statsFolder = folders.stats
	local hints = folders.hints
	local timedRewards = folders.timedRewards
	local winsFolder = folders.progressWins
	local lossesFolder = folders.progressLosses
	local streaksFolder = folders.progressStreaks
	local stats = snapshot and snapshot.stats or {}
	local progression = snapshot and snapshot.progression or {}
	local totalSnapshotWins, totalSnapshotLosses = getSnapshotModeBucket(snapshot, "Total")
	local totalWins = getIntValue(
		winsFolder,
		"Total",
		math.max(0, math.floor(tonumber(stats.boardsCleared) or totalSnapshotWins or 0))
	)
	local totalLosses = getIntValue(
		lossesFolder,
		"Total",
		math.max(0, math.floor(tonumber(stats.losses) or totalSnapshotLosses or 0))
	)
	local availableHints = snapshot and snapshot.inventory and snapshot.inventory.hintsAvailable or getIntValue(hints, "Available", 0)
	local usedHints = stats.hintsUsed
	if usedHints == nil then
		usedHints = getIntValue(statsFolder, "HintsUsed", getIntValue(hints, "TotalUsed", 0))
	end
	local totalPlaySeconds = stats.totalPlaySeconds
	if totalPlaySeconds == nil then
		totalPlaySeconds = getIntValue(timedRewards, "Playtime", getIntValue(statsFolder, "TotalPlaySeconds", 0))
	end
	local totalWordsFound = stats.totalWordsFound
	if totalWordsFound == nil then
		totalWordsFound = getIntValue(statsFolder, "TotalWordsFound", 0)
	end
	local currentStreak = stats.currentStreak
	if currentStreak == nil then
		currentStreak = getIntValue(statsFolder, "CurrentStreak", 0)
	end
	local highestStreak = stats.highestStreak
	if highestStreak == nil then
		highestStreak = getIntValue(statsFolder, "HighestStreak", getIntValue(statsFolder, "LongestStreak", 0))
	end
	local highestClassicLevel = progression.highestClassicLevel
	if highestClassicLevel == nil then
		highestClassicLevel = getIntValue(progressionFolder, "HighestClassicLevel", 1)
	end
	local fastestMillis = stats.fastestBoardClearMillis or 0
	local fastestText = "--"
	if math.max(0, math.floor(tonumber(fastestMillis) or 0)) > 0 then
		fastestText = string.format("%.2fs", fastestMillis / 1000)
	else
		local fastestStored = progress and progress:FindFirstChild("FastestSolve")
		local asNumber = tonumber(fastestStored and tostring(fastestStored.Value) or "0")
		if asNumber and asNumber > 0 then
			fastestText = string.format("%.2fs", asNumber)
		end
	end
	local dailyClears = getIntValue(progress, "DailySolves", 0)
	local generalValues = {
		general_wins = tostring(totalWins),
		general_losses = tostring(totalLosses),
		general_win_ratio = formatWinRatio(totalWins, totalLosses),
		general_highest_streak = tostring(math.max(0, math.floor(tonumber(highestStreak) or 0))),
		general_current_streak = tostring(math.max(0, math.floor(tonumber(currentStreak) or 0))),
		general_words_found = tostring(math.max(0, math.floor(tonumber(totalWordsFound) or 0))),
		general_hints_used = tostring(math.max(0, math.floor(tonumber(usedHints) or 0))),
		general_daily_clears = tostring(dailyClears),
		general_fastest_solve = fastestText,
		general_playtime = formatClock(totalPlaySeconds),
		general_highest_classic = tostring(math.max(1, math.floor(tonumber(highestClassicLevel) or 1))),
	}

	if ensureStatsLayout(self.elements) then
		for key, value in pairs(generalValues) do
			setText(statsRuntime.valueNodes[key], value)
		end

		for _, modeInfo in ipairs(MODE_SECTION_ORDER) do
			local snapshotWins, snapshotLosses = getSnapshotModeBucket(snapshot, modeInfo.key)
			local snapshotCurrentStreak, snapshotBestStreak = getSnapshotModeStreakBucket(snapshot, modeInfo.key)
			local modeWins = getIntValue(winsFolder, modeInfo.key, snapshotWins)
			local modeLosses = getIntValue(lossesFolder, modeInfo.key, snapshotLosses)
			local modeStreakFolder = streaksFolder and streaksFolder:FindFirstChild(modeInfo.key) or nil
			local modeCurrentStreak = getIntValue(modeStreakFolder, "Current", snapshotCurrentStreak)
			local modeBestStreak = getIntValue(modeStreakFolder, "Best", snapshotBestStreak)
			setText(statsRuntime.valueNodes[string.format("mode_%s_best_streak", modeInfo.key)], tostring(modeBestStreak))
			setText(statsRuntime.valueNodes[string.format("mode_%s_current_streak", modeInfo.key)], tostring(modeCurrentStreak))
			setText(statsRuntime.valueNodes[string.format("mode_%s_wins", modeInfo.key)], tostring(modeWins))
			setText(statsRuntime.valueNodes[string.format("mode_%s_losses", modeInfo.key)], tostring(modeLosses))
			setText(
				statsRuntime.valueNodes[string.format("mode_%s_win_ratio", modeInfo.key)],
				formatWinRatio(modeWins, modeLosses)
			)
		end

		return
	end

	setText(self.elements.statsDailySolve, tostring(dailyClears))
	setText(self.elements.statsFastest, fastestText)
	setText(self.elements.statsHints, string.format("%d / %d", math.max(0, math.floor(tonumber(usedHints) or 0)), availableHints))
	setText(self.elements.statsPlaytime, formatClock(totalPlaySeconds))
	setText(self.elements.statsSolves, tostring(totalWins))
	setText(self.elements.statsTimedSolve, formatWinRatio(totalWins, totalLosses))
	setText(self.elements.statsWinRatioTitle, "Win Ratio")
	setVisible(self.elements.statsRank, false)
	setVisible(self.elements.statsXP, false)
	setVisible(self.elements.statsRank and self.elements.statsRank.Parent, false)
	setVisible(self.elements.statsXP and self.elements.statsXP.Parent, false)
end

function ProgressionController:updateSettings()
	local settings = getDataFolders().settings
	setButtonStateColor(self.elements.settingsSFX, getBoolValue(settings, "SFX", true))
	setButtonStateColor(self.elements.settingsMusic, getBoolValue(settings, "Music", true))
	hideSettingElement(self.elements.settingsNumbers)
	hideSettingElement(self.elements.settingsColorblind)
end

function ProgressionController:updateBottomBarAlerts()
	local dailyClaimable = type(self.dailyRewardState) == "table" and self.dailyRewardState.claimable == true

	setVisible(self.elements.menuDailyAlert, dailyClaimable)
end

function ProgressionController:renderDailyRewardState()
	local state = self.dailyRewardState
	if not state then
		self:updateBottomBarAlerts()
		return
	end

	local currentStreak = math.max(0, math.floor(tonumber(state.currentStreak) or 0))
	local bestStreak = math.max(0, math.floor(tonumber(state.bestStreak) or 0))
	local rewardXp = math.max(0, math.floor(tonumber(state.nextRewardXp) or 0))
	local rewardHints = math.max(0, math.floor(tonumber(state.nextRewardHints) or 0))
	local rewardText = formatRewardInlineRichText(rewardHints, rewardXp)
	local nextRewardLabel = "<font color=\"#F6C14F\">Next Reward:</font>"

	setRichText(self.elements.dailyBody, string.format(
		"Daily Streak: %d day%s\nBest Streak: %d day%s\n%s %s",
		currentStreak,
		currentStreak == 1 and "" or "s",
		bestStreak,
		bestStreak == 1 and "" or "s",
		nextRewardLabel,
		rewardText
	))

	if state.claimable then
		setRichText(self.elements.dailyStatus, string.format(
			"Today's Reward: %s\nResets in %s",
			rewardText,
			formatClock(state.secondsUntilReset or 0)
		))
	else
		setRichText(self.elements.dailyStatus, string.format(
			"Next reward in %s",
			formatClock(state.secondsUntilReset or 0)
		))
	end

	local claimButton = self.elements.dailyClaim
	local claimLabel = self.elements.dailyClaimLabel
	if claimButton then
		if claimLabel then
			setText(claimLabel, state.claimable and "CLAIM" or "OKAY")
		else
			setText(claimButton, state.claimable and "CLAIM" or "OKAY")
		end
		claimButton.Visible = true
		claimButton.Active = true
		claimButton.Selectable = true
	end

	self:updateBottomBarAlerts()
end

function ProgressionController:refreshDailyRewardState()
	local remote = self.remotes.getDailyRewardState
	if not remote then
		return
	end

	local result
	local ok = pcall(function()
		result = remote:InvokeServer()
	end)
	if ok and type(result) == "table" and result.success then
		self.dailyRewardState = result
	end
	self:renderDailyRewardState()
end

function ProgressionController:renderLeaderboard()
	local elements = self.elements
	local container = elements.leaderboardSolvesContainer or elements.leaderboardRanksContainer
	if not container then
		return
	end

	clearRuntimeEntries(container, "RuntimeEntry")
	if elements.leaderboardRanksContainer and elements.leaderboardRanksContainer ~= container then
		setVisible(elements.leaderboardRanksContainer, false)
	end
	setVisible(container, true)
	if elements.leaderboardRanksButton then
		elements.leaderboardRanksButton.Active = false
	end
	if elements.leaderboardRanksStroke then
		elements.leaderboardRanksStroke.Enabled = false
	end
	if elements.leaderboardSolvesStroke then
		elements.leaderboardSolvesStroke.Enabled = true
	end
	setText(elements.leaderboardTitle, "SOLVES")

	local entriesToRender = self.leaderboardEntries
	if type(entriesToRender) ~= "table" or #entriesToRender == 0 then
		entriesToRender = getLiveSolvesFallbackEntries()
	end

	local playerTemplate = getTemplate("PlayerTemplate")
	if not playerTemplate then
		return
	end

	for index = 1, math.min(10, #entriesToRender) do
		local entryData = entriesToRender[index]
		local entry = playerTemplate:Clone()
		entry.Name = "RuntimeEntry"
		entry.LayoutOrder = index
		entry.Visible = true
		entry.Parent = container

		local username = entry:FindFirstChild("Username", true)
		local rank = entry:FindFirstChild("Rank", true)
		local score = entry:FindFirstChild("Score", true)
		local profile = entry:FindFirstChild("Profile", true)

		setText(username, entryData.Username or "Unknown")
		setText(rank, "#" .. tostring(entryData.Rank or index))
		setText(score, tostring(entryData.Score or 0))

		if profile and (profile:IsA("ImageLabel") or profile:IsA("ImageButton")) then
			profile.Image = tostring(entryData.Thumbnail or "")
			profile.BackgroundTransparency = 1
		end
	end

	local layout = container:FindFirstChildWhichIsA("UIListLayout")
	if container:IsA("ScrollingFrame") and layout then
		container.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8 + LEADERBOARD_BOTTOM_PADDING)
	end

	if self.leaderboardUpdatedAt > 0 then
		local seconds = math.max(0, MetaConfig.LEADERBOARD.RefreshInterval - math.max(0, os.time() - self.leaderboardUpdatedAt))
		setText(elements.leaderboardUpdateTime, string.format("refresh in %s", formatClock(seconds)))
	end
end

function ProgressionController:requestLeaderboardRefresh()
	if self.remotes.requestLeaderboardUpdateSolves then
		self.remotes.requestLeaderboardUpdateSolves:FireServer()
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

function ProgressionController:showHintPurchaseReward(amount)
	local hintAmount = math.max(0, math.floor(tonumber(amount) or 0))
	if hintAmount <= 0 then
		return
	end

	self:showAlert("Hints", string.format("+%d Hint%s", hintAmount, hintAmount == 1 and "" or "s"), "reward", {
		duration = 2.2,
		color = Color3.fromRGB(92, 215, 118),
		soundName = "Purchase",
	})
end

function ProgressionController:handleHintPurchase(amount)
	local pieceCost = PuzzleEconomy.GetHintPackCost(amount)
	local productId = HINT_PRODUCT_IDS[amount]

	if self.shopHintCurrency ~= SHOP_HINT_CURRENCY_PIECES then
		if type(productId) == "number" then
			self:promptProductPurchase(productId)
		else
			self:showAlert("Shop", "Hint product is not configured.", "error", {
				duration = 2.2,
			})
		end
		return
	end

	local localBalance = self:getPuzzlePiecesBalance(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)

	if pieceCost and self.remotes.purchaseHintsWithCoins then
		if localBalance < pieceCost then
			self:flashPuzzlePiecesDisplay()
			if type(productId) == "number" then
				self:promptProductPurchase(productId)
			else
				self:showAlert("Shop", "Not enough Puzzle Pieces.", "error", {
					duration = 2.2,
				})
			end
			return
		end

		local result
		local ok = pcall(function()
			result = self.remotes.purchaseHintsWithCoins:InvokeServer(amount)
		end)
		if ok and type(result) == "table" and result.success then
			if result.snapshot and self.ctx.applySnapshot then
				self.ctx.applySnapshot(result.snapshot)
			else
				self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
			end
			self:showPuzzlePieceSpendFloat(result.cost or pieceCost)
			self:showHintPurchaseReward(result.amount or amount)
			return
		end

		if type(result) == "table" and result.code == "insufficient_pieces" then
			self:flashPuzzlePiecesDisplay()
			if type(productId) == "number" then
				self:promptProductPurchase(productId)
			end
			return
		end

		self:showAlert("Shop", (type(result) == "table" and result.message) or "Hint purchase failed.", "error", {
			duration = 2.2,
		})
		return
	end

	if type(productId) == "number" then
		self:promptProductPurchase(productId)
	else
		self:showAlert("Shop", "Hint product is not configured.", "error", {
			duration = 2.2,
		})
	end
end

function ProgressionController:connectButton(button, callback)
	if not (button and button:IsA("GuiButton")) then
		return
	end

	table.insert(self.connections, button.MouseButton1Click:Connect(callback))
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
	self:connectButton(elements.timedRewardsReward, function()
		local timedRewardState = TimedRewardsUIModule.GetState(self:getTimedRewardsContext())
		if timedRewardState and timedRewardState.canClaim then
			self:claimTimedReward()
			return
		end

		if elements.timedRewardsFrame then
			self:showFrame(elements.timedRewardsFrame)
		end
	end)
	self:connectButton(elements.timedRewardsButton, function()
		local canUseTopBarActions = canUseGameplayTopBarActions()
		local timedRewardState = TimedRewardsUIModule.GetState(self:getTimedRewardsContext())
		if not canUseTopBarActions then
			return
		end

		if timedRewardState and timedRewardState.allClaimed ~= true and elements.timedRewardsFrame then
			self:showFrame(elements.timedRewardsFrame)
		end
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
	self:connectButton(elements.leaderboardBack, function()
		self:hideFrame(elements.leaderboardFrame)
	end)
	self:connectButton(elements.timedRewardsFrameQuit, function()
		self:hideFrame(elements.timedRewardsFrame)
	end)
	self:connectButton(elements.verifyExit, function()
		self:hideFrame(elements.verifyFrame)
	end)
	self:connectButton(elements.timedRewardsFrameReward, function()
		local timedRewardState = TimedRewardsUIModule.GetState(self:getTimedRewardsContext())
		if timedRewardState and timedRewardState.canClaim then
			self:claimTimedReward()
		end
	end)

	self:connectButton(elements.dailyClaim, function()
		if not (self.dailyRewardState and self.dailyRewardState.claimable == true) then
			self:hideFrame(elements.dailyFrame)
			return
		end

		local remote = self.remotes.claimDailyReward
		if not remote then
			return
		end

		local result
		local ok = pcall(function()
			result = remote:InvokeServer()
		end)
		if ok and type(result) == "table" and result.success then
			self.dailyRewardState = result.state
			if result.snapshot and self.ctx.applySnapshot then
				self.ctx.applySnapshot(result.snapshot)
			end
			self:renderDailyRewardState()

			local rewardText = formatRewardAmountText(result.rewardHints, result.rewardXp)
			self:showAlert("Daily Reward", rewardText, "reward", {
				duration = 2.4,
			})
		else
			self:showAlert("Daily Reward", (type(result) == "table" and result.message) or "Unable to claim daily reward.", "error", {
				duration = 2.2,
			})
		end
	end)

	self:connectButton(elements.settingsSFX, function()
		if self.remotes.updateSetting then
			local nextEnabled = not getBoolValue(getDataFolders().settings, "SFX", true)
			setButtonStateColor(elements.settingsSFX, nextEnabled)
			local snapshot = self.ctx.getSnapshot and self.ctx.getSnapshot() or nil
			if type(snapshot) == "table" then
				snapshot.settings = snapshot.settings or {}
				snapshot.settings.SFX = nextEnabled
				if self.ctx.applySnapshot then
					self.ctx.applySnapshot(snapshot)
				end
			end
			self.remotes.updateSetting:FireServer("SFX", nextEnabled)
		end
	end)
	self:connectButton(elements.settingsMusic, function()
		if self.remotes.updateSetting then
			local nextEnabled = not getBoolValue(getDataFolders().settings, "Music", true)
			setButtonStateColor(elements.settingsMusic, nextEnabled)
			local snapshot = self.ctx.getSnapshot and self.ctx.getSnapshot() or nil
			if type(snapshot) == "table" then
				snapshot.settings = snapshot.settings or {}
				snapshot.settings.Music = nextEnabled
				if self.ctx.applySnapshot then
					self.ctx.applySnapshot(snapshot)
				end
			end
			self.remotes.updateSetting:FireServer("Music", nextEnabled)
		end
	end)

	self:connectButton(elements.shopOneHintButton, function()
		self:handleHintPurchase(1)
	end)
	self:connectButton(elements.shopFiveHintButton, function()
		self:handleHintPurchase(5)
	end)
	self:connectButton(elements.shopTwentyFiveHintButton, function()
		self:handleHintPurchase(25)
	end)
	self:connectButton(elements.shopCurrencyToggle, function()
		self.shopHintCurrency = (self.shopHintCurrency == SHOP_HINT_CURRENCY_PIECES) and SHOP_HINT_CURRENCY_ROBUX or SHOP_HINT_CURRENCY_PIECES
		self:updateShopTexts(self.ctx.getSnapshot and self.ctx.getSnapshot() or nil)
	end)

	self:connectButton(elements.verifyJoin, function()
		if not self:getVerifiedGroupInfo() then
			self:showAlert("Group", "Unable to open the group right now.", "error", {
				duration = 2.2,
			})
			return
		end

		local prompted = false
		pcall(function()
			GroupService:PromptJoinAsync(MetaConfig.GROUP.Id)
			prompted = true
		end)

		if self:isPlayerInGroup() and self.remotes.playerJoinedGroup and self.groupClaimRequestPending ~= true then
			self.groupClaimRequestPending = true
			self.remotes.playerJoinedGroup:FireServer()
			return
		end

		if not prompted then
			pcall(function()
				GuiService:OpenBrowserWindow(string.format("https://www.roblox.com/groups/%d", MetaConfig.GROUP.Id))
			end)
		end

		self:startGroupJoinVerificationPoll()
	end)
end

function ProgressionController:connectRemoteEvents()
	if self.remotes.purchaseSuccess then
		table.insert(self.connections, self.remotes.purchaseSuccess.OnClientEvent:Connect(function(kind, amount)
			if kind == "hints" then
				self:showHintPurchaseReward(amount)
			end
		end))
	end

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
			if payload.alreadyClaimed then
				self:showAlert("Group", "Group reward already claimed.", "info", { duration = 2.2 })
				return
			end

			if payload.success then
				self:showAlert("Thanks For Joining", formatRewardAmountText(payload.rewardHints, payload.rewardXp), "reward", { duration = 2.6 })
			elseif payload.message then
				self:showAlert("Group", tostring(payload.message), "error", { duration = 2.2 })
			end
		end))
	end

	if self.remotes.adminMessage then
		table.insert(self.connections, self.remotes.adminMessage.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local text = tostring(payload.text or "")
			if text == "" then
				local title = tostring(payload.title or "")
				local message = tostring(payload.message or "")
				text = title ~= "" and string.format("[%s] %s", title, message) or message
			end
			if text ~= "" then
				displayChatMessage(text, payload.color)
			end
		end))
	end

	if self.remotes.leaderboardUpdateSolves then
		table.insert(self.connections, self.remotes.leaderboardUpdateSolves.OnClientEvent:Connect(function(entries, updatedAt)
			self.leaderboardEntries = type(entries) == "table" and entries or {}
			self.leaderboardUpdatedAt = math.max(0, math.floor(tonumber(updatedAt) or 0))
			self:renderLeaderboard()
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
	self:updateHintText(snapshot)
	self:updateShopTexts(snapshot)
	self:updateStats(snapshot)
	self:updateSettings()
	self:updateTimedRewards()
	self:queueVerifyPrompt(snapshot, nil, true)
end

function ProgressionController:bind(root)
	if self.root then
		self:destroy()
	end
	self.root = root
	self:resolveRemotes()
	self:resolveElements(root)
	self:connectButtons()
	self:connectRemoteEvents()
	self:setupTimedRewards()
	if not self.dailyCountdownLoopStarted then
		self.dailyCountdownLoopStarted = true
		self.dailyCountdownToken += 1
		local dailyCountdownToken = self.dailyCountdownToken
		task.spawn(function()
			while self.dailyCountdownToken == dailyCountdownToken and self.root and self.root.Parent do
				task.wait(1)
				if type(self.dailyRewardState) == "table" then
					self.dailyRewardState.secondsUntilReset = math.max(0, math.floor(tonumber(self.dailyRewardState.secondsUntilReset) or 0) - 1)
					if self.elements.dailyFrame and self.elements.dailyFrame.Visible then
						self:renderDailyRewardState()
					end
				end
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
	self.root = nil
	self.dailyCountdownLoopStarted = false
	self.dailyCountdownToken += 1
	self.verifyPromptQueued = false
	self.groupJoinPollToken += 1
	disconnectAllConnections(self.connections)
	disconnectAllConnections(self.frameConnections)
	disconnectAllConnections(self.timedRewardsDataConnections)

	if self.timedRewardsHeartbeat then
		self.timedRewardsHeartbeat:Disconnect()
		self.timedRewardsHeartbeat = nil
	end
	if self.timedRewardsPulseState and self.timedRewardsPulseState.connection then
		self.timedRewardsPulseState.connection:Disconnect()
		self.timedRewardsPulseState.connection = nil
	end

	self.elements = {}
	self.remotes = {}
	self.modalTokens = setmetatable({}, { __mode = "k" })
end

return ProgressionController
