--[[
	CombatAI
	IA de combate reutilizável que usa o MESMO moveset do player:
	Attack (combo), Block, Parry, Dodge (roll com i-frames).

	Como funciona o espelhamento com o player:
	- O HitService.processCombat lê os atributos DO ALVO quando ele é atingido
	  (ParryWindow / IsBlocking / IFrames). Então, setando esses atributos no NPC,
	  o parry/block/dodge dele funcionam automaticamente contra o player.
	- Pra atacar o player, o NPC dispara NPCHit (BindableEvent) via hitbox, igual
	  ao DummyAi original. O HitService processa do mesmo jeito que o ataque do player.

	Uso (de um Script dentro do modelo do NPC):
		local CombatAI = require(path.to.CombatAI)
		CombatAI.new(script.Parent, {
			Profile = "Normal" | "Boss",
			-- overrides opcionais (ver DEFAULTS abaixo)
		})
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage     = game:GetService("ServerStorage")

local RaycastHitbox = require(ReplicatedStorage:WaitForChild("RaycastHitboxV4"))
local NPCHit        = ServerScriptService:WaitForChild("NPCHit")

local KATANA_ANIMS  = ServerStorage:WaitForChild("Weapons"):WaitForChild("Katana"):WaitForChild("Animations")

local CombatAI = {}
CombatAI.__index = CombatAI

-- ─── Perfis ───────────────────────────────────────────────────

local DEFAULTS = {
	WeaponName     = "Katana",
	WalkSpeed      = 14,
	DetectRange    = 60,    -- começa a perseguir
	AttackRange    = 6,     -- distância pra atacar
	AttackCooldown = 1.4,   -- entre combos

	-- Pesos de reação (não precisam somar 1; são pesos relativos entre as
	-- opções DISPONÍVEIS no momento). Se uma opção está em cooldown, sai do sorteio.
	ParryWeight    = 0.30,
	BlockWeight    = 0.45,
	DodgeWeight    = 0.25,
	ReactChance    = 0.75,  -- chance de reagir a um golpe (resto = toma o hit)

	-- Comportamento ofensivo / ritmo
	Aggression     = 0.65,  -- 0..1: quão frequentemente parte pra cima vs espera
	StrafeSpeed    = 1.0,    -- multiplicador de velocidade ao rondar
	SpacingRange   = 8,      -- distância que tenta manter ao rondar (perto do alcance)
	PunishChance   = 0.85,   -- chance de punir quando vê o player vulnerável
	BaitChance     = 0.15,   -- chance de fingir aproximação pra induzir seu ataque
	PostAttackBackoff = 0.4, -- recua um tico depois de um combo (vulnerável)
	DecisionGap    = 0.4,    -- tempo entre decisões de comportamento (s)

	-- Cooldowns próprios da IA
	ParryCooldown  = 1.6,   -- após tentar um parry (acertando ou errando)
	DodgeCooldown  = 1.2,   -- após um dodge
	ReactMinGap    = 0.25,  -- intervalo mínimo entre reações (anti-spam)

	-- Timing do parry: quão preciso a IA é em segurar a janela no golpe.
	ReactionDelay  = 0.10,  -- atraso humano antes de começar a reagir (s)
	ParryHold      = 0.45,  -- quanto tempo mantém ParryWindow aberta (cobre a chegada do golpe)
	MissChance     = 0.20,  -- chance de errar o timing do parry de propósito (abre tarde)
	ComboMax       = 2,     -- quantos hits seguidos por investida

	MaxHealth      = 100,
	PostureMax     = 100,
}

local PROFILES = {
	Normal = {
		-- usa os defaults
	},
	Boss = {
		WalkSpeed      = 17,
		DetectRange    = 90,
		AttackRange    = 7,
		AttackCooldown = 1.0,
		ParryWeight    = 0.45,
		BlockWeight    = 0.30,
		DodgeWeight    = 0.25,
		ReactChance    = 0.90,
		Aggression     = 0.8,
		StrafeSpeed    = 1.15,
		SpacingRange   = 9,
		PunishChance   = 0.95,
		BaitChance     = 0.2,
		PostAttackBackoff = 0.3,
		DecisionGap    = 0.3,
		ParryCooldown  = 1.1,
		DodgeCooldown  = 0.9,
		ReactionDelay  = 0.07,
		ParryHold      = 0.40,
		MissChance     = 0.10,
		ComboMax       = 3,
		MaxHealth      = 350,
		PostureMax     = 150,
	},
}

-- ─── Constructor ──────────────────────────────────────────────

function CombatAI.new(model, config)
	config = config or {}
	local profileName = config.Profile or "Normal"
	local profile = PROFILES[profileName] or PROFILES.Normal

	local self = setmetatable({}, CombatAI)

	-- merge: DEFAULTS <- profile <- config
	self.cfg = {}
	for k, v in pairs(DEFAULTS)        do self.cfg[k] = v end
	for k, v in pairs(profile)         do self.cfg[k] = v end
	for k, v in pairs(config)          do self.cfg[k] = v end

	self.model     = model
	self.humanoid  = model:WaitForChild("Humanoid")
	self.root      = model:WaitForChild("HumanoidRootPart")
	self.animator  = self.humanoid:WaitForChild("Animator")
	self.profileName = profileName

	self.currentAttack = 1
	self.lastAttack    = 0
	self.busy          = false   -- reagindo (parry/block/dodge) ou atacando
	self.reacting      = false   -- trava pra não empilhar reações no mesmo golpe
	self.alive         = true

	-- Cooldowns próprios da IA (timestamps os.clock em que ficam prontos de novo)
	self.parryReadyAt  = 0
	self.dodgeReadyAt  = 0
	self.lastReactAt   = 0

	self:_setup()
	return self
end

-- ─── Setup interno ───────────────────────────────────────────

function CombatAI:_loadAnim(animObj, priority, looped)
	if not animObj then return nil end
	local track = self.animator:LoadAnimation(animObj)
	track.Priority = priority or Enum.AnimationPriority.Action
	track.Looped = looped or false
	return track
end

function CombatAI:_setup()
	local model = self.model
	local hum   = self.humanoid

	hum.WalkSpeed   = self.cfg.WalkSpeed
	hum.MaxHealth   = self.cfg.MaxHealth
	hum.Health      = self.cfg.MaxHealth

	model:SetAttribute("Posture", self.cfg.PostureMax)
	model:SetAttribute("State", "Idle")
	model:SetAttribute("IsStunned", false)
	model:SetAttribute("IsBlocking", false)
	model:SetAttribute("ParryWindow", false)
	model:SetAttribute("IFrames", false)

	-- Equipa a espada (Motor6D na mão), igual ao DummyAi
	self.weaponModel = model:FindFirstChild(self.cfg.WeaponName)
	if self.weaponModel then
		self:_equipWeapon()
		local mainPart = self.weaponModel:FindFirstChild("MainPart")
		local holder = mainPart and mainPart:FindFirstChild("AttachmentsHolder")
		if holder then
			self.hitbox = RaycastHitbox.new(holder)
			self.hitbox.RaycastParams = RaycastParams.new()
			self.hitbox.RaycastParams.FilterDescendantsInstances = { model }
			self.hitbox.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
			self.hitbox.OnHit:Connect(function(_, targetHum)
				local targetChar = targetHum and targetHum.Parent
				if targetChar then
					NPCHit:Fire(model, self.cfg.WeaponName, targetChar)
				end
			end)
		end
	else
		warn(("[CombatAI] %s não tem o modelo da arma '%s'"):format(model.Name, self.cfg.WeaponName))
	end

	-- Carrega anims
	local atkFolder = nil
	local animFolder = model:FindFirstChild("Animations")
	if animFolder then atkFolder = animFolder:FindFirstChild("AtkAnimations") end

	self.attackTracks = {}
	if atkFolder then
		local objs = atkFolder:GetChildren()
		table.sort(objs, function(a, b) return a.Name < b.Name end)
		for _, o in ipairs(objs) do
			table.insert(self.attackTracks, self:_loadAnim(o, Enum.AnimationPriority.Action4, false))
		end
	end

	-- Anims compartilhadas da Katana (Block, Parry, Roll, GotHit)
	self.blockTrack  = self:_loadAnim(KATANA_ANIMS:FindFirstChild("Block"), Enum.AnimationPriority.Action, true)
	self.parryTrackR = self:_loadAnim(KATANA_ANIMS:FindFirstChild("Parry_R"), Enum.AnimationPriority.Action4, false)
	self.parryTrackL = self:_loadAnim(KATANA_ANIMS:FindFirstChild("Parry_L"), Enum.AnimationPriority.Action4, false)
	self.rollTrack   = self:_loadAnim(KATANA_ANIMS:FindFirstChild("Roll"), Enum.AnimationPriority.Action3, false)

	-- Morte/reset
	hum.Died:Connect(function() self:_onDied() end)

	-- Loop principal
	task.spawn(function() self:_aiLoop() end)
end

function CombatAI:_equipWeapon()
	local model = self.model
	local rightHand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	local mainPart  = self.weaponModel:FindFirstChild("MainPart")
	if not rightHand or not mainPart then return end

	mainPart.CanCollide = false
	mainPart.Massless   = true

	local handAttach = rightHand:FindFirstChild("KatanaHandAttach")
	if not handAttach then
		handAttach = Instance.new("Attachment")
		handAttach.Name = "KatanaHandAttach"
		handAttach.CFrame = CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(90), math.rad(180), 0)
		handAttach.Parent = rightHand
	end

	local katanaAttach = mainPart:FindFirstChild("KatanaAttach")
	if not katanaAttach then return end

	local existing = mainPart:FindFirstChild("WeaponGrip")
	if existing then existing:Destroy() end

	local motor = Instance.new("Motor6D")
	motor.Name = "WeaponGrip"
	motor.Part0 = rightHand
	motor.Part1 = mainPart
	motor.C0 = handAttach.CFrame
	motor.C1 = katanaAttach.CFrame
	motor.Parent = mainPart
end

-- ─── Ações ──────────────────────────────────────────────────

function CombatAI:_canAct()
	return self.alive
		and self.humanoid.Health > 0
		and not self.model:GetAttribute("IsStunned")
		and not self.busy
end

-- Miolo do ataque (toca anim + hitbox). NÃO gerencia self.busy.
function CombatAI:_doSwing()
	self.model:SetAttribute("State", "Attacking")

	local track = self.attackTracks[self.currentAttack]
	if track then
		local startConn, endConn, stopConn
		startConn = track:GetMarkerReachedSignal("HitStart"):Connect(function()
			if self.hitbox then self.hitbox:HitStart() end
			startConn:Disconnect()
		end)
		endConn = track:GetMarkerReachedSignal("HitEnd"):Connect(function()
			if self.hitbox then self.hitbox:HitStop() end
			endConn:Disconnect()
		end)
		stopConn = track.Stopped:Connect(function()
			if self.hitbox then self.hitbox:HitStop() end
			if startConn then startConn:Disconnect() end
			if endConn then endConn:Disconnect() end
			stopConn:Disconnect()
		end)
		track:Play(0.05)
	end

	self.currentAttack += 1
	if self.currentAttack > #self.attackTracks then self.currentAttack = 1 end

	task.wait(0.5)
	if self.model:GetAttribute("State") == "Attacking" then
		self.model:SetAttribute("State", "Idle")
	end
end

-- Ataque único standalone (gerencia busy). Usado fora do _pressure se preciso.
function CombatAI:_attack()
	if not self:_canAct() then return end
	self.busy = true
	local ok, err = pcall(function() self:_doSwing() end)
	if not ok then warn("[CombatAI] _attack erro:", err) end
	self.busy = false
end

-- Block: segura o block por um tempo (deflete dano, mas custa postura).
function CombatAI:_block(duration)
	if not self:_canAct() then return end
	self.busy = true
	self.model:SetAttribute("IsBlocking", true)
	if self.blockTrack then self.blockTrack:Play(0.15) end

	task.wait(duration or 0.6)

	self.model:SetAttribute("IsBlocking", false)
	if self.blockTrack then self.blockTrack:Stop(0.2) end
	self.busy = false
end

-- Parry: abre a janela ParryWindow sincronizada com a chegada do golpe.
-- A IA segura a janela aberta por ParryHold (cobrindo a incerteza de quando o
-- golpe conecta). Com MissChance, abre tarde de propósito (erra o timing).
function CombatAI:_parry()
	if not self:_canAct() then return end
	self.busy = true
	self.parryReadyAt = os.clock() + self.cfg.ParryCooldown

	-- Animação de parry (visual)
	local pt = (self.parryTrackR and self.parryTrackL)
		and ({self.parryTrackR, self.parryTrackL})[math.random(1,2)]
		or self.parryTrackR or self.parryTrackL
	if pt then pt:Play(0.1) end

	self.model:SetAttribute("IsBlocking", true)

	-- Chance de errar o timing: abre a janela tarde demais (golpe já passou).
	local mistimed = math.random() < self.cfg.MissChance
	if mistimed then
		task.wait(0.35) -- abre tarde -> provavelmente toma o hit ou só bloqueia
	end

	self.model:SetAttribute("ParryWindow", true)
	task.wait(self.cfg.ParryHold)  -- mantém a janela aberta cobrindo o golpe
	self.model:SetAttribute("ParryWindow", false)

	task.wait(0.15)
	self.model:SetAttribute("IsBlocking", false)
	self.busy = false
end

-- Dodge: roll com i-frames. Durante IFrames, processCombat ignora o hit por completo.
function CombatAI:_dodge()
	if not self:_canAct() then return end
	self.busy = true
	self.dodgeReadyAt = os.clock() + self.cfg.DodgeCooldown
	self.model:SetAttribute("State", "Dodging")
	self.model:SetAttribute("IFrames", true)

	if self.rollTrack then self.rollTrack:Play(0.1) end

	-- Empurrão pra trás/lado pra simular esquiva
	local dir = (math.random() < 0.5) and self.root.CFrame.RightVector or -self.root.CFrame.LookVector
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1,0,1) * 1e5
	bv.Velocity = dir * 28
	bv.Parent = self.root
	game:GetService("Debris"):AddItem(bv, 0.25)

	task.wait(0.35)
	self.model:SetAttribute("IFrames", false)
	self.model:SetAttribute("State", "Idle")
	self.busy = false
