# Castle Restaurant Heist — Developer Guide

## Game Concept
A cooperative PvE heist game set in a medieval castle. Players sneak into the **Castle Restaurant**, steal food from the counter, evade **creepy night creatures** that hunt food-carriers, and bring stolen food back to their **Safe Base** for storage and multiplication.

### Core Loop
1. Enter the castle → steal food from the counter (click on it)
2. Carry food back to the Safe Base (enemy creatures will chase you)
3. Store food on a shelf (+25 Score) or insert into the **Food Multiplier**
4. Multiplier processes food for 60 s and doubles it
5. Collect multiplied food → repeat

---

## Project Structure

```
RobloxSample/
├── default.project.json          Rojo project manifest
├── CLAUDE.md                     This file
└── src/
    ├── server/
    │   ├── Main.server.lua       Entry point — wires all modules together
    │   └── modules/
    │       ├── Config.lua        All constants, food types, asset IDs
    │       ├── RestaurantBuilder.lua  Castle construction
    │       ├── FoodSystem.lua    Food spawning, stealing, respawning
    │       ├── EnemyAI.lua       Creature patrol + chase AI
    │       ├── BaseBuilder.lua   Safe base + multiplier machine
    │       └── GameSystems.lua   Leaderstats + DataStore persistence
    ├── client/
    │   └── Effects.client.lua   Client-only: hit flash, sparkle FX
    └── shared/
        └── RemoteEvents.lua     Centralised RemoteEvent instances
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
     sideTexture = "rbxassetid://YOUR_ID_HERE",  -- or nil
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
| Knockback | Use `AssemblyLinearVelocity` — `BodyVelocity` is deprecated |
| Client effects | All visual effects visible only to one player go in `Effects.client.lua` |
| Debounce | All repeating interactions (doors, hits) use timestamp-based debounce |
| DataStore | Wrap every call in `pcall`; use versioned key `"PlayerData_v1"` |

---

## Score System
| Action | Points |
|--------|--------|
| Steal a food item | +10 |
| Store food on a shelf | +25 |
| Collect food from multiplier | +50 × items |

Stats are visible in the Roblox leaderboard as **Food Stolen** and **Score** and persist via DataStore between sessions.

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
