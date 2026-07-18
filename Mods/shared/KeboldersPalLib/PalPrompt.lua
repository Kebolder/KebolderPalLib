-- PalPrompt - native-looking custom interact prompts on any interactable's
-- floating F/V/C list. Rows are appended to the game's own indicator canvas
-- and synced by hooking its HideIndicators/ShowIndicators cycle; in-range
-- comes from the player's InteractComponent; the 16ms input loop sleeps
-- until a prompt is actually on screen.
--
--   local PalPrompt = require("KeboldersPalLib.PalPrompt")  -- or Lib.PalPrompt
--
--   PalPrompt.new{
--       target    = PalPrompt.Enum.ItemChest, -- REQUIRED: owner-actor class (generated Enum)
--       key       = PalPrompt.Key.Y,          -- REQUIRED: key name (generated Key = has glyph)
--       label     = "Sort",                   -- row text (default "")
--       mode      = "tap",                    -- "tap" (default) | "hold"
--       hold_time = 1.0,                      -- hold only: seconds hint for the hold anim
--       -- callbacks, all optional; each gets the FOCUSED target actor (nil if
--       -- it despawned the same tick) and that object's oid (see below):
--       on_press   = function(target, oid) end, -- key down (hold: hold engaged)
--       on_hold    = function(target, oid) end, -- hold only: every ~16ms while engaged
--       on_release = function(target, oid) end, -- real key-up
--       on_cancel  = function(target, oid) end, -- broken WITHOUT key-up (walked away)
--   }
--
--   target is live and must NOT outlive the tick (UE GC); oid is a plain
--   string, safe to keep in a table across ticks and saves.
--
--   PalPrompt.Enum / PalPrompt.Key   -- generated enums, re-exported
--   PalPrompt.PROFILE = true         -- debug: print lib-side work over 2ms
--
-- new() returns a handle you can update live (all chainable):
--   local p = PalPrompt.new{...}
--   p:setText("Locked")          -- change row text
--   p:setMode("hold")            -- switch "tap" <-> "hold" (cancels any engage)
--   p:update{ label = "Open", mode = "tap" }  -- both at once
--   p:destroy()                  -- unregister; the row is recycled, not leaked
--
-- PER-OBJECT overrides. Every callback gets (target, oid) where oid is a
-- stable identity string for THAT object, so two chests sharing one prompt can
-- show different text:
--   p:setText("Locked", oid)     -- override for one object only
--   p:setMode("hold", oid)
--   p:clear(oid)                 -- drop that object's override (nil = all)
--   PalPrompt.oidOf(actor)       -- identity string for any actor
--   PalPrompt.focusedOid()       -- oid of the object the game is prompting for
--
-- Registry / slots. "Slot" is the 1-based position among the MODDED rows in
-- the game's indicator box; the game's own POOL_SIZE rows are not counted:
--   p.id                         -- stable handle id
--   p:slot()                     -- this prompt's slot, nil until its row exists
--   PalPrompt.get(id)            -- handle by id
--   PalPrompt.slots()            -- { [slot] = {id, slot, target, key, label, mode, prompt} }
--   PalPrompt.destroyAll()
--
-- "hold" honors the "single button press for hold interactions" setting.
local PalInput = require("KeboldersPalLib.PalInput")
local PalEvents = require("KeboldersPalLib.PalEvents")
local Find = require("KeboldersPalLib.PalFind")

local CANVAS_CLASS = "/Game/Pal/Blueprint/UI/WBP_PalInteractiveObjectIndicatorCanvas.WBP_PalInteractiveObjectIndicatorCanvas_C"
local POOL_SIZE = 4 -- the game's own rows; ours are appended after these
local PUSH_NAME = "Interact_Push"
local PUSH_LIT = 0.7

-- ESlateVisibility (UMG_enums) - 3 is HitTestInvisible, unused here
local VISIBLE, COLLAPSED, HIDDEN, SELF_HIT_TEST_INVISIBLE = 0, 1, 2, 4
-- EPalInteractiveObjectButtonType (Pal_enums) - LongPush_Infinity: hold
-- arrow with no gauge completion, so holding can't stick it in a "done" state
local LONG_PUSH_INFINITY = 3

