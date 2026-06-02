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
  require("plugins.dap.view"),
}
