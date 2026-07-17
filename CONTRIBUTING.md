# Contributing to KeboldersPalLib

A UE4SS **Lua** library for Palworld mods. Thanks for helping.

## Branches

| Branch     | Purpose |
|------------|---------|
| `main`     | Released, stable. **Protected — PR only.** Merging here can cut a release. Never push directly. |
| `staging`  | Integration. PRs land here first and get tested together. |
| `feat/*` `fix/*` `docs/*` | Your work, branched off `staging`. |

**Flow:** branch off `staging` → PR into `staging` → maintainer batches + tests →
`staging` merged into `main` to release.

**Open PRs against `staging`, not `main`.**

## Dev setup

Clone anywhere, then junction the two mod folders into your UE4SS install so the
game loads them live while you edit in the repo (no admin needed, no copy step):

```bat
set UE=<path>\Palworld\Pal\Binaries\Win64\ue4ss\Mods
mklink /J "%UE%\shared\KeboldersPalLib" "%CD%\Mods\shared\KeboldersPalLib"
mklink /J "%UE%\PalLibLoader"           "%CD%\Mods\PalLibLoader"
```

Requires the **latest** [UE4SS](https://github.com/Okaetsu/RE-UE4SS). Edits in the
repo are live in-game on the next launch.

## Ground rules

- **Match the surrounding style.** Every module has a header docstring; functions
  are `local`; anything touching a live UE object is `pcall`-guarded; async or
  delayed callbacks hop to the game thread (`ExecuteInGameThread`) before UE work.
- **No new dependencies.** Lua stdlib + the UE4SS API only.
- **Don't bump `VERSION`.** The maintainer sets it when releasing.
- **Test in-game first.** Say what you tested in the PR.
- **One concern per PR.** Keep diffs focused.
- **Work the PR checklist as you go**, ticking each item off as you complete it.

## Reporting bugs

Open an issue with your UE4SS version, repro steps, and any
`[PalPrompt]` / `[PalLibLoader]` console output.
