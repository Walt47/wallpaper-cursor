-- Panel tests for wallpaper-cursor: stub noctalia host, drive the two-job board.
-- Run:  lua plugin/tests/panel_test.lua   (from the repo root)
-- Needs only stock lua; no running Noctalia required. Exits 0 + ALL PASS
-- when green, 1 + "<n> FAILURES" otherwise.

local SETTINGS = "/home/test/.local/state/noctalia/settings.toml"
local settings_seed = table.concat({
  "config_version = 14",
  "",
  "[bar.default]",
  "thickness = 50",
  "",
  '[plugin_settings."walt/wallpaper-cursor"]',
  "cursor_size = 24",
  "",
  '    [plugin_settings."walt/wallpaper-cursor".folder_map]',
  '    Umineko = "Beatrice"',
  "",
  "[theme]",
  'mode = "dark"',
}, "\n")

local config = {
  wallpaper_root = "/pics/Wallpapers",
  icon_root = "/icons",
}
local live_outputs = { { name = "eDP-1" } }
local focused_name = "eDP-1"
local has_xdg = true
local fail_writes = false

local files = { [SETTINGS] = settings_seed }
local fs_children = {
  ["/pics/Wallpapers"] = { "Umineko", "Others", "Land of the Lustrous", "loose.txt", 'Weird"Name' },
  ["/pics/Wallpapers/Umineko"] = { "Beatrice.png", "Erika.JPG", "notes.txt", "thumbs" },
  ["/pics/Wallpapers/Umineko/thumbs"] = {},
  ["/pics/Wallpapers/Others"] = {},
  ["/pics/Wallpapers/Land of the Lustrous"] = { "Phos.png" },
  ["/pics/Wallpapers/Weird\"Name"] = {},
  ["/icons"] = { "Beatrice", "Phosphophyllite", "hicolor", "notes.txt" },
  ["/icons/Beatrice"] = {},
  ["/icons/Beatrice/cursors"] = {},
  ["/icons/Phosphophyllite"] = {},
  ["/icons/Phosphophyllite/cursors"] = {},
  ["/icons/hicolor"] = {},
}
local fs_files = {
  ["/pics/Wallpapers/loose.txt"] = true,
  ["/pics/Wallpapers/Umineko/Beatrice.png"] = true,
  ["/pics/Wallpapers/Umineko/Erika.JPG"] = true,
  ["/pics/Wallpapers/Umineko/notes.txt"] = true,
  ["/pics/Wallpapers/Land of the Lustrous/Phos.png"] = true,
  ["/icons/notes.txt"] = true,
}

local calls = { run = {}, notes = {}, logs = {}, applied = {}, writes = {} }
local watchers = {}

local tr_templates = {
  ["panel.title"] = "Wallpaper Cursor",
  ["panel.unknown"] = "Unknown",
  ["panel.pick_title"] = "Pick",
  ["panel.pick_folder"] = "Folder",
  ["panel.pick_cursor"] = "Cursor",
  ["panel.pick_image"] = "Image",
  ["panel.apply"] = "Apply",
  ["panel.no_images"] = "No images here",
  ["panel.open_folder"] = "Open",
  ["panel.save"] = "Save",
  ["panel.saved"] = "Saved!",
  ["panel.save_failed"] = "Save failed!",
}

