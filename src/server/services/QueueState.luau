-- Pure state transitions. The server supplies time, roster and the canonical puzzle.
local QueueState = {}
local Engine = if script then require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("puzzle"):WaitForChild("PuzzleEngine")) else require("../../shared/puzzle/PuzzleEngine")
local Score = (if script then require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("config"):WaitForChild("ProgressionConfig")) else require("../../shared/config/ProgressionConfig")).Score
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

function QueueState.NewRound(id, puzzle, members, mode)
	local self = setmetatable({ id = id, mode = mode or "Standard", puzzle = puzzle, members = {}, order = {}, revision = 0 }, Round)
	for _, member in ipairs(members) do
		self.members[member.userId] = {
			userId = member.userId, name = member.name, displayName = member.displayName,
			isBot = member.isBot == true, thumbnailImage = member.thumbnailImage,
			foundWords = {}, foundOrder = {}, hintedWords = {}, hintUses = 0, count = 0, score = 0, xpEarned = 0, completed = false,
		}
		table.insert(self.order, member.userId)
	end
	return self
end

function Round:SetTimer(now, duration)
	self.timeLimit, self.expiresAt = duration, now + duration
end

function Round:Expire(now)
	local expired = {}
	if not self.expiresAt or now < self.expiresAt then return expired end
	for _, userId in ipairs(self.order) do
		local member = self.members[userId]
		if not member.completed and not member.failed then
			member.failed, member.timedOut, member.duration = true, true, self.timeLimit
			table.insert(expired, userId)
		end
	end
	if #expired > 0 then self.revision += 1 end
	return expired
end

function Round:FindWord(userId, word, answer)
	local member = self.members[userId]
	local expected = type(word) == "string" and self.puzzle.placedWordsByWord[word] or nil
	if not member or member.completed or member.failed or member.foundWords[word] or not expected
		then return false, false end
	if Engine.CheckAnswer(self.puzzle, word, answer) ~= true then return false, false end
	member.foundWords[word] = true
	member.foundOrder[word] = self.revision + 1
	member.score += Score.Word(expected.answer, member.hintedWords[word] == true)
	member.hintedWords[word] = nil
	member.count += 1
	member.completed = member.count == #self.puzzle.words
	self.revision += 1
	return true, member.completed
end

-- Only a deliberate full-length incorrect answer can end Hardcore.
function Round:FailSelection(userId, word, answer)
    local member = self.members[userId]
    if self.mode ~= "Hardcore" or not member or member.completed or member.failed or member.foundWords[word]
        or Engine.CheckAnswer(self.puzzle, word, answer) ~= false then return false end
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

function Round:Snapshot(includePuzzle, recipientId)
	local members = {}
	for _, userId in ipairs(self.order) do
		local member = self.members[userId]
		table.insert(members, {
			userId = userId, name = member.name, displayName = member.displayName,
			isBot = member.isBot, thumbnailImage = member.thumbnailImage,
			revealedAnswers = userId == recipientId and Engine.RevealedAnswers(self.puzzle, member.foundWords, member.hintedWords) or nil, foundWords = table.clone(member.foundWords), foundOrder = table.clone(member.foundOrder), hintedWords = table.clone(member.hintedWords),
			count = member.count, score = member.score, xpEarned = member.xpEarned, duration = member.duration, completed = member.completed, failed = member.failed == true, timedOut = member.timedOut == true,
		})
	end
	return { id = self.id, mode = self.mode, solo = self.solo == true, members = members, revision = self.revision,
		timeLimit = self.timeLimit, expiresAt = self.expiresAt,
		puzzle = includePuzzle and Engine.PublicPuzzle(self.puzzle) or nil }
end

return QueueState
