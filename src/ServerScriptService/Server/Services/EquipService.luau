--[[
	EquipService
	Sistema legacy de equip (usa Remotes diretos em ReplicatedStorage).
	Era: ServerScriptService.EquipServer

	Obs: existe também WeaponService que faz equip via Remotes/EquipWeapon.
	Esse aqui mantém compatibilidade com código antigo que chama EquipRemote/UnequipRemote.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipService = {}

local function getOrCreate(parent, name, class)
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new(class)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

local EquipRemote, UnequipRemote, ValidateWeapon

local function onValidate(player, toolName)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if not character or not backpack then return end
	if typeof(toolName) ~= "string" then return end
	local _ = backpack:FindFirstChild(toolName) -- validação silenciosa original
end

local function onEquip(player, toolName)
	local character = player.Character
	local backpack  = player:FindFirstChild("Backpack")
	if not character or not backpack then return end
	if typeof(toolName) ~= "string" then return end

	local tool = backpack:FindFirstChild(toolName)
	if not tool then
		tool = character:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then return end -- já equipada
		return
	end

	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Tool") then
			obj.Parent = backpack
		end
	end

	tool.Parent = character
end

local function onUnequip(player)
	local character = player.Character
	local backpack  = player:FindFirstChild("Backpack")
	if not character or not backpack then return end
	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Tool") then
			obj.Parent = backpack
		end
	end
end

function EquipService:Init()
	EquipRemote    = getOrCreate(ReplicatedStorage, "EquipRemote",    "RemoteEvent")
	UnequipRemote  = getOrCreate(ReplicatedStorage, "UnequipRemote",  "RemoteEvent")
	ValidateWeapon = getOrCreate(ReplicatedStorage, "ValidateWeapon", "RemoteEvent")
end

function EquipService:Start()
	ValidateWeapon.OnServerEvent:Connect(onValidate)
	EquipRemote.OnServerEvent:Connect(onEquip)
	UnequipRemote.OnServerEvent:Connect(onUnequip)
end

return EquipService
