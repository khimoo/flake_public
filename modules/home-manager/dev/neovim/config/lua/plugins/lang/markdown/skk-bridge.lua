-- skkeleton ↔ autolist 連携の橋渡し。
--
-- 背景:
--   autolist は insert-mode の <CR> を <CR><cmd>AutolistNewBullet<cr> にマップして
--   箇条書きを自動継続する。しかし skkeleton が有効な間は <CR> を skkeleton 自身が
--   横取りし、上記マップが発火しない。結果、SKK で日本語入力中に Enter を押しても
--   bullet が挿入されない。
--
-- 仕組み:
--   skkeleton-handled イベント (skkeleton が 1 キーを処理した直後) で、バッファの
--   行数が増えていれば「改行が挿入された」と判定して AutolistNewBullet を呼ぶ。
--   変換確定時の <CR> (eggLikeNewline=true により改行を伴わない) では行数が
--   変わらないため、誤発火しない。
--
-- 配置の意図:
--   この橋渡しを skkeleton.lua 側に置くと skkeleton が autolist の存在を知ることになり
--   結合度が上がる。markdown ft 固有の連携なので markdown モジュールが責務を持つ。
local M = {}

local function snapshot()
  vim.b.skk_bridge_prev_lc = vim.api.nvim_buf_line_count(0)
end

function M.setup()
  local augroup = vim.api.nvim_create_augroup("skkeleton_autolist_bridge", { clear = true })

  -- skk 有効化時点のベースラインを記録 (markdown バッファのみ)
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "skkeleton-enable-post",
    callback = function()
      if vim.bo.filetype == "markdown" then snapshot() end
    end,
  })

  -- 1 キー処理後の行数増加を検知して bullet を補う
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "skkeleton-handled",
    callback = function()
      if vim.bo.filetype ~= "markdown" then return end
      local prev = vim.b.skk_bridge_prev_lc
      local cur = vim.api.nvim_buf_line_count(0)
      if prev and cur > prev then
        vim.cmd("AutolistNewBullet")
      end
      vim.b.skk_bridge_prev_lc = cur
    end,
  })
end

return M
