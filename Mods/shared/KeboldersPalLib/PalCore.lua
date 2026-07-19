-- PalCore - tiny internals shared by every KeboldersPalLib module.
--
--   local Core = require("KeboldersPalLib.PalCore")   -- or Lib.Core
--   Core.pin(fn)      -- keep a UE4SS callback alive for the mod's lifetime
--   Core.valid(obj)   -- obj if it's a live UE object, else nil
--   Core.oidOf(actor) -- stable identity string, safe as a table key

local M = {}

-- UE4SS GCs unpinned callbacks; call site then hits a freed closure.
-- Pin anything given to RegisterHook/NotifyOnNewObject/LoopAsync/Execute*.
local pinned = {}
function M.pin(fn)
    pinned[#pinned + 1] = fn
    return fn
end

-- UE4SS returns INVALID objects (not nil) from failed lookups - always check IsValid().
function M.valid(obj)
    if obj and obj:IsValid() then return obj end
    return nil
end

-- Stable table key for one object: ModelInstanceId guid if the class has one, else FName.
-- NEVER key by GetAddress(): freed memory gets reused and can still report IsValid().
local hasGuid = {}
function M.oidOf(actor)
    if not (actor and actor:IsValid()) then return nil end
    local cls = actor:GetClass()
    local key = (cls and cls:IsValid()) and cls:GetFName():ToString() or "?"
    if hasGuid[key] ~= false then
        local ok, g = pcall(function() return actor.ModelInstanceId end)
        hasGuid[key] = (ok and g ~= nil) and true or false
        if hasGuid[key] then
            -- mask to 32 bits: %08x sign-extends negative (signed) values otherwise.
            return string.format("%08x:%08x:%08x:%08x",
                g.A % 0x100000000, g.B % 0x100000000,
                g.C % 0x100000000, g.D % 0x100000000)
        end
    end
    return actor:GetFName():ToString()
end

return M
