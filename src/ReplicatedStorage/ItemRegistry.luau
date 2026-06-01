--[[
	ItemRegistry
	ReplicatedStorage > ItemRegistry (ModuleScript)

	Fonte única de verdade pros itens consumíveis (poções, etc).
	Acessível por client e server.

	Pra adicionar um item novo:
		1. Adiciona a entrada aqui
		2. (opcional) dê o item ao player com DataManager.AddItem(player, "NomeDoItem", qtd)
		3. Pronto — o ItemService cuida do efeito ao usar.

	Campos:
		DisplayName  : string  — nome exibido
		Description  : string
		Icon         : string  — rbxassetid:// pro ícone
		UseTime      : number  — tempo de "beber/usar" (s) antes do efeito
		Cooldown     : number  — cooldown depois de usar (s)
		StackMax     : number  — máximo no inventário
		ConsumeOnUse : bool    — gasta 1 ao usar
		Effect       : table   — o que faz (ver tipos abaixo)

	Tipos de Effect:
		{ Kind = "HealFlat",    Amount = 50 }              -- cura X de vida
		{ Kind = "HealPercent", Percent = 0.4 }            -- cura X% da vida máx
		{ Kind = "RestorePosture", Amount = 100 }          -- restaura postura
		{ Kind = "HealOverTime", Total = 60, Duration = 3 }-- cura ao longo do tempo
--]]

local ItemRegistry = {}

ItemRegistry["HealthPotion"] = {
	DisplayName  = "Frasco de Cura",
	Description  = "Restaura 50 de vida. Estilo Elden Ring.",
	Icon         = "rbxassetid://0",
	UseTime      = 0.8,
	Cooldown     = 1.2,
	StackMax     = 5,
	ConsumeOnUse = true,
	Effect       = { Kind = "HealFlat", Amount = 50 },
}

ItemRegistry["GreatHealthPotion"] = {
	DisplayName  = "Frasco de Cura Maior",
	Description  = "Cura 70% da vida máxima ao longo de 2.5s.",
	Icon         = "rbxassetid://0",
	UseTime      = 1.0,
	Cooldown     = 2.0,
	StackMax     = 3,
	ConsumeOnUse = true,
	Effect       = { Kind = "HealOverTime", Total = 0.7, Duration = 2.5, Percent = true },
}

ItemRegistry["PostureTonic"] = {
	DisplayName  = "Tônico de Postura",
	Description  = "Restaura toda a postura instantaneamente.",
	Icon         = "rbxassetid://0",
	UseTime      = 0.5,
	Cooldown     = 3.0,
	StackMax     = 3,
	ConsumeOnUse = true,
	Effect       = { Kind = "RestorePosture", Amount = 100 },
}

return ItemRegistry
