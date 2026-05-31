local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Net"))

local ParryBarController = {}

local player = Players.LocalPlayer

local READY_COLOR = Color3.fromRGB(255, 255, 255)  -- cheia / pronta
local COOLDOWN_COLOR = Color3.fromRGB(230, 80, 80)    -- recarregando

local fill -- Frame que enche
local refillTween

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ParryBarGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local holder = Instance.new("Frame")
	holder.Name = "ParryBar"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 0.88, 0)   -- centro, acima do hotbar
	holder.Size = UDim2.new(0, 620, 0, 10)
	holder.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	holder.BackgroundTransparency = 0.3
	holder.BorderSizePixel = 0
	holder.Parent = gui

	local holderCorner = Instance.new("UICorner")
	holderCorner.CornerRadius = UDim.new(0, 4)
	holderCorner.Parent = holder

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(1, 0, 1, 0)              -- começa cheia
	fill.BackgroundColor3 = READY_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = holder

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function setFull()
	if refillTween then refillTween:Cancel(); refillTween = nil end
	if fill then
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = READY_COLOR
	end
end

local function onWhiff(duration)
	if not fill then return end
	if refillTween then refillTween:Cancel() end

	-- Esvazia na hora e vai recarregando ao longo do cooldown.
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = COOLDOWN_COLOR

	local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
	refillTween = TweenService:Create(fill, info, { Size = UDim2.new(1, 0, 1, 0) })
	refillTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and fill then
			fill.BackgroundColor3 = READY_COLOR
		end
	end)
	refillTween:Play()
end

function ParryBarController:Start()
	buildGui()

	Net:OnClientEvent("ParryWhiff", function(duration)
		onWhiff(duration or 3)
	end)

	-- Respawn: barra volta cheia (server reseta OnParryCD no novo character).
	player.CharacterAdded:Connect(setFull)
end

return ParryBarController
