# Reign of the Asleep

Sistema combate de ação (melee) no Roblox, com sistema de postura/parry no estilo *Sekiro* e elementos de RPG (level, XP, consumíveis) no estilo *Elden Ring*. O combate é baseado em katana, com ataque em combo, bloqueio, parry, esquiva (dodge/roll) e quebra de guarda (guardbreak).

---

## Visão geral

O jogador empunha uma katana e enfrenta NPCs que compartilham o **mesmo moveset** do jogador: atacam em combo, bloqueiam, dão parry e esquivam. O sistema de combate é **simétrico** — a mesma lógica que processa os golpes do jogador processa os dos NPCs.

Pilares do gameplay:

- **Combate de postura**: além da vida, cada personagem tem uma barra de *postura*. Bloquear golpes drena postura; quando zera, o personagem sofre **guardbreak** (fica atordoado, sem poder defender, tomando dano).
- **Parry**: abrir a janela de parry no momento certo do golpe inimigo reverte a pressão, atordoando o atacante.
- **RPG leve**: derrotar NPCs concede XP; acumular XP sobe de nível. Consumíveis (poções) curam vida e restauram postura.

---

## Arquitetura

O projeto usa um **framework próprio, leve**, com carregamento automático de módulos e ciclo de vida `Init` → `Start`. Não depende de frameworks externos como Knit ou Matter — tudo é caseiro e enxuto.

### Estrutura de pastas

```
ReplicatedStorage/
  Shared/Modules/        Framework compartilhado (client + server)
    Signal               Sinais leves (sem BindableEvent)
    Net                  Wrapper de RemoteEvents/Functions com cache
    Loader               Carrega módulos de uma pasta e roda Init/Start
  WeaponRegistry         Fonte de verdade das armas (stats, timings)
  ItemRegistry           Fonte de verdade dos consumíveis

ServerScriptService/
  DataManager            Persistência (DataStore): armas, loadout, level/XP, itens
  Server/
    Bootstrap            Carrega todos os Services
    Services/
      AttributeService       Inicializa atributos do personagem no spawn
      PostureRegenService    Regeneração de postura (com delay pós-bloqueio)
      HitService             Núcleo do combate (dano, parry, block, guardbreak)
      EquipService           Equip legacy (compatibilidade)
      WeaponService          Equip/unequip, scabbard, Motor6D
      RollService            Lógica de esquiva no servidor
      WeaponPreviewService   Preview de armas
      LevelService           XP e level (NPCs com tag "npc" dão XP)
      ItemService            Uso de consumíveis (poções)

StarterPlayerScripts/
  Client/
    Bootstrap            Carrega todos os Controllers
    Controllers/
      WeaponController       Input de combate, animações, hitbox
      HotbarController       Hotbar de armas (teclas 1-9)
      Roll                   Input de esquiva
      ParryBarController     UI de parry
      HealthBarController    HUD: vida, postura, level/XP, poção
      ItemController         Input de uso de consumíveis

ServerStorage/
  Modules/CombatAI       IA de combate reutilizável dos NPCs
  Weapons/               Modelos das armas (Katana etc)
  _OLD_BACKUP/           Scripts originais (pré-refatoração)

Workspace/
  Enemies/               Inimigo Normal + BOSS (usam CombatAI)
  Dummys/                Bonecos de treino
```

### O framework

**Loader** — varre uma pasta, dá `require` em cada ModuleScript e roda o ciclo de vida: primeiro `:Init()` em todos (sequencial, pra preparar referências), depois `:Start()` em todos (em paralelo, pra lógica e loops). Cada Service/Controller é só uma tabela que opcionalmente expõe `Init` e `Start`.

**Net** — abstrai RemoteEvents/RemoteFunctions. O servidor cria os remotes sob demanda; o cliente espera por eles. API simétrica: `FireClient`, `FireAllClients`, `OnServerEvent` no servidor; `FireServer`, `OnClientEvent` no cliente.

**Signal** — implementação leve de evento/observer sem o overhead de `BindableEvent`.

Para criar um novo Service ou Controller, basta colocar um ModuleScript na pasta `Services/` ou `Controllers/` seguindo o padrão:

```lua
local MyService = {}
function MyService:Init() end   -- preparar referências
function MyService:Start() end  -- lógica, conexões, loops
return MyService
```

O Loader o detecta e carrega automaticamente.

---

## Sistemas principais

### Combate (HitService)

