-- Exact-cover themed puzzles: no filler, overlaps, or unused cells.
local Catalog = if script then require(script.Parent.Parent.content.PuzzleCatalog) else require("../content/PuzzleCatalog")
local Strands = {}
local clues = {
	Countries = "Passport, please", Animals = "Wild company", Food = "Something tasty", Sports = "Game on",
	Space = "Beyond our world", Ocean = "Below the waves", Weather = "Look to the skies", Music = "Turn it up",
	Jobs = "A day's work", Fantasy = "Once upon a time", Dinosaurs = "Long before us", Vehicles = "Going places",
	School = "Class is in session", ArtStudio = "Make your mark", Garden = "Watch it grow", Movies = "Roll the credits",
	Technology = "Plugged in", House = "Make yourself comfortable", Insects = "Small wonders", Pirates = "Ahoy there",
	Holidays = "Time to celebrate", Mountains = "On the way up", Robots = "Some assembly required", City = "Busy streets",
	Mythology = "Legends live on", Superheroes = "Here to save the day", Roblox = "Imagine, build, play",
	Brainrot = "Very online", Obbies = "Watch your step", Tycoons = "From the ground up", PetCollecting = "Hatch a friend",
	Football = "On the pitch", Basketball = "Nothing but net", Racing = "Ready, set, go",
	["Yummy Food"] = "Snack time", ["Let's Play"] = "Time for fun", ["At Home"] = "Home sweet home", Outside = "Fresh air",
}

local function shuffle(values, random)
	for i = #values, 2, -1 do
		local j = random:NextInteger(1, i)
		values[i], values[j] = values[j], values[i]
	end
	return values
end

