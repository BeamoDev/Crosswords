local module = {}

function module.new(config)
	local ui = config.ui
	local state = config.state
	local colors = config.colors
	local runtimeHelpers = config.runtimeHelpers
	local timedProduct = config.timedProduct
	local uiEffects = config.uiEffects
	local ensureScaleController = config.ensureScaleController
	local bindButtonHoverSound = config.bindButtonHoverSound
	local tween = config.tween
	local findButtonLike = config.findButtonLike
	local api = {}

	local function setBaseColor(button, color)
		button:SetAttribute("BaseColor", color)
		uiEffects.SetBaseColor(button, color)
	end

	local function getBaseColor(button)
		return button:GetAttribute("BaseColor") or colors.button
	end

	function api.setBaseColor(button, color)
		if not button then
			return
		end

		setBaseColor(button, color)
	end

	function api.setEnabled(button, enabled, color)
		if not button then
			return
		end

		if color then
			setBaseColor(button, color)
		end

		button.Active = enabled
		button.Selectable = enabled
		button:SetAttribute("ButtonEnabled", enabled)

		tween(button, {
			BackgroundColor3 = enabled and getBaseColor(button) or colors.board,
			BackgroundTransparency = enabled and 0 or 0.2,
			TextColor3 = enabled and colors.text or colors.textMuted,
		}, 0.14)

		if button:FindFirstChild("ScaleController") and not enabled then
			tween(button.ScaleController, { Scale = 1 }, 0.08)
		end
	end

	function api.setInteractivityOnly(button, enabled)
		if not button then
			return
		end

		button.Active = enabled
		button.Selectable = enabled
		button:SetAttribute("ButtonEnabled", enabled)

		tween(button, {
			BackgroundTransparency = enabled and 0 or 0.2,
		}, 0.14)

		if button:FindFirstChild("ScaleController") and not enabled then
			tween(button.ScaleController, { Scale = 1 }, 0.08)
		end
	end

	function api.setClickableOnly(button, enabled)
		if not button then
			return
		end

		button.Active = enabled
		button.Selectable = enabled
		button:SetAttribute("ButtonEnabled", enabled)
	end

	function api.prepare(button, color, hoverBrightness)
		if not button or not button:IsA("GuiButton") then
			return
		end

		ensureScaleController(button)
		setBaseColor(button, color or button.BackgroundColor3)
		bindButtonHoverSound(button)
		uiEffects.Init(button, {
			baseColor = color or button.BackgroundColor3,
			hoverScale = 1.04,
			pressScale = 0.96,
			hoverBrightness = hoverBrightness == nil and 0.08 or hoverBrightness,
		})
	end

	function api.wireActions()
		local function bindHintControl(button)
			if not button or not button:IsA("GuiButton") or button:GetAttribute("WordSearchBound") then
				return
			end

			button:SetAttribute("WordSearchBound", true)
			button.Activated:Connect(function()
				if runtimeHelpers.showHint then
					runtimeHelpers.showHint()
				end
			end)
		end

		bindHintControl(ui.hintButton)
		if ui.hintRoot and ui.hintRoot ~= ui.hintButton then
			bindHintControl(findButtonLike(ui.hintRoot))
			if not ui.hintRoot:IsA("GuiButton") and not ui.hintRoot:GetAttribute("WordSearchHintFrameBound") then
				ui.hintRoot:SetAttribute("WordSearchHintFrameBound", true)
				ui.hintRoot.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						if runtimeHelpers.showHint then
							runtimeHelpers.showHint()
						end
					end
				end)
			end
		end

		if ui.menuModeNextButton and not ui.menuModeNextButton:GetAttribute("WordSearchBound") then
			ui.menuModeNextButton:SetAttribute("WordSearchBound", true)
			ui.menuModeNextButton.Activated:Connect(function()
				if config.isInteractionBlocked() then
					return
				end

				state.menuModeIndex = (state.menuModeIndex % #config.modeOrder) + 1
				config.refreshModeButtons()
			end)
		end

		if ui.menuModePrevButton and not ui.menuModePrevButton:GetAttribute("WordSearchBound") then
			ui.menuModePrevButton:SetAttribute("WordSearchBound", true)
			ui.menuModePrevButton.Activated:Connect(function()
				if config.isInteractionBlocked() then
					return
				end

				state.menuModeIndex = ((state.menuModeIndex - 2) % #config.modeOrder) + 1
				config.refreshModeButtons()
			end)
		end

		if ui.menuPlayButton and not ui.menuPlayButton:GetAttribute("WordSearchBound") then
			ui.menuPlayButton:SetAttribute("WordSearchBound", true)
			ui.menuPlayButton.Activated:Connect(function()
				config.handleMenuPlayPressed()
			end)
		end

		if ui.menuDuelButton and not ui.menuDuelButton:GetAttribute("WordSearchBound") then
			ui.menuDuelButton:SetAttribute("WordSearchBound", true)
			ui.menuDuelButton.Activated:Connect(function()
				if config.isInteractionBlocked() or not state.duelController then
					return
				end

				config.playSound("OpenFrame")
				state.duelController:showLobby()
			end)
		end

		if ui.exitButton and not ui.exitButton:GetAttribute("WordSearchBound") then
			ui.exitButton:SetAttribute("WordSearchBound", true)
			ui.exitButton.Activated:Connect(function()
				if config.isGameplayInteractionBlocked() then
					return
				end

				config.playSound("Button2")
				config.exitCurrentMode()
			end)
		end

		if ui.nextButton and not ui.nextButton:GetAttribute("WordSearchBound") then
			ui.nextButton:SetAttribute("WordSearchBound", true)
			ui.nextButton.Activated:Connect(function()
				if config.isGameplayInteractionBlocked() or not state.gameViewActive then
					return
				end

				config.playSound("Button2")
				config.transitionToPuzzle(
					config.chooseModeLevelIndex(state.mode),
					config.nextSeed(state.sessionScore + state.puzzlesCleared + 1)
				)
			end)
		end

		if ui.timeBoostButton and not ui.timeBoostButton:GetAttribute("WordSearchBound") then
			ui.timeBoostButton:SetAttribute("WordSearchBound", true)
			ui.timeBoostButton.Activated:Connect(function()
				if config.isGameplayInteractionBlocked() or not state.gameViewActive then
					print(string.format(
						"[WordSearch MoreTime] pressed blocked interactionLocked=%s gameViewActive=%s",
						tostring(config.isGameplayInteractionBlocked()),
						tostring(state.gameViewActive == true)
					))
					return
				end

				config.playSound("Button2")
				local timeBoostCount = math.max(
					0,
					math.floor(tonumber(timedProduct.getCount and timedProduct.getCount("time_boost") or 0) or 0)
				)
				print(string.format(
					"[WordSearch MoreTime] pressed count=%d used=%s pendingKind=%s",
					timeBoostCount,
					tostring(state.timeBoostUsed == true),
					tostring(state.pendingTimedProductKind or "nil")
				))
				if timedProduct.getCount("time_boost") > 0 then
					timedProduct.tryUse("time_boost", false)
				else
					timedProduct.promptPurchase("time_boost")
				end
			end)
		end

		if ui.freezeTimeButton and not ui.freezeTimeButton:GetAttribute("WordSearchBound") then
			ui.freezeTimeButton:SetAttribute("WordSearchBound", true)
			ui.freezeTimeButton.Activated:Connect(function()
				if config.isGameplayInteractionBlocked() or not state.gameViewActive then
					return
				end

				config.playSound("Button2")
				if timedProduct.getCount("freeze_time") > 0 then
					timedProduct.tryUse("freeze_time", false)
				else
					timedProduct.promptPurchase("freeze_time")
				end
			end)
		end

		if ui.summaryButton and not ui.summaryButton:GetAttribute("WordSearchBound") then
			ui.summaryButton:SetAttribute("WordSearchBound", true)
			ui.summaryButton.Activated:Connect(function()
				if ui.summaryButton:GetAttribute("ButtonEnabled") == false
					or state.summaryGiftClaimPending == true
					or state.summaryGiftSequenceActive == true then
					return
				end
				config.playSound("Button2")
				if state.summaryAction then
					state.summaryAction()
				end
			end)
		end

		if ui.summaryGiftButton and not ui.summaryGiftButton:GetAttribute("WordSearchBound") then
			ui.summaryGiftButton:SetAttribute("WordSearchBound", true)
			ui.summaryGiftButton.Activated:Connect(function()
				if config.claimSummaryGift then
					config.playSound("Button2")
					config.claimSummaryGift()
				end
			end)
		end
	end

	return api
end

return module
