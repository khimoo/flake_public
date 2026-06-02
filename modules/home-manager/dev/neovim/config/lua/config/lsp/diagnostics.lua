local M = {}

function M.setup()
  vim.diagnostic.config({
    underline = true,
    virtual_text = false,
    signs = true,
    severity_sort = true,
    update_in_insert = true,
  })

  vim.o.updatetime = 250

  vim.api.nvim_create_autocmd("CursorHold", {
    pattern = "*",
    callback = function()
      vim.diagnostic.open_float({
        focus = false,
        source = true,
      })
    end,
  })
end

return M
