# PalPrompt

Adds a native-looking row to an interactable's floating F/V/C prompt list. The
row uses the game's own glyphs and animations; you get key callbacks. No UI to build.

```lua
local Lib = require("KeboldersPalLib")

local p = Lib.PalPrompt.new{
    target = Lib.Enum.PalBoxV2,   -- REQUIRED: owner-actor class (generated enum)
    key    = Lib.Key.Y,           -- REQUIRED: key with a guaranteed glyph
    label  = "Sort",              -- row text (default "")
    mode   = "tap",               -- "tap" (default) | "hold"
    on_press = function(target) end,
}
```

## Options

| Field       | Req | Default | Meaning |
|-------------|-----|---------|---------|
| `target`    | yes | —       | owner-actor class to attach to (`Lib.Enum.*`) |
| `key`       | yes | —       | prompt key (`Lib.Key.*` = has a keyboard glyph) |
| `label`     | no  | `""`    | row text |
| `mode`      | no  | `"tap"` | `"tap"` or `"hold"` |
| `hold_time` | no  | `1.0`   | hold only: seconds hint for the hold animation |

## Callbacks

All optional. Each receives the in-range target actor (nil if it despawned the same tick).

| Callback     | Fires on |
|--------------|----------|
| `on_press`   | key down (hold: hold engaged) |
| `on_hold`    | hold only: every ~16ms while engaged |
| `on_release` | real key-up |
| `on_cancel`  | engagement broken without a key-up (walked away) |

## Live updates

`new()` returns a handle you can change at runtime (chainable):

```lua
p:setText("Locked")                    -- change row text
p:setMode("hold")                      -- switch tap <-> hold (cancels any engage)
p:update{ label = "Open", mode = "tap" }  -- both at once
```

## Notes

- `"hold"` honors the "single button press for hold interactions" accessibility
  setting: one press starts the hold, the next press ends it.
- The 16ms input loop sleeps until a prompt is actually on screen — no idle cost.
- `PalPrompt.PROFILE = true` prints lib-side work over 2ms (debug).
