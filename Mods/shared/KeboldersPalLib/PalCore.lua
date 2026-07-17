-- PalCore - tiny internals shared by every KeboldersPalLib module.
--
--   local Core = require("KeboldersPalLib.PalCore")   -- or Lib.Core
--   Core.pin(fn)      -- keep a UE4SS callback alive for the mod's lifetime
--   Core.valid(obj)   -- obj if it's a live UE object, else nil

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

return M
