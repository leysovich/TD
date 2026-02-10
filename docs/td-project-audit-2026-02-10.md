# TD Project Audit and Rojo Migration Summary (2026-02-10)

## Scope and Objective
This audit captures the full Roblox Studio project inventory and documents the migration of practical gameplay code/config into Rojo-synchronized local files.

Applied migration defaults:
- Code-first sync: migrate scripts/modules/config only.
- Preserve runtime namespace: keep `ReplicatedStorage.TD` contract.
- Keep heavy non-script assets in Studio.
- Create legacy script backups in Studio (`*_Legacy`) and disable them.

## Local Repository Before Migration
Scaffold-only files were present locally before extraction:
- `src/client/init.client.luau`
- `src/server/init.server.luau`
- `src/shared/Hello.luau`
- `src/shared/car.luau`

Rojo project shape before migration:
- `ServerScriptService.Server` <- `src/server`
- `StarterPlayer.StarterPlayerScripts.Client` <- `src/client`
- `ReplicatedStorage.Shared` <- `src/shared`

## Studio Inventory (Authoritative Source)
### Key Gameplay Containers
- `ReplicatedStorage.TD` (Folder)
  - `Config` (ModuleScript)
  - `Remotes` (Folder)
    - `PlaceTower` (RemoteEvent)
    - `StateUpdate` (RemoteEvent)
    - `TowerAction` (RemoteFunction)
  - `Assets` (Folder)
    - `EnemyModels` (Folder, includes `Alien`, `Bruiser`, `Scout`, `Siege`)
    - `TowerModels` (Folder, includes `LaserTurret`, `FrostBeam`, `MissilePod`)
- `ServerScriptService.TDServer` (Script)
- `StarterPlayer.StarterPlayerScripts.TDClient` (LocalScript)
- `Workspace.TD_Map` (Folder)
  - `Waypoints` (`WP1`..`WP6`)
  - `PathVisual` (`Path1`..`Path5`)
- `Workspace.TD_Enemies` (Folder)
- `Workspace.TD_Towers` (Folder)

### Script/Module Size Snapshot
- `TDServer`: 52,440 chars (~1,750 lines)
- `TDClient`: 43,413 chars (~1,365 lines)
- `Config`: 4,151 chars (~82 lines)

### Gameplay Config Snapshot
Economy and match controls:
- `StartMoney=460`
- `BaseLives=20`
- `Intermission=10`
- `MaxTowersPerPlayer=22`
- `SellRefundRate=0.65`
- `WaveClearBonusBase=20`
- `WaveClearBonusScale=2.2`

Tower keys in config:
- `LaserTurret`
- `FrostBeam`
- `MissilePod`

Waves:
- 15 total waves
- Wave names include: `Probe Scouts`, `Alpha Strider`, `Titan Core`, `Overmind Apex`

## Migration Implementation
### Rojo Mapping Changes
`default.project.json` now maps gameplay runtime names directly:
- `ServerScriptService.TDServer` <- `src/server/TDServer`
- `StarterPlayer.StarterPlayerScripts.TDClient` <- `src/client/TDClient`
- `ReplicatedStorage.TD.Config` <- `src/replicated/TD/Config.luau`
- `ReplicatedStorage.TD.Remotes` declared in project:
  - `PlaceTower` RemoteEvent
  - `StateUpdate` RemoteEvent
  - `TowerAction` RemoteFunction
- `ReplicatedStorage.TD` has `"$ignoreUnknownInstances": true` so unsynced Studio assets under `TD` are preserved.

### Local Files Added from Studio Sources
- `src/server/TDServer/init.server.luau`
- `src/client/TDClient/init.client.luau`
- `src/replicated/TD/Config.luau`

### Scaffold Cleanup
Removed unmapped scaffold placeholders:
- `src/server/init.server.luau`
- `src/client/init.client.luau`

## Studio Cutover Actions
Applied in Studio via MCP:
- Created/updated `ServerScriptService.TDServer_Legacy` from `TDServer`, set `Disabled=true`.
- Created/updated `StarterPlayer.StarterPlayerScripts.TDClient_Legacy` from `TDClient`, set `Disabled=true`.
- Kept live scripts active:
  - `TDServer.Disabled=false`
  - `TDClient.Disabled=false`
- Ensured `ReplicatedStorage.TD.Remotes` contract exists with correct classes.

## Validation Results
### Rojo Validation
- `rojo sourcemap default.project.json -o sourcemap.json` succeeded.
- `rojo build default.project.json -o /tmp/TD-migrated.rbxlx` succeeded.

### Source Parity Validation (Studio vs Local)
Used identical rolling hash (`h = (h*131 + byte) % 2147483647`) and char counts.

- `TDServer`: chars `52440`, hash `660924600` (match)
- `TDClient`: chars `43413`, hash `1042797307` (match)
- `Config`: chars `4151`, hash `1227764913` (match)

### Runtime Wiring and Asset Preservation Checks
Verified in Studio:
- `ReplicatedStorage.TD` exists.
- `ReplicatedStorage.TD.Assets` exists (non-script assets preserved).
- `ReplicatedStorage.TD.Remotes` contains expected classes.
- `Workspace.TD_Map`, `Workspace.TD_Enemies`, `Workspace.TD_Towers` exist.
- `Workspace.TD_Map.Waypoints` exists with 6 children.
- `TDServer_Legacy` and `TDClient_Legacy` are present and disabled.

## Sync Status Matrix
| Area | Current State | Sync Source |
|---|---|---|
| `TDServer` script | Synced | Rojo (`src/server/TDServer/init.server.luau`) |
| `TDClient` script | Synced | Rojo (`src/client/TDClient/init.client.luau`) |
| `TD.Config` module | Synced | Rojo (`src/replicated/TD/Config.luau`) |
| `TD.Remotes` schema | Synced | Rojo project declarations |
| `TD.Assets` models/parts | Unsynced (intentional) | Studio authoritative |
| `Workspace.TD_Map` geometry/path parts | Unsynced (intentional) | Studio authoritative |
| `Workspace.TD_Enemies` / `TD_Towers` folders | Unsynced runtime containers | Studio authoritative |

## Notes for Next Iteration
If full asset sync is required later, consider a separate pass to define an asset serialization strategy (or a controlled place snapshot workflow) for `TD.Assets` and map geometry under `Workspace`.
