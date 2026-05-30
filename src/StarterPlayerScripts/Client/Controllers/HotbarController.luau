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

local EquipWeapon, UnequipWeapon, LoadoutChanged

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

local function equipSlot(slot)
	if not hotbarLoadout[slot] then return end
	if currentSlot == slot then
		UnequipWeapon:FireServer()
		currentSlot = nil
	else
		currentSlot = slot
		EquipWeapon:FireServer(slot)
	end
	notifyUI()
end

function HotbarController:Init()
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	EquipWeapon    = Remotes:WaitForChild("EquipWeapon")
	UnequipWeapon  = Remotes:WaitForChild("UnequipWeapon")
	LoadoutChanged = Remotes:WaitForChild("LoadoutChanged")
end

function HotbarController:Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		local slot = KEY_TO_SLOT[input.KeyCode]
		if slot then equipSlot(slot) end
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