Coração do jogo. Processa todo tipo de acerto — jogador vs jogador, NPC vs jogador — através de uma única função central. Lê os atributos **do alvo** no momento do impacto:

- `ParryWindow` aberta → o atacante é atordoado (parry bem-sucedido).
- `IsBlocking` ativo → o golpe é bloqueado, drenando postura; se a postura zerar, dispara **guardbreak**.
- `IFrames` ativo (durante esquiva) → o golpe é ignorado por completo.
- Caso contrário → dano normal e atordoamento curto.

Por ler atributos do alvo, o sistema funciona igual para qualquer combatente — é isso que torna o combate simétrico entre jogador e NPC.

### Postura e Guardbreak

A postura regenera lentamente, mas **só depois de ~1 segundo sem bloquear** — segurar a guarda impede a recuperação. Ao sofrer guardbreak, o personagem perde toda a defesa, fica imóvel tocando a animação de dano e não consegue bloquear nem dar parry até o atordoamento acabar.

### IA de Combate (CombatAI)

Módulo reutilizável que dá vida aos NPCs. Cada inimigo é configurado por um **perfil** (`Normal` ou `Boss`) com parâmetros de agressão, alcance, cooldowns e chances de reação. A IA:

- **Ronda** o jogador mantendo espaçamento (em vez de grudar e spammar ataque).
- **Pune aberturas** — investe quando vê o jogador atacando, atordoado ou com a guarda travada.
- **Reage defensivamente** a golpes (parry, block ou dodge), respeitando os próprios cooldowns para não tentar ações indisponíveis.
- Alterna entre **pressionar** (combo + recuo), **baitar** (provocar o ataque do jogador) e **esperar**.

O Boss é mais rápido, agressivo e resistente que o inimigo comum.

### Level / XP (LevelService)

Qualquer modelo com a tag `npc` (CollectionService) concede XP ao morrer, creditado a quem deu o último golpe. A quantidade vem do atributo `XPReward` do modelo. A curva de progressão cresce de forma exponencial leve, e é possível subir vários níveis de uma vez. O estado é salvo no DataStore.

### Consumíveis (ItemService + ItemRegistry)

Itens são definidos de forma declarativa no `ItemRegistry`. Cada item tem tempo de uso, cooldown e um efeito (`HealFlat`, `HealPercent`, `RestorePosture`, `HealOverTime`). Beber uma poção tem um tempo de execução e **é interrompido se o jogador sofrer atordoamento no meio** — fiel ao estilo *Elden Ring*. Consumo e cooldown são validados no servidor.

### Persistência (DataManager)

Camada de dados sobre DataStore, com cache em memória e *merge* de dados salvos com os padrões (para suportar campos novos sem quebrar saves antigos). Guarda armas desbloqueadas, loadout da hotbar, level, XP e inventário de itens.

---

## Controles

| Tecla | Ação |
|-------|------|
| Clique esquerdo | Atacar (combo) |
| F | Bloquear / Parry (segurar) |
| Q | Esquiva (dodge/roll) |
| R | Beber Frasco de Cura |
| T | Tônico de Postura |
| 1–9, 0 | Selecionar arma na hotbar |

---

## Como estender

### Adicionar uma arma
1. Adicione uma entrada no `WeaponRegistry` (stats, timings, animações).
2. Coloque o modelo da arma em `ServerStorage/Weapons/` com a mesma estrutura de attachments da Katana.
3. Marque `StarterWeapon = true` para concessão automática, ou use `DataManager.UnlockWeapon(player, nome)`.

### Adicionar um consumível
1. Adicione uma entrada no `ItemRegistry` com o efeito desejado.
2. Dê o item com `DataManager.AddItem(player, nome, quantidade)`.
3. (Opcional) Vincule uma tecla no `ItemController`.

### Adicionar um inimigo que dá XP
1. Crie o modelo (pode partir de um Dummy ou dos inimigos existentes).
2. Adicione a tag `npc` e o atributo `XPReward`.
3. Para IA de combate, adicione um Script que chama `CombatAI.new(modelo, { Profile = "Normal" })`.

---

## Stack técnica

- **Linguagem**: Luau (Roblox)
- **Plataforma**: Roblox Studio
- **Persistência**: Roblox DataStoreService
- **Hitbox**: RaycastHitboxV4
- **Sincronização de código**: Rojo (fluxo disco ↔ Studio)
- **Framework**: caseiro (Loader + Net + Signal), sem dependências externas
- **Arquitetura**: orientada a serviços (server) e controllers (client), data-driven (registries de armas e itens)
