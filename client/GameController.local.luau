local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if script:IsDescendantOf(StarterPlayer:WaitForChild("StarterPlayerScripts")) then
	return
end

local player = Players.LocalPlayer
local CAMERA = {
	PartName = "CamPart",
	FieldOfView = 40,
}
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local RuntimeHelpers = {}
local CameraRuntime = require(script.Parent:WaitForChild("camera"):WaitForChild("CameraRuntime"))
local BoardRuntimeModule = require(script.Parent:WaitForChild("gameplay"):WaitForChild("BoardRuntime"))
local SummaryRuntimeModule = require(script.Parent:WaitForChild("ui"):WaitForChild("SummaryRuntime"))
local UiBootstrapRuntimeModule = require(script.Parent:WaitForChild("ui"):WaitForChild("UiBootstrapRuntime"))
local ClassicLevels = require(script.Parent:WaitForChild("gameplay"):WaitForChild("ClassicLevels"))
local TimedProductRuntime = require(script.Parent:WaitForChild("gameplay"):WaitForChild("TimedProductRuntime"))
local GuiUtils = require(script.Parent:WaitForChild("ui"):WaitForChild("GuiUtils"))
local ViewTransitions = require(script.Parent:WaitForChild("ui"):WaitForChild("ViewTransitions"))
local ButtonUiModule = require(script.Parent:WaitForChild("ui"):WaitForChild("ButtonUI"))
local InputBindings = require(script.Parent:WaitForChild("input"):WaitForChild("InputBindings"))

local create = GuiUtils.create
local findDescendantByNames = GuiUtils.findDescendantByNames
local waitForDescendantByNames = GuiUtils.waitForDescendantByNames
local findTextObject = GuiUtils.findTextObject
local ensureScaleController = GuiUtils.ensureScaleController
local findButtonLike = GuiUtils.findButtonLike
local findFirstPath = GuiUtils.findFirstPath
local findBarContainer = GuiUtils.findBarContainer
local setBarFillAlpha = GuiUtils.setBarFillAlpha
local tween
local bindButtonHoverSound
local warningOverlayHeartbeatToken = 0
local warningOverlayHeartbeatRunning = false

local DEFAULT_CONFIGS = {
	Meta = {
		DEFAULTS = {
			StartingHints = 0,
			RankSolveStep = 25,
			Settings = {
				SFX = true,
				Music = true,
			},
		},
		TIMED_PRODUCT_IDS = {
			TimeBoost = 3573028604,
			FreezeTime = 3573028785,
		},
	},
	Remote = {
		FolderName = "WordSearchBackendRemotes",
		GetBootstrap = "GetBootstrap",
		TrackAction = "TrackAction",
		StateUpdated = "StateUpdated",
		UseHint = "UseHint",
		UseTimedProduct = "UseTimedProduct",
	},
}
local MODE_RESULT_NAMES = {
	"Total",
	"Classic",
	"Tiny",
	"Mega",
	"Hardcore",
	"Duel",
}
local MODE_STREAK_NAMES = {
	"Classic",
	"Tiny",
	"Mega",
	"Hardcore",
	"Duel",
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

local function setCoreGuiDisabled()
	local coreGuiTypes = {
		Enum.CoreGuiType.Backpack,
		Enum.CoreGuiType.Health,
		Enum.CoreGuiType.EmotesMenu,
		Enum.CoreGuiType.Captures,
	}

	for _, coreGuiType in ipairs(coreGuiTypes) do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, false)
		end)
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
	end)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
	end)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)

	local playerGui = player:FindFirstChild("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui") or nil
	if touchGui then
		touchGui.Enabled = false
		local touchControlFrame = touchGui:FindFirstChild("TouchControlFrame")
		if touchControlFrame and touchControlFrame:IsA("GuiObject") then
			touchControlFrame.Visible = false
		end
	end
end

local function resolveSharedConfigModule(moduleName, fallback)
	local configFolder = sharedFolder:FindFirstChild("config")
	local moduleScript = configFolder and configFolder:FindFirstChild(moduleName) or nil
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" then
			return mergeDefaults(result, cloneTable(fallback))
		end
	end

	return cloneTable(fallback)
end

local function createDefaultSnapshotModeResults()
	local modeResults = {}

	for _, modeName in ipairs(MODE_RESULT_NAMES) do
		modeResults[modeName] = {
			wins = 0,
			losses = 0,
		}
	end

	return modeResults
end

local function createDefaultSnapshotModeStreaks()
	local modeStreaks = {}

	for _, modeName in ipairs(MODE_STREAK_NAMES) do
		modeStreaks[modeName] = {
			current = 0,
			best = 0,
		}
	end

	return modeStreaks
end

local function getSnapshotModeStreakBucket(snapshot, modeName)
	local stats = type(snapshot) == "table" and snapshot.stats or nil
	local modeStreaks = type(stats and stats.modeStreaks) == "table" and stats.modeStreaks or nil
	local bucket = type(modeStreaks and modeStreaks[modeName]) == "table" and modeStreaks[modeName] or nil
	if type(bucket) ~= "table" then
		return 0, 0
	end

	return math.max(0, math.floor(tonumber(bucket.current) or 0)), math.max(0, math.floor(tonumber(bucket.best) or 0))
end

local function resolveModeStreakFromSnapshot(snapshot, modeName, fallbackValue)
	local resolvedMode = tostring(modeName or "")
	local currentStreak = select(1, getSnapshotModeStreakBucket(snapshot, resolvedMode))
	if currentStreak > 0 then
		return currentStreak
	end

	local boardState = type(snapshot) == "table" and type(snapshot.boardState) == "table" and snapshot.boardState or nil
	if boardState and tostring(boardState.mode or "") == resolvedMode then
		return math.max(0, math.floor(tonumber(boardState.streak) or 0))
	end

	return math.max(0, math.floor(tonumber(fallbackValue) or 0))
end

local Dependencies = {
	Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("Levels")),
	DefinitionBuilder = require(sharedFolder:WaitForChild("board"):WaitForChild("DefinitionBuilder")),
	Generator = require(sharedFolder:WaitForChild("board"):WaitForChild("BoardGenerator")),
	DailyMode = require(sharedFolder:WaitForChild("progression"):WaitForChild("DailyMode")),
	GiftProgress = require(sharedFolder:WaitForChild("progression"):WaitForChild("GiftProgress")),
	StarRules = require(sharedFolder:WaitForChild("progression"):WaitForChild("StarRules")),
	TimerRules = require(sharedFolder:WaitForChild("progression"):WaitForChild("TimerRules")),
	PuzzleEconomy = require(sharedFolder:WaitForChild("config"):WaitForChild("PuzzleEconomy")),
	UIEffects = require(sharedFolder:WaitForChild("ui"):WaitForChild("UIEffects")),
	AutoRejoin = require(script.Parent:WaitForChild("system"):WaitForChild("AutoRejoin")),
	InterfaceBootstrap = require(script.Parent:WaitForChild("system"):WaitForChild("InterfaceBootstrap")),
	DuelUI = require(script.Parent:WaitForChild("ui"):WaitForChild("DuelUI")),
	MetaUI = require(script.Parent:WaitForChild("ui"):WaitForChild("MetaUI")),
	MusicPlayer = require(script.Parent:WaitForChild("audio"):WaitForChild("MusicPlayer")),
	GroupIntro = require(script.Parent:WaitForChild("ui"):WaitForChild("GroupIntro")),
	MetaConfig = resolveSharedConfigModule("MetaConfig", DEFAULT_CONFIGS.Meta),
	RemoteConfig = resolveSharedConfigModule("RemoteConfig", DEFAULT_CONFIGS.Remote),
}

local PUZZLE_PIECE_TEXT = utf8.char(0x1F9E9)
local settingsAudioState = {
	storedMusicVolume = 0.4,
	storedSFXVolumes = {},
	storedAmbientVolumes = {},
}
local state
local applyAudioSettings
local playSound

do
	local function getSfxFolder()
		return SoundService:FindFirstChild("SFX")
	end

	local function setSoundVolumes(root, enabled, cache)
		if not root then
			return
		end

		for _, sound in ipairs(root:GetDescendants()) do
			if sound:IsA("Sound") then
				local key = sound:GetFullName()
				if enabled then
					local cached = cache[key]
					if cached ~= nil then
						sound.Volume = cached
					elseif sound.Volume <= 0 then
						sound.Volume = 1
					end
				else
					if sound.Volume > 0 then
						cache[key] = sound.Volume
					end
					sound.Volume = 0
				end
			end
		end
	end

	local function applyMusicFolders(enabled)
		for _, root in ipairs({
			SoundService:FindFirstChild("GroupIntro"),
			SoundService:FindFirstChild("Music"),
		}) do
			setSoundVolumes(root, enabled, settingsAudioState.storedAmbientVolumes)
		end
	end

	applyAudioSettings = function(snapshot)
		local settings = snapshot and snapshot.settings or nil
		local sfxEnabled = not (settings and settings.SFX == false)
		local musicEnabled = not (settings and settings.Music == false)

		setSoundVolumes(getSfxFolder(), sfxEnabled, settingsAudioState.storedSFXVolumes)
		if state.musicPlaybackReady then
			Dependencies.MusicPlayer.Initialize()
			settingsAudioState.storedMusicVolume = math.clamp(settingsAudioState.storedMusicVolume or Dependencies.MusicPlayer.GetVolume(), 0, 1)
			Dependencies.MusicPlayer.SetVolume(settingsAudioState.storedMusicVolume)
			if not musicEnabled then
				settingsAudioState.storedMusicVolume = Dependencies.MusicPlayer.GetVolume()
			end
			Dependencies.MusicPlayer.SetEnabled(musicEnabled)
		end
		applyMusicFolders(musicEnabled)
	end

	playSound = function(name, options)
		local settingsFolder = player:FindFirstChild("Data") and player.Data:FindFirstChild("Settings")
		local sfxEnabled = settingsFolder and settingsFolder:FindFirstChild("SFX")
		if sfxEnabled and sfxEnabled.Value == false then
			return
		end

		if type(name) ~= "string" or name == "" then
			return
		end

		local sfxFolder = getSfxFolder()
		local sound = sfxFolder and sfxFolder:FindFirstChild(name)
		if not (sound and sound:IsA("Sound")) then
			return
		end

		local resolvedPitch = tonumber(type(options) == "table" and (options.pitch or options.playbackSpeed) or nil)
		local resolvedVolume = tonumber(type(options) == "table" and options.volume or nil)
		local resolvedVolumeScale = tonumber(type(options) == "table" and options.volumeScale or nil)
		local targetSound = sound
		if sound.IsPlaying or (resolvedPitch and resolvedPitch > 0) or resolvedVolume ~= nil or resolvedVolumeScale ~= nil then
			targetSound = sound:Clone()
			targetSound.Parent = sound.Parent
			targetSound.Ended:Connect(function()
				targetSound:Destroy()
			end)
		else
			sound.TimePosition = 0
		end

		if resolvedPitch and resolvedPitch > 0 then
			targetSound.PlaybackSpeed = resolvedPitch
			pcall(function()
				targetSound.Pitch = resolvedPitch
			end)
		end

		if resolvedVolumeScale ~= nil then
			targetSound.Volume = math.max(0, targetSound.Volume * resolvedVolumeScale)
		end

		if resolvedVolume ~= nil then
			targetSound.Volume = math.max(0, resolvedVolume)
		end

		targetSound:Play()
	end
end

local COLORS = {
	tile = Color3.fromRGB(255, 255, 255),
	tileText = Color3.fromRGB(18, 18, 18),
	tileTextOnLine = Color3.fromRGB(18, 18, 18),
	tileFound = Color3.fromRGB(255, 255, 255),
	tileHint = Color3.fromRGB(94, 204, 255),
	tileHoverStroke = Color3.fromRGB(184, 190, 200),
	board = Color3.fromRGB(36, 42, 52),
	text = Color3.fromRGB(245, 247, 250),
	textMuted = Color3.fromRGB(184, 190, 200),
	dragLine = Color3.fromRGB(255, 226, 58),
	foundLine = Color3.fromRGB(162, 236, 56),
	hintLine = Color3.fromRGB(94, 204, 255),
	button = Color3.fromRGB(73, 83, 101),
	buttonPrimary = Color3.fromRGB(77, 145, 255),
	buttonDisabled = Color3.fromRGB(53, 61, 75),
	chipSoft = Color3.fromRGB(64, 73, 91),
	summary = Color3.fromRGB(38, 44, 56),
	error = Color3.fromRGB(255, 150, 150),
}

local TIMER_FLASH_COLORS = {
	startRed = Color3.fromRGB(255, 108, 108),
	startYellow = Color3.fromRGB(255, 220, 110),
	startGreen = Color3.fromRGB(126, 232, 141),
	low = Color3.fromRGB(255, 92, 92),
}

local WORD_LINE_COLORS = {
	Color3.fromRGB(142, 234, 88),
	Color3.fromRGB(184, 132, 255),
	Color3.fromRGB(255, 190, 87),
	Color3.fromRGB(102, 214, 255),
	Color3.fromRGB(255, 128, 176),
	Color3.fromRGB(255, 221, 95),
	Color3.fromRGB(118, 239, 190),
	Color3.fromRGB(255, 154, 113),
}

local ALERT_TOAST_COLORS = {
	info = Color3.fromRGB(110, 188, 255),
	success = Color3.fromRGB(58, 226, 102),
	reward = Color3.fromRGB(255, 208, 96),
	error = Color3.fromRGB(255, 72, 72),
	hint = Color3.fromRGB(110, 218, 255),
}
local MODAL_PARENT_OPEN_TRANSPARENCY = 0.6

local ALERT_SFX_PROFILES = {
	info = {
		name = "NotificationLow",
		volumeScale = 0.72,
		pitch = 0.96,
	},
	success = {
		name = "NotificationMid",
		volumeScale = 0.82,
		pitch = 1.01,
	},
	reward = {
		name = "NotificationHigh",
		volumeScale = 0.86,
		pitch = 1.05,
	},
	error = {
		name = "NotificationMid",
		volumeScale = 0.8,
		pitch = 0.9,
	},
	hint = {
		name = "NotificationLow",
		volumeScale = 0.78,
		pitch = 0.99,
	},
}

local function playAlertSound(alertType, options)
	local soundName = type(options) == "table" and options.soundName or nil
	if soundName == false then
		return
	end

	local resolvedPitch = type(options) == "table" and tonumber(options.soundPitch) or nil
	local resolvedVolume = type(options) == "table" and tonumber(options.soundVolume) or nil
	local resolvedVolumeScale = type(options) == "table" and tonumber(options.soundVolumeScale) or nil
	if type(soundName) == "string" and soundName ~= "" then
		if resolvedPitch ~= nil or resolvedVolume ~= nil or resolvedVolumeScale ~= nil then
			playSound(soundName, {
				pitch = resolvedPitch,
				volume = resolvedVolume,
				volumeScale = resolvedVolumeScale,
			})
		else
			playSound(soundName)
		end
		return
	end

	local soundProfile = ALERT_SFX_PROFILES[alertType or "info"] or ALERT_SFX_PROFILES.info
	if not soundProfile then
		return
	end

	playSound(soundProfile.name, {
		pitch = resolvedPitch ~= nil and resolvedPitch or soundProfile.pitch,
		volume = resolvedVolume,
		volumeScale = resolvedVolumeScale ~= nil and resolvedVolumeScale or soundProfile.volumeScale,
	})
end

