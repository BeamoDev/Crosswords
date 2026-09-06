local PuzzleValidator = {}
local PuzzleTypes = if script
	then require(script.Parent:WaitForChild("PuzzleTypes"))
	else require("./PuzzleTypes")

type Cell = PuzzleTypes.Cell
type PuzzleDefinition = PuzzleTypes.PuzzleDefinition

local VALID_DIRECTIONS = {
	N = true,
	NE = true,
	E = true,
	SE = true,
	S = true,
	SW = true,
	W = true,
	NW = true,
}

function PuzzleValidator.NormalizeWord(word: any): string?
	if type(word) ~= "string" then
		return nil
	end
	local normalized = string.upper(word:gsub("%s+", ""))
	return normalized ~= "" and normalized or nil
end

function PuzzleValidator.SanitizePath(path: any, maximumLength: number?, maximumCoordinate: number?): { Cell }?
	if type(path) ~= "table" then
		return nil
	end
	local maxLength = math.max(1, math.floor(tonumber(maximumLength) or 32))
	local maxCoordinate = math.max(1, math.floor(tonumber(maximumCoordinate) or 32))
	if #path <= 0 or #path > maxLength then
		return nil
	end

	local sanitized = {}
	for index, point in ipairs(path) do
		if type(point) ~= "table" then
			return nil
		end
		local row = tonumber(point.row)
		local column = tonumber(point.column)
		if not row or not column or row ~= math.floor(row) or column ~= math.floor(column)
			or row < 1 or column < 1 or row > maxCoordinate or column > maxCoordinate then
			return nil
		end
		sanitized[index] = { row = row, column = column }
	end
	return sanitized
end

function PuzzleValidator.PathsMatch(expectedPath: any, claimedPath: any): boolean
	local left = PuzzleValidator.SanitizePath(expectedPath)
	local right = PuzzleValidator.SanitizePath(claimedPath)
	if not left or not right or #left ~= #right then
		return false
	end
	for index = 1, #left do
		if left[index].row ~= right[index].row or left[index].column ~= right[index].column then
			return false
		end
	end
	return true
end

function PuzzleValidator.ValidateDefinition(definition: PuzzleDefinition): (boolean, string?)
	if type(definition) ~= "table" then
		return false, "definition must be a table"
	end
	local gridSize = tonumber(definition.gridSize)
	if not gridSize or gridSize ~= math.floor(gridSize) or gridSize < 4 or gridSize > 32 then
		return false, "gridSize must be an integer from 4 to 32"
	end
	if type(definition.words) ~= "table" or #definition.words < 1 or #definition.words > 32 then
		return false, "words must contain 1 to 32 entries"
	end
	local seen = {}
	for _, value in ipairs(definition.words) do
		local word = PuzzleValidator.NormalizeWord(value)
		if not word or #word > gridSize or seen[word] then
			return false, "words must be unique and fit the grid"
		end
		seen[word] = true
	end
	if type(definition.directions) ~= "table" or #definition.directions < 1 or #definition.directions > 8 then
		return false, "directions must contain 1 to 8 entries"
	end
	for _, direction in ipairs(definition.directions) do
		local directionIsValid = type(direction) == "string" and VALID_DIRECTIONS[direction] == true
		if type(direction) == "table" then
			local rowStep = tonumber(direction[1])
			local columnStep = tonumber(direction[2])
			directionIsValid = #direction == 2
				and rowStep ~= nil
				and columnStep ~= nil
				and rowStep == math.floor(rowStep)
				and columnStep == math.floor(columnStep)
				and math.abs(rowStep) <= 1
				and math.abs(columnStep) <= 1
				and (rowStep ~= 0 or columnStep ~= 0)
		end
		if not directionIsValid then
			return false, "unsupported direction"
		end
	end
	return true
end

return PuzzleValidator
