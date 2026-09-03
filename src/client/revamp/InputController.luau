--!nocheck

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputController = {}
InputController.__index = InputController

local controllerSerial = 0
local POINTER_SAMPLE_INTERVAL = 1 / 60

local MOVE_BINDINGS = {
	Up = {
		delta = Vector2.new(0, -1),
		keys = { Enum.KeyCode.Up, Enum.KeyCode.W, Enum.KeyCode.DPadUp },
	},
	Down = {
		delta = Vector2.new(0, 1),
		keys = { Enum.KeyCode.Down, Enum.KeyCode.S, Enum.KeyCode.DPadDown },
	},
	Left = {
		delta = Vector2.new(-1, 0),
		keys = { Enum.KeyCode.Left, Enum.KeyCode.A, Enum.KeyCode.DPadLeft },
	},
	Right = {
		delta = Vector2.new(1, 0),
		keys = { Enum.KeyCode.Right, Enum.KeyCode.D, Enum.KeyCode.DPadRight },
	},
}

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function copyCell(cell)
	if type(cell) ~= "table" then
		return nil
	end
	local row = math.floor(tonumber(cell.row or cell.Row) or 0)
	local column = math.floor(tonumber(cell.column or cell.Column) or 0)
	if row < 1 or column < 1 then
		return nil
	end
	return {
		row = row,
		column = column,
		button = cell.button or cell.instance or cell.gui,
	}
end

local function sign(value)
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

local function isGamepadInput(inputType)
	return string.find(tostring(inputType), "Gamepad") ~= nil
end

local function isDirectPointer(inputType)
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local function inputLabel(inputType)
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseMovement then
		return "Mouse"
	elseif isGamepadInput(inputType) then
		return "Gamepad"
	end
	return "Keyboard"
end

function InputController.new(options)
	options = options or {}
	controllerSerial += 1
	local self = setmetatable({}, InputController)
	self._options = options
	self._player = options.player or Players.LocalPlayer
	self._ui = options.uiController
	self._userInputService = options.userInputService or UserInputService
	self._contextActionService = options.contextActionService or ContextActionService
	self._guiService = options.guiService or GuiService
	self._runService = options.runService or RunService
	self._connections = {}
	self._roundConnections = {}
	self._round = nil
	self._bound = false
	self._destroyed = false
	self._selectionActive = false
	self._selectionStart = nil
	self._selectionEnd = nil
	self._selectionLength = 0
	self._gridWidth = nil
	self._gridHeight = nil
	self._activePointer = nil
	self._activePointerType = nil
	self._touchEndpointArmed = false
	self._touchEndpointCandidate = nil
	self._pointerRenderConnection = nil
	self._pointerSampleAccumulator = 0
	self._lastPointerX = nil
	self._lastPointerY = nil
	self._pointerCellRow = nil
	self._pointerCellColumn = nil
	self._pointerCellMinX = nil
	self._pointerCellMinY = nil
	self._pointerCellMaxX = nil
	self._pointerCellMaxY = nil
	self._cursor = nil
	self._actionPrefix = "WordSearchRevampInput_" .. tostring(controllerSerial) .. "_"
	self._actionNames = {}
	return self
end

function InputController:_callback(name)
	local roundCallback = self._round and self._round[name]
	if type(roundCallback) == "function" then
		return roundCallback
	end

	local optionCallback = self._options[name]
	if type(optionCallback) == "function" then
		return optionCallback
	end

	if name == "onSubmit" then
		return (self._round and self._round.onSubmitSelection) or self._options.onSubmitSelection
	end
	return nil
end

function InputController:_emit(name, ...)
	local callback = self:_callback(name)
	if not callback then
		return nil
	end
	local ok, result = xpcall(callback, debug.traceback, ...)
	if not ok then
		warn(string.format("[WordSearch Input] %s callback failed: %s", name, tostring(result)))
		return nil
	end
	return result
end

