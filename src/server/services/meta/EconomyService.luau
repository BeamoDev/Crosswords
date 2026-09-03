-- Server-owned economy facade. Clients submit only stable catalog identifiers;
-- prices, grants, ownership, and UTC reward eligibility are resolved here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local config = assert(shared:WaitForChild("config", 10), "Word Search config folder is missing")
local serverFolder = script.Parent.Parent.Parent
local dataFolder = assert(serverFolder:WaitForChild("data", 10), "Word Search data folder is missing")
local ShopConfig = require(assert(config:WaitForChild("ShopConfig", 10), "Word Search ShopConfig is missing"))
local DataService = require(assert(dataFolder:WaitForChild("DataService", 10), "Word Search DataService is missing"))
local DailyPuzzleService = require(assert(script.Parent:WaitForChild("DailyPuzzleService", 10), "Word Search DailyPuzzleService is missing"))

local EconomyService = {}

local function copyProduct(product)
	return {
		id = product.id,
		title = product.title,
		description = product.description,
		kind = product.kind,
		itemId = product.itemId,
		amount = product.amount,
		coinPrice = product.coinPrice,
		disabled = product.disabled == true or (product.kind == "CoinPack" and not product.developerProductId),
		accent = product.accent,
	}
end

function EconomyService.GetCatalog()
	local products = {}
	for _, product in ipairs(ShopConfig.Products) do
		table.insert(products, copyProduct(product))
	end
	local today = DailyPuzzleService.GetUtcDayStamp()
	local reward, rewardIndex = ShopConfig.GetDailyReward(today)
	return {
		products = products,
		dailyReward = { coins = reward.coins, hints = reward.hints, index = rewardIndex },
		dayStamp = today,
	}
end

function EconomyService.ClaimDailyReward(player)
	local today = DailyPuzzleService.GetUtcDayStamp()
	local reward, rewardIndex = ShopConfig.GetDailyReward(today)
	local success, snapshotOrError, applied = DataService.ClaimDailyReward(player, reward.coins, reward.hints)
	return success, snapshotOrError, applied, {
		coins = reward.coins,
		hints = reward.hints,
		index = rewardIndex,
	}
end

function EconomyService.Purchase(player, productId, requestId)
	local product = ShopConfig.GetProduct(productId)
	if not product then return false, "Unknown shop item.", false end
	return DataService.ApplyShopPurchase(player, product, requestId)
end

function EconomyService.Equip(player, kind, itemId)
	return DataService.EquipCosmetic(player, kind, itemId)
end

return table.freeze(EconomyService)
