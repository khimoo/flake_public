-- tinymist の override。plugins/lsp/init.lua の opts.servers に deep-merge される。
local main_file = require("plugins.lang.typst.main_file")

local group = vim.api.nvim_create_augroup("TypstPinMain", { clear = true })

-- pin はサーバー全体の状態なので、直前に pin したものを覚えて無駄な往復を省く。
-- サーバーが再起動すると pin は失われるため、client ごとに記録する。
---@type table<integer, string>
local pinned = {}

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

return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      tinymist = {
        settings = {
          -- 出力先は既定 ($dir/$name) のままにして .typ の隣に PDF を置く。
          -- tdf が同じパスを開いたまま hot reload する運用のため。
          exportPdf = "onType",
        },
        on_attach = function(client, bufnr)
          pin_main(client, bufnr)

          -- 別の文書に移ったら pin し直す。
          vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
          vim.api.nvim_create_autocmd("BufEnter", {
            group = group,
            buffer = bufnr,
            callback = function()
              pin_main(client, bufnr)
            end,
          })
        end,
      },
    },
  },
}
