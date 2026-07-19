-- PalFind - cached object lookups; never walk the object array mid-game.
-- (Raw FindFirstOf/FindAllOf walk millions of objects, ~23ms = frame hitch.)
--
--   local Find = require("KeboldersPalLib.PalFind")           -- or Lib.Find
--   Find.localPlayer()                 -- local player pawn, O(1), MP-correct
--   Find.localPC()                     -- local APalPlayerController
--   Find.localPlayerState()            -- local APalPlayerState (records/stats)
--   Find.wco()                         -- any live world object (WorldContext arg)
--   Find.firstOf("SomeClass")          -- first instance; walk once, cached
--   Find.cdo("/Script/Pal.Default__PalUtility")   -- object by full path
--   Find.watch("Short", "/Full.Path")  -- track a class from construction
--   Find.watchAll("Short", "/Full.Path") + Find.allOf("Short")
--                                      -- walk-free FindAllOf replacement
--   Find.aimed()                       -- actor, oid, hit under the crosshair
--
-- Caches are dropped automatically on world unload; there is nothing to wire up.

local PalEvents = require("KeboldersPalLib.PalEvents")

local M = {}

local firstCache = {}
local watched = {}

-- Watch a class: construction events keep the cache fresh, so the object
-- array is never walked for it again (one cold walk here, at load time).
-- Registration goes through PalEvents = one NotifyOnNewObject per class path.
-- The cache holds the most recently constructed instance - in multiplayer
-- that can be another player's pawn; use localPlayer()/localPC() for THE one.
function M.watch(shortName, fullClassPath)
    if watched[shortName] then return end
    watched[shortName] = true
    PalEvents.onNewObject(fullClassPath, function(obj)
        firstCache[shortName] = obj
    end)
    local c = FindFirstOf(shortName) -- cold fill, load-time only
    firstCache[shortName] = (c and c:IsValid()) and c or nil
end

function M.firstOf(className)
    local c = firstCache[className]
    if c and c:IsValid() then return c end
    -- watched classes never walk mid-game; construction refills the cache
    if watched[className] then return nil end
    c = FindFirstOf(className)
    if c and c:IsValid() then
        firstCache[className] = c
        return c
    end
    firstCache[className] = nil
    return nil
end

-- object by full path (CDOs, function libraries); StaticFindObject is a cheap
-- hash lookup, the cache just skips repeated wrapper creation
local cdoCache = {}
function M.cdo(path)
    local c = cdoCache[path]
    if c and c:IsValid() then return c end
    c = StaticFindObject(path)
    if c and c:IsValid() then
        cdoCache[path] = c
        return c
    end
    cdoCache[path] = nil
    return nil
end

-- every live instance, tracked from construction. Don't watchAll high-churn
-- classes (particles, projectiles): every construction fires a Lua callback.
local allCache = {}
local watchedAll = {}

