--[[
	Loader
	Carrega todos os ModuleScripts (recursivo) de uma pasta e chama lifecycle.

	Cada module pode opcionalmente expor:
		function module:Init()  -- prepara refs, não yielda muito (síncrono entre modules)
		function module:Start() -- lógica, conexões, loops (rodado em task.spawn paralelo)

	Uso:
		Loader.LoadFolder(workspace.Services)
		Loader.LoadModules({moduleA, moduleB})
--]]

local Loader = {}

local function safeRequire(moduleScript)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(("[Loader] Falha ao require '%s': %s"):format(moduleScript:GetFullName(), tostring(result)))
		return nil
	end
	return result
end

local function collectModuleScripts(folder)
	local scripts = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("ModuleScript") then
			table.insert(scripts, d)
		end
	end
	return scripts
end

local function runLifecycle(modules)
	-- Init phase (sequencial pra ordem determinística)
	for _, entry in ipairs(modules) do
		local m = entry.module
		if type(m) == "table" and type(m.Init) == "function" then
			local ok, err = pcall(function() m:Init() end)
			if not ok then
				warn(("[Loader] %s:Init() erro: %s"):format(entry.name, tostring(err)))
			end
		end
	end

	-- Start phase (paralelo via task.spawn)
	for _, entry in ipairs(modules) do
		local m = entry.module
		if type(m) == "table" and type(m.Start) == "function" then
			task.spawn(function()
				local ok, err = pcall(function() m:Start() end)
				if not ok then
					warn(("[Loader] %s:Start() erro: %s"):format(entry.name, tostring(err)))
				end
			end)
		end
	end
end

function Loader.LoadFolder(folder)
	assert(typeof(folder) == "Instance", "[Loader] LoadFolder espera um Instance")
	local scripts = collectModuleScripts(folder)
	local modules = {}
	for _, s in ipairs(scripts) do
		local m = safeRequire(s)
		if m ~= nil then
			table.insert(modules, { name = s.Name, module = m, instance = s })
		end
	end
	print(("[Loader] %d module(s) carregados de %s"):format(#modules, folder:GetFullName()))
	runLifecycle(modules)
	return modules
end

return Loader
