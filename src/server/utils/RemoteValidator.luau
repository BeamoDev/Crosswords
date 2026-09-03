local RemoteValidator = {}

local MAX_IDENTIFIER_LENGTH = 96

function RemoteValidator.IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function RemoteValidator.Identifier(value, maxLength)
	if type(value) ~= "string" then
		return nil
	end

	local limit = math.clamp(math.floor(tonumber(maxLength) or MAX_IDENTIFIER_LENGTH), 1, 160)
	if #value < 1 or #value > limit or not string.match(value, "^[%w_%-:%.]+$") then
		return nil
	end

	return value
end

function RemoteValidator.Cell(value, maxHeight, maxWidth)
	if type(value) ~= "table" then
		return nil
	end

	local row = value.row
	local column = value.column
	if not RemoteValidator.IsFiniteNumber(row)
		or not RemoteValidator.IsFiniteNumber(column)
		or row % 1 ~= 0
		or column % 1 ~= 0
	then
		return nil
	end

	if row < 1 or column < 1 or row > maxHeight or column > maxWidth then
		return nil
	end

	return { row = row, column = column }
end

function RemoteValidator.StartRequest(value)
	if type(value) ~= "table" then
		return nil
	end

	local mode = RemoteValidator.Identifier(value.mode, 16)
	-- Zen is server-ready and explicitly unranked; the shipped menu currently
	-- exposes the three prioritized modes only.
	if not mode or (mode ~= "Classic" and mode ~= "Quick" and mode ~= "Daily" and mode ~= "Zen") then
		return nil
	end

	local levelId = nil
	if value.levelId ~= nil then
		levelId = RemoteValidator.Identifier(value.levelId, 64)
		if not levelId then
			return nil
		end
	end

	return {
		mode = mode,
		levelId = levelId,
	}
end

function RemoteValidator.Selection(value, maxHeight, maxWidth)
	if type(value) ~= "table" then
		return nil
	end

	local roundId = RemoteValidator.Identifier(value.roundId, 80)
	local startCell = RemoteValidator.Cell(value.startCell, maxHeight, maxWidth)
	local endCell = RemoteValidator.Cell(value.endCell, maxHeight, maxWidth)
	if not roundId or not startCell or not endCell then
		return nil
	end

	return {
		roundId = roundId,
		startCell = startCell,
		endCell = endCell,
	}
end

function RemoteValidator.RoundRequest(value)
	if type(value) ~= "table" then
		return nil
	end

	local roundId = RemoteValidator.Identifier(value.roundId, 80)
	if not roundId then
		return nil
	end

	return { roundId = roundId }
end

function RemoteValidator.HintRequest(value)
	local request = RemoteValidator.RoundRequest(value)
	local requestId = type(value) == "table" and RemoteValidator.Identifier(value.requestId, 80) or nil
	if not request or not requestId then
		return nil
	end
	request.requestId = requestId
	return request
end

function RemoteValidator.PauseRequest(value)
	local request = RemoteValidator.RoundRequest(value)
	if not request or type(value.paused) ~= "boolean" then
		return nil
	end

	request.paused = value.paused
	return request
end

function RemoteValidator.SettingRequest(value)
	if type(value) ~= "table" then
		return nil
	end

	local allowed = {
		music = "boolean",
		sfx = "boolean",
		musicVolume = "number",
		sfxVolume = "number",
		uiAnimations = "boolean",
		reducedMotion = "boolean",
		highContrast = "boolean",
		colorblindMode = "boolean",
	}
	local name = RemoteValidator.Identifier(value.name, 32)
	local expectedType = name and allowed[name] or nil
	if not expectedType or type(value.value) ~= expectedType then
		return nil
	end
	local settingValue = value.value
	if expectedType == "number" then
		if not RemoteValidator.IsFiniteNumber(settingValue) or settingValue < 0 or settingValue > 1 then
			return nil
		end
		settingValue = math.floor(settingValue * 20 + 0.5) / 20
	end
	return { name = name, value = settingValue }
end

function RemoteValidator.ShopPurchase(value)
	if type(value) ~= "table" then return nil end
	local productId = RemoteValidator.Identifier(value.productId, 96)
	local requestId = RemoteValidator.Identifier(value.requestId, 128)
	if not productId or not requestId then return nil end
	return { productId = productId, requestId = requestId }
end

function RemoteValidator.CosmeticRequest(value)
	if type(value) ~= "table" then return nil end
	local kind = RemoteValidator.Identifier(value.kind, 24)
	local itemId = RemoteValidator.Identifier(value.itemId, 96)
	if not kind or not itemId or (kind ~= "Theme" and kind ~= "Trail" and kind ~= "Background" and kind ~= "UIStyle") then
		return nil
	end
	return { kind = kind, itemId = itemId }
end

return table.freeze(RemoteValidator)
