return {
  "igorlfs/nvim-dap-view",
  ---@module 'dap-view'
  ---@diagnostic disable-next-line: undefined-doc-name
  ---@type dapview.Config
  opts = {
    winbar = {
      controls = {
        enabled = true,
        buttons = { "rust_debug", "play", "step_into", "step_over", "step_out", "step_back", "run_last", "terminate", "disconnect" },
        custom_buttons = {
          rust_debug = {
            render = function()
              local statusline = require("dap-view.util.statusline")
              local has_rust = vim.iter(vim.api.nvim_list_bufs()):any(function(buf)
                return vim.bo[buf].filetype == "rust"
              end)
              if not has_rust then
                return ""
              end
              return statusline.hl("\u{ebc0}", "ControlRunLast")
            end,
            action = function()
              vim.cmd("RustLsp debuggables")
            end,
          },
        },
      },
      sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl", "console" },
    },
  },
}
