# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Grand Hotel Heist

A cooperative PvE Roblox heist game. Players steal food from 3 hotel floors (Wolves → Bears → Occultists), evade Hunter Guards, and bring the food back to a Safe Base to sell for Money or store in an upgradeable Fridge. Written in Luau and synced into Studio with Rojo. Gameplay details and controls are in [README.md](README.md).

## Commands

The Windows binaries `rojo.exe` and `stylua.exe` sit in the repo root. CI pins Rojo 7.4.4, Selene 0.27.1 and StyLua 0.20.0.

```bash
./rojo.exe serve default.project.json            # live-sync to Studio (Rojo plugin → Connect → Play)
./rojo.exe build default.project.json -o game.rbxl   # build place file (CI "build" job)

selene generate-roblox-std   # one-time: generates roblox.yml for std = "roblox"
selene src/                  # lint (CI "lint" job)
./stylua.exe --check src/    # format check (CI "format" job); drop --check to apply
./stylua.exe src/

busted                                      # run all specs (LuaJIT + busted, from repo root)
busted tests/spec/FoodSystem_spec.lua       # run one spec file
busted --filter "steal" tests/spec          # run tests whose names match a pattern
```

CI ([.github/workflows/pr-checks.yml](.github/workflows/pr-checks.yml)) runs build, lint, format and test on every PR and on every push to a non-`main` branch. A push to `main` builds and publishes the place to Roblox through the Open Cloud API ([publish.yml](.github/workflows/publish.yml)).

StyLua uses **tabs** ([.stylua.toml](.stylua.toml)) and only checks `src/`. Specs under `tests/` use spaces and are not format-checked.

## Testing outside Studio

Tests run under plain LuaJIT, not Roblox. `.busted` loads [tests/mock/RobloxMock.lua](tests/mock/RobloxMock.lua) as a helper. The helper:
- sets up mock Roblox globals and services (`Vector3`, `BrickColor`, `Instance`, `game:GetService`, `task`, and so on)
- adds `./?.lua` to `package.path`, so specs load modules by file path: `require("src.server.modules.Config")`
- provides reset helpers such as `resetWorkspace()`

Specs reload a module with fresh state by clearing `package.loaded["src.server.modules.X"] = nil` before calling `require` again. If a module uses a Roblox API the mock doesn't cover, extend `RobloxMock.lua` and leave the module unchanged. The mock also resolves sibling requires such as `require(script.Parent.ToolUtil)`: indexing an unknown name on the mock `script.Parent` returns a reference to `src/server/modules/<Name>.lua` or `src/shared/<Name>.lua`. Mock instances don't resolve children by indexing, so code uses `FindFirstChild("Handle")` and not `tool.Handle`. Specs that test cooldowns replace `os.clock` with a fake clock and restore it in `after_each`. Selene lints specs with [tests/selene.toml](tests/selene.toml), which uses `lua51+busted` as defined in [selene.toml](selene.toml) at the root. The root [selene.toml](selene.toml) applies `std = "roblox"` to `src/`.

## Architecture

**Rojo mapping** ([default.project.json](default.project.json)):

| Folder | Roblox location |
|--------|-----------------|
| `src/server/` | `ServerScriptService/GameServer` |
| `src/client/` | `StarterPlayer/StarterPlayerScripts/GameClient` |
| `src/shared/` | `ReplicatedStorage/Shared` |
| `src/world/` | `Workspace` (imported `.rbxmx` buildings and models; `WorldPopulation` positions them at runtime) |

