-- PalLibLoader - confirms KeboldersPalLib is installed and loadable.
--
-- Does nothing else: the library itself is required directly by whichever
-- mods use it (UE4SS gives every mod its own Lua VM, so "loading" it here
-- doesn't load it for anyone else). This just fails loudly and early if the
-- shared folder is missing, and says hello in chat once you're in a world.
local ok, Lib = pcall(require, "KeboldersPalLib")
if not ok then
    print("[PalLibLoader] ERROR: KeboldersPalLib not found - is Mods/shared/KeboldersPalLib installed? ("
        .. tostring(Lib) .. ")")
    return
end

print(Lib.BANNER)

local pin = Lib.Core.pin

local function announce()
    -- delayed callbacks run OFF the game thread; hop back before UE work
    ExecuteInGameThread(pin(function()
        local util = Lib.Find.cdo("/Script/Pal.Default__PalUtility")
        local ctx = Lib.Find.localPlayer()
        local sent = util and ctx and pcall(function()
            util:SendSystemAnnounce(ctx, Lib.BANNER)
        end)
        if not sent then
            print("[PalLibLoader] chat announce skipped (no world)")
        end
    end))
end

-- onPlayerPossessed = the player is actually in and controlling a pawn.
-- It fires again on every respawn, hence the guard.
local announced = false
Lib.PalEvents.onPlayerPossessed(function()
    if announced then return end
    announced = true
    ExecuteWithDelay(5000, pin(announce))
end)
