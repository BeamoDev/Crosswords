local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("Levels"))

local StarRules = {}

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)

local function clampClassicLevel(level)
	return math.clamp(math.max(1, math.floor(tonumber(level) or 1)), 1, MAX_CLASSIC_LEVEL)
end

local function getBoardInfo(mode, level)
	if mode == "Classic" or mode == "Daily" or mode == "Freeplay" or mode == "Backwards" or mode == "Fog" or mode == "OneLife" or mode == "Mega" then
		return Levels[clampClassicLevel(level)]
	end

	return Levels[clampClassicLevel(level)]
end

function StarRules.GetModeBucket(mode)
	return tostring(mode or "Classic")
end

function StarRules.GetPackName(mode, level)
	local safeMode = tostring(mode or "Classic")
	if safeMode == "Classic" then
		local boardInfo = getBoardInfo(safeMode, level)
		return tostring((boardInfo and (boardInfo.pack or boardInfo.tier)) or "Classic")
	end

	return safeMode
end

function StarRules.GetEntryKey(mode, level, metadata)
	local safeMode = tostring(mode or "Classic")
	if safeMode == "Classic" then
		local boardInfo = getBoardInfo(safeMode, level)
		local packLevel = math.max(1, math.floor(tonumber(boardInfo and (boardInfo.packLevel or boardInfo.tierLevel) or level) or 1))
		return string.format("%02d", packLevel)
	end

	if safeMode == "Daily" then
		local dayStamp = math.max(0, math.floor(tonumber(metadata and metadata.dayStamp) or 0))
		if dayStamp > 0 then
			return tostring(dayStamp)
		end
	end

	return string.format("%03d", clampClassicLevel(level))
end

function StarRules.ResolveSlot(mode, level, metadata)
	local safeMode = tostring(mode or "Classic")
	return {
		mode = StarRules.GetModeBucket(safeMode),
		pack = StarRules.GetPackName(safeMode, level),
		entry = StarRules.GetEntryKey(safeMode, level, metadata),
	}
end

function StarRules.CalculateAward(_mode, _level, hintsUsed, cleared)
	if cleared ~= true then
		return 0
	end

	local safeHintsUsed = math.max(0, math.floor(tonumber(hintsUsed) or 0))
	if safeHintsUsed == 0 then
		return 3
	elseif safeHintsUsed == 1 then
		return 2
	end

	return 1
end

return StarRules
