local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Net"))

local Roll = {}

local player = Players.LocalPlayer

-- ─── Tunables (devem casar com o RollService) ────────────────────
local ROLL_ANIM_ID = 77751651570691-- TODO: cole aqui o ID da sua animação Roll (só o número)
local ROLL_KEY = Enum.KeyCode.Q
local ROLL_SPEED = 30 -- studs/seg do impulso horizontal
local ROLL_TIME = 0.5 -- duração do deslocamento
local COOLDOWN = 1 -- cooldown local (feedback; o server é a verdade)

-- ─── Estado por character ────────────────────────────────────────
local character, humanoid, rootPart, animator
local rollTrack
local isRolling = false
local lastRoll = -math.huge
local moveConn

local function stopMovement()
	if moveConn then moveConn:Disconnect(); moveConn = nil end
	if humanoid then humanoid.AutoRotate = true end
	isRolling = false
end

local function bindCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")
	animator = humanoid:WaitForChild("Animator")

	stopMovement()
	lastRoll = -math.huge
	rollTrack = nil

	if ROLL_ANIM_ID and ROLL_ANIM_ID ~= 0 then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(ROLL_ANIM_ID)
		rollTrack = animator:LoadAnimation(anim)
		rollTrack.Priority = Enum.AnimationPriority.Action3
		rollTrack.Looped = false
	end
end

local function canRoll()
	if isRolling then return false end
	if os.clock() - lastRoll < COOLDOWN then return false end
	if not character or not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("IsStunned") then return false end
	local state = character:GetAttribute("State")
	if state == "Stunned" or state == "Dodging" or state == "Attacking" then return false end
	return true
end

local function getRollDirection()
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0.1 then
		return moveDir.Unit
	end
	-- Sem input de movimento: rola pra trás.
	return -rootPart.CFrame.LookVector
end

local function doRoll()
	if not canRoll() then return end
	isRolling = true
	lastRoll  = os.clock()

	-- Avisa o server (i-frames, State="Dodging", cooldown autoritativo).
	Net:FireServer("RollRequest")

	-- Animação local imediata (replica sozinha pros outros clients).
	if rollTrack then
		rollTrack:Play(0.1)
	end

	-- Movimento: sobrescreve a velocidade horizontal por ROLL_TIME,
	-- preservando o Y (gravidade continua agindo).
	local dir = getRollDirection()
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude > 0.01 then
		flatDir = flatDir.Unit
	else
		flatDir = rootPart.CFrame.LookVector
	end

	-- Vira o personagem na direção do roll e tira o controle de rotação do Humanoid
	-- pra ele não brigar com o nosso override de velocidade.
	humanoid.AutoRotate = false
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir)

	local endTime = os.clock() + ROLL_TIME

	if moveConn then moveConn:Disconnect() end
	moveConn = RunService.Heartbeat:Connect(function()
		if os.clock() >= endTime
			or not rootPart or not rootPart.Parent
			or not character or character:GetAttribute("IsStunned")
		then
			if rollTrack then rollTrack:Stop(0.15) end
			stopMovement()
			return
		end
		local v = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(flatDir.X * ROLL_SPEED, v.Y, flatDir.Z * ROLL_SPEED)
	end)
end

-- ─── Lifecycle ───────────────────────────────────────────────────

function Roll:Start()
	bindCharacter(player.Character or player.CharacterAdded:Wait())
	player.CharacterAdded:Connect(bindCharacter)

	ContextActionService:BindAction("Roll", function(_, state)
		if state == Enum.UserInputState.Begin then
			doRoll()
		end
		return Enum.ContextActionResult.Pass
	end, false, ROLL_KEY)
end

return Roll