noctalia = {
  getConfig = function(k) return config[k] end,
  getenv = function(n)
    if n == "HOME" then return "/home/test" end
    return nil
  end,
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
  readFile = function(p) return files[p] end,
  writeFile = function(p, c)
    if fail_writes then return false end
    files[p] = c
    table.insert(calls.writes, p)
    return true
  end,
  focusedOutputName = function() return focused_name end,
  outputs = function() return live_outputs end,
  wallpaperPath = function(conn) return nil end,
  setWallpaper = function(conn, path)
    table.insert(calls.applied, { conn = conn, path = path })
    return true
  end,
  runAsync = function(argv, cb)
    table.insert(calls.run, argv)
    if cb then cb({ exitCode = 0, stdout = "", stderr = "" }) end
    return true
  end,
  openSettings = function() error("must not be called") end,
  notify = function(t, b) table.insert(calls.notes, { title = t, body = b }) end,
  log = function(m) table.insert(calls.logs, m) end,
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

local function texts_exact(texts, s)
  for _, t in ipairs(texts) do
    if t == s then return true end
  end
  return false
end

local function find_select(tree, handler)
  local found = nil
  walk(tree, function(n)
    if found == nil and n.type == "select" and type(n.props) == "table"
      and n.props.onChange == handler then
      found = n
    end
  end)
  return found
end

local function find_button(tree, handler)
  local found = nil
  walk(tree, function(n)
    if found == nil and n.type == "button" and type(n.props) == "table"
      and n.props.onClick == handler then
      found = n
    end
  end)
  return found
end

local function find_folder_buttons(tree)
  local out = {}
  walk(tree, function(n)
    if n.type == "button" and type(n.props) == "table" and n.props.glyph == "photo" then
      table.insert(out, n)
    end
  end)
  return out
end

local function latest()
  return panel.renders[#panel.renders]
end

local function fire_watch(key, value)
  local list = watchers[key] or {}
  for _, fn in ipairs(list) do
    fn(value)
  end
end

-- Seed board state: cursor + per-output wallpapers.
noctalia.state._s["wallpaper-cursor.board"] = {
  cursor = "Beatrice",
  outputs = {
    { name = "eDP-1", wallpaper = "/pics/Wallpapers/Umineko/Beatrice.png" },
  },
}
noctalia.state._s["wallpaper-cursor.cursor"] = "Beatrice"

-- Pick helper: choose an option by name (0-based contract), re-render.
local function pick(handler, name)
  local sel = find_select(latest(), handler)
  if sel == nil or type(sel.props.options) ~= "table" then return false end
  for i, v in ipairs(sel.props.options) do
    if v == name then
      if handler == "onPickFolder" then onPickFolder(tostring(i - 1))
      elseif handler == "onPickCursor" then onPickCursor(tostring(i - 1))
      elseif handler == "onPickImage" then onPickImage(tostring(i - 1)) end
      panel.renders = {}
      onOpen(nil)
      return true
    end
  end
  return false
end

-- 1: two-job layout only — no trace of the old sections
panel.renders = {}
onOpen(nil)
check("open-renders", #panel.renders >= 1, #panel.renders)
check("title-present", texts_contain(collect_texts(latest()), "Wallpaper Cursor"))
check("pick-uminekubeatrice0", pick("onPickFolder", "Umineko") and pick("onPickCursor", "Beatrice"))
local t1 = latest()
local texts1 = collect_texts(t1)
check("folder-select", find_select(t1, "onPickFolder") ~= nil)
check("image-select", find_select(t1, "onPickImage") ~= nil)
check("cursor-select", find_select(t1, "onPickCursor") ~= nil)
check("apply-button", find_button(t1, "onApplyWallpaper") ~= nil)
check("save-button", find_button(t1, "onSaveMapping") ~= nil)
check("shortcut-buttons", #find_folder_buttons(t1) == 2, #find_folder_buttons(t1))
check("separators", (function()
  local n = 0
  walk(t1, function(node)
    if node.type == "separator" then n = n + 1 end
  end)
  return n == 3
end)())
check("no-old-prev", find_button(t1, "onPrev") == nil)
check("no-old-next", find_button(t1, "onNext") == nil)
check("no-old-settings", find_button(t1, "onSettings") == nil)
check("no-old-mapping", not texts_exact(texts1, "Folder mapping"))
check("no-old-outputs", not texts_exact(texts1, "Wallpapers"))
check("no-old-active", not texts_exact(texts1, "Active cursor"))
check("title-glyph-photo", (function()
  local found = false
  walk(t1, function(n)
    if n.type == "glyph" and type(n.props) == "table" and n.props.name == "photo" then
      found = true
    end
  end)
  return found
end)())

-- 2: discovery — sorted folders, cursor marker filter, image filter
local foldersel = find_select(latest(), "onPickFolder")
local fopts = (foldersel ~= nil and foldersel.props.options) or {}
check("folder-options", #fopts == 4 and fopts[1] == "Land of the Lustrous" and fopts[2] == "Others" and fopts[3] == "Umineko" and fopts[4] == 'Weird"Name')
local cursel = find_select(latest(), "onPickCursor")
local copts = (cursel ~= nil and cursel.props.options) or {}
check("cursor-options", #copts == 2 and copts[1] == "Beatrice" and copts[2] == "Phosphophyllite")
check("roots-line", texts_contain(collect_texts(latest()), "/pics/Wallpapers"))

-- 3: picks drive the preview pair
check("pick-uminekophos", pick("onPickFolder", "Umineko") and pick("onPickCursor", "Phosphophyllite"))
check("preview-pair", texts_contain(collect_texts(latest()), "Umineko => Phosphophyllite"))

-- 4: image options exclude dirs and non-images; apply targets focused output
local imsel = find_select(latest(), "onPickImage")
local imopts = (imsel ~= nil and imsel.props.options) or {}
check("image-options", #imopts == 2 and imopts[1] == "Beatrice.png" and imopts[2] == "Erika.JPG")
calls.applied = {}
onApplyWallpaper()
check("apply-focused", #calls.applied == 1 and calls.applied[1].conn == "eDP-1" and calls.applied[1].path == "/pics/Wallpapers/Umineko/Beatrice.png", calls.applied[1] and (tostring(calls.applied[1].conn) .. "|" .. tostring(calls.applied[1].path)))
check("pick-second-image", pick("onPickImage", "Erika.JPG"))
calls.applied = {}
onApplyWallpaper()
check("apply-second-image", #calls.applied == 1 and calls.applied[1].path == "/pics/Wallpapers/Umineko/Erika.JPG")
focused_name = nil
calls.applied = {}
onApplyWallpaper()
check("apply-fallback-output", #calls.applied == 1 and calls.applied[1].conn == "eDP-1")
focused_name = "eDP-1"

-- 5: empty folder disables apply; save is a no-op without picks
check("pick-empty-others", pick("onPickFolder", "Others"))
local t5 = latest()
check("image-empty-label", texts_contain(collect_texts(t5), "No images here"))
local apply5 = find_button(t5, "onApplyWallpaper")
check("apply-disabled-empty", apply5 ~= nil and apply5.props.enabled == false)
calls.applied = {}
onApplyWallpaper()
check("apply-noop-empty", #calls.applied == 0, #calls.applied)

-- 6: save updates an existing row, byte-identical otherwise
check("pick-uminekophos6", pick("onPickFolder", "Umineko") and pick("onPickCursor", "Phosphophyllite"))
calls.run = {}
calls.notes = {}
local before = files[SETTINGS]
onSaveMapping()
local after = files[SETTINGS]
local expected = string.gsub(before, '    Umineko = "Beatrice"', '    Umineko = "Phosphophyllite"', 1)
check("save-updates-row", after == expected, after)
check("save-backup", files[SETTINGS .. ".bak-wallpaper-cursor"] == before)
local reloaded = false
for _, argv in ipairs(calls.run) do
  if #argv == 3 and argv[1] == "noctalia" and argv[2] == "msg" and argv[3] == "config-reload" then
    reloaded = true
  end
end
check("save-reloads", reloaded)
check("save-notify", #calls.notes == 1 and calls.notes[1].title == "Saved!" and calls.notes[1].body == "Umineko → Phosphophyllite", calls.notes[1] and (tostring(calls.notes[1].title) .. "|" .. tostring(calls.notes[1].body)))

-- 7: save adds a spaced folder as a quoted row (folder_map currently Umineko-only again)
files[SETTINGS] = before
files[SETTINGS .. ".bak-wallpaper-cursor"] = nil
check("pick-landphos", pick("onPickFolder", "Land of the Lustrous") and pick("onPickCursor", "Phosphophyllite"))
calls.run = {}
calls.notes = {}
onSaveMapping()
local added = files[SETTINGS]
check("save-adds-quoted", string.find(added, '"Land of the Lustrous" = "Phosphophyllite"', 1, true) ~= nil, added)
check("save-keeps-old", string.find(added, 'Umineko = "Beatrice"', 1, true) ~= nil)
check("save-keeps-tail", string.find(added, '[theme]', 1, true) ~= nil and string.find(added, 'mode = "dark"', 1, true) ~= nil)

-- 8: save escapes quotes in folder names
files[SETTINGS] = before
files[SETTINGS .. ".bak-wallpaper-cursor"] = nil
check("pick-weird", pick("onPickFolder", 'Weird"Name') and pick("onPickCursor", "Beatrice"))
onSaveMapping()
check("save-escapes", string.find(files[SETTINGS], '"Weird\\"Name" = "Beatrice"', 1, true) ~= nil, files[SETTINGS])

-- 9: missing map section is appended; missing file aborts loudly
files[SETTINGS] = table.concat({
  '[plugin_settings."walt/wallpaper-cursor"]',
  "cursor_size = 24",
  "",
  "[theme]",
  'mode = "dark"',
  "",
}, "\n")
files[SETTINGS .. ".bak-wallpaper-cursor"] = nil
check("pick-uminekobeatrice2", pick("onPickFolder", "Umineko") and pick("onPickCursor", "Beatrice"))
calls.run = {}
calls.notes = {}
onSaveMapping()
local appended = files[SETTINGS]
check("save-appends-header", string.find(appended, '[plugin_settings."walt/wallpaper-cursor".folder_map]', 1, true) ~= nil)
check("save-appends-row", string.find(appended, 'Umineko = "Beatrice"', 1, true) ~= nil)
check("save-appends-keeps", string.find(appended, 'cursor_size = 24', 1, true) ~= nil)
files[SETTINGS] = nil
files[SETTINGS .. ".bak-wallpaper-cursor"] = nil
calls.run = {}
calls.notes = {}
onSaveMapping()
check("save-missing-file-notify", #calls.notes == 1 and calls.notes[1].title == "Save failed!")
local wrote_anything = files[SETTINGS] ~= nil or files[SETTINGS .. ".bak-wallpaper-cursor"] ~= nil
check("save-missing-file-untouched", not wrote_anything)
local reloaded2 = false
for _, argv in ipairs(calls.run) do
  if argv[3] == "config-reload" then reloaded2 = true end
end
check("save-missing-file-no-reload", not reloaded2)
files[SETTINGS] = before

-- 10: write failure keeps the original and reports
fail_writes = true
check("pick-uminekobeatrice3", pick("onPickFolder", "Umineko") and pick("onPickCursor", "Beatrice"))
calls.notes = {}
onSaveMapping()
check("save-fail-keeps-original", files[SETTINGS] == before, files[SETTINGS])
check("save-fail-notify", #calls.notes == 1 and calls.notes[1].title == "Save failed!")
fail_writes = false

-- 11: no folders at all — save button disabled, save is a silent no-op
config.wallpaper_root = nil
config.icon_root = nil
panel.renders = {}
onOpen(nil)
local t11 = latest()
local save11 = find_button(t11, "onSaveMapping")
check("save-disabled-empty", save11 ~= nil and save11.props.enabled == false)
calls.run = {}
calls.notes = {}
local writes_before = 0
for _ in pairs(files) do writes_before = writes_before + 1 end
onSaveMapping()
local writes_after = 0
for _ in pairs(files) do writes_after = writes_after + 1 end
check("save-noop-empty", writes_after == writes_before and #calls.run == 0 and #calls.notes == 0)
onClose()

-- 12: folder shortcut buttons and watch behavior
config.wallpaper_root = "/pics/Wallpapers"
config.icon_root = "/icons"
panel.renders = {}
onOpen(nil)
check("shortcut-count", #find_folder_buttons(latest()) == 2, #find_folder_buttons(latest()))
calls.run = {}
for _, b in ipairs(find_folder_buttons(latest())) do
  b.props.onClick()
end
local opened = {}
for _, argv in ipairs(calls.run) do
  if argv[1] == "xdg-open" then opened[argv[2]] = true end
end
check("shortcut-wallpapers", opened["/pics/Wallpapers"] == true)
check("shortcut-icons", opened["/icons"] == true)
has_xdg = false
panel.renders = {}
onOpen(nil)
check("no-xdg-no-buttons", #find_folder_buttons(latest()) == 0)
has_xdg = true
check("watch-registered", watchers["wallpaper-cursor.board"] ~= nil and #watchers["wallpaper-cursor.board"] >= 1)
local n0 = #panel.renders
local function fire_watch(key, value)
  for _, fn in ipairs(watchers[key] or {}) do
    fn(value)
  end
end
fire_watch("wallpaper-cursor.board", { cursor = "X", outputs = {} })
check("watch-rerenders-while-open", #panel.renders == n0 + 1, #panel.renders - n0)
onClose()
local n1 = #panel.renders
fire_watch("wallpaper-cursor.board", { cursor = "Y", outputs = {} })
check("watch-silent-after-close", #panel.renders == n1, #panel.renders - n1)

-- 13: never crashes on nil/empty configs
config.wallpaper_root = nil
config.icon_root = nil
noctalia.state._s["wallpaper-cursor.board"] = nil
live_outputs = nil
local ok = pcall(function() onOpen(nil) end)
check("nil-config-no-crash", ok)
local ok2 = pcall(function() onClose() end)
check("close-no-crash", ok2)

if failures > 0 then print(failures .. " FAILURES") os.exit(1) else print("ALL PASS") end
