-- Widget tests for wallpaper-cursor: stub noctalia host, drive widget.luau.
-- Run:  lua plugin/tests/widget_test.lua   (from the repo root)
-- Needs only stock lua; no running Noctalia required. Exits 0 + ALL PASS
-- when green, 1 + "<n> FAILURES" otherwise.
local PANEL_ID = "walt/wallpaper-cursor:board"

local config = { show_label = true }

local calls = {
  intervals = {},
  toggles = {},
  settings = 0,
  tr = {},
  logs = {},
  render_misuse = 0,
}

local bar = { glyph = nil, text = nil, tooltip = nil }

barWidget = {
  setGlyph = function(g) bar.glyph = g end,
  setText = function(t) bar.text = t end,
  setTooltip = function(t) bar.tooltip = t end,
  outputName = function() return "eDP-1" end,
  render = function(_tree) calls.render_misuse = calls.render_misuse + 1 end,
}

noctalia = {
  getConfig = function(k) return config[k] end,
  setUpdateInterval = function(ms) table.insert(calls.intervals, ms) end,
  togglePanel = function(id) table.insert(calls.toggles, id) end,
  openSettings = function() calls.settings = calls.settings + 1 end,
  tr = function(key, subst)
    table.insert(calls.tr, { key = key, subst = subst })
    local c = ""
    local w = ""
    if type(subst) == "table" then
      if subst.cursor ~= nil then c = tostring(subst.cursor) end
      if subst.wallpaper ~= nil then w = tostring(subst.wallpaper) end
    end
    return key .. "|cursor=" .. c .. "|wallpaper=" .. w
  end,
  log = function(m) table.insert(calls.logs, m) end,
  state = {
    _s = {},
    _w = {},
    set = function(k, v)
      noctalia.state._s[k] = v
      local watchers = noctalia.state._w[k]
      if watchers ~= nil then
        for _, fn in ipairs(watchers) do
          fn(v)
        end
      end
    end,
    get = function(k) return noctalia.state._s[k] end,
    watch = function(k, fn)
      if noctalia.state._w[k] == nil then
        noctalia.state._w[k] = {}
      end
      table.insert(noctalia.state._w[k], fn)
    end,
  },
}

-- Seed state before load so the initial render has something to show.
noctalia.state._s["wallpaper-cursor.cursor"] = "Beatrice"
noctalia.state._s["wallpaper-cursor.board"] = {
  cursor = "Beatrice",
  outputs = {
    { name = "eDP-1", wallpaper = "/pics/Umineko/Beatrice.png" },
    { name = "DP-1", wallpaper = "/pics/Other/other.png" },
  },
}

local failures = 0
local function check(name, cond, extra)
  if cond then print("PASS " .. name)
  else failures = failures + 1 print("FAIL " .. name .. (extra and (" | " .. tostring(extra)) or "")) end
end

-- Resolve ../widget.luau relative to this file so the suite works from any
-- checkout location (not just the author's machine).
local here = ((arg and arg[0]) or "plugin/tests/widget_test.lua"):match("^(.*)/[^/]*$") or "."
dofile(here .. "/../widget.luau")

-- 1: top-level interval + initial render shows published cursor
check("interval-2000", #calls.intervals >= 1 and calls.intervals[1] == 2000, calls.intervals[1])
-- Host would call update() on its tick; drive one explicitly so the test does
-- not depend on whether the widget also renders once at load.
if bar.text ~= "Beatrice" then
  update()
end
check("initial-glyph", bar.glyph == "pointer-filled", tostring(bar.glyph))
check("initial-text", bar.text == "Beatrice", tostring(bar.text))
check("initial-tooltip", type(bar.tooltip) == "string" and string.find(bar.tooltip, "Beatrice", 1, true) ~= nil, tostring(bar.tooltip))
check("tooltip-wallpaper", type(bar.tooltip) == "string" and string.find(bar.tooltip, "/pics/Umineko/Beatrice.png", 1, true) ~= nil, tostring(bar.tooltip))
check("tooltip-key", #calls.tr >= 1 and calls.tr[#calls.tr].key == "widget.tooltip", #calls.tr)

-- 2a: state update propagates via watch (no explicit update() call)
noctalia.state.set("wallpaper-cursor.cursor", "Phosphophyllite")
check("watch-propagates", bar.text == "Phosphophyllite", tostring(bar.text))

-- 2b: state update propagates via update() (bypass watch to isolate the path)
noctalia.state._s["wallpaper-cursor.cursor"] = "Adwaita"
update()
check("update-propagates", bar.text == "Adwaita", tostring(bar.text))

-- 3: show_label=false hides text (glyph only)
config.show_label = false
update()
check("show-label-false-hides", bar.text == "", "text=" .. tostring(bar.text))
check("show-label-false-glyph", bar.glyph == "pointer-filled", tostring(bar.glyph))

-- 3b: show_label default (nil) shows text again
config.show_label = nil
update()
check("show-label-default-shows", bar.text == "Adwaita", tostring(bar.text))

-- restore explicit true for remaining cases
config.show_label = true
update()

-- 4: onClick toggles the exact panel id
calls.toggles = {}
onClick()
check("onclick-panel", #calls.toggles == 1 and calls.toggles[1] == PANEL_ID, table.concat(calls.toggles, ","))

-- 5: onRightClick opens settings
local s0 = calls.settings
onRightClick()
check("rightclick-settings", calls.settings == s0 + 1, calls.settings)

-- 6: onIpc toggle works, other events ignored
calls.toggles = {}
onIpc("toggle", nil)
check("ipc-toggle", #calls.toggles == 1 and calls.toggles[1] == PANEL_ID, table.concat(calls.toggles, ","))
local n0 = #calls.toggles
onIpc("other", nil)
check("ipc-other-ignored", #calls.toggles == n0, #calls.toggles)

-- 7: nil state renders placeholder without crashing
noctalia.state.set("wallpaper-cursor.cursor", nil)
noctalia.state.set("wallpaper-cursor.board", nil)
local ok, err = pcall(update)
check("nil-no-crash", ok, err)
check("nil-placeholder", bar.text == "…", tostring(bar.text))
check("nil-tooltip-string", type(bar.tooltip) == "string", tostring(bar.tooltip))

-- 8: imperative API only (never barWidget.render)
check("no-render-misuse", calls.render_misuse == 0, calls.render_misuse)

if failures > 0 then print(failures .. " FAILURES") os.exit(1) else print("ALL PASS") end
