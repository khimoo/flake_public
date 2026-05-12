local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
      local buf = ev.buf
      local prefix = "<leader>l"

      local function bmap(mode, lhs, func, desc)
        vim.keymap.set(mode, lhs, func, { buffer = buf, desc = "LSP: " .. desc })
      end

      -- 頻出操作: プレフィックスなし (デファクトスタンダード)
      bmap("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
      bmap("n", "gd", vim.lsp.buf.definition, "Go to definition")
      bmap("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
      -- gr* は Neovim 0.11+ のデフォルト (grr=references, grn=rename, gra=code_action)
      bmap("n", "K", vim.lsp.buf.hover, "Hover documentation")
      bmap("n", "<C-s>", vim.lsp.buf.signature_help, "Signature help")
      bmap("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
      bmap("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")

      -- 低頻度操作: <leader>l プレフィックス付き
      local function nmap(suffix, func, desc)
        vim.keymap.set("n", prefix .. suffix, func, { buffer = buf, desc = "LSP: " .. desc })
      end
      local function vmap(suffix, func, desc)
        vim.keymap.set("v", prefix .. suffix, func, { buffer = buf, desc = "LSP: " .. desc })
      end

      nmap("wa", vim.lsp.buf.add_workspace_folder, "Add workspace folder")
      nmap("wr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
      nmap("wl", function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, "List workspace folders")

      nmap("D", vim.lsp.buf.type_definition, "Go to type definition")
      nmap("rn", vim.lsp.buf.rename, "Rename symbol")
      nmap("ca", vim.lsp.buf.code_action, "Code action")
      nmap("F", function() vim.lsp.buf.format({ bufnr = buf, async = true }) end, "Format buffer")

      vmap("ca", vim.lsp.buf.range_code_action or vim.lsp.buf.code_action, "Range code action")

      nmap("dl", vim.diagnostic.open_float, "Open diagnostic float")

      if pcall(require, "which-key") then
        local wk = require("which-key")
        wk.add({
          { prefix, buffer = buf, group = "LSP" },
          { prefix .. "w", buffer = buf, group = "Workspace" },
          { prefix .. "r", buffer = buf, group = "Rename/References" },
          { prefix .. "c", buffer = buf, group = "Code Action" },
        })
      end
    end,
  })
end

return M
