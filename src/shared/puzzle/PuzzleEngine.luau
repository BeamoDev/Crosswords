local PuzzleEngine = {}
local PuzzleTypes = if script
	then require(script.Parent:WaitForChild("PuzzleTypes"))
	else require("./PuzzleTypes")

type Cell = PuzzleTypes.Cell

local function sign(value)
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

function PuzzleEngine.GetLineSequence(startRow: number, startColumn: number, endRow: number, endColumn: number): { Cell }?
	local rowDelta = endRow - startRow
	local columnDelta = endColumn - startColumn
	if rowDelta ~= 0 and columnDelta ~= 0 and math.abs(rowDelta) ~= math.abs(columnDelta) then
		return nil
	end

	local rowStep = sign(rowDelta)
	local columnStep = sign(columnDelta)
	local length = math.max(math.abs(rowDelta), math.abs(columnDelta)) + 1
	local points = {}
	for index = 0, length - 1 do
		points[index + 1] = {
			row = startRow + rowStep * index,
			column = startColumn + columnStep * index,
		}
	end
	return points
end

function PuzzleEngine.PathsMatch(selection: { Cell }, path: { Cell }, allowReverse: boolean?): boolean
	if type(selection) ~= "table" or type(path) ~= "table" or #selection ~= #path then
		return false
	end

	local function matches(reverse)
		for index = 1, #selection do
			local left = selection[index]
			local right = path[reverse and (#path - index + 1) or index]
			if type(left) ~= "table" or type(right) ~= "table"
				or left.row ~= right.row or left.column ~= right.column then
				return false
			end
		end
		return true
	end

	return matches(false) or (allowReverse == true and matches(true))
end

function PuzzleEngine.IsComplete(words: { string }, foundWords: { [string]: boolean }): boolean
	if type(words) ~= "table" or type(foundWords) ~= "table" then
		return false
	end
	for _, word in ipairs(words) do
		if foundWords[word] ~= true then
			return false
		end
	end
	return #words > 0
end

function PuzzleEngine.CalculateWordScore(word: string, multiplier: number?): number
	return math.floor(#tostring(word or "") * 20 * math.max(0, tonumber(multiplier) or 1))
end

return PuzzleEngine
