--[[
    WeaponRegistry
    ReplicatedStorage > WeaponRegistry (ModuleScript)

    Fonte única de verdade para configurações e metadados de armas.
    Acessível tanto pelo cliente quanto pelo servidor.

    Para adicionar uma nova arma:
        1. Adicione a entrada aqui
        2. Coloque a Tool em ServerStorage/Weapons/
        3. Pronto. Nenhum outro arquivo precisa ser alterado.
--]]

local WeaponRegistry = {}

-- ─────────────────────────────────────────────────────────────
-- Tipo: Melee (definição dos campos)
--
--  DisplayName   : string  — nome exibido na UI
--  Description   : string  — tooltip / descrição futura
--  Icon          : string  — rbxassetid:// para o ImageLabel do slot
--
--  Damage        : number  — dano base por hit
--  PostureDamage : number  — dano de postura por hit
--  SwingSpeed    : number  — multiplicador de velocidade de animação
--  Cooldown      : number  — cooldown base entre ataques (segundos)
--  ComboCount    : number  — quantidade de hits no combo
--
--  Type          : "Melee" | "Ranged" | ...  (para sistemas futuros)
--  Rarity        : "Common" | "Uncommon" | "Rare" | "Legendary"
--  DefaultSlot   : number  — slot padrão ao dar a arma pela primeira vez
--  StarterWeapon : bool    — se true, todos os jogadores começam com ela
-- ─────────────────────────────────────────────────────────────

WeaponRegistry["Katana"] = {
    DisplayName = "Katana",
    Description = "Uma lâmina japonesa veloz. Combos rápidos e dano moderado.",
    Icon = "rbxassetid://0", -- substitua pelo seu asset

    Damage = 10,
    PostureDamage = 15,
    SwingSpeed = 1.2,
    Cooldown = 0.5,
    ComboCount = 3,

    Type = "Melee",
    Rarity = "Common",
    DefaultSlot = 1,
    StarterWeapon = true,
}

WeaponRegistry["Spear"] = {
    DisplayName = "Spear",
    Description = "Alcance longo e alto dano de postura.",
    Icon = "rbxassetid://0",

    Damage = 15,
    PostureDamage = 20,
    SwingSpeed = 1.0,
    Cooldown = 0.5,
    ComboCount = 3,

    Type = "Melee",
    Rarity = "Uncommon",
    DefaultSlot = 2,
    StarterWeapon = false,
}

-- ─────────────────────────────────────────────────────────────
-- Adicione novas armas abaixo seguindo o mesmo padrão
-- ─────────────────────────────────────────────────────────────

return WeaponRegistry
