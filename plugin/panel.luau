--!nonstrict
-- Minimal board: assign a wallpaper folder a cursor theme.
-- One job only: Save cursor mapping. Save rewrites just the
-- folder_map lines of the settings file (with backup) and reloads config so
-- the service adopts the new rule. Plain Luau subset parseable by stock
-- lua 5.4. plugin_api 25 only.

local is_open = false

-- Pick state (lua 1-based positions into the current option lists).
local pick_folder_idx = 1
local pick_cursor_idx = 1
-- Last render's mapping, consumed by the save handler.
local last_pick = nil

local MAP_HEADER = '[plugin_settings."walt/wallpaper-cursor".folder_map]'
local BACKUP_SUFFIX = ".bak-wallpaper-cursor"
-- Upper bound for folder/cursor names: rejects oversized input before it
-- reaches the settings file or an external command.
local MAX_NAME_LEN = 128

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

local function is_dir(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local ok, info = pcall(function()
    return noctalia.fileInfo(path)
  end)
  return ok and type(info) == "table" and info.isDir == true
end

local function open_path(path)
  if type(path) ~= "string" or path == "" then
    return
  end
  if not can_open() then
    return
  end
  -- Only open directories: a misconfigured root pointing at a file (or a
  -- path that changed on disk) must not be handed to xdg-open.
  if not is_dir(path) then
    return
  end
  -- Array form: no shell, so spaces/quotes in the path cannot inject flags.
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

-- Names come from on-disk directory entries: reject control characters
-- (CR/LF/TAB split TOML rows or log lines) and bound the length before
-- anything reaches the settings file, a notification, or a command.
local function valid_name(s)
  if type(s) ~= "string" or s == "" or #s > MAX_NAME_LEN then
    return false
  end
  return string.find(s, "[%c]") == nil
end

-- Safe display: control characters become "?" so a hostile directory name
-- cannot break the panel layout; overlong names are truncated.
local function display_name(s, fallback)
  if type(s) ~= "string" or s == "" then
    return fallback
  end
  local clean = string.gsub(s, "[%c]", "?")
  if #clean > MAX_NAME_LEN then
    clean = string.sub(clean, 1, MAX_NAME_LEN) .. "…"
  end
  return clean
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
  if not valid_name(folder) then
    return false, "invalid folder name"
  end
  if not valid_name(cursor) then
    return false, "invalid cursor name"
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

-- Fresh snapshot of on-disk options + current picks. The save handler uses
-- this instead of the last render's cache so a board watcher rerender
-- between select and click cannot make it save the wrong mapping.
local function snapshot()
  local wall_root = get_root("wallpaper_root", "~/Pictures/Wallpapers")
  local icon_root = get_root("icon_root", "~/.local/share/icons")
  local folders = list_subdirs(wall_root)
  local cursors = list_cursors(icon_root)
  local f_idx = clamp_idx(pick_folder_idx, math.max(#folders, 1))
  local c_idx = clamp_idx(pick_cursor_idx, math.max(#cursors, 1))
  return {
    wall_root = wall_root,
    icon_root = icon_root,
    folders = folders,
    cursors = cursors,
    folder_idx = f_idx,
    cursor_idx = c_idx,
    pick_folder = folders[f_idx],
    pick_cursor = cursors[c_idx],
  }
end

local function render()
  local unknown = noctalia.tr("panel.unknown")
  local open_tip = noctalia.tr("panel.open_folder")
  local snap = snapshot()

  local wall_root = snap.wall_root
  local icon_root = snap.icon_root
  local folders = snap.folders
  local cursors = snap.cursors
  -- Sync clamped positions back so stale indices cannot linger after
  -- folders/themes appear or disappear while the panel is open.
  pick_folder_idx = snap.folder_idx
  pick_cursor_idx = snap.cursor_idx

  local pick_folder = snap.pick_folder
  local pick_cursor = snap.pick_cursor

  last_pick = nil
  if valid_name(pick_folder) and valid_name(pick_cursor) then
    last_pick = { folder = pick_folder, cursor = pick_cursor }
  end
  local pf = display_name(pick_folder, unknown)
  local pc = display_name(pick_cursor, unknown)

  -- Footer: one row per root (two narrow rows fit; one wide row overflows).
  local footer_rows = {}
  local wb = folder_button(wall_root, open_tip)
  if wb ~= nil then
    table.insert(footer_rows, ui.row({ gap = 8, align = "center" }, {
      wb,
      ui.label({ text = short_root(wall_root), fontSize = 12 }),
    }))
  end
  local ib = folder_button(icon_root, open_tip)
  if ib ~= nil then
    table.insert(footer_rows, ui.row({ gap = 8, align = "center" }, {
      ib,
      ui.label({ text = short_root(icon_root), fontSize = 12 }),
    }))
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
  table.insert(body, ui.separator({ color = "outline", thickness = 1, spacing = 4 }))
  table.insert(body, ui.label({ text = noctalia.tr("panel.pick_cursor"), fontWeight = "bold" }))
  if #cursors > 0 then
    table.insert(body, ui.select({ options = cursors, selectedIndex = pick_cursor_idx - 1, onChange = "onPickCursor" }))
  else
    table.insert(body, ui.label({ text = unknown }))
  end
  table.insert(body, ui.label({ text = pf .. " => " .. pc, fontSize = 13 }))
  table.insert(body, ui.button({
    text = noctalia.tr("panel.save"),
    variant = "primary",
    enabled = last_pick ~= nil,
    onClick = "onSaveMapping",
  }))
  if #footer_rows > 0 then
    table.insert(body, ui.separator({ color = "outline", thickness = 1, spacing = 4 }))
    table.insert(body, ui.column({ gap = 6 }, footer_rows))
  end

  panel.render(ui.column({ gap = 10 }, body))
end

function onOpen(_context)
  is_open = true
  render()
end

function onClose()
  is_open = false
end

-- ui.select reports the chosen position as a 0-based index string.
-- Re-render immediately so preview and button state follow
-- the new pick without closing/reopening the panel.
function onPickFolder(value)
  local i = tonumber(value)
  if i ~= nil then
    pick_folder_idx = i + 1
    if is_open then
      render()
    end
  end
end

function onPickCursor(value)
  local i = tonumber(value)
  if i ~= nil then
    pick_cursor_idx = i + 1
    if is_open then
      render()
    end
  end
end

function onSaveMapping()
  -- Recompute from disk + current indices for the same staleness reason.
  local snap = snapshot()
  pick_folder_idx = snap.folder_idx
  pick_cursor_idx = snap.cursor_idx
  last_pick = nil
  if valid_name(snap.pick_folder) and valid_name(snap.pick_cursor) then
    last_pick = { folder = snap.pick_folder, cursor = snap.pick_cursor }
  end
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
