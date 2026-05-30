local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Loader"))

local Services = script.Parent:WaitForChild("Services")

print("[Bootstrap/Server] Iniciando...")
Loader.LoadFolder(Services)
print("[Bootstrap/Server] Pronto")
