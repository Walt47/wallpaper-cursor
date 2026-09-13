-- watcher service: poll wallpaper per output, apply mapped cursor.
-- Parity with hooks/wallpaper-cursor.sh. Settings:
--   default_cursor (string), folder_map (string_map: folder substring -> cursor),
--   cursor_size (int), enable_notifications (bool), poll_interval_ms (int),
--   enforce_dark_mode (bool).
-- Multi-output policy: last-change-wins, single write per poll. Outputs are
-- sorted by connector name for determinism; the most recently changed output
-- wins, falling back to the last sorted output when nothing changed (steady
-- state) or to the remembered winner across polls.
local MANGO_CONF = (noctalia.getenv("HOME") or os.getenv("HOME") or "") .. "/.config/mango/config.conf"

local DEFAULT_POLL_MS = 2000
local DEFAULT_SIZE = 24

local prev_paths = {}
local last_winner_name = nil
local last_board_sig = nil
local applied_interval = nil

noctalia.setUpdateInterval(DEFAULT_POLL_MS)
applied_interval = DEFAULT_POLL_MS

local function resolve_cursor(path, folder_map, default_cursor)
  if path == nil then return default_cursor end
  for folder, cursor in pairs(folder_map) do
    if string.find(path, folder, 1, true) then
      return cursor
    end
  end
  return default_cursor
end

local function current_cursor()
  local f = noctalia.readFile(MANGO_CONF)
  if not f then return nil end
  local theme = string.match(f, "cursor_theme=([^\n]+)")
  return theme
end

