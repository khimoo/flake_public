return {
  {
    "mfussenegger/nvim-dap",
    dependencies = { "theHamsta/nvim-dap-virtual-text" },
    config = function()
      local dap = require('dap')

      -- Keymaps
      vim.keymap.set('n', '<leader>dc', dap.continue, { desc = 'DAP: Continue' })
      vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'DAP: Toggle breakpoint' })
      vim.keymap.set('n', '<leader>do', dap.step_over, { desc = 'DAP: Step over' })
      vim.keymap.set('n', '<leader>di', dap.step_into, { desc = 'DAP: Step into' })
      vim.keymap.set('n', '<leader>dO', dap.step_out, { desc = 'DAP: Step out' })
      vim.keymap.set('n', '<leader>dr', dap.repl.open, { desc = 'DAP: REPL' })

      -- dap-view auto open (close は手動で行う)
      dap.listeners.after.event_initialized["dapview_autoopen"] = function()
        local ok, dv = pcall(require, 'dap-view')
        if ok then dv.open() end
      end

      -- Python adapter
      dap.adapters.python = function(cb, config)
        if config.request == 'attach' then
          ---@diagnostic disable-next-line: undefined-field
          local port = (config.connect or config).port
          ---@diagnostic disable-next-line: undefined-field
          local host = (config.connect or config).host or '127.0.0.1'
          cb({
            type = 'server',
            port = assert(port, '`connect.port` is required for a python `attach` configuration'),
            host = host,
            options = { source_filetype = 'python' },
          })
        else
          cb({
            type = 'executable',
            command = 'python',
            args = { '-m', 'debugpy.adapter' },
            options = { source_filetype = 'python' },
          })
        end
      end

      dap.configurations.python = { {
        type = 'python',
        request = 'launch',
        name = "Launch file",
        program = "${file}",
        pythonPath = function()
          local cwd = vim.fn.getcwd()
          if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
            return cwd .. '/venv/bin/python'
          elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
            return cwd .. '/.venv/bin/python'
          else
            return '/usr/bin/python'
          end
        end,
      } }
    end
  },
  {
    "leoluz/nvim-dap-go",
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {},
  },
  {
    "igorlfs/nvim-dap-view",
    ---@module 'dap-view'
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
