-- PalWorldDroppedItem - spawn REAL ground drop items, and inspect/modify any drop
-- already lying in the world (yours, a mined rock's, a dead Pal's).
--
--   local Drop = require("KeboldersPalLib.PalWorldDroppedItem")  -- or Lib.DroppedItem
--
--   Drop.slot(slot, 500, loc)                  -- 500 from one live slot
--   Drop.item(container, "Wood", 500, loc)     -- gather 500 across that container's slots
--   Drop.container(container, loc)             -- dump everything
--   Drop.slot(slot, 1, loc, { autoPickup = true })   -- fly straight to the player
--
--   for _, item in ipairs(Drop.near(loc, 300)) do    -- what's on the ground here
--       print(Drop.itemIdOf(item))
--       Drop.pickup(item, true)         -- collect it right now
--   end
--
--   Drop.autoCollect(200)              -- walk over ground drops to collect them
--   Drop.autoCollect(false)            -- stop
--   Drop.setCollectable(item, false)   -- ...but leave THIS one alone
--
-- Manual grabbing is the game's; bEnableInteract/bAutoPickedUp are read once at
-- init so writing them later is a no-op - that's why autoCollect polls.
-- Uses RequestDrop_ToServer, never SpawnActor: hand-spawning yields a half-
-- initialized map object (null model) and crashes.
-- A dropped actor isn't findable when the RPC returns - it shows up a tick later.

local Find = require("KeboldersPalLib.PalFind")
local Core = require("KeboldersPalLib.PalCore")

local M = {}

local DROP_SHORT = "PalMapObjectDropItem"
local DROP_CLASS = "/Script/Pal.PalMapObjectDropItem"

Find.watchAll(DROP_SHORT, DROP_CLASS)   -- walk-free live list of ground drops

-- item-transaction component (one per player, single-player = exactly one); Find caches it.
function M.component()
    return Find.firstOf("PalNetworkItemComponent")
end

