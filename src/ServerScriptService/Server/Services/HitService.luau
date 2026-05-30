--[[
	HitService
	Processa combate (player vs player, NPC vs player, etc).
	Era: ServerScriptService.HitServer

	Interfaces externas mantidas:
		- RemoteEvent: ReplicatedStorage.SwordHit (player -> server)
		- BindableEvent: ServerScriptService.NPCHit (criado/mantido aqui pros NPCs)

	Novo:
		- Signal: HitService.NPCHit  (mesmo evento, em Signal nativo, pra novo código)
--]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris              = game:GetService("Debris")

local Shared  = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Net     = require(Shared:WaitForChild("Net"))
local Signal  = require(Shared:WaitForChild("Signal"))

local HitService = {}

-- Signal exposto pra novos services que quiserem disparar combate de NPC
HitService.NPCHit = Signal.new()

local RECOIL_ANIM_ID = 137757449633828
local PARRY_ANIMS    = {121138324921103, 132553186957346}

local WeaponSettings
local HitEffectPrefab, ParryEffectPrefab, BlockEffectPrefab, Sounds
local SwordHitEvent
local NPCHitBindable

-- ─── Helpers ─────────────────────────────────────────────────

local function playAnim(humanoid, animId, speed)
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.1)
	track:AdjustSpeed(speed or 1)
	track.Stopped:Connect(function()
		track:Destroy()
		anim:Destroy()
	end)
	return track
end

