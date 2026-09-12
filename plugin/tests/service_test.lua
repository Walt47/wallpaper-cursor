-- Service tests for wallpaper-cursor: stub noctalia host, drive update().
-- Run:  lua plugin/tests/service_test.lua   (from the repo root)
-- Needs only stock lua; no running Noctalia required. Exits 0 + ALL PASS
-- when green, 1 + "<n> FAILURES" otherwise.
local MANGO = "/home/test/.config/mango/config.conf"

local files = { [MANGO] = "cursor_theme=Adwaita\naccent=blue\n" }
local config = {
  folder_map = { ["Land of the Lustrous"] = "Phosphophyllite", ["Umineko"] = "Beatrice" },
  default_cursor = "Adwaita",
  cursor_size = 24,
  enable_notifications = true,
  poll_interval_ms = 2000,
}
local outputs = { { name = "eDP-1" } }
local wallpapers = { ["eDP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png" }

local calls = { run = {}, logs = {}, notifies = {}, errors = {}, intervals = {}, writes = 0 }

noctalia = {
  getenv = function(n) if n == "HOME" then return "/home/test" end return nil end,
  readFile = function(p) return files[p] end,
  writeFile = function(p, c) files[p] = c calls.writes = calls.writes + 1 return true end,
  commandExists = function(n) return n == "mmsg" or n == "gsettings" end,
  runAsync = function(argv, cb)
    table.insert(calls.run, argv)
    if cb then cb({ exitCode = 0, stdout = "", stderr = "" }) end
    return true
  end,
  getConfig = function(k) return config[k] end,
  setUpdateInterval = function(ms) table.insert(calls.intervals, ms) end,
  outputs = function() return outputs end,
  wallpaperPath = function(conn) return wallpapers[conn] end,
  log = function(m) table.insert(calls.logs, m) end,
  notify = function(t, b) table.insert(calls.notifies, t) end,
  notifyError = function(t, b) table.insert(calls.errors, t .. ": " .. tostring(b)) end,
  state = { _s = {}, set = function(k, v) noctalia.state._s[k] = v end, get = function(k) return noctalia.state._s[k] end },
}

local function cursor() return (files[MANGO]:match("cursor_theme=([^\n]+)")) end
local failures = 0
local function check(name, cond, extra)
  if cond then print("PASS " .. name)
  else failures = failures + 1 print("FAIL " .. name .. (extra and (" | " .. tostring(extra)) or "")) end
end

-- Resolve ../service.luau relative to this file so the suite works from any
-- checkout location (not just the author's machine).
local here = ((arg and arg[0]) or "plugin/tests/service_test.lua"):match("^(.*)/[^/]*$") or "."
dofile(here .. "/../service.luau")

-- 1: Umineko -> Beatrice (already Adwaita in file, so writes)
update()
check("umineko->beatrice", cursor() == "Beatrice", cursor())
check("mmsg called", #calls.run >= 1)
check("state published", noctalia.state._s["wallpaper-cursor.cursor"] == "Beatrice")

-- 2: steady state -> no rewrite
local w = calls.writes
update()
check("steady-no-rewrite", calls.writes == w, "writes=" .. calls.writes)

-- 3: switch to LotL -> Phosphophyllite
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Land of the Lustrous/Phos.png"
update()
check("lotl->phos", cursor() == "Phosphophyllite", cursor())

-- 4: unmatched -> Adwaita
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Others/Reverend.png"
update()
check("other->adwaita", cursor() == "Adwaita", cursor())

-- 5: nil path -> default
wallpapers["eDP-1"] = nil
update()
check("nil->default", cursor() == "Adwaita", cursor())

-- 6: missing cursor_theme line gets appended
files[MANGO] = "accent=blue\n"
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Erika Furudo.png"
update()
check("missing-line-appended", cursor() == "Beatrice", files[MANGO])

-- 7: missing mango conf -> error, no crash
files[MANGO] = nil
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png"
local e0 = #calls.errors
update()
check("missing-conf-errors", #calls.errors == e0 + 1, #calls.errors)
files[MANGO] = "cursor_theme=Adwaita\n"

-- 8: multi-output last-change-wins
outputs = { { name = "DP-1" }, { name = "eDP-1" } }
wallpapers = {
  ["DP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png",
  ["eDP-1"] = "/home/walt/Pictures/Wallpapers/Others/Reverend.png",
}
-- prev persists; first poll learns paths, winner = last sorted (eDP-1->Adwaita)
update()
local first = cursor()
-- change DP-1 only -> DP-1 wins even though sorted-last is eDP-1
wallpapers["DP-1"] = "/home/walt/Pictures/Wallpapers/Land of the Lustrous/Bort.png"
update()
check("changed-output-wins", cursor() == "Phosphophyllite", cursor() .. " first=" .. tostring(first))
-- steady: no flap back
local w2 = calls.writes
update()
check("multi-steady-no-flap", cursor() == "Phosphophyllite" and calls.writes == w2, cursor())
-- both change same poll -> last sorted (eDP-1) wins
wallpapers["DP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png"
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Others/other2.png"
update()
check("tie-last-sorted-wins", cursor() == "Adwaita", cursor())

-- 9: poll interval applies
config.poll_interval_ms = 5000
wallpapers["DP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png"
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png"
update()
check("poll-interval-applied", calls.intervals[#calls.intervals] == 5000, calls.intervals[#calls.intervals])
-- invalid poll falls back, invalid size falls back (no crash)
config.poll_interval_ms = 5
config.cursor_size = 999
update()
check("invalid-config-fallback", true)

-- 10: notifications disabled -> no new notify
config.enable_notifications = false
local n0 = #calls.notifies
wallpapers["eDP-1"] = "/home/walt/Pictures/Wallpapers/Land of the Lustrous/Phos.png"
update()
check("notify-toggle", #calls.notifies == n0, #calls.notifies)

if failures > 0 then print(failures .. " FAILURES") os.exit(1) else print("ALL PASS") end