**Server boot order.** [Main.server.lua](src/server/Main.server.lua) is the only server Script. Every system is a ModuleScript in `src/server/modules/` and has no top-level side effects. Main wires them in three phases:
1. `X.init(deps...)`: pass in dependencies such as `RemoteEvents`, `Config` and `GameSystems`, and connect remote handlers. `GameSystems.init` runs first because players may already be in the server.
2. Build the world: `RestaurantBuilder.build(Config)` returns the per-floor food positions, which then go to `FoodSystem.spawnAll`. After that come `BaseBuilder.build()`, `SkyHotel.build()`, the creature/guard/chest `spawnAll()` calls, and the per-floor `EnemyAI.spawn` loop.
3. Start the loops: `DayNight.start`, `AirplaneSystem.start` and `FlyingCarpet.start`.

`RefrigeratorSystem.registerFridges()` runs right after `BaseBuilder.build()`. Anything that decorates built objects must be called explicitly after the build, not deferred.

To add a new system, require it with `safeRequire` and add it to every phase it needs. Systems don't require each other; they get their dependencies through `init` (for example, `FlyingCarpet` is passed into `SkyHotel` and `ChestSystem`). The one exception is the stateless helper [ToolUtil.lua](src/server/modules/ToolUtil.lua), which any module may `require(script.Parent.ToolUtil)`.

**Client/server boundary.** All RemoteEvents, plus the server-only `FoodStolenServer` BindableEvent, are created idempotently in [src/shared/RemoteEvents.lua](src/shared/RemoteEvents.lua) with `getOrCreate`. Never create one inline. Each client LocalScript fires input to the server; the server validates it (range, cooldown, raycast) and applies the result:
- `BatClient` → `BatSwing` → `BatCombat`. Damages players (only when `Config.PVP_ENABLED`), guards (`Guard_*` models), creatures (models with `IsCreature`) and breakable castle parts. It finds targets with one `GetPartBoundsInRadius` query, never a workspace scan.
- `WeaponClient` → `ShootWeapon` → `ChestSystem`. Pistol/Rifle hitscan.
- `FridgeClient` → `GiveFood` / `DropFood` → `FoodInventory`.
- Prefer server-side ProximityPrompts over client remotes for world interactions: sell stand, shop, fridges, chests and the multiplier all handle `Triggered` on the server.
- Flying carpets send nothing. `FlyingCarpet` samples each rider's `HumanoidRootPart` on the server and rubber-bands illegal speed or height. Server-initiated teleports must use `ToolUtil.teleport`, which stamps `LastServerTeleport` so the validator doesn't snap the player back.
- Server → client: `Notify` (toast, shown by `Hud`) is the only way to give one player text feedback. A ProximityPrompt's text is shared by everyone, so never change `ActionText` for one player's feedback. Other feedback events: `HitFlash`, `BatHit`, `FoodStolen`, `FridgeStoredFeedback`, `CarpetSpawned`, `CarpetRevoked`.
- `FoodSystem` fires `FoodStolenServer` (a BindableEvent) to alert `HunterAI`.

**Creatures have two behaviour modes, chosen from the spawn position** (`EnemyAI.spawn`). A creature spawned inside the hotel footprint patrols its floor and only notices players on that floor. A creature spawned outside (by `WorldPopulation`) guards the area around its spawn point and ignores players inside the hotel.

**Cosmetic work runs on the client.** The airplane model (`AirplaneFlight` event → `AirplaneClient`), the birds (`AmbientBirds`) and the day/night colour blend (`DayNightLighting`) are animated locally. The server only owns state that affects gameplay: `Lighting.ClockTime`, the `DayLength` attribute on Lighting, and air-drop food. Unanchored NPCs and loot call `ToolUtil.claimNetworkOwnership` so clients can't move them.

**Food is identified by a tag, and its state lives on the tool.** Always build food with `ToolUtil.makeFoodTool(foodType, opts)`. It tags the handle with `IsFood=true` and sets `FoodId`, `BaseSellPrice`, `CurrentSellPrice`, `Rarity`, `StoredAtLevel` and `Multiplied`. Every system that confiscates, sells, stores, gives, drops, multiplies or saves food selects tools with `ToolUtil.isFood` / `getFoodTools`. Never select food by excluding the bat or carpet: that rule is how weapons used to be sold and confiscated. Other tools carry `IsBat`, `IsCarpet` or `IsWeapon` and are never food.