local function playVisualEffect(targetChar, prefab, emitCount, isBlood)
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not prefab then return end
	local effectClone = prefab:Clone()
	effectClone.Parent = workspace
	local offset = isBlood and 0 or -1.2
	effectClone.CFrame = targetRoot.CFrame * CFrame.new(0, 0, offset)
	for _, d in ipairs(effectClone:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			task.delay(0.02, function() d:Emit(emitCount or 15) end)
		end
	end
	Debris:AddItem(effectClone, 3)
end

local function playSound(soundName, positionPart)
	local soundPrefab = Sounds:FindFirstChild(soundName)
	if soundPrefab and positionPart then
		local s = soundPrefab:Clone()
		s.Parent = positionPart
		s:Play()
		Debris:AddItem(s, s.TimeLength + 0.1)
	end
end

local function applyStun(char, duration, speed)
	char:SetAttribute("State", "Stunned")
	char:SetAttribute("IsStunned", true)
	local hum = char:FindFirstChild("Humanoid")
	if hum then hum.WalkSpeed = speed or 6 end
	task.delay(duration, function()
		if char and char.Parent and char:GetAttribute("IsStunned") == true then
			char:SetAttribute("State", "Idle")
			char:SetAttribute("IsStunned", false)
			if hum then hum.WalkSpeed = 16 end
		end
	end)
end

-- ─── Combat Core (NPC + Player share this) ────────────────────

local function processCombat(attackerChar, weaponName, target)
	if not target or not target:IsA("Model") then return end

	local targetHum  = target:FindFirstChild("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetHum or not targetRoot or targetHum.Health <= 0 then return end

	local stats      = WeaponSettings[weaponName] or { Damage = 10, PostureDamage = 20 }
	local isParrying = target:GetAttribute("ParryWindow")
	local isBlocking = target:GetAttribute("IsBlocking")

	if isParrying then
		playVisualEffect(target, ParryEffectPrefab, 15)
		playSound("Parried", targetRoot)

		local attackerHum = attackerChar:FindFirstChildOfClass("Humanoid")
		if attackerHum then
			local animator = attackerHum:FindFirstChildOfClass("Animator")
			if animator then
				for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
					if t.Priority == Enum.AnimationPriority.Action or t.Priority == Enum.AnimationPriority.Action4 then
						t:Stop(0.1)
					end
				end
			end
			playAnim(attackerHum, RECOIL_ANIM_ID, 1)
		end

		playAnim(targetHum, PARRY_ANIMS[math.random(1, #PARRY_ANIMS)], 1.5)
		applyStun(attackerChar, 1.5, 2)
		return
	end

	if isBlocking then
		local posture = target:GetAttribute("Posture") or 100
		posture = math.max(0, posture - stats.PostureDamage)
		target:SetAttribute("Posture", posture)

		playVisualEffect(target, BlockEffectPrefab, 5)
		playSound("BlockedHit", targetRoot)

		if posture <= 0 then
			target:SetAttribute("Posture", 100)
			playSound("Guardbreak", targetRoot)
			applyStun(target, 2.5, 0)
		else
			targetHum:TakeDamage(stats.Damage * 0.2)
			playAnim(targetHum, stats.HitAnim or 76890570463381, 1.2)
		end
		return
	end

	-- Hit
	targetHum:TakeDamage(stats.Damage)
	if attackerChar then
		attackerChar:SetAttribute("Posture", math.min((attackerChar:GetAttribute("Posture") or 100) + 5, 100))
	end
	playVisualEffect(target, HitEffectPrefab, 12, true)
	playSound("Hit1", targetRoot)
	playAnim(targetHum, stats.HitAnim or 76890570463381, 1)
	applyStun(target, 0.4, 4)
end

-- ─── Handlers ────────────────────────────────────────────────

local function onPlayerEvent(player, action, weaponName, target)
	local character = player.Character
	if not character or character:GetAttribute("IsStunned") then return end

	if action == "Attack" then
		character:SetAttribute("State", "Attacking")
		local stats = WeaponSettings[weaponName]
		if stats then
			local cooldown = stats.Cooldown / stats.SwingSpeed
			task.delay(cooldown, function()
				if character and character.Parent and character:GetAttribute("State") == "Attacking" then
					character:SetAttribute("State", "Idle")
				end
			end)
		end
		return
	elseif action == "BlockStart" then
		character:SetAttribute("IsBlocking", true)
		character:SetAttribute("ParryWindow", true)
		task.delay(0.30, function()
			if character and character.Parent then
				character:SetAttribute("ParryWindow", false)
			end
		end)
		return
	elseif action == "BlockEnd" then
		character:SetAttribute("IsBlocking", false)
		return
	elseif action == "AttackConfirmed" then
		processCombat(character, weaponName, target)
	end
end

local function onNPCHit(attackerChar, weaponName, target)
	if not attackerChar or attackerChar:GetAttribute("IsStunned") then return end
	processCombat(attackerChar, weaponName, target)
end

-- ─── Lifecycle ───────────────────────────────────────────────

function HitService:Init()
	WeaponSettings = require(ReplicatedStorage:WaitForChild("WeaponRegistry"))
	HitEffectPrefab = ServerStorage:WaitForChild("HitEffect")
	ParryEffectPrefab = ServerStorage:WaitForChild("ParryEffect")
	BlockEffectPrefab = ServerStorage:WaitForChild("BlockEffect")
	Sounds = ServerStorage:WaitForChild("Sounds")

	-- SwordHit historicamente fica direto em ReplicatedStorage (não em Remotes/).
	-- Mantemos lá pra não quebrar referências antigas.
	SwordHitEvent = ReplicatedStorage:FindFirstChild("SwordHit")
	if not SwordHitEvent then
		SwordHitEvent = Instance.new("RemoteEvent")
		SwordHitEvent.Name = "SwordHit"
		SwordHitEvent.Parent = ReplicatedStorage
	end

	-- BindableEvent que os Dummys/NPCs procuram com :WaitForChild("NPCHit")
	NPCHitBindable = ServerScriptService:FindFirstChild("NPCHit")
	if not NPCHitBindable or not NPCHitBindable:IsA("BindableEvent") then
		NPCHitBindable = Instance.new("BindableEvent")
		NPCHitBindable.Name = "NPCHit"
		NPCHitBindable.Parent = ServerScriptService
	end
end

function HitService:Start()
	SwordHitEvent.OnServerEvent:Connect(onPlayerEvent)
	NPCHitBindable.Event:Connect(onNPCHit)
	HitService.NPCHit:Connect(onNPCHit) -- novo Signal espelhado
end

return HitService