local ROW_FIXUPS = {
    { "Image_BlockInteract", COLLAPSED },
    { "InteractArrow",       HIDDEN },
    { "CanvasPanel_btn",     SELF_HIT_TEST_INVISIBLE },
    { "Interact_PushEff_00", SELF_HIT_TEST_INVISIBLE, 0.0 },
    { "Interact_PushEff_01", SELF_HIT_TEST_INVISIBLE, 0.0 },
}

local M = {}

M.Enum = require("KeboldersPalLib.enums.InteractableEnums")
M.Key = require("KeboldersPalLib.enums.KeyEnums")

local prompts = {}
local nextId = 0

local function log(fmt, ...) print("[PalPrompt] " .. string.format(fmt, ...)) end

-- every callback handed to UE4SS must be pinned or it gets GC'd mid-session
local pin = require("KeboldersPalLib.PalCore").pin

-- PROFILE: print any wrapped body over 2ms (os.clock granularity is 1ms, so
-- a 1.00 reading is boundary noise, not work). Zero overhead while false, and
-- returns are passed through either way - profiling must never change behavior.
M.PROFILE = false
local function profiled(label, fn)
    return function(...)
        if not M.PROFILE then return fn(...) end
        local t0 = os.clock()
        local r = table.pack(fn(...))
        local ms = (os.clock() - t0) * 1000
        if ms >= 2 then log("PROFILE %s %.2f ms", label, ms) end
        return table.unpack(r, 1, r.n)
    end
end

-- ---------------------------------------------------------------------------
-- lookups
-- ---------------------------------------------------------------------------
Find.watchAll("WBP_PalInteractiveObjectIndicatorCanvas_C", CANVAS_CLASS)

local canvasCache = nil
-- raw actor refs must never outlive the tick they were fetched in (UE GC)
local tickFocus = nil -- nil = unresolved, false = nothing focused, else {actor,target,oid}

local function resetTickCache()
    tickFocus = nil
end

-- two UE4SS wrappers of the same UObject are DIFFERENT tables, so == on them
-- is a coin flip; compare the addresses they point at
local function sameObj(a, b)
    if not (a and b) then return false end
    if not (a:IsValid() and b:IsValid()) then return false end
    return a:GetAddress() == b:GetAddress()
end

local function getPlayer()
    return Find.localPlayer()
end

local function getPC()
    return Find.localPC()
end

-- the live transient canvas (hook Context is unusable for no-param UFunctions)
local function findCanvas()
    if canvasCache and canvasCache:IsValid() then return canvasCache end
    canvasCache = nil
    for _, c in ipairs(Find.allOf("WBP_PalInteractiveObjectIndicatorCanvas_C") or {}) do
        if c:IsValid() and c:GetFullName():find("/Engine/Transient", 1, true) then
            canvasCache = c
            return c
        end
    end
    return nil
end

local function boxOf(canvas)
    local b = canvas and canvas:IsValid() and canvas.IndicatorVerticalBox
    return (b and b:IsValid()) and b or nil
end

-- in-range entries are interact COMPONENTS; walk outers to the owning actor
local function ownerActorOf(obj)
    local o = obj
    for _ = 1, 8 do
        if not (o and o:IsValid()) then return nil end
        if o:IsA("/Script/Engine.Actor") then return o end
        o = o:GetOuter()
    end
    return nil
end

-- The prompt target matching an owner actor's class. GetFName (bare class
-- name) not GetFullName - the latter builds the whole outer path per object.
-- Deliberately not memoized per class address: a GC'd class can be replaced
-- at the same address, and a stale entry would prompt on the wrong object.
local function targetOfActor(actor)
    local cls = actor:GetClass()
    if not (cls and cls:IsValid()) then return nil end
    local clsName = cls:GetFName():ToString()
    for _, p in ipairs(prompts) do
        if clsName:find(p.target, 1, true) then return p.target end
    end
    return nil
end

