-- KeboldersPalLib - shared UE4SS library for Palworld mods.
-- Lives in Mods/shared/KeboldersPalLib/; require from any mod:
--
--   local Lib = require("KeboldersPalLib")
--   Lib.PalPrompt.new{ target = Lib.Enum.PalBoxV2, key = Lib.Key.Y, ... }
--
-- Submodules (lazy - loaded on first access):
--   Lib.PalPrompt  custom interact prompts on the native F/V/C list
--   Lib.PalInput   device-aware key glyphs + FKey lookups
--   Lib.PalEvents  lifecycle events (onNewObject/onPlayerSpawned/
--                  onPlayerPossessed/onWorldUnloading)
--   Lib.Find       cached object lookups; localPlayer()/localPC() are O(1)
--                  and multiplayer-correct - never walk the object array
--   Lib.DroppedItem  spawn REAL ground drop items from any container, and
--                  inspect/modify any drop lying in the world
--   Lib.Core       pin (UE4SS callback pinning) + valid (IsValid-or-nil)
--   Lib.Enum       generated: interactable target classes
--   Lib.Key        generated: keys with guaranteed keyboard glyphs
--
-- NOTE: each mod gets its own Lua VM - "shared" means shared FILES, not shared state.

local Lib = {
    NAME = "KeboldersPalLib",
    VERSION = "0.0.7b",
    STAGE = "Experimental",
}

Lib.BANNER = string.format("[%s] Version %s - %s", Lib.NAME, Lib.VERSION, Lib.STAGE)

-- Assert the installed lib is at least `min` (e.g. "x.x.x"); returns Lib for chaining.
function Lib.atLeast(min)
    local function parts(v)
        local t = {}
        for n in tostring(v):gmatch("%d+") do
            t[#t + 1] = tonumber(n)
        end
        return t
    end
    local have, want = parts(Lib.VERSION), parts(min)
    for i = 1, math.max(#have, #want) do
        local x, y = have[i] or 0, want[i] or 0
        if x > y then break end          -- newer: ok
        if x < y then                    -- older: fail loud
            error(string.format("%s %s is too old; this mod needs >= %s",
                Lib.NAME, Lib.VERSION, min), 2)
        end
    end
    return Lib
end

local submodules = {
    PalPrompt = "KeboldersPalLib.PalPrompt",
    PalInput = "KeboldersPalLib.PalInput",
    PalEvents = "KeboldersPalLib.PalEvents",
    Find = "KeboldersPalLib.PalFind",
    DroppedItem = "KeboldersPalLib.PalWorldDroppedItem",
    Core = "KeboldersPalLib.PalCore",
    Enum = "KeboldersPalLib.enums.InteractableEnums",
    Key = "KeboldersPalLib.enums.KeyEnums",
}

setmetatable(Lib, {
    __index = function(t, name)
        local path = submodules[name]
        if not path then return nil end
        local mod = require(path)
        rawset(t, name, mod)
        return mod
    end,
})

return Lib