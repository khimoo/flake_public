local M = {}

function M.setup(dap)
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
      for _, venv in ipairs({ '/venv/bin/python', '/.venv/bin/python' }) do
        if vim.fn.executable(cwd .. venv) == 1 then
          return cwd .. venv
        end
      end
      return '/usr/bin/python'
    end,
  } }
end

return M
