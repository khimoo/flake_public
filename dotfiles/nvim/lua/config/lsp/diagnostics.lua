local M = {}

function M.setup()
  vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics,
    {
      underline = true,
      virtual_text = false,
      signs = true,
      severity_sort = true,
      update_in_insert = true,
    }
  )

  vim.o.updatetime = 250

  vim.api.nvim_create_autocmd("CursorHold", {
    pattern = "*",
    callback = function()
      vim.diagnostic.open_float(nil, {
        focus = false,
        source = "always",
      })
    end,
  })
end

return M
