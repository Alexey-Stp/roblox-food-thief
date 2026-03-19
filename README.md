# Grand Hotel Heist

![Build](https://github.com/YOUR_USERNAME/RobloxSample/actions/workflows/publish.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## What is it?

PvE heist game on Roblox. Players sneak into the Grand Hotel, steal food from 3 floors of increasingly dangerous creatures, evade guards, and bring it back to their base to sell for money or store for points.

## Gameplay Loop

1. Enter the hotel → steal food from tables (press **E**)
2. Evade floor creatures (Wolves → Bears → Occultists) and **Hunter Guards** (blue-uniform NPCs)
3. Fight back with the **Bat** (always in your backpack) — swing at nearby players or enemies
4. Return to base → sell food at the Market Stall for Money
5. Store food in a **Fridge** (upgrades level 1–10) to boost its sell value before cashing out
6. Give food to teammates (**F** key near a player) or drop it (**G** key) for coordination
7. At night: grab the **Flying Carpet** near the restaurant entrance to fly over walls
8. Watch the sky — **Airplanes** occasionally fly over and drop free food
9. Scores and money persist between sessions via DataStore

## Key Controls

| Key | Action |
|-----|--------|
| E | Pick up food / use lift / interact with fridge |
| F | Give equipped food to nearest player (≤12 studs) |
| G | Drop equipped food as world pickup |
| WASD + Space / Shift | Fly while the Flying Carpet is equipped |

## Hotel Floors

| Floor | Creature   | Difficulty |
|-------|------------|------------|
| 1     | Wolves     | Easy       |
| 2     | Bears      | Medium     |
| 3     | Occultists | Hard       |

Use the lift platforms (press **E** on the lift) or the exterior staircase (east wall) to travel between floors.

## Scoring & Economy

| Action                          | Reward                            |
|---------------------------------|-----------------------------------|
| Steal food item                 | +10 Score                         |
| Store food in fridge            | +25 Score                         |
| Sell food at stall              | +Money (varies by food type)      |
| Fridge Level N sell bonus       | ×(1 + 0.3×N) on sell price        |
| Collect air-dropped food        | No score bonus; sells at base price |
| Buy Speed Boost                 | −100 Money                        |
| Buy Jump Boost                  | −150 Money                        |

## Development Setup

**Prerequisites:** [Rojo 7.x](https://rojo.space) and Roblox Studio with the Rojo plugin.

```bash
# Start live-sync dev server
rojo serve

# Build a .rbxl place file
rojo build default.project.json -o game.rbxl
```

Then open the Rojo plugin in Studio and click **Connect**, then press **Play**.

## Project Structure

```
src/
├── server/
│   ├── Main.server.lua             entry point — wires all modules
│   └── modules/
│       ├── Config.lua              all constants & food type definitions
│       ├── GameSystems.lua         leaderboard, money, DataStore persistence
│       ├── RestaurantBuilder.lua   hotel construction (floors, lifts, doors, exterior staircase)
│       ├── FoodSystem.lua          food spawning & E-key pickup
│       ├── EnemyAI.lua             wolf / bear / occultist patrol + chase AI
│       ├── BaseBuilder.lua         safe base, fridges, shop, sell stand
│       ├── DayNight.lua            day/night cycle & lighting
│       ├── BatCombat.lua           server-validated bat PvP weapon
│       ├── FoodInventory.lua       food give & drop between players
│       ├── RefrigeratorSystem.lua  fridge levelling & sell-value bonus
│       ├── FlyingCarpet.lua        night carpet spawn + server flight validation
│       ├── AirplaneSystem.lua      fly-by airplanes with food drops
│       └── HunterAI.lua            guard NPCs with pathfinding & catch logic
├── client/
│   ├── Effects.client.lua          hit flash, sparkle FX, bat hit sound
│   ├── FlyingCarpetClient.client.lua  carpet flight input (WASD + Space/Shift)
│   ├── FridgeClient.client.lua     fridge UI, give/drop key bindings
│   ├── Hud.client.lua              heads-up display
│   └── DayNightUI.client.lua       day/night indicator
└── shared/
    └── RemoteEvents.lua            centralised RemoteEvent definitions
```

## CI/CD

| Trigger           | Action                                          |
|-------------------|-------------------------------------------------|
| Push to `main`    | Build & publish to Roblox via Open Cloud API    |
| Open / update PR  | Rojo build check + Selene lint + StyLua format  |

Required GitHub secrets for the publish pipeline:

| Secret                | Description                                    |
|-----------------------|------------------------------------------------|
| `ROBLOX_API_KEY`      | API key with *Universe Place Management: write* |
| `ROBLOX_UNIVERSE_ID`  | Game ID (Studio → File → Game Settings)        |
| `ROBLOX_PLACE_ID`     | Place ID from the game URL on Roblox.com       |

## Adding a Food Type

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

No other code changes required.

## License

MIT
