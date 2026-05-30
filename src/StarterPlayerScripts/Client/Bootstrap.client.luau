--[[
	Client Bootstrap
	Carrega todos os Controllers e roda seus lifecycles (Init -> Start).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Loader"))

local Controllers = script.Parent:WaitForChild("Controllers")

print("[Bootstrap/Client] Iniciando...")
Loader.LoadFolder(Controllers)
print("[Bootstrap/Client] Pronto")
