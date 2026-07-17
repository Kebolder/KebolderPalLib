# KeboldersPalLib — Docs

Shared UE4SS library for Palworld mods. Start here.

- **[PalPrompt](PalPrompt.md)** — custom interact prompts on the native F/V/C list
- *PalInput, PalEvents, Find, Core* — see each module's source header for now

## Load it

```lua
local Lib = require("KeboldersPalLib").atLeast("0.0.3")
```

`atLeast(min)` fails loudly if the installed lib is older than your mod needs.
Missing entirely → `require` errors. Either way you find out at load, not mid-game.

## Note on VMs

UE4SS gives every mod its own Lua VM. "Shared" means shared *files* — each mod
that requires the lib gets its own instance of everything. No cross-mod state.