-- Stable identity for one object. Map objects (chests, crushers, everything
-- placeable) carry a ModelInstanceId guid that survives save/load; anything
-- else falls back to the actor's instance name - unique per session only.
-- Which classes expose the guid is memoized BY CLASS NAME so a miss costs one
-- pcall per class, not one per tick (a class address could be recycled by GC,
-- a name can't be recycled into something with a different property set).
local hasGuid = {}
local function oidOf(actor)
    if not (actor and actor:IsValid()) then return nil end
    local cls = actor:GetClass()
    local key = (cls and cls:IsValid()) and cls:GetFName():ToString() or "?"
    if hasGuid[key] ~= false then
        local ok, g = pcall(function() return actor.ModelInstanceId end)
        hasGuid[key] = (ok and g ~= nil) and true or false
        if hasGuid[key] then
            return string.format("%x:%x:%x:%x", g.A, g.B, g.C, g.D)
        end
    end
    return actor:GetFName():ToString()
end

-- Exactly one in-range object matching a registered target, or nil if none or
-- several. Only used as a fallback, so ambiguity means "no idea" - guessing is
-- what made two crushers share one prompt in the first place.
local function soleInRange(ic)
    local objs, found = ic.InteractiveObjects, nil
    for i = 1, #objs do
        local obj = objs[i]
        if obj and obj:IsValid() then
            local actor = ownerActorOf(obj)
            if actor and targetOfActor(actor) then
                if found then return nil end
                found = actor
            end
        end
    end
    return found
end

-- THE object the game is prompting for. TargetInteractiveObject is the focused
-- one; InteractiveObjects is merely everything in range, so keying on that list
-- fires on the wrong crusher whenever two are within reach of each other.
local function resolveFocus()
    local player = getPlayer()
    local ic = player and player.InteractComponent
    if not (ic and ic:IsValid()) then return false end

    -- TScriptInterface: reachable as the object itself, but don't bet the tick on it
    local ok, actor = pcall(function() return ownerActorOf(ic.TargetInteractiveObject) end)
    local target = ok and actor and targetOfActor(actor)
    if not target then
        actor = soleInRange(ic)
        target = actor and targetOfActor(actor)
    end
    if not target then return false end
    return { actor = actor, target = target, oid = oidOf(actor) }
end

local function focus()
    if tickFocus == nil then tickFocus = resolveFocus() end
    return tickFocus or nil
end

local function currentTarget(p)
    local f = focus()
    return (f and f.target == p.target) and f.actor or nil
end

-- the focused object's oid, but only if it belongs to THIS prompt's target
local function focusedOid(p)
    local f = focus()
    return (f and f.target == p.target) and f.oid or nil
end

local function overrideOf(p)
    local oid = focusedOid(p)
    return oid and p.overrides[oid] or nil
end

local function labelOf(p)
    local o = overrideOf(p)
    return (o and o.label) or p.label
end

local function modeOf(p)
    local o = overrideOf(p)
    return (o and o.mode) or p.mode
end

-- Find a widget by name inside a row's own widget tree, by hand.
--
-- UMG's by-name lookups are unreachable from Lua. UWidgetTree
-- exposes NO reflected functions at all (only RootWidget/NamedSlotBindings
-- fields - FindWidget is a C++ template) and GetWidgetFromName isn't in the
-- reflection dump either, so there is nothing to call. Widgets promoted to
-- Blueprint variables come back as plain fields (inner.KeyGuide etc.); this
-- walk is only for the ones that aren't - i.e. Interact_Push.
--
-- Only recurses through PanelWidget children, so it stays inside this tree
-- (a nested UUserWidget has its own WidgetTree and is not descended into).
-- Depth-bounded; on miss the caller just loses the press highlight.
local function findDescendantByName(w, wantName, depth)
    if not (w and w:IsValid()) or depth > 10 then return nil end
    if w:GetFName():ToString() == wantName then return w end
    if w:IsA("/Script/UMG.PanelWidget") then -- IsA needs the FULL class path
        local n = w:GetChildrenCount()
        for i = 0, n - 1 do
            local found = findDescendantByName(w:GetChildAt(i), wantName, depth + 1)
            if found then return found end
        end
    end
    return nil
end

local function findPushImage(row)
    local inner = row.WBP_Ingame_Interact
    local tree = inner and inner:IsValid() and inner.WidgetTree
    local root = tree and tree:IsValid() and tree.RootWidget
    if not (root and root:IsValid()) then return nil end
    return findDescendantByName(root, PUSH_NAME, 0)
end

-- ---------------------------------------------------------------------------
-- prompt
-- ---------------------------------------------------------------------------
local function fireCb(p, name)
    local fn = p[name]
    if fn then
        local ok, err = pcall(fn, currentTarget(p), focusedOid(p))
        if not ok then log("%s callback error: %s", name, tostring(err)) end
    end
end

-- p.appliedMode, not modeOf(p): the row is physically built as one mode, and a
-- hold that ends because the object vanished must still take the hold branch to
-- stop the arrow anim - by then modeOf() has no focus left to read an override from
local function setPressFx(p, lit)
    if p.appliedMode == "hold" then
        local inner = p.row and p.row:IsValid() and p.row.WBP_Ingame_Interact
        if not (inner and inner:IsValid()) then return end
        if lit then
            inner:AnmEvent_Button_Start(LONG_PUSH_INFINITY, p.hold_time)
        else
            inner:AnmEvent_Button_End(LONG_PUSH_INFINITY)
        end
    else
        if p.pushImage and p.pushImage:IsValid() then
            p.pushImage:SetRenderOpacity(lit and PUSH_LIT or 0.0)
        end
    end
end

local function isToggleInteract(p)
    if p.appliedMode ~= "hold" then return false end
    local uiUtil = Find.cdo("/Script/Pal.Default__PalUIUtility")
    local world = getPlayer()
    if not (uiUtil and world) then return false end
    local ok, res = pcall(function() return uiUtil:IsToggleInteract(world) end)
    return ok and res == true
end

local function engage(p)
    p.active = true
    -- pin the object this engagement belongs to: panning from chest1 to chest2
    -- mid-hold must cancel, not silently finish the hold on the other chest
    p.activeOid = focusedOid(p)
    setPressFx(p, true)
    fireCb(p, "on_press")
end

local function disengage(p, cbName)
    p.active = false
    setPressFx(p, false)
    fireCb(p, cbName)
end

-- push the focused object's label into the live row's text block (game-thread
-- only). One row is shared by every object of the target class, so this is what
-- makes chest #1 read "Locked" while chest #2 still reads "Open".
local function applyLabel(p)
    local inner = p.row and p.row:IsValid() and p.row.WBP_Ingame_Interact
    if not (inner and inner:IsValid()) then return end
    local text = inner.BP_PalTextBlock_C_101
    if text and text:IsValid() then text:SetText(FText(labelOf(p))) end
end

local function configureRow(p, template)
    local row, inner = p.row, p.row.WBP_Ingame_Interact
    if not (inner and inner:IsValid()) then return false end
    local srcInner = template and template:IsValid() and template.WBP_Ingame_Interact
    local mode = modeOf(p)

    applyLabel(p)

    local kg, srcKg = inner.KeyGuide, srcInner and srcInner.KeyGuide
    if kg and kg:IsValid() then
        if srcKg and srcKg:IsValid() then
            kg:SetInputAction(FName(srcKg.bindActionName.Key:ToString()))
        end
        local inputType = PalInput.currentType()
        local brush = PalInput.forKey(p.key, inputType)
        if brush and kg.OverrideImageMap then
            kg.OverrideImageMap:Add(inputType, brush)
            kg.EnableOverrideImage = true
            kg:OverrideImage()
        end
        if kg.PalUIActionWidgetBase_24 and kg.PalUIActionWidgetBase_24:IsValid() then
            kg.PalUIActionWidgetBase_24:SetVisibility(SELF_HIT_TEST_INVISIBLE)
        end
    end

    for _, fix in ipairs(ROW_FIXUPS) do
        local w = inner[fix[1]]
        if w and w:IsValid() then
            w:SetVisibility(fix[2])
            if fix[3] then w:SetRenderOpacity(fix[3]) end
        end
    end
    -- hold prompts keep the arrow
    if mode == "hold" and inner.InteractArrow and inner.InteractArrow:IsValid() then
        inner.InteractArrow:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    end
    if inner.RetainerBox_111 and inner.RetainerBox_111:IsValid() then
        inner.RetainerBox_111:SetRetainRendering(false)
    end
    if inner.BackgroundBlur_117 and inner.BackgroundBlur_117:IsValid() then
        inner.BackgroundBlur_117:SetVisibility(COLLAPSED)
    end

    inner:SetInteractable(true)
    inner:SetIsValidInteract(true)

    p.pushImage = findPushImage(row)
    if p.pushImage then p.pushImage:SetRenderOpacity(0.0) end
    row:SetVisibility(COLLAPSED)
    p.appliedMode, p.appliedOid = mode, focusedOid(p)
    return true
end

-- mode changes the row's visual fixups (arrow, push fx), so a live row must be
-- rebuilt from the template. Text alone just sets the block.
local function reconfigureRow(p)
    local box = boxOf(findCanvas())
    local template = box and box:GetChildAt(0)
    if p.row and p.row:IsValid() and template and template:IsValid() then
        p.pushImage = nil
        configureRow(p, template)               -- ends COLLAPSED; show cycle re-reveals
        if p.inRange then p.row:SetVisibility(VISIBLE) end
    end
end

-- Re-point the shared row at whatever object is focused right now. Cheap and
-- idempotent: the oid check makes it a no-op on every tick that didn't change
-- focus, and only a mode override pays for a template rebuild.
local function syncRow(p, forceLabel)
    local oid = focusedOid(p)
    if not (p.row and p.row:IsValid()) then return end
    if oid == p.appliedOid then
        if forceLabel then applyLabel(p) end
        return
    end
    p.appliedOid = oid
    if modeOf(p) ~= p.appliedMode then
        if p.active then disengage(p, "on_cancel") end
        p.wasDown = false
        reconfigureRow(p)
    else
        applyLabel(p)
    end
end

-- rows left from a previous build get reused instead of leaking new ones
local function orphanedRows(box)
    local out = {}
    for i = POOL_SIZE, box:GetChildrenCount() - 1 do
        local ch = box:GetChildAt(i)
        if ch and ch:IsValid() then
            local taken = false
            for _, p in ipairs(prompts) do
                if sameObj(p.row, ch) then taken = true break end
            end
            if not taken then out[#out + 1] = ch end
        end
    end
    return out
end

local function ensureBuilt(box)
    local pending = false
    for _, p in ipairs(prompts) do
        if not (p.row and p.row:IsValid()) then pending = true break end
    end
    if not pending then return end

    local template = box:GetChildAt(0)
    local pc = getPC()
    local wbl = Find.cdo("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not (template and template:IsValid() and pc and wbl) then return end
    local orphans, nextOrphan = orphanedRows(box), 1

    for _, p in ipairs(prompts) do
        if not (p.row and p.row:IsValid()) then
            local row = orphans[nextOrphan]
            if row then
                nextOrphan = nextOrphan + 1
            else
                row = wbl:Create(pc, template:GetClass(), pc)
                if row and row:IsValid() then box:AddChildToVerticalBox(row) end
            end
            if row and row:IsValid() then
                p.row, p.pushImage = row, nil
                -- an unconfigured row must never be shown: drop it and let the
                -- next build attempt retry
                if not configureRow(p, template) then p.row = nil end
            end
        end
    end
end

local lastShownAt = -math.huge
local awake = false

local function hideAll()
    for _, p in ipairs(prompts) do
        p.inRange = false
        if p.row and p.row:IsValid() then p.row:SetVisibility(COLLAPSED) end
    end
end

local function showInRange(canvas)
    local box = boxOf(canvas)
    if not box then return end

    -- fires for EVERY interactable; bail unless one of ours is here
    local anyHere = false
    for _, p in ipairs(prompts) do
        p.inRange = currentTarget(p) ~= nil
        anyHere = anyHere or p.inRange
    end
    if not anyHere then
        hideAll()
        return
    end

    ensureBuilt(box)
    awake = true
    lastShownAt = os.clock()
    for _, p in ipairs(prompts) do
        if p.row and p.row:IsValid() then
            if p.inRange then
                syncRow(p, true)  -- focus may have moved to a different object of the same class
                p.row:SetVisibility(VISIBLE)
                local anim = p.row.Default_In
                if anim and anim:IsValid() then p.row:PlayAnimationForward(anim, 1.0, false) end
            else
                p.row:SetVisibility(COLLAPSED)
            end
        end
    end
end

local function onHideIndicators()
    resetTickCache()
    hideAll()
end

local function onShowIndicators()
    resetTickCache()
    showInRange(findCanvas())
end

-- ---------------------------------------------------------------------------
-- lifecycle: driven by PalEvents
-- ---------------------------------------------------------------------------
local buildRetries = 0
local buildScheduled = false

local function tryBuildRows()
    local box = boxOf(findCanvas())
    if not box then return false end
    local template = box:GetChildAt(0)
    if not (template and template:IsValid() and getPC()) then return false end
    ensureBuilt(box)
    return true
end

-- Pre-build rows during load: the canvas constructs before its child rows
-- (our template) exist, so retry briefly. Built lazily instead, the widget
-- Create + configure would hitch the first approach of a target.
local function buildRowsSoon()
    if buildScheduled then return end
    if tryBuildRows() or buildRetries >= 40 then return end
    buildRetries = buildRetries + 1
    buildScheduled = true
    ExecuteWithDelay(250, pin(function()
        -- delayed callbacks run OFF the game thread; hop back before UE work
        ExecuteInGameThread(pin(function()
            buildScheduled = false
            buildRowsSoon()
        end))
    end))
end

-- fill every cold cache + build rows while loading still hides the cost
local function prewarm()
    findCanvas()
    getPlayer()
    getPC()
    for _, p in ipairs(prompts) do
        if p.key then PalInput.fkey(p.key) end
    end
    buildRowsSoon()
end

-- class-level hooks survive canvases coming and going; class must be loaded
local hooked = false
local function ensureHooks()
    if hooked then return end
    local okHide = pcall(RegisterHook, CANVAS_CLASS .. ":HideIndicators", pin(profiled("HideIndicators hook", onHideIndicators)))
    local okShow = pcall(RegisterHook, CANVAS_CLASS .. ":ShowIndicators", pin(profiled("ShowIndicators hook", onShowIndicators)))
    hooked = okHide and okShow
end

local function onCanvasCreated(canvas)
    if canvas:IsValid() and canvas:GetFullName():find("/Engine/Transient", 1, true) then
        canvasCache = canvas
    end
    ensureHooks()
    if hooked then prewarm() end
end

-- fires on dedicated servers too; the hooked gate (canvas class = client-only)
-- keeps servers from paying for any of this
local function onPlayerSpawned()
    ensureHooks()
    if hooked then prewarm() end
end

-- Cancel engagements, then drop every world ref. PalFind resets its own caches
-- on this event and is registered ahead of us, so lookups are already dead by
-- the time we run: on_cancel here fires with a nil target. That's within the
-- callback contract (target is always nil-able) and the world is going away
-- regardless - a teardown cancel is a "stop what you're doing" signal, not a
-- chance to touch the object.
local function onWorldUnloading()
    for _, p in ipairs(prompts) do
        if p.active then disengage(p, "on_cancel") end
        p.row, p.pushImage, p.keyStruct = nil, nil, nil
        p.inRange, p.wasDown = false, false
        -- overrides are keyed by ModelInstanceId, which survives the reload;
        -- what's applied to a now-dead row does not
        p.appliedOid, p.appliedMode, p.activeOid = nil, p.mode, nil
    end
    canvasCache, tickFocus = nil, nil
    buildRetries = 0
    awake = false
end

local bootstrapped = false
local function bootstrap()
    if bootstrapped then return end
    bootstrapped = true
    PalEvents.onNewObject(CANVAS_CLASS, onCanvasCreated)
    PalEvents.onPlayerSpawned(onPlayerSpawned)
    PalEvents.onWorldUnloading(onWorldUnloading)
    -- hot reload: the world may already exist, no construction event coming
    ExecuteInGameThread(pin(function()
        if findCanvas() then
            ensureHooks()
            prewarm()
        end
    end))
end

-- ---------------------------------------------------------------------------
-- input: edge detection per prompt
-- ---------------------------------------------------------------------------
local function tickPrompt(p, controller)
    if not (p.inRange or p.active) then
        p.wasDown = false
        return
    end
    -- the show/hide cycle doesn't necessarily fire when the player pans from one
    -- chest to the next, so the row is re-pointed here too (no-op if unchanged)
    if p.inRange and not p.active then syncRow(p) end

    if p.keyStruct == nil and p.key then p.keyStruct = PalInput.fkey(p.key) end
    if not p.keyStruct then return end

    -- the FKey points into the input-data CDO; a GC pass can invalidate it
    local ok, isDown = pcall(function() return controller:IsInputKeyDown(p.keyStruct) end)
    if not ok then
        p.keyStruct = nil
        return
    end
    local down = isDown and true or false

    if down and not p.wasDown then
        if isToggleInteract(p) then
            if p.active then disengage(p, "on_release")
            elseif currentTarget(p) then engage(p) end
        elseif not p.active and currentTarget(p) then
            engage(p)
        end
    elseif p.wasDown and not down then
        if p.active and not isToggleInteract(p) then
            disengage(p, "on_release")
        end
    end
    p.wasDown = down

    if p.active then
        if not currentTarget(p) or focusedOid(p) ~= p.activeOid then
            disengage(p, "on_cancel")
        elseif p.appliedMode == "hold" then
            fireCb(p, "on_hold")
        end
    end
end

local tickBody = profiled("input tick", function()
    resetTickCache()

    local anyWork = false
    for _, p in ipairs(prompts) do
        if p.inRange or p.active then
            anyWork = true
            break
        end
    end
    if not anyWork then
        if (os.clock() - lastShownAt) > 3.0 then
            awake = false
            for _, p in ipairs(prompts) do
                p.keyStruct, p.wasDown = nil, false
            end
        end
        return
    end

    local controller = getPC()
    if not controller then return end
    for _, p in ipairs(prompts) do
        tickPrompt(p, controller)
    end
end)

-- LoopAsync runs on a background thread; UE objects are game-thread only
local function loopTick()
    if awake then ExecuteInGameThread(tickBody) end
    return false
end

local loopStarted = false
local function startLoop()
    if loopStarted then return end
    loopStarted = true
    if type(LoopInGameThreadWithDelay) == "function" then
        -- newer UE4SS: already on the game thread, no per-tick hop
        LoopInGameThreadWithDelay(16, pin(function()
            if awake then tickBody() end
            return false
        end))
    else
        LoopAsync(16, pin(loopTick))
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

-- methods on the handle returned by M.new; all UE work hops to the game thread
local Prompt = {}

local function setOverride(p, oid, field, value)
    local o = p.overrides[oid] or {}
    o[field] = value
    -- an override with nothing left in it would keep the oid alive forever
    p.overrides[oid] = (o.label or o.mode) and o or nil
end

-- Update the row text live (nil = leave unchanged). With an oid, only THAT
-- object gets the new text; without one, the prompt's default changes.
function Prompt:setText(label, oid)
    if label == nil or self.destroyed then return self end
    if oid then setOverride(self, oid, "label", label) else self.label = label end
    ExecuteInGameThread(pin(function()
        if oid == nil or oid == focusedOid(self) then
            applyLabel(self)
        end
    end))
    return self
end

-- Switch "tap" <-> "hold" live; cancels any in-progress engagement first.
-- With an oid, only that object switches.
function Prompt:setMode(mode, oid)
    assert(mode == "tap" or mode == "hold", 'PalPrompt setMode: mode must be "tap" or "hold"')
    if self.destroyed then return self end
    ExecuteInGameThread(pin(function()
        if oid then setOverride(self, oid, "mode", mode) else self.mode = mode end
        if oid ~= nil and oid ~= focusedOid(self) then return end
        if modeOf(self) == self.appliedMode then return end
        if self.active then disengage(self, "on_cancel") end
        self.wasDown = false
        reconfigureRow(self)
    end))
    return self
end

-- Drop one object's overrides, or every object's when oid is nil.
function Prompt:clear(oid)
    if self.destroyed then return self end
    if oid then self.overrides[oid] = nil else self.overrides = {} end
    ExecuteInGameThread(pin(function()
        if oid ~= nil and oid ~= focusedOid(self) then return end
        self.appliedOid = nil -- force the next syncRow to reapply from scratch
        syncRow(self, true)
    end))
    return self
end

-- convenience: update label and/or mode in one call (opts.oid scopes both)
function Prompt:update(opts)
    if opts.label ~= nil then self:setText(opts.label, opts.oid) end
    if opts.mode ~= nil then self:setMode(opts.mode, opts.oid) end
    return self
end

-- This prompt's 1-based position among the MODDED rows in the indicator box
-- (the game's own POOL_SIZE rows are skipped). nil until the row is built.
function Prompt:slot()
    local box = boxOf(findCanvas())
    if not (box and self.row and self.row:IsValid()) then return nil end
    for i = POOL_SIZE, box:GetChildrenCount() - 1 do
        if sameObj(box:GetChildAt(i), self.row) then return i - POOL_SIZE + 1 end
    end
    return nil
end

-- Unregister. The row is left in the box collapsed rather than removed:
-- orphanedRows() hands it to the next new() instead of leaking a fresh widget,
-- and nobody else's slot number shifts.
function Prompt:destroy()
    if self.destroyed then return self end
    self.destroyed = true
    -- unregister and release the row in ONE game-thread step: split across
    -- threads, orphanedRows could re-let the row to a new prompt in the gap and
    -- then have our cleanup collapse it out from under the new owner
    ExecuteInGameThread(pin(function()
        for i, q in ipairs(prompts) do
            if q == self then table.remove(prompts, i) break end
        end
        if self.active then disengage(self, "on_cancel") end
        if self.row and self.row:IsValid() then self.row:SetVisibility(COLLAPSED) end
        self.row, self.pushImage, self.keyStruct = nil, nil, nil
        self.inRange, self.wasDown = false, false
        self.appliedOid, self.appliedMode = nil, nil
    end))
    return self
end

-- Register a prompt (see the header for the full option/callback reference).
---@alias PromptMode "tap"|"hold"
---@param opts { target: string, label: string, key: string, mode: PromptMode|nil, hold_time: number|nil, on_press: function|nil, on_hold: function|nil, on_release: function|nil, on_cancel: function|nil }
function M.new(opts)
    assert(opts and opts.target, "PalPrompt.new: target required")
    assert(opts.key, "PalPrompt.new: key required")
    -- an unrecognized mode would silently behave as "tap"
    assert(opts.mode == nil or opts.mode == "tap" or opts.mode == "hold",
        'PalPrompt.new: mode must be "tap" or "hold"')

    local p = {
        target = opts.target,
        label = opts.label or "",
        key = opts.key,
        mode = opts.mode or "tap",
        hold_time = opts.hold_time or 1.0,
        on_press = opts.on_press,
        on_hold = opts.on_hold,
        on_release = opts.on_release,
        on_cancel = opts.on_cancel,
        overrides = {},   -- [oid] = { label =, mode = }
        row = nil,
        pushImage = nil,
        keyStruct = nil,
        appliedMode = opts.mode or "tap",
        appliedOid = nil,
        activeOid = nil,
        inRange = false,
        active = false,
        wasDown = false,
        destroyed = false,
    }
    nextId = nextId + 1
    p.id = nextId
    setmetatable(p, { __index = Prompt })
    prompts[#prompts + 1] = p

    bootstrap()
    startLoop()
    if hooked then ExecuteInGameThread(pin(buildRowsSoon)) end
    return p
end

-- identity string for any actor; pass it back to setText/setMode/clear
M.oidOf = oidOf

-- oid of whatever the game is currently prompting for, nil if nothing
function M.focusedOid()
    local f = focus()
    return f and f.oid or nil
end

function M.get(id)
    for _, p in ipairs(prompts) do
        if p.id == id then return p end
    end
    return nil
end

-- every modded row currently in the indicator box, keyed by slot. label/mode
-- are the EFFECTIVE values for the focused object, so this doubles as a
-- readout of what the player is looking at right now.
function M.slots()
    local out = {}
    for _, p in ipairs(prompts) do
        local s = p:slot()
        if s then
            out[s] = { id = p.id, slot = s, target = p.target, key = p.key,
                       label = labelOf(p), mode = modeOf(p), prompt = p }
        end
    end
    return out
end

function M.destroyAll()
    for i = #prompts, 1, -1 do prompts[i]:destroy() end
end

return M
