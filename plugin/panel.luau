--!nonstrict
-- Noctalia panel entry for wallpaper-cursor.
-- Declarative ui.* tree rendered via panel.render(). Watches
-- wallpaper-cursor.board and re-renders only while open. Falls back to live
-- noctalia.outputs() + noctalia.wallpaperPath() when board state is nil.
-- Plain Luau subset parseable by stock lua 5.4. plugin_api 25 only.

local is_open = false

-- Pick-section selection (lua 1-based positions into the current option lists).
local pick_folder_idx = 1
local pick_cursor_idx = 1
local default_idx = 1
local default_touched = false

local function basename(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local base = string.match(path, "([^/]+)$")
  if base ~= nil and base ~= "" then
    return base
  end
  return path
end

local function get_board()
  local ok, board = pcall(function()
    if noctalia.state ~= nil and noctalia.state.get ~= nil then
      return noctalia.state.get("wallpaper-cursor.board")
    end
    return nil
  end)
  if ok then
    return board
  end
  return nil
end

local function get_cursor(board)
  if type(board) == "table" and type(board.cursor) == "string" and board.cursor ~= "" then
    return board.cursor
  end
  local ok, c = pcall(function()
    if noctalia.state ~= nil and noctalia.state.get ~= nil then
      return noctalia.state.get("wallpaper-cursor.cursor")
    end
    return nil
  end)
  if ok and type(c) == "string" and c ~= "" then
    return c
  end
  return nil
end

local function get_folder_map()
  local ok, m = pcall(function()
    return noctalia.getConfig("folder_map")
  end)
  if ok and type(m) == "table" then
    return m
  end
  return {}
end

local function get_default_cursor()
  local ok, d = pcall(function()
    return noctalia.getConfig("default_cursor")
  end)
  if ok and type(d) == "string" and d ~= "" then
    return d
  end
  return nil
end

local function get_outputs(board)
  if type(board) == "table" and type(board.outputs) == "table" then
    return board.outputs
  end
  local ok, outs = pcall(function()
    return noctalia.outputs()
  end)
  if not ok or type(outs) ~= "table" then
    return {}
  end
  local result = {}
  for _, out in ipairs(outs) do
    if type(out) == "table" and out.name ~= nil and type(out.name) == "string" and out.name ~= "" then
      local name = out.name
      local path = nil
      local ok2, p = pcall(noctalia.wallpaperPath, name)
      if ok2 then
        path = p
      else
        path = nil
      end
      table.insert(result, { name = name, wallpaper = path })
    end
  end
  return result
end

local function expand(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local ok, out = pcall(function()
    if noctalia.expandPath ~= nil then
      return noctalia.expandPath(path)
    end
    return path
  end)
  if ok and type(out) == "string" and out ~= "" then
    return out
  end
  return path
end

local function get_root(key, fallback)
  local ok, v = pcall(function()
    return noctalia.getConfig(key)
  end)
  if ok and type(v) == "string" and v ~= "" then
    return expand(v)
  end
  return expand(fallback)
end

local function list_subdirs(root)
  if type(root) ~= "string" or root == "" then
    return {}
  end
  local ok, names = pcall(function()
    return noctalia.listDir(root)
  end)
  if not ok or type(names) ~= "table" then
    return {}
  end
  local dirs = {}
  for _, n in ipairs(names) do
    if type(n) == "string" and n ~= "" then
      local ok2, info = pcall(function()
        return noctalia.fileInfo(root .. "/" .. n)
      end)
      if ok2 and type(info) == "table" and info.isDir then
        table.insert(dirs, n)
      end
    end
  end
  table.sort(dirs)
  return dirs
end

-- A cursor theme is a subdir containing a cursors/ dir (skips hicolor etc.).
local function list_cursors(root)
  local themes = {}
  for _, n in ipairs(list_subdirs(root)) do
    local ok, info = pcall(function()
      return noctalia.fileInfo(root .. "/" .. n .. "/cursors")
    end)
    if ok and type(info) == "table" and info.isDir then
      table.insert(themes, n)
    end
  end
  return themes
end

local function dirname_of(path)
  if type(path) ~= "string" then
    return nil
  end
  local d = string.match(path, "^(.*)/[^/]*$")
  if d ~= nil and d ~= "" then
    return d
  end
  return nil
end

local function can_open()
  local ok, has = pcall(function()
    return noctalia.commandExists("xdg-open")
  end)
  return ok and has == true
end

local function open_path(path)
  if type(path) ~= "string" or path == "" then
    return
  end
  if not can_open() then
    return
  end
  noctalia.runAsync({ "xdg-open", path })
end

local function folder_button(dir, tooltip)
  if not can_open() then
    return nil
  end
  if type(dir) ~= "string" or dir == "" then
    return nil
  end
  return ui.button({
    glyph = "folder",
    variant = "ghost",
    controlSize = "sm",
    width = 28,
    height = 28,
    glyphSize = 14,
    tooltip = tooltip,
    onClick = function()
      open_path(dir)
    end,
  })
end

local function clamp_idx(i, n)
  if type(i) ~= "number" or i < 1 then
    return 1
  end
  if i > n then
    return n
  end
  return math.floor(i)
end

local function render()
  local board = get_board()
  local cursor = get_cursor(board)
  local unknown = noctalia.tr("panel.unknown")
  local cursor_text = cursor
  if type(cursor_text) ~= "string" or cursor_text == "" then
    cursor_text = unknown
  end
  local outputs = get_outputs(board)
  local folder_map = get_folder_map()
  local default_cursor = get_default_cursor()
  local default_for_row = default_cursor
  if type(default_for_row) ~= "string" or default_for_row == "" then
    default_for_row = unknown
  end

  local keys = {}
  for k, _ in pairs(folder_map) do
    if type(k) == "string" then
      table.insert(keys, k)
    end
  end
  table.sort(keys)

  local wall_root = get_root("wallpaper_root", "~/Pictures/Wallpapers")
  local icon_root = get_root("icon_root", "~/.local/share/icons")
  local open_tip = noctalia.tr("panel.open_folder")

  local output_rows = {}
  table.insert(output_rows, ui.label({ text = noctalia.tr("panel.outputs"), fontWeight = "bold" }))
  for _, o in ipairs(outputs) do
    local name = nil
    local wall = nil
    if type(o) == "table" then
      name = o.name
      wall = o.wallpaper
    end
    local disp_name = unknown
    if type(name) == "string" and name ~= "" then
      disp_name = name
    end
    local base = basename(wall)
    local disp_wall = unknown
    if base ~= nil then
      disp_wall = base
    end
    local cells = {}
    local fb = folder_button(dirname_of(wall) or wall_root, open_tip)
    if fb ~= nil then
      table.insert(cells, fb)
    end
    table.insert(cells, ui.label({ text = disp_name }))
    table.insert(cells, ui.label({ text = disp_wall }))
    table.insert(output_rows, ui.row({ gap = 8, align = "center" }, cells))
  end

  local mapping_children = {}
  table.insert(mapping_children, ui.label({ text = noctalia.tr("panel.mapping"), fontWeight = "bold" }))
  for _, folder in ipairs(keys) do
    local c = folder_map[folder]
    if type(c) ~= "string" then
      c = tostring(c)
    end
    -- Open the matching wallpaper subfolder when the key names one,
    -- otherwise fall back to the wallpaper root.
    local dir = wall_root
    if type(wall_root) == "string" and wall_root ~= "" then
      local cand = wall_root .. "/" .. folder
      local okd, info = pcall(function()
        return noctalia.fileInfo(cand)
      end)
      if okd and type(info) == "table" and info.isDir then
        dir = cand
      end
    end
    local cells = {}
    local fb = folder_button(dir, open_tip)
    if fb ~= nil then
      table.insert(cells, fb)
    end
    table.insert(cells, ui.label({ text = folder .. " → " .. c }))
    table.insert(mapping_children, ui.row({ gap = 8, align = "center" }, cells))
  end
  local def_cells = {}
  local dfb = folder_button(icon_root, open_tip)
  if dfb ~= nil then
    table.insert(def_cells, dfb)
  end
  table.insert(def_cells, ui.label({ text = noctalia.tr("panel.default_row", { cursor = default_for_row }) }))
  table.insert(mapping_children, ui.row({ gap = 8, align = "center" }, def_cells))

  -- Pick-from-disk reference: discovered names the user can copy into Settings.
  local folders = list_subdirs(wall_root)
  local cursors = list_cursors(icon_root)
  pick_folder_idx = clamp_idx(pick_folder_idx, math.max(#folders, 1))
  pick_cursor_idx = clamp_idx(pick_cursor_idx, math.max(#cursors, 1))
  if not default_touched and type(default_for_row) == "string" then
    for i, c in ipairs(cursors) do
      if c == default_for_row then
        default_idx = i
        break
      end
    end
  end
  default_idx = clamp_idx(default_idx, math.max(#cursors, 1))
  local pick_children = {}
  table.insert(pick_children, ui.label({ text = noctalia.tr("panel.pick_title"), fontWeight = "bold" }))
  table.insert(pick_children, ui.label({ text = noctalia.tr("panel.pick_folder") }))
  if #folders > 0 then
    -- selectedIndex is 0-based on the host; our indices are lua 1-based.
    table.insert(pick_children, ui.select({ options = folders, selectedIndex = pick_folder_idx - 1, onChange = "onPickFolder" }))
  else
    table.insert(pick_children, ui.label({ text = unknown }))
  end
  table.insert(pick_children, ui.label({ text = noctalia.tr("panel.pick_cursor") }))
  if #cursors > 0 then
    table.insert(pick_children, ui.select({ options = cursors, selectedIndex = pick_cursor_idx - 1, onChange = "onPickCursor" }))
  else
    table.insert(pick_children, ui.label({ text = unknown }))
  end
  local pf = folders[pick_folder_idx] or unknown
  local pc = cursors[pick_cursor_idx] or unknown
  table.insert(pick_children, ui.label({ text = pf .. " => " .. pc }))
  table.insert(pick_children, ui.label({ text = noctalia.tr("panel.pick_hint") }))
  table.insert(pick_children, ui.label({ text = noctalia.tr("panel.default_select") }))
  if #cursors > 0 then
    table.insert(pick_children, ui.select({ options = cursors, selectedIndex = default_idx - 1, onChange = "onDefaultCursor" }))
  else
    table.insert(pick_children, ui.label({ text = unknown }))
  end

  panel.render(ui.column({ gap = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "photo", size = 18 }),
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold" }),
    }),
    ui.separator({ color = "outline", thickness = 1, spacing = 4 }),
    ui.row({ gap = 8 }, {
      ui.label({ text = noctalia.tr("panel.active_cursor") }),
      ui.label({ text = cursor_text, fontWeight = "bold" }),
    }),
    ui.separator({ color = "outline", thickness = 1, spacing = 4 }),
    ui.column({ gap = 8 }, output_rows),
    ui.separator({ color = "outline", thickness = 1, spacing = 4 }),
    ui.column({ gap = 8 }, mapping_children),
    ui.separator({ color = "outline", thickness = 1, spacing = 4 }),
    ui.column({ gap = 8 }, pick_children),
    ui.separator({ color = "outline", thickness = 1, spacing = 4 }),
    ui.column({ gap = 8 }, {
      ui.button({ text = noctalia.tr("panel.previous"), onClick = "onPrev" }),
      ui.button({ text = noctalia.tr("panel.next"), onClick = "onNext" }),
      ui.button({ text = noctalia.tr("panel.settings"), onClick = "onSettings" }),
    }),
  }))
end

function onOpen(_context)
  is_open = true
  render()
end

function onClose()
  is_open = false
end

function onPrev()
  local out = noctalia.focusedOutputName()
  if out ~= nil then
    noctalia.runAsync({ "noctalia", "msg", "wallpaper-previous", out })
  else
    noctalia.runAsync({ "noctalia", "msg", "wallpaper-previous" })
  end
end

function onNext()
  local out = noctalia.focusedOutputName()
  if out ~= nil then
    noctalia.runAsync({ "noctalia", "msg", "wallpaper-next", out })
  else
    noctalia.runAsync({ "noctalia", "msg", "wallpaper-next" })
  end
end

function onSettings()
  noctalia.openSettings()
end

-- ui.select reports the chosen position as a 0-based index string.
function onPickFolder(value)
  local i = tonumber(value)
  if i ~= nil then
    pick_folder_idx = i + 1
  end
end

function onPickCursor(value)
  local i = tonumber(value)
  if i ~= nil then
    pick_cursor_idx = i + 1
  end
end

function onDefaultCursor(value)
  local i = tonumber(value)
  if i ~= nil then
    default_idx = i + 1
    default_touched = true
  end
end

pcall(function()
  if noctalia.state ~= nil and noctalia.state.watch ~= nil then
    noctalia.state.watch("wallpaper-cursor.board", function(_value)
      if is_open then
        render()
      end
    end)
  end
end)
