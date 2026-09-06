require("../src/shared/puzzle/PuzzleTests.spec")
local Generator = require("../src/shared/puzzle/PuzzleGenerator")
local Validator = require("../src/shared/puzzle/PuzzleValidator")
local Queue = require("../src/server/services/QueueState")
local checks = 0
local function check(value, reason) assert(value, reason) checks += 1 end
local Catalog = require("../src/shared/content/PuzzleCatalog")
local originalGetThemes = Catalog.GetThemes
local seenIds = {}
for _, theme in ipairs(Catalog.GetThemes()) do
	check(not seenIds[theme.id], "Theme IDs are unique: " .. theme.id)
	seenIds[theme.id] = true
	local words = {}
	for _, word in ipairs(theme.words) do
		check(word:match("^[A-Z]+$") and not words[word], "Theme words are unique uppercase letters: " .. theme.id .. "/" .. word)
		words[word] = true
	end
end
for _, id in ipairs({ "Roblox", "Brainrot", "Obbies", "Tycoons", "PetCollecting", "Football", "Basketball", "Racing", "Sports" }) do
	local theme = assert(Catalog.GetTheme(id), "Missing requested pack: " .. id)
	-- Isolate each pool so a random sample cannot silently miss a new pack.
	Catalog.GetThemes = function() return { theme } end
	local ok, problem = pcall(function()
		for _, mode in ipairs({ "Standard", "Mini", "Jumbo", "Hardcore", "Duel", "Timed" }) do
			for _, seed in ipairs({ 7919, 15838, 2147483646 }) do
				local definition = Generator.BuildDefinition(1, mode, seed)
				check(definition.title == theme.title and Validator.ValidateDefinition(definition), "Pack qualifies for " .. mode .. ": " .. id)
				local puzzle = Generator.Generate(definition, seed)
				check(#puzzle.words == #definition.words, "Every requested word is placed: " .. id)
				for _, word in ipairs(puzzle.words) do
					local placed = puzzle.placedWordsByWord[word]
					check(placed and #placed.path == #word, "Pack word has a full canonical path")
					for index, cell in ipairs(placed.path) do
						check(puzzle.letters[cell.row][cell.column] == word:sub(index, index), "Pack canonical path spells its word")
					end
				end
			end
		end
	end)
	Catalog.GetThemes = originalGetThemes
	assert(ok, problem)
end
for _, mode in ipairs({ "Classic", "Themed", "Freeplay", "Backwards", "Fog", "OneLife", "Mega", "Daily", "Unknown" }) do
	check(not pcall(Generator.BuildDefinition, 1, mode, 1), "Retired modes cannot fall back to gameplay: " .. mode)
end
for mode, spec in pairs({ Standard = {12, 10}, Mini = {6, 5}, Jumbo = {16, 20}, Hardcore = {12, 12}, Duel = {11, 10}, Timed = {12, 10} }) do
	local boards, themes, widths = {}, {}, {}
	for trial = 1, 100 do
		local seed = trial == 100 and 2147483646 or trial * 7919
		local definition = Generator.BuildDefinition(1, mode, seed)
		check(Validator.ValidateDefinition(definition), "Valid definition: " .. mode)
		local ok, puzzle = pcall(Generator.Generate, definition, seed)
		assert(ok, mode .. " seed=" .. seed .. ": " .. tostring(puzzle))
		check(#puzzle.letters == spec[1] and (mode == "Standard" and #puzzle.words >= 10 and #puzzle.words <= 12 or mode ~= "Standard" and #puzzle.words == spec[2]), "Mode row and word counts: " .. mode)
		local width = #puzzle.letters[1]
		check(width == spec[1], "Mode uses its fixed square dimensions")
		check(puzzle.gridWidth == width and definition.gridWidth == width, "Generation preserves declared column count")
		local rows = {}
		for _, row in ipairs(puzzle.letters) do
			check(#row == width, "Every row has the same column count")
			table.insert(rows, table.concat(row))
		end
		local signature = table.concat(rows)
		boards[signature], themes[puzzle.title] = true, true
		if not widths[width] then
			local repeated = Generator.Generate(Generator.BuildDefinition(1, mode, seed), seed)
			local repeatedRows = {}
			for _, row in ipairs(repeated.letters) do table.insert(repeatedRows, table.concat(row)) end
			check(signature == table.concat(repeatedRows) and table.concat(puzzle.words) == table.concat(repeated.words), "Same definition and seed reproduce board: " .. mode)
		end
		widths[width] = (widths[width] or 0) + 1
		for _, word in ipairs(puzzle.words) do
			local placed = puzzle.placedWordsByWord[word]
			check(placed and #placed.path == #word, "Every word is placed")
			for index, point in ipairs(placed.path) do
				check(point.row >= 1 and point.row <= spec[1] and point.column >= 1 and point.column <= width, "Canonical path stays inside both rectangular bounds")
				check(puzzle.letters[point.row][point.column] == word:sub(index, index), "Canonical path spells word")
			end
		end
	end
	local count, themeCount = 0, 0
	for _ in pairs(boards) do count += 1 end
	for _ in pairs(themes) do themeCount += 1 end
	check(count > 90 and themeCount > 1, "Repeated launches vary both grids and themes: " .. mode)
	if mode == "Standard" then
		check(widths[12] == 100 and widths[18] == nil, "Classic always uses a 12x12 square")
		print("CLASSIC_SHAPES square=" .. (widths[12] or 0) .. " rectangular=" .. (widths[18] or 0))
	end
end
-- Exercise words in the extra columns, independent member progress and hints.
local wideDefinition = {gridSize=4,gridWidth=6,maxGridSize=4,words={"PLANET"},directions={"E"}}
check(Validator.ValidateDefinition(wideDefinition), "A horizontal word can span beyond the row count")
for _, badWidth in ipairs({3, 6.5, 33, "invalid"}) do
	local invalid = table.clone(wideDefinition)
	invalid.gridWidth=badWidth
	check(not Validator.ValidateDefinition(invalid), "Invalid rectangle width is rejected")
end
local wide = Generator.Generate(wideDefinition, 51)
check(#wide.letters==4 and #wide.letters[1]==6, "Rectangular definition creates a real rectangular letter grid")
local wideRound = Queue.NewRound("wide", wide, {{userId=1},{userId=2}})
local widePath = wide.placedWordsByWord.PLANET.path
check(widePath[#widePath].column==6, "Canonical word reaches the last extra column")
check(wideRound:Snapshot(true).puzzle==wide, "Whole cohort receives one canonical rectangular puzzle")
check(wideRound:NextHint(2)=="PLANET" and wideRound:MarkHint(2,"PLANET"), "Hints use the rectangular canonical word")
check(wideRound:FindWord(1,"PLANET",widePath) and wideRound.members[2].count==0, "Wide words validate while other members solve independently")
local forged=table.clone(widePath)
forged[#forged]={row=widePath[#widePath].row,column=7}
check(not wideRound:FindWord(2,"PLANET",forged), "Extending a path beyond the rectangle cannot solve a word")
check(wideRound:FindWord(2,"PLANET",widePath), "Another cohort member can complete the same wide word")
local puzzle = Generator.Generate(Generator.BuildTutorialDefinition(77), 77)
local member = { userId = 1, name = "Test", displayName = "Test" }
local hardcore = Queue.NewRound("hard", puzzle, {member}, "Hardcore")
local path = puzzle.placedWordsByWord.CAT.path
check(not hardcore:FailSelection(1, path), "A valid word never causes Hardcore loss")
check(hardcore:FindWord(1, "CAT", path), "Hardcore accepts valid words")
check(not hardcore:FailSelection(1, path), "Repeated found word never causes Hardcore loss")
check(not hardcore:FailSelection(1, {}), "Empty gesture does not lose")
check(not hardcore:FailSelection(1, {{row=0,column=1},{row=1,column=1}}), "Off-board gesture does not lose")
check(not hardcore:FailSelection(1, {{row=1,column=1},{row=1,column=2},{row=2,column=2}}), "Bent payload does not lose")
check(not hardcore:FailSelection(1, {{row=1,column=1},{row=1,column=3}}), "Skipped cells do not lose")
check(hardcore:FindWord(1, "DOG", puzzle.placedWordsByWord.DOG.path), "Hardcore can win")
check(not hardcore:FailSelection(1, {{row=1,column=1},{row=2,column=1}}), "Completed Hardcore cannot become a loss")
-- Beginners receive a smaller Classic until ten completed puzzles.
local counts = {}
for solves = 0, 13 do
	for sample = 1, 100 do
		local seed = sample * 7919
		local definition = Generator.BuildClassicDefinition({{level=solves*20+1,solves=solves}}, seed, solves < 10 and solves or nil)
		local puzzle = Generator.Generate(definition,seed)
		local size = solves < 10 and 9 or 12
		check(puzzle.gridSize == size and puzzle.gridWidth == size and #puzzle.letters == size and #puzzle.letters[1] == size, "Classic graduates from 9x9 to 12x12 at ten solves")
		check((solves < 10 and #puzzle.words == 7 or solves >= 10 and #puzzle.words >= 10 and #puzzle.words <= 12) and Validator.ValidateDefinition(definition), "Classic word count matches saved progression")
		if solves < 10 then
			for _, word in ipairs(puzzle.words) do check(#word <= 6, "Beginner words remain short") end
			check(table.concat(definition.directions,",") == "E,S,SE", "Beginner words use forward directions")
		end
		counts[#puzzle.words] = true
		for _, word in ipairs(puzzle.words) do
			for index, cell in ipairs(puzzle.placedWordsByWord[word].path) do
				check(puzzle.letters[cell.row][cell.column] == word:sub(index,index), "Classic canonical paths spell their words")
			end
		end
	end
end
check(counts[10] and counts[11] and counts[12], "Seeded Classic word counts vary across 10, 11 and 12")
print("MODE_TESTS_PASSED=" .. checks)
