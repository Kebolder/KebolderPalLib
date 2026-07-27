-- PalInput - the game's own key/button glyphs (SlateBrush), matched to the
-- current input device, plus FKey lookup for input polling.
--
--   local PalInput = require("KeboldersPalLib.PalInput")     -- or Lib.PalInput
--   local brush, fkey = PalInput.forKey("Y")       -- current device, kbd fallback
--   local brush       = PalInput.forCombo({"LeftControl", "E"})
--   local fkey        = PalInput.fkey("Y")         -- keyboard FKey (IsInputKeyDown)
--   local fkey        = PalInput.fkey("Gamepad_DPad_Left", PalInput.GAMEPAD)
--   local t           = PalInput.currentType()     -- 0 kbd, 1 gamepad, 2 touch
--   PalInput.onChanged(function(newType) end)      -- fires on device switch
--
-- Icons live in per-device UCommonInputBaseControllerData CDOs listed in
-- CommonInputPlatformSettings.ControllerDataClasses.

local Find = require("KeboldersPalLib.PalFind")

local M = {}

local MOUSE_KEYBOARD, GAMEPAD = 0, 1 -- ECommonInputType
M.MOUSE_KEYBOARD, M.GAMEPAD = MOUSE_KEYBOARD, GAMEPAD

Find.watch("CommonInputSubsystem", "/Script/CommonInput.CommonInputSubsystem")

-- current device type via the PalUtility CDO static - O(1)
function M.currentType()
    local util, ctx = Find.cdo("/Script/Pal.Default__PalUtility"), Find.wco()
    if not (util and ctx) then return MOUSE_KEYBOARD end
    local ok, t = pcall(function() return util:GetCurrentInputType(ctx) end)
    return (ok and t) or MOUSE_KEYBOARD
end

local function currentGamepadName()
    local s = Find.firstOf("CommonInputSubsystem")
    if not s then return "" end
    local ok, n = pcall(function() return s:GetCurrentGamepadName() end)
    return (ok and n and n:ToString()) or ""
end

-- GetCurrentGamepadName() is "" for a plain XInput pad, so exact match can miss
local GENERIC_GAMEPAD = "Generic"

local cdoCache = {}
local function resolveCDO(inputType, gamepadName)
    local cacheKey = tostring(inputType) .. ":" .. (gamepadName or "")
    local cached = cdoCache[cacheKey]
    if cached and cached:IsValid() then return cached end

    local settings = FindFirstOf("CommonInputPlatformSettings")
    if not settings or not settings:IsValid() then return nil end
    local classes = settings.ControllerDataClasses

    local exact, generic, any = nil, nil, nil
    for i = 1, #classes do
        local cls = classes[i]
        if cls and cls:IsValid() then
            local path = cls:GetFullName():match("%S+%s+(.*)")
            local cdo = path and StaticFindObject(path:gsub("([^%.]+)$", "Default__%1"))
            if cdo and cdo:IsValid() and cdo.InputType == inputType then
                if inputType ~= GAMEPAD then
                    exact = cdo
                    break
                end
                local name = cdo.GamepadName:ToString()
                if name == gamepadName then exact = cdo; break end
                if name == GENERIC_GAMEPAD then generic = generic or cdo end
                any = any or cdo
            end
        end
    end
    local cdo = exact or generic or any
    if cdo then cdoCache[cacheKey] = cdo end
    return cdo
end

local function cdoForType(inputType)
    return resolveCDO(inputType, inputType == GAMEPAD and currentGamepadName() or "")
end

-- keyed by address: two wrappers of one CDO are different tables
local keyIndexCache = {}

local function lookupKey(cdo, wantName)
    local arr = cdo.InputBrushDataMap
    local id = cdo:GetAddress()
    local map = keyIndexCache[id]
    if not map then
        map = {}
        keyIndexCache[id] = map
    end
    local j = map[wantName]
    if j then
        local e = arr[j]
        if e and e.Key.KeyName:ToString() == wantName then
            return e.KeyBrush, e.Key
        end
        map[wantName] = nil -- layout changed; rescan
    end
    for i = 1, #arr do
        if arr[i].Key.KeyName:ToString() == wantName then
            map[wantName] = i
            return arr[i].KeyBrush, arr[i].Key
        end
    end
    return nil
end

-- the game's own resolver; picks the right per-brand pad art internally
local function iconByKey(fkey, inputType)
    local util, ctx = Find.cdo("/Script/Pal.Default__PalUIUtility"), Find.wco()
    if not (util and ctx) then return nil end
    local ok, brush = pcall(function() return util:GetKeyIconByKey(ctx, fkey, inputType) end)
    return ok and brush or nil
end

-- brush (+ FKey) for a key on the current device, keyboard glyph as fallback
function M.forKey(keyName, inputType)
    inputType = inputType or M.currentType()
    local cdo = cdoForType(inputType)
    if cdo then
        local b, k = lookupKey(cdo, keyName)
        if k then return iconByKey(k, inputType) or b, k end
    end
    -- this device has no such key (e.g. a keyboard name while on a pad)
    if inputType ~= MOUSE_KEYBOARD then
        local kb = resolveCDO(MOUSE_KEYBOARD, "")
        if kb then return lookupKey(kb, keyName) end
    end
    return nil
end

local missingKeys = {}

-- FKey for polling (IsInputKeyDown); inputType defaults to keyboard
function M.fkey(keyName, inputType)
    inputType = inputType or MOUSE_KEYBOARD
    local cacheId = tostring(inputType) .. ":" .. tostring(keyName)
    if missingKeys[cacheId] then return nil end
    local cdo = cdoForType(inputType)
    if not cdo then return nil end
    local _, k = lookupKey(cdo, keyName)
    if not k then
        missingKeys[cacheId] = true
        print("[InputIcons] key '" .. tostring(keyName) .. "' has no entry for input type "
            .. tostring(inputType) .. "; input for it won't work")
    end
    return k
end

-- brush for a key combo from InputBrushKeySets; order-independent exact match
function M.forCombo(names, inputType)
    inputType = inputType or M.currentType()
    local cdo = cdoForType(inputType)
    if not cdo then return nil end
    local sets = cdo.InputBrushKeySets
    for j = 1, #sets do
        local keys = sets[j].Keys
        if #keys == #names then
            local want = {}
            for _, n in ipairs(names) do want[n] = true end
            local all = true
            for k = 1, #keys do
                if not want[keys[k].KeyName:ToString()] then
                    all = false
                    break
                end
            end
            if all then return sets[j].KeyBrush end
        end
    end
    return nil
end

-- device-switch subscription; one hook, callback pinned (UE4SS GC)
local pin = require("KeboldersPalLib.PalCore").pin
local changeFns = {}
local hooked = false
function M.onChanged(fn)
    changeFns[#changeFns + 1] = fn
    if not hooked then
        hooked = pcall(RegisterHook,
            "/Script/CommonInput.CommonInputSubsystem:InputMethodChangedDelegate",
            pin(function(_ctx, newType)
                local t = newType and newType:get()
                for _, f in ipairs(changeFns) do pcall(f, t) end
            end))
    end
end

-- drop dead CDO wrappers + the permanent negative cache on a map change
function M.reset()
    cdoCache, keyIndexCache, missingKeys = {}, {}, {}
end

require("KeboldersPalLib.PalEvents").onWorldUnloading(M.reset)

return M