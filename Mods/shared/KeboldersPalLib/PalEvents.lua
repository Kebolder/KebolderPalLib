-- PalEvents - named, multi-subscriber game-lifecycle events over UE4SS's raw
-- primitives. One underlying registration per event/class no matter how many
-- subscribers; callback pinning handled here. All callbacks run on the game
-- thread; a subscriber that errors is logged and skipped.
--
--   local PalEvents = require("KeboldersPalLib.PalEvents")  -- or Lib.PalEvents
--   PalEvents.onNewObject("/Script/Pal.PalPlayerCharacter", function(obj) end)
--   PalEvents.onPlayerSpawned(function(pawn) end)        -- any pawn, incl. others'
--   PalEvents.onPlayerPossessed(function(pc, pawn) end)  -- "player ready"; works on servers
--   PalEvents.onWorldUnloading(function() end)           -- last chance to touch objects

local pin = require("KeboldersPalLib.PalCore").pin

local M = {}

local function log(fmt, ...) print("[PalEvents] " .. string.format(fmt, ...)) end

local function dispatch(name, subs, ...)
    for _, fn in ipairs(subs) do
        local ok, err = pcall(fn, ...)
        if not ok then log("%s subscriber error: %s", name, tostring(err)) end
    end
end

-- one NotifyOnNewObject per class path, fanned out to all subscribers.
-- classPath must be a full path; the class does NOT need to be loaded yet.
local newObjectSubs = {}

function M.onNewObject(classPath, fn)
    local subs = newObjectSubs[classPath]
    if not subs then
        subs = {}
        newObjectSubs[classPath] = subs
        NotifyOnNewObject(classPath, pin(function(obj)
            dispatch(classPath, subs, obj)
        end))
    end
    subs[#subs + 1] = fn
end

-- a player pawn constructed (world load, respawn) - in multiplayer this
-- includes OTHER players' pawns
function M.onPlayerSpawned(fn)
    M.onNewObject("/Script/Pal.PalPlayerCharacter", fn)
end

-- controller possessed a pawn -> (controller, pawn). The "player is actually
-- ready" signal; unlike ClientRestart it also fires on dedicated servers.
local possessSubs = {}
local possessHooked = false
function M.onPlayerPossessed(fn)
    possessSubs[#possessSubs + 1] = fn
    if not possessHooked then
        possessHooked = pcall(RegisterHook,
            "/Script/Engine.PlayerController:ServerAcknowledgePossession",
            pin(function(Context, Pawn)
                local pc = Context:get()
                local pawn = Pawn and Pawn:get()
                dispatch("onPlayerPossessed", possessSubs, pc, pawn)
            end))
        if not possessHooked then
            possessHooked = true -- don't retry a failed hook every subscribe
            log("ServerAcknowledgePossession hook failed; onPlayerPossessed will never fire")
        end
    end
end

-- just before the map tears down; world objects are still alive here
local unloadSubs = {}
local unloadHooked = false
function M.onWorldUnloading(fn)
    unloadSubs[#unloadSubs + 1] = fn
    if not unloadHooked then
        unloadHooked = pcall(RegisterLoadMapPreHook, pin(function()
            dispatch("onWorldUnloading", unloadSubs)
        end))
        if not unloadHooked then
            unloadHooked = true -- don't retry a missing API every subscribe
            log("RegisterLoadMapPreHook unavailable; onWorldUnloading will never fire")
        end
    end
end

return M
