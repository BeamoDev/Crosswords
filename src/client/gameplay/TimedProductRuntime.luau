local module = {}

function module.create(env)
	local runtime = {}

	runtime.specs = {
		time_boost = {
			displayName = "+2 Minutes",
			productIdKey = "TimeBoost",
			availableField = "availableTimeBoosts",
			usedField = "timeBoostUsed",
			apply = function()
				local state = env.state
				if state.gameEnded or not state.gameViewActive or not env.getModeConfig().startTime or state.timeBoostUsed then
					print(string.format(
						"[WordSearch MoreTime] apply blocked gameEnded=%s gameViewActive=%s modeHasTimer=%s timeBoostUsed=%s",
						tostring(state.gameEnded == true),
						tostring(state.gameViewActive == true),
						tostring(env.getModeConfig().startTime ~= nil),
						tostring(state.timeBoostUsed == true)
					))
					return false
				end

				local extraTime = env.RuntimeHelpers.getExtraTimeAmount()
				state.timeBoostUsed = true
				state.timedDurationSeconds = math.max(
					1,
					math.floor((state.timedDurationSeconds or state.timedOriginalDurationSeconds or 1) + extraTime)
				)
				if state.timedRunActive and state.timedDeadline > 0 then
					state.timedDeadline += extraTime
					state.timedSecondsLeft = math.max(1, math.ceil(math.max(0, state.timedDeadline - tick())))
				else
					state.timedSecondsLeft = math.max(1, math.floor((state.timedSecondsLeft or 0) + extraTime))
				end
				state.lastTimerWholeSecond = math.max(1, math.ceil(state.timedSecondsLeft))
				print(string.format(
					"[WordSearch MoreTime] apply success extra=%d timedDuration=%d timedSecondsLeft=%d deadlineActive=%s",
					math.max(0, math.floor(tonumber(extraTime) or 0)),
					math.max(0, math.floor(tonumber(state.timedDurationSeconds) or 0)),
					math.max(0, math.floor(tonumber(state.timedSecondsLeft) or 0)),
					tostring(state.timedRunActive == true and state.timedDeadline > 0)
				))
				env.updateHud()
				env.syncBoardProgress()
				env.showDesktopAlert(nil, string.format("+%s", env.RuntimeHelpers.formatTime(extraTime)), "success", {
					duration = 1.8,
				})
				return true
			end,
		},
		freeze_time = {
			displayName = "Freeze Timer",
			productIdKey = "FreezeTime",
			availableField = "availableFreezeTime",
			usedField = "freezeTimeUsed",
			apply = function()
				local state = env.state
				if state.gameEnded or not state.gameViewActive or not env.getModeConfig().startTime or state.freezeTimeUsed then
					return false
				end

				local freezeDuration = env.RuntimeHelpers.getFreezeDuration()
				state.freezeTimeUsed = true
				state.timedSecondsLeft = math.max(1, math.ceil(env.RuntimeHelpers.getTimedSecondsRemaining()))
				state.timedRunActive = false
				state.timedStartTick = 0
				state.timedDeadline = 0
				state.freezeTimeEndsAt = tick() + freezeDuration
				state.lastTimerWholeSecond = math.max(1, math.ceil(state.timedSecondsLeft))
				env.updateHud()
				env.syncBoardProgress()
				env.showDesktopAlert(nil, string.format("Frozen for %ds", freezeDuration), "success", {
					duration = 1.8,
				})
				return true
			end,
		},
	}

	function runtime.getSpec(kind)
		return runtime.specs[tostring(kind or "")]
	end

	function runtime.getCount(kind)
		local spec = runtime.getSpec(kind)
		if not spec then
			return 0
		end

		return math.max(0, math.floor(tonumber(env.state[spec.availableField]) or 0))
	end

	function runtime.getProductId(kind)
		local spec = runtime.getSpec(kind)
		local timedProducts = env.Dependencies.MetaConfig.TIMED_PRODUCT_IDS or {}
		return spec and tonumber(timedProducts[spec.productIdKey]) or nil
	end

	function runtime.getDisplayName(kind)
		local spec = runtime.getSpec(kind)
		return spec and spec.displayName or "Timed Product"
	end

	function runtime.canUseNow(kind)
		local spec = runtime.getSpec(kind)
		local state = env.state
		if not spec then
			return false
		end

		if state.gameEnded or not state.gameViewActive or not state.currentPuzzle or state.duelActive or not env.getModeConfig().startTime then
			return false
		end

		return not state[spec.usedField]
	end

	function runtime.promptPurchase(kind)
		local productId = runtime.getProductId(kind)
		if type(productId) ~= "number" then
			print(string.format("[WordSearch MoreTime] prompt missing_product kind=%s", tostring(kind)))
			env.showDesktopAlert(nil, "Timed product is not configured.", "error", {
				duration = 2.2,
			})
			return
		end

		if env.state.pendingTimedProductKind ~= nil then
			print(string.format(
				"[WordSearch MoreTime] prompt skipped pendingKind=%s requested=%s",
				tostring(env.state.pendingTimedProductKind),
				tostring(kind)
			))
			return
		end

		print(string.format(
			"[WordSearch MoreTime] prompt purchase kind=%s productId=%s",
			tostring(kind),
			tostring(productId)
		))
		env.state.pendingTimedProductKind = kind
		env.refreshActionButtons()
		local ok = pcall(function()
			env.MarketplaceService:PromptProductPurchase(env.player, productId)
		end)
		if not ok then
			env.state.pendingTimedProductKind = nil
			env.refreshActionButtons()
			env.showDesktopAlert(nil, "Could not open the purchase prompt.", "error", {
				duration = 2.2,
			})
		end
	end

	function runtime.tryUse(kind, fromPurchase)
		local spec = runtime.getSpec(kind)
		if not spec then
			print(string.format("[WordSearch MoreTime] tryUse invalid_kind kind=%s", tostring(kind)))
			return false
		end

		if not runtime.canUseNow(kind) then
			print(string.format(
				"[WordSearch MoreTime] tryUse blocked kind=%s fromPurchase=%s gameEnded=%s gameViewActive=%s hasPuzzle=%s duelActive=%s modeHasTimer=%s alreadyUsed=%s",
				tostring(kind),
				tostring(fromPurchase == true),
				tostring(env.state.gameEnded == true),
				tostring(env.state.gameViewActive == true),
				tostring(env.state.currentPuzzle ~= nil),
				tostring(env.state.duelActive == true),
				tostring(env.getModeConfig().startTime ~= nil),
				tostring(env.state[spec.usedField] == true)
			))
			if fromPurchase then
				env.showDesktopAlert(nil, string.format("%s purchased. Start or resume a timed board to use it.", runtime.getDisplayName(kind)), "info", {
					duration = 2.6,
				})
			end
			return false
		end

		local timedProductRemote = env.remotes.useTimedProduct
		if not timedProductRemote then
			print(string.format("[WordSearch MoreTime] tryUse missing_remote kind=%s", tostring(kind)))
			env.showDesktopAlert(nil, "Timed product service is unavailable.", "error", {
				duration = 2.2,
			})
			return false
		end

		local result = nil
		local ok = pcall(function()
			result = timedProductRemote:InvokeServer({
				kind = kind,
				boardState = env.RuntimeHelpers.buildBoardProgressPayload(),
			})
		end)

		if not ok or type(result) ~= "table" then
			print(string.format(
				"[WordSearch MoreTime] tryUse bad_result kind=%s invokeOk=%s resultType=%s",
				tostring(kind),
				tostring(ok),
				tostring(type(result))
			))
			env.showDesktopAlert(nil, "Timed product could not be used.", "error", {
				duration = 2.2,
			})
			return false
		end

		if result.snapshot then
			env.applySnapshot(result.snapshot)
		end

		if result.success ~= true then
			print(string.format(
				"[WordSearch MoreTime] tryUse rejected kind=%s message=%s",
				tostring(kind),
				tostring(result.message or "Timed product could not be used.")
			))
			local message = tostring(result.message or "Timed product could not be used.")
			if fromPurchase then
				message = string.format("%s purchased. %s", runtime.getDisplayName(kind), message)
			end
			env.showDesktopAlert(nil, message, "info", {
				duration = 2.4,
			})
			return false
		end

		print(string.format(
			"[WordSearch MoreTime] tryUse accepted kind=%s fromPurchase=%s",
			tostring(kind),
			tostring(fromPurchase == true)
		))
		return spec.apply()
	end

	return runtime
end

return module
