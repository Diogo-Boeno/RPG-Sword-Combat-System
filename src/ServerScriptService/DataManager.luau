--[[
    DataManager
    ServerScriptService > DataManager (ModuleScript)

    Gerencia dados do jogador: armas desbloqueadas e loadout da hotbar.
    Usa DataStore para persistência entre sessões.
    Requerido pelo WeaponServer — não precisa de um script separado para inicializar.

    API pública:
        DataManager.GetData(player)                      → PlayerData | nil
        DataManager.GetLoadout(player)                   → { [slot]: weaponName }
        DataManager.GetUnlockedWeapons(player)           → { weaponName, ... }
        DataManager.SetLoadoutSlot(player, slot, name)   → void
        DataManager.UnlockWeapon(player, weaponName)     → bool
        DataManager.IsDataReady(player)                  → bool
--]]

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local WeaponRegistry = require(ReplicatedStorage:WaitForChild("WeaponRegistry"))

-- Versão da store — incrementar ao mudar a estrutura de dados
local DATA_STORE_KEY = "PlayerData_v1"
local PlayerDataStore = DataStoreService:GetDataStore(DATA_STORE_KEY)

-- Cache em memória: userId -> PlayerData
local cache     = {} -- { unlockedWeapons: string[], loadout: {[number]: string} }
local readyFlag = {} -- userId -> bool (true quando data está carregada)

-- ─── Dados Padrão ────────────────────────────────────────────

local function buildDefaultData()
    local data = {
        unlockedWeapons = {},
        loadout         = {},
        -- RPG
        level           = 1,
        xp              = 0,
        -- Inventário de consumíveis: { [itemName] = quantidade }
        items           = {},
    }
    -- Concede automaticamente armas com StarterWeapon = true
    for weaponName, config in pairs(WeaponRegistry) do
        if config.StarterWeapon then
            table.insert(data.unlockedWeapons, weaponName)
            if config.DefaultSlot then
                data.loadout[config.DefaultSlot] = weaponName
            end
        end
    end
    return data
end

-- ─── DataStore ───────────────────────────────────────────────

local function deepMerge(base, override)
    for k, v in pairs(override) do
        if type(v) == "table" and type(base[k]) == "table" then
            deepMerge(base[k], v)
        else
            base[k] = v
        end
    end
    return base
end

local function loadData(player)
    local success, result = pcall(function()
        return PlayerDataStore:GetAsync("player_" .. player.UserId)
    end)

    if success and result then
        -- Mescla dados salvos com defaults (para campos novos)
        local default = buildDefaultData()
        return deepMerge(default, result)
    end

    if not success then
        warn(("[DataManager] Falha ao carregar dados de %s: %s"):format(player.Name, tostring(result)))
    end

    return buildDefaultData()
end

local saveDebounce = {} -- evita saves simultâneos por jogador

local function saveData(player)
    local userId = player.UserId
    if saveDebounce[userId] then return end
    saveDebounce[userId] = true

    local data = cache[userId]
    if not data then
        saveDebounce[userId] = nil
        return
    end

    local success, err = pcall(function()
        PlayerDataStore:SetAsync("player_" .. userId, data)
    end)

    if not success then
        warn(("[DataManager] Falha ao salvar dados de %s: %s"):format(player.Name, tostring(err)))
    end

    saveDebounce[userId] = nil
end

-- ─── Ciclo de Vida do Jogador ─────────────────────────────────

local function onPlayerAdded(player)
    local data = loadData(player)
    cache[player.UserId]     = data
    readyFlag[player.UserId] = true
end

local function onPlayerRemoving(player)
    saveData(player)
    cache[player.UserId]     = nil
    readyFlag[player.UserId] = nil
    saveDebounce[player.UserId] = nil
end

-- Inicializa imediatamente ao ser required
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Cobre jogadores já presentes (Studio play-test)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

-- Salva todos ao fechar o servidor
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        saveData(player)
    end
end)

-- ─── API Pública ─────────────────────────────────────────────

local DataManager = {}

function DataManager.IsDataReady(player)
    return readyFlag[player.UserId] == true
end

-- Aguarda até os dados do jogador estarem prontos (uso no WeaponServer)
function DataManager.WaitForData(player, timeout)
    timeout = timeout or 10
    local elapsed = 0
    while not readyFlag[player.UserId] and elapsed < timeout do
        task.wait(0.05)
        elapsed += 0.05
    end
    return cache[player.UserId]
end

function DataManager.GetData(player)
    return cache[player.UserId]
end

function DataManager.GetLoadout(player)
    local data = cache[player.UserId]
    return data and data.loadout or {}
end

function DataManager.GetUnlockedWeapons(player)
    local data = cache[player.UserId]
    return data and data.unlockedWeapons or {}
end

-- Atualiza um slot do loadout e salva
function DataManager.SetLoadoutSlot(player, slot, weaponName)
    local data = cache[player.UserId]
    if not data then return end
    data.loadout[slot] = weaponName
    saveData(player)
end

-- Desbloqueia uma arma se ainda não desbloqueada
-- Retorna true em sucesso, false se a arma não existir no registry
function DataManager.UnlockWeapon(player, weaponName)
    if not WeaponRegistry[weaponName] then
        warn(("[DataManager] Arma desconhecida: %s"):format(weaponName))
        return false
    end

    local data = cache[player.UserId]
    if not data then return false end

    for _, name in ipairs(data.unlockedWeapons) do
        if name == weaponName then return true end -- já desbloqueada
    end

    table.insert(data.unlockedWeapons, weaponName)
    saveData(player)
    return true
end

-- ─── RPG: Level / XP ─────────────────────────────────────────

function DataManager.GetLevel(player)
    local data = cache[player.UserId]
    return data and data.level or 1
end

function DataManager.GetXP(player)
    local data = cache[player.UserId]
    return data and data.xp or 0
end

-- Seta level e xp diretamente (usado pelo LevelService) e salva.
function DataManager.SetLevelXP(player, level, xp)
    local data = cache[player.UserId]
    if not data then return end
    data.level = level
    data.xp = xp
    saveData(player)
end

-- ─── RPG: Itens / Consumíveis ────────────────────────────────

function DataManager.GetItems(player)
    local data = cache[player.UserId]
    return data and data.items or {}
end

function DataManager.GetItemCount(player, itemName)
    local data = cache[player.UserId]
    if not data then return 0 end
    return data.items[itemName] or 0
end

-- Adiciona N de um item (N pode ser negativo pra remover). Não deixa abaixo de 0.
-- Retorna a nova quantidade.
function DataManager.AddItem(player, itemName, amount)
    local data = cache[player.UserId]
    if not data then return 0 end
    amount = amount or 1
    local current = data.items[itemName] or 0
    local newCount = math.max(0, current + amount)
    if newCount == 0 then
        data.items[itemName] = nil
    else
        data.items[itemName] = newCount
    end
    saveData(player)
    return newCount
end

return DataManager
