--[[
	HotbarController
	Keybinds 1-9 / 0 pra hotbar de armas. Comunica com WeaponService via Remotes.
	Era: StarterPlayerScripts.HotbarClient
--]]

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HotbarController = {}

local player = Players.LocalPlayer

local EquipWeapon, WeaponEquipped, WeaponUnequipped, LoadoutChanged

local hotbarLoadout = {}
local unlockedList  = {}
local currentSlot   = nil

local KEY_TO_SLOT = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

local function notifyUI()
	local gui = player.PlayerGui:FindFirstChild("HotbarGui")
	if not gui then return end
	local evt = gui:FindFirstChild("UpdateHotbar")
	if evt then evt:Fire(hotbarLoadout, unlockedList, currentSlot) end
end

-- Só manda o slot pressionado. O SERVER decide equip vs unequip e confirma
-- via WeaponEquipped / WeaponUnequipped. O client não adivinha o estado.
local function equipSlot(slot)
	if not hotbarLoadout[slot] then return end
	EquipWeapon:FireServer(slot)
end

local function slotForWeapon(weaponName)
	for slot, name in pairs(hotbarLoadout) do
		if name == weaponName then return slot end
	end
	return nil
end

function HotbarController:Init()
	local Remotes    = ReplicatedStorage:WaitForChild("Remotes")
	EquipWeapon      = Remotes:WaitForChild("EquipWeapon")
	WeaponEquipped   = Remotes:WaitForChild("WeaponEquipped")
	WeaponUnequipped = Remotes:WaitForChild("WeaponUnequipped")
	LoadoutChanged   = Remotes:WaitForChild("LoadoutChanged")
end

function HotbarController:Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		local slot = KEY_TO_SLOT[input.KeyCode]
		if slot then equipSlot(slot) end
	end)

	-- O destaque do slot segue o que o SERVER confirmou, não o palpite do client.
	WeaponEquipped.OnClientEvent:Connect(function(weaponName)
		currentSlot = slotForWeapon(weaponName)
		notifyUI()
	end)

	WeaponUnequipped.OnClientEvent:Connect(function()
		currentSlot = nil
		notifyUI()
	end)

	LoadoutChanged.OnClientEvent:Connect(function(loadout, unlocked)
		hotbarLoadout = loadout  or {}
		unlockedList  = unlocked or {}
		currentSlot   = nil
		notifyUI()
	end)

	player.CharacterAdded:Connect(function()
		currentSlot = nil
		notifyUI()
	end)
end

return HotbarController
