<h3 align="center">THIS MOD DOES NOTHING ON ITS OWN. IT IS A LIBRARY FOR OTHER MODS TO USE.</h3>

# KeboldersPalLib

An assortment of modules and helpers for building Palworld mods, on top of
[UE4SS](https://github.com/Okaetsu/RE-UE4SS).

> ⚠️ **Experimental.** APIs are prone to change, break, and crash. If you hit a
> crash while using the lib, please [open an issue](https://github.com/Kebolder/KebolderPalLib/issues/new)
> and attach your crash files from `%LocalAppData%\Pal\Saved\Crashes`.

This isn't one feature with a wrapper around it. It's a set of separate modules,
each solving a piece of plumbing that mods otherwise end up rebuilding
themselves: lifecycle events, cached object lookups, device-aware key glyphs,
callback pinning, spawning real ground drops, and native-looking custom interact
prompts.

They're independent. Require the ones you want and ignore the rest.

## Install

Drop into `Palworld\Pal\Binaries\Win64\ue4ss\Mods\` so you have:

```
Mods\shared\KeboldersPalLib\
Mods\PalLibLoader\
```

`PalLibLoader` just confirms the lib is installed and prints a banner in chat.

## Use it

```lua
local Lib = require("KeboldersPalLib").atLeast("0.0.8")
```

Then see the **[Quickstart](https://github.com/Kebolder/KebolderPalLib/wiki/Quickstart)**
for a working prompt in about ten lines.

## What's in it

See **[Modules](https://github.com/Kebolder/KebolderPalLib/wiki/Modules)** for
the full list and what each one is for.

## Docs

Everything lives on the **[wiki](https://github.com/Kebolder/KebolderPalLib/wiki)**.
[PalPrompt](https://github.com/Kebolder/KebolderPalLib/wiki/PalPrompt) is the
deep dive if you want to see how far one module goes.

## Status

Experimental (`0.0.8`). The API may still change. See [CHANGELOG.md](CHANGELOG.md).

## Contributing

PRs welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Branch off `staging` and
open PRs against it.

## License

[Apache 2.0](LICENSE). © 2026 Kebolder.
