--[[
	RollService
	Autoritativo do roll/dodge: valida cooldown, concede i-frames e gerencia o
	State="Dodging". O movimento e a animação são feitos no client (Roll.luau);
	aqui é só a parte que NÃO pode ser confiada ao client.
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Net"))

local RollService = {}

-- Tunables (devem casar com o client Roll.luau)
local ROLL_TIME   = 0.5   -- duração total do roll (volta pra Idle)
local IFRAME_TIME = 0.4   -- janela de invencibilidade (geralmente < ROLL_TIME)
local COOLDOWN    = 1.2   -- cooldown entre rolls

local lastRoll = {} -- player -> os.clock()

local function onRollRequest(player)
	local character = player.Character
	if not character then return end
	if character:GetAttribute("IsStunned") then return end

	local state = character:GetAttribute("State")
	if state == "Stunned" or state == "Dodging" or state == "Attacking" then return end

	local now = os.clock()
	if now - (lastRoll[player] or -math.huge) < COOLDOWN then return end
	lastRoll[player] = now

	character:SetAttribute("State", "Dodging")
	character:SetAttribute("IFrames", true)

	task.delay(IFRAME_TIME, function()
		if character and character.Parent then
			character:SetAttribute("IFrames", false)
		end
	end)

	task.delay(ROLL_TIME, function()
		if character and character.Parent and character:GetAttribute("State") == "Dodging" then
			character:SetAttribute("State", "Idle")
		end
	end)
end

function RollService:Start()
	Net:OnServerEvent("RollRequest", onRollRequest)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
	end)
end

return RollService
