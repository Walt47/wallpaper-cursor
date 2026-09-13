--!nonstrict
-- Minimal board: pick a wallpaper, assign its folder a cursor.
-- Two jobs only: Set wallpaper + Save cursor mapping. Save rewrites just the
-- folder_map lines of the settings file (with backup) and reloads config so
-- the service adopts the new rule. Plain Luau subset parseable by stock
-- lua 5.4. plugin_api 25 only.

local is_open = false

-- Pick state (lua 1-based positions into the current option lists).
local pick_folder_idx = 1
local image_idx = 1
local pick_cursor_idx = 1
-- Last render's actions, consumed by the button handlers.
local last_apply = nil
local last_connector = nil
local last_pick = nil

local MAP_HEADER = '[plugin_settings."walt/wallpaper-cursor".folder_map]'
local BACKUP_SUFFIX = ".bak-wallpaper-cursor"
local IMAGE_EXTS = { png = true, jpg = true, jpeg = true, webp = true, avif = true, bmp = true }

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

local function list_images(dir)
  if type(dir) ~= "string" or dir == "" then
    return {}
  end
  local ok, names = pcall(function()
    return noctalia.listDir(dir)
  end)
  if not ok or type(names) ~= "table" then
    return {}
  end
  local imgs = {}
  for _, n in ipairs(names) do
    if type(n) == "string" and n ~= "" then
      local ext = string.match(n, "%.([^./]+)$")
      if ext ~= nil and IMAGE_EXTS[string.lower(ext)] then
        local ok2, info = pcall(function()
          return noctalia.fileInfo(dir .. "/" .. n)
        end)
        if not ok2 or type(info) ~= "table" or not info.isDir then
          table.insert(imgs, n)
        end
      end
    end
  end
  table.sort(imgs)
  return imgs
end

