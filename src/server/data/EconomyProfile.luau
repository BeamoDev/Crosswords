-- Pure economy mutations for an already-normalized profile. DataService owns
-- validation, locking, persistence, and snapshots; this module owns only the
-- atomic domain rules that run while the profile mutation lock is held.
local EconomyProfile = {}

local COSMETIC_FIELDS = table.freeze({
	Theme = table.freeze({ owned = "ownedThemes", equipped = "equippedTheme" }),
	Trail = table.freeze({ owned = "ownedTrails", equipped = "equippedTrail" }),
	Background = table.freeze({ owned = "ownedBackgrounds", equipped = "equippedBackground" }),
	UIStyle = table.freeze({ owned = "ownedUIStyles", equipped = "equippedUIStyle" }),
})

function EconomyProfile.GetCosmeticFields(kind)
	return type(kind) == "string" and COSMETIC_FIELDS[kind] or nil
end

function EconomyProfile.ApplyDailyReward(profile, dayStamp, coinReward, hintReward, limits)
	if profile.rewards.lastClaimDay >= dayStamp then
		return false
	end

	profile.rewards.lastClaimDay = dayStamp
	profile.rewards.totalClaims = math.min(limits.maxStat, profile.rewards.totalClaims + 1)
	profile.inventory.coins = math.clamp(profile.inventory.coins + coinReward, 0, limits.maxCoins)
	profile.inventory.hints = math.clamp(profile.inventory.hints + hintReward, 0, limits.maxHints)
	return true
end

-- Returns applied, already_applied, already_owned, insufficient_funds, or
-- invalid_kind. Products passed here have already been resolved and bounded by
-- the server catalog boundary in DataService/EconomyService.
function EconomyProfile.ApplyPurchase(profile, product, requestId, timestamp, limits)
	if profile.idempotency.shopPurchases[requestId] then
		return "already_applied"
	end

	local fields = EconomyProfile.GetCosmeticFields(product.kind)
	if product.kind ~= "Hints" and not fields then
		return "invalid_kind"
	end
	if fields and profile.cosmetics[fields.owned][product.itemId] == true then
		return "already_owned"
	end
	if profile.inventory.coins < product.coinPrice then
		return "insufficient_funds"
	end

	profile.inventory.coins -= product.coinPrice
	if product.kind == "Hints" then
		profile.inventory.hints = math.clamp(
			profile.inventory.hints + product.amount,
			0,
			limits.maxHints
		)
	else
		profile.cosmetics[fields.owned][product.itemId] = true
	end
	profile.idempotency.shopPurchases[requestId] = {
		at = timestamp,
		productId = product.productId,
	}
	return "applied"
end

function EconomyProfile.EquipCosmetic(profile, kind, itemId)
	local fields = EconomyProfile.GetCosmeticFields(kind)
	if not fields then
		return false, "Invalid cosmetic."
	end
	if profile.cosmetics[fields.owned][itemId] ~= true then
		return false, "You do not own this item."
	end

	profile.cosmetics[fields.equipped] = itemId
	return true
end

return table.freeze(EconomyProfile)
