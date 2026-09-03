--!nocheck

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioController = {}
AudioController.__index = AudioController

local DEFAULT_ALIASES = {
	Button = { "Button", "Button2", "Click", "OpenFrame" },
	Correct = { "Correct", "NotificationHigh", "Plus" },
	Incorrect = { "Incorrect", "Wrong", "NotificationLow", "Minus" },
	Complete = { "Complete", "Victory", "Win" },
	Hint = { "Hint", "NotificationMid", "NotificationLow" },
	Unlock = { "Unlock", "Purchase", "NotificationHigh" },
	Music = { "Music", "Player", "Background", "Theme" },
}

local function resolveGameConfig(explicitConfig)
	if type(explicitConfig) == "table" then
		return explicitConfig
	end

	local shared = ReplicatedStorage:FindFirstChild("shared")
	local configFolder = shared and shared:FindFirstChild("config")
	local moduleScript = configFolder and configFolder:FindFirstChild("GameConfig")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" then
			return result
		end
	end

	return { Assets = { Sounds = {} } }
end

local function normalizeSoundId(value)
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if type(value) ~= "string" or value == "" then
		return nil
	end
	if string.match(value, "^rbxassetid://%d+$") or string.match(value, "^https?://") then
		return value
	end
	local numeric = tonumber(value)
	if numeric and numeric > 0 then
		return "rbxassetid://" .. tostring(math.floor(numeric))
	end
	return nil
end

local function firstSound(root, names, allowFallback)
	if not root then
		return nil
	end
	for _, name in ipairs(names or {}) do
		local candidate = root:FindFirstChild(name, true)
		if candidate and candidate:IsA("Sound") then
			return candidate
		end
	end
	if allowFallback then
		return root:FindFirstChildWhichIsA("Sound", true)
	end
	return nil
end

function AudioController.new(options)
	options = options or {}
	local self = setmetatable({}, AudioController)
	self._soundService = options.soundService or SoundService
	self._gameConfig = resolveGameConfig(options.gameConfig)
	self._aliases = options.aliases or DEFAULT_ALIASES
	self._sfxEnabled = true
	self._musicEnabled = true
	self._sfxVolume = math.clamp(tonumber(options.sfxVolume) or 0.8, 0, 1)
	self._musicVolume = math.clamp(tonumber(options.musicVolume) or 0.35, 0, 1)
	self._destroyed = false
	self._musicSound = nil
	self._warnedSlots = {}
	self._connections = {}

	self._runtimeFolder = Instance.new("Folder")
	self._runtimeFolder.Name = "WordSearchRevampAudio"
	self._runtimeFolder:SetAttribute("RuntimeOwned", true)
	self._runtimeFolder.Parent = self._soundService

	if options.settings then
		self:SetSettings(options.settings)
	end
	return self
end

function AudioController:_assetFor(key)
	local assets = self._gameConfig.Assets
	local sounds = type(assets) == "table" and assets.Sounds or nil
	return normalizeSoundId(type(sounds) == "table" and sounds[key] or nil)
end

function AudioController:_templateFor(key, music)
	local aliases = self._aliases[key] or { key }
	local preferredRoot = self._soundService:FindFirstChild(music and "Music" or "SFX")
	local template = firstSound(preferredRoot, aliases, music)
	if template then
		return template
	end

	for _, folderName in ipairs(music and { "BackgroundMusic", "Audio", "Sounds" } or { "Sounds", "Audio" }) do
		-- Generic Audio/Sounds folders often mix music and one-shot effects. Only
		-- take an arbitrary fallback from a folder explicitly dedicated to music.
		local allowFallback = music and folderName == "BackgroundMusic"
		template = firstSound(self._soundService:FindFirstChild(folderName), aliases, allowFallback)
		if template then
			return template
		end
	end
	return nil
end

function AudioController:_createSound(key, music)
	if self._destroyed or not self._runtimeFolder.Parent then
		return nil
	end

	local template = self:_templateFor(key, music)
	local sound
	if template then
		sound = template:Clone()
	else
		local soundId = self:_assetFor(key)
		if not soundId then
			if not self._warnedSlots[key] then
				self._warnedSlots[key] = true
				warn(string.format("[WordSearch Audio] No reusable Sound or GameConfig.Assets.Sounds.%s placeholder ID.", tostring(key)))
			end
			return nil
		end
		sound = Instance.new("Sound")
		sound.SoundId = soundId
	end

	sound.Name = tostring(key)
	sound.Parent = self._runtimeFolder
	return sound
