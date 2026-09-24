-- Pure local editing state. Server progress is the only source of solved entries.
local Input = {}
Input.__index = Input
local function key(cell) return cell.row .. ":" .. cell.column end
function Input.new(puzzle)
    local self = setmetatable({puzzle=puzzle, cells={}, draft={}, locked={}, found={}, index=1}, Input)
    for _, id in ipairs(puzzle.words) do
        for _, cell in ipairs(puzzle.placedWordsByWord[id].path) do
            local k = key(cell)
            self.cells[k] = self.cells[k] or {}
            table.insert(self.cells[k], id)
        end
    end
    self.selected = puzzle.words[1]
    return self
end
function Input:Entry() return self.puzzle.placedWordsByWord[self.selected] end
function Input:Cursor() return self:Entry().path[self.index] end
function Input:Select(id, cell)
    local entry = self.puzzle.placedWordsByWord[id]
    if not entry then return false end
    self.selected, self.index = id, 1
    for i, point in ipairs(entry.path) do
        if cell and key(point) == key(cell) then self.index = i return true end
        if not cell and not self.locked[key(point)] and (self.draft[key(point)] or "") == "" then self.index = i return true end
    end
    return true
end
function Input:SelectCell(cell, toggle)
    local ids = self.cells[key(cell)]
    if not ids then return false end
    local id = table.find(ids, self.selected) and self.selected or ids[1]
    if toggle and #ids == 2 and key(self:Cursor()) == key(cell) then id = ids[1] == id and ids[2] or ids[1] end
    return self:Select(id, cell)
end
function Input:Next(delta)
    local index = table.find(self.puzzle.words, self.selected) or 1
    for offset = 1, #self.puzzle.words do
        local id = self.puzzle.words[(index - 1 + offset * delta) % #self.puzzle.words + 1]
        if not self.found[id] then self:Select(id) return end
    end
end
function Input:Move(dr, dc)
    local cell = self:Cursor()
    local direction = dc ~= 0 and "Across" or "Down"
    for _, id in ipairs(self.cells[key(cell)]) do
        if self.puzzle.placedWordsByWord[id].direction == direction and id ~= self.selected then
            self:Select(id, cell) return
        end
    end
    for distance = 1, math.max(self.puzzle.gridSize, self.puzzle.gridWidth) do
        local target = {row=cell.row + dr * distance, column=cell.column + dc * distance}
        if self:SelectCell(target, false) then return end
    end
end
function Input:Type(letter)
    if type(letter) ~= "string" or not letter:match("^[A-Za-z]$") or self.found[self.selected] then return false end
    local path = self:Entry().path
    local index = self.index
    while index <= #path and self.locked[key(path[index])] do index += 1 end
    if index > #path then return false end
    self.draft[key(path[index])] = string.upper(letter)
    self.index = math.min(#path, index + 1)
    while self.index < #path and self.locked[key(path[self.index])] do self.index += 1 end
    return true
end
function Input:Backspace()
    if self.found[self.selected] then return false end
    local path, index = self:Entry().path, self.index
    if (self.draft[key(path[index])] or "") == "" or self.locked[key(path[index])] then index -= 1 end
    while index >= 1 and self.locked[key(path[index])] do index -= 1 end
    if index < 1 then return false end
    self.draft[key(path[index])], self.index = nil, index
    return true
end
-- Native text input edits a whole entry; crossing locks always win.
function Input:SetAnswer(text)
    if type(text) ~= "string" or self.found[self.selected] then return end
    text = string.upper(text:gsub("[^A-Za-z]", "")):sub(1, self:Entry().length)
    for i, cell in ipairs(self:Entry().path) do
        local k = key(cell)
        if not self.locked[k] then
            local letter = text:sub(i,i)
            self.draft[k] = letter ~= "" and letter or nil
        end
    end
    self.index = math.clamp(#text + 1, 1, self:Entry().length)
end
function Input:Answer()
    local letters = {}
    for _, cell in ipairs(self:Entry().path) do
        local letter = self.locked[key(cell)] or self.draft[key(cell)]
        if not letter or letter == "" then return nil end
        table.insert(letters, letter)
    end
    return table.concat(letters)
end
function Input:Apply(found, revealed)
    self.found, self.locked = table.clone(found), {}
    for id, answer in pairs(revealed or {}) do
        local entry = self.puzzle.placedWordsByWord[id]
        if entry and type(answer) == "string" and #answer == entry.length then
            for i, cell in ipairs(entry.path) do
                self.locked[key(cell)] = answer:sub(i, i)
                self.draft[key(cell)] = answer:sub(i, i)
            end
        end
    end
end
Input.Key = key
return Input
