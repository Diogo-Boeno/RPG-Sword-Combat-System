--[[
	AttributeService
	Inicializa os atributos básicos do personagem ao spawnar.
	Era: ServerScriptService.AttributeHolder
--]]

local Players = game:GetService("Players")

local AttributeService = {}

local DEFAULTS = {
	Posture = 100,
	State = "Idle",
	IsStunned = false,
	ParryWindow = false,
	IsBlocking  = false,
	IFrames     = false,
	OnParryCD   = false,
}

local function setupCharacter(character)
	for name, value in pairs(DEFAULTS) do
		character:SetAttribute(name, value)
	end
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end
end

function AttributeService:Start()
	Players.PlayerAdded:Connect(bindPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		bindPlayer(p)
	end
end

return AttributeService
