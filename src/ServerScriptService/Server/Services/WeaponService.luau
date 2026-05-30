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
local EquipWeapon, UnequipWeapon, LoadoutChanged, WeaponEquipped, WeaponUnequipped
local MoveToHand, MoveToScabbard
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

local function doUnequip(player)
	local character = player.Character
	if not character then return end
	WeaponUnequipped:FireClient(player)
	character:SetAttribute("State", "Sheathing")
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
	if not character then return end

	local loadout = DataManager.GetLoadout(player)
	local weaponName = loadout[slotIndex]
	if not weaponName then return end

	local scabbardModel = ensureScabbard(player, weaponName)

	local current = getEquippedModel(character)
	if current then current:Destroy() end

	local template = getTemplate(weaponName)
	if not template then warn("Template não encontrado: " .. weaponName); return end

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

	WeaponEquipped:FireClient(player, weaponName, bladeModel)
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
	Remotes          = ReplicatedStorage:WaitForChild("Remotes")
	EquipWeapon      = Remotes:WaitForChild("EquipWeapon")
	UnequipWeapon    = Remotes:WaitForChild("UnequipWeapon")
	LoadoutChanged   = Remotes:WaitForChild("LoadoutChanged")
	WeaponEquipped   = Remotes:WaitForChild("WeaponEquipped")
	WeaponUnequipped = Remotes:WaitForChild("WeaponUnequipped")
	MoveToHand       = Remotes:WaitForChild("MoveToHand")
	MoveToScabbard   = Remotes:WaitForChild("MoveToScabbard")

	WeaponsFolder     = ServerStorage:WaitForChild("Weapons")
	OriginalHipAttach = ServerStorage:WaitForChild("Assets"):WaitForChild("HipAttach")
end

function WeaponService:Start()
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

	EquipWeapon.OnServerEvent:Connect(doEquip)
	UnequipWeapon.OnServerEvent:Connect(doUnequip)

	Players.PlayerAdded:Connect(bindPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		bindPlayer(p)
	end
end

return WeaponService
