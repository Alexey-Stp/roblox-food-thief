# Grand Hotel Heist — Developer Guide

## Game Concept
A cooperative PvE heist game set in a grand hotel. Players sneak into the hotel, steal food from 3 floors of increasingly dangerous creatures, evade Hunter Guards, and bring stolen food back to their **Safe Base** to sell or store.

### Core Loop
1. Enter the hotel → steal food from tables (press **E**)
2. Evade floor creatures (Wolves → Bears → Occultists) and Hunter Guards (blue-uniform NPCs)
3. Fight back with the **Bat** (always in backpack) — server-validated, 0.8 s cooldown
4. Return to base → sell food at the Market Stall for Money
5. Store food in a **Fridge** (upgrades level 1–10 with Money) to boost its sell value
6. Give food to teammates (**F** key near player) or drop it (**G** key) for coordination
7. At night: grab the **Flying Carpet** near the restaurant entrance to fly over walls
8. Watch the sky — **Airplanes** occasionally fly over and drop free food
9. Scores and money persist between sessions via DataStore

---

## Project Structure

```
roblox_food_thief/
├── default.project.json          Rojo project manifest
├── CLAUDE.md                     This file
└── src/
    ├── server/
    │   ├── Main.server.lua             Entry point — wires all modules together
    │   └── modules/
    │       ├── Config.lua              All constants, food types, asset IDs
    │       ├── GameSystems.lua         Leaderstats + DataStore persistence
    │       ├── RestaurantBuilder.lua   Hotel construction (floors, lifts, doors, exterior staircase)
    │       ├── FoodSystem.lua          Food spawning, stealing, respawning
    │       ├── EnemyAI.lua             Creature patrol + chase AI
    │       ├── BaseBuilder.lua         Safe base, fridges, shop, sell stand
    │       ├── DayNight.lua            Day/night cycle & lighting presets
    │       ├── BatCombat.lua           Server-validated bat PvP weapon
    │       ├── FoodInventory.lua       Food give & drop between players
    │       ├── RefrigeratorSystem.lua  Fridge levelling & sell-value bonus
    │       ├── FlyingCarpet.lua        Night carpet spawn + server flight validation
    │       ├── AirplaneSystem.lua      Fly-by airplanes with food drops
    │       └── HunterAI.lua            Guard NPCs with pathfinding & catch logic
    ├── client/
    │   ├── Effects.client.lua          Hit flash, sparkle FX, bat hit sound
    │   ├── FlyingCarpetClient.client.lua  Carpet flight input (WASD + Space/Shift)
    │   ├── FridgeClient.client.lua     Fridge UI, give/drop key bindings
    │   ├── Hud.client.lua              Heads-up display
    │   └── DayNightUI.client.lua       Day/night indicator
    └── shared/
        └── RemoteEvents.lua            Centralised RemoteEvent instances
```

### Roblox Service Mapping (Rojo)
| Folder | Roblox Service |
|--------|----------------|
| `src/server/` | `ServerScriptService/GameServer` |
| `src/client/` | `StarterPlayer/StarterPlayerScripts/GameClient` |
| `src/shared/` | `ReplicatedStorage/Shared` |

---

## Development Workflow

