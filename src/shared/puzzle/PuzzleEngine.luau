local PuzzleEngine = {}
local Dictionary = if script then require(script.Parent.Parent.content.EnglishDictionary) else require("../content/EnglishDictionary")
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

-- Shared by pointer input and server validation. A tile can occur only once.
function PuzzleEngine.ReadAdjacentWord(letters, path): string?
	if type(path) ~= "table" or #path == 0 or #path > 32 then return nil end
	local used, result = {}, {}
	for index, cell in ipairs(path) do
		if type(cell) ~= "table" or type(cell.row) ~= "number" or type(cell.column) ~= "number"
			or cell.row % 1 ~= 0 or cell.column % 1 ~= 0 then return nil end
		local row = letters[cell.row]
		if not row or not row[cell.column] then return nil end
		local key = cell.row .. ":" .. cell.column
		if used[key] then return nil end
		used[key] = true
		if index > 1 then
			local previous = path[index - 1]
			if math.abs(cell.row - previous.row) > 1 or math.abs(cell.column - previous.column) > 1 then return nil end
		end
		table.insert(result, row[cell.column])
	end
	return table.concat(result)
end

-- Resolve from actual board letters, never a client-supplied word or XP amount.
function PuzzleEngine.ReadBonusWord(puzzle, path)
	if puzzle.rules ~= "Strands" or puzzle.tutorial then return nil end
	local spelling = PuzzleEngine.ReadAdjacentWord(puzzle.letters, path)
	if not spelling or #spelling < 3 then return nil end
	if Dictionary.Contains(spelling) then return spelling end
	local backwards = string.reverse(spelling)
	if Dictionary.Contains(backwards) then return backwards end
	return nil
end

function PuzzleEngine.ExtendAdjacentPath(path, cell): boolean
	local last = path[#path]
	if not last or (last.row == cell.row and last.column == cell.column) then return false end
	local previous = path[#path - 1]
	if previous and previous.row == cell.row and previous.column == cell.column then
		table.remove(path)
		return true
	end
	if math.abs(last.row - cell.row) > 1 or math.abs(last.column - cell.column) > 1 then return false end
	for _, point in ipairs(path) do
		if point.row == cell.row and point.column == cell.column then return false end
	end
	table.insert(path, { row = cell.row, column = cell.column })
	return true
end

function PuzzleEngine.MatchesStrand(puzzle, word, path): boolean
	local placed = type(word) == "string" and puzzle.placedWordsByWord[word]
	if not placed then return false end
	local spelling = PuzzleEngine.ReadAdjacentWord(puzzle.letters, path)
	if spelling ~= word and spelling ~= string.reverse(word) then return false end
	-- Reordering identical letters is fine; borrowing another answer's tiles is
	-- not, because it would leave the exact-cover board impossible to finish.
	local owned = {}
	for _, cell in ipairs(placed.path) do owned[cell.row .. ":" .. cell.column] = true end
	for _, cell in ipairs(path) do if not owned[cell.row .. ":" .. cell.column] then return false end end
	return true
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
