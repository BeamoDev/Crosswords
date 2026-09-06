local GameController = {}
local started = false

function GameController.Start()
	if started then
		return
	end
	started = true

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
local clientFolder = script.Parent.Parent
local RuntimeHelpers = {}
local InterfaceController = require(script.Parent:WaitForChild("InterfaceController"))
local Components = InterfaceController.Components
local Social = require(clientFolder:WaitForChild("features"):WaitForChild("Social"))
local CameraRuntime = require(clientFolder:WaitForChild("systems"):WaitForChild("Camera"))
local BoardRuntimeModule = require(script.Parent:WaitForChild("BoardController"))
local ProgressionControllerModule = require(script.Parent:WaitForChild("ProgressionController"))
local Rewards = require(clientFolder:WaitForChild("features"):WaitForChild("Rewards"))
local SummaryRuntimeModule = Rewards.Summary
local UiBootstrapRuntimeModule = InterfaceController
local ClassicLevels = Components.ClassicLevels
local GuiUtils = Components.Gui
local ViewTransitions = Components.Transitions
local ButtonUiModule = Components.Buttons
local InputBindings = require(clientFolder:WaitForChild("systems"):WaitForChild("Input"))

local create = GuiUtils.create
local findDescendantByNames = GuiUtils.findDescendantByNames
local waitForDescendantByNames = GuiUtils.waitForDescendantByNames
local findTextObject = GuiUtils.findTextObject
local ensureScaleController = GuiUtils.ensureScaleController
local findButtonLike = GuiUtils.findButtonLike
local findFirstPath = GuiUtils.findFirstPath
local tween
local bindButtonHoverSound
local DEFAULT_CONFIGS = {
	Meta = {
		DEFAULTS = {
			StartingHints = 0,
			Settings = {
				SFX = true,
				Music = true,
			},
		},
	},
	Remote = {
		FolderName = "WordSearchBackendRemotes",
		GetBootstrap = "GetBootstrap",
		TrackAction = "TrackAction",
		StateUpdated = "StateUpdated",
		UseHint = "UseHint",
	},
}
local MODE_RESULT_NAMES = {
	"Total",
	"Classic",
	"Themed",
	"Daily",
	"Freeplay",
	"Backwards",
	"Fog",
	"OneLife",
	"Mega",
	"Duel",
}
local MODE_STREAK_NAMES = {
	"Classic",
	"Themed",
	"Daily",
	"Freeplay",
	"Backwards",
	"Fog",
	"OneLife",
	"Mega",
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

local GameConfig = resolveSharedConfigModule("GameConfig", {
	Meta = DEFAULT_CONFIGS.Meta,
})
local ProgressionConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local PuzzleGenerator = require(sharedFolder:WaitForChild("puzzle"):WaitForChild("PuzzleGenerator"))
local Dependencies = {
	Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("PuzzleCatalog")),
	DefinitionBuilder = PuzzleGenerator,
	Generator = PuzzleGenerator,
	PuzzleEngine = require(sharedFolder:WaitForChild("puzzle"):WaitForChild("PuzzleEngine")),
	DailyMode = ProgressionConfig.Daily,
	GiftProgress = ProgressionConfig.Gift,
	StarRules = ProgressionConfig.Stars,
	TimedRewards = ProgressionConfig.TimedRewards,
	PuzzleEconomy = GameConfig.Economy,
	UIEffects = Components.Effects,
	AutoRejoin = Social.AutoRejoin,
	DeviceOrientation = require(clientFolder:WaitForChild("systems"):WaitForChild("Device")),
	InterfaceBootstrap = UiBootstrapRuntimeModule.Interface,
	DuelUI = require(clientFolder:WaitForChild("features"):WaitForChild("Duels")),
	MetaUI = ProgressionControllerModule,
	AdminMenuUI = require(clientFolder:WaitForChild("features"):WaitForChild("Admin")),
	MusicPlayer = require(clientFolder:WaitForChild("systems"):WaitForChild("Audio")),
	GroupIntro = Social.GroupIntro,
	MetaConfig = GameConfig.Meta,
	RemoteConfig = require(sharedFolder:WaitForChild("network"):WaitForChild("NetworkContract")),
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
	Themed = "rbxassetid://133070938400250",
	Freeplay = "rbxassetid://133070938400250",
	OneLife = "rbxassetid://128637682598154",
	Daily = "rbxassetid://86623066110195",
	Backwards = "rbxassetid://136131132106684",
	Fog = "rbxassetid://98108829644193",
	Mega = "rbxassetid://100065885564650",
}

