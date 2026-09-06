-- Pure state transitions. The server supplies time, roster and the canonical puzzle.
local QueueState = {}
QueueState.__index = QueueState

function QueueState.new(duration)
	return setmetatable({ duration = duration or 15, deadline = nil, members = {}, order = {}, revision = 0 }, QueueState)
end

function QueueState:Add(member, now)
	if self.members[member.userId] then return false end
	self.members[member.userId] = member
	table.insert(self.order, member.userId)
	self.deadline = self.deadline or (now + self.duration)
	self.revision += 1
	return true
end

function QueueState:Remove(userId)
	if not self.members[userId] then return false end
	self.members[userId] = nil
	table.remove(self.order, table.find(self.order, userId))
	if #self.order == 0 then self.deadline = nil end
	self.revision += 1
	return true
end

function QueueState:Snapshot()
	local members = {}
	for _, userId in ipairs(self.order) do table.insert(members, table.clone(self.members[userId])) end
	return { members = members, count = #members, deadline = self.deadline, revision = self.revision }
end

function QueueState:Drain(now)
	if not self.deadline or now < self.deadline then return nil end
	local members = self:Snapshot().members
	self.members, self.order, self.deadline = {}, {}, nil
	self.revision += 1
	return members
end

local Round = {}
Round.__index = Round

local function pathsMatch(expected, actual)
	if type(expected) ~= "table" or type(actual) ~= "table" or #expected ~= #actual then return false end
	local forward, backward = true, true
	for index, point in ipairs(actual) do
		if type(point) ~= "table" then return false end
		local a, b = expected[index], expected[#expected - index + 1]
		forward = forward and point.row == a.row and point.column == a.column
		backward = backward and point.row == b.row and point.column == b.column
	end
	return forward or backward
end

function QueueState.NewRound(id, puzzle, members, mode)
	local self = setmetatable({ id = id, mode = mode or "Standard", puzzle = puzzle, members = {}, order = {}, revision = 0 }, Round)
	for _, member in ipairs(members) do
		self.members[member.userId] = {
			userId = member.userId, name = member.name, displayName = member.displayName,
			isBot = member.isBot == true, thumbnailImage = member.thumbnailImage,
			foundWords = {}, foundOrder = {}, hintedWords = {}, hintUses = 0, count = 0, xpEarned = 0, completed = false,
		}
		table.insert(self.order, member.userId)
	end
	return self
end

function Round:FindWord(userId, word, path)
	local member = self.members[userId]
	local expected = type(word) == "string" and self.puzzle.placedWordsByWord[word] or nil
	if not member or member.completed or member.failed or member.foundWords[word] or not expected
		or not pathsMatch(expected.path, path) then return false, false end
	member.foundWords[word] = true
	member.foundOrder[word] = self.revision + 1
	member.hintedWords[word] = nil
	member.count += 1
	member.completed = member.count == #self.puzzle.words
	self.revision += 1
	return true, member.completed
end

-- Only an actual straight, in-bounds incorrect selection can lose Hardcore.
function Round:FailSelection(userId, path)
	local member = self.members[userId]
	if self.mode ~= "Hardcore" or not member or member.completed or member.failed
		or type(path) ~= "table" or #path < 2 or #path > 32 then return false end
	local dr, dc
	for index, point in ipairs(path) do
		if type(point) ~= "table" or type(point.row) ~= "number" or type(point.column) ~= "number"
			or point.row % 1 ~= 0 or point.column % 1 ~= 0
			or not self.puzzle.letters[point.row] or not self.puzzle.letters[point.row][point.column] then return false end
		if index > 1 then
			local r, c = point.row - path[index - 1].row, point.column - path[index - 1].column
			if math.abs(r) > 1 or math.abs(c) > 1 or (r == 0 and c == 0) then return false end
			if dr and (r ~= dr or c ~= dc) then return false end
			dr, dc = r, c
		end
	end
	for _, placed in pairs(self.puzzle.placedWordsByWord) do
		if pathsMatch(placed.path, path) then return false end
	end
	member.failed = true
	self.revision += 1
	return true
end

function Round:NextHint(userId)
	local member = self.members[userId]
	if not member or member.completed or member.failed then return nil end
	for _, word in ipairs(self.puzzle.words) do
		if not member.foundWords[word] and not member.hintedWords[word] then return word end
	end
	return nil
end

function Round:MarkHint(userId, word)
	local member = self.members[userId]
	if not member or member.completed or member.failed or not self.puzzle.placedWordsByWord[word] or member.foundWords[word]
		or member.hintedWords[word] then return false end
	member.hintedWords[word] = true
	member.hintUses += 1
	self.revision += 1
	return true
end

function Round:Remove(userId)
	if not self.members[userId] then return false end
	self.members[userId] = nil
	table.remove(self.order, table.find(self.order, userId))
	self.revision += 1
	return true
end

function Round:Snapshot(includePuzzle)
	local members = {}
	for _, userId in ipairs(self.order) do
		local member = self.members[userId]
		table.insert(members, {
			userId = userId, name = member.name, displayName = member.displayName,
			isBot = member.isBot, thumbnailImage = member.thumbnailImage,
			foundWords = table.clone(member.foundWords), foundOrder = table.clone(member.foundOrder), hintedWords = table.clone(member.hintedWords),
			count = member.count, xpEarned = member.xpEarned, duration = member.duration, completed = member.completed, failed = member.failed == true,
		})
	end
	return { id = self.id, mode = self.mode, solo = self.solo == true, members = members, revision = self.revision,
		puzzle = includePuzzle and self.puzzle or nil }
end

return QueueState