function InputController:_isUiInputEnabled()
	if not self._ui then
		return true
	end
	if type(self._ui.IsInputEnabled) == "function" then
		return self._ui:IsInputEnabled()
	end
	return true
end

function InputController:_canInteract()
	if self._destroyed or not self._bound or type(self._round) ~= "table" then
		return false
	end
	if self._round.enabled == false or not self:_isUiInputEnabled() then
		return false
	end
	local callback = self:_callback("canInteract")
	if callback then
		local ok, allowed = pcall(callback)
		return ok and allowed ~= false
	end
	return true
end

function InputController:_dimensions()
	if self._gridWidth and self._gridHeight then
		return self._gridWidth, self._gridHeight
	end
	local round = self._round or {}
	local width = tonumber(round.width or round.gridWidth or round.columns)
	local height = tonumber(round.height or round.gridHeight or round.rows)
	if (not width or not height) and self._ui and type(self._ui.GetGridSize) == "function" then
		local uiWidth, uiHeight = self._ui:GetGridSize()
		width = width or uiWidth
		height = height or uiHeight
	end
	return math.max(1, math.floor(width or 1)), math.max(1, math.floor(height or 1))
end

function InputController:_getCell(row, column)
	if self._ui and type(self._ui.GetCell) == "function" then
		return copyCell(self._ui:GetCell(row, column))
	end
	local cells = self._round and self._round.cells
	return copyCell(cells and cells[row] and cells[row][column])
end

function InputController:_getCellCoordinatesAtPosition(position)
	local resolver = self._round and self._round.getCellAtPosition
	if type(resolver) == "function" then
		local cell = resolver(position)
		local row = type(cell) == "table" and math.floor(tonumber(cell.row or cell.Row) or 0) or 0
		local column = type(cell) == "table" and math.floor(tonumber(cell.column or cell.Column) or 0) or 0
		if row >= 1 and column >= 1 then return row, column end
		return nil, nil
	end
	if self._ui and type(self._ui.GetCellCoordinatesAtPosition) == "function" then
		return self._ui:GetCellCoordinatesAtPosition(position)
	end
	if self._ui and type(self._ui.GetCellAtPosition) == "function" then
		local cell = self._ui:GetCellAtPosition(position)
		local row = type(cell) == "table" and math.floor(tonumber(cell.row or cell.Row) or 0) or 0
		local column = type(cell) == "table" and math.floor(tonumber(cell.column or cell.Column) or 0) or 0
		if row >= 1 and column >= 1 then return row, column end
		return nil, nil
	end
	return nil, nil
end