local MODES = {
	Classic = {
		label = "Classic",
		menuSubtitle = "Play through the level path.",
		menuImage = CTD_MODE_ICONS.Classic,
		accent = Color3.fromRGB(246, 193, 79),
		startIndex = 1,
		wordMultiplier = 1,
		completionBonus = 120,
		rewardScale = 1,
		loop = false,
	},
	Themed = {
		label = "Themed",
		menuSubtitle = "Random theme boards with matching word sets.",
		menuImage = CTD_MODE_ICONS.Themed,
		accent = Color3.fromRGB(120, 214, 255),
		startIndex = 2,
		wordMultiplier = 1.1,
		completionBonus = 138,
		rewardScale = 1.1,
		loop = true,
	},
	Freeplay = {
		label = "Freeplay",
		menuSubtitle = "Endless boards at steady difficulty.",
		menuImage = CTD_MODE_ICONS.Freeplay,
		accent = Color3.fromRGB(111, 229, 171),
		unlockWins = 3,
		startIndex = 3,
		wordMultiplier = 1.2,
		completionBonus = 150,
		rewardScale = 1.15,
		loop = true,
	},
	Backwards = {
		label = "Backwards",
		menuSubtitle = "All hidden words are reversed.",
		menuImage = CTD_MODE_ICONS.Backwards,
		accent = Color3.fromRGB(124, 169, 255),
		unlockWins = 8,
		startIndex = 4,
		wordMultiplier = 1.25,
		completionBonus = 165,
		rewardScale = 1.2,
		loop = true,
	},
	Fog = {
		label = "Fog",
		menuSubtitle = "Only nearby letters stay visible.",
		menuImage = CTD_MODE_ICONS.Fog,
		accent = Color3.fromRGB(129, 201, 255),
		unlockWins = 12,
		startIndex = 6,
		wordMultiplier = 1.38,
		completionBonus = 194,
		rewardScale = 1.3,
		loop = true,
	},
	OneLife = {
		label = "One Life",
		menuSubtitle = "One bad word ends the run.",
		menuImage = CTD_MODE_ICONS.OneLife,
		accent = Color3.fromRGB(255, 116, 116),
		unlockWins = 16,
		startIndex = 6,
		wordMultiplier = 1.48,
		completionBonus = 212,
		rewardScale = 1.38,
		loop = true,
	},
	Mega = {
		label = "MEGA",
		menuSubtitle = "16x16 event board with huge score swings.",
		menuImage = CTD_MODE_ICONS.Mega,
		accent = Color3.fromRGB(93, 205, 255),
		unlockWins = 20,
		startIndex = 8,
		wordMultiplier = 1.95,
		completionBonus = 340,
		rewardScale = 1.92,
		loop = true,
	},
	Daily = {
		label = "Daily",
		menuSubtitle = "One 16x16 board each day.",
		menuImage = CTD_MODE_ICONS.Daily,
		accent = Color3.fromRGB(255, 207, 92),
		unlockWins = 5,
		startIndex = 1,
		wordMultiplier = 2.1,
		completionBonus = 360,
		rewardScale = 2,
		loop = false,
	},
	Duel = {
		label = "1V1",
		menuSubtitle = "Race another player on the same board.",
		accent = Color3.fromRGB(69, 246, 255),
		startIndex = 1,
		wordMultiplier = 1,
		completionBonus = 0,
		rewardScale = 1,
		disableHints = false,
		loop = false,
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
		"Themed",
		"Daily",
		"Freeplay",
		"Backwards",
		"Fog",
		"OneLife",
		"Mega",
	},
	FoundLineTransparency = 0.2,
	HintLineTransparency = 0.4,
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
local FAST_TILE_REFRESH_GRID_SIZE = 10
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
	puzzlesCleared = 0,
	streak = 0,
	currentBoardHintUses = 0,
	boardStartedAt = 0,
	lastFoundAt = 0,
	wrongDragCount = 0,
	gameplayInputLocked = false,
	wordRowsRevealPending = false,
	gameEnded = false,
	transitionBusy = false,
	viewTransitionBusy = false,
	gameViewActive = false,
	pendingHintRequest = false,
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
	playerData = nil,
	starProgress = {},
	resumeBoardState = nil,
	pendingResumeBoardState = nil,
	pendingIntroResumeBoardState = nil,
	dailyModeInfo = nil,
	metaUiController = nil,
	adminMenuController = nil,
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
local showGameView
local countHintedWords
local countFoundWords
local getDailyModeInfo
local hasCompletedDailyToday
local getModeConfig
local getSnapshot
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

local function getTotalWinsCount()
	local snapshot = type(state.playerData) == "table" and state.playerData or nil
	local stats = snapshot and snapshot.stats or nil
	local modeResults = type(stats and stats.modeResults) == "table" and stats.modeResults or nil
	local totalBucket = type(modeResults and modeResults.Total) == "table" and modeResults.Total or nil

	return math.max(
		0,
		math.floor(tonumber(state.totalStars) or 0),
		math.floor(tonumber(stats and stats.boardsCleared) or 0),
		math.floor(tonumber(totalBucket and totalBucket.wins) or 0)
	)
end

local function getModeUnlockWins(modeName)
	local modeConfig = getModeConfig(modeName)
	local unlockWins = modeConfig and tonumber(modeConfig.unlockWins) or nil
	if not unlockWins or unlockWins <= 0 then
		return nil
	end

	return math.max(1, math.floor(unlockWins))
end

local function isModeUnlocked(modeName)
	local unlockWins = getModeUnlockWins(modeName)
	if not unlockWins then
		return true
	end

	return getTotalWinsCount() >= unlockWins
end

local function getMenuModeSubtitle(modeName)
	local modeConfig = getModeConfig(modeName)
	if not modeConfig then
		return ""
	end

	if modeName == "Classic" then
		return string.format("Continue at level %d.", RuntimeHelpers.getClassicContinueLevel())
	end

	local unlockWins = getModeUnlockWins(modeName)
	if unlockWins and not isModeUnlocked(modeName) then
		return string.format("Unlocks at %d wins.", unlockWins)
	end

	if modeName == "Daily" and hasCompletedDailyToday() then
		return string.format("Completed. New board in %s.", RuntimeHelpers.formatLongTime(getDailyModeInfo().secondsUntilReset))
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
	local levelNumber = state.currentPuzzle and (state.currentPuzzle.level or state.puzzleIndex) or state.puzzleIndex

	if state.duelActive then
		return string.format("Vs. %s", tostring(state.duelOpponentName ~= "" and state.duelOpponentName or "Opponent"))
	end

	if state.mode == "Classic" then
		return string.format("Level %d", levelNumber)
	end

	if state.mode == "Themed" then
		return string.upper(tostring((state.currentPuzzle and state.currentPuzzle.title) or modeConfig.label))
	end

	if state.mode == "Daily" then
		return "Daily Hunt"
	end

	return modeConfig.label
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

	if state.mode == "Fog" then
		return "Hover or drag to reveal nearby letters."
	elseif state.mode == "OneLife" then
		return "One wrong word ends the run."
	elseif state.mode == "Mega" then
		return state.currentPuzzle.subtitle or "16x16 board  /  heavy score chase."
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
		local center = math.ceil(state.currentPuzzle.gridSize * 0.5)
		pushAnchor({
			row = center,
			column = center,
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

local function refreshViewportLayout()
	syncBoardContentLayout()
	refreshUiBindings()

	if updateHud then
		updateHud()
	end

	if RuntimeHelpers.refreshDuelModeUi then
		RuntimeHelpers.refreshDuelModeUi()
	end
	if RuntimeHelpers.refreshHintButtonLayout then
		RuntimeHelpers.refreshHintButtonLayout()
	end
	if state.metaUiController then
		if state.metaUiController.applySnapshot then
			state.metaUiController:applySnapshot(getSnapshot())
		elseif state.metaUiController.updateTimedRewards then
			state.metaUiController:updateTimedRewards()
		end
	end
	if updateWordsLabel and state.currentPuzzle then
		updateWordsLabel()
	end
	if RuntimeHelpers.refreshBoard and state.currentPuzzle then
		RuntimeHelpers.refreshBoard()
	end
	if refreshPersistentLines and state.currentPuzzle then
		refreshPersistentLines()
	end
	if RuntimeHelpers.refreshBoardCursor then
		RuntimeHelpers.refreshBoardCursor()
	end
	if state.dragging and state.dragCursorPosition and RuntimeHelpers.updateDragTarget then
		RuntimeHelpers.updateDragTarget(state.dragCursorPosition)
	end
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
			if RuntimeHelpers and RuntimeHelpers.updateCountdownLetterScatter then
				RuntimeHelpers.updateCountdownLetterScatter(shouldScramble, shuffleStep)
			end
			if not shouldScramble then
				break
			end

			shuffleStep += 1
			task.wait(0.18)
		end

		if RuntimeHelpers and RuntimeHelpers.updateCountdownLetterScatter then
			RuntimeHelpers.updateCountdownLetterScatter(false)
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
		if RuntimeHelpers and RuntimeHelpers.updateCountdownLetterScatter then
			RuntimeHelpers.updateCountdownLetterScatter(false)
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

RuntimeHelpers.beginBoardCountdownIfNeeded = function(boardToken)
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
			puzzlePieces = 0,
		},
		progression = {
			lastClassicLevel = state.savedClassicLevel,
			highestClassicLevel = state.savedClassicLevel,
			giftClaimMilestone = 0,
		},
		stats = {
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

function RuntimeHelpers.formatLongTime(seconds)
	local whole = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(whole / 3600)
	local minutes = math.floor((whole % 3600) / 60)
	local remainingSeconds = whole % 60
	return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

function RuntimeHelpers.calculateAwardedStars(cleared)
	if state.duelActive then
		return 0
	end

	return Dependencies.StarRules.CalculateAward(
		state.mode,
		state.puzzleIndex,
		state.currentBoardHintUses,
		cleared == true
	)
end

function RuntimeHelpers.calculateAwardedPuzzlePiecesPreview()
	local minimumReward = math.max(0, math.floor(tonumber(Dependencies.PuzzleEconomy.MinimumCompletionReward) or 0))
	if not state.currentPuzzle then
		return minimumReward
	end

	local elapsed = math.max(0, tick() - (state.boardStartedAt or tick()))
	return math.max(minimumReward, Dependencies.PuzzleEconomy.CalculateCompletionPieces({
		mode = state.mode,
		gridSize = state.currentPuzzle.gridSize,
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

getSnapshot = function()
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
		math.floor(tonumber(snapshotStats and snapshotStats.boardsCleared) or 0),
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
		math.floor(tonumber(snapshot.stats and snapshot.stats.boardsCleared) or 0),
		math.floor(tonumber(totalBucket and totalBucket.wins) or 0)
	) or math.max(0, math.floor(state.totalStars or 0))

	state.playerData = snapshot
	RuntimeHelpers.syncClientDataMirror(snapshot)
	state.totalStars = totalWins
	state.availableHints = math.max(0, math.floor((snapshot.inventory and snapshot.inventory.hintsAvailable) or state.availableHints or 0))
	state.savedClassicLevel = math.clamp(math.floor((snapshot.progression and snapshot.progression.lastClassicLevel) or state.savedClassicLevel or 1), 1, #Dependencies.Levels)
	local snapshotBoardState = type(snapshot.boardState) == "table" and snapshot.boardState or nil
	if snapshotBoardState and snapshotBoardState.mode == "Classic" then
		local resumeLevel = math.clamp(math.floor(tonumber(snapshotBoardState.level) or state.savedClassicLevel), 1, #Dependencies.Levels)
		if resumeLevel ~= state.savedClassicLevel then
			snapshotBoardState = nil
		end
	end
	snapshot.boardState = snapshotBoardState
	state.resumeBoardState = snapshotBoardState
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
	local mode = tostring(payload and payload.mode or "")
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
		stats.modeResults = modeResults
		stats.modeStreaks = modeStreaks
		snapshot.boardState = nil
		recordSnapshotStarProgress(snapshot, mode, level, payload and payload.stars)
		inventory.puzzlePieces = math.max(0, math.floor((inventory.puzzlePieces or 0) + puzzlePiecesEarned))
		if mode == "Daily" then
			local dailyMode = type(snapshot.dailyMode) == "table" and snapshot.dailyMode or {}
			dailyMode.completedDayStamp = Dependencies.DailyMode.GetCurrentDayStamp()
			dailyMode.completed = true
			dailyMode.secondsUntilReset = Dependencies.DailyMode.GetSecondsUntilReset()
			dailyMode.resetTimestamp = Dependencies.DailyMode.GetNextResetTimestamp()
			snapshot.dailyMode = dailyMode
		end

		if mode == "Daily" then
		elseif mode ~= "Classic" then
			stats.endlessBoards = math.max(0, math.floor((stats.endlessBoards or 0) + 1))
			if mode == "Freeplay" then
				stats.freeplayBoards = math.max(0, math.floor((stats.freeplayBoards or 0) + 1))
			elseif mode == "Backwards" then
				stats.backwardsBoards = math.max(0, math.floor((stats.backwardsBoards or 0) + 1))
			end
		elseif mode == "Classic" then
			stats.classicBoards = math.max(0, math.floor((stats.classicBoards or 0) + 1))
			local unlockedLevel = math.min(#Dependencies.Levels, level + 1)
			progression.lastClassicLevel = math.max(progression.lastClassicLevel or 1, unlockedLevel)
			progression.highestClassicLevel = math.max(progression.highestClassicLevel or 1, unlockedLevel)
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
		if payload and payload.mode and payload.level and payload.stars ~= nil then
			recordSnapshotStarProgress(snapshot, payload.mode, payload.level, payload.stars)
		end
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
	local sharedRemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local sharedEventsFolder = sharedRemotesFolder and sharedRemotesFolder:FindFirstChild("Events") or nil
	remotes.adminBoardReset = sharedEventsFolder and sharedEventsFolder:FindFirstChild(Dependencies.RemoteConfig.Legacy.AdminBoardReset) or nil
	remotes.claimGift = sharedEventsFolder and sharedEventsFolder:FindFirstChild(Dependencies.RemoteConfig.Legacy.ClaimGift) or nil

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

	if remotes.claimGift then
		remotes.claimGift.OnClientEvent:Connect(function(payload)
			state.summaryGiftClaimPending = false
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
		getModeUnlockWins = getModeUnlockWins,
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
	local duelVisible = modeUnlocked and (selectedMode == "Classic" or selectedMode == "Freeplay")

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

	local nextEnabled = state.mode == "Classic"
		and canInteract and state.puzzleIndex < #Dependencies.Levels
		or (state.mode ~= "Classic" and canInteract)
	if state.duelActive then
		nextEnabled = false
	end

	ButtonUi.setEnabled(ui.nextButton, nextEnabled, COLORS.buttonPrimary)
	if ui.exitButton and ui.exitButton:IsA("GuiObject") then
		ui.exitButton.Visible = true
	end
	ButtonUi.setClickableOnly(ui.exitButton, gameViewDisplayed and not isGameplayInteractionBlocked())
	if state.metaUiController and state.metaUiController.updateTimedRewards then
		state.metaUiController:updateTimedRewards()
	end
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
			canShowTimedRewards = function()
				return state.gameViewActive and not state.duelActive
			end,
		})
		state.metaUiController:bind(ui.screenGui)
	end
	if ui.screenGui and not state.adminMenuController then
		state.adminMenuController = Dependencies.AdminMenuUI.new({
			playSound = playSound,
			showDesktopAlert = showDesktopAlert,
		})
		state.adminMenuController:bind(ui.screenGui)
	end
	if ui.screenGui and not state.duelController then
		state.duelController = Dependencies.DuelUI.new({
			showDesktopAlert = showDesktopAlert,
			trackFunnelStep = trackFunnelStep,
			getSelectedMode = function()
				return getSelectedMenuModeName()
			end,
			getSolvesText = function(userId)
				local duelPlayer = Players:GetPlayerByUserId(userId)
				local leaderstats = duelPlayer and duelPlayer:FindFirstChild("leaderstats")
				local wins = leaderstats and leaderstats:FindFirstChild("Wins")
				return wins and string.format("Wins: %d", wins.Value) or "Wins: --"
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
	if resumeBoardState.mode == "Classic" then
		local resumeLevel = math.clamp(math.floor(tonumber(resumeBoardState.level) or state.savedClassicLevel), 1, #Dependencies.Levels)
		if resumeLevel ~= state.savedClassicLevel then
			state.resumeBoardState = nil
			state.pendingResumeBoardState = nil
			return false
		end
	end

	state.mode = resumeBoardState.mode
	state.sessionScore = math.max(0, math.floor(tonumber(resumeBoardState.sessionScore) or 0))
	state.puzzlesCleared = math.max(0, math.floor(tonumber(resumeBoardState.puzzlesCleared) or 0))
	state.streak = math.max(0, math.floor(tonumber(resumeBoardState.streak) or 0))
	state.gameEnded = false
	hideSummary()
	clearHint()
	state.gameplayInputLocked = false

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
	local forceFreshStart = selectedMode == "Themed"
	trackFunnelStep("PlayPressed_" .. tostring(selectedMode), {
		mode = selectedMode,
	})
	local unlockWins = getModeUnlockWins(selectedMode)
	if unlockWins and not isModeUnlocked(selectedMode) then
		showDesktopAlert(nil, string.format("Unlocks at %d wins.", unlockWins), "error", {
			duration = 2.2,
		})
		return
	end
	if selectedMode == "Daily" and hasCompletedDailyToday() then
		showDesktopAlert("Daily", string.format("New daily in %s", RuntimeHelpers.formatLongTime(getDailyModeInfo().secondsUntilReset)), "info", {
			color = MODES.Daily.accent,
			duration = 2.6,
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
		local hadSavedThemedBoard = (type(state.resumeBoardState) == "table" and state.resumeBoardState.mode == selectedMode)
			or (activeBoardState and activeBoardState.mode == selectedMode)
		if hadSavedThemedBoard then
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
			updateHud()
			RuntimeHelpers.refreshBoard()
			refreshPersistentLines()
			RuntimeHelpers.beginBoardCountdownIfNeeded(state.boardToken)
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
Dependencies.DeviceOrientation.Init({
	playerGui = state.runtimePlayerGui,
	onViewportChanged = function()
		refreshViewportLayout()
		task.defer(refreshViewportLayout)
		task.delay(0.15, refreshViewportLayout)
	end,
})
state.startupHud = Dependencies.InterfaceBootstrap.ensurePlatformHUD(
	state.runtimePlayerGui,
	ReplicatedStorage:FindFirstChild("Interfaces"),
	UserInputService
) or Dependencies.InterfaceBootstrap.findHUD(state.runtimePlayerGui, 15)
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
	state = state,
	runtimeHelpers = RuntimeHelpers,
	userInputService = UserInputService,
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
end)

end

return GameController
