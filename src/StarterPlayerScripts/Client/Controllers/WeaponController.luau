--[[
	WeaponController
	Input de combate, animations, hitbox, sheath/unsheath.
	Era: StarterPlayerScripts.Handler(tool)

	Nota: depende do character. Inicializa pela primeira vez no Start e re-bind no respawn.
--]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponController = {}

local player = Players.LocalPlayer

local WeaponRegistry, RaycastHitbox
local SwordHitEvent
local Remotes
local WeaponEquipped, WeaponUnequipped, MoveToHand, MoveToScabbard

-- Tunables
local FULL_COMBO_COOLDOWN = 1
local COMBO_RESET_TIME    = 2
-- local PARRY_COOLDOWN_TIME = 3 -- (original não usa, mantemos sem)

-- Per-character state (reset por respawn)
local character, humanoid, animator
local currentWeapon, weaponModel
local idleTrack, walkTrack, blockTrack, unsheathTrack, sheathTrack
local attackTracks = {}
-- Variáveis de conn não mais usadas (CAS gerencia)
local hitbox
local stopConn
local runningConn, stunConn
local equipGeneration = 0
local lastComboEndTime = 0
local nextAttackTime = 0
local currentAttack = 1
local canAttack = false
local isBlocking = false
local isSheathing = false

-- ─── Helpers ─────────────────────────────────────────────────

local function grantCanAttack()
	if not character or character:GetAttribute("IsStunned") then return end
	if os.clock() < nextAttackTime then return end
	canAttack = true
end

local function updateMovement()
	if not humanoid or not idleTrack or not walkTrack then return end
	local state = character:GetAttribute("State")
	if state == "Attacking" or isBlocking then
		idleTrack:Stop(0.1)
		walkTrack:Stop(0.1)
		return
	end
	if humanoid.MoveDirection.Magnitude > 0.1 then
		if not walkTrack.IsPlaying then
			idleTrack:Stop(0.3)
			walkTrack:Play(0.3)
		end
	else
		if not idleTrack.IsPlaying then
			walkTrack:Stop(0.3)
			idleTrack:Play(0.3)
		end
	end
end

local function attack()
	local stats = WeaponRegistry[currentWeapon]
	if not stats then return end
	local state = character:GetAttribute("State")
	local currentTime = os.clock()

	if state == "Stunned" or state == "Dodging" or not canAttack or isSheathing then return end

	if currentTime - nextAttackTime > COMBO_RESET_TIME then
		currentAttack = 1
	end

	canAttack = false
	character:SetAttribute("State", "Attacking")
	SwordHitEvent:FireServer("Attack", currentWeapon, currentAttack)

	local cooldownBase = stats.Cooldown / stats.SwingSpeed
	local isLastHit = (currentAttack >= #attackTracks)
	local actualCooldown = isLastHit and FULL_COMBO_COOLDOWN or cooldownBase
	nextAttackTime = currentTime + actualCooldown

	local gen = equipGeneration
	local track = attackTracks[currentAttack]
	if track then
		track:Play(0.05, 10, stats.SwingSpeed)

		local swingSound = weaponModel
			and weaponModel:FindFirstChild("MainPart")
			and weaponModel.MainPart:FindFirstChild("Swing2")
		if swingSound then swingSound:Play() end

		local startConn, endConn, stateConn

		startConn = track:GetMarkerReachedSignal("HitStart"):Connect(function()
			if equipGeneration ~= gen then startConn:Disconnect(); return end
			hitbox:HitStart()
			startConn:Disconnect()
		end)

		endConn = track:GetMarkerReachedSignal("HitEnd"):Connect(function()
			if equipGeneration ~= gen then endConn:Disconnect(); return end
			hitbox:HitStop()
			endConn:Disconnect()
		end)

		stateConn = character:GetAttributeChangedSignal("State"):Connect(function()
			if equipGeneration ~= gen then stateConn:Disconnect(); return end
			if character:GetAttribute("State") == "Stunned" then
				track:Stop(0.05)
				stateConn:Disconnect()
			end
		end)
	end

	task.delay(actualCooldown, function()
		if os.clock() < nextAttackTime then return end
		if character:GetAttribute("IsStunned") then return end
		canAttack = true
		character:SetAttribute("State", "Idle")
		if isLastHit then
			currentAttack = 1
			lastComboEndTime = os.clock()
		else
			currentAttack += 1
		end
		updateMovement()
	end)
end

local function startBlock()
	print("[DBG] startBlock chamado | canAttack=", canAttack, " isBlocking=", isBlocking, " isSheathing=", isSheathing, " blockTrack=", blockTrack)
	if not canAttack or isBlocking or isSheathing then
		print("[DBG] startBlock SAIU CEDO")
		return
	end
	isBlocking = true
	humanoid.WalkSpeed = 10
	if idleTrack then idleTrack:Stop(0.2) end
	if walkTrack then walkTrack:Stop(0.2) end
	blockTrack:Play(0.2, 10)
	SwordHitEvent:FireServer("BlockStart")
end

local function stopBlock()
	if not isBlocking then return end
	isBlocking = false
	if not character:GetAttribute("IsStunned") then
		humanoid.WalkSpeed = 16
	end
	if blockTrack then blockTrack:Stop(0.3) end
	SwordHitEvent:FireServer("BlockEnd")
	updateMovement()
end

local function onInputBegan(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.F then
		print("[DBG] F detectado | gameProc=", gameProcessed, " currentWeapon=", currentWeapon, " isSheathing=", isSheathing, " IsStunned=", character and character:GetAttribute("IsStunned"))
	end
	if gameProcessed or not currentWeapon or isSheathing then return end
	if character:GetAttribute("IsStunned") then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attack()
	elseif input.KeyCode == Enum.KeyCode.F then
		startBlock()
	end
end

local function onInputEnded(input)
	if input.KeyCode == Enum.KeyCode.F then
		if isBlocking then stopBlock() end
	end
end

local function cleanupTracks()
	if runningConn    then runningConn:Disconnect();    runningConn = nil    end
	if stunConn       then stunConn:Disconnect();       stunConn = nil       end
	if hitbox and hitbox.HitStop then hitbox:HitStop() end
	hitbox = nil

	if idleTrack     then idleTrack:Stop(0);     idleTrack:Destroy();     idleTrack = nil     end
	if walkTrack     then walkTrack:Stop(0);     walkTrack:Destroy();     walkTrack = nil     end
	if blockTrack    then blockTrack:Stop(0);    blockTrack:Destroy();    blockTrack = nil    end
	if unsheathTrack then unsheathTrack:Stop(0); unsheathTrack:Destroy(); unsheathTrack = nil end
	if sheathTrack   then sheathTrack:Stop(0);   sheathTrack:Destroy();   sheathTrack = nil   end

	for _, t in ipairs(attackTracks) do
		t:Stop(0)
		t:Destroy()
	end
	attackTracks = {}

	if humanoid then
		if not character:GetAttribute("IsStunned") then
			humanoid.WalkSpeed = 16
		end
		humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
		task.defer(function()
			if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Running) end
		end)
	end
end

local function playSheath(onComplete)
	if not sheathTrack then
		if onComplete then onComplete() end
		return
	end

	local gen = equipGeneration -- captura geração; se o player re-equipar, callbacks antigos viram no-op

	isSheathing = true
	canAttack   = false
	stopBlock()

	if idleTrack then idleTrack:Stop(0.1) end
	if walkTrack then walkTrack:Stop(0.1) end

	sheathTrack:Play(0.1)

	local returnConn
	returnConn = sheathTrack:GetMarkerReachedSignal("SheathReturn"):Connect(function()
		if gen ~= equipGeneration then returnConn:Disconnect(); return end
		MoveToScabbard:FireServer()
		returnConn:Disconnect()
	end)

	stopConn = sheathTrack.Stopped:Connect(function()
		stopConn:Disconnect()
		if returnConn then returnConn:Disconnect(); returnConn = nil end

		-- Se a geração mudou (player re-equipou no meio), NÃO mexer no estado novo
		if gen ~= equipGeneration then
			print("[DBG] playSheath.Stopped ORFÃO ignorado (gen=", gen, "atual=", equipGeneration, ")")
			return
		end

		local SheathFinish = Remotes:FindFirstChild("SheathFinish")
		if SheathFinish then SheathFinish:FireServer() end

		isSheathing = false
		cleanupTracks()
		currentWeapon = nil
		weaponModel = nil
		if onComplete then onComplete() end
	end)
end

local function onEquipped(weaponName, model)
	equipGeneration += 1
	currentWeapon = weaponName
	weaponModel   = model

	local animFolder = model:WaitForChild("Animations")
	local atkFolder  = animFolder:WaitForChild("AtkAnimations")

	idleTrack     = animator:LoadAnimation(animFolder:WaitForChild("Idle"))
	walkTrack     = animator:LoadAnimation(animFolder:WaitForChild("Walk"))
	blockTrack    = animator:LoadAnimation(animFolder:WaitForChild("Block"))
	unsheathTrack = animator:LoadAnimation(animFolder:WaitForChild("Unsheath"))
	sheathTrack   = animator:LoadAnimation(animFolder:WaitForChild("Sheath"))

	blockTrack.Priority = Enum.AnimationPriority.Action
	blockTrack.Looped = true
	unsheathTrack.Priority = Enum.AnimationPriority.Action3
	sheathTrack.Priority   = Enum.AnimationPriority.Action3

	attackTracks = {}
	local animObjects = atkFolder:GetChildren()
	table.sort(animObjects, function(a, b) return a.Name < b.Name end)
	for _, animObj in ipairs(animObjects) do
		local track = animator:LoadAnimation(animObj)
		track.Priority = Enum.AnimationPriority.Action4
		table.insert(attackTracks, track)
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch   = false
			part.CanQuery   = false
		end
	end

	local attachmentsHolder = model:WaitForChild("MainPart"):WaitForChild("AttachmentsHolder")
	hitbox = RaycastHitbox.new(attachmentsHolder)
	hitbox.RaycastParams = RaycastParams.new()
	hitbox.RaycastParams.FilterDescendantsInstances = { character }
	hitbox.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude

	hitbox.OnHit:Connect(function(_, targetHumanoid)
		SwordHitEvent:FireServer("AttackConfirmed", currentWeapon, targetHumanoid.Parent)
	end)

	stunConn = character:GetAttributeChangedSignal("IsStunned"):Connect(function()
		if character:GetAttribute("IsStunned") then
			if hitbox then hitbox:HitStop() end
			currentAttack = 1
		else
			if os.clock() >= nextAttackTime then canAttack = true end
			updateMovement()
		end
	end)

	-- CAS bindado no Start, persiste pra sempre (não depende de equip/unequip)
	runningConn    = humanoid.Running:Connect(updateMovement)
	print("[DBG] onEquipped pronto, gen=", equipGeneration)

	isSheathing = true
	canAttack = false
	nextAttackTime = 0
	print("[DBG] onEquipped: setando isSheathing=true, tocando unsheath")

	unsheathTrack:Play(0.1)

	local releaseConn
	releaseConn = unsheathTrack:GetMarkerReachedSignal("SheathRelease"):Connect(function()
		print("[DBG] SheathRelease marker atingido -> isSheathing=false, canAttack=true")
		MoveToHand:FireServer()
		releaseConn:Disconnect()

		isSheathing = false
		local remaining = nextAttackTime - os.clock()
		if remaining <= 0 then
			canAttack = true
		else
			task.delay(remaining, function()
				if os.clock() < nextAttackTime then return end
				if character:GetAttribute("IsStunned") then return end
				canAttack = true
			end)
		end
		updateMovement()
	end)

	local fallbackConn
	fallbackConn = unsheathTrack.Stopped:Connect(function()
		fallbackConn:Disconnect()
		if isSheathing then
			print("[WeaponController] Não achou o marker de release")
			MoveToHand:FireServer()
			isSheathing = false
			grantCanAttack()
			updateMovement()
		end
	end)

	updateMovement()
end

local function bindCharacter(char)
	character = char
	humanoid  = char:WaitForChild("Humanoid")
	animator  = humanoid:WaitForChild("Animator")

	-- reset state
	currentWeapon, weaponModel = nil, nil
	attackTracks = {}
	currentAttack = 1
	canAttack = false
	isBlocking = false
	isSheathing = false
end

-- ─── Lifecycle ───────────────────────────────────────────────────

function WeaponController:Init()
	WeaponRegistry = require(ReplicatedStorage:WaitForChild("WeaponRegistry"))
	RaycastHitbox  = require(ReplicatedStorage:WaitForChild("RaycastHitboxV4"))
	SwordHitEvent  = ReplicatedStorage:WaitForChild("SwordHit")

	Remotes          = ReplicatedStorage:WaitForChild("Remotes")
	WeaponEquipped   = Remotes:WaitForChild("WeaponEquipped")
	WeaponUnequipped = Remotes:WaitForChild("WeaponUnequipped")
	MoveToHand       = Remotes:WaitForChild("MoveToHand")
	MoveToScabbard   = Remotes:WaitForChild("MoveToScabbard")
end

function WeaponController:Start()
	-- Bind via ContextActionService (1x, persiste pra sempre)
	ContextActionService:BindAction("WeaponAttack", function(_, state)
		if state == Enum.UserInputState.Begin then
			print("[CAS] Attack input | currentWeapon=", currentWeapon, " canAttack=", canAttack, " isSheathing=", isSheathing)
			if not currentWeapon or isSheathing then return Enum.ContextActionResult.Pass end
			if character and character:GetAttribute("IsStunned") then return Enum.ContextActionResult.Pass end
			attack()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1)

	ContextActionService:BindAction("WeaponBlock", function(_, state)
		print("[CAS] Block input state=", state, " currentWeapon=", currentWeapon, " canAttack=", canAttack, " isSheathing=", isSheathing)
		if state == Enum.UserInputState.Begin then
			if not currentWeapon or isSheathing then return Enum.ContextActionResult.Pass end
			if character and character:GetAttribute("IsStunned") then return Enum.ContextActionResult.Pass end
			startBlock()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if isBlocking then stopBlock() end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F)

	bindCharacter(player.Character or player.CharacterAdded:Wait())
	player.CharacterAdded:Connect(function(char)
		bindCharacter(char)
	end)

	WeaponEquipped.OnClientEvent:Connect(function(weaponName, model)
		print("[DBG] WeaponEquipped recebido:", weaponName, "| currentWeapon atual=", currentWeapon)
		if currentWeapon then
			equipGeneration += 1
			isSheathing = false
			cleanupTracks()
			currentWeapon = nil
			weaponModel = nil
		end
		onEquipped(weaponName, model)
	end)

	WeaponUnequipped.OnClientEvent:Connect(function()
		print("[DBG] WeaponUnequipped recebido | currentWeapon=", currentWeapon, "isSheathing=", isSheathing)
		if currentWeapon and not isSheathing then
			playSheath(function() end)
		end
	end)
end

return WeaponController
