# KeboldersPalLib

Shared [UE4SS](https://github.com/Okaetsu/RE-UE4SS) library for Palworld mods.

Its headline feature: **native-looking custom interact prompts** — add your own
row to any object's floating F/V/C list, glyphs and animations included, and get
press/hold/release callbacks. No custom UI to build; it rides the game's own
indicator canvas.

Also bundles the plumbing most mods re-invent: device-aware key glyphs, lifecycle
events, cached O(1) object lookups, and callback pinning.

## Install

Drop into `Palworld\Pal\Binaries\Win64\ue4ss\Mods\` so you have:

```
Mods\shared\KeboldersPalLib\
Mods\PalLibLoader\
```

`PalLibLoader` just confirms the lib is installed and prints a banner in chat.

## Quickstart

```lua
local Lib = require("KeboldersPalLib").atLeast("0.0.3")

local p = Lib.PalPrompt.new{
    target = Lib.Enum.PalBoxV2,   -- what to attach to
    key    = Lib.Key.Y,           -- prompt key
    label  = "Sort",
    on_press = function(target) print("pressed on", target:GetFullName()) end,
}

p:setText("Sorted")   -- update live
```

## Modules

| `Lib.X`     | What |
|-------------|------|
| `PalPrompt` | custom interact prompts on the native F/V/C list |
| `PalInput`  | device-aware key glyphs + FKey lookups |
| `PalEvents` | lifecycle events (player spawned/possessed, world unloading, new object) |
| `Find`      | cached lookups; `localPlayer()`/`localPC()` are O(1) and multiplayer-correct |
| `Core`      | `pin` (callback pinning) + `valid` |
| `Enum` / `Key` | generated interactable classes + keys with guaranteed glyphs |

Each module's source header has the full option/callback reference.

## Docs

Start here: **[docs/](docs/Home.md)** — [PalPrompt](docs/PalPrompt.md) is the deep dive.

## Status

Experimental (`0.0.3`). API may change.

## License

[Apache 2.0](LICENSE). © 2026 Kebolder.
