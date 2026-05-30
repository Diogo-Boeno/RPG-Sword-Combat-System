local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Loader"))

local Services = script.Parent:WaitForChild("Services")

Loader.LoadFolder(Services)