local function chooseWords(theme, total, width, random)
	-- Answers must come from the authored vocabulary, never a joined theme title.
	local pool, seen = {}, {}
	for _, raw in ipairs(theme.words) do
		local word = raw:upper()
		if word:match("^[A-Z]+$") and #word >= 3 and #word <= 14 and not seen[word] then
			seen[word] = true
			table.insert(pool, word)
		end
	end
	shuffle(pool, random)
	-- A real theme word still spans the board. Try each eligible word until the
	-- remaining vocabulary covers every other tile without filler or duplicates.
	for _, spangram in ipairs(pool) do
		if #spangram < width then continue end
		local remaining = total - #spangram
		local sums = { [0] = {} }
		for _, word in ipairs(pool) do
			if word == spangram then continue end
			for sum = remaining, #word, -1 do
				if sums[sum - #word] and (not sums[sum] or #sums[sum - #word] + 1 > #sums[sum]) then
					local selected = table.clone(sums[sum - #word])
					table.insert(selected, word)
					sums[sum] = selected
				end
			end
		end
		local selected = sums[remaining]
		if selected and #selected >= 2 then return shuffle(selected, random), spangram end
	end
	return nil
end

local function spans(path, start, length, height, width)
	local top, bottom, left, right = false, false, false, false
	local previousRow, previousColumn, bent = nil, nil, false
	for i = start, start + length - 1 do
		local cell = path[i]
		if i > start then
			local dr, dc = cell.row - path[i - 1].row, cell.column - path[i - 1].column
			if previousRow and (dr ~= previousRow or dc ~= previousColumn) then bent = true end
			previousRow, previousColumn = dr, dc
		end
		top, bottom = top or cell.row == 1, bottom or cell.row == height
		left, right = left or cell.column == 1, right or cell.column == width
	end
	return bent and ((top and bottom) or (left and right))
end

-- Backbite moves change a Hamiltonian path without losing coverage. Only
-- new joins are orthogonal; the initial path also includes diagonal bends.
local function mix(path, random)
	if random:NextInteger(0, 1) == 1 then
		for i = 1, math.floor(#path / 2) do path[i], path[#path - i + 1] = path[#path - i + 1], path[i] end
	end
	local first, candidates = path[1], {}
	for i = 3, #path do
		local cell = path[i]
		if math.abs(first.row - cell.row) + math.abs(first.column - cell.column) == 1 then table.insert(candidates, i) end
	end
	if #candidates == 0 then return end
	local finish = candidates[random:NextInteger(1, #candidates)] - 1
	for i = 1, math.floor(finish / 2) do path[i], path[finish - i + 1] = path[finish - i + 1], path[i] end
end

-- Prefer the reading direction along each word's dominant axis. Reversing an
-- individual path preserves its bends, full coverage and opposite-edge span.
local function orientWord(cells, random, backwardsPercent)
	local first, last = cells[1], cells[#cells]
	local dx, dy = last.column - first.column, last.row - first.row
	local backwards = if math.abs(dx) >= math.abs(dy) then dx < 0 else dy < 0
	local wantBackwards = random:NextInteger(1,100) <= backwardsPercent
	if backwards ~= wantBackwards then
		for i = 1, math.floor(#cells / 2) do cells[i], cells[#cells-i+1] = cells[#cells-i+1], cells[i] end
	end
end

function Strands.Generate(definition, seed)
	if definition.tutorial then
		local cat = {word="CAT", path={{row=1,column=1},{row=1,column=2},{row=2,column=2}}}
		local dog = {word="DOG", path={{row=2,column=1},{row=3,column=1},{row=3,column=2}}}
		local fox = {word="FOX", path={{row=1,column=3},{row=2,column=3},{row=3,column=3}}}
		return {level=1, title="Furry friends", clue="Furry friends", rules="Strands", tutorial=true, seed=seed,
			gridSize=3, gridWidth=3, letters={{"C","A","F"},{"D","T","O"},{"O","G","X"}},
			words={"CAT","DOG","FOX"}, placedWords={cat,dog,fox}, placedWordsByWord={CAT=cat,DOG=dog,FOX=fox}}
	end
	local height, width = definition.gridSize, definition.gridWidth
	local random = Random.new(seed % 2147483647)
	local themes = shuffle(table.clone(definition.beginner and Catalog.BeginnerThemes or Catalog.GetThemes()), random)
	local selected, spangram, theme
	for _, candidate in ipairs(themes) do
		selected, spangram = chooseWords(candidate, height * width, width, random)
		if selected then theme = candidate break end
	end
	assert(theme, "No theme can cover these Strands dimensions")
	local path = {}
	for row = 1, height do
		for column = 1, width do
			table.insert(path, {row=row, column=row % 2 == 1 and column or width - column + 1})
		end
	end
	-- Swap the second cell of the first two snake rows. Both visits remain
	-- adjacent diagonally, so even a width-length spanning word has a bend.
	path[2], path[2 * width - 1] = path[2 * width - 1], path[2]
	local fallback, insertion = table.clone(path), 1
	local found = false
	for attempt = 1, 240 do
		for _ = 1, 12 do mix(path, random) end
		local offset = 1
		for index = 1, #selected + 1 do
			if spans(path, offset, #spangram, height, width) then insertion, found = index, true break end
			if selected[index] then offset += #selected[index] end
		end
		if found then break end
	end
	-- Guaranteed spanning prefix if randomized paths found no suitable boundary.
	if not found then path = fallback end
	-- Reflections keep even fallback boards varied and preserve adjacency/spanning.
	local flipRows, flipColumns = random:NextInteger(0,1) == 1, random:NextInteger(0,1) == 1
	for _, cell in ipairs(path) do
		if flipRows then cell.row = height - cell.row + 1 end
		if flipColumns then cell.column = width - cell.column + 1 end
	end
	table.insert(selected, insertion, spangram)
	local grid, placed, byWord, offset = {}, {}, {}, 1
	local backwardsPercent = (definition.beginner or definition.mode == "Mini") and 5 or 15
	for row = 1, height do grid[row] = {} end
	for _, word in ipairs(selected) do
		local cells = {}
		for i = 1, #word do
			local cell = path[offset]
			table.insert(cells, cell)
			offset += 1
		end
		orientWord(cells, random, backwardsPercent)
		for i, cell in ipairs(cells) do grid[cell.row][cell.column] = word:sub(i,i) end
		local entry = {word=word, path=cells}
		table.insert(placed, entry)
		byWord[word] = entry
	end
	-- Display order must not reveal where a word sits along the covering path.
	table.sort(selected, function(a,b) return a < b end)
	local clue = clues[theme.id or theme.title] or theme.subtitle or theme.title
	return {level=definition.level, mode=definition.mode, title=clue, clue=clue, theme=theme.title,
		seed=seed, rules="Strands", spangram=spangram, gridSize=height, gridWidth=width,
		letters=grid, words=selected, placedWords=placed, placedWordsByWord=byWord}
end

return Strands
