-- PalUpdate - "is there a newer release on GitHub?" check for a mod/lib.
--
--   local Lib = require("KeboldersPalLib")
--   Lib.PalUpdate.check{
--       repo    = "Kebolder/KebolderPalLib",  -- owner/name
--       current = Lib.VERSION,                 -- version you're running
--       on_newer = function(latest, current)   -- only called if latest > current
--           print("Update available: " .. latest)
--       end,
--   }
--
-- How: async curl to the GitHub releases API, matches "tag_name", compares
-- semver. No HTTP library needed - curl ships with Win10+. Everything is
-- pcall-guarded and silent on failure: a version check must NEVER break the
-- mod. Needs io.popen; if it's disabled in your UE4SS build this no-ops.
--
-- Note: this phones home to api.github.com once per call. Unauthenticated,
-- rate-limited to 60/hour per IP - fine for a check at startup.
local pin = require("KeboldersPalLib.PalCore").pin

local M = {}

-- true if dotted-numeric `remote` is a higher version than `current`
local function isNewer(remote, current)
    local function parts(v)
        local t = {}
        for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local a, b = parts(remote), parts(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

function M.check(opts)
    local repo    = assert(opts and opts.repo, "PalUpdate.check: repo required")
    local current = assert(opts.current, "PalUpdate.check: current required")
    local on_newer = opts.on_newer

    local url = "https://api.github.com/repos/" .. repo .. "/releases/latest"

    -- io.popen blocks on the network; keep it off the game thread
    local run = pin(function()
        local ok, body = pcall(function()
            local h = io.popen('curl -s -m 5 "' .. url .. '"')
            if not h then return nil end
            local out = h:read("*a")
            h:close()
            return out
        end)
        if not ok or not body then return false end

        local tag = body:match('"tag_name"%s*:%s*"([^"]+)"')
        if not tag then return false end
        local remote = tag:gsub("^[vV]", "")

        if isNewer(remote, current) and on_newer then
            -- callback likely touches UE (chat, UI) - hop back to game thread
            ExecuteInGameThread(pin(function() on_newer(remote, current) end))
        end
        return false -- LoopAsync fallback: run exactly once
    end)

    if type(ExecuteAsync) == "function" then
        ExecuteAsync(run)
    else
        LoopAsync(0, run)
    end
end

return M