function InputController:_getCellCoordinatesAtScreenPosition(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil, nil
	end
	-- Preserve custom board resolvers, but let the built-in UI stay entirely
	-- scalar on the high-frequency path so it creates no temporary vectors.
	local resolver = self._round and self._round.getCellAtPosition
	if type(resolver) == "function" then
		return self:_getCellCoordinatesAtPosition(Vector2.new(x, y))
	end
	if self._ui and type(self._ui.GetCellCoordinatesAtScreenPosition) == "function" then
		return self._ui:GetCellCoordinatesAtScreenPosition(x, y)
	end
	return self:_getCellCoordinatesAtPosition(Vector2.new(x, y))
end

function InputController:_getBoardBounds()
	local resolver = self._round and self._round.getBoardBounds
	local bounds
	if type(resolver) == "function" then
		bounds = resolver()
	elseif self._ui and type(self._ui.GetBoardBounds) == "function" then
		bounds = self._ui:GetBoardBounds()
	end
	if type(bounds) ~= "table" then
		return nil
	end

	local minimum = bounds.min or bounds.minimum or bounds.position
	local maximum = bounds.max or bounds.maximum
	if not maximum and minimum and bounds.size then
		maximum = minimum + bounds.size
	end
	if typeof(minimum) ~= "Vector2" or typeof(maximum) ~= "Vector2" then
		return nil
	end
	return minimum, maximum, bounds.gui
end

function InputController:_insideBoard(position)
	if self._ui and type(self._ui.IsPositionInsideBoard) == "function" then
		return self._ui:IsPositionInsideBoard(position)
	end
	local minimum, maximum = self:_getBoardBounds()
	if not minimum or not maximum then
		return false
	end
	return position.X >= minimum.X
		and position.X <= maximum.X
		and position.Y >= minimum.Y
		and position.Y <= maximum.Y
end

function InputController:_insideBoardCoordinates(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return false
	end
	if self._ui and type(self._ui.IsScreenPositionInsideBoard) == "function" then
		return self._ui:IsScreenPositionInsideBoard(x, y)
	end
	return self:_insideBoard(Vector2.new(x, y))
end

function InputController:_setBoardScrollingEnabled(enabled)
	if self._ui and type(self._ui.SetBoardScrollingEnabled) == "function" then
		self._ui:SetBoardScrollingEnabled(enabled == true)
	end
end

function InputController:_clearPointerCellCache()
	self._lastPointerX = nil
	self._lastPointerY = nil
	self._pointerCellRow = nil
	self._pointerCellColumn = nil
	self._pointerCellMinX = nil
	self._pointerCellMinY = nil
	self._pointerCellMaxX = nil
	self._pointerCellMaxY = nil
end

function InputController:_cachePointerCell(row, column)
	self._pointerCellRow = row
	self._pointerCellColumn = column
	self._pointerCellMinX = nil
	self._pointerCellMinY = nil
	self._pointerCellMaxX = nil
	self._pointerCellMaxY = nil
	if self._ui and type(self._ui.GetCellScreenBounds) == "function" then
		local minimumX, minimumY, maximumX, maximumY = self._ui:GetCellScreenBounds(row, column)
		self._pointerCellMinX = minimumX
		self._pointerCellMinY = minimumY
		self._pointerCellMaxX = maximumX
		self._pointerCellMaxY = maximumY
	end
end

function InputController:_selectionGeometry(startCell, targetRow, targetColumn)
	local width, height = self:_dimensions()
	local rowDelta = targetRow - startCell.row
	local columnDelta = targetColumn - startCell.column
	local absoluteRow = math.abs(rowDelta)
	local absoluteColumn = math.abs(columnDelta)
	local rowStep = sign(rowDelta)
	local columnStep = sign(columnDelta)

	if absoluteRow > absoluteColumn * 1.75 then
		columnStep = 0
	elseif absoluteColumn > absoluteRow * 1.75 then
		rowStep = 0
	end

	if self._round and self._round.allowDiagonal == false and rowStep ~= 0 and columnStep ~= 0 then
		if absoluteRow >= absoluteColumn then
			columnStep = 0
		else
			rowStep = 0
		end
	end

	local steps
	if rowStep == 0 then
		steps = absoluteColumn
	elseif columnStep == 0 then
		steps = absoluteRow
	else
		steps = math.floor(((absoluteRow + absoluteColumn) * 0.5) + 0.5)
	end

	local maxSteps = math.huge
	if rowStep > 0 then
		maxSteps = math.min(maxSteps, height - startCell.row)
	elseif rowStep < 0 then
		maxSteps = math.min(maxSteps, startCell.row - 1)
	end
	if columnStep > 0 then
		maxSteps = math.min(maxSteps, width - startCell.column)
	elseif columnStep < 0 then
		maxSteps = math.min(maxSteps, startCell.column - 1)
	end
	if maxSteps == math.huge then
		maxSteps = 0
	end
	steps = math.clamp(steps, 0, maxSteps)
	return startCell.row + (rowStep * steps), startCell.column + (columnStep * steps), steps + 1, rowStep, columnStep
end

function InputController:_buildSelection(startCell, targetCell)
	startCell = copyCell(startCell)
	targetCell = copyCell(targetCell)
	if not startCell or not targetCell then
		return {}
	end

	local _, _, length, rowStep, columnStep = self:_selectionGeometry(startCell, targetCell.row, targetCell.column)

	local selection = {}
	for index = 0, length - 1 do
		local row = startCell.row + (rowStep * index)
		local column = startCell.column + (columnStep * index)
		local cell = self:_getCell(row, column) or { row = row, column = column }
		table.insert(selection, cell)
	end
	return selection
end

function InputController:_publishSelection()
	if self._ui and type(self._ui.UpdateSelectionEndpoints) == "function" then
		self._ui:UpdateSelectionEndpoints(self._selectionStart, self._selectionEnd)
	elseif self._ui and type(self._ui.UpdateSelection) == "function" then
		self._ui:UpdateSelection({ self._selectionStart, self._selectionEnd })
	end
	if self:_callback("onSelectionChanged") then
		local selection = self:_buildSelection(self._selectionStart, self._selectionEnd)
		self:_emit("onSelectionChanged", selection, {
			startCell = copyCell(self._selectionStart),
			endCell = copyCell(self._selectionEnd),
			inputType = inputLabel(self._activePointerType),
		})
	end
end

function InputController:_setCursor(cell, focus)
	cell = copyCell(cell)
	if not cell then
		return
	end
	local unchanged = self._cursor
		and self._cursor.row == cell.row
		and self._cursor.column == cell.column
	self._cursor = cell
	if self._ui and type(self._ui.SetHoveredCell) == "function" then
		self._ui:SetHoveredCell(cell, focus == true)
	elseif focus and cell.button then
		self._guiService.SelectedObject = cell.button
	end
	if unchanged and not focus then
		return
	end
	if self:_callback("onCursorChanged") then
		self:_emit("onCursorChanged", copyCell(cell))
	end
end

function InputController:_setSelectionCursor(cell, inputType, clearPointerHover)
	if not isDirectPointer(inputType) then
		self:_setCursor(cell, isGamepadInput(inputType))
		return
	end

	cell = copyCell(cell)
	if not cell then
		return
	end
	local unchanged = self._cursor
		and self._cursor.row == cell.row
		and self._cursor.column == cell.column
	self._cursor = cell
	if clearPointerHover and self._ui and type(self._ui.SetHoveredCell) == "function" then
		self._ui:SetHoveredCell(nil)
	end
	if not unchanged and self:_callback("onCursorChanged") then
		self:_emit("onCursorChanged", copyCell(cell))
	end
end

function InputController:_begin(cell, inputObject, inputType)
	if not self:_canInteract() then
		return false
	end
	cell = copyCell(cell)
	if not cell then
		return false
	end

	self._selectionActive = true
	self._selectionStart = cell
	self._selectionEnd = cell
	self._selectionLength = 1
	self._activePointer = inputObject
	self._activePointerType = inputType
	if isDirectPointer(inputType) then
		self:_clearPointerCellCache()
		self:_cachePointerCell(cell.row, cell.column)
		self:_setBoardScrollingEnabled(false)
		self:_startPointerSampling()
	end
	self:_setSelectionCursor(cell, inputType, true)
	self:_publishSelection()
	if self:_callback("onSelectionStarted") then
		self:_emit("onSelectionStarted", copyCell(cell), inputLabel(inputType))
	end
	return true
end

function InputController:_update(cell)
	if type(cell) ~= "table" then
		return
	end
	self:_updateCoordinates(cell.row or cell.Row, cell.column or cell.Column)
end

function InputController:_updateCoordinates(row, column)
	if not self._selectionActive then
		return
	end
	row = math.floor(tonumber(row) or 0)
	column = math.floor(tonumber(column) or 0)
	local width, height = self:_dimensions()
	if row < 1 or row > height or column < 1 or column > width then
		return
	end
	local endRow, endColumn, length = self:_selectionGeometry(self._selectionStart, row, column)
	if self._selectionEnd
		and self._selectionEnd.row == endRow
		and self._selectionEnd.column == endColumn
	then
		return
	end

	local endpoint = self:_getCell(endRow, endColumn) or { row = endRow, column = endColumn }
	self._selectionEnd = endpoint
	self._selectionLength = length
	self:_setSelectionCursor(endpoint, self._activePointerType)
	self:_publishSelection()
end

function InputController:_clearSelectionVisual()
	if self._ui and type(self._ui.UpdateSelectionEndpoints) == "function" then
		self._ui:UpdateSelectionEndpoints(nil, nil)
	elseif self._ui and type(self._ui.UpdateSelection) == "function" then
		self._ui:UpdateSelection({})
	end
end

function InputController:_submit()
	if not self._selectionActive then
		return
	end

	local selection = self:_buildSelection(self._selectionStart, self._selectionEnd)
	local metadata = {
		startCell = copyCell(self._selectionStart),
		endCell = copyCell(self._selectionEnd),
		inputType = inputLabel(self._activePointerType),
	}
	local minimumLength = math.max(1, math.floor(tonumber(self._round and self._round.minSelectionLength) or 2))

	self._selectionActive = false
	self._selectionStart = nil
	self._selectionEnd = nil
	self._selectionLength = 0
	self._activePointer = nil
	self._activePointerType = nil
	self._touchEndpointArmed = false
	self._touchEndpointCandidate = nil
	self:_stopPointerSampling()
	self:_setBoardScrollingEnabled(true)
	if self._ui and type(self._ui.RememberSelection) == "function" then
		self._ui:RememberSelection(selection)
	end
	self:_clearSelectionVisual()

	if #selection < minimumLength then
		self:_emit("onCancel", "selection_too_short", selection)
		return
	end

	local result = self:_emit("onSubmit", selection, metadata)
	if type(result) == "table" and self._ui and type(self._ui.ApplySelectionResult) == "function" then
		self._ui:ApplySelectionResult(result)
	end
end

function InputController:Cancel(reason)
	local hadSelection = self._selectionActive or self._selectionStart ~= nil
	local hasCancelCallback = self:_callback("onCancel") ~= nil
	local cancelledSelection = if hadSelection and hasCancelCallback
		then self:_buildSelection(self._selectionStart, self._selectionEnd)
		else nil
	self._selectionActive = false
	self._selectionStart = nil
	self._selectionEnd = nil
	self._selectionLength = 0
	self._activePointer = nil
	self._activePointerType = nil
	self._touchEndpointArmed = false
	self._touchEndpointCandidate = nil
	self:_stopPointerSampling()
	self:_setBoardScrollingEnabled(true)
	self:_clearSelectionVisual()
	if hadSelection and hasCancelCallback then
		self:_emit("onCancel", tostring(reason or "cancelled"), cancelledSelection)
	end
end

function InputController:_pointerPosition(input)
	if not input or not input.Position then
		return nil
	end
	return Vector2.new(input.Position.X, input.Position.Y)
end

function InputController:_startPointerSampling()
	if self._pointerRenderConnection or self._destroyed then
		return
	end
	self._pointerSampleAccumulator = 0
	self._pointerRenderConnection = self._runService.RenderStepped:Connect(function(deltaTime)
		self._pointerSampleAccumulator += deltaTime
		if self._pointerSampleAccumulator + 0.0001 < POINTER_SAMPLE_INTERVAL then
			return
		end
		self._pointerSampleAccumulator %= POINTER_SAMPLE_INTERVAL
		local input
		local x
		local y
		if self._touchEndpointArmed then
			local candidate = self._touchEndpointCandidate
			input = candidate and candidate.input
			local position = input and input.Position
			x = position and position.X
			y = position and position.Y
		elseif self._selectionActive and self._activePointerType == Enum.UserInputType.MouseButton1 then
			input = self._activePointer
			local position = self._userInputService:GetMouseLocation()
			x = position.X
			y = position.Y
		elseif self._selectionActive and self._activePointerType == Enum.UserInputType.Touch then
			input = self._activePointer
			local position = input and input.Position
			x = position and position.X
			y = position and position.Y
		end
		if input and x and y then
			if x == self._lastPointerX and y == self._lastPointerY then
				return
			end
			self._lastPointerX = x
			self._lastPointerY = y
			self:_handlePointerChanged(input, x, y)
		end
	end)
end

function InputController:_stopPointerSampling()
	if self._pointerRenderConnection then
		self._pointerRenderConnection:Disconnect()
		self._pointerRenderConnection = nil
	end
	self._pointerSampleAccumulator = 0
	self:_clearPointerCellCache()
end

function InputController:_handlePointerBegan(input, gameProcessed)
	local inputType = input.UserInputType
	if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
		return
	end
	if self._touchEndpointArmed and inputType == Enum.UserInputType.Touch then
		if not self:_canInteract() then
			self:Cancel("board_closed")
			return
		end
		local position = self:_pointerPosition(input)
		if position and self:_insideBoard(position) then
			self._touchEndpointCandidate = {
				input = input,
				startX = position.X,
				startY = position.Y,
				moved = false,
			}
			self:_startPointerSampling()
		end
		return
	end
	if self._selectionActive or not self:_canInteract() then
		return
	end

	local position = self:_pointerPosition(input)
	local row, column
	if position then row, column = self:_getCellCoordinatesAtPosition(position) end
	local cell = row and self:_getCell(row, column) or nil
	-- A GuiButton can mark the event processed; allow it only when the resolved
	-- target is an active board cell. Modal overlays disable UI input first.
	if gameProcessed and not cell then
		return
	end
	if cell then
		self:_begin(cell, input, inputType)
	end
end

function InputController:_handlePointerChanged(input, sampledX, sampledY)
	local rawPosition = input and input.Position
	local x = sampledX or (rawPosition and rawPosition.X)
	local y = sampledY or (rawPosition and rawPosition.Y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	if self._touchEndpointArmed then
		local candidate = self._touchEndpointCandidate
		if candidate and candidate.input == input then
			local deltaX = x - candidate.startX
			local deltaY = y - candidate.startY
			if (deltaX * deltaX) + (deltaY * deltaY) >= 144 then
				candidate.moved = true
			end
		end
		return
	end

	if not self._selectionActive then
		return
	end

	local matchingMouse = self._activePointerType == Enum.UserInputType.MouseButton1
	local matchingTouch = self._activePointerType == Enum.UserInputType.Touch
		and input.UserInputType == Enum.UserInputType.Touch
		and (input == self._activePointer or self._activePointer == nil)
	if not matchingMouse and not matchingTouch then
		return
	end
	local minimumX = self._pointerCellMinX
	local minimumY = self._pointerCellMinY
	local maximumX = self._pointerCellMaxX
	local maximumY = self._pointerCellMaxY
	if minimumX and minimumY and maximumX and maximumY
		and x >= minimumX and x <= maximumX
		and y >= minimumY and y <= maximumY
	then
		return
	end

	local row, column = self:_getCellCoordinatesAtScreenPosition(x, y)
	if row then
		if row == self._pointerCellRow and column == self._pointerCellColumn then
			return
		end
		self:_cachePointerCell(row, column)
		self:_updateCoordinates(row, column)
	elseif not self:_insideBoardCoordinates(x, y) then
		self:Cancel("pointer_left_board")
	end
end

function InputController:_handlePointerEnded(input)
	if not self._selectionActive then
		return
	end
	if self._touchEndpointArmed then
		local candidate = self._touchEndpointCandidate
		if not candidate or candidate.input ~= input then
			return
		end
		local position = self:_pointerPosition(input)
		self._touchEndpointCandidate = nil
		self:_stopPointerSampling()
		if position and not candidate.moved then
			local deltaX = position.X - candidate.startX
			local deltaY = position.Y - candidate.startY
			candidate.moved = (deltaX * deltaX) + (deltaY * deltaY) >= 144
		end
		if candidate.moved then
			return
		end

		local row, column
		if position then row, column = self:_getCellCoordinatesAtPosition(position) end
		if not row then
			return
		end
		self._touchEndpointArmed = false
		self:_updateCoordinates(row, column)
		self:_submit()
		return
	end
	local mouseEnded = self._activePointerType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseButton1
	local touchEnded = self._activePointerType == Enum.UserInputType.Touch
		and input.UserInputType == Enum.UserInputType.Touch
		and (input == self._activePointer or self._activePointer == nil)
	if mouseEnded or touchEnded then
		local finalPosition = self:_pointerPosition(input)
		local row, column
		if finalPosition then row, column = self:_getCellCoordinatesAtPosition(finalPosition) end
		if row then
			self:_updateCoordinates(row, column)
		end
	end
	if touchEnded then
		local minimumLength = math.max(1, math.floor(tonumber(self._round and self._round.minSelectionLength) or 2))
		if self._selectionLength < minimumLength then
			self._activePointer = nil
			self._touchEndpointArmed = true
			self._touchEndpointCandidate = nil
			self:_stopPointerSampling()
			self:_setBoardScrollingEnabled(true)
			if self._ui and type(self._ui.ShowToast) == "function" then
				self._ui:ShowToast("Scroll if needed, then tap the ending letter.", "info", 2.2)
			end
			return
		end
	end
	if mouseEnded or touchEnded then
		self:_submit()
	end
end

function InputController:_selectedCell()
	if self._ui and type(self._ui.GetSelectedBoardCell) == "function" then
		local selected = copyCell(self._ui:GetSelectedBoardCell())
		if selected then
			return selected
		end
	end
	return copyCell(self._cursor) or self:_getCell(1, 1) or { row = 1, column = 1 }
end

function InputController:_isBoardFocused()
	if self._ui and type(self._ui.IsBoardFocused) == "function" then
		return self._ui:IsBoardFocused()
	end
	local selected = self._guiService.SelectedObject
	if not selected then
		return false
	end
	local row = tonumber(selected:GetAttribute("GridRow"))
	local column = tonumber(selected:GetAttribute("GridColumn"))
	local _, _, boardGui = self:_getBoardBounds()
	return row ~= nil
		and column ~= nil
		and row >= 1
		and column >= 1
		and boardGui ~= nil
		and selected:IsDescendantOf(boardGui)
end

function InputController:_moveCursor(delta, inputType)
	if not self:_canInteract() then
		return false
	end
	local width, height = self:_dimensions()
	local current = self:_selectedCell()
	local nextRow = math.clamp(current.row + delta.Y, 1, height)
	local nextColumn = math.clamp(current.column + delta.X, 1, width)
	if nextRow == current.row and nextColumn == current.column then
		return false
	end
	local nextCell = self:_getCell(nextRow, nextColumn)
	if not nextCell then
		return false
	end
	if self._selectionActive then
		self._activePointerType = inputType
		self:_update(nextCell)
	else
		self._activePointerType = inputType
		self:_setCursor(nextCell, true)
	end
	return true
end

function InputController:_toggleKeyboardSelection(inputType)
	if not self:_canInteract() then
		return
	end
	if self._selectionActive then
		self:_submit()
		return
	end
	self:_begin(self:_selectedCell(), nil, inputType)
end

function InputController:_bindAction(name, callback, ...)
	local actionName = self._actionPrefix .. name
	table.insert(self._actionNames, actionName)
	self._contextActionService:BindActionAtPriority(
		actionName,
		callback,
		false,
		Enum.ContextActionPriority.High.Value,
		...
	)
end

function InputController:Bind()
	if self._bound or self._destroyed then
		return self
	end
	self._bound = true

	table.insert(self._connections, self._userInputService.InputBegan:Connect(function(input, gameProcessed)
		self:_handlePointerBegan(input, gameProcessed)
	end))
	table.insert(self._connections, self._userInputService.InputEnded:Connect(function(input)
		self:_handlePointerEnded(input)
	end))
	table.insert(self._connections, self._userInputService.WindowFocusReleased:Connect(function()
		self:Cancel("window_focus_lost")
	end))
	if self._player then
		table.insert(self._connections, self._player.CharacterAdded:Connect(function()
			self:Cancel("character_respawned")
		end))
	end

	for directionName, binding in pairs(MOVE_BINDINGS) do
		self:_bindAction("Move" .. directionName, function(_, inputState, inputObject)
			if not self:_canInteract() or self._userInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			if not self._selectionActive and not self:_isBoardFocused() then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				local moved = self:_moveCursor(binding.delta, inputObject.UserInputType)
				if not moved and not self._selectionActive then
					return Enum.ContextActionResult.Pass
				end
			end
			return Enum.ContextActionResult.Sink
		end, table.unpack(binding.keys))
	end

	self:_bindAction("Select", function(_, inputState, inputObject)
		if not self:_canInteract() or self._userInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if not self._selectionActive and not self:_isBoardFocused() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			self:_toggleKeyboardSelection(inputObject.UserInputType)
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.Return, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	self:_bindAction("Cancel", function(_, inputState)
		if not self:_canInteract() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin and self._selectionActive then
			self:Cancel("user_cancelled")
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

	self:_bindAction("Hint", function(_, inputState)
		if not self:_canInteract() or self._selectionActive or self._userInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			self:_emit("onHintRequested")
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.H, Enum.KeyCode.ButtonX)

	self:_bindAction("Pause", function(_, inputState)
		if not self:_canInteract() or self._userInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			self:Cancel("pause_requested")
			self:_emit("onPauseRequested")
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.P, Enum.KeyCode.ButtonStart)

	return self
end

function InputController:SetRound(round)
	self:Cancel("round_changed")
	disconnectAll(self._roundConnections)
	self._round = if type(round) == "table" then round else nil
	self._ui = (self._round and self._round.uiController) or self._options.uiController or self._ui
	self._cursor = nil
	self._gridWidth = nil
	self._gridHeight = nil

	if self._ui and type(self._ui.SetInputEnabled) == "function" then
		self._ui:SetInputEnabled(self._round ~= nil and self._round.enabled ~= false)
	end
	if not self._round then
		return
	end
	self._gridWidth, self._gridHeight = self:_dimensions()

	local visibilityRoot = self._round.visibilityRoot
	if not visibilityRoot and self._ui and type(self._ui.GetGameRoot) == "function" then
		visibilityRoot = self._ui:GetGameRoot()
	end
	if visibilityRoot and visibilityRoot:IsA("GuiObject") then
		table.insert(self._roundConnections, visibilityRoot:GetPropertyChangedSignal("Visible"):Connect(function()
			if not visibilityRoot.Visible then
				self:Cancel("board_closed")
			end
		end))
		table.insert(self._roundConnections, visibilityRoot.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				self:Cancel("board_destroyed")
			end
		end))
	end
	if self._ui and type(self._ui.GetInputEnabledChangedSignal) == "function" then
		table.insert(self._roundConnections, self._ui:GetInputEnabledChangedSignal():Connect(function(enabled)
			if enabled ~= true then
				self:Cancel("board_closed")
			end
		end))
	end

	local selected = self:_selectedCell()
	if selected then
		self:_setCursor(selected, false)
	end
end

function InputController:Destroy()
	if self._destroyed then
		return
	end
	self:Cancel("destroyed")
	self._destroyed = true
	disconnectAll(self._roundConnections)
	disconnectAll(self._connections)
	for _, actionName in ipairs(self._actionNames) do
		self._contextActionService:UnbindAction(actionName)
	end
	table.clear(self._actionNames)
	self._round = nil
	self._ui = nil
	self._bound = false
end

return InputController