Prices: the fridge sets `CurrentSellPrice = floor(BaseSellPrice × (1 + FRIDGE_BONUS_PER_LEVEL × level))`, calculated from the base price and never compounded. It only processes items whose `StoredAtLevel` is below the player's level, and pays the store Score once per item. The sell stand reads `CurrentSellPrice`. Food Multiplier output is tagged `Multiplied` and can't be multiplied again. Every way of picking up food respects `Config.MAX_FOOD_CARRIED`.

Only `FlyingCarpet.giveCarpet(player, isNightCarpet)` creates carpet tools (one per player). The single night carpet is tied to the tool's lifetime: if the tool is destroyed, the world carpet respawns.

**Persistence.** Only `GameSystems` touches the DataStore. It uses key `"PlayerData_v3"` (bump the suffix for breaking shape changes; the inventory loader accepts both old plain names and new metadata tables). It saves leaderstats, food inventory with price metadata, WalkSpeed/JumpPower, the per-player fridge level and `collectedFood`.
- **Data-safety rule:** a player is saved only after their load succeeded (`settings.loaded`). If every load retry fails, the session runs unsaved rather than overwriting the real record with defaults.
- Loads retry with backoff, saves use `UpdateAsync`, and `BindToClose` saves in parallel and waits for them to finish.
- Movement settings are saved from the cache, never from the live Humanoid, which may be stunned. Purchases call `GameSystems.updateSettings` (clamped to `MAX_WALK_SPEED` / `MAX_JUMP_POWER`) and then `applySettings`. Money changes go through `addMoney` / `trySpend`.
- The fridge level is published as the Player attribute `FridgeLevel`. `RefrigeratorSystem` adds `FridgeNextCost`, `FridgeBonusPct` and `FridgeMaxLevel`, and `FridgeClient` renders them locally, because Config isn't replicated to clients.
- Score values come from `Config.SCORE_*`.

**Content/tuning** (food types, creature names, floor geometry, asset IDs, day length) all lives in [Config.lua](src/server/modules/Config.lua). To add a food type, add an entry to `Config.FOOD_TYPES` (`name`, `color`, `size`, `texture`, `sideTexture`, `sellPrice`, `rarity` = `"Common" | "Rare" | "Epic"`). No other code changes are needed.

## Conventions

| Topic | Rule |
|-------|------|
| Threading | `task.wait/spawn/delay` only, never legacy `wait()` / `spawn()` |
| Physics | Use `AssemblyLinearVelocity` for knockback and flight. `BodyVelocity` is deprecated |
| Client-only visuals | Effects that only one player should see go in `Effects.client.lua` and are triggered by a RemoteEvent (an earlier screen flash showed for every player) |
| Debounce | Repeating interactions use an `os.clock()` timestamp debounce that is nil-safe (`if last and now - last < cd`). Never use `now - (last or 0)`: `os.clock()` starts near 0, so the first use would be blocked. Don't use `tick()` |
| One-shot prompts | Guard prompts that hand out a single reward (food pickup, chests, drops) with a local `taken`/`opened` flag. Two players can trigger in the same frame |
| Tool handling | Use `ToolUtil.isFood` / `isCarpet`; never classify by tool name or by "not a bat" |
| Night detection | Poll `Lighting.ClockTime` directly (≥20 or <6 = night). Don't call into `DayNight` from other modules |
| AI loops | One controller loop per NPC owns every `MoveTo` call (no spawned move threads). Stop on `Destroying` or `Humanoid.Died`; defeated NPCs respawn after `*_RESPAWN_TIME` |
| Moving platforms | Lifts are unanchored, server-owned platforms driven by a servo `PrismaticConstraint`, so physics carries the riders. Never write CFrames on client-owned characters every frame |
