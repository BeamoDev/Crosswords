local Workspace = game:GetService("Workspace")

local MusicPlayer = {}

local TRACKS = {
	"rbxassetid://72191087451264",
	"rbxassetid://133244468349763",
	"rbxassetid://9045766377",
	"rbxassetid://136037234851815",
}

local currentTrack = 1
local targetVolume = 0.2
local enabled = true
local initialized = false
local sound

local function ensureSound()
	if sound and sound.Parent then
		return sound
	end

	sound = Instance.new("Sound")
	sound.Name = "Player"
	sound.Archivable = true
	sound.Pitch = 0.95
	sound.Looped = false
	sound.Volume = 0
	sound.Parent = Workspace

	sound.Ended:Connect(function()
		if not enabled then
			return
		end

		currentTrack = (currentTrack % #TRACKS) + 1
		sound.SoundId = TRACKS[currentTrack]
		sound:Play()
	end)

	return sound
end

local function applyVolume()
	if not sound then
		return
	end

	sound.Volume = enabled and targetVolume or 0
end

local function playCurrent()
	ensureSound()
	sound.SoundId = TRACKS[currentTrack]
	applyVolume()
	if enabled then
		sound:Play()
	end
end

function MusicPlayer.Initialize()
	if initialized then
		return
	end

	initialized = true
	playCurrent()
end

function MusicPlayer.SetVolume(volume)
	targetVolume = math.clamp(tonumber(volume) or targetVolume, 0, 1)
	applyVolume()
end

function MusicPlayer.GetVolume()
	return targetVolume
end

function MusicPlayer.SetEnabled(value)
	enabled = value == true
	applyVolume()
	-- Profile updates (including hints) must not restart an already playing track.
	if enabled and sound and not sound.IsPlaying then
		sound:Play()
	end
end

function MusicPlayer.IsEnabled()
	return enabled
end

return MusicPlayer
