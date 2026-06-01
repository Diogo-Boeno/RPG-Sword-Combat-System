--[[
	LevelService
	Sistema de XP / Level.
	- Qualquer modelo com a tag "npc" (CollectionService) dá XP ao morrer.
	- O XP vai pra quem deu o último dano (atributo LastAttackerUserId, setado pelo HitService).
	- Ao acumular XP suficiente, sobe de nível (curva configurável).

	Como dar XP por um NPC específico:
		coloca a tag "npc" no modelo e (opcional) um atributo "XPReward" (número).
		Sem XPReward, usa DEFAULT_XP.

	Comunicação com client (HUD de level):
		Remote "LevelChanged" -> FireClient(player, level, xp, xpParaProximo)
--]]

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(ServerScriptService:WaitForChild("DataManager"))
local Shared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Net    = require(Shared:WaitForChild("Net"))

local LevelService = {}

local NPC_TAG          = "npc"
local DEFAULT_XP       = 25     -- XP por NPC sem XPReward definido
local KILL_CREDIT_TIME = 8      -- s: janela em que o último hit ainda conta como kill

-- Curva de XP: quanto precisa pra ir do nível L pro L+1.
-- Fórmula simples e ajustável. Ex: nivel 1->2 = 100, cresce ~40% por nível.
local function xpForLevel(level)
	return math.floor(100 * (level ^ 1.4))
end

LevelService.xpForLevel = xpForLevel -- exposto pro HUD calcular a barra

-- Marca NPCs já processados pra não dar XP duplicado (morte dispara múltiplas vezes).
local processedDeaths = {}

local function grantXP(player, amount)
	local level = DataManager.GetLevel(player)
	local xp    = DataManager.GetXP(player) + amount

	-- Sobe de nível enquanto tiver XP suficiente (pode subir vários de uma vez)
	local leveledUp = false
	while xp >= xpForLevel(level) do
		xp -= xpForLevel(level)
		level += 1
		leveledUp = true
	end

	DataManager.SetLevelXP(player, level, xp)
	Net:FireClient("LevelChanged", player, level, xp, xpForLevel(level))

	if leveledUp then
		Net:FireClient("LevelUp", player, level)
	end
end

local function onNPCDied(npcModel, humanoid)
	if processedDeaths[npcModel] then return end
	processedDeaths[npcModel] = true

	local attackerUserId = npcModel:GetAttribute("LastAttackerUserId")
	local lastHit        = npcModel:GetAttribute("LastHitTime") or 0
	if not attackerUserId then return end
	if (os.clock() - lastHit) > KILL_CREDIT_TIME then return end

	local player = Players:GetPlayerByUserId(attackerUserId)
	if not player then return end

	local reward = npcModel:GetAttribute("XPReward") or DEFAULT_XP
	grantXP(player, reward)

	-- NPCs do CombatAI respawnam (não são destruídos); libera o flag depois
	-- pra permitir creditar a próxima morte.
	task.delay(5, function()
		processedDeaths[npcModel] = nil
	end)
end

local function hookNPC(npcModel)
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		-- pode ainda não ter carregado; tenta de novo rapidinho
		task.delay(0.5, function()
			if npcModel.Parent then
				local h = npcModel:FindFirstChildOfClass("Humanoid")
				if h then
					h.Died:Connect(function() onNPCDied(npcModel, h) end)
				end
			end
		end)
		return
	end
	humanoid.Died:Connect(function() onNPCDied(npcModel, humanoid) end)
end

function LevelService:Start()
	-- Cria os remotes no boot
	Net:GetEvent("LevelChanged")
	Net:GetEvent("LevelUp")

	-- NPCs já presentes + futuros
	for _, npc in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		hookNPC(npc)
	end
	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(hookNPC)

	-- Quando o player entra (ou data carrega), manda o estado atual pro HUD
	local function pushState(player)
		task.spawn(function()
			DataManager.WaitForData(player, 10)
			local level = DataManager.GetLevel(player)
			local xp    = DataManager.GetXP(player)
			Net:FireClient("LevelChanged", player, level, xp, xpForLevel(level))

			-- Kit inicial de teste: garante pelo menos 3 poções de cura.
			-- (remova isso quando tiver loja/drops de verdade)
			if DataManager.GetItemCount(player, "HealthPotion") <= 0 then
				local left = DataManager.AddItem(player, "HealthPotion", 3)
				Net:FireClient("InventoryChanged", player, "HealthPotion", left)
			else
				Net:FireClient("InventoryChanged", player, "HealthPotion", DataManager.GetItemCount(player, "HealthPotion"))
			end
		end)
	end
	Players.PlayerAdded:Connect(pushState)
	for _, p in ipairs(Players:GetPlayers()) do pushState(p) end
end

return LevelService
