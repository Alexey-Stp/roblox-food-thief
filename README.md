# Grand Hotel Heist

![Build](https://github.com/YOUR_USERNAME/RobloxSample/actions/workflows/publish.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## What is it?

PvE heist game on Roblox. Players sneak into the Grand Hotel, steal food from 3 floors of increasingly dangerous creatures, and bring it back to their base to sell for money or store for points.

## Gameplay Loop

1. Enter the hotel → steal food from tables (press **E**)
2. Evade floor creatures (Wolves → Bears → Occultists, each floor faster)
3. Return to base → sell at the Market Stall for Money
4. Buy Speed / Jump upgrades at the Shop, or store food in fridges for Score
5. Scores and money persist between sessions via DataStore

## Hotel Floors

| Floor | Creature   | Difficulty |
|-------|------------|------------|
| 1     | Wolves     | Easy       |
| 2     | Bears      | Medium     |
| 3     | Occultists | Hard       |

Use the lift platforms (press **E** on the lift) to travel between floors.

## Scoring & Economy

| Action                      | Reward                       |
|-----------------------------|------------------------------|
| Steal food item             | +10 Score                    |
| Store food in fridge        | +25 Score                    |
| Sell food at stall          | +Money (varies by food type) |
| Buy Speed Boost             | −100 Money                   |
| Buy Jump Boost              | −150 Money                   |

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
│   ├── Main.server.lua           entry point — wires all modules
│   └── modules/
│       ├── Config.lua            all constants & food type definitions
│       ├── RestaurantBuilder.lua hotel world construction (floors, lifts, doors)
│       ├── FoodSystem.lua        food spawning & E-key pickup
│       ├── EnemyAI.lua           wolf / bear / occultist patrol + chase AI
│       ├── BaseBuilder.lua       safe base, fridges, shop, sell stand
│       └── GameSystems.lua       leaderboard, money, DataStore persistence
├── client/
│   └── Effects.client.lua        hit flash & sparkle FX (client-only)
└── shared/
    └── RemoteEvents.lua          centralised RemoteEvent definitions
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
    sideTexture = "rbxassetid://YOUR_ID_HERE",  -- or nil
    sellPrice   = 18,
},
```

No other code changes required.

## License

MIT