function M.watchAll(shortName, fullClassPath)
    if watchedAll[shortName] then return end
    watchedAll[shortName] = true
    allCache[shortName] = {}
    PalEvents.onNewObject(fullClassPath, function(obj)
        local list = allCache[shortName]
        list[#list + 1] = obj
    end)
    for _, obj in ipairs(FindAllOf(shortName) or {}) do -- cold fill, load-time only
        local list = allCache[shortName]
        list[#list + 1] = obj
    end
end

-- live instances of a watchAll'd class (nil if never watched - no silent
-- walk fallback); dead entries pruned as read
function M.allOf(shortName)
    local list = allCache[shortName]
    if not list then return nil end
    local keep = {}
    for _, obj in ipairs(list) do
        if obj:IsValid() then keep[#keep + 1] = obj end
    end
    allCache[shortName] = keep
    return keep
end

-- ---------------------------------------------------------------------------
-- local player, O(1) and multiplayer-correct: UPalUtility CDO statics resolve
-- THE local player; they just need any live world object as WorldContext,
-- which the watched pawn provides. All nil on dedicated servers.
-- ---------------------------------------------------------------------------
M.watch("PalPlayerCharacter", "/Script/Pal.PalPlayerCharacter")

local PAL_UTILITY = "/Script/Pal.Default__PalUtility"

-- any live world object; nil until the first pawn exists
function M.wco()
    for _, obj in pairs(firstCache) do
        if obj and obj:IsValid() then return obj end
    end
    return nil
end

local localPawn, localPC, localPS

function M.localPlayer()
    if localPawn and localPawn:IsValid() then return localPawn end
    localPawn = nil
    local util, ctx = M.cdo(PAL_UTILITY), M.wco()
    if not (util and ctx) then return nil end
    local p = util:GetPlayerCharacter(ctx)
    if p and p:IsValid() then localPawn = p end
    return localPawn
end

function M.localPC()
    if localPC and localPC:IsValid() then return localPC end
    localPC = nil
    local util, ctx = M.cdo(PAL_UTILITY), M.wco()
    if not (util and ctx) then return nil end
    local c = util:GetLocalPalPlayerController(ctx)
    if c and c:IsValid() then localPC = c end
    return localPC
end

-- :GetRecordData() on this reaches UPalPlayerRecordData with no walk
function M.localPlayerState()
    if localPS and localPS:IsValid() then return localPS end
    localPS = nil
    local util, ctx = M.cdo(PAL_UTILITY), M.wco()
    if not (util and ctx) then return nil end
    local s = util:GetLocalPlayerState(ctx)
    if s and s:IsValid() then localPS = s end
    return localPS
end

-- ---------------------------------------------------------------------------
-- what the player is looking at
-- ---------------------------------------------------------------------------

-- Camera-forward line trace. Returns actor, oid, hit - all nil if nothing was
-- hit, so `local a = Find.aimed()` is a valid one-liner.
--
-- UE 5.1 hit-actor path is HitResult.HitObjectHandle.Actor:Get(); 5.4+ moved it
-- to .ReferenceObject, so this stays a pcall rather than a version check.
local UEHelpers   -- required lazily: PalFind loads before UEHelpers is needed
function M.aimed(maxDistance)
    local pc = M.localPC()
    if not (pc and pc:IsValid()) then return nil end
    UEHelpers = UEHelpers or require("UEHelpers")

    local cam = pc.PlayerCameraManager
    if not (cam and cam:IsValid()) then return nil end
    local from = cam:GetCameraLocation()
    local fwd = UEHelpers.GetKismetMathLibrary():GetForwardVector(cam:GetCameraRotation())
    local reach = maxDistance or 50000
    local hit = {}
    local ok = UEHelpers.GetKismetSystemLibrary():LineTraceSingle(
        pc.Pawn, from,
        { X = from.X + fwd.X * reach, Y = from.Y + fwd.Y * reach, Z = from.Z + fwd.Z * reach },
        0, false, {}, 0, hit, true,
        { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0.0)
    if not ok then return nil end

    local actor
    pcall(function() actor = hit.HitObjectHandle.Actor:Get() end)
    if not (actor and actor:IsValid()) then
        pcall(function() actor = hit.HitObjectHandle.ReferenceObject:Get() end)
    end
    if not (actor and actor:IsValid()) then return nil, nil, hit end
    return actor, require("KeboldersPalLib.PalCore").oidOf(actor), hit
end

-- drop every cached ref; watchers stay armed and the next world's constructions
-- refill everything. Wired to world unload below - consumers don't call this.
function M.reset()
    firstCache, cdoCache = {}, {}
    localPawn, localPC, localPS = nil, nil, nil
    for name in pairs(watchedAll) do
        allCache[name] = {}
    end
end

-- Self-wiring: every mod gets its own Lua VM, so leaving this to the consumer
-- meant each one had to remember it or silently hold dead wrappers for the rest
-- of the session.
--
-- ORDERING: subscribers dispatch in registration order, and this module is
-- required before anything that uses it, so this reset runs FIRST - before any
-- other onWorldUnloading subscriber. Lookups after it return nil for the rest of
-- the teardown: localPlayer/localPC/localPlayerState all need wco(), and wco()
-- reads a cache this just emptied. Nothing refills until the next world.
--
-- That's the intended trade. Teardown handlers are for dropping references, not
-- for asking the dying world questions. If a handler genuinely needs an object,
-- it has to capture it before unload, not look it up during.
PalEvents.onWorldUnloading(M.reset)

return M