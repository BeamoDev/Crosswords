--!nocheck

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local InputController = {}
InputController.__index = InputController

local controllerSerial = 0

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
	self._connections = {}
	self._roundConnections = {}
	self._round = nil
	self._bound = false
	self._destroyed = false
	self._selectionActive = false
	self._selectionStart = nil
	self._selectionEnd = nil
	self._selection = {}
	self._activePointer = nil
	self._activePointerType = nil
	self._touchEndpointArmed = false
	self._touchEndpointCandidate = nil
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

function InputController:_getCellAtPosition(position)
	local resolver = self._round and self._round.getCellAtPosition
	if type(resolver) == "function" then
		return copyCell(resolver(position))
	end
	if self._ui and type(self._ui.GetCellAtPosition) == "function" then
		return copyCell(self._ui:GetCellAtPosition(position))
	end
	return nil
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
	local minimum, maximum = self:_getBoardBounds()
	if not minimum or not maximum then
		return false
	end
	return position.X >= minimum.X
		and position.X <= maximum.X
		and position.Y >= minimum.Y
		and position.Y <= maximum.Y
end

function InputController:_buildSelection(startCell, targetCell)
	startCell = copyCell(startCell)
	targetCell = copyCell(targetCell)
	if not startCell or not targetCell then
		return {}
	end

	local width, height = self:_dimensions()
	local rowDelta = targetCell.row - startCell.row
	local columnDelta = targetCell.column - startCell.column
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

	local selection = {}
	for index = 0, steps do
		local row = startCell.row + (rowStep * index)
		local column = startCell.column + (columnStep * index)
		local cell = self:_getCell(row, column) or { row = row, column = column }
		table.insert(selection, cell)
	end
	return selection
end

function InputController:_publishSelection()
	if self._ui and type(self._ui.UpdateSelection) == "function" then
		self._ui:UpdateSelection(self._selection)
	end
	self:_emit("onSelectionChanged", self._selection, {
		startCell = copyCell(self._selectionStart),
		endCell = copyCell(self._selectionEnd),
		inputType = inputLabel(self._activePointerType),
	})
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
	self:_emit("onCursorChanged", copyCell(cell))
end

function InputController:_setSelectionCursor(cell, inputType)
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
	if self._ui and type(self._ui.SetHoveredCell) == "function" then
		self._ui:SetHoveredCell(nil)
	end
	if not unchanged then
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
	self._selection = { cell }
	self._activePointer = inputObject
	self._activePointerType = inputType
	self:_setSelectionCursor(cell, inputType)
	self:_publishSelection()
	self:_emit("onSelectionStarted", copyCell(cell), inputLabel(inputType))
	return true
end

