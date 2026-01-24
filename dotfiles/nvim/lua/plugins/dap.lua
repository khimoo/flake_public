return {
  {
    "mfussenegger/nvim-dap",
    dependencies = { "theHamsta/nvim-dap-virtual-text" },
    config = function()
      local dap = require('dap')
      dap.adapters = {
        codelldb = { type = "executable", command = tostring(os.getenv("CODELLDB_PATH") or "") },
        python = function(cb, config)
          if config.request == 'attach' then
            ---@diagnostic disable-next-line: undefined-field
            local port = (config.connect or config).port
            ---@diagnostic disable-next-line: undefined-field
            local host = (config.connect or config).host or '127.0.0.1'
            cb({
              type = 'server',
              port = assert(port, '`connect.port` is required for a python `attach` configuration'),
              host = host,
              options = {
                source_filetype = 'python',
              },
            })
          else
            cb({
              type = 'executable',
              command = 'python',
              args = { '-m', 'debugpy.adapter' },
              options = {
                source_filetype = 'python',
              },
            })
          end
        end
      }
      dap.configurations = {
        python = { {
          -- The first three options are required by nvim-dap
          type = 'python', -- the type here established the link to the adapter definition: `dap.adapters.python`
          request = 'launch',
          name = "Launch file",

          -- Options below are for debugpy, see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options

          program = "${file}", -- This configuration will launch the current file if used.
          pythonPath = function()
            -- debugpy supports launching an application with a different interpreter then the one used to launch debugpy itself.
            -- The code below looks for a `venv` or `.venv` folder in the current directly and uses the python within.
            -- You could adapt this - to for example use the `VIRTUAL_ENV` environment variable.
            local cwd = vim.fn.getcwd()
            if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
              return cwd .. '/venv/bin/python'
            elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
              return cwd .. '/.venv/bin/python'
            else
              return '/usr/bin/python'
            end
          end,
        } },
        rust = { {
          name = "Launch file",
          type = "codelldb",
          request = "launch",
          program = function()
            local cwd = vim.fn.getcwd() .. '/'
            local file = vim.fn.expand('%:p')
            print(cwd)
            print(file)

            if not file:match('%.rs$') then
              print("not rs")
              return vim.fn.input('Path to executable: ', cwd, 'file')
            end

            -- Determine project root as parent directory of the script's directory.
            -- Example: /.../rust-toybox/scripts/foo.rs -> project = /.../rust-toybox/scripts
            local project_dir = vim.fn.fnamemodify(file, ':h')
            local name = vim.fn.fnamemodify(file, ':t:r')
            local candidate = project_dir .. '/debug/' .. name

            -- If binary already exists, return it.
            if vim.fn.filereadable(candidate) == 1 then
              return candidate
            end

            -- Try to build non-interactively by setting CARGO_TARGET_DIR to project_dir.
            -- Redirect stdin from /dev/null so scripts that expect input won't block.
            local build_cmd = 'CARGO_TARGET_DIR=' .. vim.fn.shellescape(project_dir)
                .. ' cargo -Z script ' .. vim.fn.shellescape(file)

            -- Run synchronously; this should complete quickly for most scripts (compilation only).
            print("このコマンドを実行してください", build_cmd)

            --[[ -- Fallbacks: try CARGO_HOME build locations and local target/debug as before.
                  print("fallback")
                  local cargo_home = os.getenv('CARGO_HOME') or (os.getenv('HOME') .. '/.cargo')
                  local pattern = cargo_home .. '/build/**/target/**/' .. name
                  local candidates = vim.fn.glob(pattern, 0, 1)
                  for _, c in ipairs(candidates) do
                    if vim.fn.filereadable(c) == 1 then return c end
                  end

                  local localDebug = project_dir .. '/debug/' .. name
                  if vim.fn.filereadable(localDebug) == 1 then return localDebug end

                  return vim.fn.input('Path to executable: ', cwd, 'file') ]]
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
        } },
      }
    end
  },
  --[[ {
        "rcarriga/nvim-dap-ui",
        dependencies = {"mfussenegger/nvim-dap", "nvim-neotest/nvim-nio"},
        opts = {},
    }, ]]
  {
    "igorlfs/nvim-dap-view",
    ---@module 'dap-view'
    ---@type dapview.Config
    opts = {
      winbar = {
        controls = { enabled = true },
        sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl", "console" },
      }
    },
  },
}