end

-- Escolhe e executa uma reação defensiva, respeitando cooldowns próprios.
-- Chamado quando o player entra em Attacking dentro do alcance.
function CombatAI:_react()
	if not self:_canAct() then return end
	if self.reacting then return end -- já reagindo a este golpe

	local now = os.clock()
	if (now - self.lastReactAt) < self.cfg.ReactMinGap then return end

	-- Sorteia se reage ou toma o hit
	if math.random() > self.cfg.ReactChance then return end

	self.reacting = true
	self.lastReactAt = now

	-- Monta as opções DISPONÍVEIS (respeitando cooldown)
	local options = {}
	if now >= self.parryReadyAt then
		table.insert(options, { kind = "parry", weight = self.cfg.ParryWeight })
	end
	table.insert(options, { kind = "block", weight = self.cfg.BlockWeight }) -- block nunca tem cooldown
	if now >= self.dodgeReadyAt then
		table.insert(options, { kind = "dodge", weight = self.cfg.DodgeWeight })
	end

	-- Sorteio ponderado entre as disponíveis
	local total = 0
	for _, o in ipairs(options) do total += o.weight end
	local pick = math.random() * total
	local chosen
	local acc = 0
	for _, o in ipairs(options) do
		acc += o.weight
		if pick <= acc then chosen = o.kind; break end
	end

	-- Atraso de reação humano, depois executa
	task.wait(self.cfg.ReactionDelay)

	if chosen == "parry" then
		self:_parry()
	elseif chosen == "dodge" then
		self:_dodge()
	else
		self:_block(0.7)
	end

	self.reacting = false