-- CORE. list={{slot=<UPalItemSlot>, num=<int>}, ...}
-- opts={autoPickup=false}; returns {stacks, err} (0 stacks = none dropped)
function M.slots(list, location, opts)
    opts = opts or {}
    local c = M.component()
    if not c then return { stacks = 0, err = "no PalNetworkItemComponent" } end

    local payload = {}
    for _, e in ipairs(list) do
        local s, n = e.slot, e.num or 0
        if s and s:IsValid() and n > 0 then
            local ok, id = pcall(function() return s:GetSlotId() end)
            if ok and id then payload[#payload + 1] = { SlotId = id, Num = n } end
        end
    end
    if #payload == 0 then return { stacks = 0, err = "nothing to drop" } end

    local ok, err = pcall(function()
        c:RequestDrop_ToServer(payload, location, opts.autoPickup == true)
    end)
    if not ok then return { stacks = 0, err = tostring(err) } end
    return { stacks = #payload }
end

-- drop `num` out of one live slot
function M.slot(slot, num, location, opts)
    return M.slots({ { slot = slot, num = num } }, location, opts)
end

-- Walks a container's filled slots.
-- take(slot, stackCount, itemId): return num to drop, nil skip, false stop.
local function collect(container, take)
    local list, n = {}, 0
    pcall(function() n = container:Num() end)
    for i = 0, n - 1 do
        local ok, s = pcall(function() return container:Get(i) end)
        if ok and s and s:IsValid() then
            local sc, id = 0, nil
            pcall(function() sc = s:GetStackCount() end)
            pcall(function() id = s:GetItemId().StaticId:ToString() end)
            local num = sc > 0 and take(s, sc, id) or nil
            if num == false then break end
            if num and num > 0 then list[#list + 1] = { slot = s, num = num } end
        end
    end
    return list
end

-- dump every non-empty slot of a container
function M.container(container, location, opts)
    return M.slots(collect(container, function(_, sc) return sc end), location, opts)
end

-- drop up to num of one item id, gathering across as many slots as needed
function M.item(container, itemId, num, location, opts)
    local left = num
    local list = collect(container, function(_, sc, id)
        if left <= 0 then return false end
        if id ~= itemId then return nil end
        local t = math.min(sc, left)
        left = left - t
        return t
    end)
    return M.slots(list, location, opts)
end

-- every ground drop within `radius` of `location`, nearest first
function M.near(location, radius)
    local hits = {}
    for _, item in ipairs(Find.allOf(DROP_SHORT) or {}) do
        local loc
        pcall(function() loc = item:K2_GetActorLocation() end)
        if loc then
            local dx, dy, dz = loc.X - location.X, loc.Y - location.Y, loc.Z - location.Z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if d <= radius then hits[#hits + 1] = { item = item, dist = d } end
        end
    end
    table.sort(hits, function(a, b) return a.dist < b.dist end)
    local out = {}
    for i, h in ipairs(hits) do out[i] = h.item end
    return out
end

-- stable key for one drop (Core.oidOf: guid, FName fallback); drop items DO carry the guid.
M.idOf = Core.oidOf

-- GetModel() returns the BASE model.
-- Use .ConcreteModel, not TryGetConcreteModel (out-params unreliable).
function M.model(item)
    if not (item and item:IsValid()) then return nil end
    local base
    pcall(function() base = item:GetModel() end)
    if not (base and base:IsValid()) then return nil end
    local concrete
    pcall(function() concrete = base.ConcreteModel end)
    return (concrete and concrete:IsValid()) and concrete or nil
end

-- item id string on a live drop ("None"/nil if not initialized)
function M.itemIdOf(item)
    local m = M.model(item)
    if not m then return nil end
    local id
    pcall(function() id = m.ItemId.StaticId:ToString() end)
    return id
end

-- collect it NOW. bAuto=true routes through the game's auto-pickup path.
function M.pickup(item, bAuto)
    local m = M.model(item)
    if not m then return false end
    return pcall(function() m:RequestPickup(bAuto and true or false) end)
end

-- Walk-over collection, polled: game has no proximity-pickup
-- toggle, only spawn-time bAutoPickup.
M.COLLECT_MS  = 200      -- how often to look around the player
M.EXCLUDE_TTL = 2000     -- an exclusion lapses this long after its last set (ms)

local collectRadius = nil -- nil = off
local collecting = false
local blocked = {}        -- id -> ms remaining, drops excluded from collection

-- Excludes one drop from autoCollect (default: collectable).
-- Expiring lease: lapses after EXCLUDE_TTL unless re-asserted.
function M.setCollectable(item, enabled)
    local id = M.idOf(item)
    if not id then return false end
    blocked[id] = (not enabled) and M.EXCLUDE_TTL or nil
    return true
end

function M.isCollectable(item)
    local id = M.idOf(item)
    return not (id and blocked[id])
end

local collectBody = Core.pin(function()
    local p = collectRadius and Find.localPlayer()
    local loc
    if p and p:IsValid() then pcall(function() loc = p:K2_GetActorLocation() end) end
    if loc then
        for _, item in ipairs(M.near(loc, collectRadius)) do
            if M.isCollectable(item) then M.pickup(item, true) end
        end
    end
    for id, left in pairs(blocked) do          -- age out stale leases
        blocked[id] = left > M.COLLECT_MS and (left - M.COLLECT_MS) or nil
    end
    collecting = false
end)

local looping = false

-- Radius (uu) to collect drops the player walks over.
-- ~150 = standing on it, 400 = comfy vacuum; false/nil stops.
function M.autoCollect(radius)
    collectRadius = radius or nil
    if collectRadius and not looping then
        looping = true
        -- one LoopAsync for the mod's lifetime; it idles unless a radius is set
        LoopAsync(M.COLLECT_MS, Core.pin(function()
            if collectRadius and not collecting then
                collecting = true
                ExecuteInGameThread(collectBody)
            end
            return false
        end))
    end
    return collectRadius ~= nil
end

return M