### Prerequisites
- [Rojo](https://rojo.space) — file-system sync tool for Roblox Studio
- Roblox Studio with the **Rojo plugin** installed

### Running the game
```bash
# In the project root:
rojo serve
```
Then in Roblox Studio, open the Rojo plugin and click **Connect**.
Press **Play** to test.

### Building a `.rbxl` file (for publishing)
```bash
rojo build default.project.json -o game.rbxl
```

---

## How to Add a New Food Type

1. Open [src/server/modules/Config.lua](src/server/modules/Config.lua)
2. Add an entry to the `FOOD_TYPES` table:
   ```lua
   {
     name        = "Taco",
     color       = BrickColor.new("Bright orange"),
     size        = Vector3.new(2, 0.8, 1.5),
     texture     = "rbxassetid://YOUR_ID_HERE",
     sideTexture = nil,
     sellPrice   = 18,
     rarity      = "Common",  -- "Common" | "Rare" | "Epic"
   },
   ```
3. To upload a real image:
   - In Studio: **View → Asset Manager → Images → Import from Device**
   - Upload a PNG/JPG (max 1024×1024; 512×512 recommended)
   - Right-click the uploaded image → **Copy Asset ID**
   - Paste into the `texture` field above
4. Save and reconnect Rojo — no other code changes needed.

---

## Coding Conventions

| Topic | Rule |
|-------|------|
| Threading | Always use `task.wait()`, `task.spawn()`, `task.delay()` — never legacy `wait()` / `spawn()` |
| Modules | Every system is a ModuleScript returning a table; no global state |
| RemoteEvents | Declared once in `shared/RemoteEvents.lua`; never create inline |
| Knockback / flight | Use `AssemblyLinearVelocity` — `BodyVelocity` is deprecated |
| Client effects | All visual effects visible only to one player go in `Effects.client.lua` |
| Debounce | All repeating interactions (doors, hits, swings) use timestamp-based debounce |
| DataStore | Wrap every call in `pcall`; use versioned key `"PlayerData_v1"` |
| Tool attributes | Food tools carry `BaseSellPrice`, `CurrentSellPrice`, `Rarity`, `FoodId` — always set these in `FoodSystem.lua` on the handle |
| Protected tools | Tag bat handles `IsBat=true`, carpet handles `IsCarpet=true`; the `isProtected()` helper in `EnemyAI` and `HunterAI` skips these during confiscation |
| Night detection | Poll `Lighting.ClockTime` directly (≥20 or <6 = night) — do not call into `DayNight` module from other modules |
| Fridge bonuses | `RefrigeratorSystem` writes `CurrentSellPrice` onto the tool handle; the sell stand reads this attribute, not the Config table |

---

## Score System
| Action | Points |
|--------|--------|
| Steal a food item | +10 |
| Store food in fridge | +25 |

Fridge upgrades raise `CurrentSellPrice` (the Money reward at sell time) — the +25 Score for storing is unchanged.

Stats are visible in the Roblox leaderboard as **Food Stolen** and **Score** and persist via DataStore between sessions.

---

## RemoteEvents Reference

| Event | Direction | Fired by | Handled by |
|-------|-----------|----------|------------|
| HitFlash | Server→Client | BatCombat, EnemyAI | Effects.client.lua |
| FoodStolen | Server→Client | FoodSystem | Effects.client.lua |
| BatSwing | Client→Server | client tool | BatCombat.lua |
| BatHit | Server→Client | BatCombat | Effects.client.lua |
| GiveFood | Client→Server | FridgeClient | FoodInventory.lua |
| DropFood | Client→Server | FridgeClient | FoodInventory.lua |
| UpgradeFridge | Client→Server | ProximityPrompt | RefrigeratorSystem.lua |
| StoreFoodInFridge | Client→Server | ProximityPrompt | RefrigeratorSystem.lua |
| FridgeStoredFeedback | Server→Client | RefrigeratorSystem | FridgeClient.client.lua |
| CarpetPositionUpdate | Client→Server | FlyingCarpetClient | FlyingCarpet.lua |
| CarpetRevoked | Server→Client | FlyingCarpet | FlyingCarpetClient.client.lua |
| CarpetSpawned | Server→Client | FlyingCarpet | FlyingCarpetClient.client.lua |
| FoodStolenServer *(BindableEvent)* | Server→Server | FoodSystem | HunterAI.lua |

---

## Known Asset IDs
The following texture IDs are used by default and can be replaced in `Config.lua`:

| Food | Asset ID |
|------|----------|
| Pizza (top) | `rbxassetid://6886896591` |
| Burger | `rbxassetid://7229442422` |
| Cake | `rbxassetid://7495147696` |
| Bread | `rbxassetid://6324656637` |
| Apple | `rbxassetid://6886896313` |
| Sparkle FX | `rbxassetid://744949272` |

> These IDs were present in the original project. Verify them in Studio by pasting into a Decal's **Texture** field in the Properties panel.

---

## Bug Fixes vs Original
| Bug | Fix |
|-----|-----|
| Screen flash affected all players | Moved to `Effects.client.lua` via `HitFlash` RemoteEvent |
| `BodyVelocity` deprecation warning | Replaced with `AssemblyLinearVelocity` |
| `wait()` / `spawn()` deprecation | Replaced with `task.*` equivalents |
| Door spam (no cooldown) | Added 0.5 s timestamp debounce per door |
| Creature loop leaks after destroy | `waiter.Destroying` signal breaks the AI loop |
| All Tools treated as food | Guarded with `item:IsA("Tool")` checks |
| Elevator didn't carry players | Replaced TweenService with 20Hz manual `task.spawn` loop that co-moves player HRP by delta Y |
| Bat/carpet confiscated by enemies | `IsBat` / `IsCarpet` attribute guards in `isProtected()` helper used by EnemyAI and HunterAI |
