--[[
	Net
	Wrapper de RemoteEvents/RemoteFunctions.
	Server: cria os remotes em ReplicatedStorage/Remotes sob demanda.
	Client: espera os remotes existirem.

	API Server:
		Net:FireClient(name, player, ...)
		Net:FireAllClients(name, ...)
		Net:FireClientsExcept(name, excludedPlayer, ...)
		Net:OnServerEvent(name, callback) -> Connection
		Net:OnServerInvoke(name, callback)

	API Client:
		Net:FireServer(name, ...)
		Net:InvokeServer(name, ...)
		Net:OnClientEvent(name, callback) -> Connection

	Comum:
		Net:GetEvent(name)    -> RemoteEvent
		Net:GetFunction(name) -> RemoteFunction
--]]

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

local function ensureFolder()
	local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if f then return f end
	if IS_SERVER then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = ReplicatedStorage
		return f
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
end

local remotesFolder = ensureFolder()
local cache = {}

local function get(name, className)
	assert(type(name) == "string", "[Net] name deve ser string")
	className = className or "RemoteEvent"

	local cached = cache[name]
	if cached and cached:IsA(className) then return cached end

	local r = remotesFolder:FindFirstChild(name)
	if r and not r:IsA(className) then
		warn(("[Net] Remote '%s' existe mas classe diferente esperada (%s vs %s)"):format(name, r.ClassName, className))
	end

	if not r then
		if IS_SERVER then
			r = Instance.new(className)
			r.Name = name
			r.Parent = remotesFolder
		else
			r = remotesFolder:WaitForChild(name, 10)
			if not r then
				error(("[Net] Remote '%s' não apareceu em 10s"):format(name), 2)
			end
		end
	end

	cache[name] = r
	return r
end

local Net = {}

function Net:GetEvent(name)
	return get(name, "RemoteEvent")
end

function Net:GetFunction(name)
	return get(name, "RemoteFunction")
end

if IS_SERVER then
	function Net:FireClient(name, player, ...)
		get(name, "RemoteEvent"):FireClient(player, ...)
	end

	function Net:FireAllClients(name, ...)
		get(name, "RemoteEvent"):FireAllClients(...)
	end

	function Net:FireClientsExcept(name, excluded, ...)
		local r = get(name, "RemoteEvent")
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= excluded then
				r:FireClient(plr, ...)
			end
		end
	end

	function Net:OnServerEvent(name, callback)
		return get(name, "RemoteEvent").OnServerEvent:Connect(callback)
	end

	function Net:OnServerInvoke(name, callback)
		get(name, "RemoteFunction").OnServerInvoke = callback
	end
else
	function Net:FireServer(name, ...)
		get(name, "RemoteEvent"):FireServer(...)
	end

	function Net:InvokeServer(name, ...)
		return get(name, "RemoteFunction"):InvokeServer(...)
	end

	function Net:OnClientEvent(name, callback)
		return get(name, "RemoteEvent").OnClientEvent:Connect(callback)
	end
end

return Net
