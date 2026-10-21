return {
  {
    "mfussenegger/nvim-dap",
    dependencies = { "theHamsta/nvim-dap-virtual-text" },
    config = function()
      local dap = require('dap')

      -- キーマップ
      vim.keymap.set('n', '<leader>dc', dap.continue, { desc = 'DAP: Continue' })
      vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'DAP: Toggle breakpoint' })
      vim.keymap.set('n', '<leader>do', dap.step_over, { desc = 'DAP: Step over' })
      vim.keymap.set('n', '<leader>di', dap.step_into, { desc = 'DAP: Step into' })
      vim.keymap.set('n', '<leader>dO', dap.step_out, { desc = 'DAP: Step out' })
      vim.keymap.set('n', '<leader>dr', dap.repl.open, { desc = 'DAP: REPL' })

      -- dap-view 自動open (close は手動で行う)
      dap.listeners.after.event_initialized["dapview_autoopen"] = function()
        local ok, dv = pcall(require, 'dap-view')
        if ok then dv.open() end
      end

      -- 言語固有のアダプター設定
      require("config.dap.python").setup(dap)
    end,
  },
  {
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
  },
}
