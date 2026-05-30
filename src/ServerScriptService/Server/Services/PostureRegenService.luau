--[[
	PostureRegenService
	Regenera postura do personagem quando está em estado neutro.
	Era: ServerScriptService.PostureRegenHandler
--]]

local Players = game:GetService("Players")

local PostureRegenService = {}

local TICK = 0.5
local REGEN_PER_TICK = 5
local MAX_POSTURE = 100

local function regenLoop(character)
	task.spawn(function()
		while character and character.Parent do
			task.wait(TICK)
			local state = character:GetAttribute("State")
			local posture = character:GetAttribute("Posture") or MAX_POSTURE
			if (state == "Idle" or state == "Running") and posture < MAX_POSTURE then
				character:SetAttribute("Posture", math.min(posture + REGEN_PER_TICK, MAX_POSTURE))
			end
		end
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(regenLoop)
	if player.Character then
		regenLoop(player.Character)
	end
end

function PostureRegenService:Start()
	Players.PlayerAdded:Connect(bindPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		bindPlayer(p)
	end
end

return PostureRegenService
