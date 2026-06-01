--[[
	ItemService
	Processa uso de itens consumíveis (poções etc).

	Fluxo:
		client pede usar item -> Net "UseItem" (FireServer com itemName)
		server valida (tem o item? cooldown? stunado?) -> aplica efeito -> consome
		server responde -> Net "ItemUsed" / "ItemDenied" / "InventoryChanged"

	Efeitos suportados (ver ItemRegistry):
		HealFlat, HealPercent, RestorePosture, HealOverTime
--]]

local Players           = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager  = require(ServerScriptService:WaitForChild("DataManager"))
local ItemRegistry = require(ReplicatedStorage:WaitForChild("ItemRegistry"))
local Shared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Net    = require(Shared:WaitForChild("Net"))

local ItemService = {}

local POSTURE_MAX = 100
local cooldowns = {} -- [player] = { [itemName] = readyAtClock }

local function isOnCooldown(player, itemName)
	local t = cooldowns[player]
	if not t then return false end
	local readyAt = t[itemName]
	return readyAt ~= nil and os.clock() < readyAt
end

local function setCooldown(player, itemName, dur)
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][itemName] = os.clock() + dur
end

local function applyEffect(character, humanoid, effect)
	local kind = effect.Kind

	if kind == "HealFlat" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + (effect.Amount or 0))

	elseif kind == "HealPercent" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * (effect.Percent or 0))

	elseif kind == "RestorePosture" then
		local target = effect.Amount or POSTURE_MAX
		character:SetAttribute("Posture", math.min(POSTURE_MAX, target))

	elseif kind == "HealOverTime" then
		local duration = effect.Duration or 3
		local total
		if effect.Percent then
			total = humanoid.MaxHealth * (effect.Total or 0)
		else
			total = effect.Total or 0
		end
		local ticks = math.max(1, math.floor(duration / 0.2))
		local perTick = total / ticks
		task.spawn(function()
			for _ = 1, ticks do
				if humanoid.Health <= 0 then break end
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perTick)
				task.wait(0.2)
			end
		end)
	end
end

local function onUseItem(player, itemName)
	if type(itemName) ~= "string" then return end

	local def = ItemRegistry[itemName]
	if not def then return end

	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return end

	-- Não pode usar enquanto stunado ou atacando
	if character:GetAttribute("IsStunned") then
		Net:FireClient("ItemDenied", player, itemName, "stunned")
		return
	end
	if isOnCooldown(player, itemName) then
		Net:FireClient("ItemDenied", player, itemName, "cooldown")
		return
	end

	-- Tem o item?
	if DataManager.GetItemCount(player, itemName) <= 0 then
		Net:FireClient("ItemDenied", player, itemName, "empty")
		return
	end

	-- Marca cooldown já (UseTime + Cooldown) pra não dar spam durante o "beber"
	setCooldown(player, itemName, (def.UseTime or 0) + (def.Cooldown or 0))

	-- Estado de uso (o client pode tocar anim de beber lendo esse atributo)
	character:SetAttribute("UsingItem", true)
	Net:FireClient("ItemUseStarted", player, itemName, def.UseTime or 0)

	task.delay(def.UseTime or 0, function()
		if not character.Parent or humanoid.Health <= 0 then
			character:SetAttribute("UsingItem", false)
			return
		end
		-- Se levou guardbreak/stun durante o "beber", cancela (sem consumir)
		if character:GetAttribute("IsStunned") then
			character:SetAttribute("UsingItem", false)
			Net:FireClient("ItemDenied", player, itemName, "interrupted")
			return
		end

		applyEffect(character, humanoid, def.Effect or {})

		if def.ConsumeOnUse ~= false then
			local left = DataManager.AddItem(player, itemName, -1)
			Net:FireClient("InventoryChanged", player, itemName, left)
		end

		character:SetAttribute("UsingItem", false)
		Net:FireClient("ItemUsed", player, itemName)
	end)
end

function ItemService:Start()
	Net:GetEvent("UseItem")
	Net:GetEvent("ItemUsed")
	Net:GetEvent("ItemDenied")
	Net:GetEvent("ItemUseStarted")
	Net:GetEvent("InventoryChanged")

	Net:OnServerEvent("UseItem", onUseItem)

	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return ItemService
