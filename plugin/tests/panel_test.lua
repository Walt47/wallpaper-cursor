-- Panel tests for wallpaper-cursor: stub noctalia host, drive onOpen/onClose/buttons/watch.
-- Run:  lua plugin/tests/panel_test.lua   (from the repo root)
-- Needs only stock lua; no running Noctalia required. Exits 0 + ALL PASS
-- when green, 1 + "<n> FAILURES" otherwise.

local config = {
  folder_map = { Zebra = "CursorZ", Apple = "CursorA", Mango = "CursorM" },
  default_cursor = "Adwaita",
}
local live_outputs = { { name = "eDP-1" } }
local live_wallpapers = { ["eDP-1"] = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png" }
local focused_name = "eDP-1"
local has_xdg = true

-- Fake filesystem for discovery: dirs map to their children; files are
-- listed with isDir=false; anything else is missing (nil).
local fs_children = {
  ["/pics/Wallpapers"] = { "Umineko", "Others", "loose.txt" },
  ["/pics/Wallpapers/Umineko"] = {},
  ["/pics/Wallpapers/Others"] = {},
  ["/icons"] = { "Beatrice", "Phosphophyllite", "hicolor", "notes.txt" },
  ["/icons/Beatrice"] = {},
  ["/icons/Beatrice/cursors"] = {},
  ["/icons/Phosphophyllite"] = {},
  ["/icons/Phosphophyllite/cursors"] = {},
  ["/icons/hicolor"] = {},
}
local fs_files = {
  ["/pics/Wallpapers/loose.txt"] = true,
  ["/icons/notes.txt"] = true,
}

local calls = { run = {}, settings = 0, logs = {} }
local watchers = {}

local tr_templates = {
  ["panel.title"] = "Wallpaper Cursor",
  ["panel.active_cursor"] = "Active cursor",
  ["panel.outputs"] = "Outputs",
  ["panel.mapping"] = "Mapping",
  ["panel.previous"] = "Previous",
  ["panel.next"] = "Next",
  ["panel.settings"] = "Settings",
  ["panel.unknown"] = "Unknown",
  ["panel.default_row"] = "Default: {cursor}",
}

noctalia = {
  getConfig = function(k) return config[k] end,
  focusedOutputName = function() return focused_name end,
  outputs = function() return live_outputs end,
  wallpaperPath = function(conn) return live_wallpapers[conn] end,
  runAsync = function(argv, cb)
    table.insert(calls.run, argv)
    if cb then cb({ exitCode = 0, stdout = "", stderr = "" }) end
    return true
  end,
  openSettings = function() calls.settings = calls.settings + 1 end,
  log = function(m) table.insert(calls.logs, m) end,
  expandPath = function(p) return (string.gsub(p, "^~", "/home/test")) end,
  listDir = function(path) return fs_children[path] end,
  fileInfo = function(path)
    if fs_children[path] ~= nil then
      return { size = 0, mtime = 0, isDir = true }
    end
    if fs_files[path] then
      return { size = 10, mtime = 0, isDir = false }
    end
    return nil
  end,
  commandExists = function(n)
    if n == "xdg-open" then return has_xdg end
    return false
  end,
  tr = function(key, subst)
    local s = tr_templates[key] or key
    if subst then
      for k, v in pairs(subst) do
        s = string.gsub(s, "{" .. k .. "}", tostring(v))
      end
    end
    return s
  end,
  state = {
    _s = {},
    set = function(k, v) noctalia.state._s[k] = v end,
    get = function(k) return noctalia.state._s[k] end,
    watch = function(k, fn)
      watchers[k] = watchers[k] or {}
      table.insert(watchers[k], fn)
    end,
  },
}

panel = {
  renders = {},
  closed = false,
  render = function(tree) table.insert(panel.renders, tree) end,
  close = function() panel.closed = true end,
}

local function ctor(typ)
  return function(props, children)
    if type(props) ~= "table" then props = {} end
    if type(children) ~= "table" then children = {} end
    return { type = typ, props = props, children = children }
  end
end

ui = {
  column = ctor("column"),
  row = ctor("row"),
  label = ctor("label"),
  glyph = ctor("glyph"),
  button = ctor("button"),
  separator = ctor("separator"),
  select = ctor("select"),
}

local failures = 0
local function check(name, cond, extra)
  if cond then print("PASS " .. name)
  else failures = failures + 1 print("FAIL " .. name .. (extra and (" | " .. tostring(extra)) or "")) end
end

-- Resolve ../panel.luau relative to this file so the suite works from any
-- checkout location (not just the author's machine).
local here = ((arg and arg[0]) or "plugin/tests/panel_test.lua"):match("^(.*)/[^/]*$") or "."
dofile(here .. "/../panel.luau")

local function walk(node, fn)
  if type(node) ~= "table" then return end
  fn(node)
  local ch = node.children
  if type(ch) == "table" then
    for _, c in ipairs(ch) do
      walk(c, fn)
    end
  end
end

local function collect_texts(tree)
  local out = {}
  walk(tree, function(n)
    if type(n.props) == "table" then
      if type(n.props.text) == "string" then table.insert(out, n.props.text) end
      if type(n.props.name) == "string" then table.insert(out, n.props.name) end
    end
  end)
  return out
end

local function texts_contain(texts, sub)
  for _, t in ipairs(texts) do
    if string.find(t, sub, 1, true) then return true end
  end
  return false
end

local function find_buttons(tree)
  local out = {}
  walk(tree, function(n)
    if n.type == "button" then table.insert(out, n) end
  end)
  return out
end

local function argv_equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function fire_watch(key, value)
  local list = watchers[key] or {}
  for _, fn in ipairs(list) do
    fn(value)
  end
end

local function latest()
  return panel.renders[#panel.renders]
end

-- Seed board state: cursor + per-output wallpapers.
noctalia.state._s["wallpaper-cursor.board"] = {
  cursor = "Beatrice",
  outputs = {
    { name = "eDP-1", wallpaper = "/home/walt/Pictures/Wallpapers/Umineko/Beatrice.png" },
    { name = "DP-1", wallpaper = "/home/walt/Pictures/Wallpapers/Others/Reverend.png" },
  },
}
noctalia.state._s["wallpaper-cursor.cursor"] = "Beatrice"

-- 1: onOpen renders tree containing title, active cursor, sorted mapping, default row
panel.renders = {}
onOpen(nil)
check("open-renders", #panel.renders >= 1, #panel.renders)
local t1 = latest()
local texts1 = collect_texts(t1)
check("title-present", texts_contain(texts1, "Wallpaper Cursor"))
check("title-glyph", texts_contain(texts1, "photo"))
check("title-glyph-exact", (function()
  local found = false
  walk(t1, function(n)
    if n.type == "glyph" and type(n.props) == "table" and n.props.name == "photo" then
      found = true
    end
  end)
  return found
end)())
check("title-styled", (function()
  local ok = false
  walk(t1, function(n)
    if n.type == "label" and type(n.props) == "table"
      and n.props.text == "Wallpaper Cursor"
      and n.props.fontWeight == "bold" and n.props.fontSize == 16 then
      ok = true
    end
  end)
  return ok
end)())
check("section-separators", (function()
  local n = 0
  walk(t1, function(node)
    if node.type == "separator" then n = n + 1 end
  end)
  return n == 5
end)(), "separators")
check("headers-bold", (function()
  local bold = {}
  walk(t1, function(n)
    if n.type == "label" and type(n.props) == "table" and n.props.fontWeight == "bold"
      and type(n.props.text) == "string" then
      bold[n.props.text] = true
    end
  end)
  return bold["Outputs"] and bold["Mapping"]
end)())
check("buttons-stacked", (function()
  local ok = true
  walk(t1, function(n)
    if n.type == "row" and type(n.children) == "table" then
      local nb = 0
      for _, c in ipairs(n.children) do
        if type(c) == "table" and c.type == "button" then nb = nb + 1 end
      end
      if nb > 1 then ok = false end
    end
  end)
  return ok
end)())
check("active-label", texts_contain(texts1, "Active cursor"))
check("active-cursor", texts_contain(texts1, "Beatrice"))
-- sorted mapping rows: collect labels containing the arrow in DFS order
local arrow_rows = {}
walk(t1, function(n)
  if n.type == "label" and type(n.props) == "table" and type(n.props.text) == "string" then
    if string.find(n.props.text, "→", 1, true) then
      table.insert(arrow_rows, n.props.text)
    end
  end
end)
check("mapping-count", #arrow_rows == 3, #arrow_rows)
local ia, im, iz = nil, nil, nil
for i, s in ipairs(arrow_rows) do
  if string.find(s, "Apple", 1, true) then ia = i end
  if string.find(s, "Mango", 1, true) then im = i end
  if string.find(s, "Zebra", 1, true) then iz = i end
end
check("mapping-sorted", ia ~= nil and im ~= nil and iz ~= nil and ia < im and im < iz,
  "ia=" .. tostring(ia) .. " im=" .. tostring(im) .. " iz=" .. tostring(iz))
check("mapping-row-content",
  texts_contain(texts1, "Apple") and texts_contain(texts1, "CursorA"))
check("default-row", texts_contain(texts1, "Default: Adwaita"))
check("outputs-header", texts_contain(texts1, "Outputs"))
check("mapping-header", texts_contain(texts1, "Mapping"))
check("output-connector", texts_contain(texts1, "eDP-1") and texts_contain(texts1, "DP-1"))
check("output-basename", texts_contain(texts1, "Beatrice.png") and texts_contain(texts1, "Reverend.png"))

-- 2: buttons exist with correct handler names
local btns = find_buttons(t1)
local by_handler = {}
for _, b in ipairs(btns) do
  by_handler[b.props.onClick] = b.props.text
end
check("btn-prev", by_handler["onPrev"] ~= nil and string.find(by_handler["onPrev"], "Previous", 1, true) ~= nil)
check("btn-next", by_handler["onNext"] ~= nil and string.find(by_handler["onNext"], "Next", 1, true) ~= nil)
check("btn-settings", by_handler["onSettings"] ~= nil and string.find(by_handler["onSettings"], "Settings", 1, true) ~= nil)

-- 3: onNext/onPrev call runAsync with exact argv incl. focused connector
focused_name = "eDP-1"
calls.run = {}
onNext()
check("next-with-connector", argv_equal(calls.run[1], { "noctalia", "msg", "wallpaper-next", "eDP-1" }))
calls.run = {}
onPrev()
check("prev-with-connector", argv_equal(calls.run[1], { "noctalia", "msg", "wallpaper-previous", "eDP-1" }))
-- without connector when nil
focused_name = nil
calls.run = {}
onNext()
check("next-no-connector", argv_equal(calls.run[1], { "noctalia", "msg", "wallpaper-next" }), #calls.run[1])
calls.run = {}
onPrev()
check("prev-no-connector", argv_equal(calls.run[1], { "noctalia", "msg", "wallpaper-previous" }))
focused_name = "eDP-1"

-- 4: onSettings calls openSettings
calls.settings = 0
onSettings()
check("settings-opens", calls.settings == 1, calls.settings)

-- 5: state-watch triggers re-render while open but not after onClose
check("watch-registered", watchers["wallpaper-cursor.board"] ~= nil and #watchers["wallpaper-cursor.board"] >= 1)
local n0 = #panel.renders
fire_watch("wallpaper-cursor.board", { cursor = "Phosphophyllite", outputs = {} })
check("watch-rerenders-while-open", #panel.renders == n0 + 1, #panel.renders - n0)
onClose()
local n1 = #panel.renders
fire_watch("wallpaper-cursor.board", { cursor = "Beatrice", outputs = {} })
check("watch-silent-after-close", #panel.renders == n1, #panel.renders - n1)

-- 6: nil board falls back to live outputs
noctalia.state._s["wallpaper-cursor.board"] = nil
noctalia.state._s["wallpaper-cursor.cursor"] = nil
live_outputs = { { name = "HDMI-1" } }
live_wallpapers = { ["HDMI-1"] = "/pics/Wallpapers/Land of the Lustrous/Phos.png" }
panel.renders = {}
onOpen(nil)
local t6 = latest()
local texts6 = collect_texts(t6)
check("fallback-connector", texts_contain(texts6, "HDMI-1"))
check("fallback-basename", texts_contain(texts6, "Phos.png"))
check("fallback-unknown-cursor", texts_contain(texts6, "Unknown"))

-- 7: empty folder_map renders default row only
config.folder_map = {}
config.default_cursor = "Adwaita"
panel.renders = {}
onOpen(nil)
local t7 = latest()
local texts7 = collect_texts(t7)
check("empty-default-row", texts_contain(texts7, "Default: Adwaita"))
local arrows7 = 0
walk(t7, function(n)
  if n.type == "label" and type(n.props) == "table" and type(n.props.text) == "string" then
    if string.find(n.props.text, "→", 1, true) then arrows7 = arrows7 + 1 end
  end
end)
check("empty-no-mapping-rows", arrows7 == 0, arrows7)
onClose()

-- 8: never crashes on nil/empty configs
config.folder_map = nil
config.default_cursor = nil
noctalia.state._s["wallpaper-cursor.board"] = nil
noctalia.state._s["wallpaper-cursor.cursor"] = nil
live_outputs = nil
live_wallpapers = {}
local ok = pcall(function() onOpen(nil) end)
check("nil-config-no-crash", ok)
local ok2 = pcall(function() onClose() end)
check("close-no-crash", ok2)

-- 9: discovery populates selects; folder buttons open exact dirs
config.folder_map = { Umineko = "Beatrice", Zzz = "Adwaita" }
config.default_cursor = "Adwaita"
config.wallpaper_root = "/pics/Wallpapers"
config.icon_root = "/icons"
has_xdg = true
noctalia.state._s["wallpaper-cursor.board"] = {
  cursor = "Beatrice",
  outputs = {
    { name = "eDP-1", wallpaper = "/pics/Wallpapers/Umineko/Beatrice.png" },
  },
}
noctalia.state._s["wallpaper-cursor.cursor"] = "Beatrice"
panel.renders = {}
onOpen(nil)
local t9 = latest()

local function find_selects(tree)
  local out = {}
  walk(tree, function(n)
    if n.type == "select" then table.insert(out, n) end
  end)
  return out
end

local function find_folder_buttons(tree)
  local out = {}
  walk(tree, function(n)
    if n.type == "button" and type(n.props) == "table" and n.props.glyph == "folder" then
      table.insert(out, n)
    end
  end)
  return out
end

local sels = find_selects(t9)
check("select-count", #sels == 3, #sels)
-- folder select: sorted subdirs, loose.txt excluded
check("folder-options", sels[1] ~= nil and sels[1].props.options ~= nil
  and #sels[1].props.options == 2
  and sels[1].props.options[1] == "Others"
  and sels[1].props.options[2] == "Umineko")
-- cursor select: cursors/ marker only (hicolor + notes.txt excluded)
local copts = (sels[2] ~= nil and sels[2].props.options) or {}
check("cursor-options", #copts == 2 and copts[1] == "Beatrice" and copts[2] == "Phosphophyllite")
-- default select presets nothing known (Adwaita not installed) -> first item
check("default-select-first", sels[3] ~= nil and sels[3].props.selectedIndex == 0)
-- preview uses => (keeps → counts stable) with first pair selected
local texts9 = collect_texts(t9)
check("preview-pair", texts_contain(texts9, "Others => Beatrice"))
-- 0-based contract: index "1" selects the second folder
onPickFolder("1")
panel.renders = {}
onOpen(nil)
check("pick-updates-preview", texts_contain(collect_texts(latest()), "Umineko => Beatrice"))
-- folder buttons: 2 mapping + 1 output + 1 default
local fbs = find_folder_buttons(latest())
check("folder-button-count", #fbs == 4, #fbs)
calls.run = {}
for _, b in ipairs(fbs) do
  b.props.onClick()
end
local opened = {}
for _, argv in ipairs(calls.run) do
  if argv[1] == "xdg-open" then opened[argv[2]] = true end
end
check("folder-opens-subdir", opened["/pics/Wallpapers/Umineko"] == true)
check("folder-opens-fallback", opened["/pics/Wallpapers"] == true)
check("folder-opens-walldir", opened["/pics/Wallpapers/Umineko"] == true)
check("folder-opens-icons", opened["/icons"] == true)
-- without xdg-open: no folder buttons, no crash
has_xdg = false
panel.renders = {}
onOpen(nil)
check("no-xdg-no-buttons", #find_folder_buttons(latest()) == 0)
has_xdg = true
-- nil roots: empty selects, unknown preview, no crash
config.wallpaper_root = nil
config.icon_root = nil
panel.renders = {}
local ok9 = pcall(function() onOpen(nil) end)
check("nil-roots-no-crash", ok9)
local texts9b = collect_texts(latest())
check("nil-roots-preview", texts_contain(texts9b, "=>"))
check("nil-roots-no-selects", #find_selects(latest()) == 0)
onClose()

if failures > 0 then print(failures .. " FAILURES") os.exit(1) else print("ALL PASS") end
