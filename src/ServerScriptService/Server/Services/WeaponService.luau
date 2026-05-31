--[[
	WeaponService
	Equip / unequip de armas, scabbard, Motor6D, etc.
	Era: ServerScriptService.WeaponServer
--]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- DataManager continua em ServerScriptService.DataManager (não foi migrado)
local DataManager    = require(ServerScriptService:WaitForChild("DataManager"))
local WeaponRegistry = require(ReplicatedStorage:WaitForChild("WeaponRegistry"))

local WeaponService = {}

local Remotes
local EquipWeapon, LoadoutChanged, WeaponEquipped, WeaponUnequipped
local MoveToHand, MoveToScabbard, SheathFinish
local WeaponsFolder, OriginalHipAttach

-- ─── Helpers ─────────────────────────────────────────────────

local function getTemplate(weaponName)
	local t = WeaponsFolder:FindFirstChild(weaponName)
	if not t then
		warn(("[WeaponService] Template não encontrado: ServerStorage/Weapons/%s"):format(weaponName))
	end
	return t
end

local function getEquippedModel(character)
	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Model") and WeaponRegistry[obj.Name] and not obj.Name:find("_Scabbard") then
			return obj
		end
	end
	return nil
end

local function getRightHand(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		return character:FindFirstChild("RightHand")
	end
	return character:FindFirstChild("Right Arm")
end

local function getHipPart(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		return character:FindFirstChild("UpperTorso")
	end
	return character:FindFirstChild("Torso")
end

-- ─── Scabbard na Cintura ──────────────────────────────────────

local function attachScabbard(character, scabbardModel)
	if not character or not scabbardModel then return end
	local torso = character:FindFirstChild("Torso") or character:WaitForChild("Torso", 5)
	local scabbardMain = scabbardModel:FindFirstChild("ScabbardMain") or scabbardModel:FindFirstChild("MainPart")

	if torso and scabbardMain then
		local bodyAttach = torso:FindFirstChild("HipAttach")
		local scabbardAttach = scabbardMain:FindFirstChild("ScabbardAttach")
		if bodyAttach and scabbardAttach then
			local motor = Instance.new("Motor6D")
			motor.Name = "ScabbardGrip"
			motor.Part0 = torso
			motor.Part1 = scabbardMain
			motor.C0 = bodyAttach.CFrame
			motor.C1 = scabbardAttach.CFrame
			motor.Parent = scabbardMain
		else
			warn("[WeaponService] Faltando attachments no scabbard/hip")
		end
	end
end

local function attachBladeToScabbard(character, weaponModel)
	local mainPart = weaponModel:FindFirstChild("MainPart")
	local weaponName = weaponModel.Name
	local scabbard = character:FindFirstChild(weaponName .. "_Scabbard")
	local scabbardMain = scabbard and (scabbard:FindFirstChild("ScabbardMain") or scabbard:FindFirstChild("MainPart"))
	local katanaToScabbardAttach = mainPart and mainPart:FindFirstChild("KatanaToScabbardAttach")
	local scabbardAttach = scabbardMain and scabbardMain:FindFirstChild("ScabbardAttach")

	if not mainPart or not scabbardMain or not katanaToScabbardAttach or not scabbardAttach then
		warn("[WeaponService] Falha no Sheath: Attachments ou MainPart não encontrados!")
		return
	end

	local motor = mainPart:FindFirstChild("WeaponGrip")
	if motor then
		motor.Part0 = scabbardMain
		motor.C0 = scabbardAttach.CFrame
		motor.C1 = katanaToScabbardAttach.CFrame
	else
		warn("[WeaponService] Motor6D 'WeaponGrip' não encontrado na MainPart!")
	end
end

local function attachBladeToHand(character, weaponModel)
	local mainPart = weaponModel:FindFirstChild("MainPart")
	local rightHand = getRightHand(character)
	local katanaAttach = mainPart and mainPart:FindFirstChild("KatanaAttach")
	if not mainPart or not rightHand or not katanaAttach then return end

	local handAttach = rightHand:FindFirstChild("KatanaHandAttach")
	if not handAttach then
		handAttach = Instance.new("Attachment")
		handAttach.Name = "KatanaHandAttach"
		handAttach.CFrame = CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(90), math.rad(180), 0)
		handAttach.Parent = rightHand
	end

	local existing = mainPart:FindFirstChild("WeaponGrip")
	if existing then existing:Destroy() end

	for _, part in ipairs(weaponModel:GetDescendants()) do
		if part:IsA("MeshPart") then
			part.Transparency = 0
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "WeaponGrip"
	motor.Part0 = rightHand
	motor.Part1 = mainPart
	motor.C0 = handAttach.CFrame
	motor.C1 = katanaAttach.CFrame
	motor.Parent = mainPart
end

-- ─── Equip / Unequip ───────────────────────────────────────────

local MAX_PENDING = 1   -- máximo de requests enfileirados além do que está executando
local BUSY_TIMEOUT = 2  -- segundos: failsafe caso o client não confirme o fim da animação
local playerQueues = {}
local processingQueue = {}
local weaponBusy = {}   -- player -> true enquanto sheath/unsheath está rolando
local busyToken = {}    -- token pra invalidar timeouts antigos
local equippedWeapon = {} -- player -> weaponName | FONTE DE VERDADE do que está SACADO.
                          -- NÃO usar getEquippedModel pra decidir equip/unequip: o model
                          -- da lâmina persiste guardado na bainha, então ele mente.

local function doUnequip(player)
	local character = player.Character
	if not character then return false end
	if not equippedWeapon[player] then return false end
	equippedWeapon[player] = nil
	WeaponUnequipped:FireClient(player)
	character:SetAttribute("State", "Sheathing")
	return true
end

local function ensureScabbard(player, weaponName)
	local character = player.Character
	if not character then return end
	local existing = character:FindFirstChild(weaponName .. "_Scabbard")
	if existing then return existing end

	local template = getTemplate(weaponName)
	if not template or not template:FindFirstChild("Scabbard") then return end

	local scabbardClone = template.Scabbard:Clone()
	scabbardClone.Name = weaponName .. "_Scabbard"
	scabbardClone.Parent = character

	if scabbardClone:FindFirstChild("MainPart") then
		scabbardClone.MainPart.Name = "ScabbardMain"
	end

	attachScabbard(character, scabbardClone)
	return scabbardClone
end

local function spawnScabbard(player, weaponName)
	local character = player.Character
	if not character then return end

	local old = character:FindFirstChild(weaponName .. "_Scabbard")
	if old then old:Destroy() end

	local template = getTemplate(weaponName)
	if not template then return end

	local scabbardTemplate = template:FindFirstChild("Scabbard")
	if not scabbardTemplate then return end

	local scabbard = scabbardTemplate:Clone()
	scabbard.Name = weaponName .. "_Scabbard"
	scabbard.Parent = character

	local mp = scabbard:FindFirstChild("MainPart")
	if mp then mp.Name = "ScabbardMain" end

	local scabbardMain = scabbard:FindFirstChild("ScabbardMain")
	local scabbardAttach = scabbardMain and scabbardMain:FindFirstChild("ScabbardAttach")
	local hipPart = getHipPart(character)

	if not scabbardMain or not scabbardAttach or not hipPart then
		warn("[WeaponService] spawnScabbard: partes não encontradas.")
		return
	end

	scabbardMain.CanCollide = false
	scabbardMain.Massless = true

	local hipAttach = ServerStorage.Assets:FindFirstChild("HipAttach")

	local motor = Instance.new("Motor6D")
	motor.Name = "ScabbardGrip"
	motor.Part0 = hipPart
	motor.Part1 = scabbardMain
	motor.C0 = hipAttach.CFrame
	motor.C1 = scabbardAttach.CFrame
	motor.Parent = scabbardMain
end

local function doEquip(player, slotIndex)
	local character = player.Character
	if not character then return false end

	local loadout = DataManager.GetLoadout(player)
	local weaponName = loadout[slotIndex]
	if not weaponName then return false end

	local scabbardModel = ensureScabbard(player, weaponName)

	local current = getEquippedModel(character)
	if current then current:Destroy() end

	local template = getTemplate(weaponName)
	if not template then warn("Template não encontrado: " .. weaponName); return false end

	local bladeModel = Instance.new("Model")
	bladeModel.Name = weaponName

	for _, obj in ipairs(template:GetChildren()) do
		if obj.Name ~= "Scabbard" then
			obj:Clone().Parent = bladeModel
		end
	end

	bladeModel.Parent = character

	for _, part in ipairs(bladeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end

	local mainPart       = bladeModel:FindFirstChild("MainPart")
	local scabbardMain   = scabbardModel and (scabbardModel:FindFirstChild("ScabbardMain") or scabbardModel:FindFirstChild("MainPart"))
	local katanaAttach   = mainPart and mainPart:FindFirstChild("KatanaAttach")
	local scabbardAttach = scabbardMain and scabbardMain:FindFirstChild("ScabbardAttach")

	if mainPart and scabbardMain and katanaAttach and scabbardAttach then
		local motor = Instance.new("Motor6D")
		motor.Name = "WeaponGrip"
		motor.Part0 = scabbardMain
		motor.Part1 = mainPart
		motor.C0 = scabbardAttach.CFrame
		motor.C1 = katanaAttach.CFrame
		motor.Parent = mainPart
	else
		warn("[WeaponService] Erro ao conectar: Verifique MainPart e Attachments.")
	end

	character:SetAttribute("State", "Unsheathing")
	equippedWeapon[player] = weaponName
	WeaponEquipped:FireClient(player, weaponName, bladeModel)
	return true
end

local processQueue -- forward declaration

-- Libera o busy (cedo, via SheathFinish) e tenta o próximo da fila.
local function clearBusy(player)
	weaponBusy[player] = false
	busyToken[player] = nil
	local character = player.Character
	if character then
		local state = character:GetAttribute("State")
		if state == "Sheathing" or state == "Unsheathing" then
			character:SetAttribute("State", "Idle")
		end
	end
	processQueue(player)
end

-- Marca busy + agenda failsafe: se o client nunca confirmar, libera sozinho.
local function setBusy(player)
	weaponBusy[player] = true
	local token = {}
	busyToken[player] = token
	task.delay(BUSY_TIMEOUT, function()
		if busyToken[player] == token then
			clearBusy(player)
		end
	end)
end

-- Bloqueia equip/unequip durante ataque/stun/roll (esses têm timer próprio).
local function isCombatBusy(character)
	local state = character:GetAttribute("State")
	return state == "Attacking" or state == "Stunned" or state == "Dodging"
end

function processQueue(player)
	if processingQueue[player] then return end
	if weaponBusy[player] then return end

	local queue = playerQueues[player]
	if not queue or #queue == 0 then return end

	local character = player.Character
	if not character then
		playerQueues[player] = nil
		return
	end

	if isCombatBusy(character) then return end

	processingQueue[player] = true
	local request = table.remove(queue, 1)

	-- Decisão autoritativa contra equippedWeapon (não contra o model, que persiste guardado).
	-- O client só manda o slot; o server decide equip vs unequip.
	local equipped = equippedWeapon[player]
	local loadout = DataManager.GetLoadout(player)
	local targetName = loadout[request.slot]

	local started = false
	if equipped and equipped == targetName then
		started = doUnequip(player)          -- mesma arma sacada -> guarda
	elseif targetName then
		started = doEquip(player, request.slot) -- nada sacado, ou troca de arma -> saca
	end

	processingQueue[player] = false

	if #queue == 0 then
		playerQueues[player] = nil
	end

	if started then
		setBusy(player)
	else
		-- Nada aconteceu (slot inválido etc): tenta o próximo imediatamente.
		processQueue(player)
	end
end

local function enqueue(player, request)
	if not playerQueues[player] then
		playerQueues[player] = {}
	end
	-- Cap: spam de cliques não acumula. Mantém só os primeiros MAX_PENDING.
	if #playerQueues[player] >= MAX_PENDING then
		return
	end
	table.insert(playerQueues[player], request)
	processQueue(player)
end

-- ─── Setup por character ──────────────────────────────────────────

local function setupCharacter(player, character)
	local torso = character:WaitForChild("Torso", 5)
	if torso and not torso:FindFirstChild("HipAttach") then
		local clone = OriginalHipAttach:Clone()
		clone.Parent = torso
	end

	local old = getEquippedModel(character)
	if old then old:Destroy() end

	playerQueues[player] = nil
	processingQueue[player] = false
	weaponBusy[player] = false
	busyToken[player] = nil
	equippedWeapon[player] = nil

	-- Quando o ataque/stun termina (State volta pra Idle), tenta a fila.
	character:GetAttributeChangedSignal("State"):Connect(function()
		if character:GetAttribute("State") == "Idle" then
			processQueue(player)
		end
	end)

	local data = DataManager.WaitForData(player, 10)
	if data then
		LoadoutChanged:FireClient(player, DataManager.GetLoadout(player), DataManager.GetUnlockedWeapons(player))
		local loadout = DataManager.GetLoadout(player)
		for _, weaponName in pairs(loadout) do
			spawnScabbard(player, weaponName)
		end
	else
		warn(("[WeaponService] Timeout ao carregar dados de %s."):format(player.Name))
	end
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

-- ─── Lifecycle ───────────────────────────────────────────────────

function WeaponService:Init()
	Remotes = ReplicatedStorage:WaitForChild("Remotes")
	EquipWeapon = Remotes:WaitForChild("EquipWeapon")
	LoadoutChanged = Remotes:WaitForChild("LoadoutChanged")
	WeaponEquipped = Remotes:WaitForChild("WeaponEquipped")
	WeaponUnequipped = Remotes:WaitForChild("WeaponUnequipped")
	MoveToHand = Remotes:WaitForChild("MoveToHand")
	MoveToScabbard = Remotes:WaitForChild("MoveToScabbard")
	SheathFinish = Remotes:WaitForChild("SheathFinish")

	WeaponsFolder     = ServerStorage:WaitForChild("Weapons")
	OriginalHipAttach = ServerStorage:WaitForChild("Assets"):WaitForChild("HipAttach")
end

function WeaponService:Start()
	-- Marker (meio da animação): só prende a lâmina na mão. NÃO libera a fila ainda.
	MoveToHand.OnServerEvent:Connect(function(player)
		local character = player.Character
		if not character then return end
		local model = getEquippedModel(character)
		if model then attachBladeToHand(character, model) end
	end)

	MoveToScabbard.OnServerEvent:Connect(function(player)
		local character = player.Character
		if not character then return end
		local model = getEquippedModel(character)
		if model then attachBladeToScabbard(character, model) end
	end)

	-- Fim da animação de sheath OU unsheath: libera o busy cedo.
	SheathFinish.OnServerEvent:Connect(function(player)
		if weaponBusy[player] then
			clearBusy(player)
		end
	end)

	-- Client só manda o slot pressionado; o server decide equip vs unequip.
	EquipWeapon.OnServerEvent:Connect(function(player, slotIndex)
		if type(slotIndex) ~= "number" then return end
		enqueue(player, { slot = slotIndex })
	end)

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerQueues[player] = nil
		processingQueue[player] = nil
		weaponBusy[player] = nil
		busyToken[player] = nil
		equippedWeapon[player] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		bindPlayer(p)
	end
end

return WeaponService
