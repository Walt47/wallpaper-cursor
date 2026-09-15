--!nonstrict
-- Bar widget for wallpaper-cursor: shows the active cursor theme name.
-- Data source is the watcher service via shared state:
--   "wallpaper-cursor.cursor" (string) and "wallpaper-cursor.board"
--   ({ cursor=..., outputs={{name,wallpaper}...} }).
-- Imperative barWidget API only (no barWidget.render).

noctalia.setUpdateInterval(2000)

local PANEL_ID = "walt/wallpaper-cursor:board"
local CURSOR_KEY = "wallpaper-cursor.cursor"
local BOARD_KEY = "wallpaper-cursor.board"
local GLYPH = "pointer-filled"
local PLACEHOLDER = "…"

local function current_cursor()
  local ok, v = pcall(function() return noctalia.state.get(CURSOR_KEY) end)
  if not ok then
    return nil
  end
  if type(v) == "string" then
    return v
  end
  return nil
end

local function board_wallpaper()
  local ok, board = pcall(function() return noctalia.state.get(BOARD_KEY) end)
  if not ok then
    return ""
  end
  if type(board) ~= "table" then
    return ""
  end
  if type(board.wallpaper) == "string" then
    return board.wallpaper
  end
  local outputs = board.outputs
  if type(outputs) ~= "table" then
    return ""
  end
  local current = nil
  if barWidget ~= nil and type(barWidget.outputName) == "function" then
    local ok2, name = pcall(function() return barWidget.outputName() end)
    if ok2 and type(name) == "string" then
      current = name
    end
  end
  if current ~= nil then
    for _, out in ipairs(outputs) do
      if type(out) == "table" and out.name == current and type(out.wallpaper) == "string" then
        return out.wallpaper
      end
    end
  end
  for _, out in ipairs(outputs) do
    if type(out) == "table" and type(out.wallpaper) == "string" then
      return out.wallpaper
    end
  end
  return ""
end

local function render()
  local cursor = current_cursor()
  local wallpaper = board_wallpaper()
  local show_label = noctalia.getConfig("show_label")
  if show_label == nil then
    show_label = true
  end
  barWidget.setGlyph(GLYPH)
  if show_label == false then
    barWidget.setText("")
  else
    if cursor ~= nil then
      barWidget.setText(cursor)
    else
      barWidget.setText(PLACEHOLDER)
    end
  end
  local tooltip_cursor = cursor
  if tooltip_cursor == nil then
    tooltip_cursor = ""
  end
  local ok, tip = pcall(function()
    return noctalia.tr("widget.tooltip", { cursor = tooltip_cursor, wallpaper = wallpaper })
  end)
  if ok and type(tip) == "string" then
    barWidget.setTooltip(tip)
  else
    pcall(function() barWidget.setTooltip("") end)
  end
end

noctalia.state.watch(CURSOR_KEY, function(_value)
  render()
end)

noctalia.state.watch(BOARD_KEY, function(_value)
  render()
end)

render()

function update()
  render()
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

function onRightClick()
  noctalia.openSettings()
end

function onIpc(event, _payload)
  if event == "toggle" then
    noctalia.togglePanel(PANEL_ID)
  end
end