end

-- ─── Percepção ──────────────────────────────────────────────

function CombatAI:_nearestPlayer()
	local best, bestDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local d = (root.Position - self.root.Position).Magnitude
			if d < bestDist then best, bestDist = char, d end
		end
	end
	return best, bestDist
end

-- ─── Movimento tático ────────────────────────────────────────

-- Roda o NPC pra encarar o alvo SEM teleportar (interpola o CFrame suavemente).
-- Não usa AutoRotate aqui porque quando está parado o Humanoid não rotaciona.
function CombatAI:_faceTarget(targetRoot)
	local myPos = self.root.Position
	local lookAt = Vector3.new(targetRoot.Position.X, myPos.Y, targetRoot.Position.Z)
	if (lookAt - myPos).Magnitude < 0.1 then return end
	local goal = CFrame.lookAt(myPos, lookAt)
	-- interpola (não seta direto) pra não dar aquele "snap"/teleporte de rotação
	self.root.CFrame = self.root.CFrame:Lerp(goal, 0.25)
end

-- Ronda o player mantendo distância (strafe lateral + ajuste de espaçamento).
-- Movimento é 100% via Humanoid:Move (respeita física, sem teleporte).
function CombatAI:_strafe(targetRoot)
	local toTarget = (targetRoot.Position - self.root.Position)
	local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	local dist = flatDir.Magnitude
	if dist < 0.1 then self.humanoid:Move(Vector3.zero); return end
	flatDir = flatDir.Unit

	local right = Vector3.new(-flatDir.Z, 0, flatDir.X)

	local lateral = right * self._strafeDir
	local radial = Vector3.zero
	if dist > self.cfg.SpacingRange + 1.5 then
		radial = flatDir            -- longe: aproxima um tico
	elseif dist < self.cfg.SpacingRange - 1.5 then
		radial = -flatDir           -- perto demais: afasta
	end

	local moveDir = (lateral * 0.7 + radial)
	if moveDir.Magnitude > 0.01 then
		self.humanoid:Move(moveDir.Unit, false)
	else
		self.humanoid:Move(flatDir * 0, false)
	end
