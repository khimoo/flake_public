-- rustowl hover_text display via mouse hover
-- Independently requests rustowl/cursor and shows hover_text in a floating window.
-- Does not depend on rustowl plugin internals; only uses the LSP protocol.

local M = {}

local float_win = nil
local float_buf = nil
local cached_decos = nil -- { cursor_key = "line:col", items = { {range, hover_text}, ... } }

local function close_float()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_close(float_win, true)
  end
  float_win = nil
  float_buf = nil
end

local function show_float(text)
  close_float()
  local lines = vim.split(text, '\n', { trimempty = true })
  if #lines == 0 then return end

  float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  float_win = vim.api.nvim_open_win(float_buf, false, {
    relative = 'mouse',
    row = 1,
    col = 0,
    width = width,
    height = #lines,
    style = 'minimal',
    border = 'rounded',
  })
end

--- Find a decoration whose range contains the given 0-indexed position
local function find_at(decos, line0, col0)
  for _, deco in ipairs(decos) do
    local s = deco.range.start
    local e = deco.range['end']
    if line0 >= s.line and line0 <= e.line then
      local after_start = line0 > s.line or col0 >= s.character
      local before_end = line0 < e.line or col0 < e.character
      if after_start and before_end then
        return deco
      end
    end
  end
  return nil
end

local function fetch_decos(bufnr, cursor_line, cursor_col)
  local key = cursor_line .. ':' .. cursor_col
  if cached_decos and cached_decos.cursor_key == key then
    return
  end

  local clients = vim.lsp.get_clients({ name = 'rustowl', bufnr = bufnr })
  if #clients == 0 then return end

  local params = {
    position = { line = cursor_line - 1, character = cursor_col },
    document = vim.lsp.util.make_text_document_params(bufnr),
  }

  clients[1]:request('rustowl/cursor', params, function(_, result)
    if not result or not result.decorations then return end
    local items = {}
    for _, deco in ipairs(result.decorations) do
      if not deco.overlapped and deco.hover_text and deco.hover_text ~= '' then
        table.insert(items, { range = deco.range, hover_text = deco.hover_text })
      end
    end
    cached_decos = { cursor_key = key, items = items }
  end, bufnr)
end

local function on_mouse_move()
  if not require('rustowl').is_enabled() then
    close_float()
    return
  end

  local pos = vim.fn.getmousepos()
  if pos.line == 0 then
    close_float()
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  fetch_decos(bufnr, cursor[1], cursor[2])

  if not cached_decos or #cached_decos.items == 0 then
    close_float()
    return
  end

  -- getmousepos returns 1-indexed line/col; LSP ranges are 0-indexed
  local deco = find_at(cached_decos.items, pos.line - 1, pos.column - 1)
  if deco then
    show_float(deco.hover_text)
  else
    close_float()
  end
end

function M.setup()
  vim.o.mousemoveevent = true

  vim.keymap.set('', '<MouseMove>', on_mouse_move)

  local augroup = vim.api.nvim_create_augroup('RustOwlHover', { clear = true })

  -- Clear cache when cursor moves (new highlights will be generated)
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = augroup,
    callback = function()
      cached_decos = nil
      close_float()
    end,
  })
end

return M
