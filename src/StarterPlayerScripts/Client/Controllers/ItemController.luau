--[[
	ItemController
	Input de uso de consumíveis (client). Pede ao server via Net "UseItem".

	Binds padrão:
		Q -> HealthPotion (cura, estilo Elden Ring)
		T -> PostureTonic

	A decisão real (tem o item? cooldown?) é do server (ItemService). O client
	é só o gatilho; o server responde com ItemUsed/ItemDenied.
--]]

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Net = require(Shared:WaitForChild("Net"))

local ItemController = {}

local player = Players.LocalPlayer

-- Mapa de tecla -> item
local BINDS = {
	{ key = Enum.KeyCode.R, item = "HealthPotion",  action = "UseHealthPotion" },
	{ key = Enum.KeyCode.T, item = "PostureTonic",  action = "UsePostureTonic" },
}

function ItemController:Start()
	for _, bind in ipairs(BINDS) do
		ContextActionService:BindAction(bind.action, function(_, state)
			if state == Enum.UserInputState.Begin then
				Net:FireServer("UseItem", bind.item)
			end
			return Enum.ContextActionResult.Pass
		end, false, bind.key)
	end

	-- Feedback opcional (pode ligar na HUD depois)
	Net:OnClientEvent("ItemDenied", function(itemName, reason)
		-- silencioso por enquanto; dá pra tocar um som de "falha" aqui
	end)
end

return ItemController
