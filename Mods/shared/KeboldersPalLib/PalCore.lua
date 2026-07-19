-- PalCore - tiny internals shared by every KeboldersPalLib module.
--
--   local Core = require("KeboldersPalLib.PalCore")   -- or Lib.Core
--   Core.pin(fn)      -- keep a UE4SS callback alive for the mod's lifetime
--   Core.valid(obj)   -- obj if it's a live UE object, else nil
--   Core.oidOf(actor) -- stable identity string, safe as a table key

local M = {}

-- UE4SS holds Lua callbacks weakly and GC's them mid-session, then keeps
-- calling the freed closure - everything handed to RegisterHook /
-- NotifyOnNewObject / LoopAsync / Execute* must be pinned.
local pinned = {}
function M.pin(fn)
    pinned[#pinned + 1] = fn
    return fn
end

-- UE4SS returns INVALID objects (not nil) from failed lookups, so the
-- IsValid check is never optional.
function M.valid(obj)
    if obj and obj:IsValid() then return obj end
    return nil
end

-- Stable identity for one object. Map objects (chests, drop items, everything
-- placed or spawned as one) carry a ModelInstanceId guid that survives
-- save/load; anything else falls back to the actor's instance name - unique
-- per session only.
--
-- NEVER key object state by GetAddress(): freed actor memory gets reused, so a
-- stale address can silently alias a different object - and can still report
-- IsValid() while doing it.
--
-- Which classes expose the guid is memoized BY CLASS NAME so a miss costs one
-- pcall per class, not one per call (a class address could be recycled by GC,
-- a name can't be recycled into something with a different property set).
local hasGuid = {}
function M.oidOf(actor)
    if not (actor and actor:IsValid()) then return nil end
    local cls = actor:GetClass()
    local key = (cls and cls:IsValid()) and cls:GetFName():ToString() or "?"
    if hasGuid[key] ~= false then
        local ok, g = pcall(function() return actor.ModelInstanceId end)
        hasGuid[key] = (ok and g ~= nil) and true or false
        if hasGuid[key] then
            -- mask to 32 bits: these come through signed, and %08x on a
            -- negative sign-extends to 16 chars instead of masking, so the
            -- string wouldn't match one rebuilt from the same guid elsewhere
            return string.format("%08x:%08x:%08x:%08x",
                g.A % 0x100000000, g.B % 0x100000000,
                g.C % 0x100000000, g.D % 0x100000000)
        end
    end
    return actor:GetFName():ToString()
end

return M