local function short_root(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  local home = nil
  local ok, h = pcall(function()
    if noctalia.getenv ~= nil then
      return noctalia.getenv("HOME")
    end
    return nil
  end)
  if ok and type(h) == "string" and h ~= "" then
    home = h
  else
    local ok2, h2 = pcall(function()
      return os.getenv("HOME")
    end)
    if ok2 and type(h2) == "string" and h2 ~= "" then
      home = h2
    end
  end
  if home ~= nil and string.sub(path, 1, #home) == home then
    return "~" .. string.sub(path, #home + 1)
  end
  return path
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
    glyph = "photo",
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

-- Focused output first, then the service's first known output, then live.
local function target_connector()
  local ok, out = pcall(function()
    return noctalia.focusedOutputName()
  end)
  if ok and type(out) == "string" and out ~= "" then
    return out
  end
  local okb, board = pcall(function()
    if noctalia.state ~= nil and noctalia.state.get ~= nil then
      return noctalia.state.get("wallpaper-cursor.board")
    end
    return nil
  end)
  if okb and type(board) == "table" and type(board.outputs) == "table" then
    for _, o in ipairs(board.outputs) do
      if type(o) == "table" and type(o.name) == "string" and o.name ~= "" then
        return o.name
      end
    end
  end
  local oko, outs = pcall(function()
    return noctalia.outputs()
  end)
  if oko and type(outs) == "table" then
    for _, o in ipairs(outs) do
      if type(o) == "table" and type(o.name) == "string" and o.name ~= "" then
        return o.name
      end
    end
  end
  return nil
end

local function toml_escape(s)
  s = string.gsub(s, "\\", "\\\\")
  s = string.gsub(s, '"', '\\"')
  return s
end

local function bare_key_ok(s)
  return string.match(s, "^[A-Za-z0-9_%-]+$") ~= nil
end

local function format_key(s)
  if bare_key_ok(s) then
    return s
  end
  return '"' .. toml_escape(s) .. '"'
end

-- Parse one "key = value" row. Returns indent + key, or nil for headers,
-- comments, blanks, and malformed rows. Quoted keys honour \" escapes.
local function parse_row(line)
  local indent = string.match(line, "^(%s*)") or ""
  local rest = string.sub(line, #indent + 1)
  if rest == "" or string.sub(rest, 1, 1) == "#" then
    return nil
  end
  if string.sub(rest, 1, 1) == '"' then
    local i = 2
    local buf = {}
    while i <= #rest do
      local ch = string.sub(rest, i, i)
      if ch == "\\" and i < #rest then
        table.insert(buf, string.sub(rest, i + 1, i + 1))
        i = i + 2
      elseif ch == '"' then
        if string.match(string.sub(rest, i + 1), "^%s*=%s*.+$") then
          return indent, table.concat(buf)
        end
        return nil
      else
        table.insert(buf, ch)
        i = i + 1
      end
    end
    return nil
  end
  local lhs = string.match(rest, "^(.-)%s*=%s*.+$")
  if lhs == nil or lhs == "" then
    return nil
  end
  return indent, lhs
end

local function trim(s)
  return string.match(s, "^%s*(.-)%s*$") or ""
end

-- Candidate settings files, first readable wins. Mirrors Noctalia's
-- NOCTALIA_STATE_HOME / XDG_STATE_HOME override order, then the default.
local function settings_candidates()
  local cands = {}
  local function getenv(n)
    local ok, v = pcall(function()
      if noctalia.getenv ~= nil then
        return noctalia.getenv(n)
      end
      return nil
    end)
    if ok and type(v) == "string" and v ~= "" then
      return v
    end
    return nil
  end
  local override = getenv("NOCTALIA_STATE_HOME")
  if override ~= nil then
    table.insert(cands, override .. "/settings.toml")
    table.insert(cands, override .. "/noctalia/settings.toml")
  end
  local xdg = getenv("XDG_STATE_HOME")
  if xdg ~= nil then
    table.insert(cands, xdg .. "/noctalia/settings.toml")
  end
  local home = getenv("HOME")
  if home == nil then
    local ok, h = pcall(function()
      return os.getenv("HOME")
    end)
    if ok and type(h) == "string" and h ~= "" then
      home = h
    end
  end
  if home ~= nil then
    table.insert(cands, home .. "/.local/state/noctalia/settings.toml")
  end
  return cands
end

local function find_settings()
  for _, p in ipairs(settings_candidates()) do
    local ok, content = pcall(function()
      return noctalia.readFile(p)
    end)
    if ok and type(content) == "string" then
      return p, content
    end
  end
  return nil, nil
end

-- Write one folder -> cursor row into the settings file's folder_map table.
-- Surgical: every other byte stays identical. Returns true, or false + err.
local function save_mapping(folder, cursor)
  if type(folder) ~= "string" or folder == "" then
    return false, "no folder selected"
  end
  if type(cursor) ~= "string" or cursor == "" then
    return false, "no cursor selected"
  end
  local path, content = find_settings()
  if path == nil or content == nil then
    return false, "settings file not found"
  end
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  local new_line = format_key(folder) .. ' = "' .. toml_escape(cursor) .. '"'
  local header_at = nil
  for i, line in ipairs(lines) do
    if trim(line) == MAP_HEADER then
      header_at = i
      break
    end
  end
  if header_at ~= nil then
    local stop_at = #lines + 1
    for i = header_at + 1, #lines do
      if string.match(lines[i], "^%s*%[") then
        stop_at = i
        break
      end
    end
    local indent = "    "
    local placed = false
    for i = header_at + 1, stop_at - 1 do
      local ind, key = parse_row(lines[i])
      if ind ~= nil then
        if ind ~= "" then
          indent = ind
        end
        if key == folder then
          lines[i] = ind .. format_key(folder) .. ' = "' .. toml_escape(cursor) .. '"'
          placed = true
          break
        end
      end
    end
    if not placed then
      table.insert(lines, stop_at, indent .. new_line)
    end
  else
    if #lines > 0 and lines[#lines] ~= "" then
      table.insert(lines, "")
    end
    table.insert(lines, MAP_HEADER)
    table.insert(lines, "    " .. new_line)
  end
  local new_content = table.concat(lines, "\n")
  local okb, wrote_b = pcall(noctalia.writeFile, path .. BACKUP_SUFFIX, content)
  if not okb or not wrote_b then
    return false, "backup failed"
  end
  local okw, wrote_w = pcall(noctalia.writeFile, path, new_content)
  if not okw or not wrote_w then
    return false, "write failed"
  end
  noctalia.runAsync({ "noctalia", "msg", "config-reload" })
  noctalia.notify(noctalia.tr("panel.saved"), folder .. " → " .. cursor)
  noctalia.log("wallpaper-cursor: mapping saved: " .. folder .. " -> " .. cursor)
  return true
end

local function render()
  local unknown = noctalia.tr("panel.unknown")
  local wall_root = get_root("wallpaper_root", "~/Pictures/Wallpapers")
  local icon_root = get_root("icon_root", "~/.local/share/icons")
  local open_tip = noctalia.tr("panel.open_folder")

  local folders = list_subdirs(wall_root)
  local cursors = list_cursors(icon_root)
  pick_folder_idx = clamp_idx(pick_folder_idx, math.max(#folders, 1))
  pick_cursor_idx = clamp_idx(pick_cursor_idx, math.max(#cursors, 1))

  local pick_folder = folders[pick_folder_idx]
  local image_dir = nil
  if type(pick_folder) == "string" and type(wall_root) == "string" and wall_root ~= "" then
    image_dir = wall_root .. "/" .. pick_folder
  end
  local images = list_images(image_dir)
  image_idx = clamp_idx(image_idx, math.max(#images, 1))

  last_connector = target_connector()
  last_apply = nil
  if image_dir ~= nil and images[image_idx] ~= nil then
    last_apply = { dir = image_dir, image = images[image_idx] }
  end
  last_pick = nil
  local pick_cursor = cursors[pick_cursor_idx]
  if type(pick_folder) == "string" and type(pick_cursor) == "string" then
    last_pick = { folder = pick_folder, cursor = pick_cursor }
  end
  local pf = pick_folder or unknown
  local pc = pick_cursor or unknown

  local shortcut_cells = {}
  local wb = folder_button(wall_root, open_tip)
  if wb ~= nil then
    table.insert(shortcut_cells, wb)
    table.insert(shortcut_cells, ui.label({ text = short_root(wall_root) }))
  end
  local ib = folder_button(icon_root, open_tip)
  if ib ~= nil then
    table.insert(shortcut_cells, ib)
    table.insert(shortcut_cells, ui.label({ text = short_root(icon_root) }))
  end

  local body = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "photo", size = 18 }),
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold" }),
    }),
    ui.separator({ color = "outline", thickness = 1, spacing = 4 }),
    ui.label({ text = noctalia.tr("panel.pick_folder"), fontWeight = "bold" }),
  }
  if #folders > 0 then
    -- selectedIndex is 0-based on the host; our indices are lua 1-based.
    table.insert(body, ui.select({ options = folders, selectedIndex = pick_folder_idx - 1, onChange = "onPickFolder" }))
  else
    table.insert(body, ui.label({ text = unknown }))
  end
  table.insert(body, ui.label({ text = noctalia.tr("panel.pick_image"), fontWeight = "bold" }))
  if #images > 0 then
    table.insert(body, ui.select({ options = images, selectedIndex = image_idx - 1, onChange = "onPickImage" }))
  else
    table.insert(body, ui.label({ text = noctalia.tr("panel.no_images") }))
  end
  table.insert(body, ui.button({
    text = noctalia.tr("panel.apply"),
    variant = "default",
    enabled = last_apply ~= nil and last_connector ~= nil,
    onClick = "onApplyWallpaper",
  }))
  table.insert(body, ui.separator({ color = "outline", thickness = 1, spacing = 4 }))
  table.insert(body, ui.label({ text = noctalia.tr("panel.pick_cursor"), fontWeight = "bold" }))
  if #cursors > 0 then
    table.insert(body, ui.select({ options = cursors, selectedIndex = pick_cursor_idx - 1, onChange = "onPickCursor" }))
  else
    table.insert(body, ui.label({ text = unknown }))
  end
  table.insert(body, ui.label({ text = pf .. " => " .. pc }))
  table.insert(body, ui.button({
    text = noctalia.tr("panel.save"),
    variant = "primary",
    enabled = last_pick ~= nil,
    onClick = "onSaveMapping",
  }))
  if #shortcut_cells > 0 then
    table.insert(body, ui.separator({ color = "outline", thickness = 1, spacing = 4 }))
    table.insert(body, ui.row({ gap = 8, align = "center" }, shortcut_cells))
  end

  panel.render(ui.column({ gap = 12 }, body))
end

function onOpen(_context)
  is_open = true
  render()
end

function onClose()
  is_open = false
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

function onPickImage(value)
  local i = tonumber(value)
  if i ~= nil then
    image_idx = i + 1
  end
end

function onApplyWallpaper()
  if type(last_apply) ~= "table" or last_connector == nil then
    return
  end
  local full = last_apply.dir .. "/" .. last_apply.image
  local ok, err = pcall(function()
    return noctalia.setWallpaper(last_connector, full)
  end)
  if not ok then
    noctalia.log("wallpaper-cursor: setWallpaper failed: " .. tostring(err))
  else
    noctalia.log("wallpaper-cursor: wallpaper set [" .. tostring(last_connector) .. "] " .. full)
  end
end

function onSaveMapping()
  if type(last_pick) ~= "table" then
    return
  end
  local ok, err = save_mapping(last_pick.folder, last_pick.cursor)
  if not ok then
    noctalia.notify(noctalia.tr("panel.save_failed"), tostring(err))
    noctalia.log("wallpaper-cursor: mapping save failed: " .. tostring(err))
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
