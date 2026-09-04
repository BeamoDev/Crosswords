local module = {}

local function getTransitionTween(layout)
	return layout.ViewTweenSlide or layout.ViewTweenIn or layout.ViewTweenOut
end

local function getStackedTravelOffset(layout, movingFrame, referenceFrame)
	local movingHeight = movingFrame and movingFrame.AbsoluteSize.Y or 0
	local referenceHeight = referenceFrame and referenceFrame.AbsoluteSize.Y or 0
	local travelHeight = math.max(movingHeight, referenceHeight, 0)
	local overlapPixels = math.max(0, math.floor(tonumber(layout.ViewStackedOverlapPixels) or 0))
	if travelHeight <= 0 then
		travelHeight = overlapPixels
	end

	return math.max(0, travelHeight - overlapPixels)
end

local function getStackedPosition(basePosition, layout, movingFrame, referenceFrame, direction)
	local offset = getStackedTravelOffset(layout, movingFrame, referenceFrame) * direction
	return UDim2.new(
		basePosition.X.Scale,
		basePosition.X.Offset,
		basePosition.Y.Scale,
		basePosition.Y.Offset + offset
	)
end

function module.showMenuView(context, animate, onComplete)
	local ui = context.ui
	local state = context.state
	local layout = context.layout
	local tween = context.tween
	local refreshUiBindings = context.refreshUiBindings
	local updateHud = context.updateHud

	if not ui.menu then
		state.gameViewActive = false
		refreshUiBindings()
		if onComplete then
			onComplete()
		end
		return
	end

	local function finish()
		state.viewTransitionBusy = false
		state.gameViewActive = false
		if ui.game then
			ui.game.Visible = false
			ui.game.Position = layout.ViewGameHiddenPosition
			ui.game.Size = ui.gameOpenSize or ui.game.Size
		end
		ui.menu.Visible = true
		ui.menu.Position = ui.menuOpenPosition or layout.ViewCenterPosition
		ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		refreshUiBindings()
		updateHud()
		if onComplete then
			onComplete()
		end
	end

	if not animate or not ui.game then
		ui.menu.Visible = true
		ui.menu.Position = ui.menuOpenPosition or layout.ViewCenterPosition
		ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		if ui.game then
			ui.game.Visible = false
			ui.game.Position = layout.ViewGameHiddenPosition
			ui.game.Size = ui.gameOpenSize or ui.game.Size
		end
		finish()
		return
	end

	local transitionTween = getTransitionTween(layout)
	local menuOpenPosition = ui.menuOpenPosition or layout.ViewCenterPosition
	local menuEntryPosition = getStackedPosition(menuOpenPosition, layout, ui.menu, ui.game, 1)
	local gameExitPosition = getStackedPosition(menuOpenPosition, layout, ui.game, ui.menu, -1)

	state.viewTransitionBusy = true
	state.gameViewActive = false
	ui.menu.Visible = true
	ui.menu.Position = menuEntryPosition
	ui.menu.Size = ui.menuOpenSize or ui.menu.Size
	ui.game.Visible = true
	ui.game.Position = ui.gameOpenPosition or layout.ViewCenterPosition
	ui.game.Size = ui.gameOpenSize or ui.game.Size
	refreshUiBindings()

	tween(ui.game, { Position = gameExitPosition }, transitionTween)
	tween(ui.menu, { Position = menuOpenPosition }, transitionTween)
	task.delay(transitionTween.Time + 0.02, function()
		if not state.viewTransitionBusy then
			return
		end

		if ui.game then
			ui.game.Visible = false
			ui.game.Position = layout.ViewGameHiddenPosition
		end
		ui.menu.Visible = true
		ui.menu.Position = menuOpenPosition
		ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		refreshUiBindings()
		finish()
	end)
end

function module.showGameView(context, animate, onComplete)
	local ui = context.ui
	local state = context.state
	local layout = context.layout
	local tween = context.tween
	local refreshUiBindings = context.refreshUiBindings
	local updateHud = context.updateHud

	if not ui.game then
		state.gameViewActive = true
		refreshUiBindings()
		if onComplete then
			onComplete()
		end
		return
	end

	local function finish()
		state.viewTransitionBusy = false
		state.gameViewActive = true
		if ui.menu then
			ui.menu.Visible = false
			ui.menu.Position = layout.ViewMenuHiddenPosition
			ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		end
		ui.game.Visible = true
		ui.game.Position = ui.gameOpenPosition or layout.ViewCenterPosition
		ui.game.Size = ui.gameOpenSize or ui.game.Size
		refreshUiBindings()
		updateHud()
		if onComplete then
			onComplete()
		end
	end

	if not animate or not ui.menu then
		if ui.menu then
			ui.menu.Visible = false
			ui.menu.Position = layout.ViewMenuHiddenPosition
			ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		end
		ui.game.Visible = true
		ui.game.Position = ui.gameOpenPosition or layout.ViewCenterPosition
		ui.game.Size = ui.gameOpenSize or ui.game.Size
		finish()
		return
	end

	local transitionTween = getTransitionTween(layout)
	local menuOpenPosition = ui.menuOpenPosition or layout.ViewCenterPosition
	local gameOpenPosition = ui.gameOpenPosition or layout.ViewCenterPosition
	local menuExitPosition = getStackedPosition(gameOpenPosition, layout, ui.menu, ui.game, 1)
	local gameEntryPosition = getStackedPosition(gameOpenPosition, layout, ui.game, ui.menu, -1)

	state.viewTransitionBusy = true
	ui.menu.Visible = true
	ui.menu.Position = menuOpenPosition
	ui.menu.Size = ui.menuOpenSize or ui.menu.Size
	ui.game.Visible = true
	ui.game.Position = gameEntryPosition
	ui.game.Size = ui.gameOpenSize or ui.game.Size
	refreshUiBindings()

	tween(ui.menu, { Position = menuExitPosition }, transitionTween)
	tween(ui.game, { Position = gameOpenPosition }, transitionTween)
	task.delay(transitionTween.Time + 0.02, function()
		if not state.viewTransitionBusy then
			return
		end

		if ui.menu then
			ui.menu.Visible = false
			ui.menu.Position = layout.ViewMenuHiddenPosition
		end
		ui.game.Visible = true
		ui.game.Position = gameOpenPosition
		ui.game.Size = ui.gameOpenSize or ui.game.Size
		refreshUiBindings()
		finish()
	end)
end

return module