end

function CombatAI:_backoff(targetRoot, duration)
	local toTarget = (targetRoot.Position - self.root.Position)
	local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flatDir.Magnitude > 0.1 then
		self.humanoid:Move(-flatDir.Unit, false)
	end
	task.wait(duration or 0.3)
	self.humanoid:Move(Vector3.zero)
end

-- Lê o estado do player pra detectar aberturas pra punir.
function CombatAI:_targetVulnerable(targetChar)
	if not targetChar then return false end
	if targetChar:GetAttribute("IsStunned") then return true end       -- stunado: punição garantida
	if targetChar:GetAttribute("OnParryCD") then return true end       -- parry queimado: guarda travada
	local st = targetChar:GetAttribute("State")
	if st == "Attacking" then return true end                          -- comprometido no golpe
	return false
end

-- Avança até ficar dentro do alcance de ataque (com timeout pra não travar).
-- Retorna true se chegou no alcance, false se desistiu.
function CombatAI:_closeIn(targetRoot, timeout)
	local deadline = os.clock() + (timeout or 1.2)
	while os.clock() < deadline do
		if not self.alive or self.humanoid.Health <= 0 then return false end
		if self.model:GetAttribute("IsStunned") then return false end
		local toTarget = (targetRoot.Position - self.root.Position)
		local dist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
		if dist <= self.cfg.AttackRange then
			self.humanoid:Move(Vector3.zero)
			return true
		end
		self.humanoid:Move(Vector3.new(toTarget.X, 0, toTarget.Z).Unit, false)
		task.wait(0.06)
	end
	return false
