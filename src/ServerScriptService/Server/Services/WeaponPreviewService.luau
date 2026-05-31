--[[
	WeaponPreviewService
	Clona os modelos visuais das armas (ServerStorage/Weapons) para
	ReplicatedStorage/WeaponPreviews, pra que o client consiga mostrá-los nos
	ViewportFrames do hotbar. O client NÃO acessa ServerStorage, por isso a cópia.

	Os clones são só visuais: sem Scabbard, sem Animations, sem scripts,
	com tudo Anchored (ViewportFrame não tem física).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local WeaponPreviewService = {}

local IGNORED = {
	Scabbard   = true,
	Animations = true,
}

local function buildPreview(template)
	local model = Instance.new("Model")
	model.Name = template.Name

	for _, child in ipairs(template:GetChildren()) do
		if not IGNORED[child.Name]
			and not child:IsA("LuaSourceContainer") -- Script/LocalScript/ModuleScript
		then
			child:Clone().Parent = model
		end
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored     = true
			d.CanCollide   = false
			d.CanQuery     = false
			d.CanTouch     = false
			d.Transparency = 0
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end

	local mainPart = model:FindFirstChild("MainPart")
	if mainPart and mainPart:IsA("BasePart") then
		model.PrimaryPart = mainPart
	end

	return model
end

function WeaponPreviewService:Init()
	local weaponsFolder = ServerStorage:WaitForChild("Weapons")

	local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
	if previews then previews:Destroy() end
	previews = Instance.new("Folder")
	previews.Name = "WeaponPreviews"

	for _, template in ipairs(weaponsFolder:GetChildren()) do
		if template:IsA("Model") or template:IsA("Folder") then
			local ok, preview = pcall(buildPreview, template)
			if ok and preview then
				preview.Parent = previews
			else
				warn(("[WeaponPreviewService] Falha ao gerar preview de %s: %s")
					:format(template.Name, tostring(preview)))
			end
		end
	end

	previews.Parent = ReplicatedStorage
end

return WeaponPreviewService