local function write_cursor(cursor)
  local f = noctalia.readFile(MANGO_CONF)
  if f == nil then
    return false, "mango conf missing: " .. MANGO_CONF
  end
  local lines = {}
  local found = false
  for raw in (f .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw
    if string.match(line, "^cursor_theme=") then
      line = "cursor_theme=" .. cursor
      found = true
    end
    table.insert(lines, line)
  end
  if not found then
    table.insert(lines, "cursor_theme=" .. cursor)
  end
  local ok, err = noctalia.writeFile(MANGO_CONF, table.concat(lines, "\n"))
  if not ok then
    return false, err or "write failed"
  end
  return true
end

local function live_apply(cursor, size)
  -- Primary: setoption changes appearance without reload (no flicker).
  -- Fallback: script-triggered hot-reload (still no keypress).
  if noctalia.commandExists("mmsg") then
    noctalia.runAsync({ "mmsg", "-s", "-d", "setoption,cursor_theme," .. cursor }, function(res)
      if res == nil or res.exitCode ~= 0 then
        noctalia.runAsync({ "mmsg", "-s", "-d", "reload_config" })
      end
    end)
  end
  -- GTK apps follow live (Noctalia's gtk template only syncs gtk-theme,
  -- not cursor). Best-effort: silent when gsettings is unavailable.
  if noctalia.commandExists("gsettings") then
    noctalia.runAsync({ "gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", cursor })
    noctalia.runAsync({ "gsettings", "set", "org.gnome.desktop.interface", "cursor-size", tostring(size) })
  end
end

-- Keep the app theme on dark across wallpaper switches (best-effort, silent
-- when already dark or when the noctalia CLI is unavailable).
local function enforce_dark(enabled)
  if not enabled then
    return
  end
  if not noctalia.commandExists("noctalia") then
    return
  end
  noctalia.runAsync({ "noctalia", "msg", "theme-mode-get" }, function(res)
    local mode = nil
    if res ~= nil and type(res.stdout) == "string" then
      mode = string.match(res.stdout, "^%s*(%S+)")
    end
    if mode ~= nil and mode ~= "dark" then
      noctalia.runAsync({ "noctalia", "msg", "theme-mode-set", "dark" })
      noctalia.log("wallpaper-cursor: theme mode was '" .. mode .. "', set back to dark.")
    end
  end)
end

local function apply_cursor(cursor, wallpaper_path, output_name, size, notify_enabled, dark_enabled)
  if cursor == nil then return end
  local previous = current_cursor()
  if previous == cursor then return end
  local ok, err = write_cursor(cursor)
  if not ok then
    noctalia.log("wallpaper-cursor: cannot write " .. MANGO_CONF .. ": " .. tostring(err))
    noctalia.notifyError("wallpaper-cursor: cannot write Mango config", tostring(err))
    return
  end
  live_apply(cursor, size)
  enforce_dark(dark_enabled)
  noctalia.log(
    "wallpaper-cursor: ["
      .. tostring(output_name or "")
      .. "] "
      .. tostring(wallpaper_path)
      .. " -> "
      .. tostring(cursor)
      .. " (was: "
      .. tostring(previous or "unset")
      .. ", applied live)."
  )
  if notify_enabled then
    noctalia.notify("Cursor: " .. tostring(cursor), tostring(wallpaper_path or ""))
  end
end

local function config_number(key, fallback, min_v, max_v)
  local v = noctalia.getConfig(key)
  if type(v) ~= "number" then return fallback end
  if v < min_v or v > max_v then return fallback end
  return math.floor(v)
end

function update()
  local folder_map = noctalia.getConfig("folder_map") or {}
  local default_cursor = noctalia.getConfig("default_cursor") or "Adwaita"
  local size = config_number("cursor_size", DEFAULT_SIZE, 8, 96)
  local notify_enabled = noctalia.getConfig("enable_notifications")
  if notify_enabled == nil then notify_enabled = true end
  local dark_enabled = noctalia.getConfig("enforce_dark_mode")
  if dark_enabled == nil then dark_enabled = true end
  local poll_ms = config_number("poll_interval_ms", DEFAULT_POLL_MS, 500, 10000)
  if poll_ms ~= applied_interval then
    noctalia.setUpdateInterval(poll_ms)
    applied_interval = poll_ms
  end

  local outs = noctalia.outputs() or {}
  if #outs == 0 then return end
  table.sort(outs, function(a, b)
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  -- Snapshot current wallpapers in sorted order.
  local current_paths = {}
  for _, out in ipairs(outs) do
    local name = out.name
    if name ~= nil then
      local ok, path = pcall(noctalia.wallpaperPath, name)
      if ok then
        current_paths[name] = path
      else
        current_paths[name] = nil
      end
    end
  end

  -- Find outputs whose wallpaper changed since the last poll.
  local changed = {}
  for _, out in ipairs(outs) do
    local name = out.name
    if name ~= nil and current_paths[name] ~= prev_paths[name] then
      table.insert(changed, out)
    end
  end

  local winner = nil
  if #changed > 0 then
    winner = changed[#changed] -- last changed in sorted order
    last_winner_name = winner.name
  elseif last_winner_name ~= nil and current_paths[last_winner_name] ~= nil then
    for _, out in ipairs(outs) do
      if out.name == last_winner_name then
        winner = out
        break
      end
    end
  end
  if winner == nil then
    winner = outs[#outs] -- deterministic fallback: last sorted output
    last_winner_name = winner.name
  end

  local path = current_paths[winner.name]
  local cursor = resolve_cursor(path, folder_map, default_cursor)
  apply_cursor(cursor, path, winner.name, size, notify_enabled, dark_enabled)
  noctalia.state.set("wallpaper-cursor.cursor", cursor)

  -- Board snapshot for future UI entries (widget/panel). Outputs reuse the
  -- already-sorted outs order. Publish only on change (cursor or any
  -- wallpaper path) so watchers are not spammed every poll.
  local board_rows = {}
  local sig_parts = {}
  for _, out in ipairs(outs) do
    local bname = out.name
    if bname ~= nil then
      local wpath = current_paths[bname] or ""
      table.insert(board_rows, { name = bname, wallpaper = wpath })
      table.insert(sig_parts, bname .. "=" .. wpath .. ";")
    end
  end
  local board_sig = tostring(cursor or "") .. "|" .. table.concat(sig_parts, "")
  if board_sig ~= last_board_sig then
    last_board_sig = board_sig
    noctalia.state.set("wallpaper-cursor.board", { cursor = cursor, outputs = board_rows })
  end

  prev_paths = current_paths
end

function onConfigChanged()
  update()
end

function onOutputsChanged()
  update()
end

function onEnable()
  update()
end
