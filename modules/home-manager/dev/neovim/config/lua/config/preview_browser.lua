-- プレビュー URL を枠なしの独立ウィンドウ（--app）で開く共通ヘルパー。
-- 拡張機能を入れていない素の Google Chrome を優先し、無ければ Brave、
-- どちらも無い環境（WSL 等）では Neovim 標準の vim.ui.open にフォールバックする。

local M = {}

local APP_BROWSERS = {
  "google-chrome-stable",
  "google-chrome",
  "brave",
}

---@param url string
function M.open(url)
  for _, bin in ipairs(APP_BROWSERS) do
    if vim.fn.executable(bin) == 1 then
      vim.system({ bin, "--app=" .. url }, { detach = true })
      return
    end
  end

  vim.ui.open(url)
end

return M