local DEFAULT_WORD_ROW_COLOR = Color3.fromRGB(43, 90, 200)
local DEFAULT_WORD_ROW_TRANSPARENCY = 0.5
local INACTIVE_WORD_ROW_COLOR = DEFAULT_WORD_ROW_COLOR:Lerp(Color3.fromRGB(22, 27, 35), 0.42)
local NORMAL_HINT_BUTTON_POSITION = UDim2.new(0.543, 0, 0.899, 0)
local DUEL_HINT_BUTTON_POSITION = UDim2.new(0.5, 0, 0.899, 0)
local WORD_LIST_TEXT_SIZE = 22
local WORD_LIST_HORIZONTAL_GAP = 18
local WORD_LIST_VERTICAL_GAP = 8
local WORD_LIST_PADDING_X = 10
local WORD_LIST_PADDING_Y = 2
local WORD_LIST_MIN_TEXT_SIZE = 18
local WORD_LIST_MAX_TEXT_SIZE = 48
local WORD_LIST_FOUND_COLOR = Color3.fromRGB(255, 255, 255)
local WORD_LIST_PENDING_COLOR = Color3.fromRGB(255, 255, 255)
local WORD_LIST_HINT_COLOR = WORD_LIST_PENDING_COLOR
local WORD_LIST_PENDING_SCALE = 1.12
local WORD_LIST_FOUND_SCALE = 1
local BOARD_STROKE_VISIBLE_TRANSPARENCY = 0.7
local BOARD_STROKE_HIDDEN_TRANSPARENCY = 1
local DUEL_MODE_OPP_FILL_COLOR = Color3.fromRGB(255, 112, 112)
local DUEL_MODE_MAX_FILL_SCALE = 0.5
local DUEL_MODE_MIN_FILL_SCALE = 0.2
local CTD_MODE_ICONS = {
	Classic = "rbxassetid://135856365815019",
	Tiny = "rbxassetid://133070938400250",
	Mega = "rbxassetid://100065885564650",
	Hardcore = "rbxassetid://128637682598154",
}

local MODES = {
	Classic = {
		label = "Classic",
		menuSubtitle = "Standard 12x20 boards.",
		menuImage = CTD_MODE_ICONS.Classic,
		accent = Color3.fromRGB(246, 193, 79),
		startIndex = 1,
		wordMultiplier = 1.2,
		completionBonus = 150,
		rewardScale = 1.15,
		startTime = nil,
		loop = true,
	},
	Tiny = {
		label = "Tiny",
		menuSubtitle = "Compact 9x9 boards. Unlocks at rank 10.",
		menuImage = CTD_MODE_ICONS.Tiny,
		accent = Color3.fromRGB(111, 229, 171),
		startIndex = 1,
		wordMultiplier = 1,
		completionBonus = 110,
		rewardScale = 0.95,
		startTime = nil,
		loop = true,
		unlockRank = 10,
	},
	Mega = {
		label = "Mega",
		menuSubtitle = "Huge 15x25 boards. Unlocks at rank 20.",
		menuImage = CTD_MODE_ICONS.Mega,
		accent = Color3.fromRGB(191, 130, 255),
		startIndex = 1,
		wordMultiplier = 1.35,
		completionBonus = 220,
		rewardScale = 1.35,
		startTime = nil,
		loop = true,
		unlockRank = 20,
	},
	Hardcore = {
		label = "Hardcore",
		menuSubtitle = "Super hard 12x20 boards. Unlocks at rank 50.",
		menuImage = CTD_MODE_ICONS.Hardcore,
		accent = Color3.fromRGB(255, 108, 108),
		startIndex = 1,
		wordMultiplier = 1.5,
		completionBonus = 260,
		rewardScale = 1.5,
		startTime = nil,
		loop = true,
		unlockRank = 50,
	},
}

task.spawn(function()
	local modeImages = {}
	local seenImages = {}

	for _, modeConfig in pairs(MODES) do
		local imageId = modeConfig.menuImage
		if type(imageId) == "string" and imageId ~= "" and not seenImages[imageId] then
			seenImages[imageId] = true
			table.insert(modeImages, imageId)
		end
	end

	if #modeImages > 0 then
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(modeImages)
		end)
	end
end)

