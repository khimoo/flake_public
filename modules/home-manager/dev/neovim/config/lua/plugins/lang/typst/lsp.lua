-- tinymist の override。features/lsp.lua の opts.servers に deep-merge される。
-- optional なので、lsp 機能を外すとこの spec も外れる。
local main_file = require("plugins.lang.typst.main_file")
local output_path = require("plugins.lang.typst.output_path")
local preview_browser = require("config.preview_browser")

local PREVIEW_HOST = "127.0.0.1:23635"
local PREVIEW_URL = "http://" .. PREVIEW_HOST
local PREVIEW_TASK_ID = "default_preview"
local SCROLL_DEBOUNCE_MS = 120

local pin_group = vim.api.nvim_create_augroup("TypstPinMain", { clear = true })
local scroll_group = vim.api.nvim_create_augroup("TypstPreviewScroll", { clear = true })

-- pin はサーバー全体の状態なので、直前に pin したものを覚えて無駄な往復を省く。
-- サーバーが再起動すると pin は失われるため、client ごとに記録する。
---@type table<integer, string>
local pinned = {}

local follow_cursor = true

local function pin_main(client, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end

  local main = main_file.resolve(path)
  if main == pinned[client.id] then
    return
  end
  pinned[client.id] = main

  client:exec_cmd({
    title = "pin main file",
    command = "tinymist.pinMain",
    arguments = { main },
  }, { bufnr = bufnr })
end

-- tinymist の panelScrollTo は UTF-16 の文字位置を取り、行頭（0）や見出し・箇条書きの
-- 先頭記号上では AST の span を拾えず空振りしやすい。UTF-8 バイト位置を UTF-16 に変換し、
-- 先頭境界にいるときは最初の本文文字の内側へ寄せてから送る。
local function preview_character(bufnr, row, byte_col, encoding)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  if line == "" then
    return 0
  end

  local _, prefix_end = line:find("^[%s=%-%+]+")
  local target_byte = byte_col
  if prefix_end and target_byte <= prefix_end then
    -- 先頭記号直後の 1 文字目の「次の位置」を狙うと本文テキストノードの内側に入る。
    local next_byte = vim.fn.byteidx(line, vim.fn.charidx(line, math.min(prefix_end, #line)) + 1)
    if next_byte > 0 and next_byte <= #line then
      target_byte = next_byte
    elseif prefix_end < #line then
      target_byte = prefix_end
    end
  elseif target_byte == 0 then
    local next_byte = vim.fn.byteidx(line, 1)
    if next_byte > 0 and next_byte <= #line then
      target_byte = next_byte
    end
  end

  local enc = encoding or "utf-16"
  return vim.str_utfindex(line, enc, math.min(target_byte, #line))
end

local function sync_preview_cursor(client, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local character = preview_character(bufnr, row, cursor[2], client.offset_encoding)

  client:exec_cmd({
    title = "scroll preview",
    command = "tinymist.scrollPreview",
    arguments = {
      PREVIEW_TASK_ID,
      {
        event = "panelScrollTo",
        filepath = path,
        line = row - 1,
        character = character,
      },
    },
  }, { bufnr = bufnr }, function() end)
end

local function register_preview_commands(client, bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "TypstPreview", function()
    preview_browser.open(PREVIEW_URL)
  end, { desc = "Open Tinymist background preview in app window" })

  vim.api.nvim_buf_create_user_command(bufnr, "TypstPreviewFollowCursorToggle", function()
    follow_cursor = not follow_cursor
    vim.notify("Typst preview follow cursor: " .. (follow_cursor and "ON" or "OFF"))
  end, { desc = "Toggle Tinymist preview cursor follow" })

  vim.api.nvim_buf_create_user_command(bufnr, "TypstPreviewSyncCursor", function()
    sync_preview_cursor(client, bufnr)
  end, { desc = "Sync Tinymist preview to cursor" })
end

return {
  "neovim/nvim-lspconfig",
  optional = true,
  opts = {
    servers = {
      tinymist = {
        -- tinymist の背景プレビューは initialize 時点（init_options）にネスト構造で
        -- 渡さないと起動しない。didChangeConfiguration でも維持されるよう settings にも揃える。
        init_options = {
          preview = {
            background = {
              enabled = true,
              args = {
                "--data-plane-host=" .. PREVIEW_HOST,
                "--invert-colors=auto",
                "--partial-rendering=true",
              },
            },
          },
        },
        settings = {
          -- ライブプレビュー（背景サーバ）と打鍵ごとに PDF 出力が二重に走ると重くなるため、
          -- PDF の書き出しは保存時に限定する。
          exportPdf = "onSave",
          -- 固定ポートで背景プレビューを待ち受け、枠なしブラウザ 1 窓をファイル切替や
          -- Neovim の再起動をまたいで使い回す。--open は渡さず :TypstPreview から開く。
          preview = {
            background = {
              enabled = true,
              args = {
                "--data-plane-host=" .. PREVIEW_HOST,
                "--invert-colors=auto",
                "--partial-rendering=true",
              },
            },
          },
        },
        before_init = function(_, config)
          local root = config.root_dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
          config.settings.outputPath = output_path.resolve(root)
        end,
        on_attach = function(client, bufnr)
          pin_main(client, bufnr)
          register_preview_commands(client, bufnr)

          -- 別の文書に移ったら pin し直す。
          vim.api.nvim_clear_autocmds({ group = pin_group, buffer = bufnr })
          vim.api.nvim_create_autocmd("BufEnter", {
            group = pin_group,
            buffer = bufnr,
            callback = function()
              pin_main(client, bufnr)
            end,
          })

          -- カーソル移動が止まったときだけ背景プレビューへスクロール位置を送る（連打防止）。
          local last_sent_line = nil
          local timer = vim.uv.new_timer()
          vim.api.nvim_clear_autocmds({ group = scroll_group, buffer = bufnr })
          vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
            group = scroll_group,
            buffer = bufnr,
            callback = function()
              if not follow_cursor or not timer or timer:is_closing() then
                return
              end
              timer:stop()
              timer:start(
                SCROLL_DEBOUNCE_MS,
                0,
                vim.schedule_wrap(function()
                  if not follow_cursor or client:is_stopped() then
                    return
                  end
                  if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
                    return
                  end
                  local line = vim.api.nvim_win_get_cursor(0)[1]
                  if line ~= last_sent_line then
                    last_sent_line = line
                    sync_preview_cursor(client, bufnr)
                  end
                end)
              )
            end,
          })
          vim.api.nvim_create_autocmd("BufWipeout", {
            group = scroll_group,
            buffer = bufnr,
            callback = function()
              if timer and not timer:is_closing() then
                timer:stop()
                timer:close()
              end
            end,
          })
        end,
      },
    },
  },
}