end

-- Investida ofensiva: fecha a distância, combo de 1..ComboMax, recua depois.
function CombatAI:_pressure(targetRoot)
	self.busy = true
	local ok = pcall(function()
		-- 1) fecha até o alcance
		local reached = self:_closeIn(targetRoot, 1.2)
		if not reached then return end

		-- 2) combo
		local hits = math.random(1, self.cfg.ComboMax)
		for _ = 1, hits do
			if self.model:GetAttribute("IsStunned") or self.humanoid.Health <= 0 then break end
			-- se o player se afastou, dá um passo pra dentro de novo
			local d = (targetRoot.Position - self.root.Position)
			if Vector3.new(d.X,0,d.Z).Magnitude > self.cfg.AttackRange + 1 then
				self:_closeIn(targetRoot, 0.4)
			end
			self:_faceTarget(targetRoot)
			-- _attack gerencia o próprio busy, mas aqui já estamos busy; chama o core direto
			self:_doSwing()
			task.wait(0.12)
		end
	end)
	if not ok then warn("[CombatAI] _pressure erro") end

	self.busy = false

	-- 3) recuo opcional (janela pra revidar)
	if math.random() < 0.6 and self.alive then
		self:_backoff(targetRoot, self.cfg.PostAttackBackoff)
	end
end

