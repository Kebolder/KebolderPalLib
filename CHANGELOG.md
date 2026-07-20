# Changelog

All notable changes to KeboldersPalLib. Versions before `0.0.7` are recorded in
the [git tags](https://github.com/Kebolder/KebolderPalLib/tags) only.

## [0.0.7] — Experimental

Rolls up everything since `0.0.5`, including the unreleased `0.0.6` fixes.

### Breaking

- `Lib.Dropper` is gone. Use `Lib.DroppedItem` (`PalWorldDroppedItem`).
- The `on_press` callback is gone. `"tap"` acts on `on_release`, `"hold"` on
  `on_hold`, `"timed"` on `on_complete`.
- `mode = "hold"` no longer waits for `hold_time`. It engages instantly and
  `on_hold` fires every ~16ms while the key is down. For the old
  fill-then-fire behavior use the new `mode = "timed"`.
- `oid` strings changed format. Guid parts now pad to 8 hex digits, so oids
  persisted by `0.0.5` or earlier that contained a short part will not match.

### Added

- **`PalWorldDroppedItem`** — one module for ground drop items: spawn via
  `UPalNetworkItemComponent:RequestDrop_ToServer`, plus inspect/modify for any
  drop already in the world, whoever created it.
  - `near(loc, radius)` finds drops by proximity — the spawn RPC returns
    nothing, so there is no request→actor tracking to be had.
  - `autoCollect(radius)` polls for walk-over pickup. The game has no
    proximity-pickup flag to switch on: every `bAutoPickup` in the headers is a
    spawn-time parameter, and `bEnableInteract` / `bAutoPickedUp` are read once
    at init.
  - `setCollectable(item, false)` is an expiring lease, not a latch. A carrier
    re-asserts it each tick, so an item whose carrier dies becomes collectable
    again rather than staying unpickable for the session.
- **`PalPrompt` `mode = "timed"`** — the gauge behind the glyph fills over
  `hold_time` from key-down, `on_complete` fires **once** at the top, then the
  row idles until key-up. Releasing early rewinds the fill.
- **`Find.aimed()`** — camera trace → `actor, oid, hit`. Replaces three
  hand-rolled copies and handles the UE 5.1 / 5.4 hit-result split.
- **`Core.oidOf`** — stable per-object key (ModelInstanceId guid, FName
  fallback), lifted out of `PalPrompt` so the drop module and prompts share one
  implementation.

### Changed

- `"timed"` drives `Anm_Push_long` and `Anm_Push_long_Arrow` directly instead of
  going through the game's button-anim event, so fill, reverse, and snap are
  deterministic and the gauge speed scales to `hold_time`.
- Module comments slimmed to one line per fact. No executable code changed.

### Fixed

- `setText` / `setMode` / `clear` only repaint the live row when the oid they
  target is the focused one. Updating one object no longer resets another
  object's visible label. (#1, reported by MaJoRX0)
- `oidOf` built its identity string with `%x`, dropping leading zeros — a guid
  part of `0x0393F4F6` came out as `393f4f6`. Roughly 23% of guids have at least
  one such part, so an oid rebuilt from the game's own id string silently missed
  its per-object override. Now `%08x`. (reported by MaJoRX0)
- `resolveFocus` no longer falls back to `soleInRange` when the game *did*
  resolve an object we simply have no prompt for. The visible symptom was a
  station's prompts following the Pal assigned to work it — aim at the Pal, the
  bench was the only match in range, and the bench's rows appeared and its keys
  fired. Same when aiming at a tree or a dropped item near a station.
- Hold prompts now respect the game's **Toggle Interact** accessibility setting
  correctly. The latch only applies once the hold has actually engaged, so a
  second press no longer releases a prompt that was never held.
- The key-down glyph highlight and the hold arrow anim are driven separately
  instead of sharing one function, so a hold no longer leaves the highlight lit
  underneath the arrow.

[0.0.7]: https://github.com/Kebolder/KebolderPalLib/compare/v0.0.5...v0.0.7