end

function AudioController:SetSettings(settings)
	settings = settings or {}
	local sfx = settings.sfx
	if sfx == nil then
		sfx = settings.SFX
	end
	local music = settings.music
	if music == nil then
		music = settings.Music
	end
	if sfx ~= nil then
		self:SetSfxEnabled(sfx == true)
	end
	if music ~= nil then
		self:SetMusicEnabled(music == true)
	end
	if settings.sfxVolume ~= nil then
		self:SetSfxVolume(settings.sfxVolume)
	end
	if settings.musicVolume ~= nil then
		self:SetMusicVolume(settings.musicVolume)
	end
end

function AudioController:SetSfxEnabled(enabled)
	self._sfxEnabled = enabled == true
end

function AudioController:SetMusicEnabled(enabled)
	self._musicEnabled = enabled == true
	if self._musicSound then
		self._musicSound.Volume = self._musicEnabled and self._musicVolume or 0
		if self._musicEnabled and not self._musicSound.IsPlaying then
			self._musicSound:Play()
		elseif not self._musicEnabled then
			self._musicSound:Pause()
		end
	end
end

function AudioController:SetSfxVolume(volume)
	self._sfxVolume = math.clamp(tonumber(volume) or self._sfxVolume, 0, 1)
end

function AudioController:SetMusicVolume(volume)
	self._musicVolume = math.clamp(tonumber(volume) or self._musicVolume, 0, 1)
	if self._musicSound then
		self._musicSound.Volume = self._musicEnabled and self._musicVolume or 0
	end
end

function AudioController:Play(key, options)
	if self._destroyed or not self._sfxEnabled then
		return nil
	end
	options = options or {}
	local sound = self:_createSound(tostring(key), false)
	if not sound then
		return nil
	end

	sound.Looped = false
	sound.Volume = math.clamp((tonumber(options.volume) or sound.Volume or 1) * self._sfxVolume, 0, 10)
	sound.PlaybackSpeed = math.clamp(tonumber(options.playbackSpeed or options.pitch) or 1, 0.25, 4)
	if tonumber(options.timePosition) then
		sound.TimePosition = math.max(0, tonumber(options.timePosition))
	end
	sound:Play()
	Debris:AddItem(sound, math.max(5, tonumber(options.lifetime) or 20))
	return sound
end

function AudioController:PlayMusic(options)
	if self._destroyed then
		return nil
	end
	options = options or {}
	if self._musicSound and self._musicSound.Parent then
		self._musicSound.Volume = self._musicEnabled and self._musicVolume or 0
		if self._musicEnabled and not self._musicSound.IsPlaying then
			self._musicSound:Play()
		end
		return self._musicSound
	end

	local sound = self:_createSound(options.key or "Music", true)
	if not sound then
		return nil
	end
	sound.Looped = true
	sound.Volume = self._musicEnabled and self._musicVolume or 0
	sound.PlaybackSpeed = math.clamp(tonumber(options.playbackSpeed) or 1, 0.25, 4)
	self._musicSound = sound
	if self._musicEnabled then
		sound:Play()
	end
	return sound
end

function AudioController:StopMusic(fadeSeconds)
	local sound = self._musicSound
	if not sound then
		return
	end

	self._musicSound = nil
	local duration = math.max(0, tonumber(fadeSeconds) or 0)
	if duration <= 0 then
		sound:Stop()
		sound:Destroy()
		return
	end

	local tween = game:GetService("TweenService"):Create(sound, TweenInfo.new(duration), { Volume = 0 })
	local connection
	connection = tween.Completed:Connect(function()
		if connection then
			connection:Disconnect()
		end
		if sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end)
	table.insert(self._connections, connection)
	tween:Play()
end

function AudioController:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._musicSound then
		self._musicSound:Stop()
		self._musicSound = nil
	end
	if self._runtimeFolder then
		self._runtimeFolder:Destroy()
		self._runtimeFolder = nil
	end
end

return AudioController