function CombatAI:_aiLoop()
	local targetChar
	self._strafeDir = (math.random() < 0.5) and 1 or -1
	local nextDecision = 0
	local nextStrafeFlip = 0

	-- Detector de ataque do player: escuta o SwordHit (cada "Attack" é um telegraph
	-- de golpe). Mais confiável que observar mudança de State, porque combos
	-- disparam vários "Attack" sem o State necessariamente mudar de valor.
	local SwordHit = ReplicatedStorage:FindFirstChild("SwordHit")
	if SwordHit and not self._swordConn then
		self._swordConn = SwordHit.OnServerEvent:Connect(function(player, action)
			if action ~= "Attack" then return end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local d = (root.Position - self.root.Position).Magnitude
			if d <= self.cfg.AttackRange + 4 then
				task.spawn(function() self:_react() end)
			end
		end)
	end

	while self.alive and self.humanoid.Health > 0 and self.model.Parent do
		task.wait(0.08)
		if self.model:GetAttribute("IsStunned") then
			self.humanoid:Move(Vector3.zero)
			continue
		end
		if self.busy then
			continue
		end -- reagindo/atacando: a corrotina controla o movimento

		local char, dist = self:_nearestPlayer()
		targetChar = char
		if not char then
			self.humanoid:Move(Vector3.zero)
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local now = os.clock()

		-- Longe demais pra qualquer tática: persegue direto.
		if dist > self.cfg.DetectRange then
			self.humanoid:Move(Vector3.zero)
			continue
		end
		if dist > self.cfg.SpacingRange + 6 then
			self.humanoid:MoveTo(root.Position)
			self:_faceTarget(root)
			continue
		end

		-- 1) PUNIÇÃO: viu o player vulnerável e perto -> investe já (fecha distância).
		if self:_targetVulnerable(char)
			and dist <= self.cfg.SpacingRange + 4
			and math.random() < self.cfg.PunishChance
			and self:_canAct() then
			self.lastAttack = now
			task.spawn(function() self:_pressure(root) end)
			nextDecision = now + self.cfg.DecisionGap
			continue
		end

		-- Inverte a direção do strafe de vez em quando (movimento orgânico)
		if now >= nextStrafeFlip then
			if math.random() < 0.4 then self._strafeDir = -self._strafeDir end
			nextStrafeFlip = now + math.random(8, 16) / 10
		end

		-- 2) DECISÃO de comportamento a cada DecisionGap.
		if now >= nextDecision then
			nextDecision = now + self.cfg.DecisionGap

			-- "engajamento": perto o bastante pra valer a pena investir (o _pressure
			-- fecha o resto da distância sozinho via _closeIn). NÃO exige estar já
			-- dentro do AttackRange, senão ele nunca sai do strafe.
			local canEngage = dist <= self.cfg.SpacingRange + 4
			local attackReady = (now - self.lastAttack) >= self.cfg.AttackCooldown

			if canEngage and attackReady and self:_canAct() then
				local roll = math.random()
				if roll < self.cfg.Aggression then
					-- Parte pra cima (fecha distância + combo)
					self.lastAttack = now
					task.spawn(function() self:_pressure(root) end)
				elseif roll < self.cfg.Aggression + self.cfg.BaitChance then
					-- BAIT: recua um tico tentando te induzir a atacar no vazio
					task.spawn(function() self:_backoff(root, 0.3) end)
				else
					-- Espera/ronda
					self:_strafe(root)
				end
			else
				-- Em cooldown ou longe: ronda mantendo espaçamento
				self:_strafe(root)
			end
		else
			-- Entre decisões: continua rondando suavemente
			self:_strafe(root)
		end
	end
end

-- ─── Morte / reset ──────────────────────────────────────────

function CombatAI:_onDied()
	if self.hitbox then self.hitbox:HitStop() end
	self.busy = true
	task.wait(4)
	if self.model and self.model.Parent then
		self.humanoid.Health = self.cfg.MaxHealth
		self.humanoid.WalkSpeed = self.cfg.WalkSpeed
		self.model:SetAttribute("State", "Idle")
		self.model:SetAttribute("IsStunned", false)
		self.model:SetAttribute("IsBlocking", false)
		self.model:SetAttribute("ParryWindow", false)
		self.model:SetAttribute("IFrames", false)
		self.model:SetAttribute("Posture", self.cfg.PostureMax)
		self.busy = false
	end
end

return CombatAI