function InputController:_update(cell)
	if not self._selectionActive then
		return
	end
	cell = copyCell(cell)
	if not cell then
		return
	end
	if self._selectionEnd
		and self._selectionEnd.row == cell.row
		and self._selectionEnd.column == cell.column
	then
		return
	end

	self._selectionEnd = cell
	self._selection = self:_buildSelection(self._selectionStart, cell)
	self:_setSelectionCursor(self._selection[#self._selection] or cell, self._activePointerType)
	self:_publishSelection()
end

function InputController:_clearSelectionVisual()
	if self._ui and type(self._ui.UpdateSelection) == "function" then
		self._ui:UpdateSelection({})
	end
end

function InputController:_submit()
	if not self._selectionActive then
		return
	end

	local selection = self._selection
	local metadata = {
		startCell = copyCell(self._selectionStart),
		endCell = copyCell(self._selectionEnd),
		inputType = inputLabel(self._activePointerType),
	}
	local minimumLength = math.max(1, math.floor(tonumber(self._round and self._round.minSelectionLength) or 2))

	self._selectionActive = false
	self._selectionStart = nil
	self._selectionEnd = nil
	self._selection = {}
	self._activePointer = nil
	self._activePointerType = nil
	self._touchEndpointArmed = false
	self._touchEndpointCandidate = nil
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
	local hadSelection = self._selectionActive or #self._selection > 0
	local cancelledSelection = self._selection
	self._selectionActive = false
	self._selectionStart = nil
	self._selectionEnd = nil
	self._selection = {}
	self._activePointer = nil
	self._activePointerType = nil
	self._touchEndpointArmed = false
	self._touchEndpointCandidate = nil
	self:_clearSelectionVisual()
	if hadSelection then
		self:_emit("onCancel", tostring(reason or "cancelled"), cancelledSelection)
	end
end

function InputController:_pointerPosition(input)
	if not input or not input.Position then
		return nil
	end
	return Vector2.new(input.Position.X, input.Position.Y)
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
				startPosition = position,
				moved = false,
			}
		end
		return
	end
	if self._selectionActive or not self:_canInteract() then
		return
	end

	local position = self:_pointerPosition(input)
	local cell = position and self:_getCellAtPosition(position) or nil
	-- A GuiButton can mark the event processed; allow it only when the resolved
	-- target is an active board cell. Modal overlays disable UI input first.
	if gameProcessed and not cell then
		return
	end
	if cell then
		self:_begin(cell, input, inputType)
	end
end

function InputController:_handlePointerChanged(input)
	local position = self:_pointerPosition(input)
	if not position then
		return
	end
	if self._touchEndpointArmed then
		local candidate = self._touchEndpointCandidate
		if candidate and candidate.input == input and (position - candidate.startPosition).Magnitude >= 12 then
			candidate.moved = true
		end
		return
	end

	if not self._selectionActive then
		if input.UserInputType == Enum.UserInputType.MouseMovement and self:_canInteract() then
			local hovered = self:_getCellAtPosition(position)
			if hovered then
				self:_setCursor(hovered, false)
			elseif self._ui and type(self._ui.SetHoveredCell) == "function" then
				self._ui:SetHoveredCell(nil)
			end
		end
		return
	end

	local matchingMouse = self._activePointerType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseMovement
	local matchingTouch = self._activePointerType == Enum.UserInputType.Touch
		and input.UserInputType == Enum.UserInputType.Touch
		and (input == self._activePointer or self._activePointer == nil)
	if not matchingMouse and not matchingTouch then
		return
	end

	if not self:_insideBoard(position) then
		self:Cancel("pointer_left_board")
		return
	end
	local cell = self:_getCellAtPosition(position)
	if cell then
		self:_update(cell)
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
		self._touchEndpointCandidate = nil
		if candidate.moved then
			return
		end

		local position = self:_pointerPosition(input)
		local cell = position and self:_insideBoard(position) and self:_getCellAtPosition(position) or nil
		if not cell then
			return
		end
		self._touchEndpointArmed = false
		self._selectionEnd = copyCell(cell)
		self._selection = self:_buildSelection(self._selectionStart, cell)
		self:_setSelectionCursor(self._selection[#self._selection] or cell, self._activePointerType)
		self:_publishSelection()
		self:_submit()
		return
	end
	local mouseEnded = self._activePointerType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseButton1
	local touchEnded = self._activePointerType == Enum.UserInputType.Touch
		and input.UserInputType == Enum.UserInputType.Touch
		and (input == self._activePointer or self._activePointer == nil)
	if touchEnded then
		local minimumLength = math.max(1, math.floor(tonumber(self._round and self._round.minSelectionLength) or 2))
		if #self._selection < minimumLength then
			self._activePointer = nil
			self._touchEndpointArmed = true
			self._touchEndpointCandidate = nil
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
	table.insert(self._connections, self._userInputService.InputChanged:Connect(function(input)
		self:_handlePointerChanged(input)
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

	if self._ui and type(self._ui.SetInputEnabled) == "function" then
		self._ui:SetInputEnabled(self._round ~= nil and self._round.enabled ~= false)
	end
	if not self._round then
		return
	end

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
