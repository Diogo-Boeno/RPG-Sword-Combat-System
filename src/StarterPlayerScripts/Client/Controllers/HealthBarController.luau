--[[
	HealthBarController
	Atualiza a HUD do player (barra de Vida + Postura).
	- Vida segue Humanoid.Health / MaxHealth
	- Postura segue o atributo "Posture" do character (0..100), igual ao sistema de combate
	Re-vincula a cada respawn.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Net = require(Shared:WaitForChild("Net"))

local HealthBarController = {}

local player = Players.LocalPlayer

local POSTURE_MAX = 100
local TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local hud, healthFill, healthLabel, postureFill
local xpFill, xpLabel, lvlBadge, potionCount
local conns = {}

local function disconnectAll()
	for _, c in ipairs(conns) do
		if c.Connected then c:Disconnect() end
	end
	table.clear(conns)
end

local function resolveUI()
	hud = player:WaitForChild("PlayerGui"):WaitForChild("PlayerHUD")
	local container = hud:WaitForChild("StatsContainer")
	healthFill  = container:WaitForChild("HealthBG"):WaitForChild("Fill")
	healthLabel = container.HealthBG:WaitForChild("Label")
	postureFill = container:WaitForChild("PostureBG"):WaitForChild("Fill")

	-- Level/XP
	local lvlContainer = hud:WaitForChild("LevelContainer")
	lvlBadge = lvlContainer:WaitForChild("LevelBadge")
	xpFill   = lvlContainer:WaitForChild("XPBG"):WaitForChild("Fill")
	xpLabel  = lvlContainer.XPBG:WaitForChild("Label")

	-- Poção
	local potion = hud:WaitForChild("PotionIndicator")
	potionCount = potion:WaitForChild("Count")
end

local function updateLevel(level, xp, xpForNext)
	if lvlBadge then lvlBadge.Text = tostring(level) end
	if xpFill then
		local pct = math.clamp(xp / math.max(xpForNext, 1), 0, 1)
		TweenService:Create(xpFill, TWEEN, { Size = UDim2.new(pct, -4, 1, -4) }):Play()
	end
	if xpLabel then xpLabel.Text = ("%d / %d"):format(xp, xpForNext) end
end

local function updatePotion(count)
	if potionCount then potionCount.Text = tostring(count or 0) end
end

local function updateHealth(humanoid)
	if not humanoid or not healthFill then return end
	local pct = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	TweenService:Create(healthFill, TWEEN, {
		Size = UDim2.new(pct, -4, 1, -4)
	}):Play()
	if healthLabel then
		healthLabel.Text = ("%d / %d"):format(math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5))
	end
end

local function updatePosture(character)
	if not character or not postureFill then return end
	local posture = character:GetAttribute("Posture") or POSTURE_MAX
	local pct = math.clamp(posture / POSTURE_MAX, 0, 1)
	TweenService:Create(postureFill, TWEEN, {
		Size = UDim2.new(pct, -4, 1, -4)
	}):Play()
end

local function bindCharacter(character)
	disconnectAll()
	local humanoid = character:WaitForChild("Humanoid")

	-- estado inicial
	updateHealth(humanoid)
	updatePosture(character)

	table.insert(conns, humanoid.HealthChanged:Connect(function()
		updateHealth(humanoid)
	end))
	table.insert(conns, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateHealth(humanoid)
	end))
	table.insert(conns, character:GetAttributeChangedSignal("Posture"):Connect(function()
		updatePosture(character)
	end))
end

function HealthBarController:Start()
	resolveUI()

	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		-- a HUD tem ResetOnSpawn=false, então não precisa re-resolver a UI
		bindCharacter(char)
	end)

	-- Level/XP vindo do LevelService
	Net:OnClientEvent("LevelChanged", function(level, xp, xpForNext)
		updateLevel(level, xp, xpForNext)
	end)

	-- Contador de poção vindo do ItemService (mostra a HealthPotion no indicador)
	Net:OnClientEvent("InventoryChanged", function(itemName, count)
		if itemName == "HealthPotion" then
			updatePotion(count)
		end
	end)
end

return HealthBarController