local LAYOUT = {
	ModeOrder = {
		"Classic",
		"Tiny",
		"Mega",
		"Hardcore",
	},
	FoundLineTransparency = 0.2,
	HintLineTransparency = 0.4,
	TimedComboWindowSeconds = 8,
	TimedComboMaxMultiplier = 5,
	LineLayerZIndex = 1,
	PersistentLineLayerZIndex = 1,
	PersistentLineGlowZIndex = 1,
	PersistentLineZIndex = 2,
	DragGlowZIndex = 2,
	DragLineZIndex = 3,
	GamepadCursorGlowZIndex = 14,
	GamepadCursorZIndex = 15,
	ViewCenterPosition = UDim2.fromScale(0.5, 0.5),
	ViewMenuHiddenPosition = UDim2.fromScale(0.5, 1.5),
	ViewGameHiddenPosition = UDim2.fromScale(0.5, -1.5),
	ViewStackedOverlapPixels = 24,
	ViewTweenSlide = TweenInfo.new(0.82, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
	ViewTweenIn = TweenInfo.new(0.86, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	ViewTweenOut = TweenInfo.new(0.72, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
}
local ANIMATION = {
	DefaultDuration = 0.18,
	DefaultEasingStyle = Enum.EasingStyle.Quint,
	DefaultEasingDirection = Enum.EasingDirection.Out,
	CountdownBackdropIn = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	CountdownBackdropOut = TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	CountdownCardIn = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	CountdownCardOut = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	CountdownTextIn = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	CountdownTextOut = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	PopupIn = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	PopupOut = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	SoftFadeIn = TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	SoftFadeOut = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	DragFollowSharpness = 18,
	DragLineTransparency = 0.16,
	DragGlowTransparency = 0.86,
}
tween = function(instance, properties, durationOrInfo)
	return GuiUtils.tween(
		instance,
		properties,
		durationOrInfo,
		ANIMATION.DefaultDuration,
		ANIMATION.DefaultEasingStyle,
		ANIMATION.DefaultEasingDirection,
		TweenService
	)
end
bindButtonHoverSound = function(button)
	GuiUtils.bindButtonHoverSound(button, playSound)
end
local FOG_REVEAL_RADIUS = 1
local FAST_TILE_REFRESH_GRID_SIZE = 16
local HINT_TILE_PULSE_SPEED = 5.4
local HINT_TILE_PULSE_MIN_TRANSPARENCY = 0.22
local HINT_TILE_PULSE_MAX_TRANSPARENCY = 1
local DIRECTIONS = {
	ForwardByGroup = {
		horizontal = "E",
		vertical = "S",
		diagonalDownRight = "SE",
		diagonalDownLeft = "SW",
	},
	BackwardByGroup = {
		horizontal = "W",
		vertical = "N",
		diagonalDownRight = "NW",
		diagonalDownLeft = "NE",
	},
	GroupLookup = {
		E = "horizontal",
		W = "horizontal",
		S = "vertical",
		N = "vertical",
		SE = "diagonalDownRight",
		NW = "diagonalDownRight",
		SW = "diagonalDownLeft",
		NE = "diagonalDownLeft",
	},
}

state = {
	mode = "Classic",
	puzzleIndex = 1,
	savedClassicLevel = 1,
	seed = 1,
	boardToken = 0,
	currentPuzzle = nil,
	foundWords = {},
	foundCells = {},
	wordColors = {},
	hintCells = {},
	hintedWords = {},
	hintCursorIndex = 0,
	dragging = false,
	activeInput = nil,
	activeInputType = nil,
	dragStart = nil,
	dragStartPosition = nil,
	dragCursorPosition = nil,
	dragTarget = nil,
	hoveredCellKey = nil,
	sessionScore = 0,
	totalStars = 0,
	availableHints = Dependencies.MetaConfig.DEFAULTS.StartingHints,
	availableTimeBoosts = 0,
	availableFreezeTime = 0,
	puzzlesCleared = 0,
	streak = 0,
	currentBoardHintUses = 0,
	boardStartedAt = 0,
	lastFoundAt = 0,
	wrongDragCount = 0,
	timedDeadline = 0,
	timedStartTick = 0,
	timedOriginalDurationSeconds = 0,
	timedDurationSeconds = 0,
	timedSecondsLeft = 0,
	lastTimerWholeSecond = nil,
	timedStartCueEndsAt = 0,
	timedTimerVisualKey = "",
	timedCountdownPending = false,
	timedRunActive = false,
	timedRunEnding = false,
	timeBoostUsed = false,
	freezeTimeUsed = false,
	freezeTimeEndsAt = 0,
	timedComboMultiplier = 1,
	timedComboExpiresAt = 0,
	timedComboPausedRemaining = 0,
	timedComboAccent = nil,
	gameplayInputLocked = false,
	wordRowsRevealPending = false,
	gameEnded = false,
	transitionBusy = false,
	viewTransitionBusy = false,
	gameViewActive = false,
	pendingHintRequest = false,
	pendingTimedProductKind = nil,
	menuModeIndex = 1,
	summaryAction = nil,
	summaryOutcomeContext = nil,
	summaryGiftClaimPending = false,
	summaryGiftSequenceActive = false,
	summaryGiftAutoPromptToken = 0,
	pendingGiftClaimResultCallback = nil,
	lastAppliedSnapshotVersion = 0,
	hintAttentionActive = false,
	hintAttentionNextPulseAt = 0,
	hintAttentionTweenToken = 0,
	moreTimeDebugKey = "",
	summaryGiftDebugKey = "",
	playerData = nil,
	starProgress = {},
	resumeBoardState = nil,
	pendingResumeBoardState = nil,
	pendingIntroResumeBoardState = nil,
	dailyModeInfo = nil,
	metaUiController = nil,
	musicPlaybackReady = false,
	lastDragSnapKey = nil,
	activeCountdownId = 0,
	boardStartCountdownPending = false,
	boardIntroAnimating = false,
	boardVisualToken = 0,
	boardIntroDelaySeconds = 1.12,
	gameplayStarted = false,
	startupBootstrapReady = false,
	groupIntroCompleted = false,
	groupIntroExpected = false,
	pendingGroupIntroShownFunnel = false,
	duelActive = false,
	duelMatchId = nil,
	duelOpponentName = "",
	duelSourceMode = nil,
	duelServerStarted = false,
	duelLocalCountdownFinished = false,
	duelMyProgress = 0,
	duelOpponentProgress = 0,
	duelController = nil,
	trackedClientFunnels = {},
}

local ui = {}
local tiles = {}
local remotes = {}
local tileRenderStates = {}
local dragLineVisualState = {}

local updateHud
local refreshModeButtons
local refreshActionButtons
local updateWordsLabel
local transitionToPuzzle
local performPuzzleLoad
local loadPreparedPuzzle
local endTimedRun
local showSummary
local hideSummary
local enterSelectedMode
local exitCurrentMode
local pulseScale
local clearDrag
local resetWordListUi
local showDesktopAlert
local tileFromScreenPosition
local startMode
local syncBoardProgress
local showMenuView
local TimedProduct = {}
local showGameView
local countHintedWords
local countFoundWords
local getDailyModeInfo
local hasCompletedDailyToday
local getModeConfig
local refreshClassicLevelsFrame
local showClassicLevelsFrame
local hideClassicLevelsFrame
local handleMenuPlayPressed
local startClassicLevelFromSelector
local ButtonUi
local cellKey
local currentSelection
local chooseModeLevelIndex
local buildPuzzleDefinition
local ensureTileVisuals
local setStatus
local getWordColor
local assignWordColors
local addScore
local getTileCenter
local pathMatches
local snapTargetFromPosition
local selectionLookup
local createDragLineObjects
local refreshPersistentLines
local animateWrongSelection
local keepCurrentDragLineAsFound
local clearHint
local setHintWord
local clearHintWord
local nextHintTarget
local applyResumeStateToCurrentPuzzle

local function destroyLineEntry(entry)
	if not entry then
		return
	end

	entry.animationToken = (entry.animationToken or 0) + 1
	entry.flashToken = (entry.flashToken or 0) + 1

	if entry.line then
		entry.line:Destroy()
	end

	if entry.glow then
		entry.glow:Destroy()
	end
end

local function getWordRowTemplate()
	local template = ReplicatedStorage:FindFirstChild("WordRow_Template") or ReplicatedStorage:WaitForChild("WordRow_Template", 5)
	if template and template:IsA("GuiObject") then
		return template
	end

	return nil
end

local function getPuzzleGridWidth(puzzle)
	return math.max(1, math.floor(tonumber(puzzle and (puzzle.gridWidth or puzzle.gridSize)) or 1))
end

local function getPuzzleGridHeight(puzzle)
	return math.max(1, math.floor(tonumber(puzzle and (puzzle.gridHeight or puzzle.gridSize)) or 1))
end

local function getPuzzleGridSize(puzzle)
	return math.max(getPuzzleGridWidth(puzzle), getPuzzleGridHeight(puzzle))
end

local function syncBoardContentLayout()
	if not (ui.boardHolder and ui.boardContent) then
		return
	end

	ui.boardContent.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.boardContent.Position = UDim2.fromScale(0.5, 0.5)
	ui.boardContent.Size = UDim2.fromScale(1, 1)

	if ui.boardVisualGroup then
		ui.boardVisualGroup.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.boardVisualGroup.Position = UDim2.fromScale(0.5, 0.5)
		ui.boardVisualGroup.Size = UDim2.fromScale(1, 1)
	end

	if ui.puzzleGrid then
		ui.puzzleGrid.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.puzzleGrid.Position = UDim2.fromScale(0.5, 0.5)
		ui.puzzleGrid.Size = UDim2.fromScale(1, 1)
		local puzzleGridAspect = ui.puzzleGrid:FindFirstChild("PuzzleGridAspectRatio")
		if puzzleGridAspect and puzzleGridAspect:IsA("UIAspectRatioConstraint") then
			puzzleGridAspect.AspectRatio = getPuzzleGridWidth(state.currentPuzzle) / getPuzzleGridHeight(state.currentPuzzle)
		end
	end

	if ui.tileLayer then
		ui.tileLayer.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.tileLayer.Position = UDim2.fromScale(0.5, 0.5)
		ui.tileLayer.Size = UDim2.fromScale(1, 1)
	end
end

local function setBoardVisualTransparency(alpha)
	local clampedAlpha = math.clamp(alpha or 0, 0, 1)
	if ui.boardHolderStroke then
		ui.boardHolderStroke.Transparency = BOARD_STROKE_VISIBLE_TRANSPARENCY
			+ (BOARD_STROKE_HIDDEN_TRANSPARENCY - BOARD_STROKE_VISIBLE_TRANSPARENCY) * clampedAlpha
	end

	local boardVisualGroup = ui.boardVisualGroup
	if not (boardVisualGroup and boardVisualGroup:IsA("CanvasGroup")) then
		return
	end

	boardVisualGroup.GroupTransparency = clampedAlpha
end

local function tweenBoardVisualTransparency(alpha, tweenInfo)
	local clampedAlpha = math.clamp(alpha or 0, 0, 1)
	if ui.boardHolderStroke then
		tween(ui.boardHolderStroke, {
			Transparency = BOARD_STROKE_VISIBLE_TRANSPARENCY
				+ (BOARD_STROKE_HIDDEN_TRANSPARENCY - BOARD_STROKE_VISIBLE_TRANSPARENCY) * clampedAlpha,
		}, tweenInfo)
	end

	local boardVisualGroup = ui.boardVisualGroup
	if not (boardVisualGroup and boardVisualGroup:IsA("CanvasGroup")) then
		return nil
	end

	return tween(boardVisualGroup, {
		GroupTransparency = clampedAlpha,
	}, tweenInfo)
end

local function isInteractionBlocked()
	return state.transitionBusy or state.viewTransitionBusy
end

local function isGameplayInteractionBlocked()
	return isInteractionBlocked() or state.gameplayInputLocked or state.boardIntroAnimating or state.pendingHintRequest
end

local function getDragBlockReason()
	if state.transitionBusy then
		return "transitionBusy"
	end
	if state.viewTransitionBusy then
		return "viewTransitionBusy"
	end
	if state.gameplayInputLocked then
		return "gameplayInputLocked"
	end
	if state.boardIntroAnimating then
		return "boardIntroAnimating"
	end
	if state.pendingHintRequest then
		return "pendingHintRequest"
	end
	if state.gameEnded then
		return "gameEnded"
	end
	if not state.gameViewActive then
		return "gameViewInactive"
	end
	return nil
end

local function isGameViewDisplayed()
	local gameRoot = ui and ui.game or nil
	return state.gameViewActive or (state.viewTransitionBusy and gameRoot and gameRoot.Visible == true)
end

local function getSelectedMenuModeName()
	local count = #LAYOUT.ModeOrder
	if count <= 0 then
		return "Classic"
	end

	state.menuModeIndex = math.clamp(math.floor(state.menuModeIndex or 1), 1, count)
	return LAYOUT.ModeOrder[state.menuModeIndex]
end

local function setSelectedMenuMode(modeName)
	for index, candidate in ipairs(LAYOUT.ModeOrder) do
		if candidate == modeName then
			state.menuModeIndex = index
			break
		end
	end
end

local function getCurrentRank()
	local snapshot = type(state.playerData) == "table" and state.playerData or nil
	local progression = snapshot and snapshot.progression or nil
	local leaderstats = player:FindFirstChild("leaderstats")
	local rankValue = leaderstats and leaderstats:FindFirstChild("Rank") or nil

	return math.max(
		1,
		math.floor(tonumber(progression and progression.rank) or 0),
		math.floor(tonumber(rankValue and rankValue.Value) or 0)
	)
end

local function getModeUnlockRank(modeName)
	local modeConfig = getModeConfig(modeName)
	local unlockRank = modeConfig and tonumber(modeConfig.unlockRank) or nil
	if not unlockRank or unlockRank <= 0 then
		return nil
	end

	return math.max(1, math.floor(unlockRank))
end

local function isModeUnlocked(modeName)
	local unlockRank = getModeUnlockRank(modeName)
	if not unlockRank then
		return true
	end

	return getCurrentRank() >= unlockRank
end

local function getMenuModeSubtitle(modeName)
	local modeConfig = getModeConfig(modeName)
	if not modeConfig then
		return ""
	end

	return modeConfig.menuSubtitle or ""
end

function RuntimeHelpers.getClassicContinueLevel()
	return ClassicLevels.getClassicContinueLevel(state, Dependencies)
end

RuntimeHelpers.scrollClassicLevelsToLevel = function(levelNumber)
	local container = ui.levelsContainer
	if not (container and container:IsA("ScrollingFrame")) then
		return
	end

	local entry = ui.levelEntries and ui.levelEntries[levelNumber]
	if not (entry and entry.root and entry.root.Parent) then
		return
	end

	task.defer(function()
		if not (container.Parent and entry.root.Parent and container.Visible) then
			return
		end

		local relativeY = entry.root.AbsolutePosition.Y - container.AbsolutePosition.Y + container.CanvasPosition.Y
		local targetY = math.max(0, relativeY - math.max(0, (container.AbsoluteSize.Y - entry.root.AbsoluteSize.Y) * 0.5))
		container.CanvasPosition = Vector2.new(container.CanvasPosition.X, targetY)
	end)
end

function RuntimeHelpers.getGameplayTitle()
	local modeConfig = getModeConfig()

	if state.duelActive then
		return string.format("Vs. %s", tostring(state.duelOpponentName ~= "" and state.duelOpponentName or "Opponent"))
	end

	return string.upper(tostring((state.currentPuzzle and state.currentPuzzle.title) or modeConfig.label))
end

function RuntimeHelpers.getPuzzleSubtitleText()
	if not state.currentPuzzle then
		return ""
	end

	if state.duelActive then
		local duelMode = state.duelSourceMode or "Classic"
		local duelLabel = getModeConfig(duelMode).label
		return string.format("%s duel board", tostring(duelLabel))
	end

	return state.currentPuzzle.subtitle or ""
end

RuntimeHelpers.refreshHintButtonLayout = function()
	local hintTarget = (ui.hintRoot and ui.hintRoot:IsA("GuiObject") and ui.hintRoot) or ui.hintButton
	if not (hintTarget and hintTarget:IsA("GuiObject")) then
		return
	end
	if ui.gameTopBarContainer and hintTarget:IsDescendantOf(ui.gameTopBarContainer) then
		return
	end

	hintTarget.Position = state.duelActive and DUEL_HINT_BUTTON_POSITION or NORMAL_HINT_BUTTON_POSITION
end

RuntimeHelpers.updateHintAttentionPulse = function()
	local hintVisible = (ui.hintRoot and ui.hintRoot.Visible) or (ui.hintButton and ui.hintButton.Visible) or false
	local shouldPulse = isGameViewDisplayed()
		and state.currentPuzzle ~= nil
		and not state.duelActive
		and not state.gameEnded
		and not state.timedCountdownPending
		and state.availableHints > 0
		and getModeConfig().disableHints ~= true
		and hintVisible
	local now = os.clock()

	local function collectHintTargets()
		local targets = {}
		if ui.hintRoot and ui.hintRoot:IsA("GuiObject") then
			table.insert(targets, ui.hintRoot)
		end
		if ui.hintButton and ui.hintButton:IsA("GuiObject") and ui.hintButton ~= ui.hintRoot then
			table.insert(targets, ui.hintButton)
		end
		return targets
	end

	local function getCachedHintBaseColor(target)
		if not (target and target:IsA("GuiObject")) then
			return nil
		end

		state.hintAttentionBaseColors = type(state.hintAttentionBaseColors) == "table" and state.hintAttentionBaseColors or {}
		local cached = state.hintAttentionBaseColors[target]
		if typeof(cached) == "Color3" then
			return cached
		end

		local discovered = target.BackgroundColor3
		state.hintAttentionBaseColors[target] = discovered
		return discovered
	end

	local baseColor = nil
	for _, target in ipairs(collectHintTargets()) do
		baseColor = getCachedHintBaseColor(target)
		if typeof(baseColor) == "Color3" then
			break
		end
	end
	baseColor = typeof(baseColor) == "Color3" and baseColor or Color3.fromRGB(255, 243, 79)
	local pulseColor = Color3.fromRGB(30, 30, 30)

	local function applyHintColor(color, tweenInfo)
		for _, target in ipairs(collectHintTargets()) do
			if tweenInfo then
				tween(target, {
					BackgroundColor3 = color,
				}, tweenInfo)
			else
				target.BackgroundColor3 = color
			end
		end
	end

	if not shouldPulse then
		if state.hintAttentionActive then
			state.hintAttentionTweenToken += 1
			state.hintAttentionActive = false
			applyHintColor(baseColor)
		end
		state.hintAttentionNextPulseAt = now + 5
		return
	end

	if not state.hintAttentionActive then
		state.hintAttentionActive = true
		state.hintAttentionNextPulseAt = now + 5
		applyHintColor(baseColor)
		return
	end

	if now < (state.hintAttentionNextPulseAt or 0) then
		return
	end

	state.hintAttentionNextPulseAt = now + 5
	state.hintAttentionTweenToken += 1
	local pulseToken = state.hintAttentionTweenToken
	applyHintColor(pulseColor, TweenInfo.new(0.34, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	task.delay(0.38, function()
		if pulseToken ~= state.hintAttentionTweenToken then
			return
		end

		applyHintColor(baseColor, TweenInfo.new(0.52, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	end)
end

RuntimeHelpers.ensureDuelModeUi = function(gameFrame)
	if not (gameFrame and gameFrame:IsA("GuiObject")) then
		return nil
	end

	local duelModeRoot = gameFrame:FindFirstChild("DuelMode") or findDescendantByNames(gameFrame, { "DuelMode" }, nil)
	if not duelModeRoot then
		return nil
	end

	local progressBar = duelModeRoot:FindFirstChild("Bar")
		or duelModeRoot:FindFirstChild("ProgressBar")
		or findDescendantByNames(duelModeRoot, { "Bar", "ProgressBar" }, nil)
	local progressBarFrame = progressBar and (
		progressBar:FindFirstChild("Frame")
			or findDescendantByNames(progressBar, { "Frame" }, nil)
	) or nil
	if progressBarFrame and progressBarFrame:IsA("GuiObject") then
		progressBarFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		progressBarFrame.Position = UDim2.fromScale(0.5, 0.5)
		progressBarFrame.Size = UDim2.fromScale(1, 1)
		progressBarFrame.ZIndex = progressBar.ZIndex
	end

	local fillRoot = progressBarFrame or progressBar
	local oppFill = fillRoot and (
		fillRoot:FindFirstChild("OppFill")
			or findDescendantByNames(fillRoot, { "OppFill" }, nil)
	) or nil
	if oppFill and oppFill:IsA("GuiObject") then
		oppFill.AnchorPoint = Vector2.new(1, 0)
		oppFill.Position = UDim2.new(1, 0, 0, 0)
	end

	local myFill = fillRoot and (
		fillRoot:FindFirstChild("MyFill")
			or findDescendantByNames(fillRoot, { "MyFill" }, nil)
	) or nil
	if myFill and myFill:IsA("GuiObject") then
		myFill.AnchorPoint = Vector2.new(0, 0)
		myFill.Position = UDim2.new(0, 0, 0, 0)
	end

	if duelModeRoot:IsA("GuiObject") then
		duelModeRoot.BackgroundTransparency = 1
		duelModeRoot.Visible = false
	end

	return duelModeRoot
end

RuntimeHelpers.refreshDuelModeUi = function()
	if not (ui.duelModeRoot and ui.duelModeRoot:IsA("GuiObject")) then
		return
	end

	local duelVisible = isGameViewDisplayed() and state.duelActive and not state.gameEnded
	ui.duelModeRoot.Visible = duelVisible
	if not duelVisible then
		return
	end

	local duelModeConfig = getModeConfig(state.duelSourceMode or "Classic")
	local myProgress = math.clamp(tonumber(state.duelMyProgress) or 0, 0, 100)
	local opponentProgress = math.clamp(tonumber(state.duelOpponentProgress) or 0, 0, 100)
	local versusText = string.format("Vs. %s", tostring(state.duelOpponentName ~= "" and state.duelOpponentName or "Opponent"))

	if ui.duelModeTitleLabel then
		ui.duelModeTitleLabel.Text = versusText
	end
	if ui.duelModeOpponentLabel then
		ui.duelModeOpponentLabel.Visible = false
	end
	if ui.duelModeMyLabel then
		ui.duelModeMyLabel.Text = string.format("%d%%", math.floor(myProgress + 0.5))
	end
	if ui.duelModeOppLabel then
		ui.duelModeOppLabel.Text = string.format("%d%%", math.floor(opponentProgress + 0.5))
	end
	if ui.duelModeMyFill and ui.duelModeMyFill:IsA("GuiObject") then
		ui.duelModeMyFill.BackgroundColor3 = duelModeConfig.accent or COLORS.buttonPrimary
	end
	if ui.duelModeOppFill and ui.duelModeOppFill:IsA("GuiObject") then
		ui.duelModeOppFill.BackgroundColor3 = DUEL_MODE_OPP_FILL_COLOR
	end
	if ui.duelModeMyFill and ui.duelModeOppFill then
		ui.duelModeMyFill.ZIndex = (ui.duelModeProgressBar and ui.duelModeProgressBar.ZIndex or ui.duelModeMyFill.ZIndex) + 2
		ui.duelModeOppFill.ZIndex = ui.duelModeMyFill.ZIndex - 1
	end
	tween(ui.duelModeMyFill, {
		Size = UDim2.new(math.max(DUEL_MODE_MIN_FILL_SCALE, (myProgress / 100) * DUEL_MODE_MAX_FILL_SCALE), 0, 1, 0),
	}, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	tween(ui.duelModeOppFill, {
		Size = UDim2.new(math.max(DUEL_MODE_MIN_FILL_SCALE, (opponentProgress / 100) * DUEL_MODE_MAX_FILL_SCALE), 0, 1, 0),
	}, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

RuntimeHelpers.handleDuelMatchProgress = function(payload)
	if type(payload) ~= "table" or not state.duelActive then
		return
	end
	if payload.matchId ~= nil and payload.matchId ~= state.duelMatchId then
		return
	end

	state.duelMyProgress = math.clamp(tonumber(payload.myProgress) or state.duelMyProgress or 0, 0, 100)
	state.duelOpponentProgress = math.clamp(tonumber(payload.opponentProgress) or state.duelOpponentProgress or 0, 0, 100)
	RuntimeHelpers.refreshDuelModeUi()
end

function RuntimeHelpers.getWordListDisplayText(word)
	return word
end

local function getFogRevealAnchors()
	local anchors = {}
	local seen = {}

	local function pushAnchor(point)
		if not point then
			return
		end

		local key = cellKey(point.row, point.column)
		if seen[key] then
			return
		end

		seen[key] = true
		anchors[#anchors + 1] = point
	end

	if state.dragStart then
		pushAnchor(state.dragStart)
	end
	if state.dragTarget then
		pushAnchor(state.dragTarget)
	end

	local selection = currentSelection()
	if selection then
		for _, point in ipairs(selection) do
			pushAnchor(point)
		end
	end

	if #anchors == 0 then
		local hoveredKey = state.hoveredCellKey
		if hoveredKey then
			local rowString, columnString = string.match(hoveredKey, "^(%-?%d+):(%-?%d+)$")
			pushAnchor({
				row = tonumber(rowString),
				column = tonumber(columnString),
			})
		end
	end

	if #anchors == 0 and state.currentPuzzle then
		pushAnchor({
			row = math.ceil(getPuzzleGridHeight(state.currentPuzzle) * 0.5),
			column = math.ceil(getPuzzleGridWidth(state.currentPuzzle) * 0.5),
		})
	end

	return anchors
end

local function isFogTileVisible(row, column, selectedLookup, anchors)
	if state.mode ~= "Fog" then
		return true
	end

	local key = cellKey(row, column)
	if selectedLookup[key] or state.foundCells[key] or state.hintCells[key] then
		return true
	end

	for _, point in ipairs(anchors or getFogRevealAnchors()) do
		local rowDistance = math.abs(point.row - row)
		local columnDistance = math.abs(point.column - column)
		if math.max(rowDistance, columnDistance) <= FOG_REVEAL_RADIUS then
			return true
		end
	end

	return false
end

local function refreshUiBindings()
	if refreshActionButtons then
		refreshActionButtons()
	end

	if refreshModeButtons then
		refreshModeButtons()
	end
end

RuntimeHelpers.getTimedSecondsRemaining = function()
	if not getModeConfig().startTime then
		return 0
	end

	if state.timedRunActive and state.timedDeadline > 0 then
		return math.max(0, state.timedDeadline - tick())
	end

	return math.max(0, tonumber(state.timedSecondsLeft) or 0)
end

RuntimeHelpers.getTimedLowTimeThreshold = function()
	local duration = math.max(0, math.floor(tonumber(state.timedDurationSeconds or state.timedOriginalDurationSeconds) or 0))
	if duration <= 0 then
		return 0
	end

	return math.max(1, math.ceil(duration * 0.1))
end

RuntimeHelpers.getTimedWarningThreshold = function()
	local duration = math.max(0, math.floor(tonumber(state.timedDurationSeconds or state.timedOriginalDurationSeconds) or 0))
	if duration <= 0 then
		return 0
	end

	return math.max(1, math.ceil(duration * 0.25))
end

RuntimeHelpers.getWarningOverlay = function()
	local warningImage = ui.warningImage
	if warningImage and (warningImage:IsA("ImageLabel") or warningImage:IsA("ImageButton")) then
		return warningImage
	end

	return nil
end

RuntimeHelpers.shouldShowTimedWarningOverlay = function()
	if not (
		isGameViewDisplayed()
		and not state.duelActive
		and getModeConfig().startTime ~= nil
		and state.timedRunActive == true
		and state.timedCountdownPending ~= true
		and state.gameEnded ~= true
	) then
		return false
	end

	local remaining = math.max(0, math.ceil(RuntimeHelpers.getTimedSecondsRemaining()))
	local warningThreshold = RuntimeHelpers.getTimedWarningThreshold()
	return remaining > 0 and remaining <= warningThreshold
end

RuntimeHelpers.isTimedWarningActive = function()
	return RuntimeHelpers.shouldShowTimedWarningOverlay() == true
end

RuntimeHelpers.shouldShowMoreTimeButton = function()
	if not (
		isGameViewDisplayed()
		and state.currentPuzzle ~= nil
		and not state.duelActive
		and getModeConfig().startTime ~= nil
		and state.timedRunActive == true
		and state.timedCountdownPending ~= true
		and state.gameEnded ~= true
	) then
		return false
	end

	local duration = math.max(1, math.floor(tonumber(state.timedDurationSeconds or state.timedOriginalDurationSeconds) or 1))
	local remaining = math.max(0, math.ceil(RuntimeHelpers.getTimedSecondsRemaining()))
	local threshold = math.max(
		math.ceil(duration / 3),
		RuntimeHelpers.getTimedWarningThreshold()
	)
	return remaining > 0 and remaining <= threshold
end

RuntimeHelpers.setTimedWarningOverlayEnabled = function(enabled)
	local warningImage = RuntimeHelpers.getWarningOverlay()
	if enabled == true and warningOverlayHeartbeatRunning == true then
		if warningImage and warningImage.Parent then
			warningImage.Visible = true
		end
		return
	end

	warningOverlayHeartbeatToken += 1
	local heartbeatToken = warningOverlayHeartbeatToken
	warningOverlayHeartbeatRunning = false

	if not warningImage then
		return
	end

	local warningScale = ui.warningImageScale
	local activeAnimations = ui.warningOverlayAnimations
	if type(activeAnimations) == "table" then
		for _, animation in ipairs(activeAnimations) do
			if typeof(animation) == "Instance" then
				pcall(function()
					animation:Cancel()
				end)
			end
		end
	end
	ui.warningOverlayAnimations = {}
	warningImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
	warningImage.ImageTransparency = 1
	if warningScale then
		warningScale.Scale = 1
	end
	if enabled ~= true then
		warningImage.Visible = false
		return
	end

	warningImage.Visible = true
	warningOverlayHeartbeatRunning = true
	if enabled == true then
		local remaining = math.max(0, math.ceil(RuntimeHelpers.getTimedSecondsRemaining()))
		local warningThreshold = math.max(1, RuntimeHelpers.getTimedWarningThreshold())
		local moreTimeVisible = RuntimeHelpers.shouldShowMoreTimeButton()
		print(string.format(
			"[WordSearch MoreTime] warning_start remaining=%d warningThreshold=%d shouldShow=%s root=%s button=%s used=%s runActive=%s countdown=%s",
			remaining,
			warningThreshold,
			tostring(moreTimeVisible),
			tostring(ui.timeBoostRoot and ui.timeBoostRoot:GetFullName() or "nil"),
			tostring(ui.timeBoostButton and ui.timeBoostButton:GetFullName() or "nil"),
			tostring(state.timeBoostUsed == true),
			tostring(state.timedRunActive == true),
			tostring(state.timedCountdownPending == true)
		))
	end

	task.spawn(function()
		while heartbeatToken == warningOverlayHeartbeatToken do
			if not (
				warningImage
				and warningImage.Parent
				and RuntimeHelpers.shouldShowTimedWarningOverlay()
			) then
				break
			end

			local remaining = math.max(0, RuntimeHelpers.getTimedSecondsRemaining())
			local warningThreshold = math.max(1, RuntimeHelpers.getTimedWarningThreshold())
			local urgency = 1 - math.clamp(remaining / warningThreshold, 0, 1)
			local tint = Color3.fromRGB(
				255,
				math.floor(242 - (urgency * 54)),
				math.floor(234 - (urgency * 86))
			)
			local settleTint = Color3.fromRGB(
				255,
				math.floor(248 - (urgency * 24)),
				math.floor(244 - (urgency * 34))
			)
			local peakTransparency = math.clamp(0.52 - (urgency * 0.16), 0.24, 0.52)
			local firstReleaseTransparency = math.clamp(peakTransparency + 0.16, peakTransparency + 0.1, 0.72)
			local secondPeakTransparency = math.clamp(peakTransparency + 0.06, peakTransparency, 0.64)
			local settleTransparency = math.clamp(0.84 - (urgency * 0.12), secondPeakTransparency + 0.12, 0.9)
			local firstPeakScale = 1.04 + (urgency * 0.06)
			local firstReleaseScale = 1.015 + (urgency * 0.02)
			local secondPeakScale = 1.025 + (urgency * 0.04)
			local settleScale = 1 + (urgency * 0.012)
			local firstBeatDuration = math.max(0.2, 0.28 - (urgency * 0.04))
			local firstReleaseDuration = math.max(0.16, 0.22 - (urgency * 0.03))
			local secondBeatDuration = math.max(0.14, 0.18 - (urgency * 0.03))
			local settleDuration = math.max(0.46, 0.78 - (urgency * 0.1))
			warningImage.Visible = true
			warningImage.ImageColor3 = settleTint

			local phaseOneTween = tween(warningImage, {
				ImageTransparency = peakTransparency,
				ImageColor3 = tint,
			}, TweenInfo.new(firstBeatDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
			if phaseOneTween then
				table.insert(ui.warningOverlayAnimations, phaseOneTween)
			end
			if warningScale then
				local scaleTween = tween(warningScale, {
					Scale = firstPeakScale,
				}, TweenInfo.new(firstBeatDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
				if scaleTween then
					table.insert(ui.warningOverlayAnimations, scaleTween)
				end
			end
			task.wait(firstBeatDuration)
			if heartbeatToken ~= warningOverlayHeartbeatToken or not RuntimeHelpers.shouldShowTimedWarningOverlay() then
				break
			end

			local phaseTwoTween = tween(warningImage, {
				ImageTransparency = firstReleaseTransparency,
			}, TweenInfo.new(firstReleaseDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
			if phaseTwoTween then
				table.insert(ui.warningOverlayAnimations, phaseTwoTween)
			end
			if warningScale then
				local scaleTween = tween(warningScale, {
					Scale = firstReleaseScale,
				}, TweenInfo.new(firstReleaseDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
				if scaleTween then
					table.insert(ui.warningOverlayAnimations, scaleTween)
				end
			end
			task.wait(firstReleaseDuration)
			if heartbeatToken ~= warningOverlayHeartbeatToken or not RuntimeHelpers.shouldShowTimedWarningOverlay() then
				break
			end

			local phaseThreeTween = tween(warningImage, {
				ImageTransparency = secondPeakTransparency,
				ImageColor3 = tint,
			}, TweenInfo.new(secondBeatDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
			if phaseThreeTween then
				table.insert(ui.warningOverlayAnimations, phaseThreeTween)
			end
			if warningScale then
				local scaleTween = tween(warningScale, {
					Scale = secondPeakScale,
				}, TweenInfo.new(secondBeatDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
				if scaleTween then
					table.insert(ui.warningOverlayAnimations, scaleTween)
				end
			end
			task.wait(secondBeatDuration)
			if heartbeatToken ~= warningOverlayHeartbeatToken or not RuntimeHelpers.shouldShowTimedWarningOverlay() then
				break
			end

			local phaseFourTween = tween(warningImage, {
				ImageTransparency = settleTransparency,
				ImageColor3 = settleTint,
			}, TweenInfo.new(settleDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
			if phaseFourTween then
				table.insert(ui.warningOverlayAnimations, phaseFourTween)
			end
			if warningScale then
				local scaleTween = tween(warningScale, {
					Scale = settleScale,
				}, TweenInfo.new(settleDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
				if scaleTween then
					table.insert(ui.warningOverlayAnimations, scaleTween)
				end
			end
			task.wait(settleDuration)
		end

		if heartbeatToken == warningOverlayHeartbeatToken then
			warningOverlayHeartbeatRunning = false
			ui.warningOverlayAnimations = {}
			if warningImage and warningImage.Parent then
				warningImage.ImageTransparency = 1
				warningImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
				warningImage.Visible = false
			end
			if warningScale and warningScale.Parent then
				warningScale.Scale = 1
			end
		end
	end)
end

RuntimeHelpers.getTimedTimerVisualState = function()
	local baseTextColor = ui.timedModeTimerLabelBaseColor or COLORS.text
	local baseFrameColor = ui.timedModeFrameBaseColor or COLORS.chipSoft
	local baseStrokeColor = ui.timedModeFrameStrokeBaseColor or baseFrameColor
	local now = tick()
	local startCueEndsAt = tonumber(state.timedStartCueEndsAt) or 0

	if startCueEndsAt > now then
		local elapsed = math.clamp(3 - (startCueEndsAt - now), 0, 2.999)
		local stage = math.clamp(math.floor(elapsed) + 1, 1, 3)
		local stageColor = stage == 1 and TIMER_FLASH_COLORS.startRed
			or stage == 2 and TIMER_FLASH_COLORS.startYellow
			or TIMER_FLASH_COLORS.startGreen

		return {
			key = "start_" .. tostring(stage),
			textColor = stageColor,
			frameColor = baseFrameColor:Lerp(stageColor, 0.32),
			strokeColor = stageColor,
			pulse = true,
			pulsePeak = 1.14,
		}
	end

	local lowThreshold = RuntimeHelpers.getTimedLowTimeThreshold()
	local remaining = math.max(0, math.ceil(RuntimeHelpers.getTimedSecondsRemaining()))
	if lowThreshold > 0 and remaining > 0 and remaining <= lowThreshold then
		return {
			key = "low_" .. tostring(remaining),
			textColor = TIMER_FLASH_COLORS.low,
			frameColor = baseFrameColor:Lerp(TIMER_FLASH_COLORS.low, 0.26),
			strokeColor = TIMER_FLASH_COLORS.low,
			pulse = true,
			pulsePeak = 1.08,
		}
	end

	return {
		key = "base",
		textColor = baseTextColor,
		frameColor = baseFrameColor,
		strokeColor = baseStrokeColor,
		pulse = false,
	}
end

RuntimeHelpers.applyTimedTimerVisual = function()
	local label = ui.timedModeTimerLabel
	local frame = ui.timedModeFrame
	if not label then
		return
	end

	local timedModeVisible = isGameViewDisplayed() and not state.duelActive and getModeConfig().startTime ~= nil
	local baseTextColor = ui.timedModeTimerLabelBaseColor or COLORS.text
	local baseFrameColor = ui.timedModeFrameBaseColor or COLORS.chipSoft
	local baseStrokeColor = ui.timedModeFrameStrokeBaseColor or baseFrameColor

	if not timedModeVisible then
		state.timedTimerVisualKey = ""
		RuntimeHelpers.setTimedWarningOverlayEnabled(false)
		label.TextColor3 = baseTextColor
		if frame and frame:IsA("GuiObject") then
			frame.BackgroundColor3 = baseFrameColor
		end
		if ui.timedModeFrameStroke then
			ui.timedModeFrameStroke.Color = baseStrokeColor
		end
		if ui.timedModeTimerScale then
			ui.timedModeTimerScale.Scale = 1
		end
		return
	end

	RuntimeHelpers.setTimedWarningOverlayEnabled(RuntimeHelpers.shouldShowTimedWarningOverlay())

	local visualState = RuntimeHelpers.getTimedTimerVisualState()
	if state.timedTimerVisualKey == visualState.key then
		return
	end

	state.timedTimerVisualKey = visualState.key
	tween(label, {
		TextColor3 = visualState.textColor,
	}, 0.14)
	if frame and frame:IsA("GuiObject") then
		tween(frame, {
			BackgroundColor3 = visualState.frameColor,
		}, 0.14)
	end
	if ui.timedModeFrameStroke then
		tween(ui.timedModeFrameStroke, {
			Color = visualState.strokeColor,
		}, 0.14)
	end
	if visualState.pulse and ui.timedModeTimerScale then
		pulseScale(ui.timedModeTimerScale, visualState.pulsePeak or 1.08, 1, 0)
	end
end

RuntimeHelpers.getTimedComboRemaining = function()
	return 0
end

RuntimeHelpers.refreshTimedComboUi = function()
	local comboRoot = ui.timedComboRoot
	if not comboRoot then
		return
	end

	if comboRoot:IsA("GuiObject") then
		comboRoot.Visible = false
	end
	setBarFillAlpha(ui.timedComboBarFill, ui.timedComboBar, 0)
end

RuntimeHelpers.clearTimedCombo = function(syncProgress)
	state.timedComboMultiplier = 1
	state.timedComboExpiresAt = 0
	state.timedComboPausedRemaining = 0
	state.timedComboAccent = nil
	RuntimeHelpers.refreshTimedComboUi()
end

RuntimeHelpers.playTimedComboEffect = function(color, comboMultiplier)
end

RuntimeHelpers.advanceTimedCombo = function(color)
	return 1
end

RuntimeHelpers.pauseTimedModeForMenu = function()
	if not getModeConfig().startTime or state.gameEnded then
		return
	end

	local remaining = math.max(1, math.ceil(RuntimeHelpers.getTimedSecondsRemaining()))
	state.timedRunActive = false
	state.timedStartTick = 0
	state.timedDeadline = 0
	state.timedSecondsLeft = remaining
	state.lastTimerWholeSecond = remaining
	RuntimeHelpers.refreshTimedComboUi()
end

RuntimeHelpers.resumeTimedModeFromMenu = function()
	if not getModeConfig().startTime or state.gameEnded then
		return
	end

	if state.timedCountdownPending then
		state.timedRunActive = false
		state.timedStartTick = 0
		state.timedDeadline = 0
		state.gameplayInputLocked = true
		state.lastTimerWholeSecond = math.max(1, math.floor(state.timedSecondsLeft or state.timedDurationSeconds or 0))
		return
	end

	local remaining = math.max(1, math.floor(state.timedSecondsLeft or 0))
	if (state.freezeTimeEndsAt or 0) > tick() then
		state.timedRunActive = false
		state.timedStartTick = 0
		state.timedDeadline = 0
		state.lastTimerWholeSecond = remaining
		return
	end

	state.timedSecondsLeft = remaining
	state.lastTimerWholeSecond = remaining
	state.timedRunActive = true
	state.timedStartTick = tick()
	state.timedDeadline = state.timedStartTick + remaining
	state.timedTimerVisualKey = ""
	RuntimeHelpers.refreshTimedComboUi()
end

RuntimeHelpers.runCountdownLetterShuffle = function(countdownId)
	task.spawn(function()
		local shuffleStep = 0
		while countdownId == state.activeCountdownId do
			local shouldScramble = state.gameViewActive
				and not state.gameEnded
				and not state.duelActive
				and state.currentPuzzle ~= nil
				and ui.countdownFrame ~= nil
				and ui.countdownFrame.Visible == true
			if RuntimeHelpers and RuntimeHelpers.updateTimedLetterScatter then
				RuntimeHelpers.updateTimedLetterScatter(shouldScramble, shuffleStep)
			end
			if not shouldScramble then
				break
			end

			shuffleStep += 1
			task.wait(0.18)
		end

		if RuntimeHelpers and RuntimeHelpers.updateTimedLetterScatter then
			RuntimeHelpers.updateTimedLetterScatter(false)
		end
	end)
end

RuntimeHelpers.playCountdownSequence = function(countdownTime, finalText, onComplete, stepDuration, finalHoldDuration)
	local frame = ui.countdownFrame
	local label = ui.countdownLabel
	if not (frame and label) then
		return false
	end

	local totalSteps = math.max(1, math.floor(tonumber(countdownTime) or 3))
	local revealDuration = 0.18
	local holdDuration = 0.64
	local collapseDuration = 0.18

	state.activeCountdownId += 1
	local countdownId = state.activeCountdownId
	local targetSize = UDim2.new(0.3, 0, 0.3, 0)

	frame.Visible = true
	frame.BackgroundTransparency = 1
	label.Visible = true
	label.Size = UDim2.new(0, 0, 0, 0)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	if ui.countdownCard then
		ui.countdownCard.Visible = false
	end
	refreshUiBindings()
	tween(frame, { BackgroundTransparency = 0.4 }, ANIMATION.CountdownBackdropIn)
	RuntimeHelpers.runCountdownLetterShuffle(countdownId)

	task.spawn(function()
		local function showStep(text)
			if countdownId ~= state.activeCountdownId or not (label and label.Parent) then
				return false
			end

			label.Text = text
			label.Size = UDim2.new(0, 0, 0, 0)
			label.TextTransparency = 0
			label.TextStrokeTransparency = 1
			label.Visible = true
			tween(label, { Size = targetSize }, TweenInfo.new(revealDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
			task.wait(revealDuration)
			if countdownId ~= state.activeCountdownId or not (label and label.Parent) then
				return false
			end

			task.wait(holdDuration)
			if countdownId ~= state.activeCountdownId or not (label and label.Parent) then
				return false
			end

			tween(label, { Size = UDim2.new(0, 0, 0, 0) }, TweenInfo.new(collapseDuration, Enum.EasingStyle.Back, Enum.EasingDirection.In))
			task.wait(collapseDuration)
			return countdownId == state.activeCountdownId
		end

		for value = totalSteps, 1, -1 do
			if not showStep(tostring(value)) then
				return
			end
		end

		if countdownId ~= state.activeCountdownId or not (frame and frame.Parent) then
			return
		end

		tween(frame, { BackgroundTransparency = 1 }, ANIMATION.CountdownBackdropOut)
		if RuntimeHelpers and RuntimeHelpers.updateTimedLetterScatter then
			RuntimeHelpers.updateTimedLetterScatter(false)
		end
		if onComplete then
			onComplete()
		end
		task.delay(ANIMATION.CountdownBackdropOut.Time, function()
			if countdownId ~= state.activeCountdownId or not (frame and frame.Parent) then
				return
			end

			frame.Visible = false
			refreshUiBindings()
		end)
	end)

	return true
end

RuntimeHelpers.beginTimedCountdownIfNeeded = function(boardToken)
	if not state.boardStartCountdownPending or state.gameEnded then
		return
	end

	if state.gameEnded or boardToken ~= state.boardToken then
		return
	end

	state.boardStartCountdownPending = false
	state.gameplayInputLocked = true
	updateHud()
	refreshUiBindings()

	local function beginBoard()
		if state.gameEnded or boardToken ~= state.boardToken then
			return
		end

		if getModeConfig().startTime then
			state.timedCountdownPending = false
			state.timedRunActive = true
			state.timedRunEnding = false
			state.timedStartTick = tick()
			state.timedDeadline = state.timedStartTick + math.max(1, math.floor(state.timedSecondsLeft or state.timedDurationSeconds or 1))
			state.timedSecondsLeft = math.max(1, math.ceil(math.max(0, state.timedDeadline - state.timedStartTick)))
			state.lastTimerWholeSecond = state.timedSecondsLeft
			state.timedStartCueEndsAt = tick() + 3
			state.timedTimerVisualKey = ""
		end

		state.wordRowsRevealPending = false
		updateWordsLabel()
		state.gameplayInputLocked = false
		updateHud()
		refreshUiBindings()
		if RuntimeHelpers.refreshBoard then
			RuntimeHelpers.refreshBoard()
		end
	end

	if not RuntimeHelpers.playCountdownSequence(3, nil, beginBoard, 1, 0) then
		beginBoard()
	end
end

showMenuView = function(animate, onComplete)
	ViewTransitions.showMenuView({
		ui = ui,
		state = state,
		layout = LAYOUT,
		tween = tween,
		refreshUiBindings = refreshUiBindings,
		updateHud = updateHud,
	}, animate, onComplete)
end

showGameView = function(animate, onComplete)
	ViewTransitions.showGameView({
		ui = ui,
		state = state,
		layout = LAYOUT,
		tween = tween,
		refreshUiBindings = refreshUiBindings,
		updateHud = updateHud,
	}, animate, onComplete)
end

local function applyTextFont(textObject, fallbackFont, fontFace)
	textObject.Font = fallbackFont
end

local function waitForRemote(name, className, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 5)

	while os.clock() < deadline do
		local remoteFolder = ReplicatedStorage:FindFirstChild(Dependencies.RemoteConfig.FolderName)
		local remote = remoteFolder and remoteFolder:FindFirstChild(name)
		if remote and remote.ClassName == className then
			return remote
		end
		task.wait(0.1)
	end

	return nil
end

RuntimeHelpers = RuntimeHelpers or {}

getModeConfig = function(mode)
	return MODES[mode or state.mode] or MODES.Classic
end

function RuntimeHelpers.createFallbackSnapshot()
	local fallbackModeResults = createDefaultSnapshotModeResults()
	local fallbackModeStreaks = createDefaultSnapshotModeStreaks()
	local resolvedMode = tostring(state.mode or "Classic")
	local rankSolveStep = math.max(1, math.floor(tonumber(Dependencies.MetaConfig.DEFAULTS and Dependencies.MetaConfig.DEFAULTS.RankSolveStep) or 25))
	local fallbackRank = math.max(1, math.floor(math.max(0, math.floor(tonumber(state.totalStars) or 0)) / rankSolveStep) + 1)
	if fallbackModeResults.Total then
		fallbackModeResults.Total.wins = math.max(0, math.floor(tonumber(state.totalStars) or 0))
	end
	if fallbackModeResults[resolvedMode] then
		fallbackModeResults[resolvedMode].wins = math.max(0, math.floor(tonumber(state.totalStars) or 0))
	end
	if fallbackModeStreaks[resolvedMode] then
		local streakValue = math.max(0, math.floor(tonumber(state.streak) or 0))
		fallbackModeStreaks[resolvedMode].current = streakValue
		fallbackModeStreaks[resolvedMode].best = streakValue
	end

	return {
		meta = {
			snapshotVersion = math.max(0, math.floor(tonumber(state.lastAppliedSnapshotVersion) or 0)),
		},
		inventory = {
			hintsAvailable = state.availableHints,
			timeBoostsAvailable = 0,
			freezeTimeAvailable = 0,
			puzzlePieces = 0,
		},
		progression = {
			rank = fallbackRank,
			lastClassicLevel = 1,
			highestClassicLevel = 1,
			giftClaimMilestone = 0,
		},
		stats = {
			solves = state.totalStars,
			totalWordsFound = 0,
			boardsCleared = state.totalStars,
			endlessBoards = 0,
			hintsUsed = 0,
			losses = 0,
			totalPlaySeconds = 0,
			currentStreak = math.max(0, math.floor(tonumber(state.streak) or 0)),
			highestStreak = math.max(0, math.floor(tonumber(state.streak) or 0)),
			longestStreak = math.max(0, math.floor(tonumber(state.streak) or 0)),
			modeResults = fallbackModeResults,
			modeStreaks = fallbackModeStreaks,
		},
		boardState = nil,
		dailyMode = {
			dayStamp = Dependencies.DailyMode.GetCurrentDayStamp(),
			level = Dependencies.DailyMode.GetDailyIdentity(#Dependencies.Levels).level,
			seed = Dependencies.DailyMode.GetDailyIdentity(#Dependencies.Levels).seed,
			completedDayStamp = -1,
			completed = false,
			resetTimestamp = Dependencies.DailyMode.GetNextResetTimestamp(),
			secondsUntilReset = Dependencies.DailyMode.GetSecondsUntilReset(),
		},
		starProgress = cloneTable(state.starProgress or {}),
	}
end

function RuntimeHelpers.formatTime(seconds)
	local whole = math.max(0, math.ceil(seconds))
	local minutes = math.floor(whole / 60)
	local remainingSeconds = whole % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

function RuntimeHelpers.formatLongTime(seconds)
	local whole = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(whole / 3600)
	local minutes = math.floor((whole % 3600) / 60)
	local remainingSeconds = whole % 60
	return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

function RuntimeHelpers.getPuzzleTimeLimit(puzzleData, modeName)
	return nil
end

function RuntimeHelpers.getExtraTimeAmount()
	return 0
end

function RuntimeHelpers.getFreezeDuration()
	return 0
end

function RuntimeHelpers.calculateAwardedStars(cleared, remainingTime, lossReason)
	return 0
end

function RuntimeHelpers.calculateAwardedPuzzlePiecesPreview()
	local minimumReward = math.max(0, math.floor(tonumber(Dependencies.PuzzleEconomy.MinimumCompletionReward) or 0))
	if not state.currentPuzzle then
		return minimumReward
	end

	local elapsed = math.max(0, tick() - (state.boardStartedAt or tick()))
	return math.max(minimumReward, Dependencies.PuzzleEconomy.CalculateCompletionPieces({
		mode = state.mode,
		gridSize = getPuzzleGridSize(state.currentPuzzle),
		time = elapsed,
		hints = math.max(0, math.floor(tonumber(state.currentBoardHintUses) or 0)),
		resets = 0,
	}))
end

function RuntimeHelpers.getCorrectWordSoundPitch()
	local foundCount = math.max(0, countFoundWords())
	return math.clamp(0.96 + (foundCount * 0.045), 0.96, 1.5)
end

function RuntimeHelpers.printAwardedStars(_stars)
end

function RuntimeHelpers.ensureTimedActionButton(parent, names)
	if not parent then
		return nil, nil, nil
	end

	local resolvedNames = type(names) == "table" and names or { tostring(names) }
	local root = findDescendantByNames(parent, resolvedNames, nil)
	if not root then
		return nil, nil, nil
	end

	local button = findButtonLike(root)
	local label = nil
	if root:IsA("TextButton") or root:IsA("TextLabel") then
		label = root
	else
		label = findTextObject(root, { "Label", "TextLabel", "Amount" })
	end

	return root, button, label
end

getDailyModeInfo = function()
	local identity = Dependencies.DailyMode.GetDailyIdentity(#Dependencies.Levels)
	local snapshotInfo = type(state.dailyModeInfo) == "table" and state.dailyModeInfo or nil
	local completedDayStamp = math.floor(tonumber(snapshotInfo and snapshotInfo.completedDayStamp) or -1)

	return {
		dayStamp = identity.dayStamp,
		level = identity.level,
		seed = identity.seed,
		completedDayStamp = completedDayStamp,
		completed = completedDayStamp == identity.dayStamp,
		resetTimestamp = identity.resetTimestamp,
		secondsUntilReset = Dependencies.DailyMode.GetSecondsUntilReset(),
	}
end

hasCompletedDailyToday = function()
	return getDailyModeInfo().completed == true
end

local function getSnapshot()
	return state.playerData or RuntimeHelpers.createFallbackSnapshot()
end

RuntimeHelpers.syncClientDataMirror = function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	local dataFolder = player:FindFirstChild("Data")
	if not dataFolder then
		return
	end

	local progressFolder = dataFolder:FindFirstChild("Progress")
	local hintsFolder = dataFolder:FindFirstChild("Hints")
	local totalCompletedValue = progressFolder and progressFolder:FindFirstChild("TotalCompleted") or nil
	local giftClaimMilestoneValue = progressFolder and progressFolder:FindFirstChild("GiftClaimMilestone") or nil
	local hintsAvailableValue = hintsFolder and hintsFolder:FindFirstChild("Available") or nil
	local puzzlePiecesValue = dataFolder:FindFirstChild("PuzzlePieces")
	local snapshotStats = type(snapshot.stats) == "table" and snapshot.stats or nil
	local snapshotModeResults = type(snapshotStats and snapshotStats.modeResults) == "table" and snapshotStats.modeResults or nil
	local snapshotTotalBucket = type(snapshotModeResults and snapshotModeResults.Total) == "table" and snapshotModeResults.Total or nil
	local authoritativeTotalCompleted = math.max(
		0,
		math.floor(tonumber(snapshotStats and snapshotStats.solves) or tonumber(snapshotStats and snapshotStats.boardsCleared) or 0),
		math.floor(tonumber(snapshotTotalBucket and snapshotTotalBucket.wins) or 0)
	)
	local authoritativeGiftClaimMilestone = math.max(
		0,
		math.floor(tonumber(snapshot.progression and snapshot.progression.giftClaimMilestone) or 0)
	)

	if totalCompletedValue and (totalCompletedValue:IsA("IntValue") or totalCompletedValue:IsA("NumberValue")) then
		totalCompletedValue.Value = math.max(
			math.floor(tonumber(totalCompletedValue.Value) or 0),
			authoritativeTotalCompleted
		)
	end
	if giftClaimMilestoneValue and (giftClaimMilestoneValue:IsA("IntValue") or giftClaimMilestoneValue:IsA("NumberValue")) then
		giftClaimMilestoneValue.Value = math.max(
			math.floor(tonumber(giftClaimMilestoneValue.Value) or 0),
			authoritativeGiftClaimMilestone
		)
	end
	if hintsAvailableValue and (hintsAvailableValue:IsA("IntValue") or hintsAvailableValue:IsA("NumberValue")) then
		hintsAvailableValue.Value = math.max(0, math.floor(tonumber(snapshot.inventory and snapshot.inventory.hintsAvailable) or 0))
	end
	if puzzlePiecesValue and (puzzlePiecesValue:IsA("IntValue") or puzzlePiecesValue:IsA("NumberValue")) then
		puzzlePiecesValue.Value = math.max(0, math.floor(tonumber(snapshot.inventory and snapshot.inventory.puzzlePieces) or 0))
	end
end

local function applySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	local snapshotMeta = type(snapshot.meta) == "table" and snapshot.meta or nil
	local snapshotVersion = math.max(0, math.floor(tonumber(snapshotMeta and snapshotMeta.snapshotVersion) or 0))
	if snapshotVersion > 0 and snapshotVersion < math.max(0, math.floor(tonumber(state.lastAppliedSnapshotVersion) or 0)) then
		return
	end
	if snapshotVersion <= 0 and math.max(0, math.floor(tonumber(state.lastAppliedSnapshotVersion) or 0)) > 0 then
		return
	end
	if snapshotVersion > 0 then
		state.lastAppliedSnapshotVersion = snapshotVersion
	end

	local modeResults = type(snapshot.stats and snapshot.stats.modeResults) == "table" and snapshot.stats.modeResults or nil
	local totalBucket = type(modeResults and modeResults.Total) == "table" and modeResults.Total or nil
	local hasAuthoritativeWins = snapshot.stats ~= nil or totalBucket ~= nil
	local totalWins = hasAuthoritativeWins and math.max(
		0,
		math.floor(tonumber(snapshot.stats and snapshot.stats.solves) or tonumber(snapshot.stats and snapshot.stats.boardsCleared) or 0),
		math.floor(tonumber(totalBucket and totalBucket.wins) or 0)
	) or math.max(0, math.floor(state.totalStars or 0))

	state.playerData = snapshot
	RuntimeHelpers.syncClientDataMirror(snapshot)
	state.totalStars = totalWins
	state.availableHints = math.max(0, math.floor((snapshot.inventory and snapshot.inventory.hintsAvailable) or state.availableHints or 0))
	state.availableTimeBoosts = 0
	state.availableFreezeTime = 0
	state.savedClassicLevel = 1
	state.resumeBoardState = type(snapshot.boardState) == "table" and MODES[snapshot.boardState.mode] and snapshot.boardState or nil
	state.dailyModeInfo = type(snapshot.dailyMode) == "table" and snapshot.dailyMode or nil
	state.starProgress = type(snapshot.starProgress) == "table" and snapshot.starProgress or state.starProgress or {}
	state.streak = resolveModeStreakFromSnapshot(snapshot, state.mode, state.streak)
	state.pendingHintRequest = false
	applyAudioSettings(snapshot)

	if state.metaUiController then
		state.metaUiController:applySnapshot(snapshot)
	end

	if refreshClassicLevelsFrame then
		refreshClassicLevelsFrame()
	end

	if updateHud then
		updateHud()
	end

	if state.summaryOutcomeContext and RuntimeHelpers.renderSummaryOutcome then
		task.defer(function()
			if state.summaryOutcomeContext and RuntimeHelpers.renderSummaryOutcome then
				RuntimeHelpers.renderSummaryOutcome()
			end
		end)
	end
end

local function trackServerAction(actionName, payload)
	if remotes.trackAction then
		remotes.trackAction:FireServer(actionName, payload)
	end
end

local function trackFunnelStep(stepName, details)
	if type(stepName) ~= "string" or stepName == "" then
		return
	end

	if state.trackedClientFunnels[stepName] then
		return
	end

	state.trackedClientFunnels[stepName] = true
	trackServerAction("ClientFunnel", {
		step = stepName,
		details = details or {},
	})
end

local function recordSnapshotStarProgress(snapshot, mode, level, stars)
	if type(snapshot) ~= "table" then
		return
	end

	local resolvedMode = tostring(mode or "Classic")
	local resolvedLevel = math.clamp(math.floor(tonumber(level) or 1), 1, #Dependencies.Levels)
	local numericStars = math.clamp(math.floor(tonumber(stars) or 0), 0, 3)
	local metadata = resolvedMode == "Daily" and {
		dayStamp = Dependencies.DailyMode.GetCurrentDayStamp(),
	} or nil
	local slot = Dependencies.StarRules.ResolveSlot(resolvedMode, resolvedLevel, metadata)
	local starProgress = type(snapshot.starProgress) == "table" and cloneTable(snapshot.starProgress) or {}
	local modeBucket = type(starProgress[slot.mode]) == "table" and cloneTable(starProgress[slot.mode]) or {}
	local packBucket = type(modeBucket[slot.pack]) == "table" and cloneTable(modeBucket[slot.pack]) or {}
	local previousBest = math.clamp(math.floor(tonumber(packBucket[slot.entry]) or 0), 0, 3)

	packBucket[slot.entry] = math.max(previousBest, numericStars)
	modeBucket[slot.pack] = packBucket
	starProgress[slot.mode] = modeBucket
	snapshot.starProgress = starProgress
end

local function applyLocalAction(actionName, payload)
	local snapshot = getSnapshot()
	local stats = snapshot.stats or {}
	local progression = snapshot.progression or {}
	local inventory = snapshot.inventory or {}
	local mode = tostring(payload and payload.mode or state.mode or "")
	local modeResults = type(stats.modeResults) == "table" and stats.modeResults or createDefaultSnapshotModeResults()
	local modeStreaks = type(stats.modeStreaks) == "table" and stats.modeStreaks or createDefaultSnapshotModeStreaks()
	local totalModeBucket = type(modeResults.Total) == "table" and modeResults.Total or { wins = 0, losses = 0 }
	local specificModeBucket = mode ~= "" and (type(modeResults[mode]) == "table" and modeResults[mode] or { wins = 0, losses = 0 }) or nil
	local specificModeStreakBucket = mode ~= "" and (type(modeStreaks[mode]) == "table" and modeStreaks[mode] or { current = 0, best = 0 }) or nil

	modeResults.Total = totalModeBucket
	if mode ~= "" then
		modeResults[mode] = specificModeBucket
		modeStreaks[mode] = specificModeStreakBucket
	end

	if actionName == "WordFound" then
		stats.totalWordsFound = math.max(0, math.floor((stats.totalWordsFound or 0) + 1))
	elseif actionName == "HintUsed" then
		stats.hintsUsed = math.max(0, math.floor((stats.hintsUsed or 0) + 1))
		inventory.hintsAvailable = math.max(0, math.floor((inventory.hintsAvailable or state.availableHints or 0) - 1))
	elseif actionName == "BoardCleared" then
		local level = math.max(1, math.floor(tonumber(payload and payload.level) or state.puzzleIndex))
		local puzzlePiecesEarned = math.max(0, math.floor(tonumber(payload and payload.puzzlePiecesEarned) or 0))

		totalModeBucket.wins = math.max(0, math.floor(tonumber(totalModeBucket.wins) or 0) + 1)
		if specificModeBucket then
			specificModeBucket.wins = math.max(0, math.floor(tonumber(specificModeBucket.wins) or 0) + 1)
		end
		if specificModeStreakBucket then
			specificModeStreakBucket.current = math.max(0, math.floor(tonumber(specificModeStreakBucket.current) or 0) + 1)
			specificModeStreakBucket.best = math.max(
				math.floor(tonumber(specificModeStreakBucket.best) or 0),
				specificModeStreakBucket.current
			)
		end
		stats.boardsCleared = math.max(0, math.floor((stats.boardsCleared or 0) + 1))
		stats.solves = math.max(0, math.floor(tonumber(stats.solves) or 0) + 1)
		stats.modeResults = modeResults
		stats.modeStreaks = modeStreaks
		snapshot.boardState = nil
		inventory.puzzlePieces = math.max(0, math.floor((inventory.puzzlePieces or 0) + puzzlePiecesEarned))
		stats.endlessBoards = math.max(0, math.floor((stats.endlessBoards or 0) + 1))
		if mode == "Classic" then
			stats.classicBoards = math.max(0, math.floor((stats.classicBoards or 0) + 1))
		end
	elseif actionName == "BoardLost" then
		totalModeBucket.losses = math.max(0, math.floor(tonumber(totalModeBucket.losses) or 0) + 1)
		if specificModeBucket then
			specificModeBucket.losses = math.max(0, math.floor(tonumber(specificModeBucket.losses) or 0) + 1)
		end
		if specificModeStreakBucket then
			specificModeStreakBucket.current = 0
		end
		stats.losses = math.max(0, math.floor((stats.losses or 0) + 1))
		stats.modeResults = modeResults
		stats.modeStreaks = modeStreaks
		snapshot.boardState = nil
	end

	local currentStreak = 0
	local highestStreak = math.max(
		0,
		math.floor(tonumber(stats.highestStreak or stats.longestStreak) or 0)
	)
	for _, modeName in ipairs(MODE_STREAK_NAMES) do
		local bucket = type(modeStreaks[modeName]) == "table" and modeStreaks[modeName] or nil
		currentStreak = math.max(currentStreak, math.floor(tonumber(bucket and bucket.current) or 0))
		highestStreak = math.max(highestStreak, math.floor(tonumber(bucket and bucket.best) or 0))
	end
	stats.currentStreak = currentStreak
	stats.highestStreak = highestStreak
	stats.longestStreak = highestStreak

	snapshot.stats = stats
	snapshot.progression = progression
	snapshot.inventory = inventory

	applySnapshot(snapshot)
end

local function nextSeed(index)
	local value = (DateTime.now().UnixTimestampMillis + index * 9973 + state.totalStars * 71 + state.puzzlesCleared * 193) % 2147483647
	if value == 0 then
		return 1
	end

	return value
end

local function bootstrapServerState()
	remotes.getBootstrap = waitForRemote(Dependencies.RemoteConfig.GetBootstrap, "RemoteFunction", 2)
	remotes.trackAction = waitForRemote(Dependencies.RemoteConfig.TrackAction, "RemoteEvent", 2)
	remotes.stateUpdated = waitForRemote(Dependencies.RemoteConfig.StateUpdated, "RemoteEvent", 2)
	remotes.useHint = waitForRemote(Dependencies.RemoteConfig.UseHint, "RemoteFunction", 2)
	remotes.useTimedProduct = waitForRemote(Dependencies.RemoteConfig.UseTimedProduct, "RemoteFunction", 2)
	local sharedRemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local sharedEventsFolder = sharedRemotesFolder and sharedRemotesFolder:FindFirstChild("Events") or nil
	remotes.adminBoardReset = sharedEventsFolder and sharedEventsFolder:FindFirstChild("AdminBoardReset") or nil
	remotes.purchaseSuccess = sharedEventsFolder and sharedEventsFolder:FindFirstChild("PurchaseSuccess") or nil
	remotes.claimGift = sharedEventsFolder and sharedEventsFolder:FindFirstChild("ClaimGift") or nil

	if remotes.stateUpdated then
		remotes.stateUpdated.OnClientEvent:Connect(function(snapshot)
			applySnapshot(snapshot)
		end)
	end

	if remotes.adminBoardReset then
		remotes.adminBoardReset.OnClientEvent:Connect(function()
			state.resumeBoardState = nil
			state.pendingResumeBoardState = nil
			state.pendingHintRequest = false
			state.duelActive = false
			state.duelMatchId = nil
			state.duelOpponentName = ""
			state.duelSourceMode = nil
			state.duelServerStarted = false
			state.duelLocalCountdownFinished = false
			state.timedCountdownPending = false
			state.timedRunActive = false
			state.timedRunEnding = false
			state.boardStartCountdownPending = false
			state.gameEnded = true
			if ui.countdownFrame then
				ui.countdownFrame.Visible = false
			end
			if state.gameViewActive then
				showMenuView(true)
			else
				updateHud()
			end
			showDesktopAlert("Admin", "Board reset.", "info", {
				color = Color3.fromRGB(255, 120, 120),
				soundName = false,
				duration = 2.4,
			})
		end)
	end

	if remotes.purchaseSuccess then
		remotes.purchaseSuccess.OnClientEvent:Connect(function(kind)
			local normalizedKind = tostring(kind or "")
			if normalizedKind ~= "time_boost" and normalizedKind ~= "freeze_time" then
				return
			end

			state.pendingTimedProductKind = nil
			refreshActionButtons()
			task.defer(function()
				if TimedProduct.tryUse then
					TimedProduct.tryUse(normalizedKind, true)
				end
			end)
		end)
	end

	if remotes.claimGift then
		remotes.claimGift.OnClientEvent:Connect(function(payload)
			state.summaryGiftClaimPending = false
			print(string.format(
				"[WordSearch Gift] client_result success=%s rewardHints=%s rewardPieces=%s milestone=%s hasSnapshot=%s",
				tostring(type(payload) == "table" and payload.success == true),
				tostring(type(payload) == "table" and payload.rewardHints or "nil"),
				tostring(type(payload) == "table" and payload.rewardPieces or "nil"),
				tostring(type(payload) == "table" and payload.milestone or "nil"),
				tostring(type(payload) == "table" and payload.snapshot ~= nil)
			))
			local onComplete = state.pendingGiftClaimResultCallback
			state.pendingGiftClaimResultCallback = nil
			local function finishGiftFlow()
				state.summaryGiftSequenceActive = false
				if RuntimeHelpers.renderSummaryOutcome then
					RuntimeHelpers.renderSummaryOutcome()
				end
				if onComplete then
					onComplete()
				end
			end
			if type(payload) ~= "table" then
				finishGiftFlow()
				return
			end

			if payload.snapshot then
				applySnapshot(payload.snapshot)
			end

			local alertShown = false
			if payload.success == true then
				local rewardHints = math.max(0, math.floor(tonumber(payload.rewardHints) or 0))
				local rewardPieces = math.max(0, math.floor(tonumber(payload.rewardPieces) or 0))
				local rewardParts = {}
				if rewardHints > 0 then
					table.insert(rewardParts, string.format("+%d Hint%s", rewardHints, rewardHints == 1 and "" or "s"))
				end
				if rewardPieces > 0 then
					table.insert(rewardParts, string.format("+%d Puzzle Piece%s", rewardPieces, rewardPieces == 1 and "" or "s"))
				end
				local rewardText = #rewardParts > 0 and table.concat(rewardParts, "  ") or "Gift claimed!"
				alertShown = showDesktopAlert("Gift", rewardText, "reward", {
					duration = 2.4,
					color = Color3.fromRGB(255, 215, 90),
					onOkay = finishGiftFlow,
				})
			elseif payload.message then
				alertShown = showDesktopAlert("Gift", tostring(payload.message), "info", {
					duration = 2.2,
					color = Color3.fromRGB(255, 215, 90),
					onOkay = finishGiftFlow,
				})
			end

			if RuntimeHelpers.renderSummaryOutcome then
				RuntimeHelpers.renderSummaryOutcome()
			end
			if not alertShown then
				finishGiftFlow()
			end
		end)
	end

	if remotes.getBootstrap then
		local success, snapshot = pcall(function()
			return remotes.getBootstrap:InvokeServer()
		end)

		if success and type(snapshot) == "table" then
			applySnapshot(snapshot)
			return
		end
	end

			applySnapshot(RuntimeHelpers.createFallbackSnapshot())
end

do
	local boardRuntime = BoardRuntimeModule.create({
		player = player,
		ReplicatedStorage = ReplicatedStorage,
		TextService = TextService,
		UserInputService = UserInputService,
		Workspace = Workspace,
		MarketplaceService = MarketplaceService,
		TimedProductRuntime = TimedProductRuntime,
		RuntimeHelpers = RuntimeHelpers,
		Dependencies = Dependencies,
		ClassicLevels = ClassicLevels,
		state = state,
		ui = ui,
		tiles = tiles,
		remotes = remotes,
		tileRenderStates = tileRenderStates,
		dragLineVisualState = dragLineVisualState,
		create = create,
		destroyLineEntry = destroyLineEntry,
		findDescendantByNames = findDescendantByNames,
		findTextObject = findTextObject,
		ensureScaleController = ensureScaleController,
		setBarFillAlpha = setBarFillAlpha,
		tween = tween,
		applyTextFont = applyTextFont,
		cloneTable = cloneTable,
		resolveModeStreakFromSnapshot = resolveModeStreakFromSnapshot,
		playSound = playSound,
		playAlertSound = playAlertSound,
		ALERT_SFX_PROFILES = ALERT_SFX_PROFILES,
		COLORS = COLORS,
		WORD_LINE_COLORS = WORD_LINE_COLORS,
		ALERT_TOAST_COLORS = ALERT_TOAST_COLORS,
		DEFAULT_WORD_ROW_COLOR = DEFAULT_WORD_ROW_COLOR,
		DEFAULT_WORD_ROW_TRANSPARENCY = DEFAULT_WORD_ROW_TRANSPARENCY,
		INACTIVE_WORD_ROW_COLOR = INACTIVE_WORD_ROW_COLOR,
		WORD_LIST_TEXT_SIZE = WORD_LIST_TEXT_SIZE,
		WORD_LIST_HORIZONTAL_GAP = WORD_LIST_HORIZONTAL_GAP,
		WORD_LIST_VERTICAL_GAP = WORD_LIST_VERTICAL_GAP,
		WORD_LIST_PADDING_X = WORD_LIST_PADDING_X,
		WORD_LIST_PADDING_Y = WORD_LIST_PADDING_Y,
		WORD_LIST_MIN_TEXT_SIZE = WORD_LIST_MIN_TEXT_SIZE,
		WORD_LIST_MAX_TEXT_SIZE = WORD_LIST_MAX_TEXT_SIZE,
		WORD_LIST_FOUND_COLOR = WORD_LIST_FOUND_COLOR,
		WORD_LIST_PENDING_COLOR = WORD_LIST_PENDING_COLOR,
		WORD_LIST_HINT_COLOR = WORD_LIST_HINT_COLOR,
		WORD_LIST_PENDING_SCALE = WORD_LIST_PENDING_SCALE,
		WORD_LIST_FOUND_SCALE = WORD_LIST_FOUND_SCALE,
		BOARD_STROKE_VISIBLE_TRANSPARENCY = BOARD_STROKE_VISIBLE_TRANSPARENCY,
		BOARD_STROKE_HIDDEN_TRANSPARENCY = BOARD_STROKE_HIDDEN_TRANSPARENCY,
		MODES = MODES,
		LAYOUT = LAYOUT,
		ANIMATION = ANIMATION,
		DIRECTIONS = DIRECTIONS,
		FOG_REVEAL_RADIUS = FOG_REVEAL_RADIUS,
		FAST_TILE_REFRESH_GRID_SIZE = FAST_TILE_REFRESH_GRID_SIZE,
		HINT_TILE_PULSE_SPEED = HINT_TILE_PULSE_SPEED,
		HINT_TILE_PULSE_MIN_TRANSPARENCY = HINT_TILE_PULSE_MIN_TRANSPARENCY,
		HINT_TILE_PULSE_MAX_TRANSPARENCY = HINT_TILE_PULSE_MAX_TRANSPARENCY,
		getModeConfig = getModeConfig,
		getDailyModeInfo = getDailyModeInfo,
		hasCompletedDailyToday = hasCompletedDailyToday,
		getSnapshot = getSnapshot,
		applySnapshot = applySnapshot,
		trackServerAction = trackServerAction,
		trackFunnelStep = trackFunnelStep,
		applyLocalAction = applyLocalAction,
		nextSeed = nextSeed,
		showMenuView = showMenuView,
		showGameView = showGameView,
		setSelectedMenuMode = setSelectedMenuMode,
		getSelectedMenuModeName = getSelectedMenuModeName,
		getModeUnlockWins = getModeUnlockRank,
		getModeUnlockRank = getModeUnlockRank,
		isModeUnlocked = isModeUnlocked,
		isInteractionBlocked = isInteractionBlocked,
		isGameplayInteractionBlocked = isGameplayInteractionBlocked,
		getDragBlockReason = getDragBlockReason,
		isGameViewDisplayed = isGameViewDisplayed,
		refreshModeButtons = function(...)
			return refreshModeButtons(...)
		end,
		refreshActionButtons = function(...)
			return refreshActionButtons(...)
		end,
		refreshUiBindings = refreshUiBindings,
		waitForRemote = waitForRemote,
		syncBoardContentLayout = syncBoardContentLayout,
		setBoardVisualTransparency = setBoardVisualTransparency,
		tweenBoardVisualTransparency = tweenBoardVisualTransparency,
		getFogRevealAnchors = getFogRevealAnchors,
		isFogTileVisible = isFogTileVisible,
		showSummary = function(...) return showSummary(...) end,
		hideSummary = function(...) return hideSummary(...) end,
		enterSelectedMode = function(...) return enterSelectedMode(...) end,
		showClassicLevelsFrame = function(...) return showClassicLevelsFrame(...) end,
		hideClassicLevelsFrame = function(...) return hideClassicLevelsFrame(...) end,
		getButtonUi = function() return ButtonUi end,
	})

	chooseModeLevelIndex = boardRuntime.chooseModeLevelIndex
	buildPuzzleDefinition = boardRuntime.buildPuzzleDefinition
	ensureTileVisuals = boardRuntime.ensureTileVisuals
	cellKey = boardRuntime.cellKey
	currentSelection = boardRuntime.currentSelection
	countFoundWords = boardRuntime.countFoundWords
	countHintedWords = boardRuntime.countHintedWords
	updateWordsLabel = boardRuntime.updateWordsLabel
	updateHud = boardRuntime.updateHud
	pulseScale = boardRuntime.pulseScale
	clearDrag = boardRuntime.clearDrag
	resetWordListUi = boardRuntime.resetWordListUi
	showDesktopAlert = boardRuntime.showDesktopAlert
	syncBoardProgress = boardRuntime.syncBoardProgress
	transitionToPuzzle = boardRuntime.transitionToPuzzle
	loadPreparedPuzzle = boardRuntime.loadPreparedPuzzle
	performPuzzleLoad = boardRuntime.performPuzzleLoad
	startMode = boardRuntime.startMode
	handleMenuPlayPressed = boardRuntime.handleMenuPlayPressed
	startClassicLevelFromSelector = boardRuntime.startClassicLevelFromSelector
	endTimedRun = boardRuntime.endTimedRun
	TimedProduct = boardRuntime.timedProduct or TimedProduct
	setStatus = boardRuntime.setStatus
	getWordColor = boardRuntime.getWordColor
	assignWordColors = boardRuntime.assignWordColors
	addScore = boardRuntime.addScore
	getTileCenter = boardRuntime.getTileCenter
	pathMatches = boardRuntime.pathMatches
	snapTargetFromPosition = boardRuntime.snapTargetFromPosition
	selectionLookup = boardRuntime.selectionLookup
	createDragLineObjects = boardRuntime.createDragLineObjects
	refreshPersistentLines = boardRuntime.refreshPersistentLines
	animateWrongSelection = boardRuntime.animateWrongSelection
	keepCurrentDragLineAsFound = boardRuntime.keepCurrentDragLineAsFound
	clearHint = boardRuntime.clearHint
	setHintWord = boardRuntime.setHintWord
	clearHintWord = boardRuntime.clearHintWord
	nextHintTarget = boardRuntime.nextHintTarget
	applyResumeStateToCurrentPuzzle = boardRuntime.applyResumeStateToCurrentPuzzle
end

ButtonUi = ButtonUiModule.new({
	ui = ui,
	state = state,
	colors = COLORS,
	modeOrder = LAYOUT.ModeOrder,
	runtimeHelpers = RuntimeHelpers,
	timedProduct = TimedProduct,
	uiEffects = Dependencies.UIEffects,
	ensureScaleController = ensureScaleController,
	bindButtonHoverSound = bindButtonHoverSound,
	tween = tween,
	findButtonLike = findButtonLike,
	isInteractionBlocked = isInteractionBlocked,
	isGameplayInteractionBlocked = isGameplayInteractionBlocked,
	refreshModeButtons = function()
		refreshModeButtons()
	end,
	handleMenuPlayPressed = function()
		handleMenuPlayPressed()
	end,
	playSound = playSound,
	claimSummaryGift = function()
		if RuntimeHelpers.claimSummaryGift then
			RuntimeHelpers.claimSummaryGift()
		end
	end,
	exitCurrentMode = function()
		exitCurrentMode()
	end,
	transitionToPuzzle = function(index, seed)
		transitionToPuzzle(index, seed)
	end,
	chooseModeLevelIndex = chooseModeLevelIndex,
	nextSeed = nextSeed,
	getLevelsCount = function()
		return #Dependencies.Levels
	end,
})

refreshModeButtons = function()
	local selectedMode = getSelectedMenuModeName()
	local modeConfig = getModeConfig(selectedMode)
	local menuEnabled = not isInteractionBlocked()
	local modeUnlocked = isModeUnlocked(selectedMode)
	local duelVisible = false

	if ui.menuModeNameLabel then
		ui.menuModeNameLabel.Text = modeConfig.label
	end

	if ui.menuModeSubLabel then
		ui.menuModeSubLabel.Text = getMenuModeSubtitle(selectedMode)
	end

	if ui.menuModePreviewImage then
		ui.menuModePreviewImage.Image = modeConfig.menuImage or ""
	end
	if ui.menuModeLocked and ui.menuModeLocked:IsA("GuiObject") then
		ui.menuModeLocked.Visible = not modeUnlocked
	end
	if ui.menuPlayLocked and ui.menuPlayLocked:IsA("GuiObject") then
		ui.menuPlayLocked.Visible = not modeUnlocked
	end

	ButtonUi.setClickableOnly(ui.menuPlayButton, menuEnabled)
	if ui.menuDuelRoot and ui.menuDuelRoot:IsA("GuiObject") then
		ui.menuDuelRoot.Visible = duelVisible
	end
	if ui.menuDuelButton and ui.menuDuelButton ~= ui.menuDuelRoot and ui.menuDuelButton:IsA("GuiObject") then
		ui.menuDuelButton.Visible = duelVisible
	end
	ButtonUi.setClickableOnly(ui.menuDuelButton, menuEnabled and duelVisible)
	ButtonUi.setClickableOnly(ui.menuModeNextButton, menuEnabled)
	ButtonUi.setClickableOnly(ui.menuModePrevButton, menuEnabled)
end

refreshActionButtons = function()
	local gameViewDisplayed = isGameViewDisplayed()
	local hasPuzzle = state.currentPuzzle ~= nil and gameViewDisplayed
	local canInteract = hasPuzzle and not isGameplayInteractionBlocked() and not state.gameEnded
	local modeConfig = getModeConfig()
	local showHintControl = hasPuzzle and not modeConfig.disableHints
	local hintEnabled = canInteract and not modeConfig.disableHints and not RuntimeHelpers.isComplete()

	if ui.hintRoot and ui.hintRoot:IsA("GuiObject") then
		ui.hintRoot.Visible = showHintControl
		if not ui.hintRoot:IsA("GuiButton") then
			ui.hintRoot.Active = hintEnabled
		end
	end
	if ui.hintButton and ui.hintButton:IsA("GuiObject") then
		ui.hintButton.Visible = showHintControl
	end
	if ui.hintLabel then
		if ui.hintLabel == ui.hintButton and (ui.hintLabel:IsA("TextButton") or ui.hintLabel:IsA("TextLabel")) then
			ui.hintLabel.TextTransparency = ui.hintLabelBaseTransparency or 0
		elseif ui.hintLabel:IsA("GuiObject") then
			ui.hintLabel.Visible = true
		end
	end
	if ui.hintLocked and ui.hintLocked:IsA("GuiObject") then
		ui.hintLocked.Visible = false
	end
	RuntimeHelpers.refreshHintButtonLayout()

	if ui.hintRoot and ui.hintRoot:IsA("GuiButton") then
		ButtonUi.setInteractivityOnly(ui.hintRoot, hintEnabled)
	end
	ButtonUi.setInteractivityOnly(ui.hintButton, hintEnabled)

	local timerToolsVisible = gameViewDisplayed and not state.duelActive and modeConfig.startTime ~= nil
	local timerToolsUsable = hasPuzzle and modeConfig.startTime ~= nil and not state.duelActive
	local timedPromptPending = state.pendingTimedProductKind ~= nil
	local timeBoostEnabled = timerToolsUsable and canInteract and not state.timeBoostUsed and not timedPromptPending
	local freezeTimeEnabled = timerToolsUsable and canInteract and not state.freezeTimeUsed and not timedPromptPending
	local moreTimeVisible = timerToolsVisible and RuntimeHelpers.shouldShowMoreTimeButton()
	local remainingSeconds = math.max(0, math.ceil(RuntimeHelpers.getTimedSecondsRemaining()))
	local moreTimeThreshold = math.max(
		math.ceil(math.max(1, math.floor(tonumber(state.timedDurationSeconds or state.timedOriginalDurationSeconds) or 1)) / 3),
		RuntimeHelpers.getTimedWarningThreshold()
	)
	local warningActive = RuntimeHelpers.isTimedWarningActive()
	local moreTimeDebugKey = table.concat({
		tostring(gameViewDisplayed),
		tostring(hasPuzzle),
		tostring(timerToolsVisible),
		tostring(timerToolsUsable),
		tostring(moreTimeVisible),
		tostring(timeBoostEnabled),
		tostring(state.timeBoostUsed == true),
		tostring(timedPromptPending),
		tostring(warningActive),
	}, "|")
	if warningActive or state.moreTimeDebugKey ~= moreTimeDebugKey then
		state.moreTimeDebugKey = moreTimeDebugKey
		print(string.format(
			"[WordSearch MoreTime] refresh visible=%s enabled=%s warning=%s remaining=%d threshold=%d root=%s button=%s used=%s pending=%s runActive=%s countdown=%s gameEnded=%s",
			tostring(moreTimeVisible),
			tostring(timeBoostEnabled),
			tostring(warningActive),
			remainingSeconds,
			moreTimeThreshold,
			tostring(ui.timeBoostRoot and ui.timeBoostRoot:GetFullName() or "nil"),
			tostring(ui.timeBoostButton and ui.timeBoostButton:GetFullName() or "nil"),
			tostring(state.timeBoostUsed == true),
			tostring(timedPromptPending),
			tostring(state.timedRunActive == true),
			tostring(state.timedCountdownPending == true),
			tostring(state.gameEnded == true)
		))
	end

	if ui.timeBoostRoot and ui.timeBoostRoot:IsA("GuiObject") then
		ui.timeBoostRoot.Visible = moreTimeVisible
	end
	if ui.timeBoostButton and ui.timeBoostButton:IsA("GuiObject") then
		ui.timeBoostButton.Visible = moreTimeVisible
	end
	if ui.freezeTimeRoot and ui.freezeTimeRoot:IsA("GuiObject") then
		ui.freezeTimeRoot.Visible = timerToolsVisible
	end
	ButtonUi.setClickableOnly(ui.timeBoostButton, timeBoostEnabled)
	ButtonUi.setClickableOnly(ui.freezeTimeButton, freezeTimeEnabled)

	local nextEnabled = canInteract
	if state.duelActive then
		nextEnabled = false
	end

	ButtonUi.setEnabled(ui.nextButton, nextEnabled, COLORS.buttonPrimary)
	if ui.exitButton and ui.exitButton:IsA("GuiObject") then
		ui.exitButton.Visible = true
	end
	ButtonUi.setClickableOnly(ui.exitButton, gameViewDisplayed and not isGameplayInteractionBlocked())
end

do
	local summaryRuntime = SummaryRuntimeModule.create({
		player = player,
		ReplicatedStorage = ReplicatedStorage,
		RuntimeHelpers = RuntimeHelpers,
		Dependencies = Dependencies,
		ClassicLevels = ClassicLevels,
		state = state,
		ui = ui,
		remotes = remotes,
		create = create,
		cloneTable = cloneTable,
		findDescendantByNames = findDescendantByNames,
		findFirstPath = findFirstPath,
		findTextObject = findTextObject,
		ensureScaleController = ensureScaleController,
		findButtonLike = findButtonLike,
		tween = tween,
		ButtonUi = ButtonUi,
		ANIMATION = ANIMATION,
		COLORS = COLORS,
		ALERT_TOAST_COLORS = ALERT_TOAST_COLORS,
		MODAL_PARENT_OPEN_TRANSPARENCY = MODAL_PARENT_OPEN_TRANSPARENCY,
		PUZZLE_PIECE_TEXT = PUZZLE_PIECE_TEXT,
		playSound = playSound,
		showDesktopAlert = showDesktopAlert,
		getSnapshot = getSnapshot,
		pulseScale = pulseScale,
		startClassicLevelFromSelector = function(...)
			return startClassicLevelFromSelector(...)
		end,
		enterSelectedMode = function(...)
			return enterSelectedMode(...)
		end,
	})

	showSummary = summaryRuntime.showSummary
	hideSummary = summaryRuntime.hideSummary
	refreshClassicLevelsFrame = summaryRuntime.refreshClassicLevelsFrame
	hideClassicLevelsFrame = summaryRuntime.hideClassicLevelsFrame
	showClassicLevelsFrame = summaryRuntime.showClassicLevelsFrame
end
do
	local uiBootstrapRuntime = UiBootstrapRuntimeModule.create({
		player = player,
		UserInputService = UserInputService,
		RuntimeHelpers = RuntimeHelpers,
		Dependencies = Dependencies,
		state = state,
		ui = ui,
		create = create,
		waitForDescendantByNames = waitForDescendantByNames,
		findDescendantByNames = findDescendantByNames,
		findFirstPath = findFirstPath,
		findTextObject = findTextObject,
		ensureScaleController = ensureScaleController,
		findButtonLike = findButtonLike,
		findBarContainer = findBarContainer,
		setBarFillAlpha = setBarFillAlpha,
		bindButtonHoverSound = bindButtonHoverSound,
		applyTextFont = applyTextFont,
		getWordRowTemplate = getWordRowTemplate,
		syncBoardContentLayout = syncBoardContentLayout,
		createDragLineObjects = createDragLineObjects,
		refreshPersistentLines = refreshPersistentLines,
		ButtonUi = ButtonUi,
		COLORS = COLORS,
		DEFAULT_WORD_ROW_COLOR = DEFAULT_WORD_ROW_COLOR,
		DEFAULT_WORD_ROW_TRANSPARENCY = DEFAULT_WORD_ROW_TRANSPARENCY,
		BOARD_STROKE_HIDDEN_TRANSPARENCY = BOARD_STROKE_HIDDEN_TRANSPARENCY,
		LAYOUT = LAYOUT,
		DUEL_MODE_MIN_FILL_SCALE = DUEL_MODE_MIN_FILL_SCALE,
		MODAL_PARENT_OPEN_TRANSPARENCY = MODAL_PARENT_OPEN_TRANSPARENCY,
		updateWordsLabel = updateWordsLabel,
	})

	RuntimeHelpers.bindExistingUI = uiBootstrapRuntime.bindExistingUI
end
function RuntimeHelpers.buildUI()
	RuntimeHelpers.bindExistingUI()
	if ui.screenGui and not state.metaUiController then
		state.metaUiController = Dependencies.MetaUI.new({
			playSound = playSound,
			showDesktopAlert = showDesktopAlert,
			getSnapshot = getSnapshot,
			trackFunnelStep = trackFunnelStep,
			applySnapshot = applySnapshot,
			isGameplayInteractionBlocked = isGameplayInteractionBlocked,
			isGameViewActive = function()
				return state.gameViewActive
			end,
		})
		state.metaUiController:bind(ui.screenGui)
	end
	if ui.screenGui and not state.duelController and MODES.Duel then
		state.duelController = Dependencies.DuelUI.new({
			showDesktopAlert = showDesktopAlert,
			trackFunnelStep = trackFunnelStep,
			getSelectedMode = function()
				return getSelectedMenuModeName()
			end,
			getSolvesText = function(userId)
				local duelPlayer = Players:GetPlayerByUserId(userId)
				local leaderstats = duelPlayer and duelPlayer:FindFirstChild("leaderstats")
				local solves = leaderstats and leaderstats:FindFirstChild("Solves")
				return solves and string.format("Solves: %d", solves.Value) or "Solves: --"
			end,
			onCountdown = RuntimeHelpers.handleDuelMatchCountdown,
			onProgress = RuntimeHelpers.handleDuelMatchProgress,
			onStart = RuntimeHelpers.handleDuelMatchStart,
			onResult = RuntimeHelpers.handleDuelMatchResult,
			onReturnHome = RuntimeHelpers.finishDuelAndReturnHome,
		})
		state.duelController:bind(ui.screenGui, state.metaUiController)
	end
	if ui.menu then
		ui.menuOpenAnchorPoint = ui.menuOpenAnchorPoint or ui.menu.AnchorPoint
		ui.menuOpenPosition = LAYOUT.ViewCenterPosition
		ui.menuOpenSize = ui.menuOpenSize or ui.menu.Size
		ui.menu.AnchorPoint = ui.menuOpenAnchorPoint
		ui.menu.Visible = true
		ui.menu.Position = LAYOUT.ViewMenuHiddenPosition
		ui.menu.Size = ui.menuOpenSize
	end
	if ui.game then
		ui.gameOpenAnchorPoint = ui.gameOpenAnchorPoint or ui.game.AnchorPoint
		ui.gameOpenPosition = LAYOUT.ViewCenterPosition
		ui.gameOpenSize = ui.gameOpenSize or ui.game.Size
		ui.game.AnchorPoint = ui.gameOpenAnchorPoint
		ui.game.Visible = false
		ui.game.Position = LAYOUT.ViewGameHiddenPosition
		ui.game.Size = ui.gameOpenSize
	end
	state.gameViewActive = false
	refreshUiBindings()
	ButtonUi.wireActions()
	RuntimeHelpers.bindClassicLevelsFrameActions()
	RuntimeHelpers.resetBoardRuntimeForFreshMode(state.mode)
	refreshClassicLevelsFrame()
	if state.metaUiController then
		state.metaUiController:applySnapshot(getSnapshot())
	end
end

function RuntimeHelpers.restoreResumeBoardState(resumeBoardState)
	if type(resumeBoardState) ~= "table" or not MODES[resumeBoardState.mode] then
		return false
	end

	state.mode = resumeBoardState.mode
	state.sessionScore = math.max(0, math.floor(tonumber(resumeBoardState.sessionScore) or 0))
	state.puzzlesCleared = math.max(0, math.floor(tonumber(resumeBoardState.puzzlesCleared) or 0))
	state.streak = math.max(0, math.floor(tonumber(resumeBoardState.streak) or 0))
	state.timedComboMultiplier = 1
	state.timedComboPausedRemaining = 0
	state.timedComboAccent = nil
	state.gameEnded = false
	hideSummary()
	clearHint()

	local modeConfig = getModeConfig(state.mode)
	if modeConfig.startTime then
		local remainingTime = math.max(1, math.floor(tonumber(resumeBoardState.remainingTime) or modeConfig.startTime))
		local originalDuration = RuntimeHelpers.getPuzzleTimeLimit(buildPuzzleDefinition(
			math.clamp(math.floor(tonumber(resumeBoardState.level) or state.savedClassicLevel or 1), 1, #Dependencies.Levels),
			resumeBoardState.mode,
			math.max(1, math.floor(tonumber(resumeBoardState.seed) or nextSeed(state.savedClassicLevel)))
		), resumeBoardState.mode)
		state.timedOriginalDurationSeconds = originalDuration
		state.timeBoostUsed = resumeBoardState.timeBoostUsed == true
		state.freezeTimeUsed = resumeBoardState.freezeTimeUsed == true
		state.timedDurationSeconds = originalDuration + (state.timeBoostUsed and RuntimeHelpers.getExtraTimeAmount() or 0)
		state.timedStartTick = tick()
		state.timedDeadline = state.timedStartTick + remainingTime
		state.timedSecondsLeft = remainingTime
		state.lastTimerWholeSecond = remainingTime
		state.timedStartCueEndsAt = 0
		state.timedTimerVisualKey = ""
		state.timedCountdownPending = false
		state.timedRunActive = true
		state.timedRunEnding = false
		state.gameplayInputLocked = false
		state.freezeTimeEndsAt = tick() + math.max(0, tonumber(resumeBoardState.freezeTimeRemaining) or 0)
		state.timedComboMultiplier = 1
		state.timedComboExpiresAt = 0
		if state.freezeTimeEndsAt > tick() then
			state.timedRunActive = false
			state.timedStartTick = 0
			state.timedDeadline = 0
		end
	else
		state.timedDeadline = 0
		state.timedStartTick = 0
		state.timedOriginalDurationSeconds = 0
		state.timedDurationSeconds = 0
		state.timedSecondsLeft = 0
		state.lastTimerWholeSecond = nil
		state.timedStartCueEndsAt = 0
		state.timedTimerVisualKey = ""
		state.timedCountdownPending = false
		state.timedRunActive = false
		state.timedRunEnding = false
		state.timeBoostUsed = false
		state.freezeTimeUsed = false
		state.freezeTimeEndsAt = 0
		state.gameplayInputLocked = false
		state.timedComboMultiplier = 1
		state.timedComboExpiresAt = 0
	end

	state.pendingResumeBoardState = resumeBoardState
	updateHud()
	transitionToPuzzle(
		math.clamp(math.floor(tonumber(resumeBoardState.level) or state.savedClassicLevel or 1), 1, #Dependencies.Levels),
		math.max(1, math.floor(tonumber(resumeBoardState.seed) or nextSeed(state.savedClassicLevel))),
		true
	)

	return true
end

enterSelectedMode = function()
	if isInteractionBlocked() then
		return
	end

	local selectedMode = getSelectedMenuModeName()
	local forceFreshStart = false
	trackFunnelStep("PlayPressed_" .. tostring(selectedMode), {
		mode = selectedMode,
	})
	local unlockRank = getModeUnlockRank(selectedMode)
	if unlockRank and not isModeUnlocked(selectedMode) then
		showDesktopAlert(nil, string.format("Unlocks at rank %d.", unlockRank), "error", {
			duration = 2.2,
		})
		return
	end
	local activeBoardState = RuntimeHelpers.buildBoardProgressPayload()
	local canResumeCurrentBoard = not forceFreshStart
		and state.currentPuzzle ~= nil
		and not state.gameEnded
		and state.mode == selectedMode
		and not state.gameViewActive
	local resumeBoardState = not forceFreshStart and type(state.resumeBoardState) == "table" and state.resumeBoardState or nil
	local willResumeBoard = canResumeCurrentBoard
		or (resumeBoardState and resumeBoardState.mode == selectedMode)
		or ((not forceFreshStart) and activeBoardState and activeBoardState.mode == selectedMode)

	if forceFreshStart then
		local hadSavedMatchingBoard = (type(state.resumeBoardState) == "table" and state.resumeBoardState.mode == selectedMode)
			or (activeBoardState and activeBoardState.mode == selectedMode)
		if hadSavedMatchingBoard then
			state.resumeBoardState = nil
			state.pendingResumeBoardState = nil
			trackServerAction("BoardStateCleared", {})
		end
	end

	if not willResumeBoard then
		RuntimeHelpers.resetBoardRuntimeForFreshMode(selectedMode)
	end

	showGameView(true, function()
		if canResumeCurrentBoard then
			RuntimeHelpers.resumeTimedModeFromMenu()
			updateHud()
			RuntimeHelpers.refreshBoard()
			refreshPersistentLines()
			RuntimeHelpers.beginTimedCountdownIfNeeded(state.boardToken)
			return
		end

		if resumeBoardState and resumeBoardState.mode == selectedMode then
			state.resumeBoardState = nil
			RuntimeHelpers.restoreResumeBoardState(resumeBoardState)
			playAlertSound("info")
			return
		end

		if activeBoardState and activeBoardState.mode == selectedMode then
			RuntimeHelpers.restoreResumeBoardState(activeBoardState)
			playAlertSound("info")
			return
		end

		startMode(selectedMode, true)
	end)
end

exitCurrentMode = function()
	if isGameplayInteractionBlocked() or not state.gameViewActive then
		return
	end

	if state.duelActive and state.duelController then
		state.gameplayInputLocked = true
		state.duelController:abandon()
		return
	end

	hideSummary()
	clearDrag()
	local resumeBoardState = RuntimeHelpers.buildBoardProgressPayload()
	if resumeBoardState then
		trackServerAction("BoardStateUpdated", {
			boardState = resumeBoardState,
		})
	else
		trackServerAction("BoardStateCleared", {})
	end
	RuntimeHelpers.pauseTimedModeForMenu()
	state.resumeBoardState = resumeBoardState
	setSelectedMenuMode(state.mode)
	showMenuView(true)
end

function RuntimeHelpers.startGameplay()
	if state.gameplayStarted then
		return
	end
	if not state.startupBootstrapReady then
		return
	end
	if state.groupIntroExpected and not state.groupIntroCompleted then
		return
	end

	state.gameplayStarted = true
	state.musicPlaybackReady = true
	applyAudioSettings(getSnapshot())

	if type(state.resumeBoardState) == "table" and MODES[state.resumeBoardState.mode] then
		setSelectedMenuMode(state.resumeBoardState.mode)
	else
		setSelectedMenuMode(state.mode)
	end

	if ui.screenGui and ui.screenGui:IsA("ScreenGui") then
		ui.screenGui.Enabled = true
	end

	trackFunnelStep("GroupIntroCompleted", {})
	showMenuView(false)
	trackFunnelStep("MenuShown", {
		source = "normal_start",
	})
end

RuntimeHelpers.beginStartupBootstrap = function()
	task.defer(function()
		RunService.Heartbeat:Wait()
		bootstrapServerState()
		RuntimeHelpers.buildUI()
		Dependencies.AutoRejoin.Init()
		CameraRuntime.applyJoinCamera(CAMERA)

		if ui.screenGui and ui.screenGui:IsA("ScreenGui") then
			ui.screenGui.Enabled = false
		end

		state.startupBootstrapReady = true
		if state.groupIntroExpected and state.introGui then
			local preloadTargets = {
				state.startupHud,
				state.introGui,
				ReplicatedStorage:FindFirstChild("shared"),
				SoundService:FindFirstChild("SFX"),
				SoundService:FindFirstChild("GroupIntro"),
			}
			for _, assetId in pairs(CTD_MODE_ICONS) do
				table.insert(preloadTargets, assetId)
			end

			if state.pendingGroupIntroShownFunnel then
				state.pendingGroupIntroShownFunnel = false
				trackFunnelStep("GroupIntroShown", {})
			end

			Dependencies.GroupIntro:Play(state.introGui, preloadTargets, function()
				state.groupIntroCompleted = true
				RuntimeHelpers.startGameplay()
			end)
			return
		end

		state.groupIntroCompleted = true
		RuntimeHelpers.startGameplay()
	end)
end

state.runtimePlayerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
state.startupHud = Dependencies.InterfaceBootstrap.ensurePlatformHUD(state.runtimePlayerGui)
	or state.runtimePlayerGui:WaitForChild("HUD", 15)
if state.startupHud and state.startupHud:IsA("ScreenGui") then
	state.startupHud.Enabled = false
	state.startupHud.ResetOnSpawn = false
end

state.introGui = state.runtimePlayerGui:FindFirstChild("GroupIntro")
	or state.runtimePlayerGui:WaitForChild("GroupIntro", 10)
state.groupIntroExpected = state.introGui ~= nil
if state.introGui then
	if state.introGui:IsA("ScreenGui") then
		state.introGui.Enabled = true
		state.introGui.ResetOnSpawn = false
	end

	state.pendingGroupIntroShownFunnel = true
else
	state.groupIntroCompleted = true
end

task.spawn(function()
	for _ = 1, 10 do
		setCoreGuiDisabled()
		task.wait(0.5)
	end
end)

RuntimeHelpers.beginStartupBootstrap()

player.CharacterAdded:Connect(function()
	task.defer(function()
		CameraRuntime.applyJoinCamera(CAMERA)
	end)
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(function()
		CameraRuntime.applyJoinCamera(CAMERA)
	end)
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == CAMERA.PartName and child:IsA("BasePart") then
		task.defer(function()
			CameraRuntime.applyJoinCamera(CAMERA)
		end)
	end
end)

InputBindings.bind({
	player = player,
	state = state,
	timedProduct = TimedProduct,
	runtimeHelpers = RuntimeHelpers,
	marketplaceService = MarketplaceService,
	userInputService = UserInputService,
	refreshActionButtons = refreshActionButtons,
	clearDrag = clearDrag,
	playSound = playSound,
})

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	if string.find(tostring(inputType), "Gamepad") then
		if RuntimeHelpers.ensureGamepadBoardSelection then
			RuntimeHelpers.ensureGamepadBoardSelection()
		end
	end
	if state.currentPuzzle then
		RuntimeHelpers.refreshBoard()
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	RuntimeHelpers.updateSmoothDragLine(deltaTime)
	RuntimeHelpers.updateHintAttentionPulse()
	RuntimeHelpers.updateHintTilePulse()

	if not state.gameViewActive or not getModeConfig().startTime or state.gameEnded or state.timedCountdownPending then
		RuntimeHelpers.refreshTimedComboUi()
		return
	end

	if (state.freezeTimeEndsAt or 0) > tick() then
		state.timedRunActive = false
		state.timedSecondsLeft = math.max(1, math.ceil(state.timedSecondsLeft or RuntimeHelpers.getTimedSecondsRemaining()))
		updateHud()
		return
	elseif (state.freezeTimeEndsAt or 0) > 0 then
		state.freezeTimeEndsAt = 0
		if not state.timedRunActive and not state.gameEnded then
			state.timedRunActive = true
			state.timedStartTick = tick()
			state.timedDeadline = state.timedStartTick + math.max(1, math.floor(state.timedSecondsLeft or 1))
		end
	end

	if not state.timedRunActive then
		RuntimeHelpers.refreshTimedComboUi()
		return
	end

	local remaining = math.max(0, state.timedDeadline - tick())
	local wholeSeconds = math.ceil(remaining)

	if wholeSeconds ~= state.lastTimerWholeSecond then
		state.lastTimerWholeSecond = wholeSeconds
		state.timedSecondsLeft = wholeSeconds
		updateHud()
		if wholeSeconds > 0 then
			playSound("Clock")
		end

		if wholeSeconds > 0 and wholeSeconds <= 10 and ui.secondaryChipScale then
			pulseScale(ui.secondaryChipScale, 1.05, 1, 0)
		end
	end
	if remaining <= 0 then
		endTimedRun()
	end
end)
