local rustowl = require("config.nix").data.rustowl

return {
  name = 'rustowl',
  dir = rustowl.plugin,
  ft = 'rust',
  opts = {
    client = { cmd = { rustowl.command } },
    auto_attach = true,
    auto_enable = false,
    idle_time = 500,
  },
  keys = {
    { '<leader>lo', '<cmd>Rustowl toggle<cr>', desc = 'RustOwl toggle' },
  },
  config = function(_, opts)
    require('rustowl').setup(opts)
    require('plugins.lang.rustowl-hover').setup()
  end,
}
