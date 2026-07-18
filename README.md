<h3 align="center">THIS MOD DOES NOTHING ON ITS OWN — IT IS A LIBRARY FOR OTHER MODS TO USE</h3>

# KeboldersPalLib

Shared [UE4SS](https://github.com/Okaetsu/RE-UE4SS) library for Palworld mods.

> ⚠️ **Experimental.** APIs are prone to change, break, and crash. If you hit a
> crash while using the lib, please [open an issue](https://github.com/Kebolder/KebolderPalLib/issues/new)
> and attach your crash files from `%LocalAppData%\Pal\Saved\Crashes`.

A collection of Lua-driven modules that take the friction out of building and
running Palworld mods. Rather than solving one specific thing, it bundles the
plumbing most mods end up re-inventing lifecycle events, cached O(1) object
lookups, device-aware key glyphs, callback pinning, and native-looking custom
interact prompts behind one small, consistent API. Require what you need and
skip the boilerplate.

## Install

Drop into `Palworld\Pal\Binaries\Win64\ue4ss\Mods\` so you have:

```
Mods\shared\KeboldersPalLib\
Mods\PalLibLoader\
```

`PalLibLoader` just confirms the lib is installed and prints a banner in chat.

## Quickstart

See the **[Quickstart](https://github.com/Kebolder/KebolderPalLib/wiki/Quickstart)**
on the wiki.

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

Everything lives on the **[wiki](https://github.com/Kebolder/KebolderPalLib/wiki)** —
[PalPrompt](https://github.com/Kebolder/KebolderPalLib/wiki/PalPrompt) is the deep dive.

## Status

Experimental (`0.0.4`). API may change.

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Branch off `staging` and
open PRs against it.

## License

[Apache 2.0](LICENSE). © 2026 Kebolder.
