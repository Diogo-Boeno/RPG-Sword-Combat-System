local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponRegistry = require(ReplicatedStorage:WaitForChild("WeaponRegistry"))

local HotbarController = {}

local player = Players.LocalPlayer

local EquipWeapon, WeaponEquipped, WeaponUnequipped, LoadoutChanged
local previewsFolder

local hotbarLoadout = {}
local currentSlot = nil

local hotbarFrame -- HotbarGui.HotbarFrame (cache)

local SLOT_COUNT = 10
local STROKE_THICKNESS = 2
local ACTIVE_STROKE = Color3.fromRGB(255, 255, 255)   -- branco no slot equipado
local VIEWPORT_ZOOM = 0.8   -- menor = mais perto (mais zoom)

local KEY_TO_SLOT = {
	[Enum.KeyCode.One] = 1,   [Enum.KeyCode.Two] = 2,  [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,  [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

-- A tecla mostrada no slot (slot 10 = tecla "0").
local function slotKeyText(slot)
	return slot == 10 and "0" or tostring(slot)
end

-- ─── Viewport 3D ─────────────────────────────────────────────────

local function frameViewport(viewport, model)
	local cam = viewport:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = viewport
	end
	viewport.CurrentCamera = cam

	local cf, size = model:GetBoundingBox()
	local maxExtent = math.max(size.X, size.Y, size.Z)
	local dist = maxExtent * VIEWPORT_ZOOM

	-- Olha o modelo de um ângulo 3/4 (frente, um pouco de cima e de lado).
	local dir = Vector3.new(0.5, 0.35, 1).Unit
	cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
end

local function populateViewport(slotFrame, weaponName)
	local viewport = slotFrame:FindFirstChild("ViewportFrame")
	if not viewport then return end

	local worldModel = viewport:FindFirstChild("WorldModel")
	local container = worldModel or viewport

	-- Limpa o preview anterior (mantém o WorldModel/Camera).
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			child:Destroy()
		end
	end

	if not weaponName or not previewsFolder then return end
	local src = previewsFolder:FindFirstChild(weaponName)
	if not src then return end

	local clone = src:Clone()
	clone.Parent = container
	frameViewport(viewport, clone)
end

-- ─── Render ──────────────────────────────────────────────────────

local function getHotbarFrame()
	if hotbarFrame and hotbarFrame.Parent then
		return hotbarFrame
	end
	local gui = player.PlayerGui:FindFirstChild("HotbarGui")
	if not gui then return nil end
	hotbarFrame = gui:FindFirstChild("HotbarFrame")
	return hotbarFrame
end

-- Deixa o slot quadrado (garante um UIAspectRatioConstraint = 1).
local function ensureSquare(slotFrame)
	local ar = slotFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not ar then
		ar = Instance.new("UIAspectRatioConstraint")
		ar.Parent = slotFrame
	end
	ar.AspectRatio = 1
end

local function render()
	local frame = getHotbarFrame()
	if not frame then return end

	for slot = 1, SLOT_COUNT do
		local slotFrame = frame:FindFirstChild("Slot" .. slot)
		if slotFrame then
			local weaponName = hotbarLoadout[slot]

			slotFrame.Visible = true   -- todos os 10 slots sempre aparentes
			ensureSquare(slotFrame)

			local numberLabel = slotFrame:FindFirstChild("Number")
			if numberLabel and numberLabel:IsA("TextLabel") then
				numberLabel.Text = slotKeyText(slot)
			end

			local nameLabel = slotFrame:FindFirstChild("ItemName")
			if nameLabel and nameLabel:IsA("TextLabel") then
				local info = weaponName and WeaponRegistry[weaponName]
				nameLabel.Text = (info and info.DisplayName) or weaponName or ""
			end

			populateViewport(slotFrame, weaponName)

			-- O ImageLabel está no lugar do viewport; esconde onde tem preview 3D.
			local image = slotFrame:FindFirstChild("ImageLabel")
			if image and image:IsA("ImageLabel") then
				image.Visible = (weaponName == nil)
			end

			-- UIStroke: só aparece (branco) no slot ativo.
			local stroke = slotFrame:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Enabled = (slot == currentSlot)
				if stroke.Enabled then
					stroke.Color       = ACTIVE_STROKE
					stroke.Thickness   = STROKE_THICKNESS
					stroke.Transparency = 0
				end
			end
		end
	end
end

-- ─── Input ───────────────────────────────────────────────────────

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

--  Lifecycle

function HotbarController:Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	EquipWeapon = Remotes:WaitForChild("EquipWeapon")
	WeaponEquipped = Remotes:WaitForChild("WeaponEquipped")
	WeaponUnequipped = Remotes:WaitForChild("WeaponUnequipped")
	LoadoutChanged = Remotes:WaitForChild("LoadoutChanged")

	previewsFolder = ReplicatedStorage:WaitForChild("WeaponPreviews", 10)
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
		render()
	end)

	WeaponUnequipped.OnClientEvent:Connect(function()
		currentSlot = nil
		render()
	end)

	LoadoutChanged.OnClientEvent:Connect(function(loadout)
		hotbarLoadout = loadout or {}
		currentSlot   = nil
		render()
	end)

	player.CharacterAdded:Connect(function()
		currentSlot = nil
		render()
	end)

	-- Garante que o GUI já replicou antes do primeiro render.
	player.PlayerGui:WaitForChild("HotbarGui", 10)
	render()
end

return HotbarController
