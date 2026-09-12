--!nonstrict
-- Noctalia panel entry for wallpaper-cursor.
-- Declarative ui.* tree rendered via panel.render(). Watches
-- wallpaper-cursor.board and re-renders only while open. Falls back to live
-- noctalia.outputs() + noctalia.wallpaperPath() when board state is nil.
-- Plain Luau subset parseable by stock lua 5.4. plugin_api 25 only.

local is_open = false

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

  local output_rows = {}
  table.insert(output_rows, ui.label({ text = noctalia.tr("panel.outputs") }))
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
    table.insert(output_rows, ui.row({ gap = 8 }, {
      ui.label({ text = disp_name }),
      ui.label({ text = disp_wall }),
    }))
  end

  local mapping_children = {}
  table.insert(mapping_children, ui.label({ text = noctalia.tr("panel.mapping") }))
  for _, folder in ipairs(keys) do
    local c = folder_map[folder]
    if type(c) ~= "string" then
      c = tostring(c)
    end
    table.insert(mapping_children, ui.row({ gap = 8 }, {
      ui.label({ text = folder .. " → " .. c }),
    }))
  end
  table.insert(mapping_children, ui.row({ gap = 8 }, {
    ui.label({ text = noctalia.tr("panel.default_row", { cursor = default_for_row }) }),
  }))

  panel.render(ui.column({ gap = 12 }, {
    ui.row({ gap = 8 }, {
      ui.glyph({ name = "cursor-text" }),
      ui.label({ text = noctalia.tr("panel.title") }),
    }),
    ui.row({ gap = 8 }, {
      ui.label({ text = noctalia.tr("panel.active_cursor") }),
      ui.label({ text = cursor_text }),
    }),
    ui.column({ gap = 8 }, output_rows),
    ui.column({ gap = 8 }, mapping_children),
    ui.row({ gap = 8 }, {
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

pcall(function()
  if noctalia.state ~= nil and noctalia.state.watch ~= nil then
    noctalia.state.watch("wallpaper-cursor.board", function(_value)
      if is_open then
        render()
      end
    end)
  end
end)
